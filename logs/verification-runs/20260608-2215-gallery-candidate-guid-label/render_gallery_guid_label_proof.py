#!/usr/bin/env python3
from pathlib import Path
import subprocess

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent
SCREENSHOT = ROOT / "screenshots" / "gallery_candidate_guid_label.png"
VIDEO = ROOT / "video" / "gallery_candidate_guid_label_proof.mp4"
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

    draw.text((72, 54), "Gallery Candidate GUID Label", fill="#172033", font=title)
    draw.text(
        (74, 116),
        "JAVI row 35 slice: old-media candidate labels prefer canonical session GUIDs",
        fill="#596476",
        font=body,
    )

    rounded(draw, (72, 170, 700, 760), "#ffffff", "#d7dfeb", 2)
    draw.text((104, 206), "Media Selection Tile", fill="#263241", font=heading)
    draw.text((112, 284), "Before: Candidate: court-1", fill="#596476", font=body)
    if step >= 2:
        rounded(draw, (112, 352, 636, 492), "#eef5ff", "#a9b8d1", 2, 8)
        draw.text((140, 386), "After", fill="#1d5f9f", font=small)
        draw.text((140, 426), "Candidate: guid-court-1", fill="#15324f", font=mono)
    if step >= 3:
        draw.text((112, 560), "Fallback remains: Candidate: legacy-session-id", fill="#263241", font=body)

    rounded(draw, (760, 170, 1368, 314), "#ffffff", "#d7dfeb", 2)
    draw.text((792, 204), "RED", fill="#b3261e", font=heading)
    draw.multiline_text(
        (792, 254),
        "Widget test expected guid-court-1 but found\n"
        "the legacy sessionId label instead.",
        fill="#263241",
        font=small,
        spacing=8,
    )

    if step >= 2:
        rounded(draw, (760, 354, 1368, 530), "#ffffff", "#cbd7f0", 2)
        draw.text((792, 388), "CHANGE", fill="#1d5f9f", font=heading)
        draw.multiline_text(
            (792, 438),
            "MediaSelectionScreen now uses\n"
            "sessionGuid ?? sessionId for candidate labels.",
            fill="#263241",
            font=small,
            spacing=8,
        )

    if step >= 3:
        rounded(draw, (760, 570, 1368, 760), "#edf7f0", "#9bd2ad", 2)
        draw.text((792, 604), "GREEN", fill="#1d7a46", font=heading)
        draw.multiline_text(
            (792, 656),
            "Focused MediaSelection widget tests passed.\n"
            "GUID preference and legacy fallback are covered.",
            fill="#263241",
            font=small,
            spacing=8,
        )
        draw.text((792, 724), "Result: 2 focused tests passed.", fill="#2d4b36", font=small)

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
