#include "starfall/sim/simulation_host.hpp"

#include <cassert>
#include <cmath>
#include <utility>

namespace {

using starfall::sim::Gate1BallisticBaseline;
using starfall::sim::ProjectileCommandBatch;
using starfall::sim::ProjectileEventKind;
using starfall::sim::RetireProjectileCommand;
using starfall::sim::RetireReason;
using starfall::sim::SimulationHost;

[[nodiscard]] bool near(double actual, double expected, double tolerance = 1.0e-9) {
    return std::abs(actual - expected) <= tolerance;
}

ProjectileCommandBatch spawn_batch(std::uint64_t request_id, double x) {
    ProjectileCommandBatch commands;
    commands.spawns.push_back({
        .request_id = request_id,
        .position = {x, -60.0},
        .velocity = {Gate1BallisticBaseline::projectile_speed, 0.0},
        .lifetime_seconds = Gate1BallisticBaseline::projectile_lifetime,
        .gravity_scale = Gate1BallisticBaseline::projectile_gravity_scale,
    });
    return commands;
}

void test_default_gate1_configuration() {
    SimulationHost host;
    assert(host.config().ticks_per_second == 30);
    assert(host.config().random_seed == 0x51a7e11ULL);
    assert(near(host.config().primary_gravity.center.x, 320.0));
    assert(near(host.config().primary_gravity.center.y, 10'020.0));
    assert(near(host.config().primary_gravity.surface_radius, 10'000.0));
    assert(near(host.config().primary_gravity.surface_acceleration, 320.0));
    assert(near(host.fixed_step_seconds(), 1.0 / 30.0));
    assert(host.tick() == 0);
}

void test_coalesced_command_batches_and_state_readback() {
    SimulationHost host;
    host.submit_projectile_commands(spawn_batch(10, 150.0));
    host.submit_projectile_commands(spawn_batch(11, 170.0));
    assert(host.pending_projectile_command_count() == 2);

    host.step();
    assert(host.pending_projectile_command_count() == 0);
    assert(host.tick() == 1);
    assert(host.projectile_states().tick == 1);
    assert(host.projectile_events().tick == 1);
    assert(host.projectile_states().projectiles.size() == 2);
    assert(host.projectile_events().events.size() == 2);
    assert(host.projectile_states().projectiles[0].request_id == 10);
    assert(host.projectile_states().projectiles[1].request_id == 11);
    assert(host.projectile_events().events[0].kind == ProjectileEventKind::spawned);
    assert(host.projectile_events().events[1].kind == ProjectileEventKind::spawned);
    const auto spawn_events = host.drain_projectile_events();
    assert(spawn_events.events.size() == 2);
    assert(host.projectile_events().events.empty());

    const auto first_position = host.projectile_states().projectiles[0].position;
    host.step();
    assert(host.tick() == 2);
    assert(host.projectile_events().events.empty());
    assert(host.projectile_states().projectiles[0].position.x > first_position.x);
    assert(host.projectile_states().projectiles[0].position.y > first_position.y);
}

void test_retire_batch_round_trip() {
    SimulationHost host;
    host.submit_projectile_commands(spawn_batch(77, 160.0));
    host.step();
    const auto projectile_id = host.projectile_states().projectiles.front().projectile_id;
    const auto spawn_events = host.drain_projectile_events();
    assert(spawn_events.events.size() == 1);

    ProjectileCommandBatch commands;
    commands.retires.push_back(RetireProjectileCommand{
        .projectile_id = projectile_id,
        .reason = RetireReason::impact,
    });
    host.submit_projectile_commands(std::move(commands));
    host.step();

    assert(host.projectile_states().projectiles.empty());
    assert(host.projectile_events().events.size() == 1);
    const auto& event = host.projectile_events().events.front();
    assert(event.kind == ProjectileEventKind::retired_on_impact);
    assert(event.projectile_id == projectile_id);
    assert(event.request_id == 77);
    assert(event.tick == host.tick());
}

void test_catch_up_steps_accumulate_events_until_drain() {
    SimulationHost host;
    auto commands = spawn_batch(88, 160.0);
    commands.spawns.front().lifetime_seconds = 0.04;
    host.submit_projectile_commands(std::move(commands));

    // One render frame may need multiple fixed steps. The spawned event from
    // tick 1 must survive the expiry event emitted on tick 2.
    host.step();
    host.step();
    assert(host.tick() == 2);
    assert(host.projectile_states().projectiles.empty());
    assert(host.projectile_events().tick == 2);
    assert(host.projectile_events().events.size() == 2);
    assert(host.projectile_events().events[0].kind == ProjectileEventKind::spawned);
    assert(host.projectile_events().events[0].tick == 1);
    assert(host.projectile_events().events[1].kind == ProjectileEventKind::expired);
    assert(host.projectile_events().events[1].tick == 2);

    const auto events = host.drain_projectile_events();
    assert(events.events.size() == 2);
    assert(host.projectile_events().tick == 2);
    assert(host.projectile_events().events.empty());
}

void test_two_hosts_are_deterministic() {
    SimulationHost first;
    SimulationHost second;
    for (std::uint64_t request_id = 1; request_id <= 3; ++request_id) {
        const auto commands = spawn_batch(request_id, 140.0 + 15.0 * request_id);
        first.submit_projectile_commands(commands);
        second.submit_projectile_commands(commands);
    }
    for (int step = 0; step < 12; ++step) {
        first.step();
        second.step();
    }

    const auto& lhs = first.projectile_states();
    const auto& rhs = second.projectile_states();
    assert(lhs.tick == rhs.tick);
    assert(lhs.projectiles.size() == rhs.projectiles.size());
    for (std::size_t index = 0; index < lhs.projectiles.size(); ++index) {
        assert(lhs.projectiles[index].projectile_id == rhs.projectiles[index].projectile_id);
        assert(lhs.projectiles[index].request_id == rhs.projectiles[index].request_id);
        assert(near(lhs.projectiles[index].position.x, rhs.projectiles[index].position.x));
        assert(near(lhs.projectiles[index].position.y, rhs.projectiles[index].position.y));
        assert(near(lhs.projectiles[index].velocity.x, rhs.projectiles[index].velocity.x));
        assert(near(lhs.projectiles[index].velocity.y, rhs.projectiles[index].velocity.y));
    }
}

} // namespace

int main() {
    test_default_gate1_configuration();
    test_coalesced_command_batches_and_state_readback();
    test_retire_batch_round_trip();
    test_catch_up_steps_accumulate_events_until_drain();
    test_two_hosts_are_deterministic();
    return 0;
}
