#include "starfall/sim/simulation_host.hpp"

#include <algorithm>
#include <chrono>
#include <cstdint>
#include <iostream>
#include <numeric>
#include <utility>
#include <vector>

int main() {
    constexpr std::uint32_t width = 160;
    constexpr std::uint32_t height = 90;
    constexpr std::size_t proxies = 4;
    constexpr std::uint64_t ticks = 120;
    constexpr std::uint64_t commands_per_tick = 256;
    constexpr double gate1_velocity = 1'200.0;
    constexpr double high_speed_velocity = 40'000.0;
    constexpr double frame_budget_ms = 1000.0 / 30.0;

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
    std::size_t total_substeps = 0;
    std::size_t peak_substeps = 0;
    std::size_t sample_limit_hits = 0;
    std::size_t sampled_projectiles = 0;
    std::vector<double> tick_ms;
    tick_ms.reserve(ticks);

    for (std::uint64_t tick = 0; tick < ticks; ++tick) {
        starfall::sim::ProjectileCommandBatch commands;
        commands.spawns.reserve(commands_per_tick);
        for (std::uint64_t index = 0; index < commands_per_tick; ++index) {
            commands.spawns.push_back({
                .request_id = tick * commands_per_tick + index + 1,
                .position = {20.0, -500.0 - static_cast<double>(index % 64)},
                .velocity = {
                    index == 0 ? high_speed_velocity : gate1_velocity,
                    0.0,
                },
                .lifetime_seconds = 0.55,
                .gravity_scale = 1.3,
                .collision_radius = 1.5,
            });
        }
        host.submit_collision_world(collision_world);
        host.submit_projectile_commands(std::move(commands));
        const auto tick_start = std::chrono::steady_clock::now();
        host.step();
        const auto tick_end = std::chrono::steady_clock::now();
        [[maybe_unused]] const auto events = host.drain_projectile_events();
        peak_active = std::max(peak_active, host.projectile_states().projectiles.size());
        tick_ms.push_back(std::chrono::duration<double, std::milli>(
            tick_end - tick_start
        ).count());
        for (const auto& projectile : host.projectile_states().projectiles) {
            ++sampled_projectiles;
            total_substeps += projectile.gravity_substeps;
            peak_substeps = std::max<std::size_t>(peak_substeps, projectile.gravity_substeps);
            if (projectile.gravity_sample_limit_reached) {
                ++sample_limit_hits;
            }
        }
    }

    std::sort(tick_ms.begin(), tick_ms.end());
    const auto p95_index = std::max<std::size_t>(
        0, static_cast<std::size_t>(ticks * 95U / 100U) - 1);
    const auto p95_ms = tick_ms[p95_index];
    const auto max_ms = tick_ms.back();
    const auto elapsed = std::accumulate(tick_ms.begin(), tick_ms.end(), 0.0);
    const auto average_ms = elapsed / static_cast<double>(ticks);
    const auto observed_projectiles = std::max<std::size_t>(1, sampled_projectiles);

    std::cout
        << "native ballistics benchmark: world=" << width << 'x' << height
        << " cells=" << width * height
        << " proxies=" << proxies
        << " ticks=" << ticks
        << " commands=" << ticks * commands_per_tick
        << " gate1_velocity=" << gate1_velocity
        << " high_speed_velocity=" << high_speed_velocity
        << " peak_active=" << peak_active
        << " elapsed_ms=" << elapsed
        << " tick_average_ms=" << average_ms
        << " tick_p95_ms=" << p95_ms
        << " tick_max_ms=" << max_ms
        << " frame_budget_ms=" << frame_budget_ms
        << " p95_budget_utilization=" << (p95_ms / frame_budget_ms * 100.0) << '%'
        << " gravity_substeps_average="
        << (static_cast<double>(total_substeps) / static_cast<double>(observed_projectiles))
        << " gravity_substeps_peak=" << peak_substeps
        << " gravity_sample_limit_hits=" << sample_limit_hits
        << '\n';
    if (sample_limit_hits == 0) {
        std::cerr << "native ballistics benchmark: high-speed sample-limit scenario did not execute\n";
        return 1;
    }
    return 0;
}
