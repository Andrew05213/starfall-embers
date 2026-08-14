class_name NativeGravityProvider
extends RefCounted

## Batched gravity adapter for entity queries and local-field lifecycle.
## MaterialWorld remains the GDScript fallback/shadow reference; Native is used
## only when the caller explicitly selects shadow or authoritative mode.

const MODE_GDSCRIPT_FALLBACK := "gdscript_fallback"
const MODE_NATIVE_SHADOW := "native_shadow"
const MODE_NATIVE_AUTHORITATIVE := "native_authoritative"
const GRAVITY_DTO_VERSION := 1
const ZERO_GRAVITY_EXIT := 0.001

const FIELD_RADIAL := 0
const FIELD_UNIFORM := 1
const COMMAND_ADD := 0
const COMMAND_UPDATE := 1
const COMMAND_REMOVE := 2
const RESULT_ACCEPTED := 0
const RESULT_INVALID := 1
const RESULT_DUPLICATE := 2
const RESULT_NOT_FOUND := 3

var mode := MODE_GDSCRIPT_FALLBACK
var material_world: Node
var native_host: Node
var native_available := false
var compared_samples := 0
var mismatches := 0
var max_acceleration_error := 0.0
var last_diagnostic := ""

var _next_request_id := 1
var _next_source_id := 1
var _source_bindings: Dictionary = {}
var _source_specs: Dictionary = {}


func configure(world: Node, host: Node = null) -> void:
	material_world = world
	native_host = host
	last_diagnostic = ""
	native_available = is_instance_valid(native_host) and native_host.has_method("sample_gravity_batch")
	if native_available and native_host.has_method("get_gravity_transport_version"):
		native_available = int(native_host.call("get_gravity_transport_version")) == GRAVITY_DTO_VERSION
	if not native_available:
		last_diagnostic = "native gravity extension unavailable or DTO mismatch"


func reset_bindings() -> void:
	## Runtime reset clears both-side mappings. IDs remain monotonic so delayed
	## destruction of an old starseed cannot remove a newly created source.
	_source_bindings.clear()
	_source_specs.clear()


func set_mode(next_mode: String) -> bool:
	if next_mode not in [MODE_GDSCRIPT_FALLBACK, MODE_NATIVE_SHADOW, MODE_NATIVE_AUTHORITATIVE]:
		return false
	mode = next_mode
	return true


func sample(world_position: Vector2) -> Dictionary:
	var fallback := _fallback_sample(world_position)
	if mode == MODE_GDSCRIPT_FALLBACK or not native_available:
		return fallback
	var native_results := _sample_native_batch([world_position])
	if native_results.size() != 1:
		last_diagnostic = "native gravity query failed; using fallback"
		return fallback
	if mode == MODE_NATIVE_SHADOW:
		_compare(fallback, native_results[0])
		return fallback
	return native_results[0]


func sample_pair(current_position: Vector2, predicted_position: Vector2) -> Array[Dictionary]:
	var fallback: Array[Dictionary] = [
		_fallback_sample(current_position),
		_fallback_sample(predicted_position),
	]
	if mode == MODE_GDSCRIPT_FALLBACK or not native_available:
		return fallback
	var native_results := _sample_native_batch([current_position, predicted_position])
	if native_results.size() != 2:
		last_diagnostic = "native gravity pair query failed; using fallback"
		return fallback
	if int(native_results[0].get("tick", -1)) != int(native_results[1].get("tick", -1)):
		last_diagnostic = "native gravity pair crossed a tick boundary; using fallback"
		return fallback
	if mode == MODE_NATIVE_SHADOW:
		for index in native_results.size():
			_compare(fallback[index], native_results[index])
		return fallback
	return native_results


func sample_batch(world_positions: Array[Vector2]) -> Array[Dictionary]:
	## Native-only batch retained for benchmark and bridge tests.
	return _sample_native_batch(world_positions)


func add_gravity_source(world_position: Vector2, strength: float, radius: float, ttl: float) -> int:
	return _add_source(FIELD_RADIAL, world_position, Vector2.ZERO, strength, radius, ttl)


func add_uniform_source(world_position: Vector2, vector: Vector2, radius: float, ttl: float) -> int:
	return _add_source(FIELD_UNIFORM, world_position, vector, 0.0, radius, ttl)


func update_gravity_source(source_id: int, world_position: Vector2) -> bool:
	if not _source_specs.has(source_id):
		return false
	var spec: Dictionary = _source_specs[source_id]
	var native_ok := _submit_source(
		COMMAND_UPDATE,
		int(spec["field_kind"]),
		source_id,
		world_position,
		spec["vector"] as Vector2,
		float(spec["strength"]),
		float(spec["radius"]),
		-1.0,
		int(spec.get("expires_at_tick", 0))
	)
	if _should_submit_native() and not native_ok:
		return false
	var binding: Dictionary = _source_bindings.get(source_id, {})
	var material_id := int(binding.get("material_id", 0))
	if is_instance_valid(material_world) and material_id > 0 and material_world.has_method("update_gravity_source"):
		material_world.call("update_gravity_source", material_id, world_position)
	spec["position"] = world_position
	_source_specs[source_id] = spec
	return true


func remove_gravity_source(source_id: int) -> bool:
	if not _source_specs.has(source_id):
		return false
	var native_ok := _submit_source(
		COMMAND_REMOVE, FIELD_RADIAL, source_id, Vector2.ZERO, Vector2.ZERO, 0.0, 1.0, -1.0, 0
	)
	# Removal is idempotent after a finite Native source has naturally expired.
	if _should_submit_native() and not native_ok and last_diagnostic != "native gravity source already absent":
		return false
	var binding: Dictionary = _source_bindings.get(source_id, {})
	var material_id := int(binding.get("material_id", 0))
	if is_instance_valid(material_world) and material_id > 0 and material_world.has_method("remove_gravity_source"):
		material_world.call("remove_gravity_source", material_id)
	_source_bindings.erase(source_id)
	_source_specs.erase(source_id)
	return true


func get_source_snapshots() -> Array[Dictionary]:
	var ids: Array = _source_specs.keys()
	ids.sort()
	var result: Array[Dictionary] = []
	var current_tick := int(native_host.call("get_tick")) if is_instance_valid(native_host) and native_host.has_method("get_tick") else 0
	for source_id in ids:
		var spec: Dictionary = _source_specs[source_id]
		var expiry := int(spec.get("expires_at_tick", 0))
		result.append({
			"source_id": int(source_id),
			"field_kind": int(spec.get("field_kind", FIELD_RADIAL)),
			"position": spec.get("position", Vector2.ZERO),
			"radius": float(spec.get("radius", 0.0)),
			"strength": float(spec.get("strength", 0.0)),
			"vector": spec.get("vector", Vector2.ZERO),
			"remaining_ticks": -1 if expiry == 0 else maxi(0, expiry - current_tick),
		})
	return result


func get_snapshot() -> Dictionary:
	return {
		"mode": mode,
		"enabled": native_available,
		"compared_samples": compared_samples,
		"mismatches": mismatches,
		"max_acceleration_error": max_acceleration_error,
		"last_diagnostic": last_diagnostic,
		"native_tick": int(native_host.call("get_tick")) if is_instance_valid(native_host) and native_host.has_method("get_tick") else 0,
		"source_count": _source_specs.size(),
	}


func _add_source(field_kind: int, world_position: Vector2, vector: Vector2,
		strength: float, radius: float, ttl: float) -> int:
	if not world_position.is_finite() or not vector.is_finite() or not _is_finite_float(strength):
		last_diagnostic = "gravity source rejected: non-finite input"
		return 0
	if radius <= 0.0 or not _is_finite_float(radius) or ttl != -1.0 and (ttl < 0.0 or not _is_finite_float(ttl)):
		last_diagnostic = "gravity source rejected: invalid radius or TTL"
		return 0
	var source_id := _allocate_source_id()
	if source_id <= 0:
		return 0
	var expiry := _expiry_tick(ttl)
	var native_ok := _submit_source(
		COMMAND_ADD, field_kind, source_id, world_position, vector, strength, radius, ttl, expiry
	)
	if _should_submit_native() and not native_ok:
		return 0
	var material_id := 0
	if is_instance_valid(material_world):
		if field_kind == FIELD_UNIFORM and material_world.has_method("add_uniform_gravity_source"):
			material_id = int(material_world.call("add_uniform_gravity_source", world_position, vector, radius, ttl))
		elif field_kind == FIELD_RADIAL and material_world.has_method("add_gravity_source"):
			material_id = int(material_world.call("add_gravity_source", world_position, strength, radius, ttl))
	if material_id <= 0 and is_instance_valid(material_world):
		if _should_submit_native():
			_submit_source(COMMAND_REMOVE, field_kind, source_id, Vector2.ZERO, Vector2.ZERO, 0.0, 1.0, -1.0, 0)
		last_diagnostic = "gravity source rejected by MaterialWorld"
		return 0
	_source_bindings[source_id] = {"material_id": material_id, "field_kind": field_kind}
	_source_specs[source_id] = {
		"field_kind": field_kind,
		"position": world_position,
		"strength": strength,
		"radius": radius,
		"vector": vector,
		"expires_at_tick": expiry,
	}
	return source_id


func _sample_native_batch(world_positions: Array[Vector2]) -> Array[Dictionary]:
	if not native_available or not is_instance_valid(native_host):
		return []
	var request_ids := PackedInt64Array()
	var positions := PackedVector2Array()
	for position in world_positions:
		request_ids.append(_next_request())
		positions.append(position)
	var response: Dictionary = native_host.call(
		"sample_gravity_batch", GRAVITY_DTO_VERSION, request_ids, positions
	)
	if response.is_empty() or not response.has("accelerations"):
		return []
	var accelerations: PackedVector2Array = response["accelerations"]
	var magnitudes: PackedFloat64Array = response["magnitudes"]
	var source_ids: PackedInt64Array = response["dominant_source_ids"]
	var ticks: PackedInt64Array = response["ticks"]
	var zeros: PackedInt32Array = response["zero_gravity"]
	var transitioning: PackedInt32Array = response["transitioning"]
	var limited: PackedInt32Array = response["sample_limit_reached"]
	if accelerations.size() != world_positions.size() or magnitudes.size() != accelerations.size() \
		or source_ids.size() != accelerations.size() or ticks.size() != accelerations.size() \
		or zeros.size() != accelerations.size() or transitioning.size() != accelerations.size() \
		or limited.size() != accelerations.size():
		return []
	var results: Array[Dictionary] = []
	for index in accelerations.size():
		results.append({
			"tick": int(ticks[index]),
			"acceleration": accelerations[index],
			"magnitude": float(magnitudes[index]),
			"down": accelerations[index].normalized() if magnitudes[index] > ZERO_GRAVITY_EXIT else Vector2.ZERO,
			"dominant_source_id": int(source_ids[index]),
			"zero_gravity": int(zeros[index]) != 0,
			"transitioning": int(transitioning[index]) != 0,
			"sample_limit_reached": int(limited[index]) != 0,
		})
	return results


func _fallback_sample(world_position: Vector2) -> Dictionary:
	var acceleration := Vector2.ZERO
	if is_instance_valid(material_world) and material_world.has_method("get_gravity_at"):
		acceleration = material_world.call("get_gravity_at", world_position) as Vector2
	var magnitude := acceleration.length()
	var fallback_tick := 0
	if is_instance_valid(material_world) and material_world.has_method("get_stats"):
		fallback_tick = int(material_world.call("get_stats").get("tick", 0))
	return {
		"tick": fallback_tick,
		"acceleration": acceleration,
		"magnitude": magnitude,
		"down": acceleration.normalized() if magnitude > ZERO_GRAVITY_EXIT else Vector2.ZERO,
		"dominant_source_id": 0,
		"zero_gravity": magnitude <= ZERO_GRAVITY_EXIT,
		"transitioning": false,
		"sample_limit_reached": false,
	}


func _compare(fallback: Dictionary, native: Dictionary) -> void:
	compared_samples += 1
	var error := (fallback["acceleration"] as Vector2).distance_to(native["acceleration"] as Vector2)
	max_acceleration_error = maxf(max_acceleration_error, error)
	if error > 0.001:
		mismatches += 1


func _submit_source(command_kind: int, field_kind: int, source_id: int, position: Vector2,
		vector: Vector2, strength: float, radius: float, ttl: float,
		expires_at_tick: int = 0) -> bool:
	last_diagnostic = ""
	if not _should_submit_native() or not is_instance_valid(native_host):
		return true
	var expiry := expires_at_tick if command_kind != COMMAND_ADD else _expiry_tick(ttl)
	var request_id := _next_request()
	var accepted: bool = native_host.call(
		"submit_gravity_source_commands",
		GRAVITY_DTO_VERSION,
		PackedInt32Array([command_kind]),
		PackedInt32Array([field_kind]),
		PackedInt64Array([request_id]),
		PackedInt64Array([source_id]),
		PackedVector2Array([position]),
		PackedVector2Array([vector]),
		PackedFloat64Array([strength]),
		PackedFloat64Array([maxf(radius, 0.001)]),
		PackedInt64Array([expiry])
	)
	var result_code := RESULT_INVALID
	if native_host.has_method("drain_gravity_source_command_result_batch"):
		var results: Dictionary = native_host.call("drain_gravity_source_command_result_batch")
		var request_results: PackedInt64Array = results.get("request_ids", PackedInt64Array())
		var codes: PackedInt32Array = results.get("codes", PackedInt32Array())
		for index in mini(request_results.size(), codes.size()):
			if int(request_results[index]) == request_id:
				result_code = int(codes[index])
				break
	if result_code == RESULT_ACCEPTED and accepted:
		return true
	if command_kind == COMMAND_REMOVE and result_code == RESULT_NOT_FOUND:
		last_diagnostic = "native gravity source already absent"
		return true
	last_diagnostic = "native gravity source command rejected (%d)" % result_code
	return false


func _should_submit_native() -> bool:
	return native_available and mode != MODE_GDSCRIPT_FALLBACK


func _expiry_tick(ttl: float) -> int:
	if ttl <= 0.0 or not is_instance_valid(native_host) or not native_host.has_method("get_fixed_step_seconds"):
		return 0
	var fixed_step := maxf(float(native_host.call("get_fixed_step_seconds")), 0.000001)
	var current_tick := int(native_host.call("get_tick")) if native_host.has_method("get_tick") else 0
	return current_tick + ceili(ttl / fixed_step)


func _allocate_source_id() -> int:
	var source_id := _next_source_id
	_next_source_id += 1
	if source_id <= 0:
		last_diagnostic = "gravity source ID exhausted"
		return 0
	return source_id


func _next_request() -> int:
	var request_id := _next_request_id
	_next_request_id += 1
	return request_id


func _is_finite_float(value: float) -> bool:
	return is_finite(value)
