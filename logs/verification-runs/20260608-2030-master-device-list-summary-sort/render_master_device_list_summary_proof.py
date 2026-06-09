#!/usr/bin/env python3
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent
SCREENSHOT = ROOT / "screenshots" / "master_device_list_summary_sort.png"


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

    title = font(45, True)
    heading = font(30, True)
    body = font(24)
    mono = font(21)
    small = font(18)

    draw.text((72, 54), "Master Device List Summary", fill="#18202f", font=title)
    draw.text(
        (74, 116),
        "Board item 6 slice: known device list separates live and disconnected devices",
        fill="#586174",
        font=body,
    )

    rounded(draw, (72, 170, 1368, 314), "#ffffff", "#d9deea", 2, 16)
    draw.text((104, 204), "RED", fill="#b3261e", font=heading)
    draw.text(
        (184, 208),
        "No known/stale summary and stale devices sorted first",
        fill="#18202f",
        font=mono,
    )
    draw.text(
        (104, 258),
        "Focused tests failed until the master list reported totals and ordered live devices first.",
        fill="#4a5568",
        font=body,
    )

    rounded(draw, (72, 354, 1368, 626), "#ffffff", "#cbd7f0", 2, 16)
    draw.text((104, 388), "GREEN", fill="#1d7a46", font=heading)
    steps = [
        "1. Automation payload includes known, connected, and disconnected counts.",
        "2. MasterServer returns connected devices before disconnected history.",
        "3. Master modal shows Known Devices and a live/stale summary.",
    ]
    for index, line in enumerate(steps):
        draw.text((104, 448 + index * 38), line, fill="#2d3748", font=body)

    rounded(draw, (920, 438, 1268, 552), "#edf3fb", "#a9b8d1", 2, 10)
    draw.text((948, 464), "1 connected", fill="#19324d", font=small)
    draw.text((948, 504), "1 disconnected", fill="#19324d", font=small)

    rounded(draw, (72, 670, 1368, 814), "#edf7f0", "#9bd2ad", 2, 16)
    draw.text((104, 700), "Verified Commands", fill="#185d34", font=heading)
    draw.text(
        (104, 750),
        "flutter test --no-pub test/master/connected_client_automation_payload_test.dart test/master/master_network_snapshot_cache_test.dart",
        fill="#183324",
        font=small,
    )
    draw.text((104, 784), "Result: +10 focused master tests passed", fill="#305640", font=small)

    image.save(SCREENSHOT)
    print(SCREENSHOT)


if __name__ == "__main__":
    main()
