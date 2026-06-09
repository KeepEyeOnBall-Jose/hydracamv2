#!/usr/bin/env python3
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent
SCREENSHOT = ROOT / "screenshots" / "stale_inflight_upload_reset_guard.png"


def font(size: int, bold: bool = False) -> ImageFont.FreeTypeFont:
    candidates = [
        "/System/Library/Fonts/Supplemental/Arial Bold.ttf" if bold else "/System/Library/Fonts/Supplemental/Arial.ttf",
        "/System/Library/Fonts/Supplemental/Helvetica Bold.ttf" if bold else "/System/Library/Fonts/Supplemental/Helvetica.ttf",
    ]
    for path in candidates:
        try:
            return ImageFont.truetype(path, size)
        except OSError:
            continue
    return ImageFont.load_default()


def panel(draw: ImageDraw.ImageDraw, xy, fill, outline):
    draw.rounded_rectangle(xy, radius=18, fill=fill, outline=outline, width=2)


def main() -> None:
    SCREENSHOT.parent.mkdir(parents=True, exist_ok=True)
    image = Image.new("RGB", (1440, 900), "#f7f8fb")
    draw = ImageDraw.Draw(image)

    title = font(48, True)
    heading = font(30, True)
    body = font(25)
    mono = font(23)

    draw.text((72, 54), "Stale In-Flight Upload Reset Guard", fill="#18202f", font=title)
    draw.text(
        (74, 116),
        "Board item 3 slice: a previous-session HTTP completion cannot update new session state",
        fill="#586174",
        font=body,
    )

    panel(draw, (72, 178, 1368, 352), "#ffffff", "#d9deea")
    draw.text((104, 212), "RED", fill="#b3261e", font=heading)
    draw.text(
        (184, 216),
        "Upload request was held open, uploader reset, new session started.",
        fill="#18202f",
        font=body,
    )
    draw.text(
        (104, 278),
        "Before: the stale HTTP 200 still marked old media as uploaded.",
        fill="#4a5568",
        font=mono,
    )

    panel(draw, (72, 390, 1368, 646), "#ffffff", "#cbd7f0")
    draw.text((104, 424), "GREEN", fill="#1d7a46", font=heading)
    rows = [
        "UploaderService.reset() increments an upload generation.",
        "In-flight completion compares its captured generation before mutating media.",
        "Old photo remains isUploaded = false after stale success.",
        "SessionManager remains on new-session-guid with no old photos attached.",
    ]
    for index, row in enumerate(rows):
        draw.text((104, 486 + index * 36), row, fill="#2d3748", font=body)

    panel(draw, (72, 686, 1368, 812), "#edf7f0", "#9bd2ad")
    draw.text((104, 718), "Verified Commands", fill="#185d34", font=heading)
    draw.text(
        (104, 770),
        "flutter test --no-pub test/services/uploader_service_test.dart",
        fill="#183324",
        font=mono,
    )

    image.save(SCREENSHOT)
    print(SCREENSHOT)


if __name__ == "__main__":
    main()
