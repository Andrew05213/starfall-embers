#pragma once

#include "starfall/sim/simulation_host.hpp"

#include <godot_cpp/classes/node.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_float64_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/packed_int64_array.hpp>
#include <godot_cpp/variant/packed_vector2_array.hpp>
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
        std::int64_t ticks_per_second
    );

    bool submit_projectile_spawns(
        const godot::PackedInt64Array& request_ids,
        const godot::PackedVector2Array& positions,
        const godot::PackedVector2Array& velocities,
        const godot::PackedFloat64Array& lifetimes,
        const godot::PackedFloat64Array& gravity_scales
    );
    bool submit_projectile_retires(
        const godot::PackedInt64Array& projectile_ids,
        const godot::PackedInt32Array& reasons
    );
    void step_fixed();

    [[nodiscard]] std::int64_t get_tick() const noexcept;
    [[nodiscard]] double get_fixed_step_seconds() const noexcept;
    [[nodiscard]] godot::Dictionary get_projectile_state_batch() const;
    /// Returns all events since the previous drain and consumes that queue.
    [[nodiscard]] godot::Dictionary drain_projectile_event_batch();

protected:
    static void _bind_methods();

private:
    starfall::sim::SimulationHost host_{};
};

} // namespace starfall::godot_bridge
