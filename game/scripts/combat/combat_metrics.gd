class_name CombatMetrics
extends CanvasLayer

## On-screen instrumentation for the subjective Gate-1 playtest.

var _clock := 0.0
var _shot_times := PackedFloat32Array()
var _shots_total := 0
var _hits_total := 0
var _deaths_total := 0
var _trigger_time := -1.0
var _first_shot_latency_ms := -1.0
var _native_shadow_snapshot: Dictionary = {}
var _status_label: Label
var _help_label: Label


func _ready() -> void:
	_status_label = Label.new()
	_status_label.position = Vector2(10, 8)
	_status_label.add_theme_color_override("font_color", Color("d9fff4"))
	_status_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	_status_label.add_theme_constant_override("shadow_offset_x", 1)
	_status_label.add_theme_constant_override("shadow_offset_y", 1)
	add_child(_status_label)

	_help_label = Label.new()
	_help_label.position = Vector2(10, 304)
	_help_label.text = "A/D 移动 · W/Space 跳跃 · 按住左键/F 连射 · R 重置靶场 · Esc 返回主场景"
	_help_label.add_theme_font_size_override("font_size", 11)
	_help_label.add_theme_color_override("font_color", Color("a9bcc7"))
	add_child(_help_label)
	_refresh_label()


func _process(delta: float) -> void:
	_clock += maxf(delta, 0.0)
	while not _shot_times.is_empty() and _clock - _shot_times[0] > 1.0:
		_shot_times.remove_at(0)
	_refresh_label()


func record_trigger(_timestamp: float) -> void:
	_trigger_time = _clock


func record_shot(_timestamp: float, _direction: Vector2) -> void:
	_shots_total += 1
	_shot_times.append(_clock)
	if _trigger_time >= 0.0:
		_first_shot_latency_ms = maxf(0.0, (_clock - _trigger_time) * 1000.0)
		_trigger_time = -1.0


func record_hit() -> void:
	_hits_total += 1


func record_death() -> void:
	_deaths_total += 1


func reset_metrics() -> void:
	_clock = 0.0
	_shot_times.clear()
	_shots_total = 0
	_hits_total = 0
	_deaths_total = 0
	_trigger_time = -1.0
	_first_shot_latency_ms = -1.0
	_refresh_label()


func set_native_shadow_snapshot(snapshot: Dictionary) -> void:
	_native_shadow_snapshot = snapshot


func get_snapshot() -> Dictionary:
	return {
		"shots": _shots_total,
		"hits": _hits_total,
		"deaths": _deaths_total,
		"shots_last_second": _shot_times.size(),
		"first_shot_latency_ms": _first_shot_latency_ms,
		"accuracy": float(_hits_total) / float(maxi(_shots_total, 1)),
	}


func _refresh_label() -> void:
	if not is_instance_valid(_status_label):
		return
	var latency := "--" if _first_shot_latency_ms < 0.0 else "%.1f ms" % _first_shot_latency_ms
	var shadow_line := "C++ 影子：未加载"
	if bool(_native_shadow_snapshot.get("enabled", false)):
		shadow_line = (
			"C++ 影子：%d 样本   最大漂移 %.3f px / %.3f px·s⁻¹   异常 %d"
			% [
				int(_native_shadow_snapshot.get("compared_samples", 0)),
				float(_native_shadow_snapshot.get("max_position_error_px", 0.0)),
				float(_native_shadow_snapshot.get("max_velocity_error_px_per_second", 0.0)),
				int(_native_shadow_snapshot.get("mismatches", 0)),
			]
		)
	var combat_line := (
		"射击：%d   命中：%d   击杀：%d   命中率：%d%%"
		% [
			_shots_total,
			_hits_total,
			_deaths_total,
			roundi(float(_hits_total) / float(maxi(_shots_total, 1)) * 100.0),
		]
	)
	_status_label.text = (
		"枪感实验场 / Gate 1\n"
		+ "射速：%d 发/秒   首发延迟：%s\n" % [_shot_times.size(), latency]
		+ combat_line
		+ "\n"
		+ shadow_line
	)
