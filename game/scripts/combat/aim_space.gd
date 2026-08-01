class_name CombatAimSpace
extends RefCounted

## Converts viewport coordinates through the active canvas transform. This is
## the same transform Camera2D uses, including rotation and zoom.


static func screen_to_world(canvas_transform: Transform2D, screen_position: Vector2) -> Vector2:
	return canvas_transform.affine_inverse() * screen_position


static func direction_from_screen(
	canvas_transform: Transform2D,
	world_origin: Vector2,
	screen_position: Vector2,
	fallback: Vector2 = Vector2.RIGHT
) -> Vector2:
	var world_point := screen_to_world(canvas_transform, screen_position)
	var direction := world_point - world_origin
	if direction.length_squared() <= 0.000001:
		return fallback.normalized() if fallback.length_squared() > 0.000001 else Vector2.RIGHT
	return direction.normalized()
