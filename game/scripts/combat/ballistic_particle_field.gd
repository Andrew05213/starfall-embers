class_name CombatBallisticParticleField
extends Node2D

## Small deterministic CPU particle pool for Gate-1 feedback. Particles keep
## inherited projectile momentum and sample the same local gravity field as
## gameplay objects, so sparks curve toward the asteroid instead of behaving
## like screen-space decoration.

const MAX_PARTICLES := 1024
const TRAIL_PARTICLES_PER_STEP := 1
const MIN_LIFETIME := 0.08
const TRAIL_LONGITUDINAL_MIN_RATIO := 0.10
const TRAIL_LONGITUDINAL_MAX_RATIO := 0.195
const TRAIL_LATERAL_RATIO := 0.04
const TRAIL_SPEED_CAP_RATIO := 0.20
const TRAIL_LIFETIME := 2.0
const TRAIL_FADE_DURATION := 0.2
const TRAIL_VISUAL_SIZE := 1.0
const TRAIL_VISUAL_GRID := 1.0
const COLLISION_SAMPLE_STEP := 1.0
const COLLISION_NORMAL_PROBE := 2.0
const MAX_BOUNCES := 2
const NORMAL_RESTITUTION := 0.25

var _material_world: Node
var _particles: Array[Dictionary] = []
var _sequence := 0
var _gravity_scale := 1.0
var _rng_state := 0x51a7e11


func bind_material_world(material_world: Node, gravity_scale: float = 1.0) -> void:
	_material_world = material_world
	_gravity_scale = maxf(gravity_scale, 0.0)


func emit_trail(from: Vector2, to: Vector2, projectile_velocity: Vector2, color: Color) -> void:
	var segment := to - from
	if segment.length_squared() < 0.01:
		return
	var projectile_speed := projectile_velocity.length()
	if projectile_speed <= 0.001:
		return
	var forward := projectile_velocity / projectile_speed
	var side := Vector2(-forward.y, forward.x)
	for index in range(TRAIL_PARTICLES_PER_STEP):
		var ratio := (float(index) + 0.5) / float(TRAIL_PARTICLES_PER_STEP)
		var longitudinal_ratio := lerpf(
			TRAIL_LONGITUDINAL_MIN_RATIO,
			TRAIL_LONGITUDINAL_MAX_RATIO,
			_random_unit()
		)
		var lateral_ratio := lerpf(-TRAIL_LATERAL_RATIO, TRAIL_LATERAL_RATIO, _random_unit())
		var particle_velocity := (
			projectile_velocity * longitudinal_ratio
			+ side * projectile_speed * lateral_ratio
		)
		particle_velocity = particle_velocity.limit_length(
			projectile_speed * TRAIL_SPEED_CAP_RATIO
		)
		_spawn(
			from.lerp(to, ratio),
			particle_velocity,
			color,
			TRAIL_LIFETIME,
			TRAIL_VISUAL_SIZE,
			"trail"
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
		if not bool(particle.get("settled", false)):
			var gravity := _get_gravity_at(position) * _gravity_scale
			var next_position := position + velocity * step + gravity * (0.5 * step * step)
			var next_velocity := velocity + gravity * step
			var collision := _sweep_collision(
				position,
				next_position,
				float(particle.get("collision_radius", TRAIL_VISUAL_SIZE))
			)
			if bool(collision.get("hit", false)):
				var normal := _estimate_collision_normal(
					collision["contact"] as Vector2,
					next_velocity
				)
				var bounces := int(particle.get("bounces", 0)) + 1
				particle["position"] = collision["safe_position"] as Vector2
				particle["bounces"] = bounces
				if bounces >= MAX_BOUNCES:
					particle["velocity"] = Vector2.ZERO
					particle["settled"] = true
				else:
					particle["velocity"] = resolve_bounce_velocity(next_velocity, normal)
			else:
				particle["position"] = next_position
				particle["velocity"] = next_velocity
		particle["age"] = age
		_particles[index] = particle
	queue_redraw()


func get_particle_count() -> int:
	return _particles.size()


func get_particle_snapshot(index: int) -> Dictionary:
	if index < 0 or index >= _particles.size():
		return {}
	return _particles[index].duplicate()


func get_particle_visual_alpha(index: int) -> float:
	if index < 0 or index >= _particles.size():
		return 0.0
	return _particle_alpha(_particles[index])


func get_particle_visual_position(index: int) -> Vector2:
	if index < 0 or index >= _particles.size():
		return Vector2.ZERO
	return _snap_to_visual_grid(_particles[index]["position"] as Vector2)


static func resolve_bounce_velocity(velocity: Vector2, contact_normal: Vector2) -> Vector2:
	var normal := contact_normal.normalized()
	if normal.length_squared() <= 0.000001:
		return -velocity * NORMAL_RESTITUTION
	var normal_component := normal * velocity.dot(normal)
	var tangent_component := velocity - normal_component
	return tangent_component - normal_component * NORMAL_RESTITUTION


func _process(delta: float) -> void:
	simulate_step(delta)


func _spawn(
	position: Vector2,
	velocity: Vector2,
	color: Color,
	lifetime: float,
	size: float,
	kind: String = "effect"
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
		"kind": kind,
		"collision_radius": maxf(size, TRAIL_VISUAL_SIZE),
		"bounces": 0,
		"settled": false,
	})


func _sweep_collision(from: Vector2, to: Vector2, radius: float) -> Dictionary:
	if not _can_collide():
		return {"hit": false}
	if _is_particle_colliding(from, radius):
		return {"hit": true, "safe_position": from, "contact": from}
	var distance := from.distance_to(to)
	var steps := maxi(1, ceili(distance / COLLISION_SAMPLE_STEP))
	var safe_position := from
	for step_index in range(1, steps + 1):
		var candidate := from.lerp(to, float(step_index) / float(steps))
		if _is_particle_colliding(candidate, radius):
			return {
				"hit": true,
				"safe_position": safe_position,
				"contact": candidate,
			}
		safe_position = candidate
	return {"hit": false}


func _is_particle_colliding(point: Vector2, radius: float) -> bool:
	if _is_solid_at(point):
		return true
	for offset in [Vector2.RIGHT, Vector2.LEFT, Vector2.DOWN, Vector2.UP]:
		if _is_solid_at(point + offset * radius):
			return true
	return false


func _estimate_collision_normal(contact: Vector2, incoming_velocity: Vector2) -> Vector2:
	var solid_right := 1.0 if _is_solid_at(contact + Vector2.RIGHT * COLLISION_NORMAL_PROBE) else 0.0
	var solid_left := 1.0 if _is_solid_at(contact + Vector2.LEFT * COLLISION_NORMAL_PROBE) else 0.0
	var solid_down := 1.0 if _is_solid_at(contact + Vector2.DOWN * COLLISION_NORMAL_PROBE) else 0.0
	var solid_up := 1.0 if _is_solid_at(contact + Vector2.UP * COLLISION_NORMAL_PROBE) else 0.0
	var into_solid := Vector2(solid_right - solid_left, solid_down - solid_up)
	var normal := -into_solid.normalized()
	if normal.length_squared() <= 0.000001:
		normal = -incoming_velocity.normalized()
	if normal.dot(incoming_velocity) > 0.0:
		normal = -normal
	return normal


func _can_collide() -> bool:
	return is_instance_valid(_material_world) and _material_world.has_method("is_solid_at")


func _is_solid_at(point: Vector2) -> bool:
	return _can_collide() and bool(_material_world.call("is_solid_at", point))


func _get_gravity_at(world_point: Vector2) -> Vector2:
	if (
		not is_instance_valid(_material_world)
		or not _material_world.has_method("get_gravity_at")
	):
		return Vector2.ZERO
	return _material_world.call("get_gravity_at", world_point) as Vector2


func _random_unit() -> float:
	_rng_state = int((_rng_state * 1103515245 + 12345) & 0x7fffffff)
	return float(_rng_state) / 2147483647.0


func _signed_pattern(index: int, count: int) -> float:
	if count <= 1:
		return 0.0
	return (float(index) / float(count - 1) - 0.5) * 2.0


func _draw() -> void:
	for particle in _particles:
		var fade := _particle_alpha(particle)
		var world_position := particle["position"] as Vector2
		var position := to_local(world_position)
		var velocity := particle["velocity"] as Vector2
		var color := Color(particle["color"] as Color, fade)
		if str(particle.get("kind", "effect")) == "trail":
			var snapped_position := to_local(_snap_to_visual_grid(world_position))
			var half_size := TRAIL_VISUAL_SIZE * 0.5
			draw_rect(
				Rect2(snapped_position - Vector2.ONE * half_size, Vector2.ONE * TRAIL_VISUAL_SIZE),
				color
			)
			continue
		var tail := -velocity.normalized() * minf(4.5, velocity.length() * 0.025) * fade
		draw_line(position, position + tail, color, maxf(0.6, float(particle["size"]) * fade))
		draw_circle(position, maxf(0.35, float(particle["size"]) * fade), color)


func _particle_alpha(particle: Dictionary) -> float:
	var age := float(particle["age"])
	var lifetime := maxf(float(particle["lifetime"]), 0.001)
	if str(particle.get("kind", "effect")) == "trail":
		var fade_start := maxf(0.0, lifetime - TRAIL_FADE_DURATION)
		if age <= fade_start:
			return 1.0
		return clampf((lifetime - age) / TRAIL_FADE_DURATION, 0.0, 1.0)
	return 1.0 - clampf(age / lifetime, 0.0, 1.0)


func _snap_to_visual_grid(world_position: Vector2) -> Vector2:
	return Vector2(
		roundf(world_position.x / TRAIL_VISUAL_GRID) * TRAIL_VISUAL_GRID,
		roundf(world_position.y / TRAIL_VISUAL_GRID) * TRAIL_VISUAL_GRID
	)
