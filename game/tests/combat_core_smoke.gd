extends SceneTree

const PROFILE_RESOURCE := preload("res://resources/combat/basic_rifle.tres")
const SCHEDULER_SCRIPT := preload("res://scripts/combat/fire_scheduler.gd")
const AIM_SPACE_SCRIPT := preload("res://scripts/combat/aim_space.gd")
const PROJECTILE_SCRIPT := preload("res://scripts/combat/juvenile_starseed.gd")
const TARGET_SCRIPT := preload("res://scripts/combat/combat_target.gd")
const PARTICLE_FIELD_SCRIPT := preload("res://scripts/combat/ballistic_particle_field.gd")

const EPSILON := 0.0002


class ThinTerrain:
	extends Node

	func is_solid_at(world_position: Vector2) -> bool:
		return world_position.x >= 42.0 and world_position.x < 43.0 and absf(world_position.y) <= 4.0


class ConstantGravity:
	extends Node

	var acceleration := Vector2(0.0, 135.0)

	func get_gravity_at(_world_position: Vector2) -> Vector2:
		return acceleration

	func is_solid_at(_world_position: Vector2) -> bool:
		return false


class RadialGravity:
	extends Node

	var center := Vector2.ZERO
	var samples: Array[Vector2] = []

	func get_gravity_at(world_position: Vector2) -> Vector2:
		samples.append(world_position)
		var inward := center - world_position
		return inward.normalized() * 135.0 if inward.length_squared() > 0.0001 else Vector2.ZERO

	func is_solid_at(_world_position: Vector2) -> bool:
		return false


class ProjectileInterpolationProbe:
	extends JuvenileStarseed

	var interpolation_reset_positions: Array[Vector2] = []

	func _notification(what: int) -> void:
		if what == NOTIFICATION_RESET_PHYSICS_INTERPOLATION:
			interpolation_reset_positions.append(global_position)


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
	if not await _test_projectile_ballistics():
		return
	if not await _test_radial_projectile_gravity_and_spawn_interpolation():
		return
	if not await _test_ballistic_particle_pool():
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


func _test_projectile_ballistics() -> bool:
	var world := ConstantGravity.new()
	root.add_child(world)
	var profile: CombatShotProfile = PROFILE_RESOURCE.duplicate()
	var invalid_profile: CombatShotProfile = PROFILE_RESOURCE.duplicate()
	invalid_profile.projectile_gravity_scale = -1.0
	if invalid_profile.is_valid():
		_cleanup_nodes([world])
		return _fail_bool("shot profile accepted a negative gravity scale")
	var projectile = PROJECTILE_SCRIPT.new()
	root.add_child(projectile)
	projectile.setup(profile, Vector2(1000.0, 1000.0), Vector2.RIGHT, Vector2.ZERO, world)
	projectile.set_physics_process(false)
	projectile.simulate_step(0.1)
	var displacement: Vector2 = projectile.global_position - Vector2(1000.0, 1000.0)
	if absf(displacement.x - 120.0) > EPSILON:
		_cleanup_nodes([projectile, world])
		return _fail_bool("ballistic projectile lost high horizontal speed: %s" % displacement)
	var expected_short_drop := 0.675 * profile.projectile_gravity_scale
	if absf(displacement.y - expected_short_drop) > EPSILON:
		_cleanup_nodes([projectile, world])
		return _fail_bool("ballistic projectile did not integrate local gravity: %s" % displacement)
	if absf(projectile.velocity.y - 13.5 * profile.projectile_gravity_scale) > EPSILON:
		_cleanup_nodes([projectile, world])
		return _fail_bool("ballistic projectile velocity did not inherit gravity: %s" % projectile.velocity)

	# Lock the actual Gate-1 feel scale: one 320-world-unit view takes 0.2667 s
	# to cross at 1200 u/s. The resource multiplier makes its drop readable.
	projectile.global_position = Vector2(1000.0, 1000.0)
	projectile.velocity = Vector2(profile.projectile_speed, 0.0)
	projectile.simulate_step(320.0 / profile.projectile_speed)
	var view_drop: float = projectile.global_position.y - 1000.0
	var expected_view_drop := 4.8 * profile.projectile_gravity_scale
	if absf(view_drop - expected_view_drop) > EPSILON:
		_cleanup_nodes([projectile, world])
		return _fail_bool("one-view ballistic drop differs from configured gravity: %.4f" % view_drop)
	if view_drop < 12.0 or view_drop > 20.0:
		_cleanup_nodes([projectile, world])
		return _fail_bool("one-view ballistic drop left the Gate-1 target band: %.4f" % view_drop)
	_cleanup_nodes([projectile, world])
	await process_frame
	return true


func _test_radial_projectile_gravity_and_spawn_interpolation() -> bool:
	var world := RadialGravity.new()
	root.add_child(world)
	var profile: CombatShotProfile = PROFILE_RESOURCE.duplicate()
	profile.projectile_gravity_scale = 1.0
	var projectiles: Array[Node] = []
	var cardinal_spawns: Array[Vector2] = [
		Vector2(0.0, -1000.0),
		Vector2(1000.0, 0.0),
		Vector2(0.0, 1000.0),
		Vector2(-1000.0, 0.0),
	]
	for spawn in cardinal_spawns:
		world.samples.clear()
		var inward: Vector2 = (world.center - spawn).normalized()
		var tangent := Vector2(-inward.y, inward.x)
		var projectile := ProjectileInterpolationProbe.new()
		root.add_child(projectile)
		projectiles.append(projectile)
		projectile.setup(profile, spawn, tangent, Vector2.ZERO, world)
		projectile.set_physics_process(false)
		if (
			projectile.interpolation_reset_positions.is_empty()
			or projectile.interpolation_reset_positions.back().distance_to(spawn) > EPSILON
		):
			_cleanup_nodes(projectiles + [world])
			return _fail_bool(
				"new projectile did not reset interpolation at its muzzle %s: %s"
				% [spawn, projectile.interpolation_reset_positions]
			)

		var initial_velocity: Vector2 = projectile.velocity
		for _step in range(6):
			projectile.simulate_step(1.0 / 120.0)
		if world.samples.size() != 6:
			_cleanup_nodes(projectiles + [world])
			return _fail_bool(
				"projectile at %s did not resample moving local gravity: %d samples"
				% [spawn, world.samples.size()]
			)
		if world.samples.front().distance_to(world.samples.back()) < 1.0:
			_cleanup_nodes(projectiles + [world])
			return _fail_bool(
				"projectile at %s repeatedly sampled gravity at its spawn" % spawn
			)
		var accumulated_gravity: Vector2 = projectile.velocity - initial_velocity
		if accumulated_gravity.dot(inward) <= 6.0:
			_cleanup_nodes(projectiles + [world])
			return _fail_bool(
				"projectile at %s did not fall radially inward: delta_velocity=%s"
				% [spawn, accumulated_gravity]
			)

		# GravityFollowCamera rotates the world by the inverse of its desired
		# rotation. Every cardinal inward vector must therefore become screen-down.
		var local_up: Vector2 = -inward
		var camera_rotation: float = local_up.angle() + PI * 0.5
		var screen_gravity: Vector2 = (
			Transform2D(-camera_rotation, Vector2.ZERO).basis_xform(inward)
		)
		if screen_gravity.y <= 0.999 or absf(screen_gravity.x) > EPSILON:
			_cleanup_nodes(projectiles + [world])
			return _fail_bool(
				"gravity at %s does not map to screen-down: %s" % [spawn, screen_gravity]
			)

	_cleanup_nodes(projectiles + [world])
	await process_frame
	return true


func _test_ballistic_particle_pool() -> bool:
	var world := ConstantGravity.new()
	root.add_child(world)
	var particles: CombatBallisticParticleField = PARTICLE_FIELD_SCRIPT.new()
	root.add_child(particles)
	particles.bind_material_world(world, PROFILE_RESOURCE.projectile_gravity_scale)
	particles.set_process(false)
	particles.emit_trail(
		Vector2.ZERO,
		Vector2.RIGHT * 20.0,
		Vector2.RIGHT * PROFILE_RESOURCE.projectile_speed,
		Color.WHITE
	)
	if particles.get_particle_count() != CombatBallisticParticleField.TRAIL_PARTICLES_PER_STEP:
		_cleanup_nodes([particles, world])
		return _fail_bool("trail did not emit the expected per-step particle count")
	for index in range(particles.get_particle_count()):
		var trail_particle := particles.get_particle_snapshot(index)
		var trail_velocity := trail_particle["velocity"] as Vector2
		if trail_velocity.length() > PROFILE_RESOURCE.projectile_speed * 0.20 + EPSILON:
			_cleanup_nodes([particles, world])
			return _fail_bool("trail particle exceeded the one-fifth projectile-speed cap")
		if float(trail_particle["lifetime"]) < 0.28:
			_cleanup_nodes([particles, world])
			return _fail_bool("trail particle lifetime did not preserve the longer visual tail")
	particles.simulate_step(0.20)
	if particles.get_particle_count() != CombatBallisticParticleField.TRAIL_PARTICLES_PER_STEP:
		_cleanup_nodes([particles, world])
		return _fail_bool("long-lived trail particles were reclaimed after only 0.20 seconds")
	particles.simulate_step(0.15)
	if particles.get_particle_count() != 0:
		_cleanup_nodes([particles, world])
		return _fail_bool("trail particles survived beyond their configured upper lifetime")
	particles.emit_impact(Vector2.ZERO, Vector2.RIGHT * 1200.0, Color.WHITE, false)
	if particles.get_particle_count() != 8:
		_cleanup_nodes([particles, world])
		return _fail_bool("normal impact did not emit the expected ballistic sparks")
	var before := particles.get_particle_snapshot(0)
	particles.simulate_step(0.1)
	var after := particles.get_particle_snapshot(0)
	var before_velocity := before["velocity"] as Vector2
	var after_velocity := after["velocity"] as Vector2
	var expected_particle_gravity := 13.5 * PROFILE_RESOURCE.projectile_gravity_scale
	if absf((after_velocity.y - before_velocity.y) - expected_particle_gravity) > EPSILON:
		_cleanup_nodes([particles, world])
		return _fail_bool("impact particle did not inherit local gravity")
	if float((after["position"] as Vector2).x) <= float((before["position"] as Vector2).x):
		_cleanup_nodes([particles, world])
		return _fail_bool("impact particle did not preserve projectile momentum")

	# Particles use the same position-dependent radial gravity contract as the
	# projectile. Validate every cardinal side instead of only constant screen-down.
	var radial_world := RadialGravity.new()
	root.add_child(radial_world)
	particles.bind_material_world(radial_world)
	var particle_spawns: Array[Vector2] = [
		Vector2(0.0, -1000.0),
		Vector2(1000.0, 0.0),
		Vector2(0.0, 1000.0),
		Vector2(-1000.0, 0.0),
	]
	for spawn in particle_spawns:
		var inward: Vector2 = (radial_world.center - spawn).normalized()
		var tangent := Vector2(-inward.y, inward.x)
		var particle_index := particles.get_particle_count()
		particles.emit_impact(spawn, tangent * 1200.0, Color.WHITE, false)
		var radial_before := particles.get_particle_snapshot(particle_index)
		particles.simulate_step(1.0 / 120.0)
		var radial_after := particles.get_particle_snapshot(particle_index)
		var radial_before_velocity := radial_before["velocity"] as Vector2
		var radial_after_velocity := radial_after["velocity"] as Vector2
		var radial_velocity_delta := radial_after_velocity - radial_before_velocity
		if radial_velocity_delta.dot(inward) <= 1.0:
			_cleanup_nodes([particles, world, radial_world])
			return _fail_bool(
				"particle at %s did not fall radially inward: delta_velocity=%s"
				% [spawn, radial_velocity_delta]
			)
	particles.bind_material_world(world)
	for _burst in range(40):
		particles.emit_impact(Vector2.ZERO, Vector2.RIGHT * 1200.0, Color.WHITE, true)
	if particles.get_particle_count() != CombatBallisticParticleField.MAX_PARTICLES:
		_cleanup_nodes([particles, world, radial_world])
		return _fail_bool(
			"ballistic particle pool exceeded or failed to fill its cap: %d"
			% particles.get_particle_count()
		)
	_cleanup_nodes([particles, world, radial_world])
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
