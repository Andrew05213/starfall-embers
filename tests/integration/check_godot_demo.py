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
scene = require_text(GAME / "scenes" / "main.tscn")

if 'run/main_scene="res://scenes/main.tscn"' not in project:
    fail("project.godot does not select the demo scene")

resource_paths = re.findall(r'path="res://([^\"]+)"', scene)
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
}

for path, functions in contracts.items():
    source = require_text(path)
    for function in functions:
        if re.search(rf"^func\s+{re.escape(function)}\s*\(", source, re.MULTILINE) is None:
            fail(f"{path.relative_to(ROOT)} lacks func {function}()")


material_world_path = GAME / "scripts" / "simulation" / "material_world.gd"
material_source = require_text(material_world_path)
material_enum_match = re.search(
    r"enum\s+CellMaterial\s*\{(?P<body>.*?)\}", material_source, re.DOTALL
)
if material_enum_match is None:
    fail("material_world.gd lacks enum CellMaterial")

parsed_materials: list[tuple[str, int]] = []
next_value = 0
for raw_entry in material_enum_match.group("body").split(","):
    entry = raw_entry.split("#", 1)[0].strip()
    if not entry:
        continue
    entry_match = re.fullmatch(r"([A-Z][A-Z0-9_]*)(?:\s*=\s*(\d+))?", entry)
    if entry_match is None:
        fail(f"cannot parse CellMaterial entry: {entry!r}")
    name, explicit_value = entry_match.groups()
    value = int(explicit_value) if explicit_value is not None else next_value
    parsed_materials.append((name, value))
    next_value = value + 1

expected_materials = [
    ("AIR", 0),
    ("ROCK", 1),
    ("SAND", 2),
    ("WATER", 3),
    ("OIL", 4),
    ("FIRE", 5),
    ("SMOKE", 6),
    ("LAVA", 7),
    ("STEAM", 8),
    ("METAL", 9),
]
if parsed_materials != expected_materials:
    fail(
        "CellMaterial transport IDs drifted: "
        f"expected {expected_materials!r}, got {parsed_materials!r}"
    )

main_source = require_text(GAME / "scripts" / "main.gd")
for action in ("move_left", "move_right", "jump", "fire_starseed"):
    if f'{action}={{' not in project:
        fail(f"missing input action {action}")

if "starseed_requested.connect" not in main_source:
    fail("main scene does not connect the starseed request")

print(f"demo contract: PASS ({len(resource_paths)} scene resources checked)")
