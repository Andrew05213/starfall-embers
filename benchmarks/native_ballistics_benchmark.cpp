#include "starfall/sim/simulation_host.hpp"

#include <algorithm>
#include <chrono>
#include <cstdint>
#include <iostream>
#include <utility>
#include <vector>

int main() {
    constexpr std::uint32_t width = 160;
    constexpr std::uint32_t height = 90;
    constexpr std::size_t proxies = 4;
    constexpr std::uint64_t ticks = 120;
    constexpr std::uint64_t commands_per_tick = 256;

    starfall::sim::SimulationHost host({
        .ticks_per_second = 30,
        .random_seed = 0x51a7e11ULL,
        .primary_gravity = {
            .center = {320.0, 10'020.0},
            .surface_radius = 10'000.0,
            .surface_acceleration = 320.0,
        },
    });
    starfall::sim::CollisionWorldSnapshot collision_world;
    collision_world.terrain = {
        .origin = {0.0, 0.0},
        .cell_size = 4.0,
        .width = width,
        .height = height,
        .cells = std::vector<std::uint8_t>(width * height, 0),
    };
    for (std::size_t index = 0; index < proxies; ++index) {
        collision_world.colliders.push_back({
            .collider_id = index + 1,
            .shape = starfall::sim::CollisionShape::circle,
            .center = {10'000.0 + static_cast<double>(index) * 100.0, 10'000.0},
            .half_extents = {8.0, 8.0},
        });
    }

    std::size_t peak_active = 0;
    const auto start = std::chrono::steady_clock::now();
    for (std::uint64_t tick = 0; tick < ticks; ++tick) {
        starfall::sim::ProjectileCommandBatch commands;
        commands.spawns.reserve(commands_per_tick);
        for (std::uint64_t index = 0; index < commands_per_tick; ++index) {
            commands.spawns.push_back({
                .request_id = tick * commands_per_tick + index + 1,
                .position = {20.0, -500.0 - static_cast<double>(index % 64)},
                .velocity = {1'200.0, 0.0},
                .lifetime_seconds = 0.55,
                .gravity_scale = 1.3,
                .collision_radius = 1.5,
            });
        }
        host.submit_collision_world(collision_world);
        host.submit_projectile_commands(std::move(commands));
        host.step();
        [[maybe_unused]] const auto events = host.drain_projectile_events();
        peak_active = std::max(peak_active, host.projectile_states().projectiles.size());
    }
    const auto elapsed = std::chrono::duration<double, std::milli>(
        std::chrono::steady_clock::now() - start
    ).count();

    std::cout
        << "native ballistics benchmark: world=" << width << 'x' << height
        << " cells=" << width * height
        << " proxies=" << proxies
        << " ticks=" << ticks
        << " commands=" << ticks * commands_per_tick
        << " peak_active=" << peak_active
        << " elapsed_ms=" << elapsed
        << " ms_per_tick=" << elapsed / static_cast<double>(ticks)
        << '\n';
    return 0;
}
