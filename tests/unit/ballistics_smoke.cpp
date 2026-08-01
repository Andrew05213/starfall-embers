#include "starfall/sim/ballistics.hpp"

#include <cassert>
#include <cmath>
#include <cstddef>
#include <limits>
#include <utility>

namespace {

using starfall::sim::BallisticSystem;
using starfall::sim::Gate1BallisticBaseline;
using starfall::sim::CollisionProxy;
using starfall::sim::CollisionShape;
using starfall::sim::CollisionWorldSnapshot;
using starfall::sim::PrimaryGravity;
using starfall::sim::ProjectileCommandBatch;
using starfall::sim::ProjectileEventKind;
using starfall::sim::RetireProjectileCommand;
using starfall::sim::RetireReason;
using starfall::sim::SpawnProjectileCommand;
using starfall::sim::Vec2;

[[nodiscard]] bool near(double actual, double expected, double tolerance = 1.0e-9) {
    return std::abs(actual - expected) <= tolerance;
}

void test_gate1_baseline_constants() {
    const auto gravity = Gate1BallisticBaseline::gravity();
    assert(Gate1BallisticBaseline::ticks_per_second == 30);
    assert(near(gravity.center.x, 320.0));
    assert(near(gravity.center.y, 10'020.0));
    assert(near(gravity.surface_radius, 10'000.0));
    assert(near(gravity.surface_acceleration, 320.0));
    assert(near(Gate1BallisticBaseline::projectile_speed, 1'200.0));
    assert(near(Gate1BallisticBaseline::projectile_lifetime, 0.55));
    assert(near(Gate1BallisticBaseline::projectile_gravity_scale, 1.3));
}

void test_primary_gravity_curve() {
    const PrimaryGravity gravity = Gate1BallisticBaseline::gravity();
    assert(near(gravity.magnitude_at_distance(0.0), 0.0));
    assert(near(gravity.magnitude_at_distance(5'000.0), 160.0));
    assert(near(gravity.magnitude_at_distance(10'000.0), 320.0));
    assert(near(gravity.magnitude_at_distance(20'000.0), 80.0));
    assert(near(gravity.magnitude_at_distance(40'000.0), 20.0));

    const auto at_surface = gravity.acceleration_at({320.0, 20.0});
    assert(near(at_surface.x, 0.0));
    assert(near(at_surface.y, 320.0));
    const auto at_core = gravity.acceleration_at(gravity.center);
    assert(near(at_core.x, 0.0));
    assert(near(at_core.y, 0.0));
}

ProjectileCommandBatch gate1_shot(std::uint64_t request_id = 7) {
    ProjectileCommandBatch commands;
    commands.spawns.push_back({
        .request_id = request_id,
        .position = {160.0, -60.0},
        .velocity = {Gate1BallisticBaseline::projectile_speed, 0.0},
        .lifetime_seconds = Gate1BallisticBaseline::projectile_lifetime,
        .gravity_scale = Gate1BallisticBaseline::projectile_gravity_scale,
    });
    return commands;
}

void test_fixed_step_and_batch_state() {
    BallisticSystem system;
    assert(system.ticks_per_second() == 30);
    assert(near(system.fixed_step_seconds(), 1.0 / 30.0));
    assert(system.states().projectiles.empty());

    system.submit(gate1_shot());
    system.step();
    assert(system.tick() == 1);
    assert(system.events().tick == 1);
    assert(system.events().events.size() == 1);
    assert(system.events().events.front().kind == ProjectileEventKind::spawned);
    assert(system.states().tick == 1);
    assert(system.states().projectiles.size() == 1);

    const auto& state = system.states().projectiles.front();
    assert(state.request_id == 7);
    assert(near(state.previous_position.x, 160.0));
    assert(near(state.previous_position.y, -60.0));
    assert(state.position.x > state.previous_position.x);
    assert(state.position.y > state.previous_position.y);
    assert(near(state.age_seconds, 1.0 / 30.0));
}

void test_gate1_one_view_drop_and_lifetime() {
    BallisticSystem system;
    system.submit(gate1_shot(42));

    // Eight 30 Hz steps equal the production smoke test's sixteen 60 Hz
    // integration steps and move the 1200 px/s shot approximately 320 px.
    for (int step = 0; step < 8; ++step) {
        system.step();
    }
    assert(system.states().projectiles.size() == 1);
    const auto& state = system.states().projectiles.front();
    const double displacement_x = state.position.x - 160.0;
    const double displacement_y = state.position.y + 60.0;
    assert(displacement_x > 315.0 && displacement_x < 325.0);
    assert(displacement_y > 12.0 && displacement_y < 20.0);

    while (!system.states().projectiles.empty()) {
        system.step();
    }
    assert(system.tick() == 17);
    assert(system.events().events.size() == 1);
    const auto& event = system.events().events.front();
    assert(event.kind == ProjectileEventKind::expired);
    assert(event.request_id == 42);
    // The partial final step must stop exactly at the accepted 0.55 s lifetime.
    assert(event.position.x > 810.0 && event.position.x < 825.0);
}

void test_deterministic_batch_order() {
    BallisticSystem first;
    BallisticSystem second;
    auto commands = gate1_shot(100);
    auto second_shot = gate1_shot(101).spawns.front();
    second_shot.position.x += 10.0;
    commands.spawns.push_back(second_shot);
    first.submit(commands);
    second.submit(commands);

    for (int step = 0; step < 10; ++step) {
        first.step();
        second.step();
    }
    assert(first.states().projectiles.size() == second.states().projectiles.size());
    for (std::size_t index = 0; index < first.states().projectiles.size(); ++index) {
        const auto& lhs = first.states().projectiles[index];
        const auto& rhs = second.states().projectiles[index];
        assert(lhs.projectile_id == rhs.projectile_id);
        assert(lhs.request_id == rhs.request_id);
        assert(near(lhs.position.x, rhs.position.x));
        assert(near(lhs.position.y, rhs.position.y));
        assert(near(lhs.velocity.x, rhs.velocity.x));
        assert(near(lhs.velocity.y, rhs.velocity.y));
    }
}

void test_batch_retire_contract() {
    BallisticSystem system;
    auto commands = gate1_shot(200);
    commands.spawns.push_back(gate1_shot(201).spawns.front());
    system.submit(std::move(commands));
    system.step();
    assert(system.states().projectiles.size() == 2);

    const auto retired_id = system.states().projectiles.front().projectile_id;
    ProjectileCommandBatch retire_commands;
    retire_commands.retires.push_back(RetireProjectileCommand{
        .projectile_id = retired_id,
        .reason = RetireReason::impact,
    });
    system.submit(std::move(retire_commands));
    system.step();

    assert(system.states().projectiles.size() == 1);
    assert(system.states().projectiles.front().request_id == 201);
    assert(system.events().events.size() == 1);
    assert(system.events().events.front().kind == ProjectileEventKind::retired_on_impact);
    assert(system.events().events.front().projectile_id == retired_id);
    assert(system.events().events.front().request_id == 200);
}

void test_large_spawn_batch_keeps_submission_order() {
    constexpr std::size_t projectile_count = 1'024;
    BallisticSystem system;
    ProjectileCommandBatch commands;
    commands.spawns.reserve(projectile_count);
    for (std::size_t index = 0; index < projectile_count; ++index) {
        auto command = gate1_shot(static_cast<std::uint64_t>(index + 1)).spawns.front();
        command.position.x += static_cast<double>(index);
        commands.spawns.push_back(command);
    }
    system.submit(std::move(commands));
    system.step();

    assert(system.states().projectiles.size() == projectile_count);
    assert(system.events().events.size() == projectile_count);
    for (std::size_t index = 0; index < projectile_count; ++index) {
        const auto& state = system.states().projectiles[index];
        assert(state.projectile_id == index + 1);
        assert(state.request_id == index + 1);
        assert(system.events().events[index].kind == ProjectileEventKind::spawned);
        assert(system.events().events[index].projectile_id == index + 1);
    }
}

void test_invalid_spawn_is_rejected() {
    BallisticSystem system;
    ProjectileCommandBatch commands;
    commands.spawns.push_back({
        .request_id = 99,
        .lifetime_seconds = 0.0,
    });
    system.submit(std::move(commands));
    system.step();
    assert(system.states().projectiles.empty());
    assert(system.events().events.size() == 1);
    assert(system.events().events.front().kind == ProjectileEventKind::rejected);
    assert(system.events().events.front().request_id == 99);

    ProjectileCommandBatch non_finite_commands;
    non_finite_commands.spawns.push_back({
        .request_id = 100,
        .position = {std::numeric_limits<double>::quiet_NaN(), 0.0},
    });
    system.submit(std::move(non_finite_commands));
    system.step();
    assert(system.states().projectiles.empty());
    assert(system.events().events.size() == 1);
    assert(system.events().events.front().kind == ProjectileEventKind::rejected);
    assert(system.events().events.front().request_id == 100);
}

void test_impact_retirement_batch() {
    BallisticSystem system;
    system.submit(gate1_shot(314));
    system.step();
    const auto projectile_id = system.states().projectiles.front().projectile_id;

    ProjectileCommandBatch commands;
    commands.retires.push_back(RetireProjectileCommand{
        .projectile_id = projectile_id,
        .reason = RetireReason::impact,
    });
    system.submit(std::move(commands));
    system.step();

    assert(system.states().projectiles.empty());
    assert(system.events().events.size() == 1);
    assert(system.events().events.front().kind == ProjectileEventKind::retired_on_impact);
    assert(system.events().events.front().projectile_id == projectile_id);
    assert(system.events().events.front().request_id == 314);
}

BallisticSystem flat_ballistics() {
    return BallisticSystem(30, PrimaryGravity{
        .center = {0.0, 1'000.0},
        .surface_radius = 1'000.0,
        .surface_acceleration = 0.0,
    });
}

ProjectileCommandBatch flat_shot(std::uint64_t request_id = 1) {
    ProjectileCommandBatch commands;
    commands.spawns.push_back({
        .request_id = request_id,
        .position = {0.0, 0.0},
        .velocity = {300.0, 0.0},
        .lifetime_seconds = 1.0,
        .gravity_scale = 0.0,
        .collision_radius = 1.0,
    });
    return commands;
}

void test_native_entity_hit_is_authoritative_and_stable() {
    auto system = flat_ballistics();
    CollisionWorldSnapshot world;
    // Deliberately submit the larger ID first. Equal-time hits choose the
    // stable lower collider ID, independent of scene/group iteration order.
    world.colliders.push_back(CollisionProxy{
        .collider_id = 22,
        .shape = CollisionShape::circle,
        .center = {5.0, 0.0},
        .half_extents = {1.0, 1.0},
    });
    world.colliders.push_back(CollisionProxy{
        .collider_id = 11,
        .shape = CollisionShape::circle,
        .center = {5.0, 0.0},
        .half_extents = {1.0, 1.0},
    });
    system.set_collision_world(std::move(world));
    system.submit(flat_shot(401));
    system.step();

    assert(system.states().projectiles.empty());
    assert(system.events().events.size() == 2);
    assert(system.events().events[0].kind == ProjectileEventKind::spawned);
    const auto& hit = system.events().events[1];
    assert(hit.kind == ProjectileEventKind::hit_entity);
    assert(hit.request_id == 401);
    assert(hit.collider_id == 11);
    assert(near(hit.position.x, 3.0));
}

void test_native_terrain_grid_hit_precedes_lifetime() {
    auto system = flat_ballistics();
    CollisionWorldSnapshot world;
    world.terrain = {
        .origin = {0.0, 0.0},
        .cell_size = 1.0,
        .width = 4,
        .height = 1,
        .cells = {0, 0, 1, 0},
    };
    system.set_collision_world(std::move(world));
    auto commands = flat_shot(402);
    commands.spawns.front().collision_radius = 0.0;
    system.submit(std::move(commands));
    system.step();

    assert(system.states().projectiles.empty());
    assert(system.events().events.size() == 2);
    const auto& hit = system.events().events[1];
    assert(hit.kind == ProjectileEventKind::hit_terrain);
    assert(hit.request_id == 402);
    assert(hit.collider_id == 0);
    assert(hit.position.x >= 2.0 && hit.position.x < 3.0);
}

} // namespace

int main() {
    test_gate1_baseline_constants();
    test_primary_gravity_curve();
    test_fixed_step_and_batch_state();
    test_gate1_one_view_drop_and_lifetime();
    test_deterministic_batch_order();
    test_batch_retire_contract();
    test_large_spawn_batch_keeps_submission_order();
    test_invalid_spawn_is_rejected();
    test_impact_retirement_batch();
    test_native_entity_hit_is_authoritative_and_stable();
    test_native_terrain_grid_hit_precedes_lifetime();
    return 0;
}
