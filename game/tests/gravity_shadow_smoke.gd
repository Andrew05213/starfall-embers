extends SceneTree

const PROVIDER_SCRIPT := preload("res://scripts/simulation/native_gravity_provider.gd")


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var world := MaterialWorld.new()
	root.add_child(world)
	await process_frame
	# Remove the primary field so this smoke isolates a local-field crossing.
	world.primary_gravity_acceleration = 0.0
	var native := StarfallSimulationHost.new()
	assert(native.configure_primary_gravity(
		world.primary_gravity_center,
		world.primary_surface_radius,
		world.primary_gravity_acceleration,
		30,
		0x51A7E11
	))
	var provider: NativeGravityProvider = PROVIDER_SCRIPT.new()
	provider.configure(world, native)
	assert(provider.set_mode(NativeGravityProvider.MODE_NATIVE_SHADOW))

	var sample_points := [
		world.primary_gravity_center + Vector2(32.0, 0.0),
		world.primary_gravity_center + Vector2(-32.0, 0.0),
		world.primary_gravity_center + Vector2(0.0, 32.0),
	]
	for point in sample_points:
		provider.sample(point)
	var pair := provider.sample_pair(sample_points[0], sample_points[0] + Vector2(90.0, 0.0))
	assert(pair.size() == 2)
	assert(int(pair[0]["tick"]) == int(pair[1]["tick"]))
	assert(int(provider.get_snapshot().get("compared_samples", 0)) == sample_points.size() + 2)
	assert(int(provider.get_snapshot().get("mismatches", -1)) == 0)

	var source_id := provider.add_gravity_source(Vector2(250.0, 150.0), 155.0, 105.0, -1.0)
	assert(source_id > 0)
	native.step_fixed()
	var source_sample := provider.sample(Vector2(250.0, 150.0) + Vector2(20.0, 0.0))
	assert((source_sample["acceleration"] as Vector2).is_finite())
	assert(int(provider.get_snapshot().get("mismatches", -1)) == 0)

	var uniform_id := provider.add_uniform_source(Vector2(250.0, 150.0), Vector2(0.0, 24.0), 64.0, -1.0)
	assert(uniform_id > 0)
	assert(uniform_id != source_id)
	native.step_fixed()
	var uniform_sample := provider.sample(Vector2(250.0, 150.0) + Vector2(8.0, 0.0))
	assert((uniform_sample["acceleration"] as Vector2).is_finite())
	assert(int(provider.get_snapshot().get("mismatches", -1)) == 0)
	var crossing := provider.sample_pair(Vector2(180.0, 150.0), Vector2(320.0, 150.0))
	assert(crossing.size() == 2)
	assert(int(crossing[0]["tick"]) == int(crossing[1]["tick"]))
	var frame := GravityFrame.new()
	frame.update_from_samples(crossing[0], crossing[1], Vector2.UP, Vector2.RIGHT, true)
	assert(frame.transitioning)

	assert(provider.set_mode(NativeGravityProvider.MODE_NATIVE_AUTHORITATIVE))
	var authoritative := provider.sample(world.primary_gravity_center + Vector2(32.0, 0.0))
	assert((authoritative["acceleration"] as Vector2).is_finite())
	assert(int(authoritative["tick"]) == int(native.get_tick()))

	provider.remove_gravity_source(source_id)
	native.step_fixed()
	var removed := provider.sample(Vector2(250.0, 150.0) + Vector2(20.0, 0.0))
	assert((removed["acceleration"] as Vector2).is_finite())
	provider.remove_gravity_source(uniform_id)
	native.step_fixed()
	assert(int(provider.get_snapshot().get("mismatches", -1)) == 0)

	native.free()
	world.queue_free()
	await process_frame
	print("gravity shadow smoke: PASS")
	quit(0)
