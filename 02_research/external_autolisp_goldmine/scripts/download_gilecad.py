#!/usr/bin/env python3
"""Download gileCAD AutoLISP resources into an isolated research folder.

This is a research import only. It does not touch production toolkit files and
does not execute any downloaded AutoLISP.
"""

from __future__ import annotations

import re
import sys
import zipfile
from dataclasses import dataclass
from datetime import datetime
from html.parser import HTMLParser
from pathlib import Path
from urllib.error import HTTPError, URLError
from urllib.parse import unquote, urljoin, urlparse
from urllib.request import Request, urlopen


SOURCE_URL = "https://gilecad.azurewebsites.net/Lisp.aspx"
DOWNLOAD_EXTENSIONS = {".lsp", ".zip", ".dcl", ".txt", ".vlx", ".fas"}
SOURCE_EXTENSIONS = {".lsp", ".dcl", ".txt"}
COMPILED_EXTENSIONS = {".vlx", ".fas"}
RESOURCE_PATH_MARKERS = ("/LISP/", "/Lisp/", "/Download/", "/downloads/")
USER_AGENT = "Brightspeed-AutoLISP-Research-Audit/1.0"

ROOT = Path(__file__).resolve().parents[1]
RAW_PAGES = ROOT / "raw_pages"
RAW_LSP = ROOT / "raw_lsp"
RAW_ZIPS = ROOT / "raw_zips"
RAW_COMPILED = ROOT / "raw_compiled"
EXTRACTED = ROOT / "extracted"
NOTES = ROOT / "notes"


class LinkParser(HTMLParser):
    """Collect simple links from HTML attributes."""

    def __init__(self) -> None:
        super().__init__()
        self.links: list[str] = []

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        for name, value in attrs:
            if name.lower() in {"href", "src"} and value:
                self.links.append(value)


@dataclass
class ManifestEntry:
    url: str
    local_path: str
    status: str
    error: str = ""


def ensure_dirs() -> None:
    for folder in (RAW_PAGES, RAW_LSP, RAW_ZIPS, RAW_COMPILED, EXTRACTED, NOTES):
        folder.mkdir(parents=True, exist_ok=True)


def fetch_bytes(url: str) -> bytes:
    request = Request(url, headers={"User-Agent": USER_AGENT})
    with urlopen(request, timeout=45) as response:
        return response.read()


def decode_page(data: bytes) -> str:
    for encoding in ("utf-8", "latin-1", "cp1252"):
        try:
            return data.decode(encoding)
        except UnicodeDecodeError:
            continue
    return data.decode("utf-8", errors="replace")


def is_same_site(url: str, source_netloc: str) -> bool:
    parsed = urlparse(url)
    return parsed.scheme in {"http", "https"} and parsed.netloc.lower() == source_netloc


def normalize_link(link: str, base_url: str) -> str | None:
    link = link.strip()
    if not link or link.startswith(("#", "mailto:", "javascript:")):
        return None
    return urljoin(base_url, link)


def has_downloadable_extension(url: str) -> bool:
    return Path(unquote(urlparse(url).path)).suffix.lower() in DOWNLOAD_EXTENSIONS


def has_resource_marker(url: str) -> bool:
    path = unquote(urlparse(url).path)
    return any(marker in path for marker in RESOURCE_PATH_MARKERS)


def discover_resource_urls(html: str, base_url: str) -> list[str]:
    parser = LinkParser()
    parser.feed(html)

    source_netloc = urlparse(base_url).netloc.lower()
    urls: set[str] = set()

    for raw_link in parser.links:
        url = normalize_link(raw_link, base_url)
        if not url or not is_same_site(url, source_netloc):
            continue
        if has_downloadable_extension(url) or has_resource_marker(url):
            if has_downloadable_extension(url):
                urls.add(url)

    # Some ASP.NET pages leave interesting URLs in script text or attributes that
    # are not standard href/src attributes.
    quoted_urls = re.findall(r"""["']([^"']+\.(?:lsp|zip|dcl|txt|vlx|fas)(?:\?[^"']*)?)["']""", html, re.I)
    for raw_link in quoted_urls:
        url = normalize_link(raw_link, base_url)
        if url and is_same_site(url, source_netloc) and has_downloadable_extension(url):
            urls.add(url)

    return sorted(urls)


def safe_filename_from_url(url: str) -> str:
    parsed = urlparse(url)
    name = Path(unquote(parsed.path)).name or "download"
    name = re.sub(r"[^A-Za-z0-9._ -]+", "_", name).strip(" .")
    if not name:
        name = "download"
    if parsed.query:
        query_suffix = re.sub(r"[^A-Za-z0-9._-]+", "_", parsed.query).strip("._-")
        if query_suffix:
            stem = Path(name).stem
            suffix = Path(name).suffix
            name = f"{stem}_{query_suffix}{suffix}"
    return name


def destination_for(url: str) -> Path:
    suffix = Path(unquote(urlparse(url).path)).suffix.lower()
    filename = safe_filename_from_url(url)
    if suffix == ".zip":
        return RAW_ZIPS / filename
    if suffix in COMPILED_EXTENSIONS:
        return RAW_COMPILED / filename
    return RAW_LSP / filename


def unique_path(path: Path) -> Path:
    if not path.exists():
        return path
    index = 2
    while True:
        candidate = path.with_name(f"{path.stem}_{index}{path.suffix}")
        if not candidate.exists():
            return candidate
        index += 1


def write_manifest(entries: list[ManifestEntry], resource_count: int, zip_count: int) -> None:
    path = NOTES / "DOWNLOAD_MANIFEST.md"
    lines = [
        "# gileCAD Download Manifest",
        "",
        f"- Source: {SOURCE_URL}",
        f"- Generated: {datetime.now().isoformat(timespec='seconds')}",
        f"- Resource links discovered: {resource_count}",
        f"- ZIPs extracted: {zip_count}",
        "",
        "| URL | Local path | Status | Error |",
        "|---|---|---|---|",
    ]
    for entry in entries:
        error = entry.error.replace("|", "\\|").replace("\n", " ")
        lines.append(f"| {entry.url} | {entry.local_path} | {entry.status} | {error} |")
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def extract_zip(zip_path: Path) -> tuple[str, str]:
    target = EXTRACTED / zip_path.stem
    target.mkdir(parents=True, exist_ok=True)
    try:
        with zipfile.ZipFile(zip_path) as archive:
            for member in archive.infolist():
                member_path = Path(member.filename)
                if member_path.is_absolute() or ".." in member_path.parts:
                    raise ValueError(f"unsafe ZIP path: {member.filename}")
            archive.extractall(target)
        return "extracted", ""
    except (zipfile.BadZipFile, OSError, ValueError) as exc:
        return "extract_failed", str(exc)


def main() -> int:
    ensure_dirs()
    entries: list[ManifestEntry] = []

    try:
        page_bytes = fetch_bytes(SOURCE_URL)
    except (HTTPError, URLError, TimeoutError, OSError) as exc:
        entries.append(ManifestEntry(SOURCE_URL, "", "page_fetch_failed", str(exc)))
        write_manifest(entries, 0, 0)
        print("Failed to fetch source page. See notes/DOWNLOAD_MANIFEST.md.")
        return 1

    page_path = RAW_PAGES / "Lisp.aspx.html"
    page_path.write_bytes(page_bytes)
    html = decode_page(page_bytes)
    resources = discover_resource_urls(html, SOURCE_URL)
    entries.append(ManifestEntry(SOURCE_URL, str(page_path.relative_to(ROOT)), "saved"))

    for url in resources:
        dest = unique_path(destination_for(url))
        try:
            data = fetch_bytes(url)
            dest.write_bytes(data)
            entries.append(ManifestEntry(url, str(dest.relative_to(ROOT)), "downloaded"))
        except (HTTPError, URLError, TimeoutError, OSError) as exc:
            entries.append(ManifestEntry(url, str(dest.relative_to(ROOT)), "download_failed", str(exc)))

    extracted_count = 0
    for zip_path in sorted(RAW_ZIPS.glob("*.zip")):
        status, error = extract_zip(zip_path)
        if status == "extracted":
            extracted_count += 1
        entries.append(
            ManifestEntry(
                f"zip:{zip_path.name}",
                str((EXTRACTED / zip_path.stem).relative_to(ROOT)),
                status,
                error,
            )
        )

    write_manifest(entries, len(resources), extracted_count)

    downloaded_count = sum(1 for entry in entries if entry.status == "downloaded")
    print(f"resource_links={len(resources)}")
    print(f"files_downloaded={downloaded_count}")
    print(f"zips_extracted={extracted_count}")
    print(f"manifest={NOTES / 'DOWNLOAD_MANIFEST.md'}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
