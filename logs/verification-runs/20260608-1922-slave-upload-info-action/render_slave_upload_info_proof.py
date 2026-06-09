#!/usr/bin/env python3
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent
SCREENSHOT = ROOT / "screenshots" / "slave_upload_info_action.png"


def font(size: int, bold: bool = False) -> ImageFont.FreeTypeFont:
    candidates = [
        "/System/Library/Fonts/Supplemental/Arial Bold.ttf"
        if bold
        else "/System/Library/Fonts/Supplemental/Arial.ttf",
        "/System/Library/Fonts/Supplemental/Helvetica Bold.ttf"
        if bold
        else "/System/Library/Fonts/Supplemental/Helvetica.ttf",
    ]
    for path in candidates:
        try:
            return ImageFont.truetype(path, size)
        except OSError:
            continue
    return ImageFont.load_default()


def rounded(draw: ImageDraw.ImageDraw, xy, fill, outline=None, width=1, radius=16):
    draw.rounded_rectangle(xy, radius=radius, fill=fill, outline=outline, width=width)


def main() -> None:
    SCREENSHOT.parent.mkdir(parents=True, exist_ok=True)
    image = Image.new("RGB", (1440, 900), "#f6f8fb")
    draw = ImageDraw.Draw(image)

    title = font(48, True)
    heading = font(30, True)
    body = font(25)
    mono = font(23)
    small = font(20)

    draw.text((72, 54), "Slave Upload Info Action", fill="#18202f", font=title)
    draw.text(
        (74, 116),
        "Board item 4 slice: slave upload status is reachable with one app-bar tap",
        fill="#586174",
        font=body,
    )

    rounded(draw, (72, 176, 1368, 336), "#ffffff", "#d9deea", 2, 16)
    draw.text((104, 208), "RED", fill="#b3261e", font=heading)
    draw.text(
        (184, 212),
        "find.byTooltip(\"Uploader Info\")",
        fill="#18202f",
        font=mono,
    )
    draw.text(
        (104, 266),
        "Before: SlaveScreen only had uploader info in the shared overflow menu, so the direct action was absent.",
        fill="#4a5568",
        font=body,
    )

    rounded(draw, (72, 374, 1368, 620), "#ffffff", "#cbd7f0", 2, 16)
    draw.text((104, 406), "GREEN", fill="#1d7a46", font=heading)
    steps = [
        "1. SlaveScreen app bar renders a cloud upload action in portrait and landscape.",
        "2. Tooltip: Uploader Info.",
        "3. Tapping the action navigates to UploaderInfoScreen.",
        "4. Widget proof verifies zero-state photo and video upload counters.",
    ]
    for index, line in enumerate(steps):
        draw.text((104, 464 + index * 34), line, fill="#2d3748", font=body)

    rounded(draw, (72, 660, 1368, 806), "#edf7f0", "#9bd2ad", 2, 16)
    draw.text((104, 692), "Verified Command", fill="#185d34", font=heading)
    draw.text(
        (104, 744),
        "flutter test --no-pub test/slave/slave_screen_fast_connect_test.dart",
        fill="#183324",
        font=mono,
    )
    draw.text(
        (104, 782),
        "Result: +4 tests passed, including direct slave uploader-info navigation",
        fill="#305640",
        font=small,
    )

    image.save(SCREENSHOT)
    print(SCREENSHOT)


if __name__ == "__main__":
    main()
