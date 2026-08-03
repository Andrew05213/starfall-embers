class_name GravityFrame
extends RefCounted

## One fixed-tick gravity sample shared by movement, aiming and the camera.
## The camera may smooth this frame for presentation, but never writes it back.

const ZERO_EXIT_THRESHOLD := 0.001
const ZERO_REENTER_THRESHOLD := 0.002

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


func update_from_sample(sample: Dictionary, previous_up: Vector2, previous_tangent: Vector2,
		was_zero_gravity: bool) -> GravityFrame:
	tick = int(sample.get("tick", 0))
	acceleration = sample.get("acceleration", Vector2.ZERO) as Vector2
	magnitude = float(sample.get("magnitude", acceleration.length()))
	dominant_source_id = int(sample.get("dominant_source_id", 0))
	sample_limit_reached = bool(sample.get("sample_limit_reached", false))
	var threshold := ZERO_REENTER_THRESHOLD if was_zero_gravity else ZERO_EXIT_THRESHOLD
	zero_gravity = magnitude <= threshold
	transitioning = zero_gravity != was_zero_gravity
	if zero_gravity:
		up = previous_up if previous_up.length_squared() > 0.000001 else Vector2.UP
		tangent = previous_tangent if previous_tangent.length_squared() > 0.000001 else Vector2.RIGHT
		down = -up
		return self

	down = acceleration.normalized()
	var candidate_up := -down
	up = candidate_up
	var candidate_tangent := Vector2(-up.y, up.x)
	var opposite_tangent := -candidate_tangent
	if previous_tangent.length_squared() > 0.000001 and previous_tangent.dot(opposite_tangent) > previous_tangent.dot(candidate_tangent):
		tangent = opposite_tangent
	else:
		tangent = candidate_tangent
	return self
