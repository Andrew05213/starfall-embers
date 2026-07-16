extends CanvasLayer

## Compact 640x360 combat HUD for the playable mechanics slice.

const AMBER := Color("#f6b94a")
const AMBER_BRIGHT := Color("#ffd98a")
const AMBER_DIM := Color("#9d6b2f")
const INK := Color("#07090d")
const PANEL := Color("#10151cee")
const TEXT := Color("#e8dfcf")
const TEXT_DIM := Color("#8c94a0")
const READY := Color("#72d6a0")
const DANGER := Color("#ef6f6c")
const ENERGY := Color("#69c5dd")
const MATTER := Color("#b591d4")

var _status_label: Label
var _fps_value: Label
var _active_pixels_value: Label
var _enemy_value: Label
var _health_bar: ProgressBar
var _health_value: Label
var _energy_bar: ProgressBar
var _energy_value: Label
var _matter_bar: ProgressBar
var _matter_value: Label
var _cooldown_bar: ProgressBar
var _cooldown_value: Label
var _objective_title: Label
var _objective_progress: Label
var _objective_detail: Label
var _seed_name: Label
var _seed_subtitle: Label
var _seed_cost: Label
var _seed_swatch: ColorRect
var _seed_key: Label
var _message_label: Label
var _message_tween: Tween
var _end_panel: Panel
var _end_title: Label
var _end_detail: Label
var _fps_accumulator := 0.0
var _external_fps := false


func _ready() -> void:
	layer = 20
	_build_interface()
	set_process(true)


func _process(delta: float) -> void:
	if _external_fps:
		return
	_fps_accumulator += delta
	if _fps_accumulator >= 0.25 and is_instance_valid(_fps_value):
		_fps_accumulator = 0.0
		_fps_value.text = "%d" % Engine.get_frames_per_second()


func set_stats(stats: Dictionary) -> void:
	if stats.has("status"):
		set_status(str(stats["status"]))
	if stats.has("fps") and is_instance_valid(_fps_value):
		_external_fps = true
		_fps_value.text = _format_number(stats["fps"])
	if stats.has("active_pixels") and is_instance_valid(_active_pixels_value):
		_active_pixels_value.text = _format_number(stats["active_pixels"])
	if stats.has("enemies") and is_instance_valid(_enemy_value):
		_enemy_value.text = _format_number(stats["enemies"])


func set_status(text: String) -> void:
	if is_instance_valid(_status_label):
		_status_label.text = text.to_upper()


func set_player_state(state: Dictionary) -> void:
	_set_meter(
		_health_bar,
		_health_value,
		float(state.get("health", 0.0)),
		float(state.get("max_health", 100.0)),
		"%d / %d"
	)
	_set_meter(
		_energy_bar,
		_energy_value,
		float(state.get("energy", 0.0)),
		float(state.get("max_energy", 120.0)),
		"%d / %d"
	)
	_set_meter(
		_matter_bar,
		_matter_value,
		float(state.get("matter", 0.0)),
		float(state.get("max_matter", 100.0)),
		"%d / %d"
	)


func set_objective(title: String, current: int, total: int, detail: String) -> void:
	if is_instance_valid(_objective_title):
		_objective_title.text = title
	if is_instance_valid(_objective_progress):
		_objective_progress.text = "%d / %d" % [current, total]
		_objective_progress.add_theme_color_override("font_color", READY if current >= total else AMBER)
	if is_instance_valid(_objective_detail):
		_objective_detail.text = detail


func set_cooldown(ratio: float) -> void:
	var charge := clampf(ratio, 0.0, 1.0)
	if is_instance_valid(_cooldown_bar):
		_cooldown_bar.value = charge * 100.0
	if is_instance_valid(_cooldown_value):
		_cooldown_value.text = "READY" if charge >= 0.995 else "%02d%%" % roundi(charge * 100.0)
		_cooldown_value.add_theme_color_override("font_color", READY if charge >= 0.995 else AMBER_BRIGHT)


func set_selected_seed(key: int, name: String, subtitle: String, cost: String, color: Color) -> void:
	if is_instance_valid(_seed_key):
		_seed_key.text = "[ %d ]" % key
	if is_instance_valid(_seed_name):
		_seed_name.text = name
	if is_instance_valid(_seed_subtitle):
		_seed_subtitle.text = subtitle
	if is_instance_valid(_seed_cost):
		_seed_cost.text = cost
	if is_instance_valid(_seed_swatch):
		_seed_swatch.color = color


## Compatibility alias retained for the architecture contract test.
func set_selected_material(id: Variant, name: String, color: Color) -> void:
	set_selected_seed(int(id), name, "调试物质", "", color)


func flash_message(text: String, color: Color = Color.WHITE) -> void:
	if not is_instance_valid(_message_label):
		return
	if is_instance_valid(_message_tween):
		_message_tween.kill()
	_message_label.text = text
	_message_label.add_theme_color_override("font_color", color)
	_message_label.modulate = Color.WHITE
	_message_label.visible = true
	_message_tween = create_tween()
	_message_tween.tween_interval(1.5)
	_message_tween.tween_property(_message_label, "modulate:a", 0.0, 0.35)
	_message_tween.tween_callback(_message_label.hide)


func show_end_state(success: bool, title: String, detail: String) -> void:
	if not is_instance_valid(_end_panel):
		return
	_end_panel.visible = true
	_end_title.text = title
	_end_title.add_theme_color_override("font_color", READY if success else DANGER)
	_end_detail.text = detail


func clear_end_state() -> void:
	if is_instance_valid(_end_panel):
		_end_panel.visible = false


func _build_interface() -> void:
	var root := Control.new()
	root.name = "DemoHUDRoot"
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	_build_mission_panel(root)
	_build_player_panel(root)
	_build_action_bar(root)
	_build_seed_panel(root)
	_build_message(root)
	_build_end_panel(root)


func _build_mission_panel(root: Control) -> void:
	var panel := _make_panel("MissionTelemetry", Vector2(12, 10), Vector2(252, 112))
	root.add_child(panel)
	var accent := ColorRect.new()
	accent.position = Vector2.ZERO
	accent.size = Vector2(3, 112)
	accent.color = AMBER
	accent.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(accent)

	var title := _make_label("坠星余烬", 15, AMBER_BRIGHT)
	title.position = Vector2(12, 7)
	title.size = Vector2(100, 20)
	panel.add_child(title)
	_status_label = _make_label("地表勘探中", 8, AMBER)
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_status_label.position = Vector2(128, 9)
	_status_label.size = Vector2(112, 16)
	panel.add_child(_status_label)

	_objective_title = _make_label("回收坠核尘", 11, TEXT)
	_objective_title.position = Vector2(13, 32)
	_objective_title.size = Vector2(150, 18)
	panel.add_child(_objective_title)
	_objective_progress = _make_label("0 / 3", 11, AMBER)
	_objective_progress.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_objective_progress.position = Vector2(176, 32)
	_objective_progress.size = Vector2(64, 18)
	panel.add_child(_objective_progress)
	_objective_detail = _make_label("击败物质生物", 8, TEXT_DIM)
	_objective_detail.position = Vector2(13, 51)
	_objective_detail.size = Vector2(227, 26)
	_objective_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	panel.add_child(_objective_detail)

	_add_telemetry(panel, "FPS", 86, "--", "fps")
	_add_telemetry(panel, "像素", 101, "0", "pixels")
	_add_telemetry(panel, "敌人", 101, "0", "enemies", 126)


func _build_player_panel(root: Control) -> void:
	var panel := _make_panel("PlayerState", Vector2(420, 10), Vector2(208, 126))
	root.add_child(panel)
	var title := _make_label("回响体状态", 10, TEXT)
	title.position = Vector2(10, 6)
	title.size = Vector2(100, 16)
	panel.add_child(title)
	_health_bar = _add_meter(panel, "生命", 28, DANGER)
	_health_value = panel.get_node("HealthValue") as Label
	_energy_bar = _add_meter(panel, "核力", 56, ENERGY)
	_energy_value = panel.get_node("EnergyValue") as Label
	_matter_bar = _add_meter(panel, "物质", 84, MATTER)
	_matter_value = panel.get_node("MatterValue") as Label

	_cooldown_bar = ProgressBar.new()
	_cooldown_bar.position = Vector2(10, 113)
	_cooldown_bar.size = Vector2(134, 6)
	_cooldown_bar.show_percentage = false
	_cooldown_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cooldown_bar.add_theme_stylebox_override("background", _style_box(Color("080b10"), Color("252b34"), 0, 1))
	_cooldown_bar.add_theme_stylebox_override("fill", _style_box(AMBER, AMBER, 0, 1))
	panel.add_child(_cooldown_bar)
	_cooldown_value = _make_label("READY", 8, READY)
	_cooldown_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_cooldown_value.position = Vector2(148, 106)
	_cooldown_value.size = Vector2(50, 16)
	panel.add_child(_cooldown_value)


func _build_action_bar(root: Control) -> void:
	var panel := _make_panel("ActionGuide", Vector2(12, 302), Vector2(394, 46))
	root.add_child(panel)
	var marker := _make_label("玩法操作", 8, AMBER)
	marker.position = Vector2(10, 4)
	marker.size = Vector2(60, 12)
	panel.add_child(marker)
	var controls := _make_label("A/D 移动   W/SPACE 跳跃   SHIFT 推进   LMB/F 星种", 8, TEXT)
	controls.position = Vector2(10, 17)
	controls.size = Vector2(376, 13)
	panel.add_child(controls)
	var secondary := _make_label("RMB 采掘   1/2/3 切换构筑   滚轮切换   R 重开", 8, TEXT_DIM)
	secondary.position = Vector2(10, 31)
	secondary.size = Vector2(376, 12)
	panel.add_child(secondary)


func _build_seed_panel(root: Control) -> void:
	var panel := _make_panel("SeedLoadout", Vector2(414, 276), Vector2(214, 72))
	root.add_child(panel)
	var caption := _make_label("星种构筑 // LOADOUT", 8, TEXT_DIM)
	caption.position = Vector2(10, 5)
	caption.size = Vector2(150, 12)
	panel.add_child(caption)
	_seed_key = _make_label("[ 1 ]", 9, AMBER)
	_seed_key.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_seed_key.position = Vector2(164, 5)
	_seed_key.size = Vector2(40, 13)
	panel.add_child(_seed_key)
	_seed_swatch = ColorRect.new()
	_seed_swatch.position = Vector2(10, 24)
	_seed_swatch.size = Vector2(8, 36)
	_seed_swatch.color = AMBER
	_seed_swatch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(_seed_swatch)
	_seed_name = _make_label("引核星种", 11, AMBER_BRIGHT)
	_seed_name.position = Vector2(26, 20)
	_seed_name.size = Vector2(100, 18)
	panel.add_child(_seed_name)
	_seed_subtitle = _make_label("吸附 / 锚定", 8, TEXT)
	_seed_subtitle.position = Vector2(26, 38)
	_seed_subtitle.size = Vector2(174, 13)
	panel.add_child(_seed_subtitle)
	_seed_cost = _make_label("核力30  物质12", 8, TEXT_DIM)
	_seed_cost.position = Vector2(26, 53)
	_seed_cost.size = Vector2(174, 12)
	panel.add_child(_seed_cost)


func _build_message(root: Control) -> void:
	_message_label = _make_label("", 10, TEXT)
	_message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_message_label.position = Vector2(135, 258)
	_message_label.size = Vector2(370, 20)
	_message_label.visible = false
	root.add_child(_message_label)


func _build_end_panel(root: Control) -> void:
	_end_panel = _make_panel("EndState", Vector2(150, 126), Vector2(340, 100))
	_end_panel.visible = false
	root.add_child(_end_panel)
	var marker := _make_label("PLAYTEST RESULT", 8, TEXT_DIM)
	marker.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	marker.position = Vector2(10, 10)
	marker.size = Vector2(320, 14)
	_end_panel.add_child(marker)
	_end_title = _make_label("", 20, READY)
	_end_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_end_title.position = Vector2(10, 29)
	_end_title.size = Vector2(320, 28)
	_end_panel.add_child(_end_title)
	_end_detail = _make_label("", 9, TEXT)
	_end_detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_end_detail.position = Vector2(10, 65)
	_end_detail.size = Vector2(320, 18)
	_end_panel.add_child(_end_detail)


func _add_meter(panel: Panel, caption: String, y: float, color: Color) -> ProgressBar:
	var key := "Health" if caption == "生命" else ("Energy" if caption == "核力" else "Matter")
	var label := _make_label(caption, 8, TEXT_DIM)
	label.position = Vector2(10, y - 3)
	label.size = Vector2(38, 13)
	panel.add_child(label)
	var bar := ProgressBar.new()
	bar.position = Vector2(48, y)
	bar.size = Vector2(92, 7)
	bar.min_value = 0.0
	bar.max_value = 100.0
	bar.value = 100.0
	bar.show_percentage = false
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_theme_stylebox_override("background", _style_box(Color("080b10"), Color("252b34"), 0, 1))
	bar.add_theme_stylebox_override("fill", _style_box(color, color, 0, 1))
	panel.add_child(bar)
	var value := _make_label("-- / --", 8, TEXT)
	value.name = key + "Value"
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value.position = Vector2(143, y - 4)
	value.size = Vector2(55, 14)
	panel.add_child(value)
	return bar


func _add_telemetry(
	panel: Panel,
	caption: String,
	y: float,
	value: String,
	key: String,
	x: float = 13.0
) -> void:
	var label := _make_label(caption, 8, TEXT_DIM)
	label.position = Vector2(x, y)
	label.size = Vector2(42, 12)
	panel.add_child(label)
	var value_label := _make_label(value, 8, TEXT)
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value_label.position = Vector2(x + 43, y)
	value_label.size = Vector2(52, 12)
	panel.add_child(value_label)
	match key:
		"fps":
			_fps_value = value_label
		"pixels":
			_active_pixels_value = value_label
		"enemies":
			_enemy_value = value_label


func _set_meter(bar: ProgressBar, value_label: Label, value: float, maximum: float, format: String) -> void:
	if is_instance_valid(bar):
		bar.value = clampf(value / maxf(maximum, 1.0), 0.0, 1.0) * 100.0
	if is_instance_valid(value_label):
		value_label.text = format % [roundi(value), roundi(maximum)]


func _make_panel(node_name: String, position: Vector2, size: Vector2) -> Panel:
	var panel := Panel.new()
	panel.name = node_name
	panel.position = position
	panel.size = size
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel", _style_box(PANEL, Color(AMBER_DIM, 0.72), 1, 3))
	return panel


func _make_label(text_value: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text_value
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_shadow_color", Color(INK, 0.9))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	return label


func _style_box(fill: Color, border: Color, width: int, radius: int) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = border
	box.set_border_width_all(width)
	box.set_corner_radius_all(radius)
	return box


func _format_number(value: Variant) -> String:
	if value is float:
		return "%.1f" % value
	return str(value)
