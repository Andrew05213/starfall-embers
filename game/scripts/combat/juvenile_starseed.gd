class_name JuvenileStarseed
extends Node2D

## High-speed, low-mass, short-lived starseed used by the shooting spine.
## Target collision is a continuous segment query and chooses the earliest hit,
## independent of scene-tree/group iteration order.

signal impacted(target: Node, point: Vector2, impact_velocity: Vector2)
signal expired(reason: String)
signal traveled(from: Vector2, to: Vector2, travel_velocity: Vector2)

const TERRAIN_SAMPLE_STEP := 0.8
const HIT_EPSILON := 0.000001

var velocity := Vector2.ZERO

var _profile: CombatShotProfile
var _material_world: Node
var _age := 0.0
var _expired := false
var _trail := PackedVector2Array()


func setup(
	profile: CombatShotProfile,
	origin: Vector2,
	direction: Vector2,
	inherited_velocity: Vector2 = Vector2.ZERO,
	material_world: Node = null
) -> void:
	_profile = profile
	_material_world = material_world
	global_position = origin
	var launch_direction := direction.normalized()
	if launch_direction.length_squared() <= HIT_EPSILON:
		launch_direction = Vector2.RIGHT
	velocity = (
		launch_direction * _profile.projectile_speed
		+ inherited_velocity * _profile.inherited_velocity_ratio
	)
	_age = 0.0
	_expired = false
	_trail.clear()
	add_to_group("juvenile_starseeds")
	queue_redraw()


func _physics_process(delta: float) -> void:
	simulate_step(delta)


func simulate_step(delta: float) -> void:
	if _expired or not is_instance_valid(_profile):
		return
	var remaining_lifetime := _profile.projectile_lifetime - _age
	if remaining_lifetime <= 0.0:
		_expire("lifetime")
		return
	var step_time := minf(maxf(delta, 0.0), remaining_lifetime)
	if step_time > 0.0:
		var from := global_position
		var gravity := _get_gravity_at(from) * _profile.projectile_gravity_scale
		# Integrate the ballistic arc analytically over one fixed physics step.
		# Collision uses its chord; at 60 Hz and the rifle's speed the curvature
		# inside a step is sub-pixel while still preserving continuous collision.
		var to := from + velocity * step_time + gravity * (0.5 * step_time * step_time)
		var end_velocity := velocity + gravity * step_time
		_record_trail(from)
		var hit := _find_earliest_hit(from, to)
		if not hit.is_empty():
			var hit_fraction := float(hit["fraction"])
			global_position = hit["point"] as Vector2
			velocity += gravity * step_time * hit_fraction
			traveled.emit(from, global_position, velocity)
			_age += step_time * hit_fraction
			_apply_hit(hit)
			return
		global_position = to
		velocity = end_velocity
		traveled.emit(from, to, velocity)
		_record_trail(to)
	_age += step_time
	if _age + HIT_EPSILON >= _profile.projectile_lifetime:
		_expire("lifetime")
	else:
		queue_redraw()


func is_expired() -> bool:
	return _expired


func get_age() -> float:
	return _age


func get_lifetime_ratio() -> float:
	if not is_instance_valid(_profile) or _profile.projectile_lifetime <= 0.0:
		return 1.0
	return clampf(_age / _profile.projectile_lifetime, 0.0, 1.0)


func _get_gravity_at(world_point: Vector2) -> Vector2:
	if (
		not is_instance_valid(_material_world)
		or not _material_world.has_method("get_gravity_at")
	):
		return Vector2.ZERO
	return _material_world.call("get_gravity_at", world_point) as Vector2


func _find_earliest_hit(from: Vector2, to: Vector2) -> Dictionary:
	var best: Dictionary = {}
	var best_fraction := INF
	var best_id := 9223372036854775807
	for candidate in get_tree().get_nodes_in_group("combat_targets"):
		if not is_instance_valid(candidate) or not candidate.has_method("sweep_hit"):
			continue
		var hit: Dictionary = candidate.call(
			"sweep_hit",
			from,
			to,
			_profile.collision_radius
		) as Dictionary
		if hit.is_empty():
			continue
		var fraction := clampf(float(hit.get("fraction", INF)), 0.0, 1.0)
		var candidate_id := int(candidate.get_instance_id())
		if (
			fraction < best_fraction - HIT_EPSILON
			or (absf(fraction - best_fraction) <= HIT_EPSILON and candidate_id < best_id)
		):
			best_fraction = fraction
			best_id = candidate_id
			best = {
				"fraction": fraction,
				"point": from.lerp(to, fraction),
				"target": candidate,
			}

	var terrain_fraction := _find_terrain_fraction(from, to)
	if terrain_fraction < best_fraction - HIT_EPSILON:
		best = {
			"fraction": terrain_fraction,
			"point": from.lerp(to, terrain_fraction),
			"target": null,
		}
	return best


func _find_terrain_fraction(from: Vector2, to: Vector2) -> float:
	if (
		not is_instance_valid(_material_world)
		or not _material_world.has_method("is_solid_at")
	):
		return INF
	var distance := from.distance_to(to)
	var steps := maxi(1, ceili(distance / TERRAIN_SAMPLE_STEP))
	for index in range(1, steps + 1):
		var fraction := float(index) / float(steps)
		var center := from.lerp(to, fraction)
		for offset in [
			Vector2.ZERO,
			Vector2.RIGHT * _profile.collision_radius,
			Vector2.LEFT * _profile.collision_radius,
			Vector2.UP * _profile.collision_radius,
			Vector2.DOWN * _profile.collision_radius,
		]:
			if bool(_material_world.call("is_solid_at", center + offset)):
				return fraction
	return INF


func _apply_hit(hit: Dictionary) -> void:
	var target: Node = hit.get("target") as Node
	var point := hit["point"] as Vector2
	if is_instance_valid(target) and target.has_method("receive_juvenile_hit"):
		var impulse_direction := velocity.normalized()
		target.call(
			"receive_juvenile_hit",
			_profile.damage,
			impulse_direction * _profile.hit_impulse,
			point,
			velocity
		)
	impacted.emit(target, point, velocity)
	_expire("impact")


func _record_trail(world_point: Vector2) -> void:
	if _trail.is_empty() or _trail[_trail.size() - 1].distance_squared_to(world_point) >= 4.0:
		_trail.append(world_point)
	while _trail.size() > 8:
		_trail.remove_at(0)


func _expire(reason: String) -> void:
	if _expired:
		return
	_expired = true
	remove_from_group("juvenile_starseeds")
	expired.emit(reason)
	queue_free()


func _draw() -> void:
	if not is_instance_valid(_profile):
		return
	if not _trail.is_empty():
		var local_trail := PackedVector2Array()
		for point in _trail:
			local_trail.append(to_local(point))
		local_trail.append(Vector2.ZERO)
		if local_trail.size() >= 2:
			draw_polyline(local_trail, Color(_profile.color, 0.55), 1.2)
	draw_circle(Vector2.ZERO, _profile.collision_radius + 0.8, _profile.color)
	draw_circle(Vector2.ZERO, maxf(0.7, _profile.collision_radius * 0.45), _profile.core_color)
