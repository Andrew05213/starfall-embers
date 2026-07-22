class_name NativeBallisticsShadow
extends Node

## Mirrors production Combat Lab projectile requests into sim_core without
## affecting gameplay. GDScript remains authoritative; this node only records
## trajectory and lifetime differences at common projectile ages.

const POSITION_TOLERANCE_PX := 0.1
const VELOCITY_TOLERANCE_PX_PER_SECOND := 0.5
const AGE_EPSILON := 0.00001

var _host: Node
var _enabled := false
var _accumulator := 0.0
var _fixed_step := 1.0 / 30.0
var _next_request_id := 1
var _records: Dictionary = {}
var _pending_spawns: Array[Dictionary] = []
var _projectile_id_by_request: Dictionary = {}
var _pending_retires: Dictionary = {}
var _compared_samples := 0
var _completed_lifetimes := 0
var _retired_impacts := 0
var _mismatch_count := 0
var _max_position_error := 0.0
var _max_velocity_error := 0.0


func _ready() -> void:
	# Keep the accepted GDScript path usable when a developer has not built the
	# optional extension yet. CI and migration builds require this to be enabled.
	if not ClassDB.class_exists("StarfallSimulationHost"):
		return
	_host = ClassDB.instantiate("StarfallSimulationHost") as Node
	if not is_instance_valid(_host):
		return
	add_child(_host)
	_enabled = true


func configure(material_world: Node) -> bool:
	reset_tracking()
	if not _enabled or not is_instance_valid(material_world):
		return false
	var configured := bool(_host.call(
		"configure_primary_gravity",
		material_world.primary_gravity_center,
		material_world.primary_surface_radius,
		material_world.primary_gravity_acceleration,
		30
	))
	_enabled = configured
	if configured:
		_fixed_step = float(_host.call("get_fixed_step_seconds"))
	return configured


func reset_tracking() -> void:
	_accumulator = 0.0
	_next_request_id = 1
	_records.clear()
	_pending_spawns.clear()
	_projectile_id_by_request.clear()
	_pending_retires.clear()
	_compared_samples = 0
	_completed_lifetimes = 0
	_retired_impacts = 0
	_mismatch_count = 0
	_max_position_error = 0.0
	_max_velocity_error = 0.0
	if is_instance_valid(_host):
		_host.call("reset_to_gate1_baseline")


func track_projectile(projectile: JuvenileStarseed, profile: CombatShotProfile) -> void:
	if not _enabled or not is_instance_valid(projectile) or not is_instance_valid(profile):
		return
	var request_id := _next_request_id
	_next_request_id += 1
	_records[request_id] = {
		"projectile": projectile,
		"history": [{
			"age": projectile.get_age(),
			"position": projectile.global_position,
			"velocity": projectile.velocity,
		}],
		"script_expired": false,
		"script_reason": "",
		"lifetime": profile.projectile_lifetime,
	}
	projectile.expired.connect(_on_script_projectile_expired.bind(request_id))
	_pending_spawns.append({
		"request_id": request_id,
		"position": projectile.global_position,
		"velocity": projectile.velocity,
		"lifetime": profile.projectile_lifetime,
		"gravity_scale": profile.projectile_gravity_scale,
	})


func _physics_process(delta: float) -> void:
	if not _enabled:
		return
	_sample_script_projectiles()
	_accumulator += maxf(delta, 0.0)
	while _accumulator + AGE_EPSILON >= _fixed_step:
		_submit_known_retires()
		_host.call("step_fixed")
		_accumulator -= _fixed_step
		_consume_native_events()
		_compare_native_states()
	# Submit after any due step. A shot born halfway through a 30 Hz interval
	# therefore starts at the next native boundary, while age-based history still
	# lets us compare it against the matching 60 Hz GDScript state.
	_submit_pending_spawns()


func get_snapshot() -> Dictionary:
	return {
		"enabled": _enabled,
		"active": _records.size(),
		"compared_samples": _compared_samples,
		"completed_lifetimes": _completed_lifetimes,
		"retired_impacts": _retired_impacts,
		"mismatches": _mismatch_count,
		"max_position_error_px": _max_position_error,
		"max_velocity_error_px_per_second": _max_velocity_error,
	}


func _sample_script_projectiles() -> void:
	for request_id: int in _records.keys():
		var record: Dictionary = _records[request_id]
		var projectile: JuvenileStarseed = record["projectile"] as JuvenileStarseed
		if not is_instance_valid(projectile) or bool(record["script_expired"]):
			continue
		var history: Array = record["history"]
		history.append({
			"age": projectile.get_age(),
			"position": projectile.global_position,
			"velocity": projectile.velocity,
		})


func _submit_known_retires() -> void:
	var projectile_ids := PackedInt64Array()
	var reasons := PackedInt32Array()
	for request_id: int in _pending_retires.keys():
		if not _projectile_id_by_request.has(request_id):
			continue
		projectile_ids.append(int(_projectile_id_by_request[request_id]))
		reasons.append(0 if str(_pending_retires[request_id]) == "impact" else 1)
		_pending_retires.erase(request_id)
	if not projectile_ids.is_empty():
		if not bool(_host.call("submit_projectile_retires", projectile_ids, reasons)):
			_mismatch_count += projectile_ids.size()


func _submit_pending_spawns() -> void:
	if _pending_spawns.is_empty():
		return
	var request_ids := PackedInt64Array()
	var positions := PackedVector2Array()
	var velocities := PackedVector2Array()
	var lifetimes := PackedFloat64Array()
	var gravity_scales := PackedFloat64Array()
	for spawn: Dictionary in _pending_spawns:
		request_ids.append(int(spawn["request_id"]))
		positions.append(spawn["position"] as Vector2)
		velocities.append(spawn["velocity"] as Vector2)
		lifetimes.append(float(spawn["lifetime"]))
		gravity_scales.append(float(spawn["gravity_scale"]))
	_pending_spawns.clear()
	if not bool(_host.call(
		"submit_projectile_spawns",
		request_ids,
		positions,
		velocities,
		lifetimes,
		gravity_scales
	)):
		_mismatch_count += request_ids.size()


func _consume_native_events() -> void:
	var events: Dictionary = _host.call("drain_projectile_event_batch") as Dictionary
	var kinds: PackedInt32Array = events.get("kinds", PackedInt32Array())
	var projectile_ids: PackedInt64Array = events.get("projectile_ids", PackedInt64Array())
	var request_ids: PackedInt64Array = events.get("request_ids", PackedInt64Array())
	var positions: PackedVector2Array = events.get("positions", PackedVector2Array())
	var velocities: PackedVector2Array = events.get("velocities", PackedVector2Array())
	for index in range(kinds.size()):
		var request_id := int(request_ids[index])
		match int(kinds[index]):
			0: # spawned
				_projectile_id_by_request[request_id] = int(projectile_ids[index])
			1: # expired
				_finish_native_lifetime(request_id, positions[index], velocities[index])
			2: # retired_on_impact
				_retired_impacts += 1
				_finish_record(request_id)
			3: # retired_external
				_finish_record(request_id)
			4: # rejected
				_mismatch_count += 1
				_finish_record(request_id)


func _compare_native_states() -> void:
	var states: Dictionary = _host.call("get_projectile_state_batch") as Dictionary
	var request_ids: PackedInt64Array = states.get("request_ids", PackedInt64Array())
	var positions: PackedVector2Array = states.get("positions", PackedVector2Array())
	var velocities: PackedVector2Array = states.get("velocities", PackedVector2Array())
	var ages: PackedFloat64Array = states.get("ages", PackedFloat64Array())
	for index in range(request_ids.size()):
		var request_id := int(request_ids[index])
		if not _records.has(request_id):
			continue
		var sample := _sample_at_age(_records[request_id]["history"] as Array, ages[index])
		if sample.is_empty():
			continue
		_record_comparison(sample, positions[index], velocities[index])


func _sample_at_age(history: Array, target_age: float) -> Dictionary:
	if history.is_empty():
		return {}
	for sample: Dictionary in history:
		if absf(float(sample["age"]) - target_age) <= AGE_EPSILON:
			return sample
	return {}


func _on_script_projectile_expired(reason: String, request_id: int) -> void:
	if not _records.has(request_id):
		return
	var record: Dictionary = _records[request_id]
	var projectile: JuvenileStarseed = record["projectile"] as JuvenileStarseed
	if is_instance_valid(projectile):
		var history: Array = record["history"]
		history.append({
			"age": projectile.get_age(),
			"position": projectile.global_position,
			"velocity": projectile.velocity,
		})
	record["script_expired"] = true
	record["script_reason"] = reason
	if reason != "lifetime":
		_pending_retires[request_id] = reason


func _finish_native_lifetime(
	request_id: int,
	native_position: Vector2,
	native_velocity: Vector2
) -> void:
	if not _records.has(request_id):
		_mismatch_count += 1
		return
	var record: Dictionary = _records[request_id]
	if not bool(record["script_expired"]) or str(record["script_reason"]) != "lifetime":
		_mismatch_count += 1
	else:
		var final_sample := _sample_at_age(
			record["history"] as Array,
			float(record["lifetime"])
		)
		if final_sample.is_empty():
			_mismatch_count += 1
		else:
			_record_comparison(final_sample, native_position, native_velocity)
		_completed_lifetimes += 1
	_finish_record(request_id)


func _record_comparison(
	script_sample: Dictionary,
	native_position: Vector2,
	native_velocity: Vector2
) -> void:
	var position_error := (
		script_sample["position"] as Vector2
	).distance_to(native_position)
	var velocity_error := (
		script_sample["velocity"] as Vector2
	).distance_to(native_velocity)
	_max_position_error = maxf(_max_position_error, position_error)
	_max_velocity_error = maxf(_max_velocity_error, velocity_error)
	_compared_samples += 1
	if (
		position_error > POSITION_TOLERANCE_PX
		or velocity_error > VELOCITY_TOLERANCE_PX_PER_SECOND
	):
		_mismatch_count += 1


func _finish_record(request_id: int) -> void:
	if not _records.has(request_id):
		return
	_records.erase(request_id)
	_projectile_id_by_request.erase(request_id)
	_pending_retires.erase(request_id)
