class_name NativeMaterialChunkView
extends Node2D

## Presentation-only consumer for material dirty batches. The entire DTO crosses
## GDExtension once; per-cell expansion happens locally in Godot.

const DTO_VERSION := 1
const CHUNK_SIZE := 64
const MATERIAL_COLORS := [
	Color(0.012, 0.016, 0.031, 0.0),
	Color("53505d"),
	Color("d6a64b"),
	Color("3d77d6"),
	Color("765239"),
	Color("ffb23f"),
	Color("777582"),
	Color("f04d2e"),
	Color("b8d8df"),
	Color("91a0ad"),
]

var _width := 0
var _height := 0
var _cell_size := 1
var _cells := PackedByteArray()
var _pixel_bytes := PackedByteArray()
var _image: Image
var _texture: ImageTexture


func configure_world(width: int, height: int, cell_size: int = 1) -> bool:
	if width <= 0 or height <= 0 or cell_size <= 0:
		return false
	_width = width
	_height = height
	_cell_size = cell_size
	_cells.resize(_width * _height)
	_cells.fill(0)
	_pixel_bytes.resize(_width * _height * 4)
	_pixel_bytes.fill(0)
	_image = Image.create_from_data(_width, _height, false, Image.FORMAT_RGBA8, _pixel_bytes)
	_texture = ImageTexture.create_from_image(_image)
	queue_redraw()
	return true


func apply_dirty_chunk_batch(batch: Dictionary) -> bool:
	if not _validate_batch(batch):
		return false

	var chunk_xs: PackedInt32Array = batch["chunk_xs"]
	var chunk_ys: PackedInt32Array = batch["chunk_ys"]
	var widths: PackedInt32Array = batch["widths"]
	var heights: PackedInt32Array = batch["heights"]
	var byte_offsets: PackedInt64Array = batch["byte_offsets"]
	var payload: PackedByteArray = batch["cells"]
	for chunk_index in chunk_xs.size():
		var origin_x := chunk_xs[chunk_index] * CHUNK_SIZE
		var origin_y := chunk_ys[chunk_index] * CHUNK_SIZE
		var valid_width := widths[chunk_index]
		var valid_height := heights[chunk_index]
		var byte_offset: int = byte_offsets[chunk_index]
		for local_y in valid_height:
			for local_x in valid_width:
				var material: int = payload[byte_offset + local_y * valid_width + local_x]
				var world_index := (origin_y + local_y) * _width + origin_x + local_x
				_cells[world_index] = material
				_write_pixel(world_index, material)

	_image.set_data(_width, _height, false, Image.FORMAT_RGBA8, _pixel_bytes)
	_texture.update(_image)
	queue_redraw()
	return true


func get_material_at_cell(x: int, y: int) -> int:
	if x < 0 or x >= _width or y < 0 or y >= _height:
		return -1
	return _cells[y * _width + x]


func _draw() -> void:
	if _texture != null:
		draw_texture_rect(
			_texture,
			Rect2(0.0, 0.0, _width * _cell_size, _height * _cell_size),
			false
		)


func _validate_batch(batch: Dictionary) -> bool:
	if _image == null or _texture == null:
		return false
	for key in [
		"version", "chunk_size", "chunk_xs", "chunk_ys", "widths", "heights",
		"byte_offsets", "cells"
	]:
		if not batch.has(key):
			return false
	if int(batch["version"]) != DTO_VERSION or int(batch["chunk_size"]) != CHUNK_SIZE:
		return false

	var chunk_xs: PackedInt32Array = batch["chunk_xs"]
	var chunk_ys: PackedInt32Array = batch["chunk_ys"]
	var widths: PackedInt32Array = batch["widths"]
	var heights: PackedInt32Array = batch["heights"]
	var byte_offsets: PackedInt64Array = batch["byte_offsets"]
	var payload: PackedByteArray = batch["cells"]
	var count := chunk_xs.size()
	if chunk_ys.size() != count or widths.size() != count or heights.size() != count \
			or byte_offsets.size() != count:
		return false
	for chunk_index in count:
		var origin_x := chunk_xs[chunk_index] * CHUNK_SIZE
		var origin_y := chunk_ys[chunk_index] * CHUNK_SIZE
		var valid_width := widths[chunk_index]
		var valid_height := heights[chunk_index]
		var byte_offset: int = byte_offsets[chunk_index]
		if chunk_xs[chunk_index] < 0 or chunk_ys[chunk_index] < 0 \
				or valid_width <= 0 or valid_width > CHUNK_SIZE \
				or valid_height <= 0 or valid_height > CHUNK_SIZE \
				or origin_x + valid_width > _width or origin_y + valid_height > _height \
				or byte_offset < 0 or byte_offset + valid_width * valid_height > payload.size():
			return false
		for payload_index in range(byte_offset, byte_offset + valid_width * valid_height):
			if payload[payload_index] >= MATERIAL_COLORS.size():
				return false
	return true


func _write_pixel(cell_index: int, material: int) -> void:
	var color: Color = MATERIAL_COLORS[material]
	var byte_index := cell_index * 4
	_pixel_bytes[byte_index] = roundi(color.r * 255.0)
	_pixel_bytes[byte_index + 1] = roundi(color.g * 255.0)
	_pixel_bytes[byte_index + 2] = roundi(color.b * 255.0)
	_pixel_bytes[byte_index + 3] = roundi(color.a * 255.0)
