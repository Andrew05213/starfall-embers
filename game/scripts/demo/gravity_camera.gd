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
	_resolve_target()
	if is_instance_valid(_target):
		global_position = _target.global_position
		_desired_rotation = _calculate_desired_rotation()
		rotation = _desired_rotation


func _process(delta: float) -> void:
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
	if not target_path.is_empty():
		_target = get_node_or_null(target_path) as Node2D
	if not is_instance_valid(_target):
		var parent := get_parent()
		if is_instance_valid(parent):
			_target = parent.get_node_or_null("Player") as Node2D


func _calculate_desired_rotation() -> float:
	var up_direction := Vector2.UP
	if _target.has_method("get_up_direction"):
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
