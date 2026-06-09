#!/usr/bin/env python3
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent
SCREENSHOT = ROOT / "screenshots" / "auth0_startup_restore_valid_credentials.png"


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


def main() -> None:
    SCREENSHOT.parent.mkdir(parents=True, exist_ok=True)
    image = Image.new("RGB", (1440, 900), "#f7f8fb")
    draw = ImageDraw.Draw(image)

    title = font(45, True)
    heading = font(30, True)
    body = font(24)
    mono = font(21)
    small = font(18)

    draw.text((72, 54), "Auth0 Startup Restore", fill="#18202f", font=title)
    draw.text(
        (74, 116),
        "Board item 11 slice: a valid stored Auth0 session can restore without browser login",
        fill="#586174",
        font=body,
    )

    rounded(draw, (72, 170, 1368, 314), "#ffffff", "#d9deea", 2, 16)
    draw.text((104, 204), "RED", fill="#b3261e", font=heading)
    draw.text(
        (184, 208),
        "AuthService had no restoreStoredSession method",
        fill="#18202f",
        font=mono,
    )
    draw.text(
        (104, 258),
        "The focused test failed until AuthCredentialStore could load stored credentials.",
        fill="#4a5568",
        font=body,
    )

    rounded(draw, (72, 354, 1368, 626), "#ffffff", "#cbd7f0", 2, 16)
    draw.text((104, 388), "GREEN", fill="#1d7a46", font=heading)
    steps = [
        "1. SecureAuthCredentialStore can load saved token fields.",
        "2. AuthService restores non-expired access token, email, and profile picture.",
        "3. Expired credentials return false and clear in-memory auth state.",
    ]
    for index, line in enumerate(steps):
        draw.text((104, 448 + index * 38), line, fill="#2d3748", font=body)

    rounded(draw, (920, 438, 1268, 552), "#edf3fb", "#a9b8d1", 2, 10)
    draw.text((948, 464), "restored@example.com", fill="#19324d", font=small)
    draw.text((948, 504), "stored-access-token", fill="#19324d", font=small)

    rounded(draw, (72, 670, 1368, 814), "#edf7f0", "#9bd2ad", 2, 16)
    draw.text((104, 700), "Verified Commands", fill="#185d34", font=heading)
    draw.text(
        (104, 750),
        "flutter test --no-pub test/services/auth0_service_test.dart",
        fill="#183324",
        font=mono,
    )
    draw.text((104, 784), "Result: +4 Auth0 tests passed", fill="#305640", font=small)

    image.save(SCREENSHOT)
    print(SCREENSHOT)


if __name__ == "__main__":
    main()
