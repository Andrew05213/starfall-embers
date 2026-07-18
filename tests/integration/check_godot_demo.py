#!/usr/bin/env python3
"""Dependency-free contract check for the early Godot demo."""

from pathlib import Path
import re
import sys


ROOT = Path(__file__).resolve().parents[2]
GAME = ROOT / "game"


def fail(message: str) -> None:
    print(f"demo contract: FAIL: {message}", file=sys.stderr)
    raise SystemExit(1)


def require_text(path: Path) -> str:
    if not path.is_file():
        fail(f"missing {path.relative_to(ROOT)}")
    text = path.read_text(encoding="utf-8")
    if not text.strip():
        fail(f"empty {path.relative_to(ROOT)}")
    return text


project = require_text(GAME / "project.godot")
demo_scene = require_text(GAME / "scenes" / "main.tscn")
combat_scene = require_text(GAME / "scenes" / "combat_lab.tscn")

if 'run/main_scene="res://scenes/combat_lab.tscn"' not in project:
    fail("project.godot does not select the Gate-1 combat lab")
if "common/physics_interpolation=true" not in project:
    fail("project.godot does not enable render-time physics interpolation")

resource_paths = re.findall(
    r'path="res://([^\"]+)"', demo_scene + "\n" + combat_scene
)
for relative in resource_paths:
    require_text(GAME / relative)

contracts = {
    GAME / "scripts" / "simulation" / "material_world.gd": (
        "reset_world",
        "get_gravity_at",
        "is_solid_at",
        "get_material_at",
        "extract_circle",
        "paint_circle",
        "add_gravity_source",
        "update_gravity_source",
        "remove_gravity_source",
        "get_stats",
    ),
    GAME / "scripts" / "demo" / "player_controller.gd": (
        "reset_player",
        "get_cooldown_ratio",
        "get_state",
        "take_damage",
        "add_matter",
    ),
    GAME / "scripts" / "demo" / "starseed.gd": ("setup",),
    GAME / "scripts" / "demo" / "demo_hud.gd": (
        "set_stats",
        "set_cooldown",
        "set_selected_material",
        "set_selected_seed",
        "set_player_state",
        "set_objective",
        "flash_message",
    ),
    GAME / "scripts" / "demo" / "demo_enemy.gd": (
        "setup",
        "take_damage",
        "receive_starseed_hit",
    ),
    GAME / "scripts" / "demo" / "demo_objective.gd": (
        "arm",
        "accept_starseed",
    ),
    GAME / "scripts" / "combat" / "shot_profile.gd": ("is_valid",),
    GAME / "scripts" / "combat" / "fire_scheduler.gd": (
        "configure",
        "advance",
        "reset",
    ),
    GAME / "scripts" / "combat" / "aim_space.gd": (
        "screen_to_world",
        "direction_from_screen",
    ),
    GAME / "scripts" / "combat" / "juvenile_starseed.gd": (
        "setup",
        "simulate_step",
    ),
    GAME / "scripts" / "combat" / "combat_target.gd": (
        "sweep_hit",
        "receive_juvenile_hit",
    ),
    GAME / "scripts" / "combat" / "ballistic_particle_field.gd": (
        "bind_material_world",
        "emit_trail",
        "emit_impact",
        "simulate_step",
    ),
    GAME / "scripts" / "combat" / "combat_lab.gd": ("get_lab_state",),
}

for path, functions in contracts.items():
    source = require_text(path)
    for function in functions:
        if re.search(
            rf"^(?:static\s+)?func\s+{re.escape(function)}\s*\(",
            source,
            re.MULTILINE,
        ) is None:
            fail(f"{path.relative_to(ROOT)} lacks func {function}()")

main_source = require_text(GAME / "scripts" / "main.gd")
for action in ("move_left", "move_right", "jump", "fire_starseed"):
    if f'{action}={{' not in project:
        fail(f"missing input action {action}")

if "starseed_requested.connect" not in main_source:
    fail("main scene does not connect the starseed request")

combat_source = require_text(GAME / "scripts" / "combat" / "combat_lab.gd")
if "juvenile_requested.connect" not in combat_source:
    fail("combat lab does not connect the juvenile starseed request")

print(f"demo contract: PASS ({len(set(resource_paths))} scene resources checked)")
