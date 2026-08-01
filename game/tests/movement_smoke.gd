extends SceneTree

const DEMO_SCENE := preload("res://scenes/main.tscn")
const ASTEROID_CENTER := Vector2(320.0, 180.0)
const SETTLE_FRAMES := 45
const WALK_FRAMES := 90
# Inverse-square gravity weakens above the 156 px body. A 116 px/s radial
# launch from r≈170 returns in roughly 3.6 seconds (~215 physics frames), so
# retain bounded headroom without allowing a drifting/escaping player to pass.
const JUMP_TIMEOUT_FRAMES := 300
const MAX_JUMP_HEIGHT := 130.0


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
	var world: Node = demo.get_node("MaterialWorld")
	if player.get("_material_world") != world:
		_fail(
			"player did not bind MaterialWorld: path=%s"
			% [str(player.get("material_world_path"))]
		)
		return
	for _frame in range(SETTLE_FRAMES):
		await physics_frame
	if not bool(player.get_state().get("grounded", false)):
		_fail(
			"player did not settle onto the asteroid surface: position=%s radius=%.2f"
			% [player.global_position, player.global_position.distance_to(ASTEROID_CENTER)]
		)
		return

	var walk_start: Vector2 = player.global_position
	var start_radius := walk_start.distance_to(ASTEROID_CENTER)
	Input.action_press("move_right")
	for _frame in range(WALK_FRAMES):
		await physics_frame
	Input.action_release("move_right")
	var walk_end: Vector2 = player.global_position
	var end_radius := walk_end.distance_to(ASTEROID_CENTER)
	var angular_displacement := absf(
		wrapf(
			(walk_end - ASTEROID_CENTER).angle() - (walk_start - ASTEROID_CENTER).angle(),
			-PI,
			PI
		)
	)
	var walked_arc := angular_displacement * (start_radius + end_radius) * 0.5
	if walked_arc < 24.0:
		_fail("move_right did not produce meaningful surface movement: %.2f px" % walked_arc)
		return
	if absf(end_radius - start_radius) > 16.0:
		_fail("surface movement lost radial contact: %.2f px" % absf(end_radius - start_radius))
		return

	for _frame in range(12):
		await physics_frame
	var jump_start_radius: float = player.global_position.distance_to(ASTEROID_CENTER)
	Input.action_press("jump")
	await physics_frame
	Input.action_release("jump")
	var max_radius: float = jump_start_radius
	var became_airborne := false
	var landed_again := false
	var landing_frame := -1
	for frame in range(JUMP_TIMEOUT_FRAMES):
		await physics_frame
		max_radius = maxf(max_radius, player.global_position.distance_to(ASTEROID_CENTER))
		var grounded := bool(player.get_state().get("grounded", false))
		if not grounded:
			became_airborne = true
		elif became_airborne:
			landed_again = true
			landing_frame = frame + 1
			break
	var jump_height := max_radius - jump_start_radius
	if jump_height < 8.0:
		_fail("jump did not move the player away from the asteroid surface")
		return
	if jump_height > MAX_JUMP_HEIGHT:
		_fail(
			"jump exceeded the bounded inverse-square trajectory: %.2f px"
			% jump_height
		)
		return
	if not became_airborne or not landed_again:
		_fail(
			"jump did not land within %d physics frames (max height %.2f px)"
			% [JUMP_TIMEOUT_FRAMES, jump_height]
		)
		return

	print(
		"movement smoke: PASS arc_px=",
		snappedf(walked_arc, 0.1),
		" jump_height_px=",
		snappedf(jump_height, 0.1),
		" landing_frames=",
		landing_frame
	)
	quit(0)


func _fail(message: String) -> void:
	Input.action_release("move_right")
	Input.action_release("jump")
	push_error("movement smoke: FAIL: " + message)
	quit(1)
