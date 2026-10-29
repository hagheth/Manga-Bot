from db import supabase


def add_manga(user_id: int, title: str, url: str = None, chapter: int = 0):
    data = {"user_id": user_id, "title": title, "url": url, "chapter": chapter}
    result = supabase.table("manga").insert(data).execute()
    return result.data[0] if result.data else None


def list_manga(user_id: int, status: str = None):
    query = supabase.table("manga").select("*").eq("user_id", user_id)
    if status:
        query = query.eq("status", status)
    result = query.order("created_at", desc=True).execute()
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
