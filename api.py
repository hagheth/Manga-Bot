import os
from dotenv import load_dotenv
import httpx
from urllib.parse import quote
from fastapi import FastAPI, HTTPException
from fastapi.responses import RedirectResponse, Response
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel

from manga_db import (
    add_manga, list_manga, search_manga, delete_manga,
    get_manga, update_chapter, update_status, update_note,
    update_url, update_title, update_rating, delete_manga_by_keyword,
    update_cover_url,
)
from ai import parse_message, chat_manga
from fetcher import fetch_manga_info, fetch_mangafire_url, fetch_manga_title

load_dotenv()

app = FastAPI(title="Manga Bookmark API")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

# ── Fixed user ID for single-user app ──────────────────────────────────────
USER_ID = int(os.getenv("APP_USER_ID", "0"))


# ── Models ─────────────────────────────────────────────────────────────────

class AddMangaRequest(BaseModel):
    title: str
    url: str | None = None
    chapter: int = 0

class AddMangaFromUrlRequest(BaseModel):
    url: str
    chapter: int = 0

class UpdateMangaRequest(BaseModel):
    chapter: int | None = None
    status: str | None = None
    rating: int | None = None
    note: str | None = None
    url: str | None = None
    title: str | None = None

class ChatRequest(BaseModel):
    message: str


# ── Manga routes ───────────────────────────────────────────────────────────

RENDER_BASE = "https://manga-bot-k4yd.onrender.com"

def _proxy_covers(manga_list: list) -> list:
    """Rewrite cover_url to go through our proxy (fixes CORS on web)."""
    result = []
    for m in manga_list:
        if m.get("cover_url"):
            m = dict(m)
            m["cover_url"] = f"{RENDER_BASE}/proxy/image?url={quote(m['cover_url'], safe='')}"
        result.append(m)
    return result


@app.get("/manga")
def get_manga_list(status: str | None = None):
    """List all manga, optionally filtered by status."""
    return _proxy_covers(list_manga(USER_ID, status))


@app.get("/manga/stats")
def get_stats():
    """Return reading stats summary."""
    all_manga = list_manga(USER_ID)
    total = len(all_manga)
    if not total:
        return {"total": 0}
    reading   = sum(1 for m in all_manga if m["status"] == "reading")
    completed = sum(1 for m in all_manga if m["status"] == "completed")
    dropped   = sum(1 for m in all_manga if m["status"] == "dropped")
    total_chapters = sum(m["chapter"] for m in all_manga)
    avg_chapters = round(total_chapters / total, 1)
    most_read = max(all_manga, key=lambda m: m["chapter"])
    rated = [m for m in all_manga if m.get("rating")]
    top_rated = max(rated, key=lambda m: m["rating"]) if rated else None
    return {
        "total": total,
        "reading": reading,
        "completed": completed,
        "dropped": dropped,
        "total_chapters": total_chapters,
        "avg_chapters": avg_chapters,
        "most_read": most_read,
        "top_rated": top_rated,
    }


@app.get("/manga/search")
def search(q: str):
    """Search manga by keyword."""
    return search_manga(USER_ID, q)


@app.get("/manga/{manga_id}")
def get_one(manga_id: int):
    m = get_manga(USER_ID, manga_id)
    if not m:
        raise HTTPException(status_code=404, detail="Manga not found")
    return _proxy_covers([m])[0]


@app.post("/manga", status_code=201)
def create_manga(body: AddMangaRequest):
    info = fetch_manga_info(body.title)
    cover_url = info.get("cover_url") if info else None
    url = body.url or fetch_mangafire_url(body.title)
    m = add_manga(USER_ID, body.title, url, body.chapter, cover_url=cover_url)
    if not m:
        raise HTTPException(status_code=500, detail="Failed to add manga")
    return m


@app.get("/manga/{manga_id}/suggest-link")
def suggest_link(manga_id: int):
    """Fetch and save a MangaFire link for a manga that has no URL."""
    m = get_manga(USER_ID, manga_id)
    if not m:
        raise HTTPException(status_code=404, detail="Manga not found")
    url = fetch_mangafire_url(m["title"])
    if not url:
        raise HTTPException(status_code=404, detail="No link found on MangaFire")
    update_url(USER_ID, manga_id, url)
    return {"url": url}


@app.post("/manga/from-url", status_code=201)
def create_manga_from_url(body: AddMangaFromUrlRequest):
    """Add a manga by providing a reading link — title and cover are auto-detected."""
    title = fetch_manga_title(body.url)
    if not title:
        raise HTTPException(status_code=422, detail="Could not determine manga title from the given URL")
    info = fetch_manga_info(title)
    cover_url = info.get("cover_url") if info else None
    canonical_title = (info.get("title") or title) if info else title
    m = add_manga(USER_ID, canonical_title, body.url, body.chapter, cover_url=cover_url)
    if not m:
        raise HTTPException(status_code=500, detail="Failed to add manga")
    return m


@app.post("/manga/backfill-covers", status_code=200)
def backfill_covers():
    """Fetch and save MangaDex cover URLs for all manga missing one."""
    mangas = list_manga(USER_ID)
    updated = []
    for m in mangas:
        if m.get("cover_url"):
            continue
        info = fetch_manga_info(m["title"])
        if info and info.get("cover_url"):
            update_cover_url(USER_ID, m["id"], info["cover_url"])
            updated.append(m["title"])
    return {"updated": updated}


@app.patch("/manga/{manga_id}")
def update_manga(manga_id: int, body: UpdateMangaRequest):
    m = get_manga(USER_ID, manga_id)
    if not m:
        raise HTTPException(status_code=404, detail="Manga not found")
    if body.chapter is not None:
        update_chapter(USER_ID, manga_id, body.chapter)
    if body.status is not None:
        update_status(USER_ID, manga_id, body.status)
    if body.rating is not None:
        update_rating(USER_ID, manga_id, body.rating)
    if body.note is not None:
        update_note(USER_ID, manga_id, body.note)
    if body.url is not None:
        update_url(USER_ID, manga_id, body.url)
    if body.title is not None:
        update_title(USER_ID, manga_id, body.title)
    return get_manga(USER_ID, manga_id)


@app.delete("/manga/{manga_id}", status_code=204)
def remove_manga(manga_id: int):
    result = delete_manga(USER_ID, manga_id)
    if not result:
        raise HTTPException(status_code=404, detail="Manga not found")


# ── MangaDex info ──────────────────────────────────────────────────────────

@app.get("/mangainfo")
def manga_info(title: str):
    """Fetch cover + synopsis from MangaDex."""
    info = fetch_manga_info(title)
    if not info:
        raise HTTPException(status_code=404, detail="Not found on MangaDex")
    return info


@app.get("/proxy/image")
def proxy_image(url: str):
    """Proxy external images to avoid CORS issues on web."""
    try:
        with httpx.Client(timeout=15, follow_redirects=True) as client:
            r = client.get(url)
            r.raise_for_status()
            return Response(content=r.content, media_type=r.headers.get("content-type", "image/jpeg"))
    except Exception as e:
        raise HTTPException(status_code=404, detail=f"Image not found: {e}")


@app.get("/mangainfo/cover")
def manga_cover(title: str):
    """Redirect to the MangaDex cover image URL."""
    info = fetch_manga_info(title)
    if not info or not info.get("cover_url"):
        raise HTTPException(status_code=404, detail="Cover not found")
    return RedirectResponse(url=info["cover_url"])


# ── AI Chat ────────────────────────────────────────────────────────────────

@app.post("/chat")
def chat(body: ChatRequest):
    """
    Parse a natural language message.
    Returns the parsed intent + a friendly reply.
    The Flutter app shows the intent summary and asks the user to confirm
    before calling the relevant /manga endpoint.
    """
    mangas = list_manga(USER_ID)
    parsed = parse_message(body.message, mangas)
    intent = parsed.get("intent", "unknown")

    # For unknown / chat intents — return a conversational reply
    if intent in ("unknown", "chat"):
        reply, emotion = chat_manga(body.message, mangas)
        return {"intent": "unknown", "reply": reply, "emotion": emotion}

    # For read-only intents — resolve and return data immediately
    if intent == "stats":
        stats = get_stats()
        return {"intent": "stats", "data": stats, "reply": parsed.get("reply", "")}

    if intent == "list":
        status_filter = parsed.get("status")
        results = list_manga(USER_ID, status_filter)
        return {"intent": "list", "data": results, "reply": parsed.get("reply", "")}

    if intent == "search":
        kw = parsed.get("keyword") or parsed.get("title", "")
        results = search_manga(USER_ID, kw)
        return {"intent": "search", "data": results, "reply": parsed.get("reply", "")}

    if intent in ("suggest", "suggest_new"):
        reply, emotion = chat_manga(body.message, mangas)
        return {"intent": intent, "reply": reply, "emotion": emotion}

    # For write intents — return parsed data for Flutter to confirm
    title = parsed.get("title", "")
    if intent == "add":
        confirm_msg = f"Add **{title}** to your list?"
    elif intent in ("update_chapter", "update"):
        chapter = parsed.get("chapter")
        status = parsed.get("status")
        parts = []
        if chapter is not None: parts.append(f"chapter {chapter}")
        if status: parts.append(status)
        confirm_msg = f"Update **{title}** — {', '.join(parts)}?" if parts else f"Update **{title}**?"
    elif intent == "update_status":
        confirm_msg = f"Mark **{title}** as {parsed.get('status', 'updated')}?"
    elif intent == "delete":
        confirm_msg = f"Remove **{title}** from your list?"
    else:
        confirm_msg = parsed.get("reply", "Confirm this action?")
    return {
        "intent": intent,
        "parsed": parsed,
        "reply": confirm_msg,
    }


# ── Flutter web app — MUST be last so API routes take priority ─────────────
import os as _os
if _os.path.isdir("flutter_web"):
    app.mount("/", StaticFiles(directory="flutter_web", html=True), name="flutter")
