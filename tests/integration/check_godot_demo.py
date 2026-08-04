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
        "add_uniform_gravity_source",
        "update_gravity_source",
        "remove_gravity_source",
        "get_stats",
    ),
    GAME / "scripts" / "simulation" / "native_material_chunk_view.gd": (
        "configure_world",
        "apply_dirty_chunk_batch",
        "get_material_at_cell",
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
    GAME / "scripts" / "combat" / "combat_metrics.gd": (
        "set_native_shadow_snapshot",
    ),
    GAME / "scripts" / "combat" / "native_ballistics_shadow.gd": (
        "configure",
        "set_mode",
        "get_mode",
        "track_projectile",
        "get_snapshot",
    ),
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

material_source = require_text(GAME / "scripts" / "simulation" / "material_world.gd")
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

bridge_header = require_text(
    ROOT
    / "native"
    / "godot_bridge"
    / "include"
    / "starfall"
    / "godot_bridge"
    / "simulation_host_node.hpp"
)
bridge_source = require_text(
    ROOT / "native" / "godot_bridge" / "src" / "simulation_host_node.cpp"
)
chunk_smoke = require_text(GAME / "tests" / "native_chunk_transport_smoke.gd")
for native_api in (
    "get_material_transport_version",
    "configure_material_world",
    "submit_material_commands",
    "drain_material_command_result_batch",
    "drain_dirty_chunk_batch",
    "get_material_checksum_hex",
):
    if native_api not in bridge_header or native_api not in bridge_source:
        fail(f"native material bridge lacks {native_api}")
    if native_api not in chunk_smoke:
        fail(f"native chunk smoke lacks {native_api} coverage")

shadow_source = require_text(GAME / "scripts" / "combat" / "native_ballistics_shadow.gd")
for native_api in (
    "StarfallSimulationHost",
    "submit_projectile_spawns",
    "submit_collision_world",
    "get_projectile_state_batch",
):
    if native_api not in shadow_source:
        fail(f"production native shadow lacks {native_api} bridge usage")

for mode in ("gdscript_fallback", "native_shadow", "native_authoritative"):
    if mode not in shadow_source:
        fail(f"production native runtime lacks explicit {mode} mode")

main_source = require_text(GAME / "scripts" / "main.gd")
for action in ("move_left", "move_right", "jump", "fire_starseed"):
    if f'{action}={{' not in project:
        fail(f"missing input action {action}")

if "starseed_requested.connect" not in main_source:
    fail("main scene does not connect the starseed request")

combat_source = require_text(GAME / "scripts" / "combat" / "combat_lab.gd")
if "juvenile_requested.connect" not in combat_source:
    fail("combat lab does not connect the juvenile starseed request")

diagnostics_overlay = require_text(
    GAME / "scripts" / "demo" / "gravity_diagnostics_overlay.gd"
)
for function in (
    "set_enabled",
    "set_gravity_snapshot",
    "set_primary_snapshot",
    "set_local_sources",
    "set_dirty_chunks",
    "set_warnings",
):
    if re.search(rf"^func\s+{re.escape(function)}\s*\(", diagnostics_overlay, re.MULTILINE) is None:
        fail(f"gravity_diagnostics_overlay.gd lacks func {function}()")
for relative in (
    "scripts/simulation/native_gravity_runtime.gd",
    "tests/native_gravity_bridge_smoke.gd",
    "tests/gravity_shadow_smoke.gd",
    "tests/gravity_transition_smoke.gd",
    "tests/native_gravity_runtime_smoke.gd",
):
    require_text(GAME / relative)

print(f"demo contract: PASS ({len(set(resource_paths))} scene resources checked)")
