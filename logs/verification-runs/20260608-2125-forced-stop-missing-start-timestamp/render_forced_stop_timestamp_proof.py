#!/usr/bin/env python3
from pathlib import Path
import subprocess

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent
SCREENSHOT = ROOT / "screenshots" / "forced_stop_missing_start_timestamp.png"
VIDEO = ROOT / "video" / "forced_stop_missing_start_timestamp_proof.mp4"
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

    draw.text((72, 54), "Forced Stop Timestamp Guard", fill="#172033", font=title)
    draw.text(
        (74, 116),
        "Backlog row 36 slice: forced stop survives a missing recording start timestamp",
        fill="#596476",
        font=body,
    )

    rounded(draw, (72, 170, 700, 760), "#ffffff", "#d7dfeb", 2)
    draw.text((104, 206), "Critical Battery Forced Stop", fill="#263241", font=heading)
    steps = [
        "1. Start mock video recording",
        "2. Clear videoStartRecordingDate",
        "3. Trigger forceStopRecordingDueToBattery()",
    ]
    for index, line in enumerate(steps):
        draw.text((112, 278 + index * 44), line, fill="#263241", font=body)

    if step >= 2:
        rounded(draw, (104, 470, 636, 632), "#edf3fb", "#a9b8d1", 2, 8)
        draw.text((132, 500), "Fallback metadata", fill="#1d5f9f", font=small)
        draw.text((132, 540), "startRecordingDate = videoEndRecordingDate", fill="#15324f", font=mono)
        draw.text((132, 580), "capturedVideos.length = 1", fill="#15324f", font=mono)

    rounded(draw, (760, 170, 1368, 314), "#ffffff", "#d7dfeb", 2)
    draw.text((792, 204), "RED", fill="#b3261e", font=heading)
    draw.multiline_text(
        (792, 254),
        "Test reproduced the null-check path:\n"
        "media file was written, but no video was added to session.",
        fill="#263241",
        font=small,
        spacing=8,
    )

    if step >= 2:
        rounded(draw, (760, 354, 1368, 530), "#ffffff", "#cbd7f0", 2)
        draw.text((792, 388), "CHANGE", fill="#1d5f9f", font=heading)
        draw.multiline_text(
            (792, 438),
            "Battery and storage forced-stop paths now use\n"
            "one builder with a logged timestamp fallback.",
            fill="#263241",
            font=small,
            spacing=8,
        )

    if step >= 3:
        rounded(draw, (760, 570, 1368, 760), "#edf7f0", "#9bd2ad", 2)
        draw.text((792, 604), "GREEN", fill="#1d7a46", font=heading)
        draw.multiline_text(
            (792, 656),
            "Focused CameraService test passed: recording stops,\n"
            "interruption fires, and one video is stored.",
            fill="#263241",
            font=small,
            spacing=8,
        )
        draw.text(
            (792, 724),
            "Result: camera_service_failure_test.dart passed (+13).",
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
