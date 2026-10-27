import json
import logging
import os
from groq import Groq
from dotenv import load_dotenv

logger = logging.getLogger(__name__)

load_dotenv()

client = Groq(api_key=os.getenv("GROQ_API_KEY"))

SYSTEM_PROMPT = """You are a manga bookmark assistant. The user will send a natural language message about their manga reading.

Your job is to extract the intent and data, then return a JSON response ONLY — no extra text.

Possible intents:
- "add": user wants to save a new manga
- "update_chapter": user is updating their reading progress
- "update_status": user wants to change status (reading/completed/on_hold/dropped)
- "search": user wants to find a manga
- "list": user wants to see their list
- "suggest": user wants to know what to read next from their existing list
- "suggest_new": user wants recommendations for NEW manga they haven't read yet (phrases like "suggest another", "recommend something new", "what else should I read", "based on my taste")
- "delete": user wants to remove one manga by title
- "delete_bulk": user wants to delete multiple manga matching keywords. Put ALL keywords in the "keyword" field as a comma-separated list (e.g. "mangafire,manga plus"). Never join them with "and".
- "note": user wants to add a note
- "unknown": can't determine intent

Return JSON in this exact format:
{
  "intent": "<intent>",
  "title": "<manga title or null>",
  "url": "<url or null>",
  "chapter": <chapter number or null>,
  "status": "<reading|completed|on_hold|dropped or null>",
  "keyword": "<search keyword or null>",
  "note": "<note text or null>",
  "reply": "<friendly short reply to user confirming what you understood>"
}

Rules:
- Extract chapter numbers from phrases like "chapter 1234", "ch1234", "until c1234", "ep 5"
- Detect status from phrases like "finished", "done", "completed", "dropped", "on hold", "paused", "currently reading"
- If user says "I've read X until chapter Y" or "I'm reading X at chY" → intent is always "update_chapter" (the bot will auto-add if not found)
- If user says "I've read X" with no chapter → intent is "add" with status "reading"
- If user says "I finished X" or "I completed X" → intent is "update_status" with status "completed", only if manga likely exists; otherwise "add" with status "completed"
- Keep reply short and friendly, 1 sentence max
- Always return valid JSON, nothing else"""


def parse_message(user_message: str, manga_list: list) -> dict:
    """Parse a natural language message and return structured intent + data."""

    # Give AI context about existing manga
    existing = ""
    if manga_list:
        titles = [f"#{m['id']} {m['title']} (ch{m['chapter']}, {m['status']})" for m in manga_list]
        existing = "\n\nUser's current manga list:\n" + "\n".join(titles)

    response = client.chat.completions.create(
        model="openai/gpt-oss-20b",
        messages=[
            {"role": "system", "content": SYSTEM_PROMPT + existing},
            {"role": "user", "content": user_message},
        ],
        max_tokens=300,
        temperature=0.1,
    )

    raw = response.choices[0].message.content.strip()

    # Extract JSON if wrapped in code block
    if "```" in raw:
        raw = raw.split("```")[1]
        if raw.startswith("json"):
            raw = raw[4:]

    return json.loads(raw)


def generate_tags(title: str, url: str = None) -> list[str]:
    """Ask AI to generate genre tags for a manga based on its title and URL."""
    context = f"Manga title: {title}"
    if url:
        context += f"\nURL: {url}"

    try:
        response = client.chat.completions.create(
            model="openai/gpt-oss-20b",
            messages=[{
                "role": "user",
                "content": (
                    f"{context}\n\n"
                    "Return 3-5 genre/theme tags for this manga as a JSON array of lowercase strings. "
                    "Examples: [\"action\", \"dark\", \"supernatural\"], [\"romance\", \"comedy\", \"school\"]. "
                    "Return ONLY the JSON array, nothing else."
                ),
            }],
            max_tokens=60,
            temperature=0.1,
        )
        raw = response.choices[0].message.content.strip()
        if "```" in raw:
            raw = raw.split("```")[1]
            if raw.startswith("json"):
                raw = raw[4:]
        tags = json.loads(raw)
        return [t.lower().strip() for t in tags if isinstance(t, str)][:5]
    except Exception as e:
        logger.warning(f"generate_tags failed: {e}")
        return []


def suggest_manga(manga_list: list, suggest_new: bool = False) -> str:
    """Ask AI to recommend what to read next or suggest new manga."""
    if not manga_list and not suggest_new:
        return "Your manga list is empty! Tell me about a manga you've been reading to add it."

    lines = []
    for m in manga_list:
        line = f"- {m['title']} (status: {m['status']}, chapter: {m['chapter']})"
        if m.get("notes"):
            line += f", notes: {m['notes']}"
        lines.append(line)

    list_text = "\n".join(lines) if lines else "No manga in list yet."

    if suggest_new:
        prompt = (
            "You are a manga expert. Based on this person's reading history:\n\n"
            + list_text
            + "\n\nRecommend 2-3 NEW manga titles they would enjoy (not already in their list). "
            "For each one give the title and one sentence why. Be friendly and concise, under 100 words."
        )
    else:
        prompt = (
            "You are a manga reading advisor. Here is my manga list:\n\n"
            + list_text
            + "\n\nSuggest which manga I should read next and why. "
            "Pick from reading or on_hold ones. Be friendly and concise, under 80 words."
        )

    response = client.chat.completions.create(
        model="openai/gpt-oss-20b",
        messages=[{"role": "user", "content": prompt}],
        max_tokens=250,
    )

    return response.choices[0].message.content.strip()
