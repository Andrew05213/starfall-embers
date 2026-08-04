class_name GravityFrame
extends RefCounted

## One fixed-tick gravity sample shared by movement, aiming and the camera.
## The camera may smooth this frame for presentation, but never writes it back.

const ZERO_EXIT_THRESHOLD := 0.001
const ZERO_REENTER_THRESHOLD := 0.002
const DIRECTION_TRANSITION_DOT := 0.9659258262890683 # cos(15 degrees)

var tick := 0
var acceleration := Vector2.ZERO
var magnitude := 0.0
var down := Vector2.DOWN
var up := Vector2.UP
var tangent := Vector2.RIGHT
var dominant_source_id := 0
var zero_gravity := true
var transitioning := false
var sample_limit_reached := false
var predicted_acceleration := Vector2.ZERO
var predicted_magnitude := 0.0
var predicted_dominant_source_id := 0
var predicted_zero_gravity := true


func update_from_sample(sample: Dictionary, previous_up: Vector2, previous_tangent: Vector2,
		was_zero_gravity: bool) -> GravityFrame:
	return update_from_samples(sample, sample, previous_up, previous_tangent, was_zero_gravity)


func update_from_samples(current: Dictionary, predicted: Dictionary, previous_up: Vector2,
		previous_tangent: Vector2, was_zero_gravity: bool) -> GravityFrame:
	tick = int(current.get("tick", 0))
	acceleration = current.get("acceleration", Vector2.ZERO) as Vector2
	magnitude = float(current.get("magnitude", acceleration.length()))
	dominant_source_id = int(current.get("dominant_source_id", 0))
	sample_limit_reached = bool(current.get("sample_limit_reached", false)) \
		or bool(predicted.get("sample_limit_reached", false))
	predicted_acceleration = predicted.get("acceleration", Vector2.ZERO) as Vector2
	predicted_magnitude = float(predicted.get("magnitude", predicted_acceleration.length()))
	predicted_dominant_source_id = int(predicted.get("dominant_source_id", 0))
	var threshold := ZERO_REENTER_THRESHOLD if was_zero_gravity else ZERO_EXIT_THRESHOLD
	zero_gravity = magnitude <= threshold
	predicted_zero_gravity = predicted_magnitude <= threshold
	var current_down := acceleration.normalized() if magnitude > threshold else Vector2.ZERO
	var predicted_down := predicted_acceleration.normalized() if predicted_magnitude > threshold else Vector2.ZERO
	transitioning = zero_gravity != was_zero_gravity \
		or predicted_zero_gravity != zero_gravity \
		or predicted_dominant_source_id != dominant_source_id
	if not current_down.is_zero_approx() and not predicted_down.is_zero_approx():
		transitioning = transitioning or current_down.dot(predicted_down) < DIRECTION_TRANSITION_DOT
	if zero_gravity:
		up = previous_up if previous_up.length_squared() > 0.000001 else Vector2.UP
		tangent = previous_tangent if previous_tangent.length_squared() > 0.000001 else Vector2.RIGHT
		down = -up
		return self

	down = current_down
	var candidate_up := -down
	up = candidate_up
	var candidate_tangent := Vector2(-up.y, up.x)
	var opposite_tangent := -candidate_tangent
	if previous_tangent.length_squared() > 0.000001 and previous_tangent.dot(opposite_tangent) > previous_tangent.dot(candidate_tangent):
		tangent = opposite_tangent
	else:
		tangent = candidate_tangent
	return self
