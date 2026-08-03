class_name PowderReferenceModel
extends RefCounted

## Independent GDScript oracle for the first native powder authority gate.
## This model intentionally has no Godot scene or native bridge dependency.

const AIR := 0
const ROCK := 1
const SAND := 2
const MASK32 := 0xffffffff
const LCG_MULTIPLIER := 1664525
const LCG_INCREMENT := 1013904223
const FNV_OFFSET_LO := 0x84222325
const FNV_OFFSET_HI := 0xcbf29ce4
const FNV_PRIME_LO := 0x1b3

var width: int
var height: int
var seed: int
var tick := 0
var random_state: int
var cells := PackedByteArray()
var _hash_lo := 0
var _hash_hi := 0


func _init(world_width: int, world_height: int, world_seed: int) -> void:
	width = world_width
	height = world_height
	seed = world_seed
	random_state = world_seed
	cells.resize(width * height)
	cells.fill(AIR)


func paint_cell(x: int, y: int, material: int) -> void:
	if x < 0 or x >= width or y < 0 or y >= height:
		return
	cells[y * width + x] = material


func step() -> void:
	tick += 1
	var moved := PackedByteArray()
	moved.resize(cells.size())
	moved.fill(0)
	var start := _next_random() % cells.size()
	for offset in cells.size():
		var index := (start + offset) % cells.size()
		if moved[index] != 0 or cells[index] != SAND:
			continue
		var preferred_side := 1 if (_next_random() & 1) == 0 else -1
		var x := index % width
		var y := index / width
		var candidates := [
			Vector2i(0, 1),
			Vector2i(preferred_side, 1),
			Vector2i(-preferred_side, 1),
			Vector2i(preferred_side, 0),
			Vector2i(-preferred_side, 0),
		]
		for candidate_value in candidates:
			var candidate: Vector2i = candidate_value
			var target_x: int = x + candidate.x
			var target_y: int = y + candidate.y
			if target_x < 0 or target_x >= width or target_y < 0 or target_y >= height:
				continue
			var target_index: int = target_y * width + target_x
			if cells[target_index] != AIR:
				continue
			cells[index] = AIR
			cells[target_index] = SAND
			moved[index] = 1
			moved[target_index] = 1
			break


func checksum_hex() -> String:
	_hash_lo = FNV_OFFSET_LO
	_hash_hi = FNV_OFFSET_HI
	_hash_u32(1)
	_hash_u32(30)
	_hash_u32(width)
	_hash_u32(height)
	_hash_u32(64)
	_hash_u64(seed)
	_hash_byte(AIR)
	_hash_u64(tick)
	_hash_u64(random_state)
	for value in cells:
		_hash_byte(value)
	return "%08x%08x" % [_hash_hi, _hash_lo]


func _next_random() -> int:
	random_state = (random_state * LCG_MULTIPLIER + LCG_INCREMENT) & MASK32
	return random_state


func _hash_byte(value: int) -> void:
	var x := (_hash_lo ^ value) & MASK32
	var product := x * FNV_PRIME_LO
	var carry := product >> 32
	_hash_lo = product & MASK32
	# FNV-1a's 64-bit prime is 0x100000001b3: the high half receives
	# x_lo << 8 in addition to the 0x1b3 product and carry.
	_hash_hi = (_hash_hi * FNV_PRIME_LO + ((x << 8) & MASK32) + carry) & MASK32


func _hash_u32(value: int) -> void:
	for byte_index in 4:
		_hash_byte((value >> (byte_index * 8)) & 0xff)


func _hash_u64(value: int) -> void:
	_hash_u32(value & MASK32)
	_hash_u32((value >> 32) & MASK32)
