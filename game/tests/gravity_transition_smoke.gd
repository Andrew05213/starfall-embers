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

	# A fast crossing uses the current and predicted samples from one batch. A
	# direction reversal is a transition even when neither sample is zero-gravity.
	frame.update_from_samples({
		"tick": 5,
		"acceleration": Vector2(0.0, 100.0),
		"magnitude": 100.0,
		"dominant_source_id": 11,
	}, {
		"tick": 5,
		"acceleration": Vector2(0.0, -100.0),
		"magnitude": 100.0,
		"dominant_source_id": 12,
	}, frame.up, frame.tangent, false)
	assert(frame.transitioning)
	assert(frame.dominant_source_id == 11)
	assert(frame.up == Vector2.UP)
	var stable_tangent := frame.tangent
	frame.update_from_samples({
		"tick": 6,
		"acceleration": Vector2(0.0, -100.0),
		"magnitude": 100.0,
		"dominant_source_id": 12,
	}, {
		"tick": 6,
		"acceleration": Vector2(0.0, -100.0),
		"magnitude": 100.0,
		"dominant_source_id": 12,
	}, frame.up, stable_tangent, false)
	assert(frame.up == Vector2.DOWN)
	assert(frame.tangent.dot(stable_tangent) >= 0.0)

	print("gravity transition smoke: PASS")
	quit(0)
