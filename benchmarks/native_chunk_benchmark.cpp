#include "starfall/sim/simulation_host.hpp"

#include <chrono>
#include <cstddef>
#include <cstdint>
#include <iomanip>
#include <iostream>

int main() {
    using namespace starfall::sim;
    using Clock = std::chrono::steady_clock;

    constexpr std::uint32_t world_size = 1024;
    constexpr std::uint32_t command_count = 2'048;
    constexpr std::uint64_t seed = 0x5eed1234ULL;
    const SimulationHostConfig config{
        .ticks_per_second = 30,
        .random_seed = seed,
        .primary_gravity = Gate1BallisticBaseline::gravity(),
        .material_world_width = world_size,
        .material_world_height = world_size,
        .initial_material = Material::air,
    };
    SimulationHost host(config);
    SimulationHost replay(config);

    MaterialCommandBatchDto commands;
    commands.commands.reserve(command_count);
    std::uint64_t state = seed;
    for (std::uint32_t index = 0; index < command_count; ++index) {
        state = state * 6364136223846793005ULL + 1442695040888963407ULL;
        const auto x = static_cast<std::int64_t>((state >> 16U) % world_size);
        state = state * 6364136223846793005ULL + 1442695040888963407ULL;
        const auto y = static_cast<std::int64_t>((state >> 16U) % world_size);
        const auto material = index % 5U == 0U ? Material::metal : Material::rock;
        commands.commands.emplace_back(PaintCircleCommand{x, y, 5, material});
    }

    const auto command_start = Clock::now();
    host.submit_material_commands(commands);
    host.step();
    const auto command_end = Clock::now();
    const auto results = host.drain_material_command_results();

    const auto dirty_start = Clock::now();
    const auto dirty = host.drain_dirty_chunks();
    const auto dirty_end = Clock::now();

    replay.submit_material_commands(commands);
    replay.step();
    const auto replay_results = replay.drain_material_command_results();
    const auto replay_dirty = replay.drain_dirty_chunks();
    const bool deterministic = host.material_checksum() == replay.material_checksum()
        && results.results == replay_results.results
        && dirty.chunks == replay_dirty.chunks;

    std::size_t dirty_bytes = 0;
    for (const auto& chunk : dirty.chunks) {
        dirty_bytes += chunk.cells.size();
    }
    const auto command_ms =
        std::chrono::duration<double, std::milli>(command_end - command_start).count();
    const auto dirty_ms =
        std::chrono::duration<double, std::milli>(dirty_end - dirty_start).count();

    std::cout << std::fixed << std::setprecision(3)
              << "native chunk benchmark\n"
              << "dto version: " << material_transport_dto_version << '\n'
              << "world: " << world_size << 'x' << world_size << '\n'
              << "chunk: " << material_chunk_size << 'x' << material_chunk_size << '\n'
              << "commands: " << results.results.size() << '\n'
              << "command batch ms: " << command_ms << '\n'
              << "active dirty chunks: " << dirty.chunks.size() << '\n'
              << "dirty payload bytes: " << dirty_bytes << '\n'
              << "dirty consume ms: " << dirty_ms << '\n'
              << "checksum: " << host.material_checksum() << '\n'
              << "deterministic replay: " << (deterministic ? "PASS" : "FAIL") << '\n';
    return deterministic ? 0 : 1;
}
