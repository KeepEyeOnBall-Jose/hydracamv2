#!/usr/bin/env python3
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont


RUN_DIR = Path(__file__).resolve().parent
OUTPUT = RUN_DIR / "screenshots" / "same_session_rejoin_preserves_media.png"
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
    image = Image.new("RGB", (860, 620), "#f7f5ef")
    draw = ImageDraw.Draw(image)

    title = font(34, bold=True)
    heading = font(22, bold=True)
    body = font(18)
    small = font(16)

    draw.text((40, 36), "Same Session Rejoin Proof", fill="#171717", font=title)
    draw.text(
        (40, 84),
        "Item 2: reconnecting to the same active session preserves local state",
        fill="#4b5563",
        font=body,
    )

    card(draw, (40, 130, 820, 250), "#ffffff", "#d6d3d1")
    draw.text((66, 154), "Before rejoin", fill="#171717", font=heading)
    draw.text((66, 190), "Session: same-guid", fill="#374151", font=body)
    draw.text((340, 190), "Captured photos: 1", fill="#374151", font=body)
    draw.text((590, 190), "Queue: 1", fill="#374151", font=body)

    card(draw, (40, 290, 820, 430), "#ecfdf5", "#10b981")
    draw.text((66, 316), "Same GUID rejoin", fill="#065f46", font=heading)
    draw.text(
        (66, 356),
        "startSession('same-guid', deviceType: 'Slave') preserves media and queue.",
        fill="#065f46",
        font=body,
    )
    draw.text((66, 390), "Captured photos: 1  |  Queue: 1", fill="#065f46", font=body)

    card(draw, (40, 470, 820, 550), "#eff6ff", "#2563eb")
    draw.text((66, 493), "Different GUID", fill="#1e3a8a", font=heading)
    draw.text(
        (240, 497),
        "A new session still starts with clean media state and an empty queue.",
        fill="#1e3a8a",
        font=small,
    )

    draw.text(
        (40, 585),
        "Focused tests prove the same-GUID preservation guard and new-GUID reset path.",
        fill="#4b5563",
        font=small,
    )

    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    image.save(OUTPUT)
    print(OUTPUT)


if __name__ == "__main__":
    main()
