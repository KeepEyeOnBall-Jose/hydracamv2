#!/usr/bin/env python3
"""
Try different API endpoints to find sessions data.
"""

import ssl
from urllib.request import urlopen, Request, HTTPError


def try_endpoint(base_url, path, verify_ssl=False):
    """Try to fetch an endpoint and return status."""
    url = f"{base_url}{path}"
    print(f"Trying: {url}")

    try:
        req = Request(
            url,
            headers={
                "User-Agent": "Mozilla/5.0",
                "Accept": "application/json, text/html",
            },
        )

        context = None
        if not verify_ssl:
            context = ssl._create_unverified_context()

        with urlopen(req, timeout=10, context=context) as resp:
            content_type = resp.headers.get("Content-Type", "")
            status = resp.status
            data = resp.read()

            print(f"  ✓ {status} - Content-Type: {content_type}")
            print(f"  Size: {len(data)} bytes")

            # Show first 200 chars if JSON or text
            if "json" in content_type or "text" in content_type:
                preview = data[:200].decode("utf-8", errors="ignore")
                print(f"  Preview: {preview}...")

            return True

    except HTTPError as e:
        print(f"  ✗ HTTP {e.code}: {e.reason}")
        return False
    except Exception as e:
        print(f"  ✗ Error: {e}")
        return False


def main():
    base_url = "https://hydracam.azurewebsites.net"

    endpoints = [
        "/api/sessions",
        "/api/Sessions",
        "/Sessions",
        "/sessions",
        "/api/session",
        "/home/sessions",
        "/Home/Sessions",
        "/session/list",
        "/Session/List",
    ]

    print("Testing HydraCam endpoints...\n")

    for endpoint in endpoints:
        try_endpoint(base_url, endpoint)
        print()


if __name__ == "__main__":
    main()
