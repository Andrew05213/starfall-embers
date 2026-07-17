#include "starfall/sim/world.hpp"

#include <cstdint>
#include <cstdlib>
#include <exception>
#include <iostream>
#include <limits>
#include <span>
#include <stdexcept>
#include <string_view>
#include <type_traits>
#include <vector>

namespace {

using starfall::sim::Command;
using starfall::sim::ExtractCircleCommand;
using starfall::sim::ExtractionStats;
using starfall::sim::Material;
using starfall::sim::PaintCircleCommand;
using starfall::sim::SimulationConfig;
using starfall::sim::World;

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

[[noreturn]] void fail(std::string_view message) {
    std::cerr << "world unit test failed: " << message << '\n';
    std::exit(1);
}

void require(bool condition, std::string_view message) {
    if (!condition) {
        fail(message);
    }
}

template <typename Callable>
void require_invalid_argument(Callable&& callable, std::string_view message) {
    try {
        callable();
    } catch (const std::invalid_argument&) {
        return;
    } catch (...) {
        fail(message);
    }
    fail(message);
}

std::vector<starfall::sim::CommandResult> submit(World& world,
                                                 std::initializer_list<Command> commands) {
    return world.submit_command_batch(std::span<const Command>(commands.begin(), commands.size()));
}

void test_config_validation() {
    require_invalid_argument([] { World world({0, 1, 1, 1, 0, Material::air}); },
                             "zero tick rate must be rejected");
    require_invalid_argument([] { World world({30, 0, 1, 1, 0, Material::air}); },
                             "zero width must be rejected");
    require_invalid_argument([] { World world({30, 1, 0, 1, 0, Material::air}); },
                             "zero height must be rejected");
    require_invalid_argument([] { World world({30, 1, 1, 0, 0, Material::air}); },
                             "zero chunk size must be rejected");
    require_invalid_argument([] {
        World world({30, 1, 1, 1, 0, static_cast<Material>(10)});
    }, "invalid initial material must be rejected");
    require_invalid_argument([] {
        const auto maximum = std::numeric_limits<std::uint32_t>::max();
        World world({30, maximum, maximum, 64, 0, Material::air});
    }, "dimensions beyond compact storage limits must be rejected before allocation");

    World world({30, 3, 3, 2, 7, Material::air});
    const std::vector<Command> invalid_batch{
        PaintCircleCommand{1, 1, 0, Material::rock},
        PaintCircleCommand{1, 1, 0, static_cast<Material>(255)},
    };
    require_invalid_argument([&] { (void)world.submit_command_batch(invalid_batch); },
                             "invalid batch material must be rejected");
    require(world.material_at(1, 1) == Material::air,
            "invalid batch must be validated before any mutation");
}

void test_defaults_storage_and_tick() {
    World world;
    require(world.config().ticks_per_second == 30, "default tick rate mismatch");
    require(world.config().width == 160 && world.config().height == 90,
            "default dimensions mismatch");
    require(world.config().chunk_size == 64, "default chunk size mismatch");
    require(world.chunk_columns() == 3 && world.chunk_rows() == 2,
            "default chunk grid mismatch");
    require(world.cells().size() == 160U * 90U, "cell storage must be compact");
    require(world.consume_dirty_chunks().empty(), "fresh world must not report mutations");

    const auto initial_checksum = world.checksum();
    world.step();
    world.step();
    require(world.tick() == 2, "fixed step must advance tick exactly once");
    require(world.checksum() != initial_checksum,
            "tick must participate in deterministic checksum");
    const auto snapshot = world.snapshot();
    require(snapshot.tick == 2 && snapshot.random_state == world.config().seed,
            "snapshot must include tick and explicit random state");
    require(snapshot.cells == std::vector<std::uint8_t>(world.cells().begin(), world.cells().end()),
            "snapshot must preserve compact row-major cells");
}

void test_circle_clipping_and_extraction() {
    World clipped({30, 4, 4, 2, 11, Material::air});
    (void)submit(clipped, {PaintCircleCommand{0, 0, 1, Material::rock}});
    require(clipped.material_at(0, 0) == Material::rock &&
            clipped.material_at(1, 0) == Material::rock &&
            clipped.material_at(0, 1) == Material::rock,
            "circle at world boundary must retain its in-bounds cells");
    require(clipped.material_at(1, 1) == Material::air,
            "circle geometry must exclude diagonal outside radius");

    const auto maximum_u32 = std::numeric_limits<std::uint32_t>::max();
    World maximum_radius({30, 1, 1, 1, 13, Material::air});
    (void)submit(maximum_radius, {
        PaintCircleCommand{maximum_u32, maximum_u32, maximum_u32, Material::rock},
    });
    require(maximum_radius.material_at(0, 0) == Material::air,
            "circle distance comparison must not overflow at UINT32_MAX radius");
    require(maximum_radius.consume_dirty_chunks().empty(),
            "overflow-rejected circle must not dirty the world");

    World extreme_centers({30, 1, 1, 1, 17, Material::air});
    (void)submit(extreme_centers, {
        PaintCircleCommand{std::numeric_limits<std::int64_t>::min(), 0,
                           maximum_u32, Material::rock},
        PaintCircleCommand{std::numeric_limits<std::int64_t>::max(), 0,
                           maximum_u32, Material::rock},
        PaintCircleCommand{0, std::numeric_limits<std::int64_t>::min(),
                           maximum_u32, Material::rock},
        PaintCircleCommand{0, std::numeric_limits<std::int64_t>::max(),
                           maximum_u32, Material::rock},
    });
    require(extreme_centers.material_at(0, 0) == Material::air,
            "INT64_MIN/MAX circle centers must clip safely outside the world");
    require(extreme_centers.consume_dirty_chunks().empty(),
            "safely clipped extreme centers must not dirty the world");

    World world({30, 7, 7, 4, 19, Material::air});
    const std::vector<Command> commands{
        PaintCircleCommand{3, 3, 1, Material::rock},
        PaintCircleCommand{3, 3, 0, Material::metal},
        PaintCircleCommand{3, 2, 0, Material::sand},
        PaintCircleCommand{2, 3, 0, Material::water},
        ExtractCircleCommand{3, 3, 1},
    };
    const auto results = world.submit_command_batch(commands);
    require(results.size() == commands.size(), "batch results must align with command order");
    require(std::holds_alternative<std::monostate>(results.front()),
            "paint command result must be monostate");
    const auto extracted = std::get<ExtractionStats>(results.back());
    require(extracted == ExtractionStats{4, 2, 1, 1},
            "extract must count only mineable rock, sand, and metal");
    require(world.material_at(2, 3) == Material::water,
            "extract must preserve non-mineable materials");
}

void test_dirty_chunk_transport() {
    World world({30, 70, 65, 64, 23, Material::air});
    const std::vector<Command> commands{
        PaintCircleCommand{69, 64, 0, Material::metal}, // chunk (1, 1)
        PaintCircleCommand{1, 1, 0, Material::rock},    // chunk (0, 0)
        PaintCircleCommand{68, 2, 0, Material::sand},   // chunk (1, 0)
        PaintCircleCommand{2, 2, 0, Material::rock},    // duplicate chunk (0, 0)
    };
    (void)world.submit_command_batch(commands);
    const auto dirty = world.consume_dirty_chunks();
    require(dirty.size() == 3, "each dirty chunk must appear once per consumption");
    require(dirty[0].chunk_x == 0 && dirty[0].chunk_y == 0 &&
            dirty[1].chunk_x == 1 && dirty[1].chunk_y == 0 &&
            dirty[2].chunk_x == 1 && dirty[2].chunk_y == 1,
            "dirty chunks must be stable row-major regardless of command order");
    require(dirty[0].width == 64 && dirty[0].height == 64 && dirty[0].cells.size() == 4096,
            "full chunk snapshot dimensions mismatch");
    require(dirty[1].width == 6 && dirty[1].height == 64 && dirty[1].cells.size() == 384,
            "right edge chunk must be tightly packed without padding");
    require(dirty[2].width == 6 && dirty[2].height == 1 && dirty[2].cells.size() == 6,
            "corner edge chunk must expose valid dimensions and compact bytes");
    require(dirty[2].cells[5] == static_cast<std::uint8_t>(Material::metal),
            "edge chunk bytes must be local row-major cell data");
    require(world.consume_dirty_chunks().empty(),
            "consuming dirty chunks must clear their dirty flags");

    (void)submit(world, {PaintCircleCommand{69, 64, 0, Material::metal}});
    require(world.consume_dirty_chunks().empty(),
            "painting the existing value must not create a false dirty chunk");
}

void test_command_order_and_determinism() {
    const SimulationConfig config{30, 16, 16, 8, 0xabcdefULL, Material::air};
    const std::vector<Command> paint_then_extract{
        PaintCircleCommand{8, 8, 2, Material::rock},
        ExtractCircleCommand{8, 8, 1},
    };
    World first(config);
    World second(config);
    const auto first_results = first.submit_command_batch(paint_then_extract);
    const auto second_results = second.submit_command_batch(paint_then_extract);
    first.step();
    second.step();
    require(first_results == second_results && first.checksum() == second.checksum(),
            "same seed, commands, order, and tick must be deterministic");

    World reversed(config);
    const std::vector<Command> extract_then_paint{
        ExtractCircleCommand{8, 8, 1},
        PaintCircleCommand{8, 8, 2, Material::rock},
    };
    const auto reversed_results = reversed.submit_command_batch(extract_then_paint);
    reversed.step();
    require(std::get<ExtractionStats>(first_results[1]).total == 5,
            "ordered extraction must observe earlier paint in the same batch");
    require(std::get<ExtractionStats>(reversed_results[0]).total == 0,
            "ordered extraction must not observe later paint in the same batch");
    require(first.checksum() != reversed.checksum(),
            "different command order must produce observably different state");
}

} // namespace

int main() {
    test_config_validation();
    test_defaults_storage_and_tick();
    test_circle_clipping_and_extraction();
    test_dirty_chunk_transport();
    test_command_order_and_determinism();
    std::cout << "world unit test passed\n";
    return 0;
}
