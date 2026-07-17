extends SceneTree

const DEMO_SCENE := preload("res://scenes/main.tscn")
const ASTEROID_CENTER := Vector2(320.0, 180.0)
const RIGHT_SPAWN := Vector2(490.0, 180.0)
const SETTLE_FRAMES := 90
const ANGLE_TOLERANCE := 0.12


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var demo := DEMO_SCENE.instantiate()
	root.add_child(demo)
	await process_frame

	for enemy in get_nodes_in_group("enemies"):
		enemy.queue_free()
	await process_frame

	var player: Node2D = demo.get_node("Player") as Node2D
	var camera: Camera2D = demo.get_node_or_null("GravityCamera") as Camera2D
	var hud: CanvasLayer = demo.get_node("HUD") as CanvasLayer
	if not is_instance_valid(camera):
		_fail("GravityCamera node is missing")
		return
	if not camera.enabled:
		_fail("GravityCamera is not enabled")
		return
	if camera.ignore_rotation:
		_fail("GravityCamera ignores rotation, so local up cannot remain screen-up")
		return
	if minf(camera.zoom.x, camera.zoom.y) < 1.5:
		_fail("camera zoom does not present the asteroid as a local surface: %s" % camera.zoom)
		return
	if camera.is_ancestor_of(hud):
		_fail("HUD must remain screen-aligned outside the rotating camera hierarchy")
		return
	if not player.has_method("get_up_direction"):
		_fail("player does not expose its current gravity-aligned up direction")
		return

	for _frame in range(SETTLE_FRAMES):
		await physics_frame
	if camera.global_position.distance_to(player.global_position) > 1.0:
		_fail("camera does not follow the player at the top spawn")
		return
	if not _camera_matches_player_up(camera, player):
		_fail("camera does not align the top-spawn gravity direction")
		return
	if not _viewport_maps_local_up_to_screen_up(demo, player):
		_fail("viewport transform does not apply camera rotation at the top spawn")
		return

	player.reset_player(RIGHT_SPAWN)
	for _frame in range(SETTLE_FRAMES):
		await physics_frame
	var radial_distance := player.global_position.distance_to(ASTEROID_CENTER)
	if radial_distance < 150.0 or radial_distance > 185.0:
		_fail("right-side reset did not settle near the asteroid surface: %.2f" % radial_distance)
		return
	if camera.global_position.distance_to(player.global_position) > 1.0:
		_fail("camera lost the player after gravity direction changed")
		return
	if not _camera_matches_player_up(camera, player):
		_fail(
			"camera did not rotate local up toward screen up: camera=%.3f up=%s"
			% [camera.rotation, player.get_up_direction()]
		)
		return
	if not _viewport_maps_local_up_to_screen_up(demo, player):
		_fail("viewport transform does not map right-side local up to screen up")
		return

	print(
		"camera smoke: PASS zoom=",
		camera.zoom,
		" rotation=",
		snappedf(camera.rotation, 0.001)
	)
	quit(0)


func _camera_matches_player_up(camera: Camera2D, player: Node2D) -> bool:
	var up: Vector2 = player.get_up_direction()
	var expected := up.angle() + PI * 0.5
	return absf(wrapf(camera.rotation - expected, -PI, PI)) <= ANGLE_TOLERANCE


func _viewport_maps_local_up_to_screen_up(demo: Node, player: Node2D) -> bool:
	var canvas_transform := demo.get_viewport().get_canvas_transform()
	var screen_up := canvas_transform.basis_xform(player.get_up_direction()).normalized()
	return screen_up.dot(Vector2.UP) >= cos(ANGLE_TOLERANCE)


func _fail(message: String) -> void:
	push_error("camera smoke: FAIL: " + message)
	quit(1)
