#!/usr/bin/env python3
"""
Download portal session pages directly from HydraCam portal.
No backend API needed - scrapes the public web interface.
"""

import argparse
import re
import ssl
import sys
from pathlib import Path
from urllib.parse import urljoin, urlparse
from urllib.request import urlopen, Request


def fetch_url(url, timeout=30, verify_ssl=True):
    """Fetch a URL and return the content."""
    req = Request(
        url, headers={"User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)"}
    )

    context = None
    if not verify_ssl:
        context = ssl._create_unverified_context()

    with urlopen(req, timeout=timeout, context=context) as resp:
        return resp.read().decode("utf-8", errors="ignore")


def extract_session_links(html, base_url):
    """Extract session detail links from portal listing page."""
    links = []
    # Look for links containing session IDs or "quad-" patterns
    patterns = [
        r'href=["\']([^"\']*session[^"\']*)',
        r'href=["\']([^"\']*quad-[^"\']*)',
        r'href=["\']([^"\']*[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}[^"\']*)',
    ]

    for pattern in patterns:
        for match in re.finditer(pattern, html, re.I):
            link = match.group(1)
            full_url = urljoin(base_url, link)
            if full_url not in links:
                links.append(full_url)

    return links


def extract_media_urls(html, base_url):
    """Extract media URLs (images, videos) from HTML."""
    urls = []

    # Image sources
    for match in re.finditer(r'<img[^>]*src=["\']([^"\']+)', html, re.I):
        url = urljoin(base_url, match.group(1))
        if any(url.endswith(ext) for ext in [".jpg", ".jpeg", ".png", ".gif"]):
            urls.append(url)

    # Video sources
    for match in re.finditer(r'<video[^>]*src=["\']([^"\']+)', html, re.I):
        url = urljoin(base_url, match.group(1))
        urls.append(url)

    # Media links
    for match in re.finditer(
        r'href=["\']([^"\']+\.(jpg|jpeg|png|gif|mp4|mov|webm)[^"\']*)', html, re.I
    ):
        url = urljoin(base_url, match.group(1))
        urls.append(url)

    return list(set(urls))


def main():
    parser = argparse.ArgumentParser(description="Download HydraCam portal pages")
    parser.add_argument(
        "--portal-url", required=True, help="Base URL of HydraCam portal"
    )
    parser.add_argument(
        "--sessions-path", default="/sessions", help="Path to sessions listing page"
    )
    parser.add_argument(
        "--out-dir", default="evidence", help="Output directory (default: evidence)"
    )
    parser.add_argument(
        "--download-details", action="store_true", help="Download session detail pages"
    )
    parser.add_argument(
        "--download-media", action="store_true", help="Download media files"
    )
    parser.add_argument(
        "--no-verify-ssl",
        action="store_true",
        help="Disable SSL certificate verification",
    )

    args = parser.parse_args()

    out_dir = Path(args.out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)

    base_url = args.portal_url.rstrip("/")
    sessions_url = base_url + args.sessions_path

    print(f"Fetching sessions listing from: {sessions_url}")

    verify_ssl = not args.no_verify_ssl

    try:
        # Fetch main sessions listing page
        html = fetch_url(sessions_url, verify_ssl=verify_ssl)
        listing_file = out_dir / "portal_sessions.html"
        listing_file.write_text(html, encoding="utf-8")
        print(f"✓ Saved sessions listing: {listing_file}")

        # Extract session links
        session_links = extract_session_links(html, base_url)
        links_file = out_dir / "session_links.txt"
        links_file.write_text("\n".join(session_links), encoding="utf-8")
        print(f"✓ Found {len(session_links)} session links: {links_file}")

        # Extract media URLs from listing page
        media_urls = extract_media_urls(html, base_url)
        media_file = out_dir / "portal_asset_urls.txt"
        media_file.write_text("\n".join(media_urls), encoding="utf-8")
        print(f"✓ Found {len(media_urls)} media URLs: {media_file}")

        # Download individual session pages if requested
        if args.download_details and session_links:
            pages_dir = out_dir / "session_pages"
            pages_dir.mkdir(exist_ok=True)

            for i, link in enumerate(session_links, 1):
                # Extract session ID from URL for filename
                session_id = link.split("/")[-1] or f"session_{i}"
                session_id = re.sub(r"[^0-9A-Za-z_-]", "_", session_id)

                try:
                    print(f"  [{i}/{len(session_links)}] Downloading: {link}")
                    detail_html = fetch_url(link, verify_ssl=verify_ssl)
                    detail_file = pages_dir / f"{session_id}.html"
                    detail_file.write_text(detail_html, encoding="utf-8")

                    # Extract media from detail page
                    detail_media = extract_media_urls(detail_html, base_url)
                    media_urls.extend(detail_media)

                except Exception as e:
                    print(f"  ✗ Failed: {e}")

            # Update media URLs file with all discovered media
            all_media = list(set(media_urls))
            media_file.write_text("\n".join(all_media), encoding="utf-8")
            print(f"✓ Total media URLs found: {len(all_media)}")

        # Download media files if requested
        if args.download_media and media_urls:
            media_dir = out_dir / "portal_media"
            media_dir.mkdir(exist_ok=True)

            unique_media = list(set(media_urls))
            for i, url in enumerate(unique_media, 1):
                filename = Path(urlparse(url).path).name
                if not filename:
                    filename = f"media_{i}"

                try:
                    print(f"  [{i}/{len(unique_media)}] Downloading: {filename}")
                    req = Request(url, headers={"User-Agent": "Mozilla/5.0"})
                    with urlopen(req, timeout=30) as resp:
                        data = resp.read()

                    media_file = media_dir / filename
                    media_file.write_bytes(data)

                except Exception as e:
                    print(f"  ✗ Failed: {e}")

        print("\n✅ Portal download complete!")
        return 0

    except Exception as e:
        print(f"❌ Error: {e}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
