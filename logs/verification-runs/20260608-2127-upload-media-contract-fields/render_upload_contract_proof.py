#!/usr/bin/env python3
from pathlib import Path
import subprocess

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent
SCREENSHOT = ROOT / "screenshots" / "upload_media_contract_fields.png"
VIDEO = ROOT / "video" / "upload_media_contract_fields_proof.mp4"
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


def text_block(draw, xy, lines, fill, font_obj, spacing=8):
    draw.multiline_text(xy, "\n".join(lines), fill=fill, font=font_obj, spacing=spacing)


def make_image(step: int = 3) -> Image.Image:
    image = Image.new("RGB", (1440, 900), "#f7f8fb")
    draw = ImageDraw.Draw(image)

    title = font(42, True)
    heading = font(28, True)
    body = font(22)
    small = font(19)
    mono = font(18)

    draw.text((72, 54), "Upload Media Field Contract", fill="#172033", font=title)
    draw.text(
        (74, 116),
        "JAVI row 106 slice: centralize photo/video upload field names without changing payloads",
        fill="#596476",
        font=body,
    )

    rounded(draw, (72, 170, 720, 758), "#ffffff", "#d7dfeb", 2)
    draw.text((104, 206), "Contract Surface", fill="#263241", font=heading)
    text_block(
        draw,
        (112, 270),
        [
            "Before: uploadMedia embedded multipart strings inline.",
            "",
            "RED: test referenced HydraCamUploadMediaContract",
            "and failed because the contract did not exist.",
        ],
        "#263241",
        small,
    )

    if step >= 2:
        rounded(draw, (112, 430, 672, 642), "#eef5ff", "#a9b8d1", 2, 8)
        draw.text((140, 462), "Centralized constants", fill="#1d5f9f", font=small)
        text_block(
            draw,
            (140, 506),
            [
                "endpoint: sessions/upload-media",
                "query: sessionGuid, isPhoto",
                "fields: slaveDeviceId, captureDate, receivedDate",
                "video: recordingEndDate, durationMs",
                "file field: files",
            ],
            "#15324f",
            mono,
            6,
        )

    if step >= 3:
        draw.text(
            (112, 700),
            "Payload stays compatible with the existing MoBo API contract.",
            fill="#263241",
            font=body,
        )

    rounded(draw, (760, 170, 1368, 314), "#ffffff", "#d7dfeb", 2)
    draw.text((792, 204), "RED", fill="#b3261e", font=heading)
    text_block(
        draw,
        (792, 254),
        [
            "Focused test failed at compile time:",
            "HydraCamUploadMediaContract was undefined.",
        ],
        "#263241",
        small,
    )

    if step >= 2:
        rounded(draw, (760, 354, 1368, 530), "#ffffff", "#cbd7f0", 2)
        draw.text((792, 388), "CHANGE", fill="#1d5f9f", font=heading)
        text_block(
            draw,
            (792, 438),
            [
                "uploadMedia now builds endpoint, query params,",
                "multipart fields, app metadata, file field,",
                "method, and success code from one contract.",
            ],
            "#263241",
            small,
        )

    if step >= 3:
        rounded(draw, (760, 570, 1368, 760), "#edf7f0", "#9bd2ad", 2)
        draw.text((792, 604), "GREEN", fill="#1d7a46", font=heading)
        text_block(
            draw,
            (792, 656),
            [
                "Focused HydraCamApiService tests passed.",
                "Photo, video duration, invalid file,",
                "and contract-field coverage are green.",
            ],
            "#263241",
            small,
        )
        draw.text((792, 730), "Result: 5 focused tests passed.", fill="#2d4b36", font=small)

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
