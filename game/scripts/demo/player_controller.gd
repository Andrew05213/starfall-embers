class_name DemoPlayerController
extends Node2D

## Lightweight controller for the early material/gravity demo.
##
## The player intentionally does not depend on CharacterBody2D or a scene resource.  Collision is
## sampled directly from MaterialWorld so the controller can walk on destructible pixel terrain.

signal starseed_requested(origin: Vector2, velocity: Vector2)

@export var material_world_path: NodePath
@export var walk_speed: float = 62.0
@export var ground_acceleration: float = 520.0
@export var air_acceleration: float = 175.0
@export var jump_speed: float = 116.0
@export var terminal_speed: float = 235.0
@export var starseed_speed: float = 155.0
@export var fire_cooldown: float = 0.38

const HALF_WIDTH := 3.0
const HALF_HEIGHT := 6.0
const COLLISION_STEP := 0.75
const MIN_GRAVITY := 0.001

var velocity := Vector2.ZERO

var _material_world: Node
var _up_direction := Vector2.UP
var _tangent_direction := Vector2.RIGHT
var _aim_direction := Vector2.RIGHT
var _grounded := false
var _fire_time_left := 0.0
var _fire_was_down := false
var _jump_was_down := false


func _ready() -> void:
	if not material_world_path.is_empty():
		_material_world = get_node_or_null(material_world_path)
	queue_redraw()


func _physics_process(delta: float) -> void:
	if not is_instance_valid(_material_world):
		_resolve_material_world()
		queue_redraw()
		return

	_fire_time_left = maxf(0.0, _fire_time_left - delta)
	_update_gravity_basis()
	_update_aim()
	_grounded = _is_grounded()

	var move_input := _read_move_axis()
	var tangent_speed := velocity.dot(_tangent_direction)
	var acceleration := ground_acceleration if _grounded else air_acceleration
	tangent_speed = move_toward(tangent_speed, move_input * walk_speed, acceleration * delta)

	var vertical_speed := velocity.dot(_up_direction)
	if _grounded and vertical_speed < 0.0:
		vertical_speed = 0.0
	if _consume_jump_pressed() and _grounded:
		vertical_speed = jump_speed

	var gravity := _get_gravity(global_position)
	velocity = _tangent_direction * tangent_speed + _up_direction * vertical_speed
	velocity += gravity * delta
	velocity = velocity.limit_length(terminal_speed)
	_move_pixel_body(velocity * delta)
	_handle_fire_input()
	queue_redraw()


func reset_player(world_position: Vector2) -> void:
	global_position = world_position
	velocity = Vector2.ZERO
	_grounded = false
	_fire_time_left = 0.0
	_fire_was_down = false
	_jump_was_down = false
	queue_redraw()


func get_cooldown_ratio() -> float:
	if fire_cooldown <= 0.0:
		return 1.0
	return 1.0 - clampf(_fire_time_left / fire_cooldown, 0.0, 1.0)


func set_material_world(world: Node) -> void:
	_material_world = world


func _resolve_material_world() -> void:
	if not material_world_path.is_empty():
		_material_world = get_node_or_null(material_world_path)


func _update_gravity_basis() -> void:
	var gravity := _get_gravity(global_position)
	if gravity.length_squared() > MIN_GRAVITY * MIN_GRAVITY:
		_up_direction = -gravity.normalized()
	_tangent_direction = Vector2(-_up_direction.y, _up_direction.x)


func _update_aim() -> void:
	var to_mouse := get_global_mouse_position() - global_position
	if to_mouse.length_squared() > 1.0:
		_aim_direction = to_mouse.normalized()


func _read_move_axis() -> float:
	var axis := 0.0
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		axis -= 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		axis += 1.0
	return axis


func _consume_jump_pressed() -> bool:
	var jump_down := Input.is_key_pressed(KEY_SPACE) or Input.is_key_pressed(KEY_W)
	var just_pressed := jump_down and not _jump_was_down
	_jump_was_down = jump_down
	return just_pressed


func _handle_fire_input() -> void:
	var fire_down := Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) or Input.is_key_pressed(KEY_F)
	if fire_down and not _fire_was_down and _fire_time_left <= 0.0:
		var muzzle := global_position + _aim_direction * 9.0
		starseed_requested.emit(muzzle, _aim_direction * starseed_speed + velocity * 0.25)
		_fire_time_left = fire_cooldown
	_fire_was_down = fire_down


func _move_pixel_body(displacement: Vector2) -> void:
	# Sweep in sub-pixel steps.  Resolve tangent and radial motion separately so the body naturally
	# slides along curved surfaces instead of sticking on the first diagonal sample.
	var tangent_motion := _tangent_direction * displacement.dot(_tangent_direction)
	var radial_motion := _up_direction * displacement.dot(_up_direction)
	_sweep_component(tangent_motion, true)
	_sweep_component(radial_motion, false)


func _sweep_component(motion: Vector2, tangent_component: bool) -> void:
	var distance := motion.length()
	if distance <= 0.0001:
		return
	var steps := maxi(1, ceili(distance / COLLISION_STEP))
	var step := motion / float(steps)
	for _index in range(steps):
		if _solid_body_at(global_position + step):
			if tangent_component:
				velocity -= _tangent_direction * velocity.dot(_tangent_direction)
			else:
				velocity -= _up_direction * velocity.dot(_up_direction)
			return
		global_position += step


func _solid_body_at(center: Vector2) -> bool:
	# Nine samples approximate a small gravity-aligned capsule while keeping collision queries cheap.
	var horizontal := _tangent_direction * HALF_WIDTH
	var vertical := _up_direction * HALF_HEIGHT
	return (
		_is_solid(center + horizontal + vertical)
		or _is_solid(center - horizontal + vertical)
		or _is_solid(center + horizontal - vertical)
		or _is_solid(center - horizontal - vertical)
		or _is_solid(center + horizontal)
		or _is_solid(center - horizontal)
		or _is_solid(center + vertical)
		or _is_solid(center - vertical)
		or _is_solid(center)
	)


func _is_grounded() -> bool:
	var down := -_up_direction
	var foot_center := global_position + down * (HALF_HEIGHT + 1.25)
	return (
		_is_solid(foot_center)
		or _is_solid(foot_center + _tangent_direction * (HALF_WIDTH - 0.5))
		or _is_solid(foot_center - _tangent_direction * (HALF_WIDTH - 0.5))
	)


func _get_gravity(world_position: Vector2) -> Vector2:
	if is_instance_valid(_material_world) and _material_world.has_method("get_gravity_at"):
		return _material_world.call("get_gravity_at", world_position) as Vector2
	return Vector2.DOWN * 120.0


func _is_solid(world_position: Vector2) -> bool:
	return (
		is_instance_valid(_material_world)
		and _material_world.has_method("is_solid_at")
		and bool(_material_world.call("is_solid_at", world_position))
	)


func _draw() -> void:
	# All points are local-space vectors but remain aligned to the current gravity basis.
	var h := _tangent_direction * HALF_WIDTH
	var v := _up_direction * HALF_HEIGHT
	var body := PackedVector2Array([-h - v, h - v, h + v, -h + v])
	draw_colored_polygon(body, Color("d9e2d0"))
	draw_polyline(
		PackedVector2Array([body[0], body[1], body[2], body[3], body[0]]), Color("35423d"), 1.0
	)

	var visor_center := _up_direction * 1.5 + _aim_direction * 1.3
	draw_circle(visor_center, 1.6, Color("75e7dd"))
	draw_line(_aim_direction * 7.0, _aim_direction * 18.0, Color(0.46, 0.91, 0.87, 0.7), 1.0)
	if _fire_time_left > 0.0:
		draw_arc(
			Vector2.ZERO,
			8.5,
			-PI * 0.5,
			-PI * 0.5 + TAU * (1.0 - get_cooldown_ratio()),
			18,
			Color("f5b955"),
			1.0
		)
