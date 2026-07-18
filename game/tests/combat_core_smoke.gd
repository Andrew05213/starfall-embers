extends SceneTree

const PROFILE_RESOURCE := preload("res://resources/combat/basic_rifle.tres")
const SCHEDULER_SCRIPT := preload("res://scripts/combat/fire_scheduler.gd")
const AIM_SPACE_SCRIPT := preload("res://scripts/combat/aim_space.gd")
const PROJECTILE_SCRIPT := preload("res://scripts/combat/juvenile_starseed.gd")
const TARGET_SCRIPT := preload("res://scripts/combat/combat_target.gd")

const EPSILON := 0.0002


class ThinTerrain:
	extends Node

	func is_solid_at(world_position: Vector2) -> bool:
		return world_position.x >= 42.0 and world_position.x < 43.0 and absf(world_position.y) <= 4.0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	if not _test_scheduler():
		return
	if not _test_rotated_camera_aim_contract():
		return
	if not await _test_swept_hit_and_earliest_target():
		return
	if not await _test_swept_terrain_hit():
		return
	if not await _test_projectile_lifetime():
		return
	print("combat core smoke: PASS")
	quit(0)


func _test_scheduler() -> bool:
	var scheduler = SCHEDULER_SCRIPT.new()
	scheduler.configure(0.11, 4)

	# Boundary semantics: pressing emits at t=0. A frame ending exactly at the
	# interval emits the next shot once, at offset 0.11, never twice.
	var shots: PackedFloat32Array = scheduler.advance(0.0, true)
	if shots.size() != 1 or absf(shots[0]) > EPSILON:
		return _fail_bool("scheduler did not emit the first shot immediately")
	shots = scheduler.advance(0.11, true)
	if shots.size() != 1 or absf(shots[0] - 0.11) > EPSILON:
		return _fail_bool("scheduler interval boundary over/under-fired: %s" % shots)

	scheduler.advance(0.0, false)
	shots = scheduler.advance(0.0, true)
	if shots.size() != 1 or absf(shots[0]) > EPSILON:
		return _fail_bool("release/repress did not emit an immediate shot")

	# A one-second 120 Hz hold should produce t=0 through t=0.99: ten shots.
	scheduler.configure(0.11, 4)
	var absolute_times := PackedFloat32Array()
	var elapsed := 0.0
	for _frame in range(120):
		shots = scheduler.advance(1.0 / 120.0, true)
		for offset in shots:
			absolute_times.append(elapsed + offset)
		elapsed += 1.0 / 120.0
	if absolute_times.size() != 10:
		return _fail_bool("one-second hold produced %d shots, expected 10" % absolute_times.size())
	for index in range(absolute_times.size()):
		var expected := float(index) * 0.11
		if absf(absolute_times[index] - expected) > EPSILON:
			return _fail_bool(
				"cadence drift at shot %d: %.5f vs %.5f"
				% [index, absolute_times[index], expected]
			)

	# Long stalls are capped and their backlog is discarded rather than bursting
	# on the next frame.
	scheduler.configure(0.11, 4)
	if scheduler.advance(5.0, true).size() != 4:
		return _fail_bool("scheduler did not cap long-frame catch-up")
	if not scheduler.advance(0.0, true).is_empty():
		return _fail_bool("scheduler leaked discarded backlog into the next frame")
	return true


func _test_rotated_camera_aim_contract() -> bool:
	var world_to_screen := Transform2D(0.83, Vector2(287.0, 149.0)).scaled(Vector2(2.0, 2.0))
	var origin := Vector2(41.0, -23.0)
	var expected_direction := Vector2.from_angle(-0.46)
	var world_target := origin + expected_direction * 180.0
	var screen_target := world_to_screen * world_target
	var actual: Vector2 = AIM_SPACE_SCRIPT.direction_from_screen(
		world_to_screen,
		origin,
		screen_target
	)
	if actual.dot(expected_direction) < 0.99999:
		return _fail_bool(
			"rotated/zoomed camera aim drifted: expected=%s actual=%s"
			% [expected_direction, actual]
		)
	return true


func _test_swept_hit_and_earliest_target() -> bool:
	var far_target = TARGET_SCRIPT.new()
	far_target.setup("static", Vector2(70.0, 0.0))
	root.add_child(far_target)
	far_target.set_physics_process(false)
	var near_target = TARGET_SCRIPT.new()
	near_target.setup("static", Vector2(35.0, 0.0))
	root.add_child(near_target)
	near_target.set_physics_process(false)
	await process_frame

	var projectile = PROJECTILE_SCRIPT.new()
	root.add_child(projectile)
	projectile.setup(PROFILE_RESOURCE, Vector2.ZERO, Vector2.RIGHT)
	projectile.set_physics_process(false)
	var hit_capture := [null, Vector2.ZERO]
	projectile.impacted.connect(
		func(target: Node, point: Vector2, _impact_velocity: Vector2) -> void:
			hit_capture[0] = target
			hit_capture[1] = point
	)

	# 1/15 s moves 80 px, crossing both targets in a single step. Point-only
	# collision would miss; the segment query must pick the near target even
	# though the far target was inserted into the group first.
	projectile.simulate_step(1.0 / 15.0)
	if hit_capture[0] != near_target:
		_cleanup_nodes([projectile, near_target, far_target])
		return _fail_bool("swept projectile did not select the earliest target")
	if float((hit_capture[1] as Vector2).x) >= far_target.global_position.x:
		_cleanup_nodes([projectile, near_target, far_target])
		return _fail_bool("swept hit point was not on the near target")
	_cleanup_nodes([projectile, near_target, far_target])
	await process_frame
	return true


func _test_projectile_lifetime() -> bool:
	var profile: CombatShotProfile = PROFILE_RESOURCE.duplicate()
	profile.projectile_lifetime = 0.4
	var projectile = PROJECTILE_SCRIPT.new()
	root.add_child(projectile)
	projectile.setup(profile, Vector2(1000.0, 1000.0), Vector2.RIGHT)
	projectile.set_physics_process(false)
	var reason := [""]
	projectile.expired.connect(func(value: String) -> void: reason[0] = value)
	projectile.simulate_step(0.399)
	if projectile.is_expired():
		_cleanup_nodes([projectile])
		return _fail_bool("projectile expired before its configured lifetime")
	projectile.simulate_step(0.002)
	if not projectile.is_expired() or str(reason[0]) != "lifetime":
		_cleanup_nodes([projectile])
		return _fail_bool("projectile did not expire at its configured lifetime")
	if absf(projectile.get_age() - 0.4) > EPSILON:
		_cleanup_nodes([projectile])
		return _fail_bool("projectile lifetime step overshot: %.5f" % projectile.get_age())
	_cleanup_nodes([projectile])
	await process_frame
	return true


func _test_swept_terrain_hit() -> bool:
	var world := ThinTerrain.new()
	root.add_child(world)
	var target = TARGET_SCRIPT.new()
	target.setup("static", Vector2(70.0, 0.0))
	root.add_child(target)
	target.set_physics_process(false)
	var projectile = PROJECTILE_SCRIPT.new()
	root.add_child(projectile)
	projectile.setup(PROFILE_RESOURCE, Vector2.ZERO, Vector2.RIGHT, Vector2.ZERO, world)
	projectile.set_physics_process(false)
	var hit_capture := [false, null, Vector2.ZERO]
	projectile.impacted.connect(
		func(hit_target: Node, point: Vector2, _impact_velocity: Vector2) -> void:
			hit_capture[0] = true
			hit_capture[1] = hit_target
			hit_capture[2] = point
	)
	projectile.simulate_step(1.0 / 15.0)
	if not bool(hit_capture[0]) or hit_capture[1] != null:
		_cleanup_nodes([projectile, target, world])
		return _fail_bool("swept projectile did not report thin terrain before the target")
	var point := hit_capture[2] as Vector2
	if point.x >= target.global_position.x or point.x < 38.0 or point.x > 44.0:
		_cleanup_nodes([projectile, target, world])
		return _fail_bool("thin-terrain swept hit point is invalid: %s" % point)
	_cleanup_nodes([projectile, target, world])
	await process_frame
	return true


func _cleanup_nodes(nodes: Array) -> void:
	for node in nodes:
		if is_instance_valid(node) and not node.is_queued_for_deletion():
			node.queue_free()


func _fail_bool(message: String) -> bool:
	push_error("combat core smoke: FAIL: " + message)
	quit(1)
	return false
