class_name CombatShotProfile
extends Resource

## Data-only firing contract. Later star-sequence components can compile into this
## profile without coupling the projectile runtime to the construction UI.

@export var display_name := "高速铁砂幼种"
@export_range(0.05, 1.0, 0.001) var fire_interval := 0.11
@export_range(100.0, 3000.0, 1.0) var projectile_speed := 1200.0
@export_range(0.1, 2.0, 0.01) var projectile_lifetime := 0.55
@export_range(0.25, 8.0, 0.1) var collision_radius := 1.4
@export_range(0.0, 100.0, 0.5) var damage := 7.0
@export_range(0.0, 100.0, 0.5) var hit_impulse := 22.0
@export_range(0.0, 10.0, 0.05) var real_recoil := 0.65
@export_range(0.0, 10.0, 0.05) var presentation_recoil := 2.4
@export_range(0.0, 1.0, 0.001) var inherited_velocity_ratio := 0.12
@export_range(0.0, 6.0, 0.05) var projectile_gravity_scale := 1.0
@export var color := Color("76f4d6")
@export var core_color := Color("effff9")


func is_valid() -> bool:
	return (
		fire_interval > 0.0
		and projectile_speed > 0.0
		and projectile_lifetime > 0.0
		and collision_radius > 0.0
		and damage >= 0.0
		and projectile_gravity_scale >= 0.0
	)
