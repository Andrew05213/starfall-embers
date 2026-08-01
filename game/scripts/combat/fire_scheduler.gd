class_name CombatFireScheduler
extends RefCounted

## Deterministic hold-to-fire cadence with an immediate first shot.
## A frame can catch up a small number of missed shots, but a long stall is
## deliberately discarded so returning from a pause never creates a burst.

const EPSILON := 0.000001

var interval := 0.11
var max_shots_per_advance := 4

var _trigger_held := false
var _time_to_next := 0.0
var _total_shots := 0


func configure(requested_interval: float, catch_up_cap: int = 4) -> void:
	interval = maxf(requested_interval, EPSILON)
	max_shots_per_advance = maxi(catch_up_cap, 1)
	reset()


func reset() -> void:
	_trigger_held = false
	_time_to_next = 0.0
	_total_shots = 0


func advance(delta: float, held: bool) -> PackedFloat32Array:
	var shot_offsets := PackedFloat32Array()
	var frame_time := maxf(delta, 0.0)
	if not held:
		_trigger_held = false
		_time_to_next = 0.0
		return shot_offsets

	if not _trigger_held:
		_trigger_held = true
		_time_to_next = 0.0

	var remaining := frame_time
	var elapsed := 0.0
	while (
		_time_to_next <= remaining + EPSILON
		and shot_offsets.size() < max_shots_per_advance
	):
		elapsed += _time_to_next
		remaining = maxf(0.0, remaining - _time_to_next)
		shot_offsets.append(elapsed)
		_total_shots += 1
		_time_to_next = interval

	if shot_offsets.size() >= max_shots_per_advance and _time_to_next <= remaining + EPSILON:
		# Explicit overload policy: discard backlog and resume at one interval.
		_time_to_next = interval
	else:
		_time_to_next = maxf(0.0, _time_to_next - remaining)
	return shot_offsets


func get_total_shots() -> int:
	return _total_shots


func get_time_to_next() -> float:
	return _time_to_next
