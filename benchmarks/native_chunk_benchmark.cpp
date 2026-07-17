#include "starfall/sim/world.hpp"

#include <chrono>
#include <cstddef>
#include <cstdint>
#include <iomanip>
#include <iostream>
#include <vector>

int main() {
    using namespace starfall::sim;
    using Clock = std::chrono::steady_clock;

    constexpr std::uint32_t world_size = 1024;
    constexpr std::uint32_t command_count = 2'048;
    World world({30, world_size, world_size, 64, 0x5eed1234ULL, Material::air});

    std::vector<Command> commands;
    commands.reserve(command_count);
    std::uint64_t state = world.config().seed;
    for (std::uint32_t index = 0; index < command_count; ++index) {
        state = state * 6364136223846793005ULL + 1442695040888963407ULL;
        const auto x = static_cast<std::int64_t>((state >> 16U) % world_size);
        state = state * 6364136223846793005ULL + 1442695040888963407ULL;
        const auto y = static_cast<std::int64_t>((state >> 16U) % world_size);
        const auto material = (index % 5U == 0U) ? Material::metal : Material::rock;
        commands.emplace_back(PaintCircleCommand{x, y, 5, material});
    }

    const auto command_start = Clock::now();
    const auto results = world.submit_command_batch(commands);
    const auto command_end = Clock::now();
    const auto dirty_start = Clock::now();
    const auto dirty = world.consume_dirty_chunks();
    const auto dirty_end = Clock::now();

    std::size_t dirty_bytes = 0;
    for (const auto& chunk : dirty) {
        dirty_bytes += chunk.cells.size();
    }
    const auto command_ms =
        std::chrono::duration<double, std::milli>(command_end - command_start).count();
    const auto dirty_ms =
        std::chrono::duration<double, std::milli>(dirty_end - dirty_start).count();

    std::cout << std::fixed << std::setprecision(3)
              << "native chunk benchmark\n"
              << "world: " << world_size << 'x' << world_size << '\n'
              << "chunk: " << world.config().chunk_size << 'x' << world.config().chunk_size << '\n'
              << "commands: " << results.size() << '\n'
              << "command batch ms: " << command_ms << '\n'
              << "dirty chunks: " << dirty.size() << '\n'
              << "dirty payload bytes: " << dirty_bytes << '\n'
              << "dirty consume ms: " << dirty_ms << '\n'
              << "checksum: " << world.checksum() << '\n';
    return 0;
}
