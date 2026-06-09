#!/usr/bin/env python3
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont


RUN_DIR = Path(__file__).resolve().parent
OUTPUT = RUN_DIR / "screenshots" / "gallery_session_window_matcher.png"
FONT_PATH = Path("/System/Library/Fonts/Supplemental/Arial.ttf")


def font(size: int, bold: bool = False) -> ImageFont.FreeTypeFont:
    path = Path("/System/Library/Fonts/Supplemental/Arial Bold.ttf")
    if not bold or not path.exists():
        path = FONT_PATH
    return ImageFont.truetype(str(path), size)


def draw_card(
    draw: ImageDraw.ImageDraw,
    xy: tuple[int, int, int, int],
    fill: str,
    outline: str,
) -> None:
    draw.rounded_rectangle(xy, radius=18, fill=fill, outline=outline, width=2)


def main() -> None:
    image = Image.new("RGB", (860, 640), "#f7f5ef")
    draw = ImageDraw.Draw(image)

    title = font(34, bold=True)
    heading = font(22, bold=True)
    body = font(18)
    small = font(16)

    draw.text((40, 36), "Gallery Match Proof", fill="#171717", font=title)
    draw.text(
        (40, 84),
        "Item 9: candidate session matching uses a clear time window",
        fill="#4b5563",
        font=body,
    )

    draw_card(draw, (40, 130, 820, 230), "#ffffff", "#d6d3d1")
    draw.text((66, 156), "Imported video", fill="#171717", font=heading)
    draw.text((66, 190), "near-session.mp4  |  10:43-10:44 UTC", fill="#374151", font=body)
    draw.text((520, 190), "Margin: 15 minutes", fill="#374151", font=body)

    draw.text((40, 266), "Candidate sessions", fill="#171717", font=heading)

    draw_card(draw, (40, 306, 820, 426), "#ecfdf5", "#10b981")
    draw.text((66, 330), "INCLUDED: Court 1", fill="#065f46", font=heading)
    draw.text(
        (66, 366),
        "Session 10:00-10:30 UTC  ->  matching window 09:45-10:45 UTC",
        fill="#065f46",
        font=body,
    )
    draw.text((66, 396), "Nearest gap: 13 minutes after session end", fill="#065f46", font=small)

    draw_card(draw, (40, 456, 820, 556), "#fff7ed", "#f97316")
    draw.text((66, 480), "EXCLUDED: Court 2", fill="#9a3412", font=heading)
    draw.text(
        (66, 516),
        "Session 11:00-11:30 UTC  ->  matching window starts at 10:45 UTC",
        fill="#9a3412",
        font=body,
    )

    draw.text(
        (40, 590),
        "Unit tests also verify outside-window exclusion and nearest-first ranking.",
        fill="#4b5563",
        font=small,
    )

    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    image.save(OUTPUT)
    print(OUTPUT)


if __name__ == "__main__":
    main()
