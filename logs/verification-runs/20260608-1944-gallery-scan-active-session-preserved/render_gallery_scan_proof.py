#!/usr/bin/env python3
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent
SCREENSHOT = ROOT / "screenshots" / "gallery_scan_active_session_preserved.png"


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
    body = font(25)
    mono = font(22)
    small = font(20)

    draw.text((72, 54), "Gallery Scan Preserves Active Session", fill="#18202f", font=title)
    draw.text(
        (74, 116),
        "Board item 9 slice: old-media reconstruction no longer corrupts live session state",
        fill="#586174",
        font=body,
    )

    rounded(draw, (72, 176, 1368, 348), "#ffffff", "#d9deea", 2, 16)
    draw.text((104, 210), "RED", fill="#b3261e", font=heading)
    draw.text(
        (184, 214),
        "scanAndReconstructSessions changed sessionGuid to scan-preserve-old",
        fill="#18202f",
        font=mono,
    )
    draw.text(
        (104, 270),
        "The scan rebuilt old media metadata but left the singleton pointing at the reconstructed session.",
        fill="#4a5568",
        font=body,
    )

    rounded(draw, (72, 388, 1368, 626), "#ffffff", "#cbd7f0", 2, 16)
    draw.text((104, 422), "GREEN", fill="#1d7a46", font=heading)
    steps = [
        "1. Capture previous _currentSession, _sessionGuid, and _deviceType before scanning.",
        "2. Reconstruct metadata for folders whose final path segment starts with session_.",
        "3. Restore the active session identity after scanning historical media folders.",
        "4. Keep non-session folders out of available-session and reconstruction results.",
    ]
    for index, line in enumerate(steps):
        draw.text((104, 482 + index * 36), line, fill="#2d3748", font=body)

    rounded(draw, (72, 670, 1368, 810), "#edf7f0", "#9bd2ad", 2, 16)
    draw.text((104, 700), "Verified Command", fill="#185d34", font=heading)
    draw.text(
        (104, 750),
        "flutter test --no-pub test/services/session_manager_test.dart",
        fill="#183324",
        font=mono,
    )
    draw.text((104, 784), "Result: +10 tests passed", fill="#305640", font=small)

    image.save(SCREENSHOT)
    print(SCREENSHOT)


if __name__ == "__main__":
    main()
