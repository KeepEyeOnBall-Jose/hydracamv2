#!/usr/bin/env python3
"""Simple portal scraper for HydraCam saved HTML.

Reads a saved sessions listing HTML file (default: evidence/portal_sessions.html),
extracts session detail links containing "quad-<digits>", extracts media asset
URLs (img/src and anchor hrefs with media extensions), writes lists to
`evidence/session_links.txt` and `evidence/portal_asset_urls.txt`, and can
optionally download session detail pages into `evidence/session_pages/`.

This script uses only the Python standard library so it can run in minimal
environments.
"""

from __future__ import annotations

import argparse
import os
import re
import sys
from html.parser import HTMLParser
from pathlib import Path
from typing import List
from urllib.parse import urljoin
from urllib.request import urlopen, Request


class LinkExtractor(HTMLParser):
    def __init__(self) -> None:
        super().__init__()
        self.hrefs: List[str] = []
        self.srcs: List[str] = []

    def handle_starttag(self, tag, attrs):
        attrs_map = {k: v for k, v in attrs}
        if tag == "a" and "href" in attrs_map:
            self.hrefs.append(attrs_map["href"])
        if tag in ("img", "source") and "src" in attrs_map:
            self.srcs.append(attrs_map["src"])


def sanitize_filename(s: str) -> str:
    return re.sub(r"[^0-9A-Za-z._-]", "_", s)


def write_list(path: Path, items: List[str]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("\n".join(items), encoding="utf-8")


def download_url(url: str, dest: Path) -> None:
    dest.parent.mkdir(parents=True, exist_ok=True)
    req = Request(url, headers={"User-Agent": "hydracam-scraper/1.0"})
    with urlopen(req, timeout=30) as resp:
        data = resp.read()
    dest.write_bytes(data)


def main(argv: List[str] | None = None) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", default="evidence/portal_sessions.html")
    parser.add_argument(
        "--base", default=None, help="Base URL to resolve relative links"
    )
    parser.add_argument("--out-dir", default="evidence", help="Output directory")
    parser.add_argument(
        "--download-pages", action="store_true", help="Download session detail pages"
    )
    args = parser.parse_args(argv)

    input_path = Path(args.input)
    out_dir = Path(args.out_dir)

    if not input_path.exists():
        print(
            f"Input file {input_path} not found. Save the portal page as this file and retry."
        )
        return 2

    html = input_path.read_text(encoding="utf-8", errors="ignore")
    extractor = LinkExtractor()
    extractor.feed(html)

    # Collect candidate session links (hrefs containing quad-<digits>)
    session_links = []
    for h in extractor.hrefs:
        if re.search(r"quad-\d+", h):
            session_links.append(h)

    # Collect media urls from hrefs and srcs (common extensions)
    media_ext = re.compile(r"\.(jpg|jpeg|png|gif|mp4|mov|webm)(\?|$)", re.I)
    asset_urls = []
    for h in extractor.hrefs + extractor.srcs:
        if media_ext.search(h):
            asset_urls.append(h)

    # Resolve relative links if base provided
    base = args.base
    if base:
        session_links = [urljoin(base, s) for s in session_links]
        asset_urls = [urljoin(base, a) for a in asset_urls]

    # Deduplicate and sort
    session_links = sorted(dict.fromkeys(session_links))
    asset_urls = sorted(dict.fromkeys(asset_urls))

    # Write outputs
    write_list(out_dir / "session_links.txt", session_links)
    write_list(out_dir / "portal_asset_urls.txt", asset_urls)

    print(
        f"Found {len(session_links)} session links and {len(asset_urls)} media asset URLs"
    )
    print(
        f"Wrote {out_dir / 'session_links.txt'} and {out_dir / 'portal_asset_urls.txt'}"
    )

    if args.download_pages and session_links:
        pages_dir = out_dir / "session_pages"
        pages_dir.mkdir(parents=True, exist_ok=True)
        for url in session_links:
            if not (url.startswith("http://") or url.startswith("https://")):
                if not base:
                    print(f"Skipping download of relative URL {url} (no base provided)")
                    continue
                full = urljoin(base, url)
            else:
                full = url
            fname = sanitize_filename(url)
            dest = pages_dir / f"{fname}.html"
            try:
                print(f"Downloading {full} -> {dest}")
                download_url(full, dest)
            except Exception as exc:  # pragma: no cover - network errors
                print(f"Failed to download {full}: {exc}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
#!/usr/bin/env python3
"""Simple portal scraper: extract session detail links containing 'quad-' and asset URLs from saved HTML.

Usage:
  python3 scripts/portal_scraper.py [--base BASE_URL] [input.html]

Outputs to `evidence/session_links.txt` and `evidence/portal_asset_urls.txt`.
"""

import sys
import re
from pathlib import Path
from urllib.parse import urljoin


def extract_links(html_text):
    # find hrefs that include quad-<digits>
    hrefs = set()
    for m in re.finditer(r'href=["\']([^"\']*quad-[0-9][^"\']*)', html_text, re.I):
        hrefs.add(m.group(1))
    return sorted(hrefs)


def extract_asset_urls(html_text):
    urls = set()
    # absolute urls to common media extensions
    for m in re.finditer(
        r'(https?://[^"\'<>\s]+\.(?:jpg|jpeg|png|gif|mp4|mov|webm))', html_text, re.I
    ):
        urls.add(m.group(1))
    # relative urls to media
    for m in re.finditer(
        r'href=["\']([^"\']*\.(?:jpg|jpeg|png|gif|mp4|mov|webm)[^"\']*)',
        html_text,
        re.I,
    ):
        urls.add(m.group(1))
    for m in re.finditer(
        r'src=["\']([^"\']*\.(?:jpg|jpeg|png|gif|mp4|mov|webm)[^"\']*)', html_text, re.I
    ):
        urls.add(m.group(1))
    return sorted(urls)


def main():
    args = sys.argv[1:]
    base = None
    infile = Path("evidence/portal_sessions.html")
    if "--base" in args:
        i = args.index("--base")
        if i + 1 < len(args):
            base = args[i + 1]
            # remove from args
            args.pop(i)
            args.pop(i)
    if args:
        infile = Path(args[0])

    if not infile.exists():
        print(f"Input file {infile} not found", file=sys.stderr)
        sys.exit(2)

    html = infile.read_text(encoding="utf-8", errors="ignore")

    links = extract_links(html)
    assets = extract_asset_urls(html)

    out_links = Path("evidence/session_links.txt")
    out_assets = Path("evidence/portal_asset_urls.txt")
    out_links.parent.mkdir(parents=True, exist_ok=True)

    with out_links.open("w", encoding="utf-8") as f:
        for l in links:
            if base and l.startswith("/"):
                f.write(urljoin(base, l) + "\n")
            else:
                f.write(
                    (urljoin(base, l) if base and not l.startswith("http") else l)
                    + "\n"
                )

    with out_assets.open("w", encoding="utf-8") as f:
        for a in assets:
            if base and a.startswith("/"):
                f.write(urljoin(base, a) + "\n")
            else:
                f.write(
                    (urljoin(base, a) if base and not a.startswith("http") else a)
                    + "\n"
                )

    print(
        f"Wrote {out_links} ({len(links)} links) and {out_assets} ({len(assets)} assets)"
    )


if __name__ == "__main__":
    main()
