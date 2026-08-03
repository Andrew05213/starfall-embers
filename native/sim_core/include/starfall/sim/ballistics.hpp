#pragma once

#include "starfall/sim/gravity.hpp"

#include <cstdint>
#include <vector>

namespace starfall::sim {

using ProjectileId = std::uint64_t;

/// Gate 1's accepted shooting baseline. These values live here solely as a
/// migration regression fixture; future star-sequence content will submit them
/// through SpawnProjectileCommand instead of changing simulation code.
struct Gate1BallisticBaseline final {
    static constexpr std::uint32_t ticks_per_second = 30;
    static constexpr double projectile_speed = 1'200.0;
    static constexpr double projectile_lifetime = 0.55;
    static constexpr double projectile_gravity_scale = 1.3;

    [[nodiscard]] static constexpr PrimaryGravity gravity() noexcept {
        return {
            .center = {320.0, 10'020.0},
            .surface_radius = 10'000.0,
            .surface_acceleration = 320.0,
        };
    }
};

struct SpawnProjectileCommand final {
    /// Presentation-owned token copied into state and events for correlation.
    std::uint64_t request_id = 0;
    Vec2 position{};
    Vec2 velocity{};
    double lifetime_seconds = Gate1BallisticBaseline::projectile_lifetime;
    double gravity_scale = Gate1BallisticBaseline::projectile_gravity_scale;
    double collision_radius = 1.5;
};

enum class CollisionShape : std::uint8_t {
    circle,
    axis_aligned_box,
};

struct CollisionProxy final {
    std::uint64_t collider_id = 0;
    CollisionShape shape = CollisionShape::circle;
    Vec2 center{};
    /// Circle proxies use x as radius. Boxes use x/y as half extents.
    Vec2 half_extents{};
};

struct TerrainCollisionGrid final {
    Vec2 origin{};
    double cell_size = 1.0;
    std::uint32_t width = 0;
    std::uint32_t height = 0;
    std::vector<std::uint8_t> cells;
};

/// One fixed-step collision snapshot. Godot submits it as a coarse batch;
/// sim_core never calls back into the scene tree or reads individual pixels.
struct CollisionWorldSnapshot final {
    std::vector<CollisionProxy> colliders;
    TerrainCollisionGrid terrain;
};

enum class RetireReason : std::uint8_t {
    impact,
    external,
};

struct RetireProjectileCommand final {
    ProjectileId projectile_id = 0;
    RetireReason reason = RetireReason::external;
};

/// Coarse input boundary. Commands are consumed only at fixed-step boundaries.
struct ProjectileCommandBatch final {
    std::vector<SpawnProjectileCommand> spawns;
    std::vector<RetireProjectileCommand> retires;
};

struct ProjectileState final {
    ProjectileId projectile_id = 0;
    std::uint64_t request_id = 0;
    Vec2 previous_position{};
    Vec2 position{};
    Vec2 velocity{};
    double age_seconds = 0.0;
    double lifetime_seconds = 0.0;
    double gravity_scale = 0.0;
    double collision_radius = 0.0;
    std::uint32_t gravity_substeps = 0;
    bool gravity_sample_limit_reached = false;
};

struct ProjectileStateBatch final {
    std::uint64_t tick = 0;
    std::vector<ProjectileState> projectiles;
};

enum class ProjectileEventKind : std::uint8_t {
    spawned,
    expired,
    retired_on_impact,
    retired_external,
    rejected,
    hit_entity,
    hit_terrain,
};

struct ProjectileEvent final {
    ProjectileEventKind kind = ProjectileEventKind::rejected;
    ProjectileId projectile_id = 0;
    std::uint64_t request_id = 0;
    std::uint64_t tick = 0;
    std::uint64_t collider_id = 0;
    Vec2 position{};
    Vec2 velocity{};
};

struct ProjectileEventBatch final {
    std::uint64_t tick = 0;
    std::vector<ProjectileEvent> events;
};

class BallisticSystem final {
public:
    explicit BallisticSystem(
        std::uint32_t ticks_per_second = Gate1BallisticBaseline::ticks_per_second,
        PrimaryGravity gravity = Gate1BallisticBaseline::gravity()
    );
    explicit BallisticSystem(
        std::uint32_t ticks_per_second,
        GravityField* gravity_field
    );
    BallisticSystem(const BallisticSystem&) = delete;
    BallisticSystem& operator=(const BallisticSystem&) = delete;
    BallisticSystem(BallisticSystem&&) = delete;
    BallisticSystem& operator=(BallisticSystem&&) = delete;

    /// Queues one command batch for the next fixed step. A batch is intentionally
    /// moved in so bridge code can transfer many commands with one boundary
    /// crossing. Submitting another non-empty batch before step() is an error.
    void submit(ProjectileCommandBatch commands);
    void set_collision_world(CollisionWorldSnapshot snapshot);
    /// Clears all projectile state while retaining a caller-owned gravity
    /// field binding. This avoids copying a raw field pointer during host
    /// reconfiguration.
    void reset(std::uint32_t ticks_per_second, GravityField* gravity_field);
    void step();

    [[nodiscard]] std::uint32_t ticks_per_second() const noexcept;
    [[nodiscard]] double fixed_step_seconds() const noexcept;
    [[nodiscard]] std::uint64_t tick() const noexcept;
    [[nodiscard]] const PrimaryGravity& gravity() const noexcept;
    [[nodiscard]] const GravityField& gravity_field() const noexcept;
    [[nodiscard]] const ProjectileStateBatch& states() const noexcept;
    [[nodiscard]] const ProjectileEventBatch& events() const noexcept;

private:
    void process_retires();
    void process_spawns();
    void integrate_projectiles();
    void rebuild_state_batch();

    std::uint32_t ticks_per_second_ = Gate1BallisticBaseline::ticks_per_second;
    double fixed_step_seconds_ = 1.0 / Gate1BallisticBaseline::ticks_per_second;
    std::uint64_t tick_ = 0;
    ProjectileId next_projectile_id_ = 1;
    GravityField gravity_storage_{};
    GravityField* gravity_field_ = &gravity_storage_;
    ProjectileCommandBatch pending_commands_{};
    CollisionWorldSnapshot collision_world_{};
    std::vector<ProjectileState> active_projectiles_{};
    ProjectileStateBatch state_batch_{};
    ProjectileEventBatch event_batch_{};
};

} // namespace starfall::sim
