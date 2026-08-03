extends SceneTree


func _init() -> void:
	var frame := GravityFrame.new()
	frame.update_from_sample({
		"tick": 1,
		"acceleration": Vector2(0.0, 100.0),
		"magnitude": 100.0,
	}, Vector2.UP, Vector2.RIGHT, false)
	assert(frame.up == Vector2.UP)
	assert(frame.down == Vector2.DOWN)
	assert(frame.tangent == Vector2.RIGHT)

	frame.update_from_sample({
		"tick": 2,
		"acceleration": Vector2.ZERO,
		"magnitude": 0.0005,
	}, frame.up, frame.tangent, false)
	assert(frame.zero_gravity)
	assert(frame.up == Vector2.UP)

	# Hysteresis keeps a near-zero frame stable until the re-entry threshold.
	frame.update_from_sample({
		"tick": 3,
		"acceleration": Vector2(0.0, 0.0015),
		"magnitude": 0.0015,
	}, frame.up, frame.tangent, true)
	assert(frame.zero_gravity)
	frame.update_from_sample({
		"tick": 4,
		"acceleration": Vector2(0.0, 0.003),
		"magnitude": 0.003,
	}, frame.up, frame.tangent, true)
	assert(not frame.zero_gravity)
	assert(frame.up == Vector2.UP)

	print("gravity transition smoke: PASS")
	quit(0)
