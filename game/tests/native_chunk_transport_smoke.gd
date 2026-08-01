extends SceneTree


const DTO_VERSION := 1


func _init() -> void:
	var host := StarfallSimulationHost.new()
	assert(host.get_material_transport_version() == DTO_VERSION)
	assert(not host.configure_material_world(70, 65, 0, DTO_VERSION + 1))
	assert(host.configure_material_world(70, 65, 0, DTO_VERSION))

	assert(not host.submit_material_commands(
		DTO_VERSION + 1,
		PackedInt32Array([0]),
		PackedInt64Array([1]),
		PackedInt64Array([1]),
		PackedInt64Array([0]),
		PackedInt32Array([1])
	))
	assert(host.submit_material_commands(
		DTO_VERSION,
		PackedInt32Array([0, 0, 0, 1]),
		PackedInt64Array([1, 68, 69, 1]),
		PackedInt64Array([1, 2, 64, 1]),
		PackedInt64Array([0, 0, 0, 0]),
		PackedInt32Array([1, 2, 9, 0])
	))

	host.step_fixed()
	assert(host.get_tick() == 1)

	var results: Dictionary = host.drain_material_command_result_batch()
	assert(results.version == DTO_VERSION)
	assert(results.tick == 1)
	assert(results.command_kinds == PackedInt32Array([0, 0, 0, 1]))
	assert(results.totals == PackedInt64Array([0, 0, 0, 1]))
	assert(results.rock == PackedInt64Array([0, 0, 0, 1]))
	assert(host.drain_material_command_result_batch().command_kinds.is_empty())

	var dirty: Dictionary = host.drain_dirty_chunk_batch()
	assert(dirty.version == DTO_VERSION)
	assert(dirty.tick == 1)
	assert(dirty.chunk_size == 64)
	assert(dirty.chunk_xs == PackedInt32Array([0, 1, 1]))
	assert(dirty.chunk_ys == PackedInt32Array([0, 0, 1]))
	assert(dirty.widths == PackedInt32Array([64, 6, 6]))
	assert(dirty.heights == PackedInt32Array([64, 64, 1]))
	assert(dirty.byte_offsets == PackedInt64Array([0, 4096, 4480]))
	assert(dirty.cells.size() == 4486)
	assert(dirty.cells[4485] == 9)
	assert(host.drain_dirty_chunk_batch().cells.is_empty())
	var view := NativeMaterialChunkView.new()
	assert(view.configure_world(70, 65))
	assert(view.apply_dirty_chunk_batch(dirty))
	assert(view.get_material_at_cell(1, 1) == 0)
	assert(view.get_material_at_cell(68, 2) == 2)
	assert(view.get_material_at_cell(69, 64) == 9)
	var wrong_version_dirty := dirty.duplicate(true)
	wrong_version_dirty["version"] = DTO_VERSION + 1
	assert(not view.apply_dirty_chunk_batch(wrong_version_dirty))

	var checksum := host.get_material_checksum_hex()
	assert(checksum.length() == 16)
	assert(checksum.is_valid_hex_number(false))

	view.free()
	host.free()
	print("native_chunk_transport_smoke: PASS")
	quit(0)
