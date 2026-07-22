#include "starfall/sim/simulation_host.hpp"

#include <iterator>
#include <utility>

namespace starfall::sim {

SimulationHost::SimulationHost(SimulationHostConfig config)
    : config_(config),
      ballistics_(config_.ticks_per_second, config_.primary_gravity) {}

void SimulationHost::submit_projectile_commands(ProjectileCommandBatch commands) {
    pending_projectile_commands_.spawns.insert(
        pending_projectile_commands_.spawns.end(),
        std::make_move_iterator(commands.spawns.begin()),
        std::make_move_iterator(commands.spawns.end())
    );
    pending_projectile_commands_.retires.insert(
        pending_projectile_commands_.retires.end(),
        std::make_move_iterator(commands.retires.begin()),
        std::make_move_iterator(commands.retires.end())
    );
}

void SimulationHost::step() {
    ballistics_.submit(std::move(pending_projectile_commands_));
    pending_projectile_commands_ = {};
    ballistics_.step();

    const auto& step_events = ballistics_.events();
    pending_projectile_events_.tick = step_events.tick;
    pending_projectile_events_.events.insert(
        pending_projectile_events_.events.end(),
        step_events.events.begin(),
        step_events.events.end()
    );
}

const SimulationHostConfig& SimulationHost::config() const noexcept {
    return config_;
}

std::uint64_t SimulationHost::tick() const noexcept {
    return ballistics_.tick();
}

double SimulationHost::fixed_step_seconds() const noexcept {
    return ballistics_.fixed_step_seconds();
}

std::size_t SimulationHost::pending_projectile_command_count() const noexcept {
    return pending_projectile_commands_.spawns.size()
        + pending_projectile_commands_.retires.size();
}

const ProjectileStateBatch& SimulationHost::projectile_states() const noexcept {
    return ballistics_.states();
}

const ProjectileEventBatch& SimulationHost::projectile_events() const noexcept {
    return pending_projectile_events_;
}

ProjectileEventBatch SimulationHost::drain_projectile_events() {
    ProjectileEventBatch drained = std::move(pending_projectile_events_);
    pending_projectile_events_ = {
        .tick = tick(),
        .events = {},
    };
    return drained;
}

} // namespace starfall::sim
