extends Node2D

const STARSEED_SCRIPT := preload("res://scripts/demo/starseed.gd")

const MATERIAL_ROCK := 1
const MATERIAL_SAND := 2
const MATERIAL_WATER := 3
const MATERIAL_OIL := 4
const MATERIAL_LAVA := 7
const MATERIAL_METAL := 9

const TOOL_ORDER: Array[int] = [
	MATERIAL_SAND,
	MATERIAL_WATER,
	MATERIAL_OIL,
	MATERIAL_LAVA,
	MATERIAL_ROCK,
	MATERIAL_METAL,
]

const TOOL_DATA := {
	MATERIAL_ROCK: {"name": "岩石", "color": Color("4c5264")},
	MATERIAL_SAND: {"name": "砂", "color": Color("d7ae62")},
	MATERIAL_WATER: {"name": "水", "color": Color("3f82d8")},
	MATERIAL_OIL: {"name": "油", "color": Color("55425f")},
	MATERIAL_LAVA: {"name": "熔质", "color": Color("ef5a32")},
	MATERIAL_METAL: {"name": "金属", "color": Color("8d98a8")},
}

@onready var material_world = $MaterialWorld
@onready var player = $Player
@onready var hud = $HUD

var selected_tool_index := 0
var stats_accumulator := 0.0


func _ready() -> void:
	player.starseed_requested.connect(_on_starseed_requested)
	material_world.stats_changed.connect(_on_simulation_stats_changed)
	_select_tool(0)
	_reset_demo()
	queue_redraw()
	hud.flash_message("观察坠律，铸造第一枚星种。", Color("f0bc67"))


func _process(delta: float) -> void:
	stats_accumulator += delta
	if stats_accumulator >= 0.2:
		stats_accumulator = 0.0
		_refresh_hud(material_world.get_stats())

	if player.has_method("get_cooldown_ratio"):
		hud.set_cooldown(player.get_cooldown_ratio())

	if Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		var mouse_position := get_viewport().get_mouse_position()
		if Rect2(Vector2.ZERO, Vector2(640.0, 360.0)).has_point(mouse_position):
			material_world.paint_circle(mouse_position, 2, TOOL_ORDER[selected_tool_index])


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_1:
				_select_tool(0)
			KEY_2:
				_select_tool(1)
			KEY_3:
				_select_tool(2)
			KEY_4:
				_select_tool(3)
			KEY_5:
				_select_tool(4)
			KEY_6:
				_select_tool(5)
			KEY_R:
				_reset_demo()
			KEY_BRACKETLEFT:
				_select_tool(selected_tool_index - 1)
			KEY_BRACKETRIGHT:
				_select_tool(selected_tool_index + 1)

	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_select_tool(selected_tool_index - 1)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_select_tool(selected_tool_index + 1)


func _draw() -> void:
	draw_rect(Rect2(0.0, 0.0, 640.0, 360.0), Color("070b14"))
	for index in range(72):
		var x := float((index * 83 + 29) % 640)
		var y := float((index * 47 + 11) % 360)
		var brightness := 0.25 + float(index % 5) * 0.08
		draw_circle(
			Vector2(x, y),
			0.6 + float(index % 3) * 0.25,
			Color(brightness, brightness, brightness * 1.15, 0.8)
		)


func _on_starseed_requested(origin: Vector2, launch_velocity: Vector2) -> void:
	var starseed := STARSEED_SCRIPT.new()
	add_child(starseed)
	starseed.add_to_group("starseeds")
	starseed.setup(material_world, origin, launch_velocity)
	hud.flash_message("星种已释放：周围律尘开始改轨。", Color("8ed5ff"))
	_refresh_hud(material_world.get_stats())


func _on_simulation_stats_changed(stats: Dictionary) -> void:
	_refresh_hud(stats)


func _refresh_hud(stats: Dictionary) -> void:
	var display_stats := stats.duplicate()
	if display_stats.has("active_cells"):
		display_stats["active_pixels"] = display_stats["active_cells"]
	display_stats["starseeds"] = get_tree().get_nodes_in_group("starseeds").size()
	hud.set_stats(display_stats)


func _select_tool(index: int) -> void:
	selected_tool_index = posmod(index, TOOL_ORDER.size())
	var material_id := TOOL_ORDER[selected_tool_index]
	var data: Dictionary = TOOL_DATA[material_id]
	hud.set_selected_material(material_id, str(data["name"]), data["color"] as Color)


func _reset_demo() -> void:
	for starseed in get_tree().get_nodes_in_group("starseeds"):
		starseed.queue_free()
	material_world.reset_world()
	if player.has_method("reset_player"):
		player.reset_player(Vector2(320.0, 10.0))
	else:
		player.position = Vector2(320.0, 10.0)
	hud.flash_message("世界已重置。", Color("f0bc67"))
	_refresh_hud(material_world.get_stats())
