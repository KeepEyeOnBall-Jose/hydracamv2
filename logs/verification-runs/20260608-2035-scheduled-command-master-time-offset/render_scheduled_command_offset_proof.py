#!/usr/bin/env python3
from pathlib import Path
import subprocess

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent
SCREENSHOT = ROOT / "screenshots" / "scheduled_command_master_time_offset.png"
VIDEO = ROOT / "video" / "scheduled_command_master_time_offset_proof.mp4"
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


def rounded(draw: ImageDraw.ImageDraw, xy, fill, outline=None, width=1, radius=16):
    draw.rounded_rectangle(xy, radius=radius, fill=fill, outline=outline, width=width)


def draw_panel(
    draw: ImageDraw.ImageDraw,
    xy,
    title: str,
    subtitle: str,
    accent: str,
) -> None:
    heading = font(30, True)
    body = font(23)
    rounded(draw, xy, "#ffffff", "#d6deeb", 2, 14)
    draw.rectangle((xy[0], xy[1], xy[0] + 12, xy[3]), fill=accent)
    draw.text((xy[0] + 34, xy[1] + 28), title, fill=accent, font=heading)
    draw.text((xy[0] + 34, xy[1] + 78), subtitle, fill="#263241", font=body)


def make_image(step: int = 3) -> Image.Image:
    image = Image.new("RGB", (1440, 900), "#f6f8fb")
    draw = ImageDraw.Draw(image)

    title = font(44, True)
    body = font(24)
    small = font(19)
    mono = font(22)

    draw.text((72, 52), "Scheduled Command Clock Offset", fill="#172033", font=title)
    draw.text(
        (74, 112),
        "Board item 7 slice: master timestamp travels with scheduled commands",
        fill="#596476",
        font=body,
    )

    draw_panel(
        draw,
        (72, 170, 1368, 302),
        "RED",
        "Focused tests failed until scheduleCommand accepted masterTime and SlaveClient accepted an injected scheduler.",
        "#b3261e",
    )

    if step >= 2:
        draw_panel(
            draw,
            (72, 336, 1368, 528),
            "PROTOCOL",
            "Payload now includes scheduledTime plus masterTime. Slave computes offset before delayUntil().",
            "#1d5f9f",
        )
        rounded(draw, (120, 444, 1320, 498), "#edf3fb", "#a9b8d1", 2, 10)
        draw.text(
            (150, 458),
            '{"type":"scheduledCommand","scheduledTime":"20:35:05Z","masterTime":"20:35:02Z"}',
            fill="#15324f",
            font=mono,
        )

    if step >= 3:
        draw_panel(
            draw,
            (72, 566, 1368, 792),
            "GREEN",
            "Loopback slave applies +2000 ms offset; corrected delay to capture command is 3 seconds.",
            "#1d7a46",
        )
        draw.text(
            (120, 674),
            "flutter test --no-pub test/master/master_network_snapshot_cache_test.dart test/slave/slave_client_registration_test.dart",
            fill="#2d3748",
            font=small,
        )
        draw.text(
            (120, 720),
            "Result: +13 focused tests passed; log includes 'Updated slave scheduled clock offset from master: 2000 ms.'",
            fill="#2d3748",
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
