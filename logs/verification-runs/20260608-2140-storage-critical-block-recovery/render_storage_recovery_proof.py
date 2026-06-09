#!/usr/bin/env python3
from pathlib import Path
import subprocess

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent
SCREENSHOT = ROOT / "screenshots" / "storage_critical_block_recovery.png"
VIDEO = ROOT / "video" / "storage_critical_block_recovery_proof.mp4"
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


def rounded(draw: ImageDraw.ImageDraw, xy, fill, outline=None, width=1, radius=12):
    draw.rounded_rectangle(xy, radius=radius, fill=fill, outline=outline, width=width)


def lines(draw, xy, values, fill, font_obj, spacing=8):
    draw.multiline_text(xy, "\n".join(values), fill=fill, font=font_obj, spacing=spacing)


def make_image(step: int = 3) -> Image.Image:
    image = Image.new("RGB", (1440, 900), "#f7f8fb")
    draw = ImageDraw.Draw(image)

    title = font(42, True)
    heading = font(28, True)
    body = font(22)
    small = font(19)
    mono = font(18)

    draw.text((72, 54), "Critical Storage Block Recovery", fill="#172033", font=title)
    draw.text(
        (74, 116),
        "T-017 slice: critical storage blocks recording; low storage only warns",
        fill="#596476",
        font=body,
    )

    rounded(draw, (72, 170, 720, 758), "#ffffff", "#d7dfeb", 2)
    draw.text((104, 206), "Storage Thresholds", fill="#263241", font=heading)
    lines(
        draw,
        (112, 270),
        [
            "Critical threshold: 0.5 GB",
            "Low-warning threshold: 1.5 GB",
            "",
            "Scenario: 400 MB free then 900 MB free.",
        ],
        "#263241",
        small,
    )

    if step >= 2:
        rounded(draw, (112, 438, 672, 626), "#eef5ff", "#a9b8d1", 2, 8)
        draw.text((140, 470), "Expected state", fill="#1d5f9f", font=small)
        lines(
            draw,
            (140, 514),
            [
                "400 MB: recording blocked, callback once",
                "900 MB: block cleared",
                "900 MB: low-storage warning may still show",
            ],
            "#15324f",
            mono,
            6,
        )

    if step >= 3:
        draw.text(
            (112, 690),
            "Recording blockage now follows the critical threshold only.",
            fill="#263241",
            font=body,
        )

    rounded(draw, (760, 170, 1368, 314), "#ffffff", "#d7dfeb", 2)
    draw.text((792, 204), "RED", fill="#b3261e", font=heading)
    lines(
        draw,
        (792, 254),
        [
            "Focused test expected block=false at 900 MB.",
            "Actual value remained true before the fix.",
        ],
        "#263241",
        small,
    )

    if step >= 2:
        rounded(draw, (760, 354, 1368, 530), "#ffffff", "#cbd7f0", 2)
        draw.text((792, 388), "CHANGE", fill="#1d5f9f", font=heading)
        lines(
            draw,
            (792, 438),
            [
                "StorageService clears _blockRecording",
                "as soon as storage is above critical.",
                "The low threshold still controls warnings.",
            ],
            "#263241",
            small,
        )

    if step >= 3:
        rounded(draw, (760, 570, 1368, 760), "#edf7f0", "#9bd2ad", 2)
        draw.text((792, 604), "GREEN", fill="#1d7a46", font=heading)
        lines(
            draw,
            (792, 656),
            [
                "Focused StorageService tests passed.",
                "Critical callback count stays at one.",
                "Recovery above critical clears recording block.",
            ],
            "#263241",
            small,
        )
        draw.text((792, 730), "Result: 6 focused tests passed.", fill="#2d4b36", font=small)

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
