extends SceneTree

const PROVIDER_SCRIPT := preload("res://scripts/simulation/native_gravity_provider.gd")


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var world := MaterialWorld.new()
	root.add_child(world)
	await process_frame
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
	assert(int(provider.get_snapshot().get("compared_samples", 0)) == sample_points.size())
	assert(int(provider.get_snapshot().get("mismatches", -1)) == 0)

	var source_id := provider.add_gravity_source(Vector2(250.0, 150.0), 155.0, 105.0, -1.0)
	assert(source_id > 0)
	native.step_fixed()
	var source_sample := provider.sample(Vector2(250.0, 150.0) + Vector2(20.0, 0.0))
	assert((source_sample["acceleration"] as Vector2).is_finite())
	assert(int(provider.get_snapshot().get("mismatches", -1)) == 0)

	assert(provider.set_mode(NativeGravityProvider.MODE_NATIVE_AUTHORITATIVE))
	var authoritative := provider.sample(world.primary_gravity_center + Vector2(32.0, 0.0))
	assert((authoritative["acceleration"] as Vector2).is_finite())
	assert(int(authoritative["tick"]) == 1)

	provider.remove_gravity_source(source_id)
	native.step_fixed()
	var removed := provider.sample(Vector2(250.0, 150.0) + Vector2(20.0, 0.0))
	assert(int(removed["dominant_source_id"]) == 0)

	native.free()
	world.queue_free()
	await process_frame
	print("gravity shadow smoke: PASS")
	quit(0)
