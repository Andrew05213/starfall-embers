extends SceneTree

const DTO_VERSION := 1
const WIDTH := 70
const HEIGHT := 65


func _init() -> void:
	var host := StarfallSimulationHost.new()
	if not _check(host.get_material_transport_version() == DTO_VERSION, "DTO version mismatch"):
		quit(1)
		return
	if not _check(host.configure_material_world(WIDTH, HEIGHT, 0, DTO_VERSION),
			"native material world configuration failed"):
		quit(1)
		return

	var reference := PowderReferenceModel.new(WIDTH, HEIGHT, host.get_random_seed())
	var command_kinds := PackedInt32Array()
	var center_xs := PackedInt64Array()
	var center_ys := PackedInt64Array()
	var radii := PackedInt64Array()
	var material_ids := PackedInt32Array()
	var points := [
		[1, 1, 2], [2, 1, 2], [3, 1, 1],
		[62, 62, 2], [63, 62, 1], [62, 63, 2],
		[64, 63, 0], [68, 64, 2], [68, 63, 9],
		[10, 60, 2], [10, 61, 1], [9, 61, 1], [11, 61, 1],
	]
	for point in points:
		command_kinds.append(0)
		center_xs.append(point[0])
		center_ys.append(point[1])
		radii.append(0)
		material_ids.append(point[2])
		reference.paint_cell(point[0], point[1], point[2])

	if not _check(host.submit_material_commands(
		DTO_VERSION,
		command_kinds,
		center_xs,
		center_ys,
		radii,
		material_ids
	), "initial powder commands rejected"):
		quit(1)
		return

	var native_cells := PackedByteArray()
	native_cells.resize(WIDTH * HEIGHT)
	native_cells.fill(0)
	for _tick in 32:
		host.step_fixed()
		reference.step()
		var dirty: Dictionary = host.drain_dirty_chunk_batch()
		if not _check(dirty.tick == reference.tick, "tick mismatch at %s" % reference.tick):
			quit(1)
			return
		if not _check(_apply_dirty(native_cells, dirty),
				"dirty DTO invalid at %s" % reference.tick):
			quit(1)
			return
		if not _check(native_cells == reference.cells,
				"cell mismatch at %s" % reference.tick):
			quit(1)
			return
		if not _check(
			host.get_material_checksum_hex() == reference.checksum_hex(),
			"checksum mismatch at %s native=%s reference=%s"
				% [reference.tick, host.get_material_checksum_hex(), reference.checksum_hex()]
		):
			quit(1)
			return

	host.free()
	print("native_powder_reference_smoke: PASS")
	quit(0)


func _check(condition: bool, message: String) -> bool:
	if condition:
		return true
	push_error(message)
	return false


func _apply_dirty(native_cells: PackedByteArray, dirty: Dictionary) -> bool:
	for key in ["chunk_xs", "chunk_ys", "widths", "heights", "byte_offsets", "cells"]:
		if not dirty.has(key):
			return false
	var chunk_xs: PackedInt32Array = dirty["chunk_xs"]
	var chunk_ys: PackedInt32Array = dirty["chunk_ys"]
	var widths: PackedInt32Array = dirty["widths"]
	var heights: PackedInt32Array = dirty["heights"]
	var byte_offsets: PackedInt64Array = dirty["byte_offsets"]
	var payload: PackedByteArray = dirty["cells"]
	for chunk_index in chunk_xs.size():
		var origin_x := chunk_xs[chunk_index] * 64
		var origin_y := chunk_ys[chunk_index] * 64
		var valid_width := widths[chunk_index]
		var valid_height := heights[chunk_index]
		var byte_offset: int = byte_offsets[chunk_index]
		for local_y in valid_height:
			for local_x in valid_width:
				var world_index := (origin_y + local_y) * WIDTH + origin_x + local_x
				native_cells[world_index] = payload[byte_offset + local_y * valid_width + local_x]
	return true
