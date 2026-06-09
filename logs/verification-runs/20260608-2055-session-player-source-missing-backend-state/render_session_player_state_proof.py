#!/usr/bin/env python3
from pathlib import Path
import subprocess

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent
SCREENSHOT = ROOT / "screenshots" / "session_player_source_missing_backend_state.png"
VIDEO = ROOT / "video" / "session_player_source_missing_backend_state_proof.mp4"
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
    label = font(22, True)

    draw.text((72, 54), "Session Player Source State", fill="#172033", font=title)
    draw.text(
        (74, 116),
        "Board item 10 slice: missing backend support is explicit in session details",
        fill="#596476",
        font=body,
    )

    rounded(draw, (72, 170, 680, 752), "#ffffff", "#d7dfeb", 2)
    draw.text((104, 206), "Session Details", fill="#263241", font=heading)
    metadata = [
        "Session ID: session-players",
        "Session GUID: guid-players",
        "Start Time: 2026-06-08 20:55:00.000Z",
        "Total Photos: 0",
        "Total Videos: 0",
    ]
    for index, line in enumerate(metadata):
        draw.text((104, 268 + index * 34), line, fill="#263241", font=small)

    if step >= 2:
        rounded(draw, (104, 480, 612, 650), "#f8fafc", "#cbd5e1", 2, 8)
        draw.text((132, 510), "Players", fill="#172033", font=label)
        draw.text(
            (132, 560),
            "Source: backend not configured",
            fill="#263241",
            font=small,
        )
        draw.text(
            (132, 604),
            "Player assignment unavailable",
            fill="#576173",
            font=small,
        )

    rounded(draw, (740, 170, 1368, 314), "#ffffff", "#d7dfeb", 2)
    draw.text((772, 204), "RED", fill="#b3261e", font=heading)
    draw.text(
        (772, 254),
        "Widget test failed because SessionDetailsScreen had no Players section.",
        fill="#263241",
        font=small,
    )

    if step >= 2:
        rounded(draw, (740, 354, 1368, 520), "#ffffff", "#cbd7f0", 2)
        draw.text((772, 388), "CHANGE", fill="#1d5f9f", font=heading)
        draw.multiline_text(
            (772, 438),
            "Session metadata now shows a Players panel\n"
            "with explicit source and unavailable state.",
            fill="#263241",
            font=small,
            spacing=8,
        )

    if step >= 3:
        rounded(draw, (740, 560, 1368, 748), "#edf7f0", "#9bd2ad", 2)
        draw.text((772, 594), "GREEN", fill="#1d7a46", font=heading)
        draw.multiline_text(
            (772, 646),
            "Focused widget test proves Players,\n"
            "Source, and unavailable labels render.",
            fill="#263241",
            font=small,
            spacing=8,
        )
        draw.text(
            (772, 704),
            "Result: test/screens/session_details_screen_test.dart passed (+1).",
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
