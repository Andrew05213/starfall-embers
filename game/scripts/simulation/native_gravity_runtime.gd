class_name NativeGravityRuntime
extends Node

## Fixed-clock owner for the one formal Native gravity host.
## Local fields are queued by starseeds before this node's physics priority;
## players sample after the host has advanced a complete 30 Hz tick.

const FIXED_HZ := 30.0
const FIXED_STEP := 1.0 / FIXED_HZ
const MAX_STEPS_PER_FRAME := 3
const RANDOM_SEED := 0x51A7E11

var material_world: Node
var native_host: Node
var provider: NativeGravityProvider
var native_available := false
var last_step_count := 0
var total_steps := 0
var _accumulator := 0.0


func _ready() -> void:
	process_physics_priority = -100
	if not is_instance_valid(material_world):
		var parent := get_parent()
		if is_instance_valid(parent):
			material_world = parent.get_node_or_null("MaterialWorld")
	configure(material_world)


func configure(world: Node) -> void:
	material_world = world
	if is_instance_valid(native_host):
		native_host.free()
	native_host = _create_native_host()
	provider = NativeGravityProvider.new()
	provider.configure(material_world, native_host)
	provider.set_mode(NativeGravityProvider.MODE_NATIVE_AUTHORITATIVE)
	native_available = provider.native_available
	_accumulator = 0.0
	last_step_count = 0


func reset_runtime() -> void:
	if not is_instance_valid(material_world):
		return
	_accumulator = 0.0
	last_step_count = 0
	total_steps = 0
	if is_instance_valid(provider):
		provider.reset_bindings()
	if is_instance_valid(native_host):
		native_host.free()
	native_host = _create_native_host()
	if is_instance_valid(provider):
		provider.configure(material_world, native_host)
		provider.set_mode(NativeGravityProvider.MODE_NATIVE_AUTHORITATIVE)
		native_available = provider.native_available
	else:
		native_available = false


func get_provider() -> NativeGravityProvider:
	if not is_instance_valid(provider):
		provider = NativeGravityProvider.new()
		provider.configure(material_world, native_host)
	return provider


func get_tick() -> int:
	return int(native_host.call("get_tick")) if is_instance_valid(native_host) and native_host.has_method("get_tick") else 0


func get_snapshot() -> Dictionary:
	var snapshot := provider.get_snapshot() if is_instance_valid(provider) else {}
	snapshot["fixed_hz"] = FIXED_HZ
	snapshot["last_step_count"] = last_step_count
	snapshot["total_steps"] = total_steps
	return snapshot


func _create_native_host() -> Node:
	if not ClassDB.class_exists("StarfallSimulationHost") or not is_instance_valid(material_world):
		return null
	var host := StarfallSimulationHost.new()
	if not host.configure_primary_gravity(
		material_world.primary_gravity_center,
		material_world.primary_surface_radius,
		material_world.primary_gravity_acceleration,
		int(FIXED_HZ),
		RANDOM_SEED
	):
		host.free()
		return null
	add_child(host)
	return host


func _physics_process(delta: float) -> void:
	last_step_count = 0
	if not is_instance_valid(native_host) or not native_host.has_method("step_fixed"):
		return
	_accumulator = minf(_accumulator + maxf(delta, 0.0), FIXED_STEP * MAX_STEPS_PER_FRAME)
	while _accumulator >= FIXED_STEP and last_step_count < MAX_STEPS_PER_FRAME:
		native_host.call("step_fixed")
		_accumulator -= FIXED_STEP
		last_step_count += 1
		total_steps += 1
