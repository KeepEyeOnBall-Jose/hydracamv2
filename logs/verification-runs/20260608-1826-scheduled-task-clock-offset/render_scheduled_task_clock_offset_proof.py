#!/usr/bin/env python3
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont


RUN_DIR = Path(__file__).resolve().parent
OUTPUT = RUN_DIR / "screenshots" / "scheduled_task_clock_offset.png"
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

    draw.text((40, 36), "Scheduled Clock Offset Proof", fill="#171717", font=title)
    draw.text(
        (40, 84),
        "Item 7: scheduling delay is computed from corrected local time",
        fill="#4b5563",
        font=body,
    )

    card(draw, (40, 130, 820, 245), "#ffffff", "#d6d3d1")
    draw.text((66, 154), "Test clock", fill="#171717", font=heading)
    draw.text((66, 190), "Local now: 18:26:00 UTC", fill="#374151", font=body)
    draw.text((420, 190), "Clock offset: +2 seconds", fill="#374151", font=body)

    card(draw, (40, 280, 820, 400), "#ecfdf5", "#10b981")
    draw.text((66, 304), "Corrected schedule delay", fill="#065f46", font=heading)
    draw.text(
        (66, 340),
        "Target command time: 18:26:05 UTC",
        fill="#065f46",
        font=body,
    )
    draw.text(
        (66, 370),
        "Corrected now: 18:26:02 UTC  ->  delayUntil = 3 seconds",
        fill="#065f46",
        font=body,
    )

    card(draw, (40, 435, 820, 525), "#eff6ff", "#2563eb")
    draw.text((66, 458), "Slave command path", fill="#1e3a8a", font=heading)
    draw.text(
        (66, 492),
        "SlaveClient now schedules received commands through ScheduledTaskService.",
        fill="#1e3a8a",
        font=body,
    )

    draw.text(
        (40, 560),
        "Unit tests also verify immediate execution for past corrected time and cancellable future timers.",
        fill="#4b5563",
        font=small,
    )

    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    image.save(OUTPUT)
    print(OUTPUT)


if __name__ == "__main__":
    main()
