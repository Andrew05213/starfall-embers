class_name NativeGravityProvider
extends RefCounted

## Batched gravity adapter for entity queries. The GDScript MaterialWorld remains
## the fallback and shadow reference; native queries never perform gameplay side
## effects and are only authoritative when the caller explicitly selects it.

const MODE_GDSCRIPT_FALLBACK := "gdscript_fallback"
const MODE_NATIVE_SHADOW := "native_shadow"
const MODE_NATIVE_AUTHORITATIVE := "native_authoritative"
const GRAVITY_DTO_VERSION := 1
const ZERO_GRAVITY_EXIT := 0.001

var mode := MODE_GDSCRIPT_FALLBACK
var material_world: Node
var native_host: Node
var native_available := false
var compared_samples := 0
var mismatches := 0
var max_acceleration_error := 0.0
var last_diagnostic := ""
var _next_request_id := 1
var _source_bindings: Dictionary = {}
var _source_specs: Dictionary = {}


func configure(world: Node, host: Node = null) -> void:
	material_world = world
	native_host = host
	native_available = is_instance_valid(native_host) and native_host.has_method("sample_gravity_batch")
	if native_available and native_host.has_method("get_gravity_transport_version"):
		native_available = int(native_host.call("get_gravity_transport_version")) == GRAVITY_DTO_VERSION
	if not native_available:
		last_diagnostic = "native gravity extension unavailable or DTO mismatch"


func set_mode(next_mode: String) -> bool:
	if next_mode not in [MODE_GDSCRIPT_FALLBACK, MODE_NATIVE_SHADOW, MODE_NATIVE_AUTHORITATIVE]:
		return false
	mode = next_mode
	return true


func sample(world_position: Vector2) -> Dictionary:
	var fallback := _fallback_sample(world_position)
	if mode == MODE_GDSCRIPT_FALLBACK or not native_available:
		return fallback
	var native_results := sample_batch([world_position])
	if native_results.is_empty():
		last_diagnostic = "native gravity query batch failed; using fallback"
		return fallback
	var native := native_results[0]
	if mode == MODE_NATIVE_SHADOW:
		_compare(fallback, native)
		return fallback
	return native


func sample_batch(world_positions: Array[Vector2]) -> Array[Dictionary]:
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


func add_gravity_source(world_position: Vector2, strength: float, radius: float, ttl: float) -> int:
	if not is_instance_valid(material_world) or not material_world.has_method("add_gravity_source"):
		return 0
	var source_id := int(material_world.call("add_gravity_source", world_position, strength, radius, ttl))
	_source_bindings[source_id] = true
	_source_specs[source_id] = {"field_kind": 0, "strength": strength, "radius": radius, "vector": Vector2.ZERO}
	_submit_source(0, 0, source_id, world_position, Vector2.ZERO, strength, radius, ttl)
	return source_id


func add_uniform_source(world_position: Vector2, vector: Vector2, radius: float, ttl: float) -> int:
	var source_id := _next_request()
	_source_specs[source_id] = {"field_kind": 1, "strength": 0.0, "radius": radius, "vector": vector}
	_submit_source(0, 1, source_id, world_position, vector, 0.0, radius, ttl)
	return source_id


func update_gravity_source(source_id: int, world_position: Vector2) -> void:
	if is_instance_valid(material_world) and material_world.has_method("update_gravity_source"):
		material_world.call("update_gravity_source", source_id, world_position)
	var spec: Dictionary = _source_specs.get(source_id, {
		"field_kind": 0, "strength": 0.0, "radius": 1.0, "vector": Vector2.ZERO,
	})
	_submit_source(
		1,
		int(spec["field_kind"]),
		source_id,
		world_position,
		spec["vector"] as Vector2,
		float(spec["strength"]),
		float(spec["radius"]),
		-1.0
	)


func remove_gravity_source(source_id: int) -> void:
	if is_instance_valid(material_world) and material_world.has_method("remove_gravity_source"):
		material_world.call("remove_gravity_source", source_id)
	_submit_source(2, 0, source_id, Vector2.ZERO, Vector2.ZERO, 0.0, 1.0, -1.0)
	_source_bindings.erase(source_id)
	_source_specs.erase(source_id)


func get_snapshot() -> Dictionary:
	return {
		"mode": mode,
		"enabled": native_available,
		"compared_samples": compared_samples,
		"mismatches": mismatches,
		"max_acceleration_error": max_acceleration_error,
		"last_diagnostic": last_diagnostic,
	}


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
		vector: Vector2, strength: float, radius: float, ttl: float) -> void:
	if not native_available or not is_instance_valid(native_host):
		return
	var expiry := 0
	if ttl > 0.0 and native_host.has_method("get_fixed_step_seconds"):
		expiry = int(native_host.call("get_tick")) + ceili(ttl / maxf(float(native_host.call("get_fixed_step_seconds")), 0.000001))
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
	if not accepted:
		last_diagnostic = "native gravity source command rejected"


func _next_request() -> int:
	var request_id := _next_request_id
	_next_request_id += 1
	return request_id
