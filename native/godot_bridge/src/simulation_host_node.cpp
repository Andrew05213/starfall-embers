#include "starfall/godot_bridge/simulation_host_node.hpp"

#include <godot_cpp/core/class_db.hpp>

#include <cmath>
#include <cstdint>
#include <limits>
#include <utility>

namespace starfall::godot_bridge {
namespace {

using starfall::sim::ProjectileCommandBatch;
using starfall::sim::RetireProjectileCommand;
using starfall::sim::RetireReason;
using starfall::sim::SpawnProjectileCommand;
using starfall::sim::Vec2;

[[nodiscard]] Vec2 to_sim(godot::Vector2 value) noexcept {
    return {static_cast<double>(value.x), static_cast<double>(value.y)};
}

[[nodiscard]] godot::Vector2 to_godot(Vec2 value) noexcept {
    return {static_cast<godot::real_t>(value.x), static_cast<godot::real_t>(value.y)};
}

[[nodiscard]] bool non_negative_id(std::int64_t value) noexcept {
    return value >= 0;
}

[[nodiscard]] std::int64_t to_godot_id(std::uint64_t value) noexcept {
    constexpr auto max = static_cast<std::uint64_t>(std::numeric_limits<std::int64_t>::max());
    return value <= max ? static_cast<std::int64_t>(value) : -1;
}

} // namespace

void StarfallSimulationHost::_bind_methods() {
    godot::ClassDB::bind_method(
        godot::D_METHOD("reset_to_gate1_baseline"),
        &StarfallSimulationHost::reset_to_gate1_baseline
    );
    godot::ClassDB::bind_method(
        godot::D_METHOD(
            "configure_primary_gravity",
            "center",
            "surface_radius",
            "surface_acceleration",
            "ticks_per_second",
            "random_seed"
        ),
        &StarfallSimulationHost::configure_primary_gravity
    );
    godot::ClassDB::bind_method(
        godot::D_METHOD(
            "submit_projectile_spawns",
            "request_ids",
            "positions",
            "velocities",
            "lifetimes",
            "gravity_scales",
            "collision_radii"
        ),
        &StarfallSimulationHost::submit_projectile_spawns
    );
    godot::ClassDB::bind_method(
        godot::D_METHOD(
            "submit_collision_world",
            "collider_ids",
            "shape_kinds",
            "centers",
            "half_extents",
            "terrain_cells",
            "terrain_width",
            "terrain_height",
            "terrain_origin",
            "terrain_cell_size"
        ),
        &StarfallSimulationHost::submit_collision_world
    );
    godot::ClassDB::bind_method(
        godot::D_METHOD("submit_projectile_retires", "projectile_ids", "reasons"),
        &StarfallSimulationHost::submit_projectile_retires
    );
    godot::ClassDB::bind_method(
        godot::D_METHOD("step_fixed"),
        &StarfallSimulationHost::step_fixed
    );
    godot::ClassDB::bind_method(
        godot::D_METHOD("get_tick"),
        &StarfallSimulationHost::get_tick
    );
    godot::ClassDB::bind_method(
        godot::D_METHOD("get_fixed_step_seconds"),
        &StarfallSimulationHost::get_fixed_step_seconds
    );
    godot::ClassDB::bind_method(
        godot::D_METHOD("get_random_seed"),
        &StarfallSimulationHost::get_random_seed
    );
    godot::ClassDB::bind_method(
        godot::D_METHOD("get_projectile_state_batch"),
        &StarfallSimulationHost::get_projectile_state_batch
    );
    godot::ClassDB::bind_method(
        godot::D_METHOD("drain_projectile_event_batch"),
        &StarfallSimulationHost::drain_projectile_event_batch
    );
}

void StarfallSimulationHost::reset_to_gate1_baseline() {
    host_ = starfall::sim::SimulationHost{};
}

bool StarfallSimulationHost::configure_primary_gravity(
    godot::Vector2 center,
    double surface_radius,
    double surface_acceleration,
    std::int64_t ticks_per_second,
    std::int64_t random_seed
) {
    if (!std::isfinite(center.x) || !std::isfinite(center.y)
        || !std::isfinite(surface_radius) || surface_radius <= 0.0
        || !std::isfinite(surface_acceleration) || surface_acceleration < 0.0
        || ticks_per_second <= 0
        || ticks_per_second > std::numeric_limits<std::uint32_t>::max()
        || random_seed < 0) {
        return false;
    }

    starfall::sim::SimulationHostConfig config{
        .ticks_per_second = static_cast<std::uint32_t>(ticks_per_second),
        .random_seed = static_cast<std::uint64_t>(random_seed),
        .primary_gravity = {
            .center = to_sim(center),
            .surface_radius = surface_radius,
            .surface_acceleration = surface_acceleration,
        },
    };
    host_ = starfall::sim::SimulationHost{config};
    return true;
}

bool StarfallSimulationHost::submit_projectile_spawns(
    const godot::PackedInt64Array& request_ids,
    const godot::PackedVector2Array& positions,
    const godot::PackedVector2Array& velocities,
    const godot::PackedFloat64Array& lifetimes,
    const godot::PackedFloat64Array& gravity_scales,
    const godot::PackedFloat64Array& collision_radii
) {
    const std::int64_t count = request_ids.size();
    if (positions.size() != count || velocities.size() != count
        || lifetimes.size() != count || gravity_scales.size() != count
        || collision_radii.size() != count) {
        return false;
    }

    ProjectileCommandBatch batch;
    batch.spawns.reserve(static_cast<std::size_t>(count));
    for (std::int64_t index = 0; index < count; ++index) {
        if (!non_negative_id(request_ids[index])) {
            return false;
        }
        batch.spawns.push_back(SpawnProjectileCommand{
            .request_id = static_cast<std::uint64_t>(request_ids[index]),
            .position = to_sim(positions[index]),
            .velocity = to_sim(velocities[index]),
            .lifetime_seconds = lifetimes[index],
            .gravity_scale = gravity_scales[index],
            .collision_radius = collision_radii[index],
        });
    }
    host_.submit_projectile_commands(std::move(batch));
    return true;
}

bool StarfallSimulationHost::submit_projectile_retires(
    const godot::PackedInt64Array& projectile_ids,
    const godot::PackedInt32Array& reasons
) {
    const std::int64_t count = projectile_ids.size();
    if (reasons.size() != count) {
        return false;
    }

    ProjectileCommandBatch batch;
    batch.retires.reserve(static_cast<std::size_t>(count));
    for (std::int64_t index = 0; index < count; ++index) {
        if (projectile_ids[index] <= 0 || reasons[index] < 0 || reasons[index] > 1) {
            return false;
        }
        batch.retires.push_back(RetireProjectileCommand{
            .projectile_id = static_cast<std::uint64_t>(projectile_ids[index]),
            .reason = reasons[index] == 0 ? RetireReason::impact : RetireReason::external,
        });
    }
    host_.submit_projectile_commands(std::move(batch));
    return true;
}

bool StarfallSimulationHost::submit_collision_world(
    const godot::PackedInt64Array& collider_ids,
    const godot::PackedInt32Array& shape_kinds,
    const godot::PackedVector2Array& centers,
    const godot::PackedVector2Array& half_extents,
    const godot::PackedByteArray& terrain_cells,
    std::int64_t terrain_width,
    std::int64_t terrain_height,
    godot::Vector2 terrain_origin,
    double terrain_cell_size
) {
    const std::int64_t count = collider_ids.size();
    if (shape_kinds.size() != count || centers.size() != count
        || half_extents.size() != count || terrain_width < 0 || terrain_height < 0
        || terrain_width > std::numeric_limits<std::uint32_t>::max()
        || terrain_height > std::numeric_limits<std::uint32_t>::max()
        || !std::isfinite(terrain_origin.x) || !std::isfinite(terrain_origin.y)
        || !std::isfinite(terrain_cell_size) || terrain_cell_size <= 0.0) {
        return false;
    }
    const auto expected_cells = static_cast<std::uint64_t>(terrain_width)
        * static_cast<std::uint64_t>(terrain_height);
    if (expected_cells != static_cast<std::uint64_t>(terrain_cells.size())) {
        return false;
    }

    starfall::sim::CollisionWorldSnapshot snapshot;
    snapshot.colliders.reserve(static_cast<std::size_t>(count));
    for (std::int64_t index = 0; index < count; ++index) {
        if (collider_ids[index] <= 0 || shape_kinds[index] < 0 || shape_kinds[index] > 1
            || !std::isfinite(centers[index].x) || !std::isfinite(centers[index].y)
            || !std::isfinite(half_extents[index].x)
            || !std::isfinite(half_extents[index].y)
            || half_extents[index].x < 0.0 || half_extents[index].y < 0.0) {
            return false;
        }
        snapshot.colliders.push_back({
            .collider_id = static_cast<std::uint64_t>(collider_ids[index]),
            .shape = shape_kinds[index] == 0
                ? starfall::sim::CollisionShape::circle
                : starfall::sim::CollisionShape::axis_aligned_box,
            .center = to_sim(centers[index]),
            .half_extents = to_sim(half_extents[index]),
        });
    }
    snapshot.terrain = {
        .origin = to_sim(terrain_origin),
        .cell_size = terrain_cell_size,
        .width = static_cast<std::uint32_t>(terrain_width),
        .height = static_cast<std::uint32_t>(terrain_height),
        .cells = {},
    };
    snapshot.terrain.cells.reserve(static_cast<std::size_t>(terrain_cells.size()));
    for (std::int64_t index = 0; index < terrain_cells.size(); ++index) {
        snapshot.terrain.cells.push_back(terrain_cells[index]);
    }
    host_.submit_collision_world(std::move(snapshot));
    return true;
}

void StarfallSimulationHost::step_fixed() {
    host_.step();
}

std::int64_t StarfallSimulationHost::get_tick() const noexcept {
    return to_godot_id(host_.tick());
}

double StarfallSimulationHost::get_fixed_step_seconds() const noexcept {
    return host_.fixed_step_seconds();
}

std::int64_t StarfallSimulationHost::get_random_seed() const noexcept {
    return to_godot_id(host_.config().random_seed);
}

godot::Dictionary StarfallSimulationHost::get_projectile_state_batch() const {
    const auto& batch = host_.projectile_states();
    godot::PackedInt64Array projectile_ids;
    godot::PackedInt64Array request_ids;
    godot::PackedVector2Array previous_positions;
    godot::PackedVector2Array positions;
    godot::PackedVector2Array velocities;
    godot::PackedFloat64Array ages;
    godot::PackedFloat64Array lifetimes;
    godot::PackedFloat64Array gravity_scales;

    for (const auto& projectile : batch.projectiles) {
        projectile_ids.append(to_godot_id(projectile.projectile_id));
        request_ids.append(to_godot_id(projectile.request_id));
        previous_positions.append(to_godot(projectile.previous_position));
        positions.append(to_godot(projectile.position));
        velocities.append(to_godot(projectile.velocity));
        ages.append(projectile.age_seconds);
        lifetimes.append(projectile.lifetime_seconds);
        gravity_scales.append(projectile.gravity_scale);
    }

    godot::Dictionary result;
    result["tick"] = to_godot_id(batch.tick);
    result["projectile_ids"] = projectile_ids;
    result["request_ids"] = request_ids;
    result["previous_positions"] = previous_positions;
    result["positions"] = positions;
    result["velocities"] = velocities;
    result["ages"] = ages;
    result["lifetimes"] = lifetimes;
    result["gravity_scales"] = gravity_scales;
    return result;
}

godot::Dictionary StarfallSimulationHost::drain_projectile_event_batch() {
    const auto batch = host_.drain_projectile_events();
    godot::PackedInt32Array kinds;
    godot::PackedInt64Array projectile_ids;
    godot::PackedInt64Array request_ids;
    godot::PackedInt64Array ticks;
    godot::PackedInt64Array collider_ids;
    godot::PackedVector2Array positions;
    godot::PackedVector2Array velocities;

    for (const auto& event : batch.events) {
        kinds.append(static_cast<std::int32_t>(event.kind));
        projectile_ids.append(to_godot_id(event.projectile_id));
        request_ids.append(to_godot_id(event.request_id));
        ticks.append(to_godot_id(event.tick));
        collider_ids.append(to_godot_id(event.collider_id));
        positions.append(to_godot(event.position));
        velocities.append(to_godot(event.velocity));
    }

    godot::Dictionary result;
    result["tick"] = to_godot_id(batch.tick);
    result["kinds"] = kinds;
    result["projectile_ids"] = projectile_ids;
    result["request_ids"] = request_ids;
    result["ticks"] = ticks;
    result["collider_ids"] = collider_ids;
    result["positions"] = positions;
    result["velocities"] = velocities;
    return result;
}

} // namespace starfall::godot_bridge
