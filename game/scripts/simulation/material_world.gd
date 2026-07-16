class_name MaterialWorld
extends Node2D

## Small, deterministic falling-material sandbox used by the pre-alpha demo.
## The authoritative cell state is kept in one byte per cell. The low nibble is
## the material id and bit 7 is a transient "already moved this tick" flag.

signal stats_changed(stats: Dictionary)

enum CellMaterial {
	AIR,
	ROCK,
	SAND,
	WATER,
	OIL,
	FIRE,
	SMOKE,
	LAVA,
	STEAM,
	METAL,
}

const GRID_WIDTH := 160
const GRID_HEIGHT := 90
const CELL_SIZE := 4
const CELL_COUNT := GRID_WIDTH * GRID_HEIGHT
const SIMULATION_HZ := 30.0
const FIXED_STEP := 1.0 / SIMULATION_HZ
const MAX_STEPS_PER_FRAME := 3
const BASE_GRAVITY_ACCELERATION := 135.0
const MATERIAL_MASK := 0x0f
const MOVED_MASK := 0x80
const ASTEROID_CENTER := Vector2(79.5, 44.5)

const MATERIAL_NAMES := [
	"air", "rock", "sand", "water", "oil", "fire", "smoke", "lava", "steam", "metal"
]
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

var cells := PackedByteArray()

var _image: Image
var _texture: ImageTexture
var _pixel_bytes := PackedByteArray()
var _accumulator := 0.0
var _tick := 0
var _rng_state := 0x51a7e11
var _render_dirty := true
var _stats_dirty := true
var _cached_stats: Dictionary = {}
var _gravity_sources: Dictionary = {}
var _next_gravity_source_id := 1


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_pixel_bytes.resize(CELL_COUNT * 4)
	_pixel_bytes.fill(0)
	_image = Image.create(GRID_WIDTH, GRID_HEIGHT, false, Image.FORMAT_RGBA8)
	_texture = ImageTexture.create_from_image(_image)
	reset_world()


func _physics_process(delta: float) -> void:
	_update_gravity_source_ttls(delta)
	_accumulator = minf(_accumulator + delta, FIXED_STEP * MAX_STEPS_PER_FRAME)
	while _accumulator >= FIXED_STEP:
		_simulate_tick()
		_accumulator -= FIXED_STEP
	if _render_dirty:
		_upload_texture()
	if _stats_dirty and _tick % 8 == 0:
		stats_changed.emit(get_stats())


func _draw() -> void:
	if _texture != null:
		draw_texture_rect(
			_texture, Rect2(0.0, 0.0, GRID_WIDTH * CELL_SIZE, GRID_HEIGHT * CELL_SIZE), false
		)


func reset_world() -> void:
	cells.resize(CELL_COUNT)
	cells.fill(CellMaterial.AIR)
	_pixel_bytes.resize(CELL_COUNT * 4)
	_pixel_bytes.fill(0)
	_tick = 0
	_accumulator = 0.0
	_rng_state = 0x51a7e11
	_gravity_sources.clear()
	_next_gravity_source_id = 1
	_generate_asteroid()
	_mark_changed()
	if is_node_ready():
		_upload_texture()
		stats_changed.emit(get_stats())


func get_gravity_at(world_pos: Vector2) -> Vector2:
	var local_gravity := _gravity_for_local_position(to_local(world_pos))
	return global_transform.x * local_gravity.x + global_transform.y * local_gravity.y


func is_solid_at(world_pos: Vector2) -> bool:
	var cell := _local_to_cell(to_local(world_pos))
	if not _is_in_bounds(cell.x, cell.y):
		return false
	var material := _material_at(cell.x, cell.y)
	return (
		material == CellMaterial.ROCK
		or material == CellMaterial.SAND
		or material == CellMaterial.METAL
	)


func get_material_at(world_pos: Vector2) -> int:
	var cell := _local_to_cell(to_local(world_pos))
	if not _is_in_bounds(cell.x, cell.y):
		return CellMaterial.AIR
	return _material_at(cell.x, cell.y)


func extract_circle(world_pos: Vector2, radius_cells: int) -> Dictionary:
	var center := _local_to_cell(to_local(world_pos))
	var radius := maxi(radius_cells, 0)
	var radius_squared := radius * radius
	var extracted := {
		"total": 0,
		"rock": 0,
		"sand": 0,
		"metal": 0,
	}
	for y in range(maxi(0, center.y - radius), mini(GRID_HEIGHT, center.y + radius + 1)):
		for x in range(maxi(0, center.x - radius), mini(GRID_WIDTH, center.x + radius + 1)):
			var dx := x - center.x
			var dy := y - center.y
			if dx * dx + dy * dy > radius_squared:
				continue
			var material := _material_at(x, y)
			match material:
				CellMaterial.ROCK:
					extracted["rock"] += 1
				CellMaterial.SAND:
					extracted["sand"] += 1
				CellMaterial.METAL:
					extracted["metal"] += 1
				_:
					continue
			extracted["total"] += 1
			_set_material(x, y, CellMaterial.AIR)
	if int(extracted["total"]) > 0:
		_mark_changed()
	return extracted


func paint_circle(world_pos: Vector2, radius_cells: int, material_id: int) -> void:
	if material_id < CellMaterial.AIR or material_id > CellMaterial.METAL:
		return
	var center := _local_to_cell(to_local(world_pos))
	_fill_circle_cells(center, maxi(radius_cells, 0), material_id)
	_mark_changed()


func add_gravity_source(world_pos: Vector2, strength: float, radius: float, ttl: float) -> int:
	var source_id := _next_gravity_source_id
	_next_gravity_source_id += 1
	_gravity_sources[source_id] = {
		"position": to_local(world_pos),
		"strength": strength,
		"radius": maxf(radius, 1.0),
		"ttl": ttl,
	}
	_stats_dirty = true
	return source_id


func update_gravity_source(source_id: int, world_pos: Vector2) -> void:
	if not _gravity_sources.has(source_id):
		return
	var source: Dictionary = _gravity_sources[source_id]
	source["position"] = to_local(world_pos)
	_gravity_sources[source_id] = source


func remove_gravity_source(source_id: int) -> void:
	if _gravity_sources.erase(source_id):
		_stats_dirty = true


func get_stats() -> Dictionary:
	if not _stats_dirty and not _cached_stats.is_empty():
		return _cached_stats.duplicate(true)
	var counts := {}
	for material_name in MATERIAL_NAMES:
		counts[material_name] = 0
	var active_cells := 0
	for value in cells:
		var material := value & MATERIAL_MASK
		counts[MATERIAL_NAMES[material]] += 1
		if material != CellMaterial.AIR:
			active_cells += 1
	_cached_stats = {
		"tick": _tick,
		"simulation_hz": SIMULATION_HZ,
		"grid_size": Vector2i(GRID_WIDTH, GRID_HEIGHT),
		"cell_size": CELL_SIZE,
		"active_cells": active_cells,
		"gravity_sources": _gravity_sources.size(),
		"materials": counts,
	}
	_stats_dirty = false
	return _cached_stats.duplicate(true)


func _simulate_tick() -> void:
	_tick += 1
	for index in CELL_COUNT:
		cells[index] &= MATERIAL_MASK

	# A coprime stride visits every cell once while avoiding a persistent scan
	# direction. The moved bit prevents a particle from moving twice in one tick.
	var start := _rand_u32() % CELL_COUNT
	var stride := 73 if (_tick & 1) == 0 else 127
	for iteration in CELL_COUNT:
		var index := (start + iteration * stride) % CELL_COUNT
		if (cells[index] & MOVED_MASK) != 0:
			continue
		var material := cells[index] & MATERIAL_MASK
		if (
			material == CellMaterial.AIR
			or material == CellMaterial.ROCK
			or material == CellMaterial.METAL
		):
			continue
		var x := index % GRID_WIDTH
		var y := index / GRID_WIDTH
		_process_cell(x, y, material)

	_mark_changed()


func _process_cell(x: int, y: int, material: int) -> void:
	if _react_at(x, y, material):
		return
	match material:
		CellMaterial.SAND:
			_move_powder(x, y)
		CellMaterial.WATER, CellMaterial.OIL, CellMaterial.LAVA:
			_move_liquid(x, y, material)
		CellMaterial.FIRE, CellMaterial.SMOKE, CellMaterial.STEAM:
			_move_gas(x, y, material)


func _react_at(x: int, y: int, material: int) -> bool:
	match material:
		CellMaterial.OIL:
			if _has_neighbor(x, y, CellMaterial.FIRE) or _has_neighbor(x, y, CellMaterial.LAVA):
				_set_material(x, y, CellMaterial.FIRE, true)
				return true
		CellMaterial.WATER:
			var lava_pos := _find_neighbor(x, y, CellMaterial.LAVA)
			if lava_pos.x >= 0:
				_set_material(lava_pos.x, lava_pos.y, CellMaterial.ROCK, true)
				_set_material(x, y, CellMaterial.STEAM, true)
				return true
			var fire_pos := _find_neighbor(x, y, CellMaterial.FIRE)
			if fire_pos.x >= 0 and _chance(2):
				_set_material(fire_pos.x, fire_pos.y, CellMaterial.SMOKE, true)
				_set_material(x, y, CellMaterial.STEAM, true)
				return true
		CellMaterial.LAVA:
			var water_pos := _find_neighbor(x, y, CellMaterial.WATER)
			if water_pos.x >= 0:
				_set_material(x, y, CellMaterial.ROCK, true)
				_set_material(water_pos.x, water_pos.y, CellMaterial.STEAM, true)
				return true
		CellMaterial.FIRE:
			var oil_pos := _find_neighbor(x, y, CellMaterial.OIL)
			if oil_pos.x >= 0:
				_set_material(oil_pos.x, oil_pos.y, CellMaterial.FIRE, true)
			var water_pos := _find_neighbor(x, y, CellMaterial.WATER)
			if water_pos.x >= 0 and _chance(2):
				_set_material(water_pos.x, water_pos.y, CellMaterial.STEAM, true)
				_set_material(x, y, CellMaterial.SMOKE, true)
				return true
			if _chance(18):
				_set_material(x, y, CellMaterial.SMOKE, true)
				return true
		CellMaterial.SMOKE:
			if _chance(90):
				_set_material(x, y, CellMaterial.AIR, true)
				return true
		CellMaterial.STEAM:
			if _chance(120):
				_set_material(x, y, CellMaterial.WATER, true)
				return true
	return false


func _move_powder(x: int, y: int) -> void:
	var directions := _movement_directions(x, y, false)
	for direction in directions:
		var target_x: int = x + direction.x
		var target_y: int = y + direction.y
		if not _is_in_bounds(target_x, target_y):
			continue
		var target_material := _material_at(target_x, target_y)
		if target_material == CellMaterial.AIR or _is_liquid(target_material):
			_swap_or_move(x, y, target_x, target_y, CellMaterial.SAND)
			return


func _move_liquid(x: int, y: int, material: int) -> void:
	var directions := _movement_directions(x, y, false)
	for direction in directions:
		var target_x: int = x + direction.x
		var target_y: int = y + direction.y
		if not _is_in_bounds(target_x, target_y):
			continue
		var target_material := _material_at(target_x, target_y)
		if target_material == CellMaterial.AIR or _liquid_can_displace(material, target_material):
			_swap_or_move(x, y, target_x, target_y, material)
			return


func _move_gas(x: int, y: int, material: int) -> void:
	var directions := _movement_directions(x, y, true)
	for direction in directions:
		var target_x: int = x + direction.x
		var target_y: int = y + direction.y
		if (
			_is_in_bounds(target_x, target_y)
			and _material_at(target_x, target_y) == CellMaterial.AIR
		):
			_swap_or_move(x, y, target_x, target_y, material)
			return


func _movement_directions(x: int, y: int, opposite_gravity: bool) -> Array[Vector2i]:
	var local_position := Vector2((x + 0.5) * CELL_SIZE, (y + 0.5) * CELL_SIZE)
	var gravity := _gravity_for_local_position(local_position)
	if opposite_gravity:
		gravity = -gravity
	var primary := Vector2i.ZERO
	if absf(gravity.x) > absf(gravity.y):
		primary.x = 1 if gravity.x > 0.0 else -1
	else:
		primary.y = 1 if gravity.y > 0.0 else -1
	if primary == Vector2i.ZERO:
		primary = Vector2i.DOWN
	var side := Vector2i(-primary.y, primary.x)
	if _chance(2):
		side = -side
	return [primary, primary + side, primary - side, side, -side]


func _gravity_for_local_position(local_position: Vector2) -> Vector2:
	var center_pixels := (ASTEROID_CENTER + Vector2(0.5, 0.5)) * CELL_SIZE
	var delta := center_pixels - local_position
	var gravity := (
		delta.normalized() * BASE_GRAVITY_ACCELERATION
		if delta.length_squared() > 0.01
		else Vector2.ZERO
	)
	for source_id in _gravity_sources:
		var source: Dictionary = _gravity_sources[source_id]
		var source_delta: Vector2 = source["position"] - local_position
		var distance := source_delta.length()
		var radius: float = source["radius"]
		if distance > 0.001 and distance < radius:
			var falloff := 1.0 - distance / radius
			gravity += source_delta / distance * float(source["strength"]) * falloff
	return gravity


func _swap_or_move(from_x: int, from_y: int, to_x: int, to_y: int, material: int) -> void:
	var from_index := _index(from_x, from_y)
	var to_index := _index(to_x, to_y)
	var displaced := cells[to_index] & MATERIAL_MASK
	cells[to_index] = material | MOVED_MASK
	cells[from_index] = displaced | MOVED_MASK
	_write_pixel(to_index, material)
	_write_pixel(from_index, displaced)


func _set_material(x: int, y: int, material: int, moved: bool = false) -> void:
	var cell_index := _index(x, y)
	cells[cell_index] = material | (MOVED_MASK if moved else 0)
	_write_pixel(cell_index, material)


func _material_at(x: int, y: int) -> int:
	return cells[_index(x, y)] & MATERIAL_MASK


func _has_neighbor(x: int, y: int, material: int) -> bool:
	return _find_neighbor(x, y, material).x >= 0


func _find_neighbor(x: int, y: int, material: int) -> Vector2i:
	const NEIGHBORS := [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]
	var offset := _rand_u32() & 3
	for index in 4:
		var direction: Vector2i = NEIGHBORS[(index + offset) & 3]
		var target_x := x + direction.x
		var target_y := y + direction.y
		if _is_in_bounds(target_x, target_y) and _material_at(target_x, target_y) == material:
			return Vector2i(target_x, target_y)
	return Vector2i(-1, -1)


func _is_liquid(material: int) -> bool:
	return (
		material == CellMaterial.WATER
		or material == CellMaterial.OIL
		or material == CellMaterial.LAVA
	)


func _liquid_can_displace(material: int, target: int) -> bool:
	if not _is_liquid(target):
		return false
	# Denser liquids sink toward the core through lighter liquids.
	return _liquid_density(material) > _liquid_density(target)


func _liquid_density(material: int) -> int:
	match material:
		CellMaterial.LAVA:
			return 3
		CellMaterial.WATER:
			return 2
		CellMaterial.OIL:
			return 1
	return 0


func _generate_asteroid() -> void:
	var radius := 39.0
	for y in GRID_HEIGHT:
		for x in GRID_WIDTH:
			var delta := Vector2(x, y) - ASTEROID_CENTER
			var angle_wobble := sin(delta.angle() * 7.0) * 1.5 + sin(delta.angle() * 13.0) * 0.8
			if delta.length() <= radius + angle_wobble:
				_set_material(x, y, CellMaterial.ROCK)

	# Connected caverns and pockets; these deliberately expose all demo materials.
	_fill_circle_cells(Vector2i(59, 29), 12, CellMaterial.AIR)
	_fill_circle_cells(Vector2i(78, 28), 10, CellMaterial.AIR)
	_fill_circle_cells(Vector2i(99, 31), 13, CellMaterial.AIR)
	_fill_circle_cells(Vector2i(53, 51), 11, CellMaterial.AIR)
	_fill_circle_cells(Vector2i(76, 51), 14, CellMaterial.AIR)
	_fill_circle_cells(Vector2i(104, 54), 13, CellMaterial.AIR)
	_fill_circle_cells(Vector2i(82, 67), 10, CellMaterial.AIR)
	_carve_tunnel(Vector2i(59, 29), Vector2i(99, 31), 5)
	_carve_tunnel(Vector2i(53, 51), Vector2i(104, 54), 5)
	_carve_tunnel(Vector2i(76, 51), Vector2i(82, 67), 4)

	_fill_circle_cells(Vector2i(61, 24), 6, CellMaterial.SAND)
	_fill_circle_cells(Vector2i(94, 27), 6, CellMaterial.WATER)
	_fill_circle_cells(Vector2i(107, 55), 6, CellMaterial.OIL)
	_fill_circle_cells(Vector2i(82, 69), 5, CellMaterial.LAVA)
	_fill_circle_cells(Vector2i(73, 47), 3, CellMaterial.METAL)
	_fill_circle_cells(Vector2i(87, 47), 3, CellMaterial.METAL)
	_fill_circle_cells(Vector2i(101, 48), 2, CellMaterial.FIRE)


func _fill_circle_cells(center: Vector2i, radius: int, material: int) -> void:
	var radius_squared := radius * radius
	for y in range(maxi(0, center.y - radius), mini(GRID_HEIGHT, center.y + radius + 1)):
		for x in range(maxi(0, center.x - radius), mini(GRID_WIDTH, center.x + radius + 1)):
			var dx := x - center.x
			var dy := y - center.y
			if dx * dx + dy * dy <= radius_squared:
				_set_material(x, y, material)


func _carve_tunnel(from: Vector2i, to: Vector2i, radius: int) -> void:
	var distance := Vector2(from).distance_to(Vector2(to))
	var steps := maxi(1, ceili(distance / 3.0))
	for step in steps + 1:
		var point := Vector2(from).lerp(Vector2(to), float(step) / steps)
		_fill_circle_cells(Vector2i(point.round()), radius, CellMaterial.AIR)


func _upload_texture() -> void:
	if _image == null or _texture == null:
		return
	_image.set_data(GRID_WIDTH, GRID_HEIGHT, false, Image.FORMAT_RGBA8, _pixel_bytes)
	_texture.update(_image)
	_render_dirty = false
	queue_redraw()


func _write_pixel(cell_index: int, material: int) -> void:
	if _pixel_bytes.size() != CELL_COUNT * 4:
		return
	var color: Color = MATERIAL_COLORS[material]
	var x := cell_index % GRID_WIDTH
	var y := cell_index / GRID_WIDTH
	# Stable checker variation keeps the low-resolution surface readable.
	if material != CellMaterial.AIR and ((x * 17 + y * 31) & 7) == 0:
		color = color.lightened(0.10)
	var byte_index := cell_index * 4
	_pixel_bytes[byte_index] = roundi(color.r * 255.0)
	_pixel_bytes[byte_index + 1] = roundi(color.g * 255.0)
	_pixel_bytes[byte_index + 2] = roundi(color.b * 255.0)
	_pixel_bytes[byte_index + 3] = roundi(color.a * 255.0)


func _update_gravity_source_ttls(delta: float) -> void:
	var expired: Array[int] = []
	for source_id in _gravity_sources:
		var source: Dictionary = _gravity_sources[source_id]
		var ttl: float = source["ttl"]
		if ttl <= 0.0:
			continue
		ttl -= delta
		if ttl <= 0.0:
			expired.append(source_id)
		else:
			source["ttl"] = ttl
			_gravity_sources[source_id] = source
	for source_id in expired:
		_gravity_sources.erase(source_id)
	if not expired.is_empty():
		_stats_dirty = true


func _mark_changed() -> void:
	_render_dirty = true
	_stats_dirty = true


func _local_to_cell(local_position: Vector2) -> Vector2i:
	return Vector2i(floori(local_position.x / CELL_SIZE), floori(local_position.y / CELL_SIZE))


func _index(x: int, y: int) -> int:
	return y * GRID_WIDTH + x


func _is_in_bounds(x: int, y: int) -> bool:
	return x >= 0 and x < GRID_WIDTH and y >= 0 and y < GRID_HEIGHT


func _chance(one_in: int) -> bool:
	return (_rand_u32() % maxi(one_in, 1)) == 0


func _rand_u32() -> int:
	_rng_state = (_rng_state * 1664525 + 1013904223) & 0xffffffff
	return _rng_state
