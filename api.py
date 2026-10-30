import os
from dotenv import load_dotenv
from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel

from manga_db import (
    add_manga, list_manga, search_manga, delete_manga,
    get_manga, update_chapter, update_status, update_note,
    update_url, update_title, update_rating, delete_manga_by_keyword,
)
from ai import parse_message, chat_manga
from fetcher import fetch_manga_info

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

@app.get("/manga")
def get_manga_list(status: str | None = None):
    """List all manga, optionally filtered by status."""
    return list_manga(USER_ID, status)


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
    return m


@app.post("/manga", status_code=201)
def create_manga(body: AddMangaRequest):
    m = add_manga(USER_ID, body.title, body.url, body.chapter)
    if not m:
        raise HTTPException(status_code=500, detail="Failed to add manga")
    return m


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
    if intent == "unknown":
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
    return {
        "intent": intent,
        "parsed": parsed,
        "reply": parsed.get("reply", ""),
    }
