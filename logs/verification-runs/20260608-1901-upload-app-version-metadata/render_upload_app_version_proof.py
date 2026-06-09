#!/usr/bin/env python3
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent
SCREENSHOT = ROOT / "screenshots" / "upload_app_version_metadata.png"


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

    draw.text((72, 54), "Uploaded Media App Metadata", fill="#18202f", font=title)
    draw.text(
        (74, 116),
        "Board row 111 slice: include app version/build in upload multipart fields",
        fill="#586174",
        font=body,
    )

    panel(draw, (72, 178, 1368, 352), "#ffffff", "#d9deea")
    draw.text((104, 212), "RED", fill="#b3261e", font=heading)
    draw.text(
        (184, 216),
        "Multipart fields did not contain appVersion or appBuildNumber.",
        fill="#18202f",
        font=body,
    )
    draw.text(
        (104, 276),
        "Captured fields: slaveDeviceId, captureDate, receivedDate",
        fill="#4a5568",
        font=mono,
    )

    panel(draw, (72, 390, 1368, 626), "#ffffff", "#cbd7f0")
    draw.text((104, 424), "GREEN", fill="#1d7a46", font=heading)
    rows = [
        "appVersion = 2.3.4",
        "appBuildNumber = 567",
        "Existing fields preserved: slaveDeviceId, captureDate, receivedDate",
        "Mock HTTP client returned 200, so uploadMedia() returned true",
    ]
    for index, row in enumerate(rows):
        draw.text((104, 486 + index * 34), row, fill="#2d3748", font=body)

    panel(draw, (72, 664, 1368, 806), "#edf7f0", "#9bd2ad")
    draw.text((104, 696), "Verified Commands", fill="#185d34", font=heading)
    draw.text(
        (104, 748),
        "flutter test --no-pub test/services/hydracam_api_service_test.dart",
        fill="#183324",
        font=mono,
    )

    image.save(SCREENSHOT)
    print(SCREENSHOT)


if __name__ == "__main__":
    main()
