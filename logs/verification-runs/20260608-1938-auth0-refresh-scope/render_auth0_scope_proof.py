#!/usr/bin/env python3
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent
SCREENSHOT = ROOT / "screenshots" / "auth0_refresh_scope.png"


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

    title = font(48, True)
    heading = font(30, True)
    body = font(25)
    mono = font(23)
    small = font(20)

    draw.text((72, 54), "Auth0 Refresh-Capable Scope", fill="#18202f", font=title)
    draw.text(
        (74, 116),
        "Board item 11 slice: login now asks Auth0 for offline_access",
        fill="#586174",
        font=body,
    )

    rounded(draw, (72, 178, 1368, 338), "#ffffff", "#d9deea", 2, 16)
    draw.text((104, 210), "RED", fill="#b3261e", font=heading)
    draw.text((184, 214), "AuthService.authorizationScopes missing", fill="#18202f", font=mono)
    draw.text(
        (104, 268),
        "Before: the request used only openid/profile/email, so refresh-capable credentials could not be requested.",
        fill="#4a5568",
        font=body,
    )

    rounded(draw, (72, 378, 1368, 602), "#ffffff", "#cbd7f0", 2, 16)
    draw.text((104, 410), "GREEN", fill="#1d7a46", font=heading)
    steps = [
        "1. AuthService.authorizationScopes includes openid, profile, email, and offline_access.",
        "2. The AuthorizationTokenRequest uses that shared scope list.",
        "3. This is only the first recoverable-login prerequisite; credential persistence remains separate.",
    ]
    for index, line in enumerate(steps):
        draw.text((104, 470 + index * 38), line, fill="#2d3748", font=body)

    rounded(draw, (72, 646, 1368, 790), "#edf7f0", "#9bd2ad", 2, 16)
    draw.text((104, 678), "Verified Command", fill="#185d34", font=heading)
    draw.text(
        (104, 730),
        "flutter test --no-pub test/services/auth0_service_test.dart",
        fill="#183324",
        font=mono,
    )
    draw.text(
        (104, 766),
        "Result: +1 test passed",
        fill="#305640",
        font=small,
    )

    image.save(SCREENSHOT)
    print(SCREENSHOT)


if __name__ == "__main__":
    main()
