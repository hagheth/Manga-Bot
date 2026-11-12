"""
Upstash Redis cache via REST API.
Used to cache MangaDex search results and AI recommendations.
"""
import os
import json
import httpx

_URL = os.getenv("UPSTASH_REDIS_REST_URL")
_TOKEN = os.getenv("UPSTASH_REDIS_REST_TOKEN")
_HEADERS = {"Authorization": f"Bearer {_TOKEN}"} if _TOKEN else {}


def _pipeline(commands: list) -> list:
    if not _URL:
        return []
    try:
        r = httpx.post(f"{_URL}/pipeline", headers=_HEADERS, json=commands, timeout=3)
        return r.json()
    except Exception:
        return []


def cache_get(key: str):
    """Return cached value or None."""
    results = _pipeline([["GET", key]])
    if not results:
        return None
    result = results[0].get("result")
    if result is None:
        return None
    try:
        return json.loads(result)
    except Exception:
        return None


def cache_set(key: str, value, ex: int = 3600):
    """Store value with TTL in seconds (default 1 hour)."""
    try:
        encoded = json.dumps(value, ensure_ascii=False)
        _pipeline([["SET", key, encoded, "EX", ex]])
    except Exception:
        pass
