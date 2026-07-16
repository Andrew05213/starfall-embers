extends CanvasLayer
## Demo HUD for the 640x360 vertical slice.
##
## The interface is created entirely in code so the early demo has no scene or
## asset dependency. Every Control ignores mouse input; world interactions pass
## through the HUD unchanged.

const AMBER := Color("#f6b94a")
const AMBER_BRIGHT := Color("#ffd98a")
const AMBER_DIM := Color("#9d6b2f")
const INK := Color("#07090d")
const PANEL := Color("#10151cdd")
const TEXT := Color("#e8dfcf")
const TEXT_DIM := Color("#8c94a0")
const READY := Color("#72d6a0")

var _status_label: Label
var _fps_value: Label
var _active_pixels_value: Label
var _starseed_value: Label
var _cooldown_bar: ProgressBar
var _cooldown_value: Label
var _current_material_name: Label
var _current_material_id: Label
var _current_material_swatch: ColorRect
var _message_label: Label
var _message_tween: Tween
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


## Updates any supplied HUD values. Missing entries keep their current values.
## Recognized keys: status, fps, active_pixels and starseed_count (or starseeds).
func set_stats(stats: Dictionary) -> void:
	if stats.has("status") and is_instance_valid(_status_label):
		_status_label.text = str(stats["status"]).to_upper()
	if stats.has("fps") and is_instance_valid(_fps_value):
		_external_fps = true
		_fps_value.text = _format_number(stats["fps"])
	if stats.has("active_pixels") and is_instance_valid(_active_pixels_value):
		_active_pixels_value.text = _format_number(stats["active_pixels"])
	if is_instance_valid(_starseed_value):
		if stats.has("starseed_count"):
			_starseed_value.text = _format_number(stats["starseed_count"])
		elif stats.has("starseeds"):
			_starseed_value.text = _format_number(stats["starseeds"])


## Sets normalized starseed charge progress: 0.0 is empty, 1.0 is ready.
func set_cooldown(ratio: float) -> void:
	var charge := clampf(ratio, 0.0, 1.0)
	if is_instance_valid(_cooldown_bar):
		_cooldown_bar.value = charge * 100.0
	if is_instance_valid(_cooldown_value):
		if charge >= 0.995:
			_cooldown_value.text = "就绪 / READY"
			_cooldown_value.add_theme_color_override("font_color", READY)
		else:
			_cooldown_value.text = "充能 %02d%%" % roundi(charge * 100.0)
			_cooldown_value.add_theme_color_override("font_color", AMBER_BRIGHT)


## Updates the selected material readout and its color swatch.
func set_selected_material(id: Variant, name: String, color: Color) -> void:
	if is_instance_valid(_current_material_name):
		_current_material_name.text = name if not name.is_empty() else "未命名物质"
	if is_instance_valid(_current_material_id):
		_current_material_id.text = "ID  %s" % str(id)
	if is_instance_valid(_current_material_swatch):
		_current_material_swatch.color = color


## Shows a short non-blocking notification above the action bar.
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
	_message_tween.tween_interval(1.35)
	_message_tween.tween_property(_message_label, "modulate:a", 0.0, 0.35)
	_message_tween.tween_callback(_message_label.hide)


func _build_interface() -> void:
	var root := Control.new()
	root.name = "DemoHUDRoot"
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	_build_mission_panel(root)
	_build_cooldown_panel(root)
	_build_action_bar(root)
	_build_material_toolbar(root)
	_build_message(root)


func _build_mission_panel(root: Control) -> void:
	var panel := _make_panel("MissionTelemetry", Vector2(12, 10), Vector2(226, 104))
	root.add_child(panel)

	var accent := ColorRect.new()
	accent.position = Vector2(0, 0)
	accent.size = Vector2(3, 104)
	accent.color = AMBER
	accent.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(accent)

	var title := _make_label("坠星余烬", 16, AMBER_BRIGHT)
	title.position = Vector2(12, 8)
	title.size = Vector2(150, 20)
	panel.add_child(title)

	var designation := _make_label("FALLEN STARS // PROTOTYPE", 8, TEXT_DIM)
	designation.position = Vector2(13, 28)
	designation.size = Vector2(190, 12)
	panel.add_child(designation)

	_status_label = _make_label("地表勘探中", 9, AMBER)
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_status_label.position = Vector2(118, 9)
	_status_label.size = Vector2(96, 18)
	panel.add_child(_status_label)

	var divider := ColorRect.new()
	divider.position = Vector2(12, 45)
	divider.size = Vector2(202, 1)
	divider.color = Color(AMBER_DIM, 0.55)
	divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(divider)

	_add_stat_row(panel, "FPS", 53, "--", "fps")
	_add_stat_row(panel, "活跃像素", 69, "0", "pixels")
	_add_stat_row(panel, "星种库存", 85, "0", "starseeds")


func _build_cooldown_panel(root: Control) -> void:
	var panel := _make_panel("StarseedCooldown", Vector2(436, 10), Vector2(192, 62))
	root.add_child(panel)

	var title := _make_label("星种投放序列", 10, TEXT)
	title.position = Vector2(10, 7)
	title.size = Vector2(100, 16)
	panel.add_child(title)

	var key_hint := _make_label("[ LMB / F ]", 9, AMBER)
	key_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	key_hint.position = Vector2(132, 7)
	key_hint.size = Vector2(50, 16)
	panel.add_child(key_hint)

	_cooldown_bar = ProgressBar.new()
	_cooldown_bar.position = Vector2(10, 30)
	_cooldown_bar.size = Vector2(112, 17)
	_cooldown_bar.min_value = 0.0
	_cooldown_bar.max_value = 100.0
	_cooldown_bar.value = 100.0
	_cooldown_bar.show_percentage = false
	_cooldown_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cooldown_bar.add_theme_stylebox_override(
		"background", _style_box(Color("#080b10"), AMBER_DIM, 1, 2)
	)
	_cooldown_bar.add_theme_stylebox_override("fill", _style_box(AMBER, AMBER_BRIGHT, 0, 1))
	panel.add_child(_cooldown_bar)

	_cooldown_value = _make_label("就绪 / READY", 9, READY)
	_cooldown_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_cooldown_value.position = Vector2(126, 30)
	_cooldown_value.size = Vector2(56, 17)
	panel.add_child(_cooldown_value)


func _build_action_bar(root: Control) -> void:
	var panel := _make_panel("ActionGuide", Vector2(12, 302), Vector2(352, 46))
	root.add_child(panel)

	var marker := _make_label("操作链路", 8, AMBER)
	marker.position = Vector2(10, 4)
	marker.size = Vector2(60, 12)
	panel.add_child(marker)

	var controls := _make_label("A D  移动    W / SPACE  跳跃    LMB / F  星种", 9, TEXT)
	controls.position = Vector2(10, 17)
	controls.size = Vector2(334, 14)
	panel.add_child(controls)

	var secondary := _make_label("RMB  物质刷    1–6 / 滚轮  切换    R  重置", 8, TEXT_DIM)
	secondary.position = Vector2(10, 31)
	secondary.size = Vector2(330, 12)
	panel.add_child(secondary)


func _build_material_toolbar(root: Control) -> void:
	var panel := _make_panel("MaterialToolbar", Vector2(372, 286), Vector2(256, 62))
	root.add_child(panel)

	var title := _make_label("物质容器 // SELECTED", 8, TEXT_DIM)
	title.position = Vector2(10, 5)
	title.size = Vector2(150, 12)
	panel.add_child(title)

	var key_hint := _make_label("[ 1 ]", 9, AMBER)
	key_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	key_hint.position = Vector2(202, 5)
	key_hint.size = Vector2(44, 13)
	panel.add_child(key_hint)

	var swatch_frame := Panel.new()
	swatch_frame.position = Vector2(10, 23)
	swatch_frame.size = Vector2(30, 29)
	swatch_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	swatch_frame.add_theme_stylebox_override("panel", _style_box(INK, AMBER, 1, 2))
	panel.add_child(swatch_frame)

	_current_material_swatch = ColorRect.new()
	_current_material_swatch.position = Vector2(4, 4)
	_current_material_swatch.size = Vector2(22, 21)
	_current_material_swatch.color = Color("#a28f72")
	_current_material_swatch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	swatch_frame.add_child(_current_material_swatch)

	_current_material_name = _make_label("岩尘", 12, AMBER_BRIGHT)
	_current_material_name.position = Vector2(49, 20)
	_current_material_name.size = Vector2(112, 20)
	panel.add_child(_current_material_name)

	_current_material_id = _make_label("ID  rock_dust", 8, TEXT_DIM)
	_current_material_id.position = Vector2(50, 39)
	_current_material_id.size = Vector2(112, 13)
	panel.add_child(_current_material_id)

	var capacity := _make_label("储量", 8, TEXT_DIM)
	capacity.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	capacity.position = Vector2(170, 23)
	capacity.size = Vector2(72, 12)
	panel.add_child(capacity)

	var unlimited := _make_label("∞", 18, AMBER)
	unlimited.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	unlimited.position = Vector2(170, 31)
	unlimited.size = Vector2(72, 23)
	panel.add_child(unlimited)


func _build_message(root: Control) -> void:
	_message_label = _make_label("", 11, TEXT)
	_message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_message_label.position = Vector2(170, 260)
	_message_label.size = Vector2(300, 22)
	_message_label.visible = false
	root.add_child(_message_label)


func _add_stat_row(panel: Panel, caption: String, y: float, value: String, key: String) -> void:
	var caption_label := _make_label(caption, 9, TEXT_DIM)
	caption_label.position = Vector2(13, y)
	caption_label.size = Vector2(100, 14)
	panel.add_child(caption_label)

	var value_label := _make_label(value, 9, TEXT)
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value_label.position = Vector2(115, y)
	value_label.size = Vector2(98, 14)
	panel.add_child(value_label)
	match key:
		"fps":
			_fps_value = value_label
		"pixels":
			_active_pixels_value = value_label
		"starseeds":
			_starseed_value = value_label


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
