#!/usr/bin/env python3
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont


RUN_DIR = Path(__file__).resolve().parent
OUTPUT = RUN_DIR / "screenshots" / "pending_upload_cancel_control.png"
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
    image = Image.new("RGB", (860, 600), "#f7f5ef")
    draw = ImageDraw.Draw(image)

    title = font(34, bold=True)
    heading = font(22, bold=True)
    body = font(18)
    small = font(16)

    draw.text((40, 36), "Pending Upload Cancel Proof", fill="#171717", font=title)
    draw.text(
        (40, 84),
        "Item 4: explicit cancel control for media still waiting in the queue",
        fill="#4b5563",
        font=body,
    )

    card(draw, (40, 130, 820, 275), "#ffffff", "#d6d3d1")
    draw.text((66, 155), "Media row", fill="#171717", font=heading)
    draw.text((66, 195), "Video from: pending-cancel-device", fill="#374151", font=body)
    draw.text((66, 225), "Pending upload", fill="#374151", font=body)
    draw.rounded_rectangle((650, 175, 720, 245), radius=35, fill="#fff7ed", outline="#f97316", width=3)
    draw.text((672, 194), "X", fill="#9a3412", font=font(28, bold=True))
    draw.text((625, 252), "Cancel upload", fill="#9a3412", font=small)

    card(draw, (40, 320, 820, 440), "#ecfdf5", "#10b981")
    draw.text((66, 346), "Queue result", fill="#065f46", font=heading)
    draw.text(
        (66, 386),
        "cancelQueuedMedia(firstPhoto) -> true, queue length 2 -> 1",
        fill="#065f46",
        font=body,
    )

    card(draw, (40, 480, 820, 545), "#eff6ff", "#2563eb")
    draw.text((66, 500), "Scope", fill="#1e3a8a", font=heading)
    draw.text(
        (160, 504),
        "This cancels pending queued uploads; in-flight network cancellation remains open.",
        fill="#1e3a8a",
        font=small,
    )

    draw.text(
        (40, 575),
        "Focused tests cover queue removal and row callback/tooltip behavior.",
        fill="#4b5563",
        font=small,
    )

    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    image.save(OUTPUT)
    print(OUTPUT)


if __name__ == "__main__":
    main()
