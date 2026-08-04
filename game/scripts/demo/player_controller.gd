class_name DemoPlayerController
extends Node2D

## Gravity-aligned controller used by the playable vertical slice.
## Collision is sampled from MaterialWorld so mined terrain immediately affects movement.

signal starseed_requested(origin: Vector2, velocity: Vector2, seed_type: String)
signal extractor_requested(origin: Vector2, direction: Vector2)
signal state_changed(state: Dictionary)
signal action_denied(reason: String)
signal died
signal teleported(world_position: Vector2)

@export var material_world_path: NodePath
@export var walk_speed: float = 62.0
@export var ground_acceleration: float = 520.0
@export var air_acceleration: float = 175.0
@export var jump_speed: float = 178.0
@export var terminal_speed: float = 900.0
@export var starseed_speed: float = 170.0
@export var fire_cooldown: float = 0.42
@export var boost_acceleration: float = 185.0

const MAX_HEALTH := 100.0
const MAX_ENERGY := 100.0
const MAX_MATTER := 100.0
const GROUND_ENERGY_RECOVERY := 22.0
const AIR_ENERGY_RECOVERY := 8.0
const BOOST_ENERGY_COST := 35.0
const EXTRACT_ENERGY_COST := 2.0
const EXTRACT_INTERVAL := 0.11
const HALF_WIDTH := 3.0
const HALF_HEIGHT := 6.0
const COLLISION_STEP := 0.75
const MIN_GRAVITY := 0.001
const STEP_HEIGHT := 4.5
const SURFACE_SNAP_DISTANCE := 4.5
const DEPENETRATION_DISTANCE := 24.0

const SEED_COSTS := {
	"gravity": {"energy": 30.0, "matter": 12.0},
	"steam": {"energy": 24.0, "matter": 16.0},
	"rupture": {"energy": 38.0, "matter": 20.0},
}

var velocity := Vector2.ZERO
var health := MAX_HEALTH
var energy := MAX_ENERGY
var matter := 48.0
var active := true

var _material_world: Node
var _gravity_provider: NativeGravityProvider
var _gravity_frame := GravityFrame.new()
var _up_direction := Vector2.UP
var _tangent_direction := Vector2.RIGHT
var _aim_direction := Vector2.RIGHT
var _grounded := false
var _selected_starseed_type := "gravity"
var _fire_time_left := 0.0
var _extract_time_left := 0.0
var _invulnerability_left := 0.0
var _fire_was_down := false
var _last_state_signature := ""


func _ready() -> void:
	_resolve_material_world()
	if is_instance_valid(_material_world):
		_configure_default_gravity_provider()
		_update_gravity_basis(0.0)
		_resolve_initial_overlap()
	# A reset is a discontinuity, not movement. Discard the previous physics
	# transform so render interpolation cannot draw a trail from the old spawn.
	reset_physics_interpolation()
	teleported.emit(global_position)
	_emit_state_if_changed(true)
	queue_redraw()


func _physics_process(delta: float) -> void:
	if not is_instance_valid(_material_world):
		_resolve_material_world()
		_configure_default_gravity_provider()
		queue_redraw()
		return

	_fire_time_left = maxf(0.0, _fire_time_left - delta)
	_extract_time_left = maxf(0.0, _extract_time_left - delta)
	_invulnerability_left = maxf(0.0, _invulnerability_left - delta)
	_update_gravity_basis(delta)
	_update_aim()
	_grounded = _is_grounded()

	if not active:
		velocity = velocity.move_toward(Vector2.ZERO, 180.0 * delta)
		_move_pixel_body(velocity * delta)
		queue_redraw()
		return

	var move_input := _read_move_axis()
	var was_grounded := _grounded
	var tangent_speed := velocity.dot(_tangent_direction)
	var acceleration := ground_acceleration if _grounded else air_acceleration
	tangent_speed = move_toward(tangent_speed, move_input * walk_speed, acceleration * delta)

	var vertical_speed := velocity.dot(_up_direction)
	if _grounded and vertical_speed < 0.0:
		vertical_speed = 0.0
	var jumped := _consume_jump_pressed() and _grounded
	if jumped:
		vertical_speed = jump_speed

	var gravity := _gravity_frame.acceleration
	velocity = _tangent_direction * tangent_speed + _up_direction * vertical_speed
	velocity += gravity * delta
	_handle_boost(delta)
	velocity = velocity.limit_length(terminal_speed)
	_move_pixel_body(velocity * delta, was_grounded and not jumped)
	_handle_fire_input()
	_handle_extractor_input()
	_recover_energy(delta)
	_emit_state_if_changed()
	queue_redraw()


func reset_player(world_position: Vector2) -> void:
	global_position = world_position
	velocity = Vector2.ZERO
	health = MAX_HEALTH
	energy = MAX_ENERGY
	matter = 48.0
	active = true
	_grounded = false
	_fire_time_left = 0.0
	_extract_time_left = 0.0
	_invulnerability_left = 0.0
	_fire_was_down = false
	_gravity_frame = GravityFrame.new()
	_up_direction = Vector2.UP
	_tangent_direction = Vector2.RIGHT
	if not is_instance_valid(_material_world):
		_resolve_material_world()
		_configure_default_gravity_provider()
	if is_instance_valid(_material_world):
		_update_gravity_basis(0.0)
		_resolve_initial_overlap()
	# A reset is a discontinuity, not movement. Discard the previous physics
	# transform so render interpolation cannot draw a trail from the old spawn.
	reset_physics_interpolation()
	teleported.emit(global_position)
	_emit_state_if_changed(true)
	queue_redraw()


func set_starseed_type(seed_type: String) -> void:
	if SEED_COSTS.has(seed_type):
		_selected_starseed_type = seed_type
		_emit_state_if_changed(true)


func set_active(value: bool) -> void:
	active = value
	_fire_was_down = false
	_emit_state_if_changed(true)


func take_damage(amount: float, impulse: Vector2 = Vector2.ZERO) -> bool:
	if not active or amount <= 0.0 or _invulnerability_left > 0.0:
		return false
	health = maxf(0.0, health - amount)
	velocity += impulse
	_invulnerability_left = 0.48
	_emit_state_if_changed(true)
	queue_redraw()
	if health <= 0.0:
		active = false
		died.emit()
	return true


func heal(amount: float) -> void:
	health = minf(MAX_HEALTH, health + maxf(amount, 0.0))
	_emit_state_if_changed(true)


func add_matter(amount: float) -> float:
	var before := matter
	matter = clampf(matter + amount, 0.0, MAX_MATTER)
	_emit_state_if_changed(true)
	return matter - before


func get_cooldown_ratio() -> float:
	if fire_cooldown <= 0.0:
		return 1.0
	return 1.0 - clampf(_fire_time_left / fire_cooldown, 0.0, 1.0)


func get_up_direction() -> Vector2:
	## Read-only gravity basis for presentation systems such as the follow camera.
	return _up_direction


func get_gravity_frame() -> GravityFrame:
	return _gravity_frame


func set_gravity_provider(provider: NativeGravityProvider) -> void:
	_gravity_provider = provider
	if is_instance_valid(_material_world):
		_update_gravity_basis(0.0)


func get_state() -> Dictionary:
	return {
		"health": health,
		"max_health": MAX_HEALTH,
		"energy": energy,
		"max_energy": MAX_ENERGY,
		"matter": matter,
		"max_matter": MAX_MATTER,
		"grounded": _grounded,
		"active": active,
		"seed_type": _selected_starseed_type,
	}


func set_material_world(world: Node) -> void:
	_material_world = world
	_configure_default_gravity_provider()


func _resolve_material_world() -> void:
	if not material_world_path.is_empty():
		_material_world = get_node_or_null(material_world_path)
	if not is_instance_valid(_material_world):
		var parent := get_parent()
		if is_instance_valid(parent):
			_material_world = parent.get_node_or_null("MaterialWorld")


func _configure_default_gravity_provider() -> void:
	## The formal scene injects one shared provider from NativeGravityRuntime.
	## Standalone tests and fallback scenes intentionally remain GDScript-only.
	return


func _update_gravity_basis(delta: float) -> void:
	var predicted_position := global_position + velocity * maxf(delta, 0.0)
	var samples: Array[Dictionary] = []
	if is_instance_valid(_gravity_provider):
		samples = _gravity_provider.sample_pair(global_position, predicted_position)
	if samples.size() < 2:
		samples = [_sample_gravity(global_position), _sample_gravity(predicted_position)]
	_gravity_frame.update_from_samples(
		samples[0], samples[1], _up_direction, _tangent_direction, _gravity_frame.zero_gravity
	)
	_up_direction = _gravity_frame.up
	_tangent_direction = _gravity_frame.tangent


func _update_aim() -> void:
	var to_mouse := get_global_mouse_position() - global_position
	if to_mouse.length_squared() > 1.0:
		_aim_direction = to_mouse.normalized()


func _read_move_axis() -> float:
	return Input.get_axis("move_left", "move_right")


func _consume_jump_pressed() -> bool:
	return Input.is_action_just_pressed("jump")


func _handle_boost(delta: float) -> void:
	if not Input.is_key_pressed(KEY_SHIFT) or energy <= 0.0:
		return
	var spent := minf(energy, BOOST_ENERGY_COST * delta)
	energy -= spent
	velocity += _aim_direction * boost_acceleration * delta * (spent / maxf(BOOST_ENERGY_COST * delta, 0.001))


func _recover_energy(delta: float) -> void:
	if Input.is_key_pressed(KEY_SHIFT):
		return
	var recovery := GROUND_ENERGY_RECOVERY if _grounded else AIR_ENERGY_RECOVERY
	energy = minf(MAX_ENERGY, energy + recovery * delta)


func _handle_fire_input() -> void:
	var fire_down := Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) or Input.is_key_pressed(KEY_F)
	if fire_down and not _fire_was_down and _fire_time_left <= 0.0:
		var cost: Dictionary = SEED_COSTS[_selected_starseed_type]
		if energy < float(cost["energy"]):
			action_denied.emit("核力不足")
		elif matter < float(cost["matter"]):
			action_denied.emit("物质不足：使用右键采掘")
		else:
			energy -= float(cost["energy"])
			matter -= float(cost["matter"])
			var muzzle := global_position + _aim_direction * 9.0
			starseed_requested.emit(
				muzzle,
				_aim_direction * starseed_speed + velocity * 0.25,
				_selected_starseed_type
			)
			_fire_time_left = fire_cooldown
			_emit_state_if_changed(true)
	_fire_was_down = fire_down


func _handle_extractor_input() -> void:
	if not Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) or _extract_time_left > 0.0:
		return
	if energy < EXTRACT_ENERGY_COST:
		action_denied.emit("核力不足")
		_extract_time_left = EXTRACT_INTERVAL
		return
	energy -= EXTRACT_ENERGY_COST
	_extract_time_left = EXTRACT_INTERVAL
	extractor_requested.emit(global_position + _aim_direction * 8.0, _aim_direction)


func _emit_state_if_changed(force: bool = false) -> void:
	var state := get_state()
	var signature := "%d:%d:%d:%s:%s" % [
		roundi(health), roundi(energy), roundi(matter), _selected_starseed_type, str(active)
	]
	if force or signature != _last_state_signature:
		_last_state_signature = signature
		state_changed.emit(state)


func _move_pixel_body(displacement: Vector2, allow_surface_snap: bool = false) -> void:
	var tangent_motion := _tangent_direction * displacement.dot(_tangent_direction)
	var radial_motion := _up_direction * displacement.dot(_up_direction)
	_sweep_tangent(tangent_motion)
	_sweep_component(radial_motion)
	if allow_surface_snap:
		_snap_to_surface()


func _sweep_tangent(motion: Vector2) -> void:
	var distance := motion.length()
	if distance <= 0.0001:
		return
	var steps := maxi(1, ceili(distance / COLLISION_STEP))
	var step := motion / float(steps)
	for _index in range(steps):
		if not _solid_body_at(global_position + step):
			global_position += step
			continue
		if _try_step_up(step):
			continue
		velocity -= _tangent_direction * velocity.dot(_tangent_direction)
		return


func _try_step_up(tangent_step: Vector2) -> bool:
	var lift := COLLISION_STEP
	while lift <= STEP_HEIGHT + 0.001:
		var lifted_position := global_position + _up_direction * lift
		if (
			not _solid_body_at(lifted_position)
			and not _solid_body_at(lifted_position + tangent_step)
		):
			global_position = lifted_position + tangent_step
			return true
		lift += COLLISION_STEP
	return false


func _sweep_component(motion: Vector2) -> void:
	var distance := motion.length()
	if distance <= 0.0001:
		return
	var steps := maxi(1, ceili(distance / COLLISION_STEP))
	var step := motion / float(steps)
	for _index in range(steps):
		if _solid_body_at(global_position + step):
			velocity -= _up_direction * velocity.dot(_up_direction)
			return
		global_position += step


func _snap_to_surface() -> void:
	if _is_grounded():
		return
	var down := -_up_direction
	var travelled := 0.0
	var last_free := global_position
	while travelled < SURFACE_SNAP_DISTANCE:
		var amount := minf(COLLISION_STEP, SURFACE_SNAP_DISTANCE - travelled)
		var candidate := global_position + down * amount
		if _solid_body_at(candidate):
			global_position = last_free
			velocity -= _up_direction * minf(velocity.dot(_up_direction), 0.0)
			return
		global_position = candidate
		last_free = candidate
		travelled += amount
		if _is_grounded():
			velocity -= _up_direction * minf(velocity.dot(_up_direction), 0.0)
			return


func _resolve_initial_overlap() -> void:
	var travelled := 0.0
	while _solid_body_at(global_position) and travelled < DEPENETRATION_DISTANCE:
		global_position += _up_direction * COLLISION_STEP
		travelled += COLLISION_STEP


func _solid_body_at(center: Vector2) -> bool:
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
	return _sample_gravity(world_position).get("acceleration", Vector2.ZERO) as Vector2


func _sample_gravity(world_position: Vector2) -> Dictionary:
	if is_instance_valid(_gravity_provider):
		return _gravity_provider.sample(world_position)
	if is_instance_valid(_material_world) and _material_world.has_method("get_gravity_at"):
		var acceleration := _material_world.call("get_gravity_at", world_position) as Vector2
		return {
			"tick": 0,
			"acceleration": acceleration,
			"magnitude": acceleration.length(),
			"dominant_source_id": 0,
		}
	return {"acceleration": Vector2.DOWN * 120.0, "magnitude": 120.0}


func _is_solid(world_position: Vector2) -> bool:
	return (
		is_instance_valid(_material_world)
		and _material_world.has_method("is_solid_at")
		and bool(_material_world.call("is_solid_at", world_position))
	)


func _draw() -> void:
	var alpha := 0.35 if _invulnerability_left > 0.0 and int(_invulnerability_left * 30.0) % 2 == 0 else 1.0
	var h := _tangent_direction * HALF_WIDTH
	var v := _up_direction * HALF_HEIGHT
	var body := PackedVector2Array([-h - v, h - v, h + v, -h + v])
	draw_colored_polygon(body, Color(0.85, 0.89, 0.82, alpha))
	draw_polyline(
		PackedVector2Array([body[0], body[1], body[2], body[3], body[0]]),
		Color(0.21, 0.26, 0.24, alpha),
		1.0
	)
	var visor_center := _up_direction * 1.5 + _aim_direction * 1.3
	draw_circle(visor_center, 1.6, Color(0.46, 0.91, 0.87, alpha))
	draw_line(_aim_direction * 7.0, _aim_direction * 18.0, Color(0.46, 0.91, 0.87, 0.7), 1.0)
	if Input.is_key_pressed(KEY_SHIFT) and active:
		draw_line(-_aim_direction * 5.0, -_aim_direction * 11.0, Color("ff9b42"), 2.0)
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
