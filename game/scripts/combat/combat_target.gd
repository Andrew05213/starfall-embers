class_name CombatTarget
extends Node2D

## Decoupled Gate-1 hit contract. Projectiles know only the combat_targets group
## and sweep_hit/receive_juvenile_hit methods.

signal hit_received(target: Node, point: Vector2, impact_velocity: Vector2, strong: bool)
signal defeated(target: Node, point: Vector2, velocity: Vector2)

@export_enum("wall", "static", "moving", "enemy") var target_kind := "static"
@export var collision_radius := 8.0
@export var wall_half_size := Vector2(3.0, 22.0)
@export var max_health := 49.0
@export var movement_amplitude := 24.0
@export var movement_frequency := 1.15

var velocity := Vector2.ZERO

var _health := 49.0
var _origin := Vector2.ZERO
var _age := 0.0
var _hit_flash := 0.0
var _hit_pause_left := 0.0
var _impact_offset := Vector2.ZERO
var _dead := false


func _ready() -> void:
	_origin = global_position
	_health = max_health
	add_to_group("combat_targets")
	queue_redraw()


func setup(kind: String, world_position: Vector2) -> void:
	target_kind = kind if kind in ["wall", "static", "moving", "enemy"] else "static"
	global_position = world_position
	_origin = world_position
	_health = max_health
	_dead = false
	if target_kind == "wall":
		max_health = 1000000.0
		_health = max_health
	elif target_kind in ["static", "moving"]:
		max_health = 140.0
		_health = max_health
	else:
		max_health = 49.0
		_health = max_health
	if not is_in_group("combat_targets"):
		add_to_group("combat_targets")
	queue_redraw()


func _physics_process(delta: float) -> void:
	if _dead:
		return
	if _hit_pause_left > 0.0:
		_hit_pause_left = maxf(0.0, _hit_pause_left - delta)
		queue_redraw()
		return
	_age += delta
	_hit_flash = maxf(0.0, _hit_flash - delta)
	_impact_offset = _impact_offset.move_toward(Vector2.ZERO, 28.0 * delta)
	if target_kind == "moving":
		global_position = _origin + Vector2.UP * sin(_age * TAU * movement_frequency) * movement_amplitude
	elif target_kind == "enemy":
		velocity = velocity.move_toward(Vector2.ZERO, 72.0 * delta)
		global_position += velocity * delta
	queue_redraw()


func sweep_hit(from: Vector2, to: Vector2, projectile_radius: float) -> Dictionary:
	if _dead:
		return {}
	if target_kind == "wall":
		return _sweep_expanded_rect(from, to, projectile_radius)
	var fraction := Geometry2D.segment_intersects_circle(
		from,
		to,
		global_position,
		collision_radius + projectile_radius
	)
	if fraction < 0.0:
		return {}
	return {"fraction": fraction}


func receive_juvenile_hit(
	damage: float,
	impulse: Vector2,
	point: Vector2,
	impact_velocity: Vector2
) -> void:
	if _dead:
		return
	var previous_ratio := get_health_ratio()
	if target_kind != "wall":
		_health = maxf(0.0, _health - maxf(damage, 0.0))
		velocity += impulse
	_impact_offset = -impact_velocity.normalized() * 1.5
	_hit_flash = 0.08
	var strong := previous_ratio > 0.5 and get_health_ratio() <= 0.5
	# Target-local hit pause preserves input, camera, projectiles and material
	# simulation. Strong threshold breaks are longer but still presentation-only.
	_hit_pause_left = maxf(_hit_pause_left, 0.05 if strong else 0.025)
	hit_received.emit(self, point, impact_velocity, strong)
	queue_redraw()
	if _health <= 0.0:
		_die(point, impact_velocity)


func get_health_ratio() -> float:
	return clampf(_health / maxf(max_health, 1.0), 0.0, 1.0)


func is_dead() -> bool:
	return _dead


func get_hit_pause_remaining() -> float:
	return _hit_pause_left


func _sweep_expanded_rect(from: Vector2, to: Vector2, radius: float) -> Dictionary:
	var minimum := global_position - wall_half_size - Vector2.ONE * radius
	var maximum := global_position + wall_half_size + Vector2.ONE * radius
	var direction := to - from
	var t_min := 0.0
	var t_max := 1.0
	for axis in range(2):
		var start := from[axis]
		var delta := direction[axis]
		if absf(delta) <= 0.000001:
			if start < minimum[axis] or start > maximum[axis]:
				return {}
			continue
		var first := (minimum[axis] - start) / delta
		var second := (maximum[axis] - start) / delta
		if first > second:
			var swap := first
			first = second
			second = swap
		t_min = maxf(t_min, first)
		t_max = minf(t_max, second)
		if t_min > t_max:
			return {}
	if t_max < 0.0 or t_min > 1.0:
		return {}
	return {"fraction": clampf(t_min, 0.0, 1.0)}


func _die(point: Vector2, impact_velocity: Vector2) -> void:
	if _dead:
		return
	_dead = true
	remove_from_group("combat_targets")
	defeated.emit(self, point, impact_velocity)
	queue_free()


func _draw() -> void:
	var fill := Color("52606f")
	var outline := Color("d5e3ef")
	match target_kind:
		"wall":
			fill = Color("303b46")
			outline = Color("6f899d")
		"moving":
			fill = Color("376e78")
			outline = Color("8ef0e0")
		"enemy":
			fill = Color("8b4251")
			outline = Color("ffac83")
	if _hit_flash > 0.0:
		fill = Color.WHITE

	if target_kind == "wall":
		draw_rect(Rect2(-wall_half_size, wall_half_size * 2.0), fill)
		draw_rect(Rect2(-wall_half_size, wall_half_size * 2.0), outline, false, 1.0)
		for y in range(-18, 19, 8):
			draw_line(Vector2(-wall_half_size.x, y), Vector2(wall_half_size.x, y + 4), outline, 0.7)
		return

	var center := _impact_offset
	draw_circle(center, collision_radius, fill)
	draw_arc(center, collision_radius, 0.0, TAU, 24, outline, 1.0)
	if target_kind == "moving":
		draw_line(center + Vector2(-4, 0), center + Vector2(4, 0), outline, 1.0)
		draw_line(center + Vector2(0, -4), center + Vector2(0, 4), outline, 1.0)
	elif target_kind == "enemy":
		draw_circle(center + Vector2(2, -1), 1.8, outline)

	var bar_width := 18.0
	draw_rect(Rect2(center + Vector2(-bar_width * 0.5, -13), Vector2(bar_width, 2)), Color("1a2028"))
	draw_rect(
		Rect2(center + Vector2(-bar_width * 0.5, -13), Vector2(bar_width * get_health_ratio(), 2)),
		Color("72e0bd") if target_kind != "enemy" else Color("ff6f61")
	)
