class_name DemoObjective
extends Node2D

## A dormant local gravity relay. It becomes the final target after enough core dust is recovered.

signal completed

var collision_radius := 12.0
var armed := false
var complete := false
var _pulse_time := 0.0


func _ready() -> void:
	add_to_group("objectives")
	queue_redraw()


func _process(delta: float) -> void:
	_pulse_time += delta
	queue_redraw()


func reset_objective() -> void:
	armed = false
	complete = false
	_pulse_time = 0.0
	queue_redraw()


func arm() -> void:
	if complete:
		return
	armed = true
	queue_redraw()


func accept_starseed(seed_type: String) -> bool:
	if not armed or complete or seed_type != "gravity":
		return false
	complete = true
	armed = false
	completed.emit()
	queue_redraw()
	return true


func _draw() -> void:
	var pulse := 0.5 + 0.5 * sin(_pulse_time * (5.0 if armed else 2.0))
	var frame_color := Color("6c6260")
	var core_color := Color("3b414b")
	if armed:
		frame_color = Color("f6b94a")
		core_color = Color("8de4cf")
	elif complete:
		frame_color = Color("8de4cf")
		core_color = Color("fff2b8")

	draw_arc(Vector2.ZERO, 12.0 + pulse * 2.0, 0.0, TAU, 32, Color(frame_color, 0.55), 1.0)
	draw_rect(Rect2(-8, -7, 16, 14), Color("161b22"))
	draw_rect(Rect2(-8, -7, 16, 14), frame_color, false, 1.0)
	for index in range(4):
		var angle := _pulse_time * (0.7 if armed else 0.2) + float(index) * TAU / 4.0
		var point := Vector2.from_angle(angle) * (8.5 + pulse)
		draw_circle(point, 1.2, frame_color)
	draw_circle(Vector2.ZERO, 3.0 + pulse, core_color)
	draw_circle(Vector2.ZERO, 1.2, Color("fff4ca"))
