extends SceneTree

const DEMO_SCENE := preload("res://scenes/main.tscn")
const STARSEED_SCRIPT := preload("res://scripts/demo/starseed.gd")


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var demo := DEMO_SCENE.instantiate()
	root.add_child(demo)
	await process_frame

	var world = demo.get_node("MaterialWorld")
	if world == null:
		_fail("MaterialWorld node is missing")
		return

	world.paint_circle(Vector2(300.0, 40.0), 2, 3)
	world.paint_circle(Vector2(308.0, 40.0), 2, 7)

	var starseed := STARSEED_SCRIPT.new()
	demo.add_child(starseed)
	starseed.setup(world, Vector2(320.0, 4.0), Vector2(0.0, 120.0))

	for _frame in range(120):
		await physics_frame

	var stats: Dictionary = world.get_stats()
	if int(stats.get("tick", 0)) < 30:
		_fail("fixed-step simulation did not advance")
		return
	if int(stats.get("active_cells", 0)) <= 0:
		_fail("generated asteroid contains no material")
		return
	if not starseed.is_anchored():
		_fail("starseed did not anchor to the asteroid")
		return
	if int(stats.get("gravity_sources", 0)) < 1:
		_fail("anchored starseed did not register a gravity source")
		return

	print("godot demo smoke: PASS ", stats)
	quit(0)


func _fail(message: String) -> void:
	push_error("godot demo smoke: FAIL: " + message)
	quit(1)
