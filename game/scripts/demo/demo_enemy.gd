class_name DemoEnemy
extends Node2D

## Small material-bodied enemy used to test whether state changes matter more than raw DPS.

signal defeated(enemy: Node, reward: int)

const MATERIAL_WATER := 3
const MATERIAL_OIL := 4
const MATERIAL_FIRE := 5
const MATERIAL_LAVA := 7
const MATERIAL_STEAM := 8
const SWEEP_STEP := 0.8

var collision_radius := 6.0
var velocity := Vector2.ZERO

var _material_world: Node
var _target: Node2D
var _kind := "stone"
var _max_health := 60.0
var _health := 60.0
var _move_speed := 34.0
var _contact_damage := 12.0
var _reward := 18
var _attack_cooldown := 0.0
var _environment_timer := 0.0
var _hit_flash := 0.0
var _dead := false


func setup(world: Node, target: Node2D, spawn_position: Vector2, kind: String) -> void:
	_material_world = world
	_target = target
	global_position = spawn_position
	_kind = kind
	match _kind:
		"oil":
			_max_health = 48.0
			_move_speed = 42.0
			_contact_damage = 9.0
			_reward = 22
			collision_radius = 6.5
		"spore":
			_max_health = 36.0
			_move_speed = 54.0
			_contact_damage = 7.0
			_reward = 16
			collision_radius = 5.5
		_:
			_max_health = 72.0
			_move_speed = 30.0
			_contact_damage = 14.0
			_reward = 20
			collision_radius = 7.0
	_health = _max_health
	velocity = Vector2.ZERO
	_dead = false
	add_to_group("enemies")
	queue_redraw()


func _physics_process(delta: float) -> void:
	if _dead or not is_instance_valid(_material_world) or not is_instance_valid(_target):
		return
	_attack_cooldown = maxf(0.0, _attack_cooldown - delta)
	_hit_flash = maxf(0.0, _hit_flash - delta)
	_environment_timer -= delta

	var gravity := _material_world.get_gravity_at(global_position) as Vector2
	var up := -gravity.normalized() if gravity.length_squared() > 0.001 else Vector2.UP
	var tangent := Vector2(-up.y, up.x)
	var to_target := _target.global_position - global_position
	var direction := signf(to_target.dot(tangent))
	var desired_speed := direction * _move_speed
	var tangent_speed := move_toward(velocity.dot(tangent), desired_speed, 150.0 * delta)
	var radial_speed := velocity.dot(up)
	velocity = tangent * tangent_speed + up * radial_speed + gravity * delta
	velocity = velocity.limit_length(150.0)
	_sweep(velocity * delta)

	if global_position.distance_to(_target.global_position) <= collision_radius + 6.0:
		_attack_target(up)
	if _environment_timer <= 0.0:
		_environment_timer = 0.18
		_apply_environment()
	queue_redraw()


func take_damage(amount: float, impulse: Vector2 = Vector2.ZERO, damage_type: String = "impact") -> void:
	if _dead or amount <= 0.0:
		return
	var adjusted := amount
	if _kind == "stone" and damage_type == "impact":
		adjusted *= 0.65
	elif _kind == "oil" and damage_type in ["heat", "steam"]:
		adjusted *= 1.8
	elif _kind == "spore" and damage_type == "gravity":
		adjusted *= 1.5
	_health = maxf(0.0, _health - adjusted)
	velocity += impulse
	_hit_flash = 0.13
	queue_redraw()
	if _health <= 0.0:
		_die()


func receive_starseed_hit(seed_type: String, impact_speed: float, impact_direction: Vector2) -> void:
	match seed_type:
		"steam":
			take_damage(22.0 + impact_speed * 0.025, impact_direction * 45.0, "steam")
		"rupture":
			take_damage(14.0 + impact_speed * 0.02, impact_direction * 95.0, "gravity")
		_:
			take_damage(18.0 + impact_speed * 0.035, impact_direction * 55.0, "impact")


func get_health_ratio() -> float:
	return clampf(_health / maxf(_max_health, 1.0), 0.0, 1.0)


func get_kind() -> String:
	return _kind


func _attack_target(up: Vector2) -> void:
	if _attack_cooldown > 0.0 or not _target.has_method("take_damage"):
		return
	var impulse := (_target.global_position - global_position).normalized() * 42.0 + up * 22.0
	if bool(_target.call("take_damage", _contact_damage, impulse)):
		_attack_cooldown = 0.8


func _apply_environment() -> void:
	if not _material_world.has_method("get_material_at"):
		return
	var material := int(_material_world.call("get_material_at", global_position))
	if _kind == "oil":
		if material == MATERIAL_FIRE or material == MATERIAL_LAVA:
			take_damage(9.0, Vector2.ZERO, "heat")
		elif material == MATERIAL_WATER:
			velocity *= 0.75
	elif _kind == "spore":
		if material in [MATERIAL_FIRE, MATERIAL_LAVA, MATERIAL_STEAM]:
			take_damage(12.0, Vector2.ZERO, "heat")
	elif _kind == "stone" and material == MATERIAL_LAVA:
		take_damage(5.0, Vector2.ZERO, "heat")


func _sweep(displacement: Vector2) -> void:
	var distance := displacement.length()
	if distance <= 0.0001:
		return
	var steps := maxi(1, ceili(distance / SWEEP_STEP))
	var step := displacement / float(steps)
	for _index in range(steps):
		var candidate := global_position + step
		if _body_hits_solid(candidate):
			velocity *= 0.35
			return
		global_position = candidate


func _body_hits_solid(center: Vector2) -> bool:
	if not _material_world.has_method("is_solid_at"):
		return false
	for offset in [
		Vector2.ZERO,
		Vector2.RIGHT * collision_radius,
		Vector2.LEFT * collision_radius,
		Vector2.UP * collision_radius,
		Vector2.DOWN * collision_radius,
	]:
		if bool(_material_world.call("is_solid_at", center + offset)):
			return true
	return false


func _die() -> void:
	if _dead:
		return
	_dead = true
	if is_instance_valid(_material_world):
		match _kind:
			"oil":
				_material_world.paint_circle(global_position, 3, MATERIAL_OIL)
			"spore":
				_material_world.paint_circle(global_position, 3, MATERIAL_STEAM)
			_:
				_material_world.paint_circle(global_position, 2, 2)
	defeated.emit(self, _reward)
	queue_free()


func _draw() -> void:
	var fill := Color("a69a83")
	var core := Color("f5c66b")
	match _kind:
		"oil":
			fill = Color("6f466f")
			core = Color("ff8a5b")
		"spore":
			fill = Color("547f72")
			core = Color("b6ef9e")
	if _hit_flash > 0.0:
		fill = Color.WHITE

	if _kind == "stone":
		var body := PackedVector2Array([
			Vector2(-7, -3), Vector2(-3, -7), Vector2(4, -6),
			Vector2(7, -1), Vector2(5, 6), Vector2(-4, 7), Vector2(-7, 2),
		])
		draw_colored_polygon(body, fill)
		draw_polyline(PackedVector2Array([body[0], body[1], body[2], body[3], body[4], body[5], body[6], body[0]]), Color("302e35"), 1.0)
	else:
		draw_circle(Vector2.ZERO, collision_radius, fill)
		draw_circle(Vector2(-3, -2), 2.2, fill.lightened(0.12))
	draw_circle(Vector2(2, -1), 1.7, core)

	var width := 16.0
	draw_rect(Rect2(-width * 0.5, -12.0, width, 2.0), Color("241f25"))
	draw_rect(Rect2(-width * 0.5, -12.0, width * get_health_ratio(), 2.0), Color("e45f54"))
