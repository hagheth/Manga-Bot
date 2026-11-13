"""
Embedding generation via HuggingFace Inference API.
Model: sentence-transformers/all-MiniLM-L6-v2 (384 dimensions, free).
"""
import os
import logging
import httpx

logger = logging.getLogger(__name__)

HF_TOKEN = os.getenv("HUGGINGFACE_API_TOKEN")
HF_URL = "https://api-inference.huggingface.co/pipeline/feature-extraction/sentence-transformers/all-MiniLM-L6-v2"


def get_embedding(text: str) -> list[float] | None:
    """Return a 384-dim embedding vector for the given text, or None on failure."""
    if not HF_TOKEN:
        logger.warning("HUGGINGFACE_API_TOKEN not set — skipping embedding")
        return None
    try:
        with httpx.Client(timeout=15) as client:
            r = client.post(
                HF_URL,
                headers={"Authorization": f"Bearer {HF_TOKEN}"},
                json={"inputs": text, "options": {"wait_for_model": True}},
            )
            r.raise_for_status()
            result = r.json()
            # HF returns nested list for batch; flatten if needed
            if isinstance(result[0], list):
                return result[0]
            return result
    except Exception as e:
        logger.warning(f"Embedding failed for text '{text[:40]}...': {e}")
        return None


def manga_text(manga: dict) -> str:
    """Build a descriptive text string from a manga record for embedding."""
    parts = [manga.get("title", "")]
    if manga.get("status"):
        parts.append(f"status: {manga['status']}")
    if manga.get("notes"):
        parts.append(manga["notes"])
    return " | ".join(p for p in parts if p)
