extends SceneTree

const DEMO_SCENE := preload("res://scenes/main.tscn")


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var demo := DEMO_SCENE.instantiate()
	root.add_child(demo)
	await process_frame

	var runtime: NativeGravityRuntime = demo.get_node("NativeGravityRuntime")
	var player := demo.get_node("Player")
	var provider: NativeGravityProvider = runtime.get_provider()
	assert(player.get("_gravity_provider") == provider)
	var initial_total := runtime.total_steps
	for _frame in range(6):
		await physics_frame
	assert(runtime.total_steps >= initial_total)
	if provider.native_available:
		assert(runtime.get_tick() > 0)
		assert(runtime.last_step_count <= NativeGravityRuntime.MAX_STEPS_PER_FRAME)

	var radial_id := provider.add_gravity_source(Vector2(260.0, 150.0), 155.0, 105.0, -1.0)
	var uniform_id := provider.add_uniform_source(Vector2(260.0, 150.0), Vector2(0.0, 18.0), 72.0, -1.0)
	assert(radial_id > 0)
	assert(uniform_id > 0)
	assert(radial_id != uniform_id)
	for _frame in range(4):
		await physics_frame
	assert(provider.get_source_snapshots().size() == 2)
	assert((provider.sample(Vector2(270.0, 150.0))["acceleration"] as Vector2).is_finite())

	assert(provider.update_gravity_source(radial_id, Vector2(264.0, 150.0)))
	assert(provider.remove_gravity_source(uniform_id))
	for _frame in range(4):
		await physics_frame
	assert(provider.get_source_snapshots().size() == 1)

	runtime.reset_runtime()
	assert(provider.get_source_snapshots().is_empty())
	assert(runtime.get_tick() == 0 if provider.native_available else true)

	demo.queue_free()
	await process_frame
	print("native gravity runtime smoke: PASS")
	quit(0)
