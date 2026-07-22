extends SceneTree

const LAB_SCENE := preload("res://scenes/combat_lab.tscn")
const PROFILE := preload("res://resources/combat/basic_rifle.tres")
const TARGET_SCRIPT := preload("res://scripts/combat/combat_target.gd")
const PROJECTILE_SCRIPT := preload("res://scripts/combat/juvenile_starseed.gd")


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
	var material_world: MaterialWorld = lab.get_node("MaterialWorld") as MaterialWorld
	var player: CombatLabPlayer = lab.get_node("Player") as CombatLabPlayer
	if absf(player.jump_speed - 178.0) > 0.01 or absf(player.terminal_speed - 900.0) > 0.01:
		_fail("combat player does not use the Jingxing jump/terminal-speed balance")
		return
	if absf(float(player.get_state().get("max_energy", 0.0)) - 100.0) > 0.01:
		_fail("combat player max energy is not the 100-point balance baseline")
		return
	if material_world.terrain_generation_mode != "surface_patch":
		_fail("combat lab still generates the small whole asteroid")
		return
	if absf(material_world.primary_surface_radius - 10000.0) > 0.1:
		_fail("combat surface radius is not 10000 world px")
		return
	var core_distance := player.global_position.distance_to(material_world.primary_gravity_center)
	if core_distance < 9800.0 or core_distance > 10200.0:
		_fail("player is not approximately 10000 px from the primary core: %.2f" % core_distance)
		return
	var left_sample := player.global_position + Vector2.LEFT * visible_world_width * 0.5
	var right_sample := player.global_position + Vector2.RIGHT * visible_world_width * 0.5
	var left_gravity: Vector2 = material_world.get_gravity_at(left_sample)
	var right_gravity: Vector2 = material_world.get_gravity_at(right_sample)
	if left_gravity.length() < 315.0 or right_gravity.length() < 315.0:
		_fail("combat patch gravity is no longer close to its configured surface value")
		return
	if left_gravity.length() > 320.01 or right_gravity.length() > 320.01:
		_fail("combat patch gravity exceeds its configured surface value outside the planet")
		return
	var direction_change := acos(clampf(left_gravity.normalized().dot(right_gravity.normalized()), -1.0, 1.0))
	if direction_change > 0.04:
		_fail("gravity varies too much across the local surface patch: %.4f rad" % direction_change)
		return
	var radius: float = material_world.primary_surface_radius
	var surface_g := material_world.get_primary_gravity_magnitude_at_distance(radius)
	var double_radius_g := material_world.get_primary_gravity_magnitude_at_distance(radius * 2.0)
	var quadruple_radius_g := material_world.get_primary_gravity_magnitude_at_distance(radius * 4.0)
	var half_radius_g := material_world.get_primary_gravity_magnitude_at_distance(radius * 0.5)
	var core_g := material_world.get_primary_gravity_magnitude_at_distance(0.0)
	if absf(surface_g - 320.0) > 0.001:
		_fail("primary gravity does not equal surface g at r=R: %.4f" % surface_g)
		return
	if absf(double_radius_g / surface_g - 0.25) > 0.0001:
		_fail("primary gravity does not follow inverse-square falloff at r=2R")
		return
	if absf(quadruple_radius_g / surface_g - 0.0625) > 0.0001:
		_fail("primary gravity does not follow inverse-square falloff at r=4R")
		return
	if absf(half_radius_g / surface_g - 0.5) > 0.0001:
		_fail("interior primary gravity is not continuous uniform-sphere gravity at r=R/2")
		return
	if absf(core_g) > 0.0001:
		_fail("primary gravity is not zero at the core")
		return
	var escape_speed := sqrt(2.0 * surface_g * radius)
	var full_boost_delta := player.boost_acceleration * 100.0 / 35.0
	var conservative_combo_speed := player.jump_speed + full_boost_delta + 125.0
	if conservative_combo_speed >= escape_speed * 0.4:
		_fail(
			"jump+boost+rupture conservative speed lost the 40%% escape margin: %.2f / %.2f"
			% [conservative_combo_speed, escape_speed]
		)
		return
	if player.terminal_speed >= escape_speed * 0.4:
		_fail("player safety cap is no longer below 40% of Jingxing escape speed")
		return
	var crossing_time := visible_world_width / PROFILE.projectile_speed
	var estimated_drop := (
		0.5
		* material_world.get_primary_gravity_at(player.global_position).length()
		* PROFILE.projectile_gravity_scale
		* crossing_time
		* crossing_time
	)
	if estimated_drop < 12.0 or estimated_drop > 20.0:
		_fail("configured one-view projectile drop is outside 12-20 px: %.2f" % estimated_drop)
		return
	if not await _test_surface_patch_and_live_projectile(
		lab,
		material_world,
		visible_world_width
	):
		return
	if not await _test_arena_containment(player, camera, visible_world_width):
		return
	var feedback: CombatFeedback = lab.get_node("CombatFeedback") as CombatFeedback
	for layer in ["cast", "flight", "hit", "death"]:
		if not feedback.has_audio_layer(layer):
			_fail("combat feedback did not generate the %s audio layer" % layer)
			return
	if str(feedback.get_audio_characteristics("cast").get("family", "")) != "crisp_hiss":
		_fail("cast audio is not the short crisp hiss revision")
		return
	if str(feedback.get_audio_characteristics("hit").get("family", "")) != "crisp_impact":
		_fail("hit audio is not the crisp impact revision")
		return

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
	var native_shadow: Dictionary = state.get("native_shadow", {}) as Dictionary
	if not bool(native_shadow.get("enabled", false)):
		_fail("production Combat Lab did not enable the native ballistic shadow")
		return
	if int(native_shadow.get("compared_samples", 0)) < 30:
		_fail("production shadow did not compare enough real projectile samples")
		return
	if int(native_shadow.get("completed_lifetimes", 0)) < 3:
		_fail("production shadow did not observe real projectile lifetime events")
		return
	if int(native_shadow.get("mismatches", -1)) != 0:
		_fail("production shadow reported trajectory/lifetime mismatches: %s" % native_shadow)
		return
	if float(native_shadow.get("max_position_error_px", INF)) > 0.125:
		_fail("production shadow position error exceeded 0.125 px: %s" % native_shadow)
		return
	if float(native_shadow.get("max_velocity_error_px_per_second", INF)) > 0.5:
		_fail("production shadow velocity error exceeded 0.5 px/s: %s" % native_shadow)
		return

	# Fire once through the production player/lab signal path at a real target.
	# The C++ slice does not own collision yet, so Godot reports the impact and
	# the shadow must retire the correlated native projectile in a later batch.
	for _frame in range(8):
		await physics_frame
	var static_target: CombatTarget = lab.get_node("StaticTarget") as CombatTarget
	var target_screen := lab.get_viewport().get_canvas_transform() * static_target.global_position
	player.set_aim_screen_position(target_screen)
	Input.action_press("fire_starseed")
	await physics_frame
	Input.action_release("fire_starseed")
	for _frame in range(10):
		await physics_frame
	native_shadow = lab.get_lab_state().get("native_shadow", {}) as Dictionary
	if int(native_shadow.get("retired_impacts", 0)) < 1:
		_fail("production shadow did not correlate and retire a real impact: %s" % native_shadow)
		return
	if int(native_shadow.get("mismatches", -1)) != 0:
		_fail("production impact retirement introduced a native mismatch: %s" % native_shadow)
		return

	lab.queue_free()
	await process_frame
	if not await _test_grunt_hit_contract():
		return
	print("combat lab smoke: PASS shots=", shots, " screens_per_second=", snappedf(screens_per_second, 0.01))
	quit(0)


func _test_surface_patch_and_live_projectile(
	lab: Node,
	material_world: MaterialWorld,
	visible_world_width: float
) -> bool:
	var center: Vector2 = material_world.primary_gravity_center
	var radius: float = material_world.primary_surface_radius
	# Cell centers are 4 px apart. Sampling six pixels to either side of the
	# analytic surface leaves enough tolerance for rasterization while proving
	# collision and the decorative 10k circle describe the same patch.
	var surface_sample_xs: Array[float] = [0.0, 160.0, 320.0, 480.0, 639.0]
	for x in surface_sample_xs:
		var horizontal: float = x - center.x
		var surface_y: float = (
			center.y - sqrt(maxf(radius * radius - horizontal * horizontal, 0.0))
		)
		var above := Vector2(x, surface_y - 6.0)
		var below := Vector2(x, surface_y + 6.0)
		if material_world.is_solid_at(above):
			return _fail_bool("10k surface patch is solid above its analytic surface at x=%.1f" % x)
		if not material_world.is_solid_at(below):
			return _fail_bool("10k surface patch is empty below its analytic surface at x=%.1f" % x)

	# Exercise the production projectile against the real far-core MaterialWorld.
	# This high path clears targets and terrain, isolating one-view ballistics.
	var projectile: JuvenileStarseed = PROJECTILE_SCRIPT.new()
	lab.add_child(projectile)
	var origin := Vector2(160.0, -60.0)
	projectile.setup(PROFILE, origin, Vector2.RIGHT, Vector2.ZERO, material_world)
	projectile.set_physics_process(false)
	var impacted := [false]
	projectile.impacted.connect(
		func(_target: Node, _point: Vector2, _velocity: Vector2) -> void:
			impacted[0] = true
	)
	# Sixteen production-sized physics steps cross 320 px at 1200 px/s and
	# require gravity to be resampled along the complete trajectory.
	for _step in range(16):
		projectile.simulate_step(1.0 / 60.0)
	var displacement: Vector2 = projectile.global_position - origin
	if bool(impacted[0]) or projectile.is_expired():
		projectile.queue_free()
		await process_frame
		return _fail_bool("live one-view projectile unexpectedly hit or expired")
	if displacement.x < visible_world_width - 5.0 or displacement.x > visible_world_width + 5.0:
		projectile.queue_free()
		await process_frame
		return _fail_bool("live projectile did not cross one visible width: %s" % displacement)
	if displacement.y < 12.0 or displacement.y > 20.0:
		projectile.queue_free()
		await process_frame
		return _fail_bool("live far-core projectile drop is outside 12-20 px: %.3f" % displacement.y)
	projectile.queue_free()
	await process_frame
	return true


func _test_arena_containment(
	player: CombatLabPlayer,
	camera: Camera2D,
	visible_world_width: float
) -> bool:
	if (
		not player.horizontal_arena_enabled
		or absf(player.arena_min_x - 162.0) > 0.01
		or absf(player.arena_max_x - 478.0) > 0.01
	):
		return _fail_bool("combat player does not use the 162..478 Gate-1 containment")

	var test_y := player.global_position.y
	player.global_position = Vector2(player.arena_min_x - 24.0, test_y)
	player.velocity = Vector2(-255.0, 0.0)
	for _frame in range(2):
		await physics_frame
	if player.global_position.x < player.arena_min_x - 0.01 or player.velocity.x < -0.01:
		return _fail_bool(
			"left arena edge did not clamp position/outward velocity: pos=%s velocity=%s"
			% [player.global_position, player.velocity]
		)
	var left_clamped_x := player.global_position.x
	for _frame in range(6):
		await physics_frame
	if player.global_position.x < left_clamped_x - 0.01:
		return _fail_bool("player continued moving outward after the left containment clamp")
	for _frame in range(60):
		await physics_frame
	if camera.global_position.x - visible_world_width * 0.5 < -0.5:
		return _fail_bool("camera view left the generated patch at the left arena edge")

	player.global_position = Vector2(player.arena_max_x + 24.0, test_y)
	player.velocity = Vector2(255.0, 0.0)
	for _frame in range(2):
		await physics_frame
	if player.global_position.x > player.arena_max_x + 0.01 or player.velocity.x > 0.01:
		return _fail_bool(
			"right arena edge did not clamp position/outward velocity: pos=%s velocity=%s"
			% [player.global_position, player.velocity]
		)
	var right_clamped_x := player.global_position.x
	for _frame in range(6):
		await physics_frame
	if player.global_position.x > right_clamped_x + 0.01:
		return _fail_bool("player continued moving outward after the right containment clamp")
	for _frame in range(60):
		await physics_frame
	if camera.global_position.x + visible_world_width * 0.5 > 640.5:
		return _fail_bool("camera view left the generated patch at the right arena edge")

	player.reset_combat_player(Vector2(320.0, 10.0))
	for _frame in range(8):
		await physics_frame
	return true


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
