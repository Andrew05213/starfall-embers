#!/usr/bin/env python3
"""Extract approved V0.2 Wellstar pixel assets from multi-asset sheets."""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path

import numpy as np
from PIL import Image


ROOT = Path(__file__).resolve().parents[2]


@dataclass(frozen=True)
class Sheet:
    source: str
    master: str
    native: str
    columns: int
    rows: int
    tile: tuple[int, int]
    preview_scale: int
    outputs: tuple[str, ...]


SHEETS = (
    Sheet(
        source="井星_环境建筑_160x90生成稿.png",
        master="井星_环境建筑母版.png",
        native="井星_环境建筑_原生160x90母版.png",
        columns=2,
        rows=4,
        tile=(160, 90),
        preview_scale=4,
        outputs=(
            "env_01_星体剖面.png", "env_02_维修层.png",
            "env_03_生态站.png", "env_04_古炼室.png",
            "env_05_断裂地维柱.png", "env_06_上升兽巢腔.png",
            "env_07_坠核抽取台.png", "env_08_古发射井.png",
        ),
    ),
    Sheet(
        source="井星_NPC生物_20px比例稿.png",
        master="井星_NPC生物母版.png",
        native="井星_NPC生物_20px比例母版.png",
        columns=3,
        rows=2,
        tile=(64, 64),
        preview_scale=6,
        outputs=(
            "char_01_砾.png", "char_02_简七.png", "char_03_照临.png",
            "creature_01_上升兽.png", "creature_02_沉浆鳗.png", "creature_03_钉足兽.png",
        ),
    ),
    Sheet(
        source="井星_物品材料_世界比例无标尺稿.png",
        master="井星_物品材料母版.png",
        native="井星_物品材料_世界比例母版.png",
        columns=4,
        rows=2,
        tile=(64, 64),
        preview_scale=5,
        outputs=(
            "item_01_引核星种.png", "item_02_旧固定钉.png",
            "item_03_五色石.png", "item_04_冷石矿簇.png",
            "item_05_燃海罐.png", "item_06_见证匣.png",
            "item_07_生态密封罐.png", "item_08_方向铃.png",
        ),
    ),
)


def contiguous(mask: np.ndarray) -> list[tuple[int, int]]:
    padded = np.pad(mask.astype(np.int8), (1, 1))
    change = np.diff(padded)
    return [(int(a), int(b)) for a, b in zip(np.flatnonzero(change == 1), np.flatnonzero(change == -1))]


def intervals(image: Image.Image, projection_axis: int, expected: int) -> list[tuple[int, int]]:
    rgb = np.asarray(image.convert("RGB"), dtype=np.uint8)
    non_black = rgb.max(axis=2) > 9
    score = non_black.mean(axis=projection_axis)
    found = contiguous(score > 0.08)
    length = image.width if projection_axis == 0 else image.height
    found = [(a, b) for a, b in found if b - a > length / (expected * 5)]
    if len(found) != expected:
        raise RuntimeError(f"Expected {expected} intervals, found {found}")
    return found


def extract(spec: Sheet) -> None:
    source = Image.open(ROOT / "assets" / "source" / spec.source).convert("RGB")
    ys = intervals(source, projection_axis=1, expected=spec.rows)

    tiles: list[Image.Image] = []
    row_xs: list[list[tuple[int, int]]] = []
    for top, bottom in ys:
        row_image = source.crop((0, top, source.width, bottom))
        xs = intervals(row_image, projection_axis=0, expected=spec.columns)
        row_xs.append(xs)
        for left, right in xs:
            tile = source.crop((left, top, right, bottom)).resize(spec.tile, Image.Resampling.NEAREST)
            tiles.append(tile)

    if len(tiles) != len(spec.outputs):
        raise RuntimeError(f"{spec.source}: panel count mismatch")

    for tile, name in zip(tiles, spec.outputs):
        tile.save(ROOT / "assets" / "split" / name, optimize=True)

    gap = 4
    margin = 4
    tile_w, tile_h = spec.tile
    width = margin * 2 + spec.columns * tile_w + (spec.columns - 1) * gap
    height = margin * 2 + spec.rows * tile_h + (spec.rows - 1) * gap
    native = Image.new("RGB", (width, height), (2, 3, 3))
    for index, tile in enumerate(tiles):
        column = index % spec.columns
        row = index // spec.columns
        native.paste(tile, (margin + column * (tile_w + gap), margin + row * (tile_h + gap)))

    native.save(ROOT / "assets" / "native" / spec.native, optimize=True)
    preview = native.resize(
        (native.width * spec.preview_scale, native.height * spec.preview_scale),
        Image.Resampling.NEAREST,
    )
    preview.save(ROOT / "assets" / "master" / spec.master, optimize=True)
    print(f"{spec.master}: source={source.size}; x_by_row={row_xs}; y={ys}; tile={spec.tile}")


def main() -> None:
    for sheet in SHEETS:
        extract(sheet)


if __name__ == "__main__":
    main()
