class_name CombatLab
extends Node2D

const PROJECTILE_SCRIPT := preload("res://scripts/combat/juvenile_starseed.gd")
const TARGET_SCRIPT := preload("res://scripts/combat/combat_target.gd")

@onready var material_world: Node = $MaterialWorld
@onready var player: CombatLabPlayer = $Player
@onready var feedback: CombatFeedback = $CombatFeedback
@onready var metrics: CombatMetrics = $CombatMetrics


func _ready() -> void:
	feedback.bind_material_world(material_world)
	player.juvenile_requested.connect(_on_juvenile_requested)
	player.trigger_started.connect(metrics.record_trigger)
	player.shot_fired.connect(metrics.record_shot)
	_reset_lab()
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_R:
			_reset_lab()
		elif event.keycode == KEY_ESCAPE:
			get_tree().change_scene_to_file("res://scenes/main.tscn")


func get_lab_state() -> Dictionary:
	var state := metrics.get_snapshot()
	state["targets"] = get_tree().get_nodes_in_group("combat_targets").size()
	state["projectiles"] = get_tree().get_nodes_in_group("juvenile_starseeds").size()
	state["player_aim"] = player.get_aim_direction()
	state["fire_interval"] = player.get_fire_interval()
	return state


func _draw() -> void:
	draw_rect(Rect2(0, 0, 640, 360), Color("050b13"))
	for index in range(80):
		var x := float((index * 97 + 17) % 640)
		var y := float((index * 53 + 7) % 360)
		var alpha := 0.16 + float(index % 4) * 0.07
		draw_circle(Vector2(x, y), 0.55 + float(index % 3) * 0.25, Color(0.65, 0.83, 0.9, alpha))
	# The line is presentation-only; the physical shootable wall is a target.
	draw_arc(Vector2(320, 180), 174.0, -2.32, -0.82, 72, Color(0.22, 0.42, 0.46, 0.35), 0.8)


func _reset_lab() -> void:
	for projectile in get_tree().get_nodes_in_group("juvenile_starseeds"):
		projectile.remove_from_group("juvenile_starseeds")
		projectile.queue_free()
	for target in get_tree().get_nodes_in_group("combat_targets"):
		target.remove_from_group("combat_targets")
		target.queue_free()
	material_world.reset_world()
	player.reset_combat_player(Vector2(320.0, 10.0))
	metrics.reset_metrics()
	_spawn_target("wall", Vector2(213.0, 5.0), "ShootableWall")
	_spawn_target("static", Vector2(267.0, -12.0), "StaticTarget")
	_spawn_target("moving", Vector2(368.0, 5.0), "MovingTarget")
	_spawn_target("enemy", Vector2(417.0, 10.0), "OrdinaryEnemy")


func _spawn_target(kind: String, position: Vector2, node_name: String) -> CombatTarget:
	var target: CombatTarget = TARGET_SCRIPT.new()
	target.name = node_name
	target.z_index = 9
	target.setup(kind, position)
	add_child(target)
	target.hit_received.connect(_on_target_hit)
	target.defeated.connect(_on_target_defeated)
	return target


func _on_juvenile_requested(
	origin: Vector2,
	direction: Vector2,
	inherited_velocity: Vector2,
	profile: CombatShotProfile
) -> void:
	var projectile: JuvenileStarseed = PROJECTILE_SCRIPT.new()
	projectile.z_index = 12
	add_child(projectile)
	projectile.setup(profile, origin, direction, inherited_velocity, material_world)
	projectile.impacted.connect(_on_projectile_impacted)
	projectile.traveled.connect(
		func(from: Vector2, to: Vector2, travel_velocity: Vector2) -> void:
			feedback.projectile_trail(from, to, travel_velocity, profile.color)
	)
	feedback.release(origin, direction, profile.color)


func _on_projectile_impacted(target: Node, point: Vector2, impact_velocity: Vector2) -> void:
	# Target hits produce their richer material/body feedback through the target
	# signal. Terrain still needs a distinct impact flash.
	if not is_instance_valid(target):
		feedback.impact(point, impact_velocity, Color("90a7b7"))


func _on_target_hit(
	_target: Node,
	point: Vector2,
	impact_velocity: Vector2,
	strong: bool
) -> void:
	metrics.record_hit()
	feedback.impact(point, impact_velocity, Color("76f4d6"), strong)


func _on_target_defeated(_target: Node, point: Vector2, impact_velocity: Vector2) -> void:
	metrics.record_death()
	feedback.death(point, impact_velocity, Color("ff806c"))
