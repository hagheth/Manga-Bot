import re
import httpx
from bs4 import BeautifulSoup

MANGADEX_API = "https://api.mangadex.org"


def _title_similarity(query: str, manga: dict) -> float:
    """Score a manga result against the search query using all its titles (0–1)."""
    q_raw = query.lower().strip()
    q_words = set(q_raw.split())
    attrs = manga["attributes"]
    all_titles = list(attrs.get("title", {}).values())
    for alt in attrs.get("altTitles", []):
        all_titles.extend(alt.values())
    best = 0.0
    for t in all_titles:
        t_norm = t.lower().strip()
        t_words = set(t_norm.split())
        if not t_words:
            continue
        # Word-overlap score
        word_score = len(q_words & t_words) / max(len(q_words), len(t_words))
        # Substring score: "onepiece" inside "one piece" (stripped spaces)
        t_nospace = t_norm.replace(" ", "").replace("-", "")
        q_nospace = q_raw.replace(" ", "").replace("-", "")
        sub_score = 1.0 if q_nospace == t_nospace else (0.8 if q_nospace in t_nospace or t_nospace in q_nospace else 0.0)
        score = max(word_score, sub_score)
        if score > best:
            best = score
    return best


def fetch_manga_info(title: str) -> dict | None:
    """Search MangaDex for a manga by title. Returns {title, synopsis, cover_url} or None."""
    try:
        with httpx.Client(timeout=10) as client:
            r = client.get(f"{MANGADEX_API}/manga", params={
                "title": title,
                "limit": 10,
                "includes[]": ["cover_art", "author"],
                "contentRating[]": ["safe", "suggestive"],
                "order[relevance]": "desc",
            })
            r.raise_for_status()
            data = r.json().get("data", [])
            if not data:
                return None

            # Filter out doujinshi
            candidates = [
                m for m in data
                if "doujinshi" not in [
                    t["attributes"]["name"].get("en", "").lower()
                    for t in m["attributes"].get("tags", [])
                ]
            ]
            if not candidates:
                candidates = data

            manga = max(candidates, key=lambda m: _title_similarity(title, m))
            manga_id = manga["id"]
            attrs = manga["attributes"]

            # Prefer English title, then romanised Japanese, then first available
            titles = attrs.get("title", {})
            found_title = titles.get("en") or titles.get("ja-ro") or next(iter(titles.values()), title)

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

            total_chapters = attrs.get("lastChapter") or None
            status = attrs.get("status", "").capitalize() or None

            manga_url = f"https://mangadex.org/title/{manga_id}"

            return {"title": found_title, "synopsis": synopsis, "cover_url": cover_url,
                    "total_chapters": total_chapters, "status": status, "manga_url": manga_url}

    except Exception:
        return None

HEADERS = {
    "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/120.0.0.0 Safari/537.36"
}

def fetch_mangafire_url(title: str) -> str | None:
    """
    Try to get a reading link for a manga title.
    MangaFire is JS-rendered so we fall back to MangaDex which has a stable URL.
    """
    info = fetch_manga_info(title)
    if info and info.get("manga_url"):
        return info["manga_url"]
    return None

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
