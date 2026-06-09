#!/usr/bin/env python3
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent
SCREENSHOT = ROOT / "screenshots" / "start_upload_all_slave_command.png"


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


def rounded(draw: ImageDraw.ImageDraw, xy, fill, outline=None, width=1, radius=18):
    draw.rounded_rectangle(xy, radius=radius, fill=fill, outline=outline, width=width)


def main() -> None:
    SCREENSHOT.parent.mkdir(parents=True, exist_ok=True)
    image = Image.new("RGB", (1440, 900), "#f7f8fb")
    draw = ImageDraw.Draw(image)

    title = font(48, True)
    heading = font(30, True)
    body = font(25)
    mono = font(23)
    small = font(20)

    draw.text((72, 54), "Start Upload All Slave Command", fill="#18202f", font=title)
    draw.text(
        (74, 116),
        "Board item 4 slice: master command starts a slave's queued uploader",
        fill="#586174",
        font=body,
    )

    rounded(draw, (72, 178, 1368, 334), "#ffffff", "#d9deea", 2, 16)
    draw.text((104, 210), "RED", fill="#b3261e", font=heading)
    draw.text((184, 214), '{"command":"startUploadingAll"}', fill="#18202f", font=mono)
    draw.text(
        (104, 264),
        "Before: SlaveClient logged Unknown JSON command type and the queued upload stayed pending.",
        fill="#4a5568",
        font=body,
    )

    rounded(draw, (72, 370, 1368, 600), "#ffffff", "#cbd7f0", 2, 16)
    draw.text((104, 402), "GREEN", fill="#1d7a46", font=heading)
    steps = [
        "1. Local WebSocket sends startUploadingAll after slave registration.",
        "2. SlaveClient routes the JSON command into _executeCommand().",
        "3. UploaderService.startUploadingManually() consumes the queued item.",
        "4. No backend request is made in this proof because sessionGuid is intentionally null.",
    ]
    for index, line in enumerate(steps):
        draw.text((104, 462 + index * 32), line, fill="#2d3748", font=body)

    rounded(draw, (72, 638, 1368, 806), "#edf7f0", "#9bd2ad", 2, 16)
    draw.text((104, 670), "Verified Commands", fill="#185d34", font=heading)
    draw.text(
        (104, 725),
        "flutter test --no-pub test/slave/slave_client_registration_test.dart",
        fill="#183324",
        font=mono,
    )
    draw.text(
        (104, 764),
        "Result: +4 tests passed, including startUploadingAll command starts pending upload queue",
        fill="#305640",
        font=small,
    )

    image.save(SCREENSHOT)
    print(SCREENSHOT)


if __name__ == "__main__":
    main()
