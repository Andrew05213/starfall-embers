class_name GravityDiagnosticsOverlay
extends Node2D

## Opt-in diagnostic drawing for P4 gravity and transport validation.
## This node is deliberately not part of the formal scene: attaching it to a
## debug scene is the only way to enable the overlay. Dirty chunks are shown as
## dirty transport output, never as an activation scheduler claim.

@export var enabled := false
@export var dirty_chunk_size := 64.0

var _gravity_snapshot: Dictionary = {}
var _primary_snapshot: Dictionary = {}
var _local_sources: Array[Dictionary] = []
var _dirty_chunks: Array[Vector2i] = []
var _warnings: PackedStringArray = []


func set_enabled(next_enabled: bool) -> void:
	enabled = next_enabled
	queue_redraw()


func set_gravity_snapshot(snapshot: Dictionary) -> void:
	_gravity_snapshot = snapshot.duplicate(true)
	queue_redraw()


func set_primary_snapshot(center: Vector2, surface_radius: float, model: String) -> void:
	_primary_snapshot = {
		"center": center,
		"surface_radius": surface_radius,
		"model": model,
	}
	queue_redraw()


func set_local_sources(sources: Array[Dictionary]) -> void:
	_local_sources = sources.duplicate(true)
	queue_redraw()


func set_dirty_chunks(chunks: Array[Vector2i]) -> void:
	_dirty_chunks = chunks.duplicate()
	queue_redraw()


func set_warnings(warnings: PackedStringArray) -> void:
	_warnings = warnings.duplicate()
	queue_redraw()


func _draw() -> void:
	if not enabled:
		return
	var font := ThemeDB.fallback_font
	var lines := PackedStringArray()
	var acceleration: Vector2 = _gravity_snapshot.get("acceleration", Vector2.ZERO)
	var magnitude := float(_gravity_snapshot.get("magnitude", acceleration.length()))
	lines.append("P4 gravity diagnostics")
	lines.append("position=%s  acceleration=%s  magnitude=%.3f" % [
		str(_gravity_snapshot.get("position", Vector2.ZERO)), acceleration, magnitude
	])
	lines.append("dominant_source=%s  tick=%s  zero=%s  transitioning=%s" % [
		str(_gravity_snapshot.get("dominant_source_id", 0)),
		str(_gravity_snapshot.get("tick", 0)),
		str(_gravity_snapshot.get("zero_gravity", false)),
		str(_gravity_snapshot.get("transitioning", false)),
	])
	lines.append("predicted_source=%s  predicted_zero=%s" % [
		str(_gravity_snapshot.get("predicted_dominant_source_id", 0)),
		str(_gravity_snapshot.get("predicted_zero_gravity", false)),
	])
	lines.append("velocity=%s  predicted=%s  predicted_magnitude=%.3f" % [
		str(_gravity_snapshot.get("velocity", Vector2.ZERO)),
		str(_gravity_snapshot.get("predicted_acceleration", Vector2.ZERO)),
		float(_gravity_snapshot.get("predicted_magnitude", 0.0)),
	])
	lines.append("sample_limit=%s  native_tick=%s  fixed_hz=%s" % [
		str(_gravity_snapshot.get("sample_limit_reached", false)),
		str(_gravity_snapshot.get("native_tick", 0)),
		str(_gravity_snapshot.get("fixed_hz", 0)),
	])
	if not _dirty_chunks.is_empty():
		lines.append("dirty chunks (transport only; not activation scheduling): %d" % _dirty_chunks.size())
	else:
		lines.append("dirty chunks (transport only; not activation scheduling): 0")
	if not _primary_snapshot.is_empty():
		lines.append("primary center=%s radius=%.1f model=%s" % [
			str(_primary_snapshot.get("center", Vector2.ZERO)),
			float(_primary_snapshot.get("surface_radius", 0.0)),
			str(_primary_snapshot.get("model", "unknown")),
		])
	lines.append("local fields: %d" % _local_sources.size())
	for warning in _warnings:
		lines.append("WARNING: " + warning)
	for source in _local_sources:
		var field_name := "uniform" if int(source.get("field_kind", 0)) == 1 else "radial"
		lines.append("source %s %s r=%.1f remaining=%s" % [
			str(source.get("source_id", 0)),
			field_name,
			float(source.get("radius", 0.0)),
			str(source.get("remaining_ticks", -1)),
		])
	for index in lines.size():
		draw_string(font, Vector2(12.0, 24.0 + index * 18.0), lines[index],
			HORIZONTAL_ALIGNMENT_LEFT, -1.0, 14, Color(0.85, 0.95, 1.0))

	if not _primary_snapshot.is_empty():
		var primary_center: Vector2 = _primary_snapshot.get("center", Vector2.ZERO)
		var primary_radius := float(_primary_snapshot.get("surface_radius", 0.0))
		if primary_radius > 0.0 and primary_radius < 4_096.0:
			draw_arc(primary_center, primary_radius, 0.0, TAU, 96,
				Color(0.3, 0.7, 1.0, 0.45), 1.5)
	for source in _local_sources:
		var center: Vector2 = source.get("position", source.get("center", Vector2.ZERO))
		var radius := float(source.get("radius", 0.0))
		if radius > 0.0:
			draw_arc(center, radius, 0.0, TAU, 48, Color(1.0, 0.75, 0.25, 0.55), 1.0)
	for chunk in _dirty_chunks:
		var rect := Rect2(Vector2(chunk) * dirty_chunk_size,
			Vector2.ONE * dirty_chunk_size)
		draw_rect(rect, Color(1.0, 0.3, 0.2, 0.55), false, 1.0)
