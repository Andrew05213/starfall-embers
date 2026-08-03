#include "starfall/sim/gravity.hpp"
#include "starfall/sim/simulation_host.hpp"

#include <cassert>
#include <cmath>
#include <cstdint>
#include <limits>
#include <stdexcept>

namespace {

using starfall::sim::GravityField;
using starfall::sim::GravityFieldKind;
using starfall::sim::GravitySourceCommand;
using starfall::sim::GravitySourceCommandBatch;
using starfall::sim::GravitySourceCommandKind;
using starfall::sim::PrimaryGravity;
using starfall::sim::SimulationHost;
using starfall::sim::Vec2;
using starfall::sim::gravity_transport_dto_version;

[[nodiscard]] bool near(double actual, double expected, double tolerance = 1.0e-9) {
    return std::abs(actual - expected) <= tolerance;
}

void test_primary_curve_and_zero_gravity() {
    const PrimaryGravity gravity = {
        .center = {0.0, 0.0},
        .surface_radius = 100.0,
        .surface_acceleration = 200.0,
    };
    assert(near(gravity.magnitude_at_distance(0.0), 0.0));
    assert(near(gravity.magnitude_at_distance(50.0), 100.0));
    assert(near(gravity.magnitude_at_distance(100.0), 200.0));
    assert(near(gravity.magnitude_at_distance(200.0), 50.0));
    assert(near(gravity.acceleration_at({0.0, 0.0}).x, 0.0));
    assert(near(gravity.acceleration_at({100.0, 0.0}).x, -200.0));
    assert(near(gravity.acceleration_at({0.0, 200.0}).y, -50.0));
}

GravitySourceCommand add_radial(std::uint64_t id) {
    return {
        .kind = GravitySourceCommandKind::add,
        .request_id = id,
        .source = {
            .source_id = id,
            .kind = GravityFieldKind::radial_falloff,
            .center = {0.0, 0.0},
            .strength = 100.0,
            .radius = 100.0,
        },
    };
}

void test_local_fields_are_bounded_and_stable() {
    GravityField field(30, PrimaryGravity{
        .center = {10'000.0, 10'000.0},
        .surface_radius = 10'000.0,
        .surface_acceleration = 0.0,
    });
    GravitySourceCommandBatch commands;
    commands.commands.push_back(add_radial(20));
    commands.commands.push_back({
        .kind = GravitySourceCommandKind::add,
        .request_id = 10,
        .source = {
            .source_id = 10,
            .kind = GravityFieldKind::uniform_vector,
            .center = {0.0, 0.0},
            .vector = {0.0, 25.0},
            .radius = 20.0,
        },
    });
    field.apply(std::move(commands));
    assert(field.sources().size() == 2);
    assert(field.sources()[0].source_id == 10);
    assert(field.sources()[1].source_id == 20);

    const auto inside = field.sample({0.0, 50.0});
    assert(inside.acceleration.y < -40.0);
    assert(inside.dominant_source_id == 20);
    const auto outside = field.sample({0.0, 200.0});
    assert(near(outside.acceleration.x, 0.0));
    assert(near(outside.acceleration.y, 0.0));

    const auto batch = field.sample_batch({{0.0, 0.0}, {0.0, 200.0}});
    assert(batch.size() == 2);
    assert(near(batch[1].magnitude, 0.0));
}

void test_commands_are_atomic_and_expire_on_ticks() {
    GravityField field;
    const auto before = field.checksum();
    bool rejected = false;
    try {
        field.apply({
            .version = gravity_transport_dto_version + 1,
            .commands = {add_radial(1)},
        });
    } catch (const std::invalid_argument&) {
        rejected = true;
    }
    assert(rejected);
    assert(field.source_count() == 0);
    assert(field.checksum() == before);

    auto expiring = add_radial(3);
    expiring.source.expires_at_tick = 2;
    field.apply({.commands = {expiring}});
    assert(field.source_count() == 1);
    field.advance_tick();
    assert(field.source_count() == 1);
    field.advance_tick();
    assert(field.source_count() == 0);

    auto duplicate = add_radial(4);
    field.apply({.commands = {duplicate}});
    bool duplicate_rejected = false;
    try {
        field.apply({.commands = {duplicate}});
    } catch (const std::invalid_argument&) {
        duplicate_rejected = true;
    }
    assert(duplicate_rejected);
    assert(field.source_count() == 1);
}

void test_shared_host_field_and_replay() {
    SimulationHost first;
    SimulationHost second;
    GravitySourceCommandBatch commands;
    commands.commands.push_back(add_radial(9));
    first.submit_gravity_source_commands(commands);
    second.submit_gravity_source_commands(commands);
    assert(first.pending_gravity_source_command_count() == 1);
    first.step();
    second.step();
    assert(first.gravity_field().tick() == 1);
    assert(first.gravity_checksum() == second.gravity_checksum());
    const auto first_sample = first.gravity_field().sample({0.0, 50.0});
    const auto second_sample = second.gravity_field().sample({0.0, 50.0});
    assert(near(first_sample.acceleration.x, second_sample.acceleration.x));
    assert(near(first_sample.acceleration.y, second_sample.acceleration.y));
}

} // namespace

int main() {
    test_primary_curve_and_zero_gravity();
    test_local_fields_are_bounded_and_stable();
    test_commands_are_atomic_and_expire_on_ticks();
    test_shared_host_field_and_replay();
    return 0;
}
