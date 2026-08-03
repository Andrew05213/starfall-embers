#include "starfall/sim/world.hpp"

#include <cstdint>
#include <cstdlib>
#include <exception>
#include <iostream>
#include <limits>
#include <stdexcept>
#include <string_view>
#include <type_traits>
#include <vector>

namespace {

using starfall::sim::ExtractCircleCommand;
using starfall::sim::ExtractionStats;
using starfall::sim::Material;
using starfall::sim::MaterialCommand;
using starfall::sim::MaterialCommandBatchDto;
using starfall::sim::PaintCircleCommand;
using starfall::sim::SimulationConfig;
using starfall::sim::World;
using starfall::sim::material_chunk_size;
using starfall::sim::material_transport_dto_version;

static_assert(static_cast<std::uint8_t>(Material::air) == 0);
static_assert(static_cast<std::uint8_t>(Material::rock) == 1);
static_assert(static_cast<std::uint8_t>(Material::sand) == 2);
static_assert(static_cast<std::uint8_t>(Material::water) == 3);
static_assert(static_cast<std::uint8_t>(Material::oil) == 4);
static_assert(static_cast<std::uint8_t>(Material::fire) == 5);
static_assert(static_cast<std::uint8_t>(Material::smoke) == 6);
static_assert(static_cast<std::uint8_t>(Material::lava) == 7);
static_assert(static_cast<std::uint8_t>(Material::steam) == 8);
static_assert(static_cast<std::uint8_t>(Material::metal) == 9);
static_assert(std::is_same_v<std::underlying_type_t<Material>, std::uint8_t>);
static_assert(material_chunk_size == 64);
static_assert(material_transport_dto_version == 1);

[[noreturn]] void fail(std::string_view message) {
    std::cerr << "world unit test failed: " << message << '\n';
    std::exit(1);
}

void require(bool condition, std::string_view message) {
    if (!condition) {
        fail(message);
    }
}

template <typename Exception, typename Callable>
void require_throws(Callable&& callable, std::string_view message) {
    try {
        callable();
    } catch (const Exception&) {
        return;
    } catch (...) {
        fail(message);
    }
    fail(message);
}

starfall::sim::MaterialCommandResultBatchDto submit(
    World& world,
    std::initializer_list<MaterialCommand> commands
) {
    MaterialCommandBatchDto batch;
    batch.commands.assign(commands.begin(), commands.end());
    return world.submit_command_batch(batch);
}

std::uint32_t next_powder_random(std::uint64_t& state) {
    const auto next = static_cast<std::uint32_t>(state) * 1664525U + 1013904223U;
    state = next;
    return next;
}

void simulate_powder_reference(std::vector<std::uint8_t>& cells,
                               std::uint32_t width,
                               std::uint32_t height,
                               std::uint64_t& random_state) {
    const auto air = static_cast<std::uint8_t>(Material::air);
    const auto sand = static_cast<std::uint8_t>(Material::sand);
    std::vector<std::uint8_t> moved(cells.size(), 0);
    const auto start = static_cast<std::size_t>(next_powder_random(random_state)) % cells.size();
    for (std::size_t offset = 0; offset < cells.size(); ++offset) {
        const auto index = (start + offset) % cells.size();
        if (moved[index] != 0 || cells[index] != sand) {
            continue;
        }

        const auto preferred_side = (next_powder_random(random_state) & 1U) == 0U ? 1 : -1;
        const auto x = static_cast<std::int64_t>(index % width);
        const auto y = static_cast<std::int64_t>(index / width);
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
                || target_x >= static_cast<std::int64_t>(width)
                || target_y >= static_cast<std::int64_t>(height)) {
                continue;
            }
            const auto target_index = static_cast<std::size_t>(target_y) * width
                + static_cast<std::size_t>(target_x);
            if (cells[target_index] != air) {
                continue;
            }
            cells[index] = air;
            cells[target_index] = sand;
            moved[index] = 1;
            moved[target_index] = 1;
            break;
        }
    }
}

void test_config_and_dto_validation() {
    require_throws<std::invalid_argument>(
        [] { World world({0, 1, 1, material_chunk_size, 0, Material::air}); },
        "zero tick rate must be rejected"
    );
    require_throws<std::invalid_argument>(
        [] { World world({30, 0, 1, material_chunk_size, 0, Material::air}); },
        "zero width must be rejected"
    );
    require_throws<std::invalid_argument>(
        [] { World world({30, 1, 0, material_chunk_size, 0, Material::air}); },
        "zero height must be rejected"
    );
    require_throws<std::invalid_argument>(
        [] { World world({30, 1, 1, 32, 0, Material::air}); },
        "non-64 chunk size must be rejected"
    );
    require_throws<std::invalid_argument>(
        [] { World world({30, 1, 1, material_chunk_size, 0, static_cast<Material>(10)}); },
        "invalid initial material must be rejected"
    );
    require_throws<std::invalid_argument>([] {
        const auto maximum = std::numeric_limits<std::uint32_t>::max();
        World world({30, maximum, maximum, material_chunk_size, 0, Material::air});
    }, "oversized dimensions must be rejected before allocation");

    World world({30, 3, 3, material_chunk_size, 7, Material::air});
    MaterialCommandBatchDto wrong_version{
        .version = material_transport_dto_version + 1,
        .commands = {PaintCircleCommand{1, 1, 0, Material::rock}},
    };
    require_throws<std::invalid_argument>(
        [&] { (void)world.submit_command_batch(wrong_version); },
        "unknown DTO version must be rejected"
    );
    require(world.material_at(1, 1) == Material::air,
            "rejected DTO version must not mutate the world");

    MaterialCommandBatchDto invalid_material{
        .version = material_transport_dto_version,
        .commands = {
            PaintCircleCommand{1, 1, 0, Material::rock},
            PaintCircleCommand{1, 1, 0, static_cast<Material>(255)},
        },
    };
    require_throws<std::invalid_argument>(
        [&] { (void)world.submit_command_batch(invalid_material); },
        "invalid material must reject the complete batch"
    );
    require(world.material_at(1, 1) == Material::air,
            "invalid batch must be validated before any mutation");
}

void test_storage_snapshot_and_tick() {
    World world;
    require(world.config().ticks_per_second == 30, "default tick rate mismatch");
    require(world.config().width == 160 && world.config().height == 90,
            "default dimensions mismatch");
    require(world.config().chunk_size == material_chunk_size, "chunk size mismatch");
    require(world.chunk_columns() == 3 && world.chunk_rows() == 2,
            "default chunk grid mismatch");
    require(world.cells().size() == 160U * 90U, "cell storage must be compact");
    require(world.consume_dirty_chunks().chunks.empty(),
            "fresh world must not report mutations");

    const auto initial_checksum = world.checksum();
    world.step();
    world.step();
    const auto snapshot = world.snapshot();
    auto expected_random_state = world.config().seed;
    (void)next_powder_random(expected_random_state);
    (void)next_powder_random(expected_random_state);
    require(world.tick() == 2, "fixed step must advance tick exactly once");
    require(world.checksum() != initial_checksum, "tick must affect checksum");
    require(snapshot.version == material_transport_dto_version,
            "snapshot must carry the DTO version");
    require(snapshot.tick == 2 && snapshot.random_state == expected_random_state,
            "snapshot must include tick and advanced explicit random state");
    require(snapshot.cells == std::vector<std::uint8_t>(world.cells().begin(), world.cells().end()),
            "snapshot must preserve compact row-major cells");
}

void test_circle_clipping_and_extraction() {
    World clipped({30, 4, 4, material_chunk_size, 11, Material::air});
    (void)submit(clipped, {PaintCircleCommand{0, 0, 1, Material::rock}});
    require(clipped.material_at(0, 0) == Material::rock
            && clipped.material_at(1, 0) == Material::rock
            && clipped.material_at(0, 1) == Material::rock,
            "boundary circle must retain in-bounds cells");
    require(clipped.material_at(1, 1) == Material::air,
            "circle geometry must exclude diagonal outside radius");

    const auto maximum_u32 = std::numeric_limits<std::uint32_t>::max();
    World extreme({30, 1, 1, material_chunk_size, 13, Material::air});
    (void)submit(extreme, {
        PaintCircleCommand{std::numeric_limits<std::int64_t>::min(), 0,
                           maximum_u32, Material::rock},
        PaintCircleCommand{std::numeric_limits<std::int64_t>::max(), 0,
                           maximum_u32, Material::rock},
    });
    require(extreme.material_at(0, 0) == Material::air,
            "extreme centers must clip without integer overflow");

    World world({30, 7, 7, material_chunk_size, 19, Material::air});
    const auto results = submit(world, {
        PaintCircleCommand{3, 3, 1, Material::rock},
        PaintCircleCommand{3, 3, 0, Material::metal},
        PaintCircleCommand{3, 2, 0, Material::sand},
        PaintCircleCommand{2, 3, 0, Material::water},
        ExtractCircleCommand{3, 3, 1},
    });
    require(results.results.size() == 5, "results must align with command order");
    require(std::holds_alternative<std::monostate>(results.results.front()),
            "paint result must be monostate");
    require(std::get<ExtractionStats>(results.results.back()) == ExtractionStats{4, 2, 1, 1},
            "extract must count only mineable materials");
    require(world.material_at(2, 3) == Material::water,
            "extract must preserve non-mineable materials");
}

void test_dirty_chunk_transport() {
    World world({30, 70, 65, material_chunk_size, 23, Material::air});
    (void)submit(world, {
        PaintCircleCommand{69, 64, 0, Material::metal},
        PaintCircleCommand{1, 1, 0, Material::rock},
        PaintCircleCommand{68, 2, 0, Material::sand},
        PaintCircleCommand{2, 2, 0, Material::rock},
    });
    world.step();
    const auto dirty = world.consume_dirty_chunks();
    require(dirty.version == material_transport_dto_version && dirty.tick == 1,
            "dirty batch must carry version and authoritative tick");
    require(dirty.chunk_size == 64 && dirty.chunks.size() == 3,
            "dirty batch must use fixed chunks without duplicates");
    require(dirty.chunks[0].chunk_x == 0 && dirty.chunks[0].chunk_y == 0
            && dirty.chunks[1].chunk_x == 1 && dirty.chunks[1].chunk_y == 0
            && dirty.chunks[2].chunk_x == 1 && dirty.chunks[2].chunk_y == 1,
            "dirty chunks must be stable row-major");
    require(dirty.chunks[0].width == 64 && dirty.chunks[0].height == 64
            && dirty.chunks[0].cells.size() == 4096,
            "full chunk payload mismatch");
    require(dirty.chunks[1].width == 6 && dirty.chunks[1].height == 64
            && dirty.chunks[1].cells.size() == 384,
            "right edge must be tightly packed");
    require(dirty.chunks[2].width == 6 && dirty.chunks[2].height == 1
            && dirty.chunks[2].cells.size() == 6,
            "corner edge must be tightly packed");
    require(dirty.chunks[2].cells[5] == static_cast<std::uint8_t>(Material::metal),
            "edge bytes must be local row-major data");
    require(world.consume_dirty_chunks().chunks.empty(),
            "draining must clear dirty flags");

    (void)submit(world, {PaintCircleCommand{69, 64, 0, Material::metal}});
    require(world.consume_dirty_chunks().chunks.empty(),
            "painting an existing value must not create false dirtiness");
}

void test_deterministic_replay() {
    const SimulationConfig config{30, 160, 90, material_chunk_size, 0xabcdefULL, Material::air};
    World first(config);
    World replay(config);
    const std::vector<MaterialCommandBatchDto> frames{
        {material_transport_dto_version, {
            PaintCircleCommand{80, 45, 8, Material::rock},
            PaintCircleCommand{80, 45, 2, Material::metal},
        }},
        {material_transport_dto_version, {
            ExtractCircleCommand{80, 45, 3},
            PaintCircleCommand{10, 10, 1, Material::sand},
        }},
        {material_transport_dto_version, {
            PaintCircleCommand{159, 89, 2, Material::water},
        }},
    };

    for (const auto& frame : frames) {
        const auto first_results = first.submit_command_batch(frame);
        const auto replay_results = replay.submit_command_batch(frame);
        first.step();
        replay.step();
        require(first_results.results == replay_results.results,
                "replay results must match frame by frame");
        require(first.random_state() == replay.random_state(),
                "same seed and commands must replay the random state");
        require(first.checksum() == replay.checksum(),
                "same seed, command order, and ticks must replay deterministically");
    }
    require(first.snapshot().cells == replay.snapshot().cells,
            "deterministic replay must reproduce the complete world");
}

void test_powder_movement_and_boundaries() {
    {
        World world({30, 5, 6, material_chunk_size, 1, Material::air});
        (void)submit(world, {PaintCircleCommand{2, 0, 0, Material::sand}});
        world.step();
        require(world.material_at(2, 0) == Material::air
                && world.material_at(2, 1) == Material::sand,
                "sand must fall vertically into air");
    }

    {
        World world({30, 5, 6, material_chunk_size, 2, Material::air});
        (void)submit(world, {
            PaintCircleCommand{0, 0, 0, Material::sand},
            PaintCircleCommand{0, 1, 0, Material::rock},
            PaintCircleCommand{0, 2, 0, Material::rock},
        });
        world.step();
        require(world.material_at(0, 0) == Material::air
                && world.material_at(1, 1) == Material::sand,
                "sand must use the only available down-diagonal at the left boundary");
    }

    {
        World world({30, 5, 6, material_chunk_size, 3, Material::air});
        (void)submit(world, {
            PaintCircleCommand{2, 2, 0, Material::sand},
            PaintCircleCommand{2, 3, 0, Material::rock},
            PaintCircleCommand{1, 3, 0, Material::rock},
            PaintCircleCommand{3, 3, 0, Material::rock},
            PaintCircleCommand{3, 2, 0, Material::metal},
        });
        world.step();
        require(world.material_at(2, 2) == Material::air
                && world.material_at(1, 2) == Material::sand,
                "sand must spread horizontally only after vertical candidates fail");
    }

    {
        World world({30, 5, 6, material_chunk_size, 4, Material::air});
        (void)submit(world, {
            PaintCircleCommand{2, 2, 0, Material::sand},
            PaintCircleCommand{2, 3, 0, Material::rock},
            PaintCircleCommand{1, 3, 0, Material::rock},
            PaintCircleCommand{3, 3, 0, Material::rock},
            PaintCircleCommand{1, 2, 0, Material::rock},
            PaintCircleCommand{3, 2, 0, Material::metal},
        });
        world.step();
        require(world.material_at(2, 2) == Material::sand,
                "sand must remain still when every candidate is blocked");
    }

    {
        World world({30, 5, 6, material_chunk_size, 5, Material::air});
        (void)submit(world, {
            PaintCircleCommand{2, 4, 0, Material::sand},
            PaintCircleCommand{2, 5, 0, Material::water},
            PaintCircleCommand{1, 5, 0, Material::rock},
            PaintCircleCommand{3, 5, 0, Material::metal},
            PaintCircleCommand{1, 4, 0, Material::rock},
            PaintCircleCommand{3, 4, 0, Material::rock},
        });
        world.step();
        require(world.material_at(2, 4) == Material::sand
                && world.material_at(2, 5) == Material::water,
                "sand must not enter or displace a non-air material at a boundary");
    }

    {
        World world({30, 8, 3, material_chunk_size, 6, Material::air});
        const std::vector<Material> static_materials{
            Material::rock, Material::water, Material::oil, Material::fire,
            Material::smoke, Material::lava, Material::steam, Material::metal,
        };
        for (std::size_t x = 0; x < static_materials.size(); ++x) {
            (void)submit(world, {PaintCircleCommand{
                static_cast<std::int64_t>(x), 1, 0, static_materials[x],
            }});
        }
        world.step();
        for (std::size_t x = 0; x < static_materials.size(); ++x) {
            require(world.material_at(static_cast<std::uint32_t>(x), 1)
                        == static_materials[x],
                    "non-migrated materials must remain static during powder steps");
        }
    }

    {
        World world({30, 5, 7, material_chunk_size, 6, Material::air});
        (void)submit(world, {
            PaintCircleCommand{2, 0, 0, Material::sand},
            PaintCircleCommand{2, 2, 0, Material::sand},
            PaintCircleCommand{2, 4, 0, Material::sand},
        });
        world.step();
        require(world.material_at(2, 0) == Material::air
                && world.material_at(2, 1) == Material::sand
                && world.material_at(2, 2) == Material::air
                && world.material_at(2, 3) == Material::sand
                && world.material_at(2, 4) == Material::air
                && world.material_at(2, 5) == Material::sand
                && world.material_at(2, 6) == Material::air,
                "a sand cell must move at most once per tick");
    }
}

void test_powder_cross_chunk_dirty_transport() {
    World world({30, 130, 130, material_chunk_size, 7, Material::air});
    (void)submit(world, {
        PaintCircleCommand{63, 62, 0, Material::sand},
        PaintCircleCommand{63, 63, 0, Material::rock},
        PaintCircleCommand{62, 63, 0, Material::rock},
        PaintCircleCommand{62, 63, 0, Material::sand},
    });
    (void)world.consume_dirty_chunks();
    world.step();
    const auto dirty = world.consume_dirty_chunks();
    require(world.material_at(63, 62) == Material::air
            && world.material_at(64, 63) == Material::sand,
            "powder must cross the x=63/64 chunk boundary");
    require(world.material_at(62, 63) == Material::air
            && world.material_at(62, 64) == Material::sand,
            "powder must cross the y=63/64 chunk boundary");
    require(dirty.chunks.size() == 3
            && dirty.chunks[0].chunk_x == 0 && dirty.chunks[0].chunk_y == 0
            && dirty.chunks[1].chunk_x == 1 && dirty.chunks[1].chunk_y == 0
            && dirty.chunks[2].chunk_x == 0 && dirty.chunks[2].chunk_y == 1,
            "powder movement must report stable row-major cross-chunk dirtiness");
}

void test_powder_seed_divergence() {
    const auto run = [](std::uint64_t seed) {
        World world({30, 5, 5, material_chunk_size, seed, Material::air});
        (void)submit(world, {
            PaintCircleCommand{2, 1, 0, Material::sand},
            PaintCircleCommand{2, 2, 0, Material::rock},
        });
        world.step();
        return std::vector<std::uint8_t>(world.cells().begin(), world.cells().end());
    };
    const auto first = run(1);
    const auto second = run(2);
    require(first != second, "different seeds must choose different symmetric powder branches");
}

void test_randomized_reference_model() {
    constexpr std::uint32_t width = 70;
    constexpr std::uint32_t height = 65;
    World world({30, width, height, material_chunk_size, 0x12345678ULL, Material::air});
    std::vector<std::uint8_t> reference(width * height, 0);
    std::uint64_t command_random_state = 0x9e3779b97f4a7c15ULL;
    std::uint64_t powder_random_state = 0x12345678ULL;

    auto next_random = [&command_random_state]() {
        command_random_state = command_random_state * 6364136223846793005ULL
            + 1442695040888963407ULL;
        return command_random_state;
    };
    const auto inside = [](std::int64_t x, std::int64_t y,
                           std::int64_t center_x, std::int64_t center_y,
                           std::uint32_t radius) {
        const auto dx = x - center_x;
        const auto dy = y - center_y;
        return dx * dx + dy * dy <= static_cast<std::int64_t>(radius) * radius;
    };

    for (int frame = 0; frame < 8; ++frame) {
        MaterialCommandBatchDto batch;
        std::vector<ExtractionStats> expected_extractions;
        for (int index = 0; index < 32; ++index) {
            const auto center_x = static_cast<std::int64_t>(next_random() % width);
            const auto center_y = static_cast<std::int64_t>(next_random() % height);
            const auto radius = static_cast<std::uint32_t>(next_random() % 6U);
            if ((next_random() & 3U) != 0U) {
                const auto material_id = static_cast<std::uint8_t>(1U + next_random() % 9U);
                const auto material = static_cast<Material>(material_id);
                batch.commands.emplace_back(PaintCircleCommand{
                    center_x, center_y, radius, material,
                });
                for (std::uint32_t y = 0; y < height; ++y) {
                    for (std::uint32_t x = 0; x < width; ++x) {
                        if (inside(x, y, center_x, center_y, radius)) {
                            reference[static_cast<std::size_t>(y) * width + x] = material_id;
                        }
                    }
                }
                continue;
            }

            batch.commands.emplace_back(ExtractCircleCommand{center_x, center_y, radius});
            ExtractionStats expected;
            for (std::uint32_t y = 0; y < height; ++y) {
                for (std::uint32_t x = 0; x < width; ++x) {
                    if (!inside(x, y, center_x, center_y, radius)) {
                        continue;
                    }
                    auto& cell = reference[static_cast<std::size_t>(y) * width + x];
                    if (cell == static_cast<std::uint8_t>(Material::rock)) {
                        ++expected.rock;
                    } else if (cell == static_cast<std::uint8_t>(Material::sand)) {
                        ++expected.sand;
                    } else if (cell == static_cast<std::uint8_t>(Material::metal)) {
                        ++expected.metal;
                    } else {
                        continue;
                    }
                    ++expected.total;
                    cell = static_cast<std::uint8_t>(Material::air);
                }
            }
            expected_extractions.push_back(expected);
        }

        const auto results = world.submit_command_batch(batch);
        std::size_t extraction_index = 0;
        for (const auto& result : results.results) {
            if (const auto* extracted = std::get_if<ExtractionStats>(&result)) {
                require(*extracted == expected_extractions[extraction_index++],
                        "random reference extraction statistics must match");
            }
        }
        require(extraction_index == expected_extractions.size(),
                "random reference extraction result count must match");
        world.step();
        simulate_powder_reference(reference, width, height, powder_random_state);
        require(std::vector<std::uint8_t>(world.cells().begin(), world.cells().end()) == reference,
                "random reference cell state must match after every frame");
    }
}

} // namespace

int main() {
    test_config_and_dto_validation();
    test_storage_snapshot_and_tick();
    test_circle_clipping_and_extraction();
    test_dirty_chunk_transport();
    test_deterministic_replay();
    test_powder_movement_and_boundaries();
    test_powder_cross_chunk_dirty_transport();
    test_powder_seed_divergence();
    test_randomized_reference_model();
    std::cout << "world unit test passed\n";
    return 0;
}
