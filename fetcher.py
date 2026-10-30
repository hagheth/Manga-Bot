import re
import httpx
from bs4 import BeautifulSoup

MANGADEX_API = "https://api.mangadex.org"


def fetch_manga_info(title: str) -> dict | None:
    """Search MangaDex for a manga by title. Returns {title, synopsis, cover_url} or None."""
    try:
        with httpx.Client(timeout=10) as client:
            r = client.get(f"{MANGADEX_API}/manga", params={
                "title": title,
                "limit": 1,
                "includes[]": "cover_art",
                "contentRating[]": ["safe", "suggestive", "erotica", "pornographic"],
            })
            r.raise_for_status()
            data = r.json().get("data", [])
            if not data:
                return None

            manga = data[0]
            manga_id = manga["id"]
            attrs = manga["attributes"]

            titles = attrs.get("title", {})
            found_title = titles.get("en") or next(iter(titles.values()), title)

            desc = attrs.get("description", {})
            synopsis = desc.get("en") or next(iter(desc.values()), "")
            if synopsis and len(synopsis) > 200:
                synopsis = synopsis[:200].rstrip() + "..."

            cover_url = None
            for rel in manga.get("relationships", []):
                if rel["type"] == "cover_art":
                    filename = rel.get("attributes", {}).get("fileName")
                    if filename:
                        cover_url = f"https://uploads.mangadex.org/covers/{manga_id}/{filename}.256.jpg"
                    break

            return {"title": found_title, "synopsis": synopsis, "cover_url": cover_url}

    except Exception:
        return None

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
