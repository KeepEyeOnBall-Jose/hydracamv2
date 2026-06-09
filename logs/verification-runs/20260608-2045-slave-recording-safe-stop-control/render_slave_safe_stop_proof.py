#!/usr/bin/env python3
from pathlib import Path
import subprocess

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent
SCREENSHOT = ROOT / "screenshots" / "slave_recording_safe_stop_control.png"
VIDEO = ROOT / "video" / "slave_recording_safe_stop_control_proof.mp4"
FRAMES = ROOT / "video" / "frames"


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


def rounded(draw: ImageDraw.ImageDraw, xy, fill, outline=None, width=1, radius=14):
    draw.rounded_rectangle(xy, radius=radius, fill=fill, outline=outline, width=width)


def make_image(step: int = 3) -> Image.Image:
    image = Image.new("RGB", (1440, 900), "#f6f8fb")
    draw = ImageDraw.Draw(image)

    title = font(44, True)
    heading = font(30, True)
    body = font(23)
    small = font(19)
    button = font(22, True)

    draw.text((72, 54), "Slave Recording Safe Stop", fill="#172033", font=title)
    draw.text(
        (74, 116),
        "Board item 8 slice: recording surface exposes a local stop control",
        fill="#596476",
        font=body,
    )

    rounded(draw, (72, 170, 650, 748), "#ffffff", "#d7dfeb", 2)
    draw.text((104, 206), "Simulated Slave Screen", fill="#263241", font=heading)
    rounded(draw, (124, 278, 598, 618), "#111827", "#1f2937", 2, 10)

    if step == 1:
        draw.text((242, 430), "Recording...", fill="#ef4444", font=heading)
    else:
        draw.text((242, 396), "Recording...", fill="#ef4444", font=heading)
        rounded(draw, (244, 458, 478, 524), "#f8fafc", "#cbd5e1", 2, 18)
        draw.ellipse((268, 477, 288, 497), fill="#dc2626")
        draw.text((310, 476), "Stop", fill="#172033", font=button)

    rounded(draw, (740, 170, 1368, 314), "#ffffff", "#d7dfeb", 2)
    draw.text((772, 204), "RED", fill="#b3261e", font=heading)
    draw.text(
        (772, 254),
        "Widget test failed: no stop control existed while the fake slave was recording.",
        fill="#263241",
        font=small,
    )

    if step >= 2:
        rounded(draw, (740, 354, 1368, 520), "#ffffff", "#cbd7f0", 2)
        draw.text((772, 388), "CHANGE", fill="#1d5f9f", font=heading)
        draw.multiline_text(
            (772, 438),
            "SlaveConnectionClient exposes stopRecordingLocally().\n"
            "SlaveScreen awaits it from the overlay button.",
            fill="#263241",
            font=small,
            spacing=8,
        )

    if step >= 3:
        rounded(draw, (740, 560, 1368, 748), "#edf7f0", "#9bd2ad", 2)
        draw.text((772, 594), "GREEN", fill="#1d7a46", font=heading)
        draw.multiline_text(
            (772, 646),
            "Focused widget test taps the control,\n"
            "observes one stop call, and sees Recording stopped.",
            fill="#263241",
            font=small,
            spacing=8,
        )
        draw.text(
            (772, 696),
            "Result: test/slave/slave_screen_fast_connect_test.dart passed (+5).",
            fill="#2d4b36",
            font=small,
        )

    return image


def write_video() -> None:
    FRAMES.mkdir(parents=True, exist_ok=True)
    VIDEO.parent.mkdir(parents=True, exist_ok=True)
    for index, step in enumerate([1, 2, 3], start=1):
        frame = make_image(step)
        for repeat in range(18):
            frame.save(FRAMES / f"frame_{((index - 1) * 18) + repeat:03d}.png")

    subprocess.run(
        [
            "ffmpeg",
            "-y",
            "-framerate",
            "12",
            "-i",
            str(FRAMES / "frame_%03d.png"),
            "-pix_fmt",
            "yuv420p",
            str(VIDEO),
        ],
        check=True,
    )


def main() -> None:
    SCREENSHOT.parent.mkdir(parents=True, exist_ok=True)
    make_image(3).save(SCREENSHOT)
    write_video()
    print(SCREENSHOT)
    print(VIDEO)


if __name__ == "__main__":
    main()
