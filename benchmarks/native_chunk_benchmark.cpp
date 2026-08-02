#include "starfall/sim/simulation_host.hpp"

#include <algorithm>
#include <chrono>
#include <cstddef>
#include <cstdint>
#include <iomanip>
#include <iostream>
#include <numeric>
#include <vector>

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
    const auto dirty_batches_equal = [](const DirtyChunkBatchDto& left,
                                        const DirtyChunkBatchDto& right) {
        return left.version == right.version
            && left.tick == right.tick
            && left.chunk_size == right.chunk_size
            && left.chunks == right.chunks;
    };

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
    const auto replay_dirty_initial = replay.drain_dirty_chunks();
    const bool deterministic = host.material_checksum() == replay.material_checksum()
        && results.results == replay_results.results
        && dirty_batches_equal(dirty, replay_dirty_initial);

    std::size_t dirty_bytes = 0;
    for (const auto& chunk : dirty.chunks) {
        dirty_bytes += chunk.cells.size();
    }
    const auto command_ms =
        std::chrono::duration<double, std::milli>(command_end - command_start).count();
    const auto dirty_ms =
        std::chrono::duration<double, std::milli>(dirty_end - dirty_start).count();

    MaterialCommandBatchDto powder_commands;
    powder_commands.commands.reserve(command_count);
    state = seed ^ 0x9e3779b97f4a7c15ULL;
    for (std::uint32_t index = 0; index < command_count; ++index) {
        state = state * 6364136223846793005ULL + 1442695040888963407ULL;
        const auto x = static_cast<std::int64_t>((state >> 16U) % world_size);
        state = state * 6364136223846793005ULL + 1442695040888963407ULL;
        const auto y = static_cast<std::int64_t>((state >> 16U) % (world_size / 2U));
        powder_commands.commands.emplace_back(PaintCircleCommand{x, y, 2, Material::sand});
    }
    host.submit_material_commands(powder_commands);
    host.step();
    (void)host.drain_material_command_results();
    (void)host.drain_dirty_chunks();
    replay.submit_material_commands(powder_commands);
    replay.step();
    (void)replay.drain_material_command_results();
    (void)replay.drain_dirty_chunks();

    constexpr std::size_t powder_ticks = 300;
    constexpr double frame_budget_ms = 1000.0 / 30.0;
    std::vector<double> powder_tick_ms;
    powder_tick_ms.reserve(powder_ticks);
    std::size_t dirty_chunk_total = 0;
    std::size_t dirty_chunk_max = 0;
    std::size_t dirty_payload_total = 0;
    std::size_t dirty_payload_max = 0;
    bool powder_deterministic = true;
    for (std::size_t tick = 0; tick < powder_ticks; ++tick) {
        const auto powder_start = Clock::now();
        host.step();
        const auto powder_end = Clock::now();
        const auto powder_dirty = host.drain_dirty_chunks();
        replay.step();
        const auto replay_powder_dirty = replay.drain_dirty_chunks();
        const auto powder_ms =
            std::chrono::duration<double, std::milli>(powder_end - powder_start).count();
        powder_tick_ms.push_back(powder_ms);

        std::size_t payload_bytes = 0;
        for (const auto& chunk : powder_dirty.chunks) {
            payload_bytes += chunk.cells.size();
        }
        dirty_chunk_total += powder_dirty.chunks.size();
        dirty_chunk_max = std::max(dirty_chunk_max, powder_dirty.chunks.size());
        dirty_payload_total += payload_bytes;
        dirty_payload_max = std::max(dirty_payload_max, payload_bytes);
        powder_deterministic = powder_deterministic
            && host.material_checksum() == replay.material_checksum()
            && dirty_batches_equal(powder_dirty, replay_powder_dirty);
    }

    std::sort(powder_tick_ms.begin(), powder_tick_ms.end());
    const auto p95_index = std::max<std::size_t>(
        0, static_cast<std::size_t>(powder_ticks * 95U / 100U) - 1);
    const auto powder_p95_ms = powder_tick_ms[p95_index];
    const auto powder_max_ms = powder_tick_ms.back();
    const auto powder_average_ms =
        std::accumulate(powder_tick_ms.begin(), powder_tick_ms.end(), 0.0)
        / static_cast<double>(powder_ticks);

    std::cout << std::fixed << std::setprecision(3)
              << "native chunk/powder benchmark\n"
              << "dto version: " << material_transport_dto_version << '\n'
              << "world: " << world_size << 'x' << world_size << '\n'
              << "chunk: " << material_chunk_size << 'x' << material_chunk_size << '\n'
              << "commands: " << results.results.size() << '\n'
              << "command batch ms: " << command_ms << '\n'
              << "active dirty chunks: " << dirty.chunks.size() << '\n'
              << "dirty payload bytes: " << dirty_bytes << '\n'
              << "dirty consume ms: " << dirty_ms << '\n'
              << "powder ticks: " << powder_ticks << '\n'
              << "powder tick average ms: " << powder_average_ms << '\n'
              << "powder tick p95 ms: " << powder_p95_ms << '\n'
              << "powder tick max ms: " << powder_max_ms << '\n'
              << "powder frame budget ms: " << frame_budget_ms << '\n'
              << "powder p95 budget utilization: "
              << (powder_p95_ms / frame_budget_ms * 100.0) << "%\n"
              << "powder active dirty chunks average: "
              << (static_cast<double>(dirty_chunk_total) / powder_ticks) << '\n'
              << "powder active dirty chunks max: " << dirty_chunk_max << '\n'
              << "powder dirty payload bytes average: "
              << (static_cast<double>(dirty_payload_total) / powder_ticks) << '\n'
              << "powder dirty payload bytes max: " << dirty_payload_max << '\n'
              << "powder checksum: " << host.material_checksum() << '\n'
              << "deterministic replay: " << (deterministic && powder_deterministic
                                                    ? "PASS" : "FAIL") << '\n'
              << "powder frame budget: " << (powder_p95_ms <= frame_budget_ms
                                                   ? "PASS" : "OVER") << '\n';
    return deterministic && powder_deterministic ? 0 : 1;
}
