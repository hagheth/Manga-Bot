from db import supabase


def add_manga(user_id: int, title: str, url: str = None, chapter: int = 0, cover_url: str = None):
    data = {"user_id": user_id, "title": title, "url": url, "chapter": chapter}
    if cover_url:
        data["cover_url"] = cover_url
    result = supabase.table("manga").insert(data).execute()
    return result.data[0] if result.data else None


def update_cover_url(user_id: int, manga_id: int, cover_url: str):
    result = (
        supabase.table("manga")
        .update({"cover_url": cover_url})
        .eq("id", manga_id)
        .eq("user_id", user_id)
        .execute()
    )
    return result.data[0] if result.data else None


def list_manga(user_id: int, status: str = None):
    query = supabase.table("manga").select("*").eq("user_id", user_id)
    if status:
        query = query.eq("status", status)
    result = query.order("updated_at", desc=True).execute()
    return result.data


def search_manga(user_id: int, keyword: str):
    result = (
        supabase.table("manga")
        .select("*")
        .eq("user_id", user_id)
        .ilike("title", f"%{keyword}%")
        .execute()
    )
    return result.data


def delete_manga_by_keyword(user_id: int, keyword: str) -> list:
    """Delete all manga whose title contains keyword. Returns deleted titles."""
    matches = search_manga(user_id, keyword)
    deleted = []
    for m in matches:
        supabase.table("manga").delete().eq("id", m["id"]).eq("user_id", user_id).execute()
        deleted.append(m["title"])
    return deleted


def delete_manga(user_id: int, manga_id: int):
    result = (
        supabase.table("manga")
        .delete()
        .eq("id", manga_id)
        .eq("user_id", user_id)
        .execute()
    )
    return result.data


def get_manga(user_id: int, manga_id: int):
    result = (
        supabase.table("manga")
        .select("*")
        .eq("id", manga_id)
        .eq("user_id", user_id)
        .execute()
    )
    return result.data[0] if result.data else None


def update_chapter(user_id: int, manga_id: int, chapter: int):
    result = (
        supabase.table("manga")
        .update({"chapter": chapter, "updated_at": "now()"})
        .eq("id", manga_id)
        .eq("user_id", user_id)
        .execute()
    )
    return result.data[0] if result.data else None


def update_status(user_id: int, manga_id: int, status: str):
    result = (
        supabase.table("manga")
        .update({"status": status, "updated_at": "now()"})
        .eq("id", manga_id)
        .eq("user_id", user_id)
        .execute()
    )
    return result.data[0] if result.data else None


def update_rating(user_id: int, manga_id: int, rating: int):
    result = (
        supabase.table("manga")
        .update({"rating": rating, "updated_at": "now()"})
        .eq("id", manga_id)
        .eq("user_id", user_id)
        .execute()
    )
    return result.data[0] if result.data else None


def update_title(user_id: int, manga_id: int, new_title: str):
    result = (
        supabase.table("manga")
        .update({"title": new_title, "updated_at": "now()"})
        .eq("id", manga_id)
        .eq("user_id", user_id)
        .execute()
    )
    return result.data[0] if result.data else None


def update_url(user_id: int, manga_id: int, url: str):
    result = (
        supabase.table("manga")
        .update({"url": url, "updated_at": "now()"})
        .eq("id", manga_id)
        .eq("user_id", user_id)
        .execute()
    )
    return result.data[0] if result.data else None


def update_note(user_id: int, manga_id: int, note: str):
    result = (
        supabase.table("manga")
        .update({"notes": note, "updated_at": "now()"})
        .eq("id", manga_id)
        .eq("user_id", user_id)
        .execute()
    )
    return result.data[0] if result.data else None


# ── Device tokens (push notifications) ────────────────────────────────────────

def save_device_token(token: str):
    """Upsert a device token into the device_tokens table."""
    supabase.table("device_tokens").upsert({"token": token}).execute()


def get_all_device_tokens() -> list[str]:
    """Return all stored FCM device tokens."""
    result = supabase.table("device_tokens").select("token").execute()
    return [row["token"] for row in result.data]


# ── Vector embeddings (RAG) ────────────────────────────────────────────────────

def save_embedding(manga_id: int, embedding: list[float]):
    """Store a vector embedding for a manga row."""
    supabase.table("manga").update({"embedding": embedding}).eq("id", manga_id).execute()


def search_similar_manga(user_id: int, query_embedding: list[float], limit: int = 5) -> list:
    """Find the most semantically similar manga using pgvector cosine similarity."""
    result = supabase.rpc("match_manga", {
        "query_embedding": query_embedding,
        "match_user_id": user_id,
        "match_count": limit,
    }).execute()
    return result.data or []
