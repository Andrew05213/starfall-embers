class_name NativeBallisticsShadow
extends Node

## Three-mode Gate 1.5 runtime. GDScript fallback owns gameplay without the
## extension; shadow mode compares both paths; authoritative mode consumes only
## batched C++ state and events for advancement, collision, lifetime and expiry.

const MODE_GDSCRIPT_FALLBACK := "gdscript_fallback"
const MODE_NATIVE_SHADOW := "native_shadow"
const MODE_NATIVE_AUTHORITATIVE := "native_authoritative"
const MODES := [MODE_GDSCRIPT_FALLBACK, MODE_NATIVE_SHADOW, MODE_NATIVE_AUTHORITATIVE]
const POSITION_TOLERANCE_PX := 0.125
const VELOCITY_TOLERANCE_PX_PER_SECOND := 0.5
const AGE_EPSILON := 0.00001
const DEFAULT_RANDOM_SEED := 0x51A7E11

@export_enum("gdscript_fallback", "native_shadow", "native_authoritative")
var requested_mode := MODE_NATIVE_AUTHORITATIVE

var _host: Node
var _host_available := false
var _active_mode := MODE_GDSCRIPT_FALLBACK
var _material_world: Node
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
var _native_entity_hits := 0
var _native_terrain_hits := 0
var _mismatch_count := 0
var _max_position_error := 0.0
var _max_velocity_error := 0.0


func _ready() -> void:
	if not ClassDB.class_exists("StarfallSimulationHost"):
		return
	_host = ClassDB.instantiate("StarfallSimulationHost") as Node
	if not is_instance_valid(_host):
		return
	add_child(_host)
	_host_available = true


func set_mode(mode: String) -> bool:
	if mode not in MODES:
		return false
	if mode == _active_mode:
		requested_mode = mode
		return true
	if not _records.is_empty() and mode != _active_mode:
		return false
	requested_mode = mode
	if is_instance_valid(_material_world):
		return configure(_material_world)
	_active_mode = mode if mode == MODE_GDSCRIPT_FALLBACK or _host_available else MODE_GDSCRIPT_FALLBACK
	return _active_mode == mode


func get_mode() -> String:
	return _active_mode


func configure(material_world: Node) -> bool:
	_material_world = material_world
	reset_tracking()
	if requested_mode == MODE_GDSCRIPT_FALLBACK:
		_active_mode = MODE_GDSCRIPT_FALLBACK
		return true
	if not _host_available or not is_instance_valid(material_world):
		_active_mode = MODE_GDSCRIPT_FALLBACK
		return false
	var configured := bool(_host.call(
		"configure_primary_gravity",
		material_world.primary_gravity_center,
		material_world.primary_surface_radius,
		material_world.primary_gravity_acceleration,
		30,
		DEFAULT_RANDOM_SEED
	))
	_active_mode = requested_mode if configured else MODE_GDSCRIPT_FALLBACK
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
	_native_entity_hits = 0
	_native_terrain_hits = 0
	_mismatch_count = 0
	_max_position_error = 0.0
	_max_velocity_error = 0.0
	if is_instance_valid(_host):
		_host.call("reset_to_gate1_baseline")


func track_projectile(projectile: JuvenileStarseed, profile: CombatShotProfile) -> void:
	if _active_mode == MODE_GDSCRIPT_FALLBACK:
		return
	if not is_instance_valid(projectile) or not is_instance_valid(profile):
		return
	var request_id := _next_request_id
	_next_request_id += 1
	if _active_mode == MODE_NATIVE_AUTHORITATIVE:
		projectile.configure_native_presentation()
	_records[request_id] = {
		"projectile": projectile,
		"profile": profile,
		"history": [{
			"age": projectile.get_age(),
			"position": projectile.global_position,
			"velocity": projectile.velocity,
		}],
		"script_expired": false,
		"script_reason": "",
		"lifetime": profile.projectile_lifetime,
	}
	if _active_mode == MODE_NATIVE_SHADOW:
		projectile.expired.connect(_on_script_projectile_expired.bind(request_id))
	_pending_spawns.append({
		"request_id": request_id,
		"position": projectile.global_position,
		"velocity": projectile.velocity,
		"lifetime": profile.projectile_lifetime,
		"gravity_scale": profile.projectile_gravity_scale,
		"collision_radius": profile.collision_radius,
	})


func _physics_process(delta: float) -> void:
	if _active_mode == MODE_GDSCRIPT_FALLBACK:
		return
	if _active_mode == MODE_NATIVE_SHADOW:
		_sample_script_projectiles()
	_accumulator += maxf(delta, 0.0)
	while _accumulator + AGE_EPSILON >= _fixed_step:
		if _active_mode == MODE_NATIVE_AUTHORITATIVE:
			if not _submit_collision_world():
				_mismatch_count += 1
		else:
			_submit_known_retires()
		_host.call("step_fixed")
		_accumulator -= _fixed_step
		_consume_native_events()
		if _active_mode == MODE_NATIVE_AUTHORITATIVE:
			_apply_native_states()
		else:
			_compare_native_states()
	_submit_pending_spawns()


func get_snapshot() -> Dictionary:
	return {
		"enabled": _host_available,
		"mode": _active_mode,
		"requested_mode": requested_mode,
		"random_seed": DEFAULT_RANDOM_SEED,
		"native_tick": int(_host.call("get_tick")) if _host_available else 0,
		"active": _records.size(),
		"compared_samples": _compared_samples,
		"completed_lifetimes": _completed_lifetimes,
		"retired_impacts": _retired_impacts,
		"native_entity_hits": _native_entity_hits,
		"native_terrain_hits": _native_terrain_hits,
		"mismatches": _mismatch_count,
		"max_position_error_px": _max_position_error,
		"max_velocity_error_px_per_second": _max_velocity_error,
	}


func _submit_collision_world() -> bool:
	if not is_instance_valid(_material_world):
		return false
	var collider_ids := PackedInt64Array()
	var shape_kinds := PackedInt32Array()
	var centers := PackedVector2Array()
	var half_extents := PackedVector2Array()
	for candidate in get_tree().get_nodes_in_group("combat_targets"):
		if not is_instance_valid(candidate) or not candidate.has_method("get_native_collision_proxy"):
			continue
		var proxy: Dictionary = candidate.call("get_native_collision_proxy") as Dictionary
		if proxy.is_empty():
			continue
		collider_ids.append(int(proxy["collider_id"]))
		shape_kinds.append(int(proxy["shape_kind"]))
		centers.append(proxy["center"] as Vector2)
		half_extents.append(proxy["half_extents"] as Vector2)
	var terrain: Dictionary = _material_world.call("get_native_collision_grid") as Dictionary
	return bool(_host.call(
		"submit_collision_world",
		collider_ids,
		shape_kinds,
		centers,
		half_extents,
		terrain.get("cells", PackedByteArray()),
		int(terrain.get("width", 0)),
		int(terrain.get("height", 0)),
		terrain.get("origin", Vector2.ZERO) as Vector2,
		float(terrain.get("cell_size", 1.0))
	))


func _sample_script_projectiles() -> void:
	for request_id: int in _records.keys():
		var record: Dictionary = _records[request_id]
		var projectile_value: Variant = record["projectile"]
		if not is_instance_valid(projectile_value) or bool(record["script_expired"]):
			continue
		var projectile: JuvenileStarseed = projectile_value as JuvenileStarseed
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
	var collision_radii := PackedFloat64Array()
	for spawn: Dictionary in _pending_spawns:
		request_ids.append(int(spawn["request_id"]))
		positions.append(spawn["position"] as Vector2)
		velocities.append(spawn["velocity"] as Vector2)
		lifetimes.append(float(spawn["lifetime"]))
		gravity_scales.append(float(spawn["gravity_scale"]))
		collision_radii.append(float(spawn["collision_radius"]))
	_pending_spawns.clear()
	if not bool(_host.call(
		"submit_projectile_spawns",
		request_ids,
		positions,
		velocities,
		lifetimes,
		gravity_scales,
		collision_radii
	)):
		_mismatch_count += request_ids.size()


func _consume_native_events() -> void:
	var events: Dictionary = _host.call("drain_projectile_event_batch") as Dictionary
	var kinds: PackedInt32Array = events.get("kinds", PackedInt32Array())
	var projectile_ids: PackedInt64Array = events.get("projectile_ids", PackedInt64Array())
	var request_ids: PackedInt64Array = events.get("request_ids", PackedInt64Array())
	var collider_ids: PackedInt64Array = events.get("collider_ids", PackedInt64Array())
	var positions: PackedVector2Array = events.get("positions", PackedVector2Array())
	var velocities: PackedVector2Array = events.get("velocities", PackedVector2Array())
	for index in range(kinds.size()):
		var request_id := int(request_ids[index])
		match int(kinds[index]):
			0: # spawned
				_projectile_id_by_request[request_id] = int(projectile_ids[index])
			1: # expired
				if _active_mode == MODE_NATIVE_AUTHORITATIVE:
					_apply_authoritative_expiry(request_id, "lifetime")
				else:
					_finish_native_lifetime(request_id, positions[index], velocities[index])
			2: # retired_on_impact (shadow)
				_retired_impacts += 1
				_finish_record(request_id)
			3: # retired_external (shadow)
				_finish_record(request_id)
			4: # rejected
				_mismatch_count += 1
				if _active_mode == MODE_NATIVE_AUTHORITATIVE:
					_apply_authoritative_expiry(request_id, "rejected")
				else:
					_finish_record(request_id)
			5: # native entity hit
				_native_entity_hits += 1
				_apply_authoritative_hit(
					request_id,
					int(collider_ids[index]),
					positions[index],
					velocities[index]
				)
			6: # native terrain hit
				_native_terrain_hits += 1
				_apply_authoritative_hit(request_id, 0, positions[index], velocities[index])


func _apply_native_states() -> void:
	var states: Dictionary = _host.call("get_projectile_state_batch") as Dictionary
	var request_ids: PackedInt64Array = states.get("request_ids", PackedInt64Array())
	var previous_positions: PackedVector2Array = states.get("previous_positions", PackedVector2Array())
	var positions: PackedVector2Array = states.get("positions", PackedVector2Array())
	var velocities: PackedVector2Array = states.get("velocities", PackedVector2Array())
	var ages: PackedFloat64Array = states.get("ages", PackedFloat64Array())
	for index in range(request_ids.size()):
		var request_id := int(request_ids[index])
		if not _records.has(request_id):
			continue
		var projectile: JuvenileStarseed = _records[request_id]["projectile"] as JuvenileStarseed
		if is_instance_valid(projectile):
			projectile.apply_native_state(
				previous_positions[index], positions[index], velocities[index], ages[index]
			)


func _apply_authoritative_hit(
	request_id: int,
	collider_id: int,
	position: Vector2,
	impact_velocity: Vector2
) -> void:
	if not _records.has(request_id):
		_mismatch_count += 1
		return
	var projectile: JuvenileStarseed = _records[request_id]["projectile"] as JuvenileStarseed
	var target: Node = null
	if collider_id > 0:
		target = instance_from_id(collider_id) as Node
	if is_instance_valid(projectile):
		projectile.apply_native_hit(target, position, impact_velocity)
	_finish_record(request_id)


func _apply_authoritative_expiry(request_id: int, reason: String) -> void:
	if not _records.has(request_id):
		return
	var projectile: JuvenileStarseed = _records[request_id]["projectile"] as JuvenileStarseed
	if is_instance_valid(projectile):
		projectile.apply_native_expire(reason)
	if reason == "lifetime":
		_completed_lifetimes += 1
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
		if not sample.is_empty():
			_record_comparison(sample, positions[index], velocities[index])


func _sample_at_age(history: Array, target_age: float) -> Dictionary:
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
		var final_sample := _sample_at_age(record["history"] as Array, float(record["lifetime"]))
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
	var position_error := (script_sample["position"] as Vector2).distance_to(native_position)
	var velocity_error := (script_sample["velocity"] as Vector2).distance_to(native_velocity)
	_max_position_error = maxf(_max_position_error, position_error)
	_max_velocity_error = maxf(_max_velocity_error, velocity_error)
	_compared_samples += 1
	if position_error > POSITION_TOLERANCE_PX or velocity_error > VELOCITY_TOLERANCE_PX_PER_SECOND:
		_mismatch_count += 1


func _finish_record(request_id: int) -> void:
	_records.erase(request_id)
	_projectile_id_by_request.erase(request_id)
	_pending_retires.erase(request_id)
