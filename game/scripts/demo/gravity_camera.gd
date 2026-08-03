class_name GravityFollowCamera
extends Camera2D

## Presentation-only camera that keeps the player's local up direction at screen up.
## It reads the controller's gravity basis without owning or changing simulation state.

@export var target_path: NodePath
@export_range(0.0, 40.0, 0.1) var position_response: float = 18.0
@export_range(0.0, 40.0, 0.1) var rotation_response: float = 9.0

var _target: Node2D
var _desired_rotation := 0.0


func _ready() -> void:
	# The target is authoritative in _physics_process. Updating this camera on
	# the same clock lets Godot interpolate both transforms together at render
	# time instead of sampling a stepped physics position from _process.
	process_callback = Camera2D.CAMERA2D_PROCESS_PHYSICS
	_resolve_target()
	if is_instance_valid(_target):
		_snap_to_target()


func _physics_process(delta: float) -> void:
	if not is_instance_valid(_target):
		_resolve_target()
	if not is_instance_valid(_target):
		return

	var position_weight := _response_weight(position_response, delta)
	global_position = global_position.lerp(_target.global_position, position_weight)
	_desired_rotation = _calculate_desired_rotation()
	var rotation_weight := _response_weight(rotation_response, delta)
	rotation = lerp_angle(rotation, _desired_rotation, rotation_weight)


func get_desired_rotation() -> float:
	return _desired_rotation


func _resolve_target() -> void:
	var previous_target := _target
	if not target_path.is_empty():
		_target = get_node_or_null(target_path) as Node2D
	if not is_instance_valid(_target):
		var parent := get_parent()
		if is_instance_valid(parent):
			_target = parent.get_node_or_null("Player") as Node2D
	if _target != previous_target and is_instance_valid(_target) and _target.has_signal("teleported"):
		var callback := Callable(self, "_on_target_teleported")
		if not _target.is_connected("teleported", callback):
			_target.connect("teleported", callback)


func _on_target_teleported(_world_position: Vector2) -> void:
	_snap_to_target()


func _snap_to_target() -> void:
	if not is_instance_valid(_target):
		return
	global_position = _target.global_position
	_desired_rotation = _calculate_desired_rotation()
	rotation = _desired_rotation
	# Camera position and gravity rotation both jump on spawn/reset. Clearing
	# interpolation prevents a one-frame sweep through the previous viewpoint.
	reset_physics_interpolation()


func _calculate_desired_rotation() -> float:
	var up_direction := Vector2.UP
	if _target.has_method("get_gravity_frame"):
		var frame := _target.call("get_gravity_frame") as GravityFrame
		if frame != null:
			up_direction = frame.up
	elif _target.has_method("get_up_direction"):
		up_direction = _target.call("get_up_direction") as Vector2
	if up_direction.length_squared() <= 0.000001:
		return _desired_rotation
	# Camera rotation is the world-space angle of the screen's right axis. Aligning
	# its screen-up axis with local up therefore requires up.angle() + PI / 2.
	return wrapf(up_direction.angle() + PI * 0.5, -PI, PI)


func _response_weight(response: float, delta: float) -> float:
	if response <= 0.0:
		return 1.0
	return 1.0 - exp(-response * maxf(delta, 0.0))
