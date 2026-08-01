extends SceneTree


func _init() -> void:
	var host := StarfallSimulationHost.new()
	assert(is_equal_approx(host.get_fixed_step_seconds(), 1.0 / 30.0))

	var accepted := host.submit_projectile_spawns(
		PackedInt64Array([17]),
		PackedVector2Array([Vector2(320.0, 20.0)]),
		PackedVector2Array([Vector2(1200.0, 0.0)]),
		PackedFloat64Array([0.55]),
		PackedFloat64Array([1.3]),
		PackedFloat64Array([1.5])
	)
	assert(accepted)
	host.step_fixed()

	var states: Dictionary = host.get_projectile_state_batch()
	assert(states.tick == 1)
	assert(states.projectile_ids.size() == 1)
	assert(states.request_ids[0] == 17)
	assert(states.positions[0].x > 320.0)
	assert(states.positions[0].y > 20.0)

	var events: Dictionary = host.drain_projectile_event_batch()
	assert(events.tick == 1)
	assert(events.kinds.size() == 1)
	assert(events.kinds[0] == 0)
	assert(host.drain_projectile_event_batch().kinds.is_empty())

	host.reset_to_gate1_baseline()
	assert(host.submit_projectile_spawns(
		PackedInt64Array([18]),
		PackedVector2Array([Vector2(320.0, 20.0)]),
		PackedVector2Array([Vector2(1200.0, 0.0)]),
		PackedFloat64Array([0.04]),
		PackedFloat64Array([1.3]),
		PackedFloat64Array([1.5])
	))
	host.step_fixed()
	host.step_fixed()
	var catch_up_events: Dictionary = host.drain_projectile_event_batch()
	assert(catch_up_events.tick == 2)
	assert(catch_up_events.kinds == PackedInt32Array([0, 1]))
	assert(catch_up_events.ticks == PackedInt64Array([1, 2]))
	assert(host.get_projectile_state_batch().projectile_ids.is_empty())

	assert(not host.configure_primary_gravity(Vector2.ZERO, 0.0, 320.0, 30, 0x51A7E11))
	assert(host.configure_primary_gravity(Vector2(320.0, 10020.0), 10000.0, 320.0, 30, 0x51A7E11))
	assert(host.get_random_seed() == 0x51A7E11)
	assert(not host.submit_projectile_spawns(
		PackedInt64Array([19]),
		PackedVector2Array(),
		PackedVector2Array([Vector2(1200.0, 0.0)]),
		PackedFloat64Array([0.55]),
		PackedFloat64Array([1.3]),
		PackedFloat64Array([1.5])
	))
	# Structurally valid batches are accepted as a unit. Individual physical
	# commands are then either spawned or rejected by sim_core at the next tick.
	assert(host.submit_projectile_spawns(
		PackedInt64Array([20, 21]),
		PackedVector2Array([Vector2(320.0, 20.0), Vector2(320.0, 20.0)]),
		PackedVector2Array([Vector2(1200.0, 0.0), Vector2(1200.0, 0.0)]),
		PackedFloat64Array([0.55, 0.0]),
		PackedFloat64Array([1.3, 1.3]),
		PackedFloat64Array([1.5, 1.5])
	))
	host.step_fixed()
	var mixed_events: Dictionary = host.drain_projectile_event_batch()
	assert(mixed_events.kinds == PackedInt32Array([0, 4]))
	var mixed_states: Dictionary = host.get_projectile_state_batch()
	assert(mixed_states.projectile_ids.size() == 1)
	assert(host.submit_projectile_retires(
		PackedInt64Array([mixed_states.projectile_ids[0]]),
		PackedInt32Array([0])
	))
	host.step_fixed()
	var retire_events: Dictionary = host.drain_projectile_event_batch()
	assert(retire_events.kinds == PackedInt32Array([2]))
	assert(host.get_projectile_state_batch().projectile_ids.is_empty())

	# One entity-proxy batch and one terrain grid batch prove collision remains
	# coarse-grained across the GDExtension boundary.
	assert(host.configure_primary_gravity(Vector2(0.0, 1000.0), 1000.0, 0.0, 30, 1234))
	assert(host.submit_collision_world(
		PackedInt64Array([77]),
		PackedInt32Array([0]),
		PackedVector2Array([Vector2(5.0, 0.0)]),
		PackedVector2Array([Vector2.ONE]),
		PackedByteArray([0, 0, 0, 0]),
		4,
		1,
		Vector2.ZERO,
		1.0
	))
	assert(host.submit_projectile_spawns(
		PackedInt64Array([30]),
		PackedVector2Array([Vector2.ZERO]),
		PackedVector2Array([Vector2(300.0, 0.0)]),
		PackedFloat64Array([1.0]),
		PackedFloat64Array([0.0]),
		PackedFloat64Array([1.0])
	))
	host.step_fixed()
	var entity_hit_events: Dictionary = host.drain_projectile_event_batch()
	assert(entity_hit_events.kinds == PackedInt32Array([0, 5]))
	assert(entity_hit_events.collider_ids == PackedInt64Array([0, 77]))

	assert(host.configure_primary_gravity(Vector2(0.0, 1000.0), 1000.0, 0.0, 30, 1234))
	assert(host.submit_collision_world(
		PackedInt64Array(),
		PackedInt32Array(),
		PackedVector2Array(),
		PackedVector2Array(),
		PackedByteArray([0, 0, 1, 0]),
		4,
		1,
		Vector2.ZERO,
		1.0
	))
	assert(host.submit_projectile_spawns(
		PackedInt64Array([31]),
		PackedVector2Array([Vector2.ZERO]),
		PackedVector2Array([Vector2(300.0, 0.0)]),
		PackedFloat64Array([1.0]),
		PackedFloat64Array([0.0]),
		PackedFloat64Array([0.0])
	))
	host.step_fixed()
	var terrain_hit_events: Dictionary = host.drain_projectile_event_batch()
	assert(terrain_hit_events.kinds == PackedInt32Array([0, 6]))
	assert(terrain_hit_events.collider_ids == PackedInt64Array([0, 0]))

	host.free()
	print("native_bridge_smoke: PASS")
	quit(0)
