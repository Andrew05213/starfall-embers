#pragma once

#include "starfall/sim/ballistics.hpp"
#include "starfall/sim/world.hpp"

#include <cstddef>
#include <cstdint>

namespace starfall::sim {

struct SimulationHostConfig final {
    std::uint32_t ticks_per_second = Gate1BallisticBaseline::ticks_per_second;
    std::uint64_t random_seed = 0x51a7e11ULL;
    PrimaryGravity primary_gravity = Gate1BallisticBaseline::gravity();
    std::uint32_t material_world_width = 160;
    std::uint32_t material_world_height = 90;
    Material initial_material = Material::air;
};

/// Engine-independent coarse-grained facade for the authoritative simulation.
///
/// Presentation code may submit multiple command batches between fixed steps;
/// the host coalesces them and crosses into each subsystem once per step. State
/// and event batches remain valid until the following call to step().
class SimulationHost final {
public:
    explicit SimulationHost(SimulationHostConfig config = {});
    SimulationHost(const SimulationHost&) = delete;
    SimulationHost& operator=(const SimulationHost&) = delete;
    SimulationHost(SimulationHost&&) = delete;
    SimulationHost& operator=(SimulationHost&&) = delete;

    /// Rebuilds all subsystem state without assigning a BallisticSystem that
    /// would retain a pointer to a temporary GravityField.
    void reset(SimulationHostConfig config = {});
    void submit_projectile_commands(ProjectileCommandBatch commands);
    void submit_gravity_source_commands(GravitySourceCommandBatch commands);
    void submit_material_commands(MaterialCommandBatchDto commands);
    void submit_collision_world(CollisionWorldSnapshot snapshot);
    void step();

    [[nodiscard]] const SimulationHostConfig& config() const noexcept;
    [[nodiscard]] std::uint64_t tick() const noexcept;
    [[nodiscard]] double fixed_step_seconds() const noexcept;
    [[nodiscard]] std::size_t pending_projectile_command_count() const noexcept;
    [[nodiscard]] std::size_t pending_gravity_source_command_count() const noexcept;
    [[nodiscard]] std::size_t pending_material_command_count() const noexcept;
    [[nodiscard]] const ProjectileStateBatch& projectile_states() const noexcept;
    /// Events accumulate across fixed steps until explicitly drained. This is
    /// required when one render frame advances multiple catch-up ticks.
    [[nodiscard]] const ProjectileEventBatch& projectile_events() const noexcept;
    [[nodiscard]] ProjectileEventBatch drain_projectile_events();
    [[nodiscard]] const MaterialCommandResultBatchDto& material_command_results() const noexcept;
    [[nodiscard]] MaterialCommandResultBatchDto drain_material_command_results();
    [[nodiscard]] DirtyChunkBatchDto drain_dirty_chunks();
    [[nodiscard]] std::uint64_t material_checksum() const noexcept;
    [[nodiscard]] std::uint64_t gravity_checksum() const noexcept;
    [[nodiscard]] const GravityField& gravity_field() const noexcept;
    [[nodiscard]] const World& material_world() const noexcept;

private:
    SimulationHostConfig config_{};
    GravityField gravity_field_{};
    BallisticSystem ballistics_{};
    World material_world_{};
    ProjectileCommandBatch pending_projectile_commands_{};
    GravitySourceCommandBatch pending_gravity_source_commands_{};
    ProjectileEventBatch pending_projectile_events_{};
    MaterialCommandBatchDto pending_material_commands_{};
    MaterialCommandResultBatchDto pending_material_results_{};
};

} // namespace starfall::sim
