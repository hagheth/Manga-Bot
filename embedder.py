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
    result = get_embeddings_batch([text])
    return result[0] if result else None


def get_embeddings_batch(texts: list[str]) -> list[list[float]] | None:
    """Return embeddings for a list of texts in one API call."""
    if not HF_TOKEN:
        logger.warning("HUGGINGFACE_API_TOKEN not set — skipping embedding")
        return None
    try:
        with httpx.Client(timeout=60) as client:
            r = client.post(
                HF_URL,
                headers={"Authorization": f"Bearer {HF_TOKEN}"},
                json={"inputs": texts, "options": {"wait_for_model": True}},
            )
            logger.info(f"HF API status={r.status_code} body[:120]={r.text[:120]!r}")
            result = r.json()
            # HF returns error dict when model is loading or on error
            if isinstance(result, dict):
                logger.warning(f"HF API returned dict (not embeddings): {result}")
                return None
            if not result or not isinstance(result, list):
                logger.warning(f"HF API unexpected response type: {type(result)}")
                return None
            # For batch: result is [[vec], [vec], ...] or [[float...], [float...]]
            first = result[0]
            if isinstance(first, list) and first and isinstance(first[0], list):
                return [row[0] for row in result]
            return result
    except Exception as e:
        logger.warning(f"Batch embedding failed: {e}")
        return None


def manga_text(manga: dict) -> str:
    """Build a descriptive text string from a manga record for embedding."""
    parts = [manga.get("title", "")]
    if manga.get("status"):
        parts.append(f"status: {manga['status']}")
    if manga.get("notes"):
        parts.append(manga["notes"])
    return " | ".join(p for p in parts if p)
