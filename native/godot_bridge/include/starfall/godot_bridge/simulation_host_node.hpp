#pragma once

#include "starfall/sim/simulation_host.hpp"

#include <godot_cpp/classes/node.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/packed_float64_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/packed_int64_array.hpp>
#include <godot_cpp/variant/packed_vector2_array.hpp>
#include <godot_cpp/variant/string.hpp>
#include <godot_cpp/variant/vector2.hpp>

namespace starfall::godot_bridge {

/// Coarse Godot-facing adapter for the engine-independent SimulationHost.
///
/// Every method crosses the extension boundary once for a whole command or
/// snapshot batch. Presentation code must not use this class as a per-pixel or
/// per-projectile callback surface.
class StarfallSimulationHost final : public godot::Node {
    GDCLASS(StarfallSimulationHost, godot::Node)

public:
    StarfallSimulationHost() = default;

    void reset_to_gate1_baseline();
    bool configure_primary_gravity(
        godot::Vector2 center,
        double surface_radius,
        double surface_acceleration,
        std::int64_t ticks_per_second,
        std::int64_t random_seed
    );

    bool submit_projectile_spawns(
        const godot::PackedInt64Array& request_ids,
        const godot::PackedVector2Array& positions,
        const godot::PackedVector2Array& velocities,
        const godot::PackedFloat64Array& lifetimes,
        const godot::PackedFloat64Array& gravity_scales,
        const godot::PackedFloat64Array& collision_radii
    );
    bool submit_collision_world(
        const godot::PackedInt64Array& collider_ids,
        const godot::PackedInt32Array& shape_kinds,
        const godot::PackedVector2Array& centers,
        const godot::PackedVector2Array& half_extents,
        const godot::PackedByteArray& terrain_cells,
        std::int64_t terrain_width,
        std::int64_t terrain_height,
        godot::Vector2 terrain_origin,
        double terrain_cell_size
    );
    bool submit_projectile_retires(
        const godot::PackedInt64Array& projectile_ids,
        const godot::PackedInt32Array& reasons
    );
    [[nodiscard]] std::int64_t get_material_transport_version() const noexcept;
    [[nodiscard]] std::int64_t get_gravity_transport_version() const noexcept;
    bool submit_gravity_source_commands(
        std::int64_t dto_version,
        const godot::PackedInt32Array& command_kinds,
        const godot::PackedInt32Array& field_kinds,
        const godot::PackedInt64Array& request_ids,
        const godot::PackedInt64Array& source_ids,
        const godot::PackedVector2Array& centers,
        const godot::PackedVector2Array& vectors,
        const godot::PackedFloat64Array& strengths,
        const godot::PackedFloat64Array& radii,
        const godot::PackedInt64Array& expires_at_ticks
    );
    [[nodiscard]] godot::Dictionary drain_gravity_source_command_result_batch();
    [[nodiscard]] godot::Dictionary sample_gravity_batch(
        std::int64_t dto_version,
        const godot::PackedInt64Array& request_ids,
        const godot::PackedVector2Array& positions
    ) const;
    bool configure_material_world(
        std::int64_t width,
        std::int64_t height,
        std::int64_t initial_material,
        std::int64_t dto_version
    );
    bool submit_material_commands(
        std::int64_t dto_version,
        const godot::PackedInt32Array& command_kinds,
        const godot::PackedInt64Array& center_xs,
        const godot::PackedInt64Array& center_ys,
        const godot::PackedInt64Array& radii,
        const godot::PackedInt32Array& material_ids
    );
    void step_fixed();

    [[nodiscard]] std::int64_t get_tick() const noexcept;
    [[nodiscard]] double get_fixed_step_seconds() const noexcept;
    [[nodiscard]] std::int64_t get_random_seed() const noexcept;
    [[nodiscard]] godot::Dictionary get_projectile_state_batch() const;
    /// Returns all events since the previous drain and consumes that queue.
    [[nodiscard]] godot::Dictionary drain_projectile_event_batch();
    [[nodiscard]] godot::Dictionary drain_material_command_result_batch();
    [[nodiscard]] godot::Dictionary drain_dirty_chunk_batch();
    [[nodiscard]] godot::String get_material_checksum_hex() const;
    [[nodiscard]] godot::String get_gravity_checksum_hex() const;

protected:
    static void _bind_methods();

private:
    starfall::sim::SimulationHost host_{};
    starfall::sim::GravitySourceCommandResultBatch gravity_command_results_{};
};

} // namespace starfall::godot_bridge
