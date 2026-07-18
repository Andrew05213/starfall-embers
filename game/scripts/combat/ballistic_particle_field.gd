class_name CombatBallisticParticleField
extends Node2D

## Small deterministic CPU particle pool for Gate-1 feedback. Particles keep
## inherited projectile momentum and sample the same local gravity field as
## gameplay objects, so sparks curve toward the asteroid instead of behaving
## like screen-space decoration.

const MAX_PARTICLES := 192
const TRAIL_PARTICLES_PER_STEP := 2
const MIN_LIFETIME := 0.08

var _material_world: Node
var _particles: Array[Dictionary] = []
var _sequence := 0


func bind_material_world(material_world: Node) -> void:
	_material_world = material_world


func emit_trail(from: Vector2, to: Vector2, projectile_velocity: Vector2, color: Color) -> void:
	var segment := to - from
	if segment.length_squared() < 0.01:
		return
	var backward := -projectile_velocity.normalized()
	var side := Vector2(-backward.y, backward.x)
	for index in range(TRAIL_PARTICLES_PER_STEP):
		var ratio := (float(index) + 0.5) / float(TRAIL_PARTICLES_PER_STEP)
		var alternating := -1.0 if (_sequence + index) % 2 == 0 else 1.0
		_spawn(
			from.lerp(to, ratio),
			projectile_velocity * 0.075 + backward * (18.0 + index * 7.0) + side * alternating * 5.0,
			color,
			0.11 + index * 0.025,
			0.85
		)
	_sequence += TRAIL_PARTICLES_PER_STEP


func emit_impact(point: Vector2, impact_velocity: Vector2, color: Color, strong: bool) -> void:
	var incoming := impact_velocity.normalized()
	if incoming.length_squared() < 0.01:
		incoming = Vector2.RIGHT
	var count := 14 if strong else 8
	for index in range(count):
		var spread := _signed_pattern(index, count) * (1.45 if strong else 1.05)
		var direction := (-incoming).rotated(spread)
		var speed := (82.0 if strong else 54.0) + float((index * 19) % 37)
		_spawn(
			point + direction * 1.2,
			impact_velocity * 0.055 + direction * speed,
			color,
			0.30 if strong else 0.22,
			1.5 if strong else 1.1
		)
	_sequence += count


func emit_death(point: Vector2, impact_velocity: Vector2, color: Color) -> void:
	for index in range(18):
		var direction := Vector2.from_angle(float(index) / 18.0 * TAU + 0.17)
		var speed := 38.0 + float((index * 23) % 61)
		_spawn(point, impact_velocity * 0.035 + direction * speed, color, 0.48, 1.7)
	_sequence += 18


func simulate_step(delta: float) -> void:
	var step := maxf(delta, 0.0)
	for index in range(_particles.size() - 1, -1, -1):
		var particle := _particles[index]
		var age := float(particle["age"]) + step
		if age >= float(particle["lifetime"]):
			_particles.remove_at(index)
			continue
		var position := particle["position"] as Vector2
		var velocity := particle["velocity"] as Vector2
		var gravity := _get_gravity_at(position)
		particle["position"] = position + velocity * step + gravity * (0.5 * step * step)
		particle["velocity"] = velocity + gravity * step
		particle["age"] = age
		_particles[index] = particle
	queue_redraw()


func get_particle_count() -> int:
	return _particles.size()


func get_particle_snapshot(index: int) -> Dictionary:
	if index < 0 or index >= _particles.size():
		return {}
	return _particles[index].duplicate()


func _process(delta: float) -> void:
	simulate_step(delta)


func _spawn(
	position: Vector2,
	velocity: Vector2,
	color: Color,
	lifetime: float,
	size: float
) -> void:
	while _particles.size() >= MAX_PARTICLES:
		_particles.remove_at(0)
	_particles.append({
		"position": position,
		"velocity": velocity,
		"color": color,
		"age": 0.0,
		"lifetime": maxf(lifetime, MIN_LIFETIME),
		"size": size,
	})


func _get_gravity_at(world_point: Vector2) -> Vector2:
	if (
		not is_instance_valid(_material_world)
		or not _material_world.has_method("get_gravity_at")
	):
		return Vector2.ZERO
	return _material_world.call("get_gravity_at", world_point) as Vector2


func _signed_pattern(index: int, count: int) -> float:
	if count <= 1:
		return 0.0
	return (float(index) / float(count - 1) - 0.5) * 2.0


func _draw() -> void:
	for particle in _particles:
		var age_ratio := clampf(
			float(particle["age"]) / maxf(float(particle["lifetime"]), 0.001),
			0.0,
			1.0
		)
		var fade := 1.0 - age_ratio
		var position := to_local(particle["position"] as Vector2)
		var velocity := particle["velocity"] as Vector2
		var color := Color(particle["color"] as Color, fade)
		var tail := -velocity.normalized() * minf(4.5, velocity.length() * 0.025) * fade
		draw_line(position, position + tail, color, maxf(0.6, float(particle["size"]) * fade))
		draw_circle(position, maxf(0.35, float(particle["size"]) * fade), color)
