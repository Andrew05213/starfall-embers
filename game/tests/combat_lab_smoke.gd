extends SceneTree

const LAB_SCENE := preload("res://scenes/combat_lab.tscn")
const PROFILE := preload("res://resources/combat/basic_rifle.tres")
const TARGET_SCRIPT := preload("res://scripts/combat/combat_target.gd")


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var lab := LAB_SCENE.instantiate()
	root.add_child(lab)
	await process_frame
	for _frame in range(8):
		await physics_frame

	var state: Dictionary = lab.get_lab_state()
	if int(state.get("targets", 0)) != 4:
		_fail("combat lab did not spawn wall, static, moving and ordinary targets")
		return
	if absf(float(state.get("fire_interval", 0.0)) - 0.11) > 0.0001:
		_fail("combat lab does not use the 0.11 s automatic profile")
		return
	var camera: Camera2D = lab.get_node("GravityCamera") as Camera2D
	var visible_world_width := 640.0 / camera.zoom.x
	var screens_per_second := PROFILE.projectile_speed / visible_world_width
	if screens_per_second < 3.0 or screens_per_second > 5.0:
		_fail("juvenile speed is outside 3-5 current-view screens/s: %.2f" % screens_per_second)
		return
	if PROFILE.projectile_lifetime < 0.4 or PROFILE.projectile_lifetime > 0.8:
		_fail("juvenile lifetime is outside the Gate-1 band")
		return
	var feedback: CombatFeedback = lab.get_node("CombatFeedback") as CombatFeedback
	for layer in ["cast", "flight", "hit", "death"]:
		if not feedback.has_audio_layer(layer):
			_fail("combat feedback did not generate the %s audio layer" % layer)
			return

	var player: CombatLabPlayer = lab.get_node("Player") as CombatLabPlayer
	# Live Camera2D contract: feed a screen point generated from a known world
	# direction, then require the controller to invert the rotated canvas.
	var expected_aim := Vector2.from_angle(0.41)
	var screen_target := lab.get_viewport().get_canvas_transform() * (
		player.global_position + expected_aim * 100.0
	)
	player.set_aim_screen_position(screen_target)
	await physics_frame
	if player.get_aim_direction().dot(expected_aim) < 0.999:
		_fail("live combat player aim does not invert the active Camera2D transform")
		return

	# Aim away from the asteroid/targets so the cadence measurement isolates the
	# scheduler and cannot be affected by a target death.
	var outward: Vector2 = player.get_up_direction()
	screen_target = lab.get_viewport().get_canvas_transform() * (player.global_position + outward * 100.0)
	player.set_aim_screen_position(screen_target)
	Input.action_press("fire_starseed")
	await physics_frame
	state = lab.get_lab_state()
	if int(state.get("shots", 0)) < 1:
		_fail("held fire did not emit on the first physics frame")
		return
	if float(state.get("first_shot_latency_ms", 999.0)) >= 50.0:
		_fail("first-shot latency exceeded 50 ms")
		return
	for _frame in range(59):
		await physics_frame
	Input.action_release("fire_starseed")
	await physics_frame
	state = lab.get_lab_state()
	var shots := int(state.get("shots", 0))
	if shots < 9 or shots > 11:
		_fail("one-second live hold produced %d shots, expected 9-11" % shots)
		return

	lab.queue_free()
	await process_frame
	if not await _test_grunt_hit_contract():
		return
	print("combat lab smoke: PASS shots=", shots, " screens_per_second=", snappedf(screens_per_second, 0.01))
	quit(0)


func _test_grunt_hit_contract() -> bool:
	var grunt: CombatTarget = TARGET_SCRIPT.new()
	grunt.setup("enemy", Vector2.ZERO)
	root.add_child(grunt)
	grunt.set_physics_process(false)
	await process_frame
	var defeated_count := [0]
	grunt.defeated.connect(
		func(_target: Node, _point: Vector2, _velocity: Vector2) -> void:
			defeated_count[0] += 1
	)

	grunt.receive_juvenile_hit(PROFILE.damage, Vector2.RIGHT, Vector2.ZERO, Vector2.RIGHT * PROFILE.projectile_speed)
	if grunt.get_hit_pause_remaining() < 0.024 or grunt.get_hit_pause_remaining() > 0.026:
		return _fail_bool("ordinary target-local hit pause is not approximately 25 ms")
	for _hit in range(2):
		grunt.receive_juvenile_hit(PROFILE.damage, Vector2.RIGHT, Vector2.ZERO, Vector2.RIGHT * PROFILE.projectile_speed)
	grunt.receive_juvenile_hit(PROFILE.damage, Vector2.RIGHT, Vector2.ZERO, Vector2.RIGHT * PROFILE.projectile_speed)
	if grunt.get_hit_pause_remaining() < 0.049 or grunt.get_hit_pause_remaining() > 0.051:
		return _fail_bool("strong threshold target-local hit pause is not approximately 50 ms")
	for _hit in range(2):
		grunt.receive_juvenile_hit(PROFILE.damage, Vector2.RIGHT, Vector2.ZERO, Vector2.RIGHT * PROFILE.projectile_speed)
	if grunt.is_dead():
		return _fail_bool("ordinary enemy died before seven rifle hits")
	grunt.receive_juvenile_hit(PROFILE.damage, Vector2.RIGHT, Vector2.ZERO, Vector2.RIGHT * PROFILE.projectile_speed)
	if not grunt.is_dead() or int(defeated_count[0]) != 1:
		return _fail_bool("ordinary enemy did not die on the seventh rifle hit")

	var projected_ttk := 6.0 * PROFILE.fire_interval + 90.0 / PROFILE.projectile_speed
	if projected_ttk < 0.5 or projected_ttk > 1.2:
		return _fail_bool("ordinary enemy projected TTK is outside 0.5-1.2 s: %.3f" % projected_ttk)
	if is_instance_valid(grunt) and not grunt.is_queued_for_deletion():
		grunt.queue_free()
	await process_frame
	return true


func _fail_bool(message: String) -> bool:
	_fail(message)
	return false


func _fail(message: String) -> void:
	Input.action_release("fire_starseed")
	push_error("combat lab smoke: FAIL: " + message)
	quit(1)
