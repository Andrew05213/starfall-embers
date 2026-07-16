extends SceneTree

const DEMO_SCENE := preload("res://scenes/main.tscn")
const STARSEED_SCRIPT := preload("res://scripts/demo/starseed.gd")


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var demo := DEMO_SCENE.instantiate()
	root.add_child(demo)
	await process_frame
	for _frame in range(8):
		await physics_frame

	var state: Dictionary = demo.get_demo_state()
	if int(state.get("enemies", 0)) != 5:
		_fail("playtest arena did not spawn five material enemies")
		return

	var player = demo.get_node("Player")
	var health_before := float(player.get_state()["health"])
	player.take_damage(10.0)
	if float(player.get_state()["health"]) >= health_before:
		_fail("player damage and health loop did not advance")
		return

	var world = demo.get_node("MaterialWorld")
	var extracted: Dictionary = world.extract_circle(Vector2(320.0, 22.0), 2)
	if int(extracted.get("total", 0)) <= 0:
		_fail("extractor contract could not remove breakable terrain")
		return

	var enemies := get_nodes_in_group("enemies")
	var oil_enemy: Node = null
	for enemy in enemies:
		if enemy.get_kind() == "oil":
			oil_enemy = enemy
			break
	if not is_instance_valid(oil_enemy):
		_fail("playtest arena lacks an oil-bodied enemy")
		return
	var oil_health_before := float(oil_enemy.get_health_ratio())
	var outward: Vector2 = (oil_enemy.global_position - Vector2(320.0, 180.0)).normalized()
	var steam_seed := STARSEED_SCRIPT.new()
	demo.add_child(steam_seed)
	steam_seed.setup(world, oil_enemy.global_position + outward * 14.0, -outward * 150.0, "steam")
	for _frame in range(8):
		await physics_frame
	if is_instance_valid(oil_enemy) and float(oil_enemy.get_health_ratio()) >= oil_health_before:
		_fail("steam starseed did not collide with and damage an oil body")
		return

	enemies = get_nodes_in_group("enemies")
	for index in range(3):
		enemies[index].take_damage(999.0, Vector2.ZERO, "steam")
		await process_frame

	state = demo.get_demo_state()
	if int(state.get("recovered_shards", 0)) < 3:
		_fail("defeated enemies did not award the required core dust")
		return
	if not bool(state.get("objective_armed", false)):
		_fail("gravity relay did not arm after the core-dust objective")
		return

	var objective = demo.get_node("GravityRelay")
	if objective.accept_starseed("steam"):
		_fail("gravity relay accepted the wrong starseed type")
		return
	if not objective.accept_starseed("gravity"):
		_fail("armed gravity relay rejected an attraction starseed")
		return
	await process_frame
	state = demo.get_demo_state()
	if str(state.get("status", "")) != "won":
		_fail("completed relay did not close the playable loop")
		return

	print("gameplay smoke: PASS ", state)
	quit(0)


func _fail(message: String) -> void:
	push_error("gameplay smoke: FAIL: " + message)
	quit(1)
