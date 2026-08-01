#include "starfall/sim/simulation_host.hpp"

#include <iterator>
#include <utility>

namespace starfall::sim {

SimulationHost::SimulationHost(SimulationHostConfig config)
    : config_(config),
      ballistics_(config_.ticks_per_second, config_.primary_gravity),
      material_world_({
          .ticks_per_second = config_.ticks_per_second,
          .width = config_.material_world_width,
          .height = config_.material_world_height,
          .chunk_size = material_chunk_size,
          .seed = config_.random_seed,
          .initial_material = config_.initial_material,
      }) {}

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

void SimulationHost::submit_material_commands(MaterialCommandBatchDto commands) {
    material_world_.validate_command_batch(commands);
    pending_material_commands_.commands.insert(
        pending_material_commands_.commands.end(),
        std::make_move_iterator(commands.commands.begin()),
        std::make_move_iterator(commands.commands.end())
    );
}

void SimulationHost::submit_collision_world(CollisionWorldSnapshot snapshot) {
    ballistics_.set_collision_world(std::move(snapshot));
}

void SimulationHost::step() {
    pending_material_results_.results.reserve(
        pending_material_results_.results.size() + pending_material_commands_.commands.size()
    );
    auto step_material_results = material_world_.submit_command_batch(pending_material_commands_);
    pending_material_commands_.commands.clear();
    material_world_.step();
    pending_material_results_.version = material_transport_dto_version;
    pending_material_results_.tick = material_world_.tick();
    pending_material_results_.results.insert(
        pending_material_results_.results.end(),
        std::make_move_iterator(step_material_results.results.begin()),
        std::make_move_iterator(step_material_results.results.end())
    );

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

std::size_t SimulationHost::pending_material_command_count() const noexcept {
    return pending_material_commands_.commands.size();
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

const MaterialCommandResultBatchDto& SimulationHost::material_command_results() const noexcept {
    return pending_material_results_;
}

MaterialCommandResultBatchDto SimulationHost::drain_material_command_results() {
    MaterialCommandResultBatchDto drained = std::move(pending_material_results_);
    pending_material_results_ = {
        .version = material_transport_dto_version,
        .tick = tick(),
        .results = {},
    };
    return drained;
}

DirtyChunkBatchDto SimulationHost::drain_dirty_chunks() {
    return material_world_.consume_dirty_chunks();
}

std::uint64_t SimulationHost::material_checksum() const noexcept {
    return material_world_.checksum();
}

const World& SimulationHost::material_world() const noexcept {
    return material_world_;
}

} // namespace starfall::sim
