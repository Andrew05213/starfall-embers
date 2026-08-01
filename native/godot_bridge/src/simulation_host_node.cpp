#include "starfall/godot_bridge/simulation_host_node.hpp"

#include <godot_cpp/core/class_db.hpp>

#include <cmath>
#include <cstdint>
#include <exception>
#include <iomanip>
#include <limits>
#include <sstream>
#include <utility>
#include <variant>

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
        godot::D_METHOD("get_material_transport_version"),
        &StarfallSimulationHost::get_material_transport_version
    );
    godot::ClassDB::bind_method(
        godot::D_METHOD(
            "configure_material_world",
            "width",
            "height",
            "initial_material",
            "dto_version"
        ),
        &StarfallSimulationHost::configure_material_world
    );
    godot::ClassDB::bind_method(
        godot::D_METHOD(
            "submit_material_commands",
            "dto_version",
            "command_kinds",
            "center_xs",
            "center_ys",
            "radii",
            "material_ids"
        ),
        &StarfallSimulationHost::submit_material_commands
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
    godot::ClassDB::bind_method(
        godot::D_METHOD("drain_material_command_result_batch"),
        &StarfallSimulationHost::drain_material_command_result_batch
    );
    godot::ClassDB::bind_method(
        godot::D_METHOD("drain_dirty_chunk_batch"),
        &StarfallSimulationHost::drain_dirty_chunk_batch
    );
    godot::ClassDB::bind_method(
        godot::D_METHOD("get_material_checksum_hex"),
        &StarfallSimulationHost::get_material_checksum_hex
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

    auto config = host_.config();
    config.ticks_per_second = static_cast<std::uint32_t>(ticks_per_second);
    config.random_seed = static_cast<std::uint64_t>(random_seed);
    config.primary_gravity = {
        .center = to_sim(center),
        .surface_radius = surface_radius,
        .surface_acceleration = surface_acceleration,
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

std::int64_t StarfallSimulationHost::get_material_transport_version() const noexcept {
    return starfall::sim::material_transport_dto_version;
}

bool StarfallSimulationHost::configure_material_world(
    std::int64_t width,
    std::int64_t height,
    std::int64_t initial_material,
    std::int64_t dto_version
) {
    if (dto_version != starfall::sim::material_transport_dto_version
        || width <= 0 || height <= 0
        || width > std::numeric_limits<std::uint32_t>::max()
        || height > std::numeric_limits<std::uint32_t>::max()
        || initial_material < 0 || initial_material >= starfall::sim::material_count) {
        return false;
    }

    auto config = host_.config();
    config.material_world_width = static_cast<std::uint32_t>(width);
    config.material_world_height = static_cast<std::uint32_t>(height);
    config.initial_material = static_cast<starfall::sim::Material>(initial_material);
    try {
        host_ = starfall::sim::SimulationHost{config};
    } catch (const std::exception&) {
        return false;
    }
    return true;
}

bool StarfallSimulationHost::submit_material_commands(
    std::int64_t dto_version,
    const godot::PackedInt32Array& command_kinds,
    const godot::PackedInt64Array& center_xs,
    const godot::PackedInt64Array& center_ys,
    const godot::PackedInt64Array& radii,
    const godot::PackedInt32Array& material_ids
) {
    const std::int64_t count = command_kinds.size();
    if (dto_version != starfall::sim::material_transport_dto_version
        || center_xs.size() != count || center_ys.size() != count
        || radii.size() != count || material_ids.size() != count) {
        return false;
    }

    starfall::sim::MaterialCommandBatchDto batch;
    batch.commands.reserve(static_cast<std::size_t>(count));
    for (std::int64_t index = 0; index < count; ++index) {
        if (command_kinds[index] < 0 || command_kinds[index] > 1
            || radii[index] < 0
            || static_cast<std::uint64_t>(radii[index])
                > std::numeric_limits<std::uint32_t>::max()
            || material_ids[index] < 0
            || material_ids[index] >= starfall::sim::material_count) {
            return false;
        }
        if (command_kinds[index] == 0) {
            batch.commands.emplace_back(starfall::sim::PaintCircleCommand{
                .center_x = center_xs[index],
                .center_y = center_ys[index],
                .radius = static_cast<std::uint32_t>(radii[index]),
                .material = static_cast<starfall::sim::Material>(material_ids[index]),
            });
        } else {
            batch.commands.emplace_back(starfall::sim::ExtractCircleCommand{
                .center_x = center_xs[index],
                .center_y = center_ys[index],
                .radius = static_cast<std::uint32_t>(radii[index]),
            });
        }
    }

    try {
        host_.submit_material_commands(std::move(batch));
    } catch (const std::exception&) {
        return false;
    }
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

godot::Dictionary StarfallSimulationHost::drain_material_command_result_batch() {
    const auto batch = host_.drain_material_command_results();
    godot::PackedInt32Array command_kinds;
    godot::PackedInt64Array totals;
    godot::PackedInt64Array rock;
    godot::PackedInt64Array sand;
    godot::PackedInt64Array metal;

    for (const auto& command_result : batch.results) {
        if (std::holds_alternative<std::monostate>(command_result)) {
            command_kinds.append(0);
            totals.append(0);
            rock.append(0);
            sand.append(0);
            metal.append(0);
            continue;
        }
        const auto& extracted = std::get<starfall::sim::ExtractionStats>(command_result);
        command_kinds.append(1);
        totals.append(to_godot_id(extracted.total));
        rock.append(to_godot_id(extracted.rock));
        sand.append(to_godot_id(extracted.sand));
        metal.append(to_godot_id(extracted.metal));
    }

    godot::Dictionary result;
    result["version"] = static_cast<std::int64_t>(batch.version);
    result["tick"] = to_godot_id(batch.tick);
    result["command_kinds"] = command_kinds;
    result["totals"] = totals;
    result["rock"] = rock;
    result["sand"] = sand;
    result["metal"] = metal;
    return result;
}

godot::Dictionary StarfallSimulationHost::drain_dirty_chunk_batch() {
    const auto batch = host_.drain_dirty_chunks();
    godot::PackedInt32Array chunk_xs;
    godot::PackedInt32Array chunk_ys;
    godot::PackedInt32Array widths;
    godot::PackedInt32Array heights;
    godot::PackedInt64Array byte_offsets;
    godot::PackedByteArray cells;

    std::uint64_t byte_offset = 0;
    for (const auto& chunk : batch.chunks) {
        chunk_xs.append(static_cast<std::int32_t>(chunk.chunk_x));
        chunk_ys.append(static_cast<std::int32_t>(chunk.chunk_y));
        widths.append(static_cast<std::int32_t>(chunk.width));
        heights.append(static_cast<std::int32_t>(chunk.height));
        byte_offsets.append(to_godot_id(byte_offset));
        for (const auto cell : chunk.cells) {
            cells.append(cell);
        }
        byte_offset += chunk.cells.size();
    }

    godot::Dictionary result;
    result["version"] = static_cast<std::int64_t>(batch.version);
    result["tick"] = to_godot_id(batch.tick);
    result["chunk_size"] = static_cast<std::int64_t>(batch.chunk_size);
    result["chunk_xs"] = chunk_xs;
    result["chunk_ys"] = chunk_ys;
    result["widths"] = widths;
    result["heights"] = heights;
    result["byte_offsets"] = byte_offsets;
    result["cells"] = cells;
    return result;
}

godot::String StarfallSimulationHost::get_material_checksum_hex() const {
    std::ostringstream output;
    output << std::hex << std::setfill('0') << std::setw(16) << host_.material_checksum();
    return godot::String(output.str().c_str());
}

} // namespace starfall::godot_bridge
