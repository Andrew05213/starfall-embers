#pragma once

#include "starfall/sim/ballistics.hpp"

#include <cstddef>
#include <cstdint>

namespace starfall::sim {

struct SimulationHostConfig final {
    std::uint32_t ticks_per_second = Gate1BallisticBaseline::ticks_per_second;
    std::uint64_t random_seed = 0x51a7e11ULL;
    PrimaryGravity primary_gravity = Gate1BallisticBaseline::gravity();
};

/// Engine-independent coarse-grained facade for the authoritative simulation.
///
/// Presentation code may submit multiple command batches between fixed steps;
/// the host coalesces them and crosses into each subsystem once per step. State
/// and event batches remain valid until the following call to step().
class SimulationHost final {
public:
    explicit SimulationHost(SimulationHostConfig config = {});

    void submit_projectile_commands(ProjectileCommandBatch commands);
    void submit_collision_world(CollisionWorldSnapshot snapshot);
    void step();

    [[nodiscard]] const SimulationHostConfig& config() const noexcept;
    [[nodiscard]] std::uint64_t tick() const noexcept;
    [[nodiscard]] double fixed_step_seconds() const noexcept;
    [[nodiscard]] std::size_t pending_projectile_command_count() const noexcept;
    [[nodiscard]] const ProjectileStateBatch& projectile_states() const noexcept;
    /// Events accumulate across fixed steps until explicitly drained. This is
    /// required when one render frame advances multiple catch-up ticks.
    [[nodiscard]] const ProjectileEventBatch& projectile_events() const noexcept;
    [[nodiscard]] ProjectileEventBatch drain_projectile_events();

private:
    SimulationHostConfig config_{};
    BallisticSystem ballistics_{};
    ProjectileCommandBatch pending_projectile_commands_{};
    ProjectileEventBatch pending_projectile_events_{};
};

} // namespace starfall::sim
