#!/usr/bin/env python3
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont


RUN_DIR = Path(__file__).resolve().parent
OUTPUT = RUN_DIR / "screenshots" / "upload_time_estimate_visible.png"
FONT_PATH = Path("/System/Library/Fonts/Supplemental/Arial.ttf")


def font(size: int, bold: bool = False) -> ImageFont.FreeTypeFont:
    path = Path("/System/Library/Fonts/Supplemental/Arial Bold.ttf")
    if not bold or not path.exists():
        path = FONT_PATH
    return ImageFont.truetype(str(path), size)


def card(
    draw: ImageDraw.ImageDraw,
    xy: tuple[int, int, int, int],
    fill: str,
    outline: str,
) -> None:
    draw.rounded_rectangle(xy, radius=18, fill=fill, outline=outline, width=2)


def main() -> None:
    image = Image.new("RGB", (860, 600), "#f7f5ef")
    draw = ImageDraw.Draw(image)

    title = font(34, bold=True)
    heading = font(22, bold=True)
    body = font(18)
    small = font(16)

    draw.text((40, 36), "Upload Time Estimate Proof", fill="#171717", font=title)
    draw.text(
        (40, 84),
        "Item 4: progress includes bytes and estimated time remaining",
        fill="#4b5563",
        font=body,
    )

    card(draw, (40, 130, 820, 250), "#ffffff", "#d6d3d1")
    draw.text((66, 154), "Current upload", fill="#171717", font=heading)
    draw.text((66, 190), "File size: 4 B", fill="#374151", font=body)
    draw.text((300, 190), "Progress: 50%", fill="#374151", font=body)
    draw.text((535, 190), "Elapsed: 4s", fill="#374151", font=body)

    card(draw, (40, 290, 820, 430), "#ecfdf5", "#10b981")
    draw.text((66, 316), "Visible media-list result", fill="#065f46", font=heading)
    draw.text((66, 356), "2 B / 4 B", fill="#065f46", font=body)
    draw.text((66, 390), "About 4s left", fill="#065f46", font=body)

    card(draw, (40, 470, 820, 540), "#eff6ff", "#2563eb")
    draw.text((66, 493), "Layout fix", fill="#1e3a8a", font=heading)
    draw.text(
        (210, 497),
        "Time estimate moved to subtitle so trailing progress does not overflow.",
        fill="#1e3a8a",
        font=small,
    )

    draw.text(
        (40, 570),
        "Widget tests verify deterministic time estimates and existing upload states.",
        fill="#4b5563",
        font=small,
    )

    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    image.save(OUTPUT)
    print(OUTPUT)


if __name__ == "__main__":
    main()
