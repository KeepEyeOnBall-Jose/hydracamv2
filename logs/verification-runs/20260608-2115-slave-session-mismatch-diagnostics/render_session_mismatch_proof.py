#!/usr/bin/env python3
from pathlib import Path
import subprocess

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent
SCREENSHOT = ROOT / "screenshots" / "slave_session_mismatch_diagnostics.png"
VIDEO = ROOT / "video" / "slave_session_mismatch_diagnostics_proof.mp4"
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

    draw.text((72, 54), "Slave Session Mismatch Diagnostics", fill="#172033", font=title)
    draw.text(
        (74, 116),
        "Backlog row 8 slice: master can identify slaves reporting another session",
        fill="#596476",
        font=body,
    )

    rounded(draw, (72, 170, 690, 760), "#ffffff", "#d7dfeb", 2)
    draw.text((104, 206), "Protocol Evidence", fill="#263241", font=heading)
    rounded(draw, (104, 270, 626, 390), "#edf3fb", "#a9b8d1", 2, 8)
    draw.text((132, 302), "Slave heartbeat", fill="#1d5f9f", font=small)
    draw.text(
        (132, 340),
        '{"type":"heartbeat","sessionGuid":"slave-session-guid"}',
        fill="#15324f",
        font=mono,
    )

    if step >= 2:
        rounded(draw, (104, 450, 626, 632), "#f8fafc", "#cbd5e1", 2, 8)
        draw.text((132, 482), "Master diagnostics", fill="#172033", font=small)
        draw.text((132, 526), "Master session: master-active-session", fill="#263241", font=small)
        draw.text((132, 562), "Slave reports: slave-other-session", fill="#263241", font=small)
        draw.text((132, 598), "Session: Different session", fill="#b3261e", font=small)

    rounded(draw, (740, 170, 1368, 314), "#ffffff", "#d7dfeb", 2)
    draw.text((772, 204), "RED", fill="#b3261e", font=heading)
    draw.multiline_text(
        (772, 254),
        "Tests failed because heartbeat did not include sessionGuid\n"
        "and diagnostics lacked sessionStatus fields.",
        fill="#263241",
        font=small,
        spacing=8,
    )

    if step >= 2:
        rounded(draw, (740, 354, 1368, 546), "#ffffff", "#cbd7f0", 2)
        draw.text((772, 388), "CHANGE", fill="#1d5f9f", font=heading)
        draw.multiline_text(
            (772, 438),
            "Slave registration and heartbeat report sessionGuid.\n"
            "ConnectedDeviceInfo compares slave and master sessions.",
            fill="#263241",
            font=small,
            spacing=8,
        )

    if step >= 3:
        rounded(draw, (740, 586, 1368, 760), "#edf7f0", "#9bd2ad", 2)
        draw.text((772, 620), "GREEN", fill="#1d7a46", font=heading)
        draw.multiline_text(
            (772, 672),
            "Focused loopback/unit tests passed: heartbeat reports\n"
            "slave-session-guid and payload labels Different session.",
            fill="#263241",
            font=small,
            spacing=8,
        )
        draw.text(
            (772, 732),
            "Result: slave_client_registration + connected_client payload passed.",
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
