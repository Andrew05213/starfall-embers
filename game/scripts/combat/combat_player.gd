class_name CombatLabPlayer
extends "res://scripts/demo/player_controller.gd"

## Gate-1 player: keeps the proven gravity movement controller and replaces the
## expensive edge-triggered demo starseed with a hold-to-fire juvenile weapon.

signal juvenile_requested(
	origin: Vector2,
	direction: Vector2,
	inherited_velocity: Vector2,
	profile: CombatShotProfile
)
signal trigger_started(timestamp: float)
signal shot_fired(timestamp: float, aim_direction: Vector2)

@export var shot_profile: CombatShotProfile

var _scheduler := CombatFireScheduler.new()
var _weapon_kick := 0.0
var _combat_clock := 0.0
var _combat_trigger_held := false
var _aim_override_enabled := false
var _aim_screen_override := Vector2.ZERO


func _ready() -> void:
	if is_instance_valid(shot_profile):
		_scheduler.configure(shot_profile.fire_interval)
	super._ready()


func _physics_process(delta: float) -> void:
	_combat_clock += maxf(delta, 0.0)
	_weapon_kick = move_toward(_weapon_kick, 0.0, 32.0 * delta)
	super._physics_process(delta)


func reset_combat_player(world_position: Vector2) -> void:
	_scheduler.configure(shot_profile.fire_interval if is_instance_valid(shot_profile) else 0.11)
	_weapon_kick = 0.0
	_combat_clock = 0.0
	_combat_trigger_held = false
	reset_player(world_position)


func set_shot_profile(profile: CombatShotProfile) -> void:
	shot_profile = profile
	_scheduler.configure(profile.fire_interval if is_instance_valid(profile) else 0.11)


func set_aim_screen_position(screen_position: Vector2) -> void:
	_aim_screen_override = screen_position
	_aim_override_enabled = true


func clear_aim_screen_override() -> void:
	_aim_override_enabled = false


func get_aim_direction() -> Vector2:
	return _aim_direction


func get_fire_interval() -> float:
	return shot_profile.fire_interval if is_instance_valid(shot_profile) else 0.0


func _update_aim() -> void:
	var viewport := get_viewport()
	var screen_position := _aim_screen_override if _aim_override_enabled else viewport.get_mouse_position()
	_aim_direction = CombatAimSpace.direction_from_screen(
		viewport.get_canvas_transform(),
		global_position,
		screen_position,
		_aim_direction
	)


func _handle_fire_input() -> void:
	var fire_down := Input.is_action_pressed("fire_starseed")
	if fire_down and not _combat_trigger_held:
		trigger_started.emit(_combat_clock)
	_combat_trigger_held = fire_down
	if not is_instance_valid(shot_profile) or not shot_profile.is_valid():
		_scheduler.advance(get_physics_process_delta_time(), false)
		return

	var shots := _scheduler.advance(get_physics_process_delta_time(), fire_down)
	for _shot_offset in shots:
		var muzzle := global_position + _aim_direction * (10.0 - _weapon_kick)
		juvenile_requested.emit(muzzle, _aim_direction, velocity, shot_profile)
		shot_fired.emit(_combat_clock, _aim_direction)
		velocity -= _aim_direction * shot_profile.real_recoil
		_weapon_kick = minf(
			_weapon_kick + shot_profile.presentation_recoil,
			shot_profile.presentation_recoil * 1.8
		)
	queue_redraw()


func _handle_extractor_input() -> void:
	# The combat lab isolates firing feel; material extraction stays in the
	# original vertical-slice scene.
	pass


func _draw() -> void:
	super._draw()
	if not is_instance_valid(shot_profile):
		return
	var weapon_origin := _aim_direction * (2.0 - _weapon_kick)
	var weapon_end := _aim_direction * (10.0 - _weapon_kick)
	draw_line(weapon_origin, weapon_end, Color("22333b"), 2.6)
	draw_line(weapon_origin, weapon_end, shot_profile.color, 1.0)
	if _weapon_kick > 0.1:
		var side := Vector2(-_aim_direction.y, _aim_direction.x)
		draw_line(
			weapon_end - side * 2.0,
			weapon_end + _aim_direction * 3.5,
			Color(shot_profile.color, clampf(_weapon_kick / 4.0, 0.15, 0.8)),
			1.2
		)
