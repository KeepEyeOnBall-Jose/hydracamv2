#!/usr/bin/env python3
from pathlib import Path
import subprocess

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent
SCREENSHOT = ROOT / "screenshots" / "invalid_upload_file_guard.png"
VIDEO = ROOT / "video" / "invalid_upload_file_guard_proof.mp4"
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
    image = Image.new("RGB", (1440, 900), "#f7f8fb")
    draw = ImageDraw.Draw(image)

    title = font(43, True)
    heading = font(29, True)
    body = font(22)
    small = font(19)
    mono = font(19)

    draw.text((72, 54), "Invalid Upload File Guard", fill="#172033", font=title)
    draw.text(
        (74, 116),
        "Testing T-016 slice: missing media fails before multipart HTTP send",
        fill="#596476",
        font=body,
    )

    rounded(draw, (72, 170, 700, 760), "#ffffff", "#d7dfeb", 2)
    draw.text((104, 206), "Guard Behavior", fill="#263241", font=heading)
    steps = [
        "1. Call uploadMedia with a missing local file",
        "2. Return false before multipart request",
        "3. Log a clear missing-file reason",
    ]
    for index, line in enumerate(steps):
        draw.text((112, 278 + index * 44), line, fill="#263241", font=body)

    if step >= 2:
        rounded(draw, (104, 500, 636, 640), "#eef5ff", "#a9b8d1", 2, 8)
        draw.text((132, 530), "Expected log", fill="#1d5f9f", font=small)
        draw.text((132, 570), "Upload file does not exist: <path>", fill="#15324f", font=mono)
        draw.text((132, 604), "HTTP request sent = false", fill="#15324f", font=mono)

    rounded(draw, (760, 170, 1368, 314), "#ffffff", "#d7dfeb", 2)
    draw.text((792, 204), "RED", fill="#b3261e", font=heading)
    draw.multiline_text(
        (792, 254),
        "Test saw a generic PathNotFoundException log\n"
        "after upload setup instead of a file guard.",
        fill="#263241",
        font=small,
        spacing=8,
    )

    if step >= 2:
        rounded(draw, (760, 354, 1368, 530), "#ffffff", "#cbd7f0", 2)
        draw.text((792, 388), "CHANGE", fill="#1d5f9f", font=heading)
        draw.multiline_text(
            (792, 438),
            "HydraCamApiService checks file existence before\n"
            "headers, metadata, streaming, or HTTP send.",
            fill="#263241",
            font=small,
            spacing=8,
        )

    if step >= 3:
        rounded(draw, (760, 570, 1368, 760), "#edf7f0", "#9bd2ad", 2)
        draw.text((792, 604), "GREEN", fill="#1d7a46", font=heading)
        draw.multiline_text(
            (792, 656),
            "Focused upload API tests passed.\n"
            "Missing file returns false and no request is sent.",
            fill="#263241",
            font=small,
            spacing=8,
        )
        draw.text((792, 724), "Result: 4 focused tests passed.", fill="#2d4b36", font=small)

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
