import re
import httpx
from bs4 import BeautifulSoup

HEADERS = {
    "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/120.0.0.0 Safari/537.36"
}

# Sites that render titles with JavaScript — fall back to URL slug
JS_RENDERED_SITES = ["mangafire.to", "mangasee123.com", "manganato.com"]


def fetch_manga_title(url: str) -> str | None:
    """Try to extract manga title from a URL using page metadata or URL slug."""

    # For JS-rendered sites, extract title from URL slug directly
    for site in JS_RENDERED_SITES:
        if site in url:
            return title_from_slug(url)

    try:
        with httpx.Client(headers=HEADERS, timeout=10, follow_redirects=True) as client:
            response = client.get(url)
            response.raise_for_status()

        soup = BeautifulSoup(response.text, "html.parser")

        # Try Open Graph title first (most sites use this)
        og_title = soup.find("meta", property="og:title")
        if og_title and og_title.get("content"):
            cleaned = clean_title(og_title["content"])
            if not is_generic_title(cleaned):
                return cleaned

        # Fallback to <title> tag
        if soup.title and soup.title.string:
            cleaned = clean_title(soup.title.string)
            if not is_generic_title(cleaned):
                return cleaned

        # Last resort: extract from URL slug
        return title_from_slug(url)

    except Exception:
        return title_from_slug(url)


def title_from_slug(url: str) -> str | None:
    """Extract a readable title from the URL path slug."""
    # Match patterns like /title/w5qk7-under-ninjaa or /manga/one-piece
    match = re.search(r"/(?:title|manga|series|comic)/[\w\d]+-([a-z0-9-]+)", url)
    if match:
        slug = match.group(1)
        return slug.replace("-", " ").title()

    # Fallback: grab the last meaningful path segment
    path = url.rstrip("/").split("/")
    for segment in reversed(path):
        if segment and not segment.startswith("chapter") and len(segment) > 3:
            cleaned = re.sub(r"^[\w\d]+-", "", segment)  # remove ID prefix like w5qk7-
            return cleaned.replace("-", " ").title()

    return None


def clean_title(raw: str) -> str:
    """Remove common site name suffixes from titles."""
    site_names = [
        "MangaPlus", "MangaDex", "MangaFire", "MangaSee", "Manganato",
        "Bato.to", "MangaRock", "MangaFox", "MangaKakalot", "MangaNelo",
    ]
    title = raw.strip()
    for name in site_names:
        for sep in [" - ", " | ", " – "]:
            title = re.sub(re.escape(sep + name), "", title, flags=re.IGNORECASE)
            title = re.sub(re.escape(name + sep), "", title, flags=re.IGNORECASE)
    return title.strip()


def is_generic_title(title: str) -> bool:
    """Return True if the title is just a site name, not a manga title."""
    generic = [
        "read manga online free", "manga online", "read manga free",
        "mangafire", "mangadex", "mangaplus", "manganato",
    ]
    return any(g in title.lower() for g in generic)
