"""
Chapter update checker + FCM push notification sender.
Called by POST /check-chapters (triggered by cron-job.org every 6 hours).
"""
import os
import logging
import httpx

logger = logging.getLogger(__name__)

MANGADEX_API = "https://api.mangadex.org"


def _latest_chapter_from_mangadex(title: str) -> str | None:
    """Query MangaDex for the latest chapter number of a manga by title."""
    try:
        with httpx.Client(timeout=10) as client:
            r = client.get(f"{MANGADEX_API}/manga", params={
                "title": title, "limit": 5,
                "contentRating[]": ["safe", "suggestive"],
                "order[relevance]": "desc",
            })
            r.raise_for_status()
            data = r.json().get("data", [])
            if not data:
                return None
            attrs = data[0].get("attributes", {})
            return attrs.get("lastChapter")
    except Exception as e:
        logger.warning(f"MangaDex lookup failed for '{title}': {e}")
        return None


def _send_fcm(tokens: list[str], title: str, body: str):
    """Send a push notification via FCM HTTP v1 API."""
    import json
    import google.auth
    import google.auth.transport.requests
    from google.oauth2 import service_account

    # Prefer JSON string env var (safe for Render); fall back to file path
    sa_json = os.getenv("FIREBASE_SERVICE_ACCOUNT_JSON")
    sa_file = os.getenv("FIREBASE_SERVICE_ACCOUNT_PATH", "firebase_service_account.json")

    try:
        if sa_json:
            info = json.loads(sa_json)
            credentials = service_account.Credentials.from_service_account_info(
                info,
                scopes=["https://www.googleapis.com/auth/firebase.messaging"],
            )
            project_id = info.get("project_id")
        else:
            credentials, project_id = google.auth.load_credentials_from_file(
                sa_file,
                scopes=["https://www.googleapis.com/auth/firebase.messaging"],
            )
        credentials.refresh(google.auth.transport.requests.Request())
        access_token = credentials.token
    except Exception as e:
        logger.error(f"Failed to load Firebase credentials: {e}")
        return

    url = f"https://fcm.googleapis.com/v1/projects/{project_id}/messages:send"
    headers = {"Authorization": f"Bearer {access_token}", "Content-Type": "application/json"}

    sent, failed = 0, 0
    for token in tokens:
        payload = {
            "message": {
                "token": token,
                "notification": {"title": title, "body": body},
                "android": {"priority": "high"},
                "apns": {"payload": {"aps": {"sound": "default"}}},
            }
        }
        try:
            with httpx.Client(timeout=10) as client:
                res = client.post(url, json=payload, headers=headers)
                if res.status_code == 200:
                    sent += 1
                else:
                    logger.warning(f"FCM error for token ..{token[-6:]}: {res.text}")
                    failed += 1
        except Exception as e:
            logger.warning(f"FCM request failed: {e}")
            failed += 1

    logger.info(f"FCM: {sent} sent, {failed} failed")


def check_and_notify(manga_list: list, device_tokens: list[str]) -> dict:
    """
    For each manga with status 'reading', check if MangaDex has a newer chapter.
    Sends one batched notification listing all updated manga.
    Returns a summary dict.
    """
    if not device_tokens:
        logger.info("No device tokens — skipping notifications")
        return {"checked": 0, "updates": []}

    updates = []
    reading = [m for m in manga_list if m.get("status") == "reading"]

    for manga in reading:
        title = manga.get("title", "")
        saved_chapter = manga.get("chapter", 0)
        try:
            saved_num = float(saved_chapter) if saved_chapter else 0
        except (ValueError, TypeError):
            saved_num = 0

        latest_str = _latest_chapter_from_mangadex(title)
        if latest_str is None:
            continue

        try:
            latest_num = float(latest_str)
        except (ValueError, TypeError):
            continue

        if latest_num > saved_num:
            updates.append({
                "title": title,
                "saved": saved_chapter,
                "latest": latest_str,
            })
            logger.info(f"New chapter: {title} — saved ch{saved_chapter}, latest ch{latest_str}")

    if updates:
        if len(updates) == 1:
            u = updates[0]
            notif_title = f"New chapter: {u['title']}"
            notif_body = f"Chapter {u['latest']} is out! You're on ch{u['saved']}."
        else:
            titles = ", ".join(u["title"] for u in updates[:3])
            extra = f" (+{len(updates) - 3} more)" if len(updates) > 3 else ""
            notif_title = f"{len(updates)} manga updated"
            notif_body = f"{titles}{extra} have new chapters!"

        _send_fcm(device_tokens, notif_title, notif_body)

    return {"checked": len(reading), "updates": updates}
