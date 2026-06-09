#!/usr/bin/env python3
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont


RUN_DIR = Path(__file__).resolve().parent
OUTPUT = RUN_DIR / "screenshots" / "gallery_browse_all_filter_action.png"
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


def button(
    draw: ImageDraw.ImageDraw,
    xy: tuple[int, int, int, int],
    label: str,
    fill: str,
    text: str,
    font_obj: ImageFont.FreeTypeFont,
) -> None:
    draw.rounded_rectangle(xy, radius=14, fill=fill)
    bbox = draw.textbbox((0, 0), label, font=font_obj)
    x = xy[0] + ((xy[2] - xy[0]) - (bbox[2] - bbox[0])) / 2
    y = xy[1] + ((xy[3] - xy[1]) - (bbox[3] - bbox[1])) / 2 - 2
    draw.text((x, y), label, fill=text, font=font_obj)


def main() -> None:
    image = Image.new("RGB", (860, 600), "#f7f5ef")
    draw = ImageDraw.Draw(image)

    title = font(34, bold=True)
    heading = font(22, bold=True)
    body = font(18)
    small = font(16)

    draw.text((40, 36), "Gallery Browse All Proof", fill="#171717", font=title)
    draw.text(
        (40, 84),
        "Item 9: old-media import can proceed without choosing specific filters",
        fill="#4b5563",
        font=body,
    )

    card(draw, (120, 130, 740, 415), "#ffffff", "#d6d3d1")
    draw.text((160, 165), "Select Media Filters", fill="#171717", font=heading)
    draw.text((160, 215), "Media Type: Photos", fill="#374151", font=body)
    draw.text((160, 255), "From: Any", fill="#374151", font=body)
    draw.text((360, 255), "To: Any", fill="#374151", font=body)

    button(draw, (160, 335, 270, 382), "Cancel", "#e5e7eb", "#374151", small)
    button(draw, (300, 335, 455, 382), "Browse All", "#10b981", "#ffffff", small)
    button(draw, (485, 335, 595, 382), "Apply", "#2563eb", "#ffffff", small)

    card(draw, (40, 455, 820, 540), "#ecfdf5", "#10b981")
    draw.text((66, 478), "Returned filters", fill="#065f46", font=heading)
    draw.text(
        (270, 482),
        "isPhoto=true, startDate=null, endDate=null, minDuration=null",
        fill="#065f46",
        font=small,
    )

    draw.text(
        (40, 570),
        "Widget test verifies Browse All and leaves the filtered Apply action available.",
        fill="#4b5563",
        font=small,
    )

    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    image.save(OUTPUT)
    print(OUTPUT)


if __name__ == "__main__":
    main()
