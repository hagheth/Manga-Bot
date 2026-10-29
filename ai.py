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
- "list": user wants to see their list. If they mention ONE specific status (reading/completed/dropped), set the status field. If they say "all", mention multiple statuses, or don't specify, leave status as null.
- "suggest": user wants to know what to read next from their existing list
- "suggest_new": user wants recommendations for NEW manga they haven't read yet (phrases like "suggest another", "recommend something new", "what else should I read", "based on my taste")
- "delete": user wants to remove one manga by title
- "delete_bulk": user wants to delete multiple manga matching keywords. Put ALL keywords in the "keyword" field as a comma-separated list (e.g. "mangafire,manga plus"). Never join them with "and".
- "update_url": user wants to update/change the link for an existing manga
- "rename": user wants to rename/change the title of an existing manga (e.g. "change X into Y", "rename X to Y"). Put the OLD name in "keyword" and the NEW name in "title".
- "note": user wants to add a note
- "stats": user wants to see their reading statistics (e.g. "show my stats", "how many manga have I read", "my reading summary")
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
- If user says "add X" or "save X" with a title/url → intent is "add", extract title, url, chapter
- If user sends a URL with a chapter number (e.g. "https://... chapter 100") → intent is "update_chapter", extract url and chapter
- If user says "I've read X until chapter Y" or "I'm reading X at chY" → intent is "update_chapter" (the bot will auto-add if not found)
- If user says "I've read X" with no chapter → intent is "add" with status "reading"
- If user says "I finished X" or "I completed X" → intent is "update_status" with status "completed", only if manga likely exists; otherwise "add" with status "completed"
- Keep reply short and friendly, 1 sentence max
- IMPORTANT: Always return ONLY valid JSON, no extra text, no markdown code blocks"""


def _preparse(user_message: str) -> dict | None:
    """Detect obvious patterns before hitting the AI."""
    import re
    url_match = re.search(r'https?://\S+', user_message)
    ch_match = re.search(r'(?:chapter|ch|c)\s*(\d+)', user_message, re.IGNORECASE)
    text_lower = user_message.lower()

    if url_match and ch_match:
        intent = "update_chapter" if any(w in text_lower for w in ("read", "on", "at", "until", "till")) else "add"
        return {
            "intent": intent,
            "url": url_match.group(0),
            "chapter": int(ch_match.group(1)),
            "title": None,
            "status": "reading",
            "reply": "Got it!",
        }
    return None


def parse_message(user_message: str, manga_list: list) -> dict:
    """Parse a natural language message and return structured intent + data."""

    # Fast-path for obvious URL + chapter patterns
    pre = _preparse(user_message)
    if pre:
        return pre

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

    # Extract JSON from code block or find first { } block
    if "```" in raw:
        raw = raw.split("```")[1]
        if raw.startswith("json"):
            raw = raw[4:]
    else:
        import re
        m = re.search(r'\{.*\}', raw, re.DOTALL)
        if m:
            raw = m.group(0)

    try:
        return json.loads(raw)
    except json.JSONDecodeError:
        logger.warning(f"Failed to parse AI response: {raw!r}")
        return {"intent": "unknown", "reply": raw or "I didn't quite get that."}



def chat_manga(user_message: str, manga_list: list = None) -> str:
    """Answer general manga questions conversationally, with optional reading list context."""
    context = ""
    if manga_list:
        lines = []
        for m in manga_list:
            lines.append(f"- {m['title']}: {m['status']}, chapter {m['chapter']}")
        context = "\n\nThe user's manga list:\n" + "\n".join(lines)

    response = client.chat.completions.create(
        model="openai/gpt-oss-20b",
        messages=[
            {
                "role": "system",
                "content": (
                    "You are an enthusiastic manga expert who talks like an anime character from a dub. "
                    "Use anime catchphrases and expressions naturally (like 'Believe it!', 'This is my ninja way!', 'By the power of friendship!', 'Nani?!', 'Sugoi!', 'Yare yare...', etc). "
                    "Talk in a casual conversational tone like you're chatting with a friend — no bullet points, no lists, no tables, no markdown, no asterisks, no bold, no italic. Plain text only. "
                    "Keep it under 80 words and make it fun and energetic. "
                    "Sprinkle in relevant emojis naturally based on the topic (e.g. ⚔️ action, 💀 dark themes, 💕 romance, 🔥 hype, 😂 comedy, 🌊 adventure). "
                    "Only mention the user's manga list if they directly ask about it or ask for recommendations — never bring it up unprompted during casual conversation or greetings. "
                    "If the user asks about anime (not manga), kindly let them know you specialise in manga but still try to help or redirect — never silently ignore the question."
                    + context
                ),
            },
            {"role": "user", "content": user_message},
        ],
        max_tokens=400,
        temperature=0.7,
    )
    return response.choices[0].message.content.strip()


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
