#include "starfall/sim/world.hpp"

#include <algorithm>
#include <limits>
#include <stdexcept>
#include <type_traits>

namespace starfall::sim {
namespace {

[[nodiscard]] std::size_t checked_product(std::uint32_t left,
                                          std::uint32_t right,
                                          const char* message) {
    const auto max = std::numeric_limits<std::size_t>::max();
    if (right != 0 && static_cast<std::size_t>(left) > max / static_cast<std::size_t>(right)) {
        throw std::invalid_argument(message);
    }
    return static_cast<std::size_t>(left) * static_cast<std::size_t>(right);
}

[[nodiscard]] std::uint32_t ceil_div(std::uint32_t value, std::uint32_t divisor) noexcept {
    return value / divisor + (value % divisor == 0 ? 0U : 1U);
}

[[nodiscard]] std::uint64_t absolute_distance(std::int64_t value,
                                              std::uint32_t coordinate) noexcept {
    const auto coordinate64 = static_cast<std::int64_t>(coordinate);
    if (value >= coordinate64) {
        return static_cast<std::uint64_t>(value) - static_cast<std::uint64_t>(coordinate64);
    }
    return static_cast<std::uint64_t>(coordinate64) - static_cast<std::uint64_t>(value);
}

[[nodiscard]] bool is_inside_circle(std::uint32_t x,
                                    std::uint32_t y,
                                    std::int64_t center_x,
                                    std::int64_t center_y,
                                    std::uint32_t radius) noexcept {
    const auto dx = absolute_distance(center_x, x);
    const auto dy = absolute_distance(center_y, y);
    if (dx > radius || dy > radius) {
        return false;
    }
    const auto radius_squared = static_cast<std::uint64_t>(radius) * radius;
    const auto dx_squared = dx * dx;
    return dy * dy <= radius_squared - dx_squared;
}

struct ClippedBounds final {
    std::uint32_t min_x = 0;
    std::uint32_t max_x = 0;
    std::uint32_t min_y = 0;
    std::uint32_t max_y = 0;
    bool empty = true;
};

[[nodiscard]] ClippedBounds clipped_circle_bounds(std::uint32_t width,
                                                  std::uint32_t height,
                                                  std::int64_t center_x,
                                                  std::int64_t center_y,
                                                  std::uint32_t radius) noexcept {
    const auto radius64 = static_cast<std::int64_t>(radius);
    const auto world_max_x = static_cast<std::int64_t>(width) - 1;
    const auto world_max_y = static_cast<std::int64_t>(height) - 1;

    if (center_x < -radius64 || center_y < -radius64
        || center_x > world_max_x + radius64 || center_y > world_max_y + radius64) {
        return {};
    }

    const auto min_x = center_x <= radius64 ? 0 : center_x - radius64;
    const auto min_y = center_y <= radius64 ? 0 : center_y - radius64;
    const auto max_x = center_x >= world_max_x - radius64 ? world_max_x : center_x + radius64;
    const auto max_y = center_y >= world_max_y - radius64 ? world_max_y : center_y + radius64;
    if (min_x > max_x || min_y > max_y) {
        return {};
    }
    return {
        static_cast<std::uint32_t>(min_x),
        static_cast<std::uint32_t>(max_x),
        static_cast<std::uint32_t>(min_y),
        static_cast<std::uint32_t>(max_y),
        false,
    };
}

void hash_byte(std::uint64_t& hash, std::uint8_t value) noexcept {
    hash ^= value;
    hash *= 1099511628211ULL;
}

template <typename Integer>
void hash_integer(std::uint64_t& hash, Integer value) noexcept {
    using Unsigned = std::make_unsigned_t<Integer>;
    auto remaining = static_cast<Unsigned>(value);
    for (std::size_t byte = 0; byte < sizeof(Integer); ++byte) {
        hash_byte(hash, static_cast<std::uint8_t>(remaining & 0xffU));
        remaining >>= 8U;
    }
}

} // namespace

World::World(SimulationConfig config)
    : config_(config), random_state_(config.seed) {
    if (config_.ticks_per_second == 0) {
        throw std::invalid_argument("ticks_per_second must be greater than zero");
    }
    if (config_.width == 0 || config_.height == 0) {
        throw std::invalid_argument("world width and height must be greater than zero");
    }
    if (config_.chunk_size != material_chunk_size) {
        throw std::invalid_argument("material transport chunks must be exactly 64 by 64");
    }
    if (!is_valid_material(config_.initial_material)) {
        throw std::invalid_argument("initial_material is outside the transport material range");
    }

    const auto cell_count = checked_product(config_.width, config_.height,
                                            "world dimensions overflow addressable storage");
    if (cell_count > cells_.max_size()) {
        throw std::invalid_argument("world dimensions exceed contiguous cell storage limits");
    }
    chunk_columns_ = ceil_div(config_.width, config_.chunk_size);
    chunk_rows_ = ceil_div(config_.height, config_.chunk_size);
    const auto chunk_count = checked_product(chunk_columns_, chunk_rows_,
                                             "chunk dimensions overflow addressable storage");
    if (chunk_count > dirty_chunks_.max_size()) {
        throw std::invalid_argument("chunk dimensions exceed dirty storage limits");
    }
    cells_.assign(cell_count, static_cast<std::uint8_t>(config_.initial_material));
    moved_cells_.assign(cell_count, 0);
    dirty_chunks_.assign(chunk_count, false);
}

void World::step() noexcept {
    ++tick_;
    simulate_powder();
}

std::uint32_t World::next_random_u32() noexcept {
    // Match the 32-bit unsigned LCG used by the GDScript reference model.
    const auto state = static_cast<std::uint32_t>(random_state_);
    const auto next = state * 1664525U + 1013904223U;
    random_state_ = next;
    return next;
}

void World::simulate_powder() noexcept {
    std::fill(moved_cells_.begin(), moved_cells_.end(), 0);
    if (cells_.empty()) {
        return;
    }

    // A seed-derived rotation of canonical row-major order is still a fixed
    // order for a given seed/tick and avoids unordered or chunk-dependent work.
    const auto start = static_cast<std::size_t>(next_random_u32()) % cells_.size();
    for (std::size_t offset = 0; offset < cells_.size(); ++offset) {
        const auto index = (start + offset) % cells_.size();
        if (moved_cells_[index] != 0
            || cells_[index] != static_cast<std::uint8_t>(Material::sand)) {
            continue;
        }

        const auto preferred_side = (next_random_u32() & 1U) == 0U ? 1 : -1;
        const auto x = static_cast<std::int64_t>(index % config_.width);
        const auto y = static_cast<std::int64_t>(index / config_.width);
        const std::int64_t candidates[5][2]{
            {0, 1},
            {preferred_side, 1},
            {-preferred_side, 1},
            {preferred_side, 0},
            {-preferred_side, 0},
        };

        for (const auto& candidate : candidates) {
            const auto target_x = x + candidate[0];
            const auto target_y = y + candidate[1];
            if (target_x < 0 || target_y < 0
                || target_x >= static_cast<std::int64_t>(config_.width)
                || target_y >= static_cast<std::int64_t>(config_.height)) {
                continue;
            }

            const auto target_index = static_cast<std::size_t>(target_y)
                * config_.width + static_cast<std::size_t>(target_x);
            if (cells_[target_index] != static_cast<std::uint8_t>(Material::air)) {
                continue;
            }

            cells_[index] = static_cast<std::uint8_t>(Material::air);
            cells_[target_index] = static_cast<std::uint8_t>(Material::sand);
            moved_cells_[index] = 1;
            moved_cells_[target_index] = 1;
            dirty_chunks_[chunk_index(
                static_cast<std::uint32_t>(x) / config_.chunk_size,
                static_cast<std::uint32_t>(y) / config_.chunk_size)] = true;
            dirty_chunks_[chunk_index(
                static_cast<std::uint32_t>(target_x) / config_.chunk_size,
                static_cast<std::uint32_t>(target_y) / config_.chunk_size)] = true;
            break;
        }
    }
}

void World::validate_command_batch(const MaterialCommandBatchDto& batch) const {
    if (batch.version != material_transport_dto_version) {
        throw std::invalid_argument("unsupported material command DTO version");
    }
    for (const auto& command : batch.commands) {
        if (const auto* paint = std::get_if<PaintCircleCommand>(&command);
            paint != nullptr && !is_valid_material(paint->material)) {
            throw std::invalid_argument("paint material is outside the transport material range");
        }
    }
}

MaterialCommandResultBatchDto World::submit_command_batch(const MaterialCommandBatchDto& batch) {
    validate_command_batch(batch);

    MaterialCommandResultBatchDto output{
        .version = material_transport_dto_version,
        .tick = tick_,
        .results = {},
    };
    output.results.reserve(batch.commands.size());
    for (const auto& command : batch.commands) {
        if (const auto* paint = std::get_if<PaintCircleCommand>(&command)) {
            paint_circle(*paint);
            output.results.emplace_back(std::monostate{});
        } else {
            output.results.emplace_back(extract_circle(std::get<ExtractCircleCommand>(command)));
        }
    }
    return output;
}

DirtyChunkBatchDto World::consume_dirty_chunks() {
    DirtyChunkBatchDto batch{
        .version = material_transport_dto_version,
        .tick = tick_,
        .chunk_size = material_chunk_size,
        .chunks = {},
    };
    batch.chunks.reserve(dirty_chunks_.size());

    for (std::uint32_t chunk_y = 0; chunk_y < chunk_rows_; ++chunk_y) {
        for (std::uint32_t chunk_x = 0; chunk_x < chunk_columns_; ++chunk_x) {
            const auto dirty_index = chunk_index(chunk_x, chunk_y);
            if (!dirty_chunks_[dirty_index]) {
                continue;
            }

            const auto origin_x = chunk_x * config_.chunk_size;
            const auto origin_y = chunk_y * config_.chunk_size;
            const auto valid_width = std::min(config_.chunk_size, config_.width - origin_x);
            const auto valid_height = std::min(config_.chunk_size, config_.height - origin_y);
            DirtyChunkSnapshot snapshot{chunk_x, chunk_y, valid_width, valid_height, {}};
            snapshot.cells.reserve(checked_product(valid_width, valid_height,
                                                   "dirty chunk dimensions overflow"));
            for (std::uint32_t row = 0; row < valid_height; ++row) {
                const auto first = cells_.begin() + static_cast<std::ptrdiff_t>(
                    cell_index(origin_x, origin_y + row));
                snapshot.cells.insert(snapshot.cells.end(), first,
                                      first + static_cast<std::ptrdiff_t>(valid_width));
            }
            batch.chunks.push_back(std::move(snapshot));
        }
    }

    std::fill(dirty_chunks_.begin(), dirty_chunks_.end(), false);
    return batch;
}

WorldSnapshot World::snapshot() const {
    return {
        material_transport_dto_version,
        config_,
        tick_,
        random_state_,
        cells_,
    };
}

std::uint64_t World::checksum() const noexcept {
    std::uint64_t hash = 14695981039346656037ULL;
    hash_integer(hash, material_transport_dto_version);
    hash_integer(hash, config_.ticks_per_second);
    hash_integer(hash, config_.width);
    hash_integer(hash, config_.height);
    hash_integer(hash, config_.chunk_size);
    hash_integer(hash, config_.seed);
    hash_byte(hash, static_cast<std::uint8_t>(config_.initial_material));
    hash_integer(hash, tick_);
    hash_integer(hash, random_state_);
    for (const auto cell : cells_) {
        hash_byte(hash, cell);
    }
    return hash;
}

Material World::material_at(std::uint32_t x, std::uint32_t y) const {
    if (x >= config_.width || y >= config_.height) {
        throw std::out_of_range("material coordinates are outside the world");
    }
    return static_cast<Material>(cells_[cell_index(x, y)]);
}

const SimulationConfig& World::config() const noexcept {
    return config_;
}

std::uint64_t World::tick() const noexcept {
    return tick_;
}

std::uint64_t World::random_state() const noexcept {
    return random_state_;
}

std::uint32_t World::chunk_columns() const noexcept {
    return chunk_columns_;
}

std::uint32_t World::chunk_rows() const noexcept {
    return chunk_rows_;
}

std::span<const std::uint8_t> World::cells() const noexcept {
    return cells_;
}

std::size_t World::cell_index(std::uint32_t x, std::uint32_t y) const noexcept {
    return static_cast<std::size_t>(y) * config_.width + x;
}

std::size_t World::chunk_index(std::uint32_t chunk_x, std::uint32_t chunk_y) const noexcept {
    return static_cast<std::size_t>(chunk_y) * chunk_columns_ + chunk_x;
}

void World::set_material(std::uint32_t x, std::uint32_t y, Material material) {
    const auto index = cell_index(x, y);
    const auto encoded = static_cast<std::uint8_t>(material);
    if (cells_[index] == encoded) {
        return;
    }
    cells_[index] = encoded;
    dirty_chunks_[chunk_index(x / config_.chunk_size, y / config_.chunk_size)] = true;
}

void World::paint_circle(const PaintCircleCommand& command) {
    const auto bounds = clipped_circle_bounds(config_.width, config_.height,
                                              command.center_x, command.center_y,
                                              command.radius);
    if (bounds.empty) {
        return;
    }
    for (auto y = bounds.min_y; y <= bounds.max_y; ++y) {
        for (auto x = bounds.min_x; x <= bounds.max_x; ++x) {
            if (is_inside_circle(x, y, command.center_x, command.center_y, command.radius)) {
                set_material(x, y, command.material);
            }
        }
    }
}

ExtractionStats World::extract_circle(const ExtractCircleCommand& command) {
    ExtractionStats result;
    const auto bounds = clipped_circle_bounds(config_.width, config_.height,
                                              command.center_x, command.center_y,
                                              command.radius);
    if (bounds.empty) {
        return result;
    }
    for (auto y = bounds.min_y; y <= bounds.max_y; ++y) {
        for (auto x = bounds.min_x; x <= bounds.max_x; ++x) {
            if (!is_inside_circle(x, y, command.center_x, command.center_y, command.radius)) {
                continue;
            }
            const auto material = material_at(x, y);
            switch (material) {
            case Material::rock:
                ++result.rock;
                break;
            case Material::sand:
                ++result.sand;
                break;
            case Material::metal:
                ++result.metal;
                break;
            default:
                continue;
            }
            ++result.total;
            set_material(x, y, Material::air);
        }
    }
    return result;
}

} // namespace starfall::sim
