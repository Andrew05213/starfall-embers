class_name DemoStarseed
extends Node2D

## A throwable seed that turns into a temporary local gravity source when it hits material.

signal anchored(position: Vector2)
signal expired

@export var gravity_strength: float = 155.0
@export var gravity_radius: float = 105.0
@export var anchored_lifetime: float = 7.0
@export var maximum_flight_time: float = 6.0
@export var collision_radius: float = 2.0
@export var terminal_speed: float = 260.0

const SWEEP_STEP := 1.0

var velocity := Vector2.ZERO

var _material_world: Node
var _gravity_source_id := -1
var _is_anchored := false
var _age := 0.0
var _anchor_age := 0.0
var _cleaned_up := false
var _trail := PackedVector2Array()


func setup(world: Node, origin: Vector2, initial_velocity: Vector2) -> void:
	_material_world = world
	global_position = origin
	velocity = initial_velocity
	_age = 0.0
	_anchor_age = 0.0
	_is_anchored = false
	_cleaned_up = false
	_gravity_source_id = -1
	_trail.clear()
	add_to_group("starseeds")
	queue_redraw()


func _physics_process(delta: float) -> void:
	if _cleaned_up:
		return
	_age += delta

	if _is_anchored:
		_anchor_age += delta
		if (
			_gravity_source_id >= 0
			and is_instance_valid(_material_world)
			and _material_world.has_method("update_gravity_source")
		):
			_material_world.call("update_gravity_source", _gravity_source_id, global_position)
		if _anchor_age >= anchored_lifetime:
			_expire()
		else:
			queue_redraw()
		return

	if _age >= maximum_flight_time or not is_instance_valid(_material_world):
		_expire()
		return

	var gravity := Vector2.ZERO
	if _material_world.has_method("get_gravity_at"):
		gravity = _material_world.call("get_gravity_at", global_position) as Vector2
	velocity = (velocity + gravity * delta).limit_length(terminal_speed)
	_record_trail_point()
	_sweep_flight(velocity * delta)
	queue_redraw()


func is_anchored() -> bool:
	return _is_anchored


func get_remaining_ratio() -> float:
	if not _is_anchored or anchored_lifetime <= 0.0:
		return 0.0
	return clampf(1.0 - _anchor_age / anchored_lifetime, 0.0, 1.0)


func _sweep_flight(displacement: Vector2) -> void:
	var distance := displacement.length()
	var steps := maxi(1, ceili(distance / SWEEP_STEP))
	var step := displacement / float(steps)
	for _index in range(steps):
		var candidate := global_position + step
		if _hits_solid(candidate):
			_anchor()
			return
		global_position = candidate


func _hits_solid(center: Vector2) -> bool:
	if not is_instance_valid(_material_world) or not _material_world.has_method("is_solid_at"):
		return false
	for offset in [
		Vector2.ZERO,
		Vector2.RIGHT * collision_radius,
		Vector2.LEFT * collision_radius,
		Vector2.DOWN * collision_radius,
		Vector2.UP * collision_radius,
	]:
		if bool(_material_world.call("is_solid_at", center + offset)):
			return true
	return false


func _anchor() -> void:
	if _is_anchored:
		return
	_is_anchored = true
	velocity = Vector2.ZERO
	_anchor_age = 0.0
	if _material_world.has_method("add_gravity_source"):
		_gravity_source_id = int(
			_material_world.call(
				"add_gravity_source",
				global_position,
				gravity_strength,
				gravity_radius,
				anchored_lifetime
			)
		)
	anchored.emit(global_position)
	queue_redraw()


func _record_trail_point() -> void:
	if _trail.is_empty() or _trail[_trail.size() - 1].distance_squared_to(global_position) >= 9.0:
		_trail.append(global_position)
	while _trail.size() > 12:
		_trail.remove_at(0)


func _expire() -> void:
	if _cleaned_up:
		return
	_cleaned_up = true
	_remove_gravity_source()
	expired.emit()
	queue_free()


func _remove_gravity_source() -> void:
	if (
		_gravity_source_id >= 0
		and is_instance_valid(_material_world)
		and _material_world.has_method("remove_gravity_source")
	):
		_material_world.call("remove_gravity_source", _gravity_source_id)
	_gravity_source_id = -1


func _exit_tree() -> void:
	_remove_gravity_source()


func _draw() -> void:
	if not _trail.is_empty() and not _is_anchored:
		var local_trail := PackedVector2Array()
		for world_point in _trail:
			local_trail.append(to_local(world_point))
		local_trail.append(Vector2.ZERO)
		if local_trail.size() >= 2:
			draw_polyline(local_trail, Color(0.95, 0.57, 0.24, 0.45), 1.0)

	if not _is_anchored:
		draw_circle(Vector2.ZERO, collision_radius + 1.0, Color("ffb04a"))
		draw_circle(Vector2.ZERO, 1.0, Color("fff0b5"))
		return

	var pulse := 0.5 + 0.5 * sin(_anchor_age * 8.0)
	var core_radius := 3.0 + pulse * 1.2
	draw_circle(Vector2.ZERO, core_radius, Color("ffc857"))
	draw_circle(Vector2.ZERO, 1.5, Color("fff4bc"))
	for index in range(3):
		var phase := fmod(_anchor_age * 0.65 + float(index) / 3.0, 1.0)
		var radius := lerpf(8.0, 25.0, phase)
		var alpha := (1.0 - phase) * 0.65
		draw_arc(Vector2.ZERO, radius, 0.0, TAU, 40, Color(1.0, 0.65, 0.25, alpha), 1.0)

	var orbit_angle := _anchor_age * 2.4
	var orbit_position := Vector2.from_angle(orbit_angle) * 12.0
	draw_arc(
		Vector2.ZERO,
		12.0,
		orbit_angle - 1.8,
		orbit_angle + 0.35,
		18,
		Color(0.45, 0.93, 0.88, 0.55),
		1.0
	)
	draw_circle(orbit_position, 1.4, Color("73ece1"))
