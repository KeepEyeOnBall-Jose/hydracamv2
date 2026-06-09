#!/usr/bin/env python3
from pathlib import Path
import subprocess

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent
SCREENSHOT = ROOT / "screenshots" / "master_slave_preview_missing_state.png"
VIDEO = ROOT / "video" / "master_slave_preview_missing_state_proof.mp4"
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
    mono = font(20)

    draw.text((72, 54), "Master Preview Missing State", fill="#172033", font=title)
    draw.text(
        (74, 116),
        "Board item 14 slice: missing slave preview is explicit in diagnostics",
        fill="#596476",
        font=body,
    )

    rounded(draw, (72, 170, 690, 752), "#ffffff", "#d7dfeb", 2)
    draw.text((104, 206), "Known Devices", fill="#263241", font=heading)
    draw.text((104, 256), "1 connected · 0 disconnected", fill="#596476", font=body)
    rounded(draw, (104, 320, 626, 632), "#f8fafc", "#cbd5e1", 2, 8)
    draw.text((136, 352), "slave-de · Connected · Ready", fill="#172033", font=body)
    details = [
        "Device ID: slave-device-a",
        "SSID: Wi-Fi active",
        "Device IP: 192.168.178.62 | Remote: 192.168.178.62",
        "Subnet: 192.168.178.0/24",
    ]
    for index, line in enumerate(details):
        draw.text((136, 404 + index * 32), line, fill="#263241", font=small)
    if step >= 2:
        draw.text(
            (136, 536),
            "Preview: Preview unavailable",
            fill="#1d5f9f",
            font=small,
        )
        draw.text(
            (136, 568),
            "(Preview transport not configured)",
            fill="#1d5f9f",
            font=small,
        )

    rounded(draw, (740, 170, 1368, 314), "#ffffff", "#d7dfeb", 2)
    draw.text((772, 204), "RED", fill="#b3261e", font=heading)
    draw.text(
        (772, 254),
        "Payload test failed because connected clients had no preview status keys.",
        fill="#263241",
        font=small,
    )

    if step >= 2:
        rounded(draw, (740, 354, 1368, 546), "#ffffff", "#cbd7f0", 2)
        draw.text((772, 388), "CHANGE", fill="#1d5f9f", font=heading)
        draw.multiline_text(
            (772, 438),
            '"previewStatus":"unavailable"\n'
            '"previewStatusLabel":"Preview unavailable"\n'
            '"previewTransportLabel":"Preview transport not configured"',
            fill="#263241",
            font=mono,
            spacing=8,
        )

    if step >= 3:
        rounded(draw, (740, 586, 1368, 752), "#edf7f0", "#9bd2ad", 2)
        draw.text((772, 620), "GREEN", fill="#1d7a46", font=heading)
        draw.multiline_text(
            (772, 672),
            "Focused payload test passed; modal uses\n"
            "the same labels for connected devices.",
            fill="#263241",
            font=small,
            spacing=8,
        )
        draw.text(
            (772, 726),
            "Result: connected_client_automation_payload_test.dart passed (+3).",
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
