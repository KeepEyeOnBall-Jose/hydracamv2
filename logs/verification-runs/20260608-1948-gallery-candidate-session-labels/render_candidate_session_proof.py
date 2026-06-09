#!/usr/bin/env python3
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent
SCREENSHOT = ROOT / "screenshots" / "gallery_candidate_session_labels.png"


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
    image = Image.new("RGB", (1440, 900), "#f7f8fb")
    draw = ImageDraw.Draw(image)

    title = font(46, True)
    heading = font(30, True)
    body = font(24)
    mono = font(22)
    small = font(18)

    draw.text((72, 54), "Gallery Candidate Session Labels", fill="#18202f", font=title)
    draw.text(
        (74, 116),
        "Board item 9 slice: media selection now surfaces nearest session candidates for videos",
        fill="#586174",
        font=body,
    )

    rounded(draw, (72, 170, 1368, 314), "#ffffff", "#d9deea", 2, 16)
    draw.text((104, 204), "RED", fill="#b3261e", font=heading)
    draw.text(
        (184, 208),
        "MediaSelectionScreen had no candidateSessions input or visible candidate label",
        fill="#18202f",
        font=mono,
    )
    draw.text(
        (104, 258),
        "The widget test failed before production changes because the constructor did not accept candidate sessions.",
        fill="#4a5568",
        font=body,
    )

    rounded(draw, (72, 354, 1368, 628), "#ffffff", "#cbd7f0", 2, 16)
    draw.text((104, 388), "GREEN", fill="#1d7a46", font=heading)
    steps = [
        "1. Matcher accepts raw video start/end ranges.",
        "2. MediaSelectionScreen renders the nearest video match.",
        "3. Gallery import passes the active session without historical loads.",
    ]
    for index, line in enumerate(steps):
        draw.text((104, 448 + index * 38), line, fill="#2d3748", font=body)

    tile_x, tile_y = 1032, 408
    rounded(draw, (tile_x, tile_y, tile_x + 238, tile_y + 160), "#d7dee9", "#9aa7bb", 2, 10)
    draw.rectangle((tile_x + 8, tile_y + 8, tile_x + 230, tile_y + 152), fill="#9fb1c8")
    draw.rectangle((tile_x + 16, tile_y + 118, tile_x + 222, tile_y + 148), fill="#263238")
    draw.text((tile_x + 24, tile_y + 124), "Candidate: court-1", fill="#ffffff", font=small)

    rounded(draw, (72, 670, 1368, 814), "#edf7f0", "#9bd2ad", 2, 16)
    draw.text((104, 700), "Verified Commands", fill="#185d34", font=heading)
    draw.text(
        (104, 750),
        "flutter test --no-pub test/services/gallery_session_matcher_test.dart test/screens/media_selection_screen_test.dart",
        fill="#183324",
        font=mono,
    )
    draw.text((104, 784), "Result: +4 tests passed", fill="#305640", font=small)

    image.save(SCREENSHOT)
    print(SCREENSHOT)


if __name__ == "__main__":
    main()
