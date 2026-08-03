extends SceneTree


func _init() -> void:
	var host := StarfallSimulationHost.new()
	assert(host.get_gravity_transport_version() == 1)
	assert(host.configure_primary_gravity(Vector2(512.0, 512.0), 400.0, 0.0, 30, 0x50442026))

	var accepted := host.submit_gravity_source_commands(
		1,
		PackedInt32Array([0]),
		PackedInt32Array([0]),
		PackedInt64Array([41]),
		PackedInt64Array([41]),
		PackedVector2Array([Vector2(100.0, 100.0)]),
		PackedVector2Array([Vector2.ZERO]),
		PackedFloat64Array([100.0]),
		PackedFloat64Array([100.0]),
		PackedInt64Array([2])
	)
	assert(accepted)
	var command_results: Dictionary = host.drain_gravity_source_command_result_batch()
	assert(command_results.version == 1)
	assert(command_results.codes == PackedInt32Array([0]))
	assert(command_results.source_ids == PackedInt64Array([41]))

	host.step_fixed()
	var query := host.sample_gravity_batch(
		1,
		PackedInt64Array([9001, 9002]),
		PackedVector2Array([Vector2(80.0, 100.0), Vector2(512.0, 512.0)])
	)
	assert(query.version == 1)
	assert(query.tick == 1)
	assert(query.accelerations.size() == 2)
	assert(query.accelerations[0].x > 0.0)
	assert(query.dominant_source_ids[0] == 41)
	assert(query.zero_gravity[1] == 1)
	assert(str(host.get_gravity_checksum_hex()).length() == 16)

	host.step_fixed()
	var expired := host.sample_gravity_batch(
		1,
		PackedInt64Array([9003]),
		PackedVector2Array([Vector2(80.0, 100.0)])
	)
	assert(expired.dominant_source_ids[0] == 0)

	host.free()
	print("native_gravity_bridge_smoke: PASS")
	quit(0)
