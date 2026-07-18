class_name CombatFeedback
extends Node2D

## Lightweight code-native audiovisual feedback. Hooks remain available for a
## later authored sound pass; generated tones make the Gate playable now.

signal audio_hook_requested(layer: String, position: Vector2, intensity: float)

const AUDIO_POOL_SIZE := 10
const SAMPLE_RATE := 22050

var _effects: Array[Dictionary] = []
var _audio_streams: Dictionary = {}
var _audio_pool: Array[AudioStreamPlayer2D] = []
var _audio_cursor := 0
var _audio_sequence := 0


func _ready() -> void:
	_audio_streams = {
		"cast": _make_tone(760.0, 0.055, 0.28, 0.38),
		"flight": _make_tone(1180.0, 0.045, 0.16, 0.51),
		"hit": _make_tone(185.0, 0.07, 0.42, 1.55),
		"strong_hit": _make_tone(105.0, 0.11, 0.54, 1.9),
		"death": _make_tone(82.0, 0.19, 0.58, 2.35),
	}
	for _index in range(AUDIO_POOL_SIZE):
		var player := AudioStreamPlayer2D.new()
		player.max_distance = 420.0
		player.attenuation = 0.55
		player.volume_db = -7.0
		add_child(player)
		_audio_pool.append(player)


func _process(delta: float) -> void:
	for index in range(_effects.size() - 1, -1, -1):
		_effects[index]["age"] = float(_effects[index]["age"]) + delta
		if (
			str(_effects[index]["kind"]) == "release"
			and not bool(_effects[index].get("flight_played", false))
			and float(_effects[index]["age"]) >= 0.018
		):
			_effects[index]["flight_played"] = true
			var flight_position := (
				_effects[index]["position"] as Vector2
				+ (_effects[index]["direction"] as Vector2) * 10.0
			)
			audio_hook_requested.emit("flight", flight_position, 0.28)
			_play_audio("flight", flight_position, 0.28)
		if float(_effects[index]["age"]) >= float(_effects[index]["duration"]):
			_effects.remove_at(index)
	queue_redraw()


func release(origin: Vector2, direction: Vector2, color: Color) -> void:
	_effects.append({
		"kind": "release",
		"position": origin,
		"direction": direction.normalized(),
		"color": color,
		"age": 0.0,
		"duration": 0.075,
		"flight_played": false,
	})
	audio_hook_requested.emit("cast", origin, 0.45)
	_play_audio("cast", origin, 0.45)
	queue_redraw()


func impact(point: Vector2, direction: Vector2, color: Color, strong: bool = false) -> void:
	_effects.append({
		"kind": "strong_hit" if strong else "hit",
		"position": point,
		"direction": direction.normalized(),
		"color": color,
		"age": 0.0,
		"duration": 0.16 if strong else 0.11,
	})
	audio_hook_requested.emit("strong_hit" if strong else "hit", point, 1.0 if strong else 0.62)
	_play_audio("strong_hit" if strong else "hit", point, 1.0 if strong else 0.62)
	queue_redraw()


func death(point: Vector2, direction: Vector2, color: Color) -> void:
	_effects.append({
		"kind": "death",
		"position": point,
		"direction": direction.normalized(),
		"color": color,
		"age": 0.0,
		"duration": 0.38,
	})
	audio_hook_requested.emit("death", point, 1.0)
	_play_audio("death", point, 1.0)
	queue_redraw()


func get_active_effect_count() -> int:
	return _effects.size()


func has_audio_layer(layer: String) -> bool:
	return _audio_streams.has(layer) and is_instance_valid(_audio_streams[layer])


func _play_audio(layer: String, world_position: Vector2, intensity: float) -> void:
	if _audio_pool.is_empty() or not _audio_streams.has(layer):
		return
	var player := _audio_pool[_audio_cursor]
	_audio_cursor = (_audio_cursor + 1) % _audio_pool.size()
	_audio_sequence += 1
	player.stop()
	player.global_position = world_position
	player.stream = _audio_streams[layer]
	# The body of each sound is fixed for a stable firing rhythm. Only a tiny,
	# deterministic pitch variation avoids mechanical phase buildup.
	var variation: float = float([-0.012, 0.0, 0.009, 0.015][_audio_sequence % 4])
	player.pitch_scale = 1.0 + variation
	player.volume_db = linear_to_db(clampf(intensity, 0.05, 1.0)) - 5.0
	player.play()


func _make_tone(frequency: float, duration: float, gain: float, harmonic: float) -> AudioStreamWAV:
	var sample_count := maxi(1, roundi(duration * float(SAMPLE_RATE)))
	var bytes := PackedByteArray()
	bytes.resize(sample_count * 2)
	for index in range(sample_count):
		var time := float(index) / float(SAMPLE_RATE)
		var phase := time / maxf(duration, 0.001)
		var attack := minf(1.0, phase * 18.0)
		var envelope := attack * pow(1.0 - phase, 2.2)
		var sweep_frequency := frequency * lerpf(1.12, 0.72, phase)
		var sample := (
			sin(TAU * sweep_frequency * time)
			+ sin(TAU * sweep_frequency * harmonic * time) * 0.28
		) * 0.72
		var value := clampi(roundi(sample * envelope * gain * 32767.0), -32768, 32767)
		bytes.encode_s16(index * 2, value)
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = SAMPLE_RATE
	stream.stereo = false
	stream.data = bytes
	return stream


func _draw() -> void:
	for effect in _effects:
		var duration := float(effect["duration"])
		var ratio := clampf(float(effect["age"]) / maxf(duration, 0.001), 0.0, 1.0)
		var fade := 1.0 - ratio
		var point := to_local(effect["position"] as Vector2)
		var direction := effect["direction"] as Vector2
		var side := Vector2(-direction.y, direction.x)
		var color := Color(effect["color"] as Color, fade)
		match str(effect["kind"]):
			"release":
				draw_circle(point + direction * ratio * 4.0, 3.4 * fade + 0.5, color)
				draw_line(point - side * 2.2, point + direction * 8.0, color, 1.3)
			"strong_hit":
				draw_arc(point, lerpf(3.0, 13.0, ratio), 0.0, TAU, 20, color, 1.5)
				for index in range(8):
					var ray := Vector2.from_angle(float(index) / 8.0 * TAU)
					draw_line(point + ray * 2.0, point + ray * (5.0 + 10.0 * ratio), color, 1.2)
			"death":
				for index in range(12):
					var spread := (float(index) / 11.0 - 0.5) * 2.2
					var shard_direction := direction.rotated(spread)
					var shard := point + shard_direction * lerpf(2.0, 22.0, ratio)
					draw_circle(shard, 1.6 * fade + 0.3, color)
			_:
				draw_circle(point, lerpf(2.0, 7.5, ratio), Color(color, fade * 0.55), false, 1.2)
				for index in range(5):
					var spread := (float(index) - 2.0) * 0.34
					var spark_direction := (-direction).rotated(spread)
					draw_line(point, point + spark_direction * lerpf(2.0, 9.0, ratio), color, 1.0)
