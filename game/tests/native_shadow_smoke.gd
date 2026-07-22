extends SceneTree

const LAB_SCENE := preload("res://scenes/combat_lab.tscn")
const PROFILE := preload("res://resources/combat/basic_rifle.tres")
const PROJECTILE_SCRIPT := preload("res://scripts/combat/juvenile_starseed.gd")

const POSITION_TOLERANCE_PX := 0.1
const VELOCITY_TOLERANCE_PX_PER_SECOND := 0.5


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var lab := LAB_SCENE.instantiate()
	root.add_child(lab)
	await process_frame

	var material_world: MaterialWorld = lab.get_node("MaterialWorld") as MaterialWorld
	var script_projectile: JuvenileStarseed = PROJECTILE_SCRIPT.new()
	lab.add_child(script_projectile)
	var origin := Vector2(160.0, -60.0)
	script_projectile.setup(PROFILE, origin, Vector2.RIGHT, Vector2.ZERO, material_world)
	script_projectile.set_physics_process(false)

	var native_host := StarfallSimulationHost.new()
	assert(native_host.configure_primary_gravity(
		material_world.primary_gravity_center,
		material_world.primary_surface_radius,
		material_world.primary_gravity_acceleration,
		30
	))
	assert(native_host.submit_projectile_spawns(
		PackedInt64Array([1]),
		PackedVector2Array([origin]),
		PackedVector2Array([Vector2.RIGHT * PROFILE.projectile_speed]),
		PackedFloat64Array([PROFILE.projectile_lifetime]),
		PackedFloat64Array([PROFILE.projectile_gravity_scale])
	))

	# The accepted GDScript projectile runs at 60 Hz; the native authority runs
	# at 30 Hz. Compare at their common tick boundary without changing gameplay.
	for expected_tick in range(1, 9):
		script_projectile.simulate_step(1.0 / 60.0)
		script_projectile.simulate_step(1.0 / 60.0)
		native_host.step_fixed()
		var states: Dictionary = native_host.get_projectile_state_batch()
		assert(states.tick == expected_tick)
		assert(states.projectile_ids.size() == 1)
		var position_error := script_projectile.global_position.distance_to(states.positions[0])
		var velocity_error := script_projectile.velocity.distance_to(states.velocities[0])
		assert(position_error <= POSITION_TOLERANCE_PX)
		assert(velocity_error <= VELOCITY_TOLERANCE_PX_PER_SECOND)

	var spawn_events: Dictionary = native_host.drain_projectile_event_batch()
	assert(spawn_events.kinds == PackedInt32Array([0]))
	assert(not script_projectile.is_expired())

	var script_expire_reason := [""]
	script_projectile.expired.connect(
		func(reason: String) -> void:
			script_expire_reason[0] = reason
	)
	for _tick in range(9):
		script_projectile.simulate_step(1.0 / 60.0)
		script_projectile.simulate_step(1.0 / 60.0)
		native_host.step_fixed()

	var expire_events: Dictionary = native_host.drain_projectile_event_batch()
	assert(expire_events.kinds == PackedInt32Array([1]))
	assert(expire_events.ticks == PackedInt64Array([17]))
	assert(script_projectile.is_expired())
	assert(script_expire_reason[0] == "lifetime")
	assert(
		script_projectile.global_position.distance_to(expire_events.positions[0])
		<= POSITION_TOLERANCE_PX
	)

	native_host.free()
	lab.queue_free()
	await process_frame
	print("native shadow smoke: PASS")
	quit(0)
