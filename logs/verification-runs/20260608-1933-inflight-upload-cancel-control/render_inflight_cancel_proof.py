#!/usr/bin/env python3
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent
SCREENSHOT = ROOT / "screenshots" / "inflight_upload_cancel_control.png"


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

    draw.text((72, 54), "In-Flight Upload Cancel Control", fill="#18202f", font=title)
    draw.text(
        (74, 114),
        "Board item 4 slice: current upload can be cancelled from the uploader UI",
        fill="#586174",
        font=body,
    )

    rounded(draw, (72, 176, 1368, 338), "#ffffff", "#d9deea", 2, 16)
    draw.text((104, 208), "RED", fill="#b3261e", font=heading)
    draw.text((184, 212), "Cancel upload tooltip absent for current row", fill="#18202f", font=mono)
    draw.text(
        (104, 266),
        "Before: only pending queued media exposed the cancel action; active uploads could not be stopped.",
        fill="#4a5568",
        font=body,
    )

    rounded(draw, (72, 376, 1368, 632), "#ffffff", "#cbd7f0", 2, 16)
    draw.text((104, 408), "GREEN", fill="#1d7a46", font=heading)
    steps = [
        "1. MediaListWidget exposes Cancel upload for the current item.",
        "2. UploaderInfoScreen calls UploaderService.cancelMediaUpload().",
        "3. cancelCurrentUpload clears current/progress state and increments the generation guard.",
        "4. The API client is closed and replaced so the active request is aborted at the transport boundary.",
        "5. Late completion is ignored and cannot mark media uploaded.",
    ]
    for index, line in enumerate(steps):
        draw.text((104, 464 + index * 34), line, fill="#2d3748", font=body)

    rounded(draw, (72, 674, 1368, 820), "#edf7f0", "#9bd2ad", 2, 16)
    draw.text((104, 706), "Verified Commands", fill="#185d34", font=heading)
    draw.text(
        (104, 758),
        "flutter test --no-pub test/services/uploader_service_test.dart",
        fill="#183324",
        font=mono,
    )
    draw.text(
        (104, 794),
        "Also covered: media_list_widget_test.dart and uploader_info_screen_test.dart",
        fill="#305640",
        font=small,
    )

    image.save(SCREENSHOT)
    print(SCREENSHOT)


if __name__ == "__main__":
    main()
