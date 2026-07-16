extends SceneTree

const DEMO_SCENE := preload("res://scenes/main.tscn")
const SAMPLE_FRAMES := 300


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var demo := DEMO_SCENE.instantiate()
	root.add_child(demo)
	await process_frame

	var world = demo.get_node("MaterialWorld")
	world.add_gravity_source(Vector2(250.0, 150.0), 155.0, 105.0, -1.0)
	world.add_gravity_source(Vector2(390.0, 150.0), 155.0, 105.0, -1.0)
	world.add_gravity_source(Vector2(320.0, 250.0), 155.0, 105.0, -1.0)
	for index in range(24):
		var position := Vector2(220.0 + float((index * 37) % 200), 90.0 + float((index * 53) % 180))
		world.paint_circle(position, 3, 2 + index % 3)

	var start_tick: int = world.get_stats()["tick"]
	var started_usec := Time.get_ticks_usec()
	for _frame in range(SAMPLE_FRAMES):
		await process_frame
	var elapsed_seconds := float(Time.get_ticks_usec() - started_usec) / 1_000_000.0
	var end_tick: int = world.get_stats()["tick"]

	print(
		"godot demo benchmark: frames=",
		SAMPLE_FRAMES,
		" elapsed_s=",
		snappedf(elapsed_seconds, 0.001),
		" average_fps=",
		snappedf(float(SAMPLE_FRAMES) / elapsed_seconds, 0.1),
		" simulation_ticks=",
		end_tick - start_tick
	)
	quit(0)
