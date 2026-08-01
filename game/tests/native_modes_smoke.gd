extends SceneTree

const LAB_SCENE := preload("res://scenes/combat_lab.tscn")
const PROFILE := preload("res://resources/combat/basic_rifle.tres")
const PROJECTILE_SCRIPT := preload("res://scripts/combat/juvenile_starseed.gd")


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var lab := LAB_SCENE.instantiate()
	root.add_child(lab)
	await process_frame
	var runtime: NativeBallisticsShadow = lab.get_node("NativeBallisticsShadow")
	var world: MaterialWorld = lab.get_node("MaterialWorld")
	assert(runtime.get_mode() == NativeBallisticsShadow.MODE_NATIVE_AUTHORITATIVE)

	# Explicit fallback leaves the accepted 60 Hz GDScript simulation intact and
	# does not register a duplicate native projectile.
	assert(runtime.set_mode(NativeBallisticsShadow.MODE_GDSCRIPT_FALLBACK))
	var fallback: JuvenileStarseed = PROJECTILE_SCRIPT.new()
	lab.add_child(fallback)
	fallback.setup(PROFILE, Vector2(160.0, -60.0), Vector2.RIGHT, Vector2.ZERO, world)
	fallback.set_physics_process(false)
	runtime.track_projectile(fallback, PROFILE)
	var fallback_origin := fallback.global_position
	fallback.simulate_step(1.0 / 60.0)
	assert(fallback.global_position.x > fallback_origin.x)
	assert(int(runtime.get_snapshot().active) == 0)
	fallback.queue_free()
	await process_frame

	# Shadow mode still compares the independently running GDScript projectile.
	assert(runtime.set_mode(NativeBallisticsShadow.MODE_NATIVE_SHADOW))
	var shadow: JuvenileStarseed = PROJECTILE_SCRIPT.new()
	lab.add_child(shadow)
	shadow.setup(PROFILE, Vector2(160.0, -60.0), Vector2.RIGHT, Vector2.ZERO, world)
	runtime.track_projectile(shadow, PROFILE)
	for _frame in range(36):
		await physics_frame
	var shadow_snapshot := runtime.get_snapshot()
	assert(int(shadow_snapshot.compared_samples) > 0)
	assert(int(shadow_snapshot.completed_lifetimes) == 1)
	assert(int(shadow_snapshot.mismatches) == 0)

	# Authoritative mode disables GDScript advancement and emits one gameplay hit
	# from the native event batch. The target receives damage exactly once.
	assert(runtime.set_mode(NativeBallisticsShadow.MODE_NATIVE_AUTHORITATIVE))
	var target: CombatTarget = lab.get_node("StaticTarget")
	var initial_health := target.get_health_ratio()
	var impacts := [0]
	var authoritative: JuvenileStarseed = PROJECTILE_SCRIPT.new()
	lab.add_child(authoritative)
	authoritative.setup(
		PROFILE,
		target.global_position + Vector2.LEFT * 30.0,
		Vector2.RIGHT,
		Vector2.ZERO,
		world
	)
	authoritative.impacted.connect(
		func(_target: Node, _point: Vector2, _velocity: Vector2) -> void:
			impacts[0] += 1
	)
	runtime.track_projectile(authoritative, PROFILE)
	for _frame in range(8):
		await physics_frame
	assert(int(impacts[0]) == 1)
	assert(target.get_health_ratio() < initial_health)
	assert(int(runtime.get_snapshot().native_entity_hits) == 1)

	var terrain_impacts := [0]
	var terrain_projectile: JuvenileStarseed = PROJECTILE_SCRIPT.new()
	lab.add_child(terrain_projectile)
	terrain_projectile.setup(PROFILE, Vector2(100.0, 0.0), Vector2.DOWN, Vector2.ZERO, world)
	terrain_projectile.impacted.connect(
		func(hit_target: Node, _point: Vector2, _velocity: Vector2) -> void:
			assert(hit_target == null)
			terrain_impacts[0] += 1
	)
	runtime.track_projectile(terrain_projectile, PROFILE)
	for _frame in range(8):
		await physics_frame
	assert(int(terrain_impacts[0]) == 1)
	assert(int(runtime.get_snapshot().native_terrain_hits) == 1)

	# Pausing the scene tree freezes the authoritative fixed tick. Reconfigure is
	# the restart boundary and returns the native host to tick zero.
	var tick_before_pause := int(runtime.get_snapshot().native_tick)
	paused = true
	for _frame in range(4):
		await physics_frame
	assert(int(runtime.get_snapshot().native_tick) == tick_before_pause)
	paused = false
	assert(runtime.configure(world))
	assert(int(runtime.get_snapshot().native_tick) == 0)

	lab.queue_free()
	await process_frame
	print("native modes smoke: PASS")
	quit(0)
