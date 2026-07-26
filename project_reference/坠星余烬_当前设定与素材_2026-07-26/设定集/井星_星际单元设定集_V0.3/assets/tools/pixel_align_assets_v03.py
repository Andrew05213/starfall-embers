#!/usr/bin/env python3
"""Rebuild the approved Wellstar concept assets as hard-edged pixel art.

The script deliberately keeps the approved logical canvases and silhouettes:
64x64 for characters, creatures and world items; 160x90 for environments.
It removes the generated sheet background, applies a shared limited palette per
asset family, writes binary alpha only, and creates nearest-neighbour previews.
"""

from __future__ import annotations

from pathlib import Path
import subprocess
import sys

import numpy as np
from PIL import Image
from scipy import ndimage


ROOT = Path(__file__).resolve().parents[2]
SPLIT = ROOT / "assets" / "split"

CHARACTER_NAMES = (
    "char_01_砾.png", "char_02_简七.png", "char_03_照临.png",
    "creature_01_上升兽.png", "creature_02_沉浆鳗.png", "creature_03_钉足兽.png",
)
ITEM_NAMES = (
    "item_01_引核星种.png", "item_02_旧固定钉.png", "item_03_五色石.png",
    "item_04_冷石矿簇.png", "item_05_燃海罐.png", "item_06_见证匣.png",
    "item_07_生态密封罐.png", "item_08_方向铃.png",
)
ENVIRONMENT_NAMES = (
    "env_01_星体剖面.png", "env_02_维修层.png", "env_03_生态站.png",
    "env_04_古炼室.png", "env_05_断裂地维柱.png", "env_06_上升兽巢腔.png",
    "env_07_坠核抽取台.png", "env_08_古发射井.png",
)


def robust_background(rgb: np.ndarray, border: int = 7) -> np.ndarray:
    """Fit the smooth generated-card background from border pixels."""
    height, width, _ = rgb.shape
    yy, xx = np.mgrid[:height, :width]
    x = (xx / max(width - 1, 1)) * 2 - 1
    y = (yy / max(height - 1, 1)) * 2 - 1
    features = np.stack((np.ones_like(x), x, y, x * x, y * y, x * y), axis=-1)
    edge = (xx < border) | (xx >= width - border) | (yy < border) | (yy >= height - border)
    design = features[edge]
    samples = rgb[edge].astype(np.float64)
    keep = np.ones(len(samples), dtype=bool)
    coefficients = None
    for _ in range(4):
        coefficients, *_ = np.linalg.lstsq(design[keep], samples[keep], rcond=None)
        predicted = design @ coefficients
        residual = np.sqrt(np.sum((samples - predicted) ** 2, axis=1))
        cutoff = max(5.0, float(np.percentile(residual[keep], 88)))
        keep = residual <= cutoff
    assert coefficients is not None
    return np.clip(features @ coefficients, 0, 255)


def connected_from_seeds(candidate: np.ndarray, seeds: np.ndarray) -> np.ndarray:
    """Binary reconstruction: retain candidate pixels connected to strong seeds."""
    labels, count = ndimage.label(candidate, structure=np.ones((3, 3), dtype=np.uint8))
    if count == 0:
        return np.zeros_like(candidate)
    selected = np.unique(labels[seeds])
    selected = selected[selected != 0]
    return np.isin(labels, selected)


def object_mask(rgb: np.ndarray) -> np.ndarray:
    """Remove the dark generated card while preserving one-pixel outlines."""
    background = robust_background(rgb)
    delta = rgb.astype(np.float64) - background
    distance = np.sqrt(np.sum(delta * delta, axis=2))
    light_delta = rgb.max(axis=2).astype(np.float64) - background.max(axis=2)

    seeds = (distance >= 17.0) | (light_delta >= 11.0)
    candidate = (distance >= 7.0) | (np.abs(light_delta) >= 5.0)
    mask = connected_from_seeds(candidate, seeds)

    # Pull in dark outline pixels immediately adjacent to the detected sprite.
    for threshold in (4.2, 3.2):
        fringe = ndimage.binary_dilation(mask, structure=np.ones((3, 3))) & (distance >= threshold)
        mask |= fringe

    # Remove isolated generator noise while preserving tiny approved items.
    labels, count = ndimage.label(mask, structure=np.ones((3, 3), dtype=np.uint8))
    if count:
        sizes = np.bincount(labels.ravel())
        height, width = mask.shape
        cy, cx = height / 2, width / 2
        keep = np.zeros(count + 1, dtype=bool)
        for label in range(1, count + 1):
            ys, xs = np.nonzero(labels == label)
            if not len(xs):
                continue
            near_center = abs(float(xs.mean()) - cx) <= width * 0.43 and abs(float(ys.mean()) - cy) <= height * 0.43
            keep[label] = sizes[label] >= 2 and near_center
        mask = keep[labels]
    return mask


def environment_mask(rgb: np.ndarray) -> np.ndarray:
    """Make only the border-connected void transparent in full scene concepts."""
    maximum = rgb.max(axis=2)
    minimum = rgb.min(axis=2)
    # Very dark, nearly neutral pixels are empty space/card background. Restrict
    # removal to regions connected to the canvas edge so internal black outlines
    # and enclosed cavities survive.
    empty_candidate = (maximum <= 19) & ((maximum - minimum) <= 10)
    edge_seed = np.zeros_like(empty_candidate)
    edge_seed[0, :] = empty_candidate[0, :]
    edge_seed[-1, :] = empty_candidate[-1, :]
    edge_seed[:, 0] = empty_candidate[:, 0]
    edge_seed[:, -1] = empty_candidate[:, -1]
    empty = connected_from_seeds(empty_candidate, edge_seed)
    return ~empty


def build_palette(images: list[np.ndarray], masks: list[np.ndarray], colors: int) -> np.ndarray:
    pixels = np.concatenate([image[mask] for image, mask in zip(images, masks)], axis=0)
    # PIL median-cut supplies a deterministic shared family palette. A 1-column
    # strip avoids introducing any spatial/dither behaviour.
    strip = Image.fromarray(pixels.reshape((-1, 1, 3)).astype(np.uint8), "RGB")
    quantized = strip.quantize(colors=colors, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE)
    counts = quantized.getcolors(maxcolors=len(pixels)) or []
    palette_data = np.asarray(quantized.getpalette(), dtype=np.uint8).reshape((-1, 3))
    indices = [index for _count, index in sorted(counts, reverse=True)]
    return palette_data[indices]


def map_palette(rgb: np.ndarray, mask: np.ndarray, palette: np.ndarray) -> Image.Image:
    output = np.zeros((*mask.shape, 4), dtype=np.uint8)
    pixels = rgb[mask].astype(np.int16)
    # Weighted squared RGB distance approximates luminance sensitivity while
    # remaining deterministic and dependency-light.
    difference = pixels[:, None, :] - palette[None, :, :].astype(np.int16)
    weights = np.asarray((2, 4, 1), dtype=np.int32)
    distance = np.sum(difference.astype(np.int32) ** 2 * weights, axis=2)
    output[mask, :3] = palette[np.argmin(distance, axis=1)]
    output[mask, 3] = 255
    return Image.fromarray(output, "RGBA")


def process_family(names: tuple[str, ...], colors: int, environment: bool = False) -> list[Image.Image]:
    arrays = [np.asarray(Image.open(SPLIT / name).convert("RGB"), dtype=np.uint8) for name in names]
    masks = [environment_mask(image) if environment else object_mask(image) for image in arrays]
    palette = build_palette(arrays, masks, colors)
    outputs = [map_palette(image, mask, palette) for image, mask in zip(arrays, masks)]
    for name, output in zip(names, outputs):
        output.save(SPLIT / name, optimize=True)
    return outputs


def compose_sheet(
    images: list[Image.Image], columns: int, rows: int, tile: tuple[int, int],
    native_name: str, master_name: str, preview_scale: int,
) -> None:
    gap = 4
    margin = 4
    tile_width, tile_height = tile
    width = margin * 2 + columns * tile_width + (columns - 1) * gap
    height = margin * 2 + rows * tile_height + (rows - 1) * gap
    sheet = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    for index, image in enumerate(images):
        column = index % columns
        row = index // columns
        sheet.alpha_composite(image, (margin + column * (tile_width + gap), margin + row * (tile_height + gap)))
    sheet.save(ROOT / "assets" / "native" / native_name, optimize=True)
    preview = sheet.resize((width * preview_scale, height * preview_scale), Image.Resampling.NEAREST)
    preview.save(ROOT / "assets" / "master" / master_name, optimize=True)


def validate() -> None:
    expected = {
        **{name: (64, 64) for name in CHARACTER_NAMES + ITEM_NAMES},
        **{name: (160, 90) for name in ENVIRONMENT_NAMES},
    }
    for name, size in expected.items():
        image = Image.open(SPLIT / name).convert("RGBA")
        alpha = np.asarray(image)[:, :, 3]
        values = set(np.unique(alpha).tolist())
        if image.size != size:
            raise RuntimeError(f"{name}: expected {size}, got {image.size}")
        if not values <= {0, 255} or 0 not in values:
            raise RuntimeError(f"{name}: alpha must be binary and include transparency; got {values}")
        opaque = int(np.count_nonzero(alpha == 255))
        if opaque == 0:
            raise RuntimeError(f"{name}: empty output")
        print(f"{name}: {image.width}x{image.height}; opaque={opaque}; alpha={sorted(values)}")


def main() -> None:
    # Always rebuild the V0.2 logical tiles from the preserved source sheets
    # first. This keeps the V0.3 pipeline deterministic and safe to rerun.
    subprocess.run(
        [sys.executable, str(ROOT / "assets" / "tools" / "extract_assets_v02.py")],
        cwd=ROOT,
        check=True,
    )
    characters = process_family(CHARACTER_NAMES, colors=16)
    items = process_family(ITEM_NAMES, colors=16)
    environments = process_family(ENVIRONMENT_NAMES, colors=48, environment=True)
    compose_sheet(characters, 3, 2, (64, 64), "井星_NPC生物_20px比例母版.png", "井星_NPC生物母版.png", 6)
    compose_sheet(items, 4, 2, (64, 64), "井星_物品材料_世界比例母版.png", "井星_物品材料母版.png", 5)
    compose_sheet(environments, 2, 4, (160, 90), "井星_环境建筑_原生160x90母版.png", "井星_环境建筑母版.png", 4)
    validate()


if __name__ == "__main__":
    main()
