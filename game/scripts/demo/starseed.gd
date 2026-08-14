class_name DemoStarseed
extends Node2D

## Throwable micro-world with three prototype forms: attraction, steam and repulsion.

signal anchored(position: Vector2)
signal impacted(position: Vector2, seed_type: String)
signal expired

@export var gravity_strength: float = 155.0
@export var gravity_radius: float = 105.0
@export var anchored_lifetime: float = 7.0
@export var maximum_flight_time: float = 6.0
@export var collision_radius: float = 2.0
@export var terminal_speed: float = 280.0

const SWEEP_STEP := 1.0
const MATERIAL_WATER := 3
const MATERIAL_STEAM := 8

var velocity := Vector2.ZERO
var seed_type := "gravity"

var _material_world: Node
var _gravity_provider: NativeGravityProvider
var _gravity_source_id := -1
var _is_anchored := false
var _age := 0.0
var _anchor_age := 0.0
var _cleaned_up := false
var _trail := PackedVector2Array()


func setup(
	world: Node,
	origin: Vector2,
	initial_velocity: Vector2,
	requested_type: String = "gravity",
	gravity_provider: NativeGravityProvider = null
) -> void:
	_material_world = world
	_gravity_provider = gravity_provider
	process_physics_priority = -200
	global_position = origin
	velocity = initial_velocity
	seed_type = requested_type if requested_type in ["gravity", "steam", "rupture"] else "gravity"
	_age = 0.0
	_anchor_age = 0.0
	_is_anchored = false
	_cleaned_up = false
	_gravity_source_id = -1
	_trail.clear()
	match seed_type:
		"steam":
			gravity_strength = 45.0
			gravity_radius = 48.0
			anchored_lifetime = 0.7
		"rupture":
			gravity_strength = -205.0
			gravity_radius = 92.0
			anchored_lifetime = 3.6
		_:
			gravity_strength = 155.0
			gravity_radius = 105.0
			anchored_lifetime = 7.0
	add_to_group("starseeds")
	queue_redraw()


func _physics_process(delta: float) -> void:
	if _cleaned_up:
		return
	_age += delta
	if _is_anchored:
		_anchor_age += delta
		if _gravity_source_id >= 0:
			if is_instance_valid(_gravity_provider):
				_gravity_provider.update_gravity_source(_gravity_source_id, global_position)
			elif is_instance_valid(_material_world) and _material_world.has_method("update_gravity_source"):
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
		if _try_objective_hit(candidate):
			return
		var enemy := _enemy_at(candidate)
		if is_instance_valid(enemy):
			global_position = candidate
			_impact_enemy(enemy)
			return
		if _hits_solid(candidate):
			global_position = candidate
			_impact_world()
			return
		global_position = candidate


func _try_objective_hit(candidate: Vector2) -> bool:
	for objective in get_tree().get_nodes_in_group("objectives"):
		if not is_instance_valid(objective):
			continue
		var radius := float(objective.get("collision_radius"))
		if candidate.distance_to(objective.global_position) > collision_radius + radius:
			continue
		if objective.has_method("accept_starseed") and bool(objective.call("accept_starseed", seed_type)):
			global_position = objective.global_position
			impacted.emit(global_position, seed_type)
			_expire()
			return true
	return false


func _enemy_at(candidate: Vector2) -> Node:
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(enemy):
			continue
		var radius := float(enemy.get("collision_radius"))
		if candidate.distance_to(enemy.global_position) <= collision_radius + radius:
			return enemy
	return null


func _impact_enemy(enemy: Node) -> void:
	var direction := velocity.normalized()
	if enemy.has_method("receive_starseed_hit"):
		enemy.call("receive_starseed_hit", seed_type, velocity.length(), direction)
	if seed_type == "steam":
		_spawn_steam_burst()
		impacted.emit(global_position, seed_type)
		_expire()
	elif seed_type == "rupture":
		_apply_rupture_burst()
		_anchor()
	else:
		_anchor()


func _impact_world() -> void:
	if seed_type == "steam":
		_spawn_steam_burst()
		impacted.emit(global_position, seed_type)
		_expire()
		return
	if seed_type == "rupture":
		_apply_rupture_burst()
	_anchor()


func _spawn_steam_burst() -> void:
	if not is_instance_valid(_material_world):
		return
	_material_world.paint_circle(global_position, 2, MATERIAL_WATER)
	for offset in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]:
		_material_world.paint_circle(global_position + offset * 8.0, 2, MATERIAL_STEAM)
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if is_instance_valid(enemy) and global_position.distance_to(enemy.global_position) <= 46.0:
			enemy.take_damage(12.0, (enemy.global_position - global_position).normalized() * 20.0, "steam")


func _apply_rupture_burst() -> void:
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(enemy):
			continue
		var distance: float = global_position.distance_to(enemy.global_position)
		if distance > 72.0:
			continue
		var direction: Vector2 = (enemy.global_position - global_position).normalized()
		var falloff: float = 1.0 - distance / 72.0
		enemy.take_damage(12.0 * falloff, direction * (95.0 * falloff), "gravity")


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
	if is_instance_valid(_gravity_provider):
		# The visual lifetime owns removal; Native uses a permanent source so the
		# second clock cannot expire it before the starseed's explicit cleanup.
		_gravity_source_id = _gravity_provider.add_gravity_source(
			global_position, gravity_strength, gravity_radius, -1.0
		)
	elif is_instance_valid(_material_world) and _material_world.has_method("add_gravity_source"):
		_gravity_source_id = int(
			_material_world.call("add_gravity_source", global_position, gravity_strength, gravity_radius, -1.0)
		)
	anchored.emit(global_position)
	impacted.emit(global_position, seed_type)
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
	if _gravity_source_id >= 0:
		if is_instance_valid(_gravity_provider):
			_gravity_provider.remove_gravity_source(_gravity_source_id)
		elif is_instance_valid(_material_world) and _material_world.has_method("remove_gravity_source"):
			_material_world.call("remove_gravity_source", _gravity_source_id)
	_gravity_source_id = -1


func _exit_tree() -> void:
	_remove_gravity_source()


func _draw() -> void:
	var color := Color("ffb04a")
	var core := Color("fff0b5")
	match seed_type:
		"steam":
			color = Color("73d9ed")
			core = Color("e7fbff")
		"rupture":
			color = Color("d176ef")
			core = Color("f6d6ff")
	if not _trail.is_empty() and not _is_anchored:
		var local_trail := PackedVector2Array()
		for world_point in _trail:
			local_trail.append(to_local(world_point))
		local_trail.append(Vector2.ZERO)
		if local_trail.size() >= 2:
			draw_polyline(local_trail, Color(color, 0.45), 1.0)

	if not _is_anchored:
		draw_circle(Vector2.ZERO, collision_radius + 1.0, color)
		draw_circle(Vector2.ZERO, 1.0, core)
		return

	var pulse := 0.5 + 0.5 * sin(_anchor_age * 8.0)
	var core_radius := 3.0 + pulse * 1.2
	draw_circle(Vector2.ZERO, core_radius, color)
	draw_circle(Vector2.ZERO, 1.5, core)
	for index in range(3):
		var phase := fmod(_anchor_age * 0.65 + float(index) / 3.0, 1.0)
		var radius := lerpf(8.0, 25.0, phase)
		var alpha := (1.0 - phase) * 0.65
		draw_arc(Vector2.ZERO, radius, 0.0, TAU, 40, Color(color, alpha), 1.0)
