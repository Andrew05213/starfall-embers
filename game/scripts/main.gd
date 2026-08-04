extends Node2D

const STARSEED_SCRIPT := preload("res://scripts/demo/starseed.gd")
const ENEMY_SCRIPT := preload("res://scripts/demo/demo_enemy.gd")
const OBJECTIVE_SCRIPT := preload("res://scripts/demo/demo_objective.gd")

const REQUIRED_SHARDS := 3
const ASTEROID_CENTER := Vector2(320.0, 180.0)
const SEED_ORDER := ["gravity", "steam", "rupture"]
const SEED_DATA := {
	"gravity": {
		"name": "引核星种",
		"subtitle": "吸附 / 锚定 / 终局钥匙",
		"color": Color("f6b94a"),
		"cost": "核力30  物质12",
	},
	"steam": {
		"name": "蒸汽矛",
		"subtitle": "爆发 / 灭火 / 克制油体",
		"color": Color("73d9ed"),
		"cost": "核力24  物质16",
	},
	"rupture": {
		"name": "斥裂核",
		"subtitle": "排斥 / 群控 / 轨迹改写",
		"color": Color("d176ef"),
		"cost": "核力38  物质20",
	},
}

@onready var material_world = $MaterialWorld
@onready var gravity_runtime: NativeGravityRuntime = $NativeGravityRuntime
@onready var player = $Player
@onready var hud = $HUD
@onready var gravity_overlay: GravityDiagnosticsOverlay = $GravityDiagnosticsOverlay

var selected_seed_index := 0
var recovered_shards := 0
var demo_status := "playing"
var stats_accumulator := 0.0
var _objective: Node2D
var _extractor_start := Vector2.ZERO
var _extractor_end := Vector2.ZERO
var _extractor_flash := 0.0


func _ready() -> void:
	if is_instance_valid(gravity_runtime):
		player.set_gravity_provider(gravity_runtime.get_provider())
	player.starseed_requested.connect(_on_starseed_requested)
	player.extractor_requested.connect(_on_extractor_requested)
	player.state_changed.connect(_on_player_state_changed)
	player.action_denied.connect(_on_action_denied)
	player.died.connect(_on_player_died)
	material_world.stats_changed.connect(_on_simulation_stats_changed)
	_create_objective()
	_select_seed(0)
	_reset_demo()
	_update_gravity_diagnostics()
	queue_redraw()


func _process(delta: float) -> void:
	stats_accumulator += delta
	_extractor_flash = maxf(0.0, _extractor_flash - delta)
	if stats_accumulator >= 0.2:
		stats_accumulator = 0.0
		_refresh_hud(material_world.get_stats())
	if player.has_method("get_cooldown_ratio"):
		hud.set_cooldown(player.get_cooldown_ratio())
	_update_gravity_diagnostics()
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_1:
				_select_seed(0)
			KEY_2:
				_select_seed(1)
			KEY_3:
				_select_seed(2)
			KEY_R:
				_reset_demo()
			KEY_F3:
				if is_instance_valid(gravity_overlay):
					gravity_overlay.set_enabled(not gravity_overlay.enabled)
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_select_seed(selected_seed_index - 1)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_select_seed(selected_seed_index + 1)


func get_demo_state() -> Dictionary:
	return {
		"status": demo_status,
		"recovered_shards": recovered_shards,
		"required_shards": REQUIRED_SHARDS,
		"enemies": get_tree().get_nodes_in_group("enemies").size(),
		"objective_armed": bool(_objective.get("armed")) if is_instance_valid(_objective) else false,
		"player": player.get_state() if player.has_method("get_state") else {},
	}


func _draw() -> void:
	draw_rect(Rect2(0.0, 0.0, 640.0, 360.0), Color("070b14"))
	for index in range(72):
		var x := float((index * 83 + 29) % 640)
		var y := float((index * 47 + 11) % 360)
		var brightness := 0.25 + float(index % 5) * 0.08
		draw_circle(
			Vector2(x, y),
			0.6 + float(index % 3) * 0.25,
			Color(brightness, brightness, brightness * 1.15, 0.8)
		)
	if _extractor_flash > 0.0:
		draw_line(_extractor_start, _extractor_end, Color("81f0cf"), 1.5)
		draw_circle(_extractor_end, 3.0 + _extractor_flash * 9.0, Color(0.5, 0.95, 0.8, 0.45), false, 1.0)


func _create_objective() -> void:
	_objective = OBJECTIVE_SCRIPT.new()
	_objective.name = "GravityRelay"
	_objective.position = Vector2(430.0, 47.0)
	_objective.z_index = 8
	add_child(_objective)
	_objective.completed.connect(_on_objective_completed)


func _spawn_enemies() -> void:
	var entries := [
		{"angle": -2.55, "kind": "stone"},
		{"angle": -0.22, "kind": "oil"},
		{"angle": 1.05, "kind": "spore"},
		{"angle": 2.18, "kind": "oil"},
		{"angle": 3.02, "kind": "stone"},
	]
	for entry in entries:
		var enemy := ENEMY_SCRIPT.new()
		enemy.z_index = 9
		add_child(enemy)
		var spawn_position := ASTEROID_CENTER + Vector2.from_angle(float(entry["angle"])) * 171.0
		enemy.setup(material_world, player, spawn_position, str(entry["kind"]))
		enemy.defeated.connect(_on_enemy_defeated)


func _on_starseed_requested(origin: Vector2, launch_velocity: Vector2, seed_type: String) -> void:
	if demo_status != "playing":
		return
	var starseed := STARSEED_SCRIPT.new()
	add_child(starseed)
	starseed.z_index = 11
	starseed.setup(
		material_world,
		origin,
		launch_velocity,
		seed_type,
		gravity_runtime.get_provider() if is_instance_valid(gravity_runtime) else null
	)
	starseed.impacted.connect(_on_starseed_impacted)
	hud.flash_message("%s已释放。" % str(SEED_DATA[seed_type]["name"]), SEED_DATA[seed_type]["color"])
	_refresh_hud(material_world.get_stats())


func _on_starseed_impacted(_position: Vector2, seed_type: String) -> void:
	match seed_type:
		"steam":
			hud.flash_message("蒸汽爆发：油体与孢子受到额外伤害。", Color("73d9ed"))
		"rupture":
			hud.flash_message("排斥场展开：附近目标与物质被推离。", Color("d176ef"))
		_:
			hud.flash_message("引核锚定：局部坠律已改写。", Color("f6b94a"))


func _on_extractor_requested(origin: Vector2, direction: Vector2) -> void:
	if demo_status != "playing":
		return
	_extractor_start = origin
	_extractor_end = origin + direction * 72.0
	var extracted_total := 0
	for distance in range(12, 77, 4):
		var point := origin + direction * float(distance)
		if not material_world.is_solid_at(point):
			continue
		var extracted: Dictionary = material_world.extract_circle(point, 1)
		extracted_total = int(extracted.get("total", 0))
		_extractor_end = point
		break
	_extractor_flash = 0.12
	if extracted_total > 0:
		var gained: float = player.add_matter(float(extracted_total) * 0.65)
		if gained > 0.0:
			hud.flash_message("采掘 +%d 物质" % maxi(1, roundi(gained)), Color("81f0cf"))


func _on_enemy_defeated(_enemy: Node, reward: int) -> void:
	if demo_status != "playing":
		return
	recovered_shards += 1
	player.add_matter(float(reward))
	if recovered_shards >= REQUIRED_SHARDS and not bool(_objective.get("armed")):
		_objective.arm()
		hud.flash_message("地维稳定器已解锁：用引核星种命中它。", Color("ffd98a"))
	else:
		hud.flash_message("回收坠核尘 %d/%d" % [recovered_shards, REQUIRED_SHARDS], Color("f6b94a"))
	_update_objective_hud()


func _on_player_state_changed(state: Dictionary) -> void:
	hud.set_player_state(state)


func _on_action_denied(reason: String) -> void:
	hud.flash_message(reason, Color("ef6f6c"))


func _on_player_died() -> void:
	if demo_status != "playing":
		return
	demo_status = "lost"
	player.set_active(false)
	hud.set_status("回响中断")
	hud.show_end_state(false, "物质归零", "按 R 让相邻宇宙中的你继续醒来")


func _on_objective_completed() -> void:
	if demo_status != "playing":
		return
	demo_status = "won"
	player.set_active(false)
	hud.set_status("坠律稳定")
	hud.show_end_state(true, "地维重新对齐", "玩法闭环完成 · 按 R 再试一种构筑")
	hud.flash_message("测试完成：你用物质、重力与构筑恢复了地维。", Color("8de4cf"))


func _on_simulation_stats_changed(stats: Dictionary) -> void:
	_refresh_hud(stats)


func _refresh_hud(stats: Dictionary) -> void:
	var display_stats := stats.duplicate()
	if display_stats.has("active_cells"):
		display_stats["active_pixels"] = display_stats["active_cells"]
	display_stats["starseeds"] = get_tree().get_nodes_in_group("starseeds").size()
	display_stats["enemies"] = get_tree().get_nodes_in_group("enemies").size()
	hud.set_stats(display_stats)
	hud.set_player_state(player.get_state())


func _select_seed(index: int) -> void:
	selected_seed_index = posmod(index, SEED_ORDER.size())
	var seed_type: String = SEED_ORDER[selected_seed_index]
	var data: Dictionary = SEED_DATA[seed_type]
	player.set_starseed_type(seed_type)
	hud.set_selected_seed(
		selected_seed_index + 1,
		str(data["name"]),
		str(data["subtitle"]),
		str(data["cost"]),
		data["color"] as Color
	)


func _update_objective_hud() -> void:
	if demo_status != "playing":
		return
	if recovered_shards < REQUIRED_SHARDS:
		hud.set_objective(
			"回收坠核尘",
			recovered_shards,
			REQUIRED_SHARDS,
			"击败物质生物；观察颜色与环境克制"
		)
	else:
		hud.set_objective(
			"激活地维稳定器",
			1 if bool(_objective.get("complete")) else 0,
			1,
			"切换 [1] 引核星种，命中右上方琥珀装置"
		)


func _reset_demo() -> void:
	for starseed in get_tree().get_nodes_in_group("starseeds"):
		starseed.remove_from_group("starseeds")
		starseed.queue_free()
	for enemy in get_tree().get_nodes_in_group("enemies"):
		enemy.remove_from_group("enemies")
		enemy.queue_free()
	material_world.reset_world()
	if is_instance_valid(gravity_runtime):
		gravity_runtime.reset_runtime()
	player.reset_player(Vector2(320.0, 10.0))
	_objective.reset_objective()
	recovered_shards = 0
	demo_status = "playing"
	_spawn_enemies()
	hud.clear_end_state()
	hud.set_status("地表勘探中")
	_select_seed(0)
	_update_objective_hud()
	hud.flash_message("击败三只物质生物，回收坠核尘。", Color("f0bc67"))
	_refresh_hud(material_world.get_stats())
	_update_gravity_diagnostics()


func _update_gravity_diagnostics() -> void:
	if not is_instance_valid(gravity_overlay) or not is_instance_valid(gravity_runtime):
		return
	var frame: GravityFrame = player.get_gravity_frame() if player.has_method("get_gravity_frame") else null
	if frame == null:
		return
	var snapshot := gravity_runtime.get_snapshot()
	snapshot["position"] = player.global_position
	snapshot["acceleration"] = frame.acceleration
	snapshot["magnitude"] = frame.magnitude
	snapshot["dominant_source_id"] = frame.dominant_source_id
	snapshot["zero_gravity"] = frame.zero_gravity
	snapshot["transitioning"] = frame.transitioning
	snapshot["velocity"] = player.velocity
	snapshot["predicted_acceleration"] = frame.predicted_acceleration
	snapshot["predicted_magnitude"] = frame.predicted_magnitude
	snapshot["predicted_dominant_source_id"] = frame.predicted_dominant_source_id
	snapshot["predicted_zero_gravity"] = frame.predicted_zero_gravity
	gravity_overlay.set_gravity_snapshot(snapshot)
	gravity_overlay.set_primary_snapshot(
		material_world.primary_gravity_center,
		material_world.primary_surface_radius,
		"inside-linear/outside-inverse-square"
	)
	gravity_overlay.set_local_sources(gravity_runtime.get_provider().get_source_snapshots())
	var warnings := PackedStringArray()
	if not bool(snapshot.get("enabled", false)):
		warnings.append(str(snapshot.get("last_diagnostic", "native gravity unavailable")))
	if frame.sample_limit_reached:
		warnings.append("gravity sample limit reached")
	gravity_overlay.set_warnings(warnings)
