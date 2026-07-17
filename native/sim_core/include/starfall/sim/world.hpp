#pragma once

#include <cstddef>
#include <cstdint>
#include <span>
#include <variant>
#include <vector>

namespace starfall::sim {

// These values are part of the batched transport contract and deliberately
// match MaterialWorld.CellMaterial in game/scripts/simulation/material_world.gd.
enum class Material : std::uint8_t {
    air = 0,
    rock = 1,
    sand = 2,
    water = 3,
    oil = 4,
    fire = 5,
    smoke = 6,
    lava = 7,
    steam = 8,
    metal = 9,
};

inline constexpr std::uint8_t material_count = 10;

[[nodiscard]] constexpr bool is_valid_material(Material material) noexcept {
    return static_cast<std::uint8_t>(material) < material_count;
}

struct SimulationConfig final {
    std::uint32_t ticks_per_second = 30;
    std::uint32_t width = 160;
    std::uint32_t height = 90;
    std::uint32_t chunk_size = 64;
    std::uint64_t seed = 0x051a7e11ULL;
    Material initial_material = Material::air;
};

struct PaintCircleCommand final {
    std::int64_t center_x = 0;
    std::int64_t center_y = 0;
    std::uint32_t radius = 0;
    Material material = Material::air;
};

struct ExtractCircleCommand final {
    std::int64_t center_x = 0;
    std::int64_t center_y = 0;
    std::uint32_t radius = 0;
};

using Command = std::variant<PaintCircleCommand, ExtractCircleCommand>;

struct ExtractionStats final {
    std::uint64_t total = 0;
    std::uint64_t rock = 0;
    std::uint64_t sand = 0;
    std::uint64_t metal = 0;

    [[nodiscard]] bool operator==(const ExtractionStats&) const noexcept = default;
};

// Results have the same order and cardinality as the submitted commands.
// Paint commands return monostate; extract commands return their counts.
using CommandResult = std::variant<std::monostate, ExtractionStats>;

struct DirtyChunkSnapshot final {
    std::uint32_t chunk_x = 0;
    std::uint32_t chunk_y = 0;
    std::uint32_t width = 0;
    std::uint32_t height = 0;
    std::vector<std::uint8_t> cells;
};

struct WorldSnapshot final {
    SimulationConfig config;
    std::uint64_t tick = 0;
    std::uint64_t random_state = 0;
    std::vector<std::uint8_t> cells;
};

class World final {
public:
    explicit World(SimulationConfig config = {});

    // Storage/transport foundation only: stepping advances deterministic time;
    // material reactions and movement still live in the temporary Godot world.
    void step() noexcept;

    [[nodiscard]] std::vector<CommandResult>
    submit_command_batch(std::span<const Command> commands);

    // Returns each dirty chunk at most once in row-major chunk order and clears
    // the returned dirty flags.
    [[nodiscard]] std::vector<DirtyChunkSnapshot> consume_dirty_chunks();

    [[nodiscard]] WorldSnapshot snapshot() const;
    [[nodiscard]] std::uint64_t checksum() const noexcept;

    [[nodiscard]] Material material_at(std::uint32_t x, std::uint32_t y) const;
    [[nodiscard]] const SimulationConfig& config() const noexcept;
    [[nodiscard]] std::uint64_t tick() const noexcept;
    [[nodiscard]] std::uint64_t random_state() const noexcept;
    [[nodiscard]] std::uint32_t chunk_columns() const noexcept;
    [[nodiscard]] std::uint32_t chunk_rows() const noexcept;
    [[nodiscard]] std::span<const std::uint8_t> cells() const noexcept;

private:
    [[nodiscard]] std::size_t cell_index(std::uint32_t x, std::uint32_t y) const noexcept;
    [[nodiscard]] std::size_t chunk_index(std::uint32_t chunk_x,
                                          std::uint32_t chunk_y) const noexcept;
    void set_material(std::uint32_t x, std::uint32_t y, Material material);
    void paint_circle(const PaintCircleCommand& command);
    [[nodiscard]] ExtractionStats extract_circle(const ExtractCircleCommand& command);

    SimulationConfig config_;
    std::uint32_t chunk_columns_ = 0;
    std::uint32_t chunk_rows_ = 0;
    std::vector<std::uint8_t> cells_;
    std::vector<bool> dirty_chunks_;
    std::uint64_t tick_ = 0;
    std::uint64_t random_state_ = 0;
};

} // namespace starfall::sim
