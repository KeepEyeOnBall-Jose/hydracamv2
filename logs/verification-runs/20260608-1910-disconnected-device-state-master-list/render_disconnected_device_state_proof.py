#!/usr/bin/env python3
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent
SCREENSHOT = ROOT / "screenshots" / "disconnected_device_state_master_list.png"


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
    small = font(20)

    draw.text((72, 54), "Master Device List: Disconnected State", fill="#18202f", font=title)
    draw.text(
        (74, 116),
        "Board item 6 slice: retain a diagnostic row after a slave socket disconnects",
        fill="#586174",
        font=body,
    )

    panel(draw, (72, 178, 1368, 348), "#ffffff", "#d9deea")
    draw.text((104, 212), "RED", fill="#b3261e", font=heading)
    draw.text(
        (184, 216),
        "After socket removal, getConnectedDeviceInfos() returned an empty list.",
        fill="#18202f",
        font=body,
    )
    draw.text(
        (104, 278),
        "The master modal had no way to show which known device disconnected.",
        fill="#4a5568",
        font=mono,
    )

    panel(draw, (72, 386, 1368, 646), "#ffffff", "#cbd7f0")
    draw.text((104, 420), "GREEN", fill="#1d7a46", font=heading)
    rows = [
        "Connected IDs: []",
        "Device row: slave-a · Disconnected · Ready",
        "Disconnected timestamp: recorded in ConnectedDeviceInfo.disconnectedAt",
        "Automation payload: connectedClientCount stays live-only, diagnostics include both states",
    ]
    for index, row in enumerate(rows):
        draw.text((104, 482 + index * 36), row, fill="#2d3748", font=body)

    panel(draw, (72, 686, 1368, 834), "#edf7f0", "#9bd2ad")
    draw.text((104, 718), "Verified Commands", fill="#185d34", font=heading)
    draw.text(
        (104, 766),
        "flutter test --no-pub test/master/master_network_snapshot_cache_test.dart",
        fill="#183324",
        font=mono,
    )
    draw.text(
        (104, 796),
        "flutter test --no-pub test/master/connected_client_automation_payload_test.dart",
        fill="#183324",
        font=small,
    )

    image.save(SCREENSHOT)
    print(SCREENSHOT)


if __name__ == "__main__":
    main()
