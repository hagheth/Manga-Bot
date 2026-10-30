import asyncio
import logging
import os
import random
from dotenv import load_dotenv
from telegram import Update, InlineKeyboardButton, InlineKeyboardMarkup
from telegram.ext import ApplicationBuilder, CommandHandler, MessageHandler, CallbackQueryHandler, filters, ContextTypes

from manga_db import (
    add_manga, list_manga, search_manga, delete_manga,
    get_manga, update_chapter, update_status, update_note, update_url, update_title, update_rating,
    delete_manga_by_keyword,
)
from ai import suggest_manga, parse_message, chat_manga
from fetcher import fetch_manga_title, fetch_manga_info

load_dotenv()

logging.basicConfig(
    format="%(asctime)s - %(name)s - %(levelname)s - %(message)s",
    level=logging.INFO,
)
logger = logging.getLogger(__name__)

BOT_TOKEN = os.getenv("BOT_TOKEN")
STICKER_PACK = "AnimuReaction1"
_sticker_cache = {}  # {emoji: [file_id, ...]}
_recent_stickers: list = []  # track last N file_ids to avoid repeats
_STICKER_HISTORY = 20

EMOTION_MAP = {
    "happy":    ["😄", "😊", "😁", "🥳", "😂", "🤣", "😆", "😍"],
    "hype":     ["🔥", "💪", "⚡", "✨", "🚀", "💥", "🤩"],
    "sad":      ["😭", "😢", "😔", "💔", "😿"],
    "thinking": ["🤔", "💭", "🧐"],
    "surprised":["😱", "😲", "🤯", "😮"],
    "cool":     ["😎", "🗿", "👍", "🤙"],
    "love":     ["❤️", "💕", "🥰", "😘"],
}


async def _load_stickers(context):
    global _sticker_cache
    if _sticker_cache:
        return
    pack = await context.bot.get_sticker_set(STICKER_PACK)
    for s in pack.stickers:
        emoji = s.emoji or "😄"
        _sticker_cache.setdefault(emoji, []).append(s.file_id)


async def send_random_sticker(chat_id, context, emotion: str = "happy"):
    global _recent_stickers
    try:
        await _load_stickers(context)
        all_stickers = [fid for fids in _sticker_cache.values() for fid in fids]
        # Try emotion-matched first, then fall back to full pack — always excluding recent
        target_emojis = EMOTION_MAP.get(emotion, EMOTION_MAP["happy"])
        candidates = []
        for emoji in target_emojis:
            candidates.extend(_sticker_cache.get(emoji, []))
        fresh = [fid for fid in candidates if fid not in _recent_stickers]
        if not fresh:
            # Emotion pool exhausted — use full pack minus recent
            fresh = [fid for fid in all_stickers if fid not in _recent_stickers]
        if not fresh:
            # All stickers used — reset history and pick any
            _recent_stickers.clear()
            fresh = all_stickers
        file_id = random.choice(fresh)
        _recent_stickers.append(file_id)
        if len(_recent_stickers) > _STICKER_HISTORY:
            _recent_stickers.pop(0)
        await context.bot.send_sticker(chat_id=chat_id, sticker=file_id)
    except Exception as e:
        logger.warning(f"Sticker send failed: {e}")

STATUS_EMOJI = {
    "reading": "📖",
    "completed": "✅",
    "on_hold": "⏸️",
    "dropped": "❌",
}


async def start(update: Update, context: ContextTypes.DEFAULT_TYPE):
    user = update.effective_user.first_name
    await update.message.reply_text(
        f"Yosh! {user}-kun! 🔥 Your manga sensei has arrived!\n\n"
        "I'll guard your reading list with the power of friendship! 💪\n\n"
        "Just talk to me naturally, believe it! Examples:\n"
        "• \"I'm reading One Piece ch1120\"\n"
        "• \"I finished Berserk\"\n"
        "• \"What should I read next?\"\n"
        "• \"Show me my list\"\n\n"
        "Or type /help to see all my jutsu! ⚡"
    )
    await send_random_sticker(update.message.chat_id, context)


async def help_command(update: Update, context: ContextTypes.DEFAULT_TYPE):
    await update.message.reply_text(
        "📚 Manga Bookmark Bot\n\n"
        "Just talk to me naturally! Examples:\n"
        "\"I'm reading One Piece ch500\"\n"
        "\"I finished Berserk\"\n"
        "\"Show my reading list\"\n"
        "\"Delete One Piece\"\n"
        "\"Rate Berserk 9\"\n"
        "\"Show my stats\"\n"
        "\"Recommend me something new\"\n\n"
        "Slash commands:\n"
        "/list — browse by status\n"
        "/add <title> | <url> | ch<n>\n"
        "/search <keyword>\n"
        "/info <id>\n"
        "/delete <id>\n\n"
        "Statuses: reading, completed, dropped"
    )


async def add_command(update: Update, context: ContextTypes.DEFAULT_TYPE):
    user_id = update.effective_user.id
    args = " ".join(context.args).strip()

    if not args:
        await update.message.reply_text(
            "Usage:\n"
            "`/add <url>` — auto-fetch title from link\n"
            "`/add <title>` — add by title\n"
            "`/add <title> | <url>` — add with link\n"
            "`/add <title> | <url> | ch10` — add with chapter",
            parse_mode="Markdown",
        )
        return

    parts = [p.strip() for p in args.split("|")]
    url = None
    chapter = 0

    # If single arg and looks like a URL — auto-fetch title
    if len(parts) == 1 and parts[0].startswith("http"):
        url = parts[0]
        notice = await update.message.reply_text("🔍 Activating manga detection jutsu...")
        title = fetch_manga_title(url)
        if not title:
            await notice.edit_text("😤 Couldn't grab the title! Try `/add <title> | <url>` instead.", parse_mode="Markdown")
            return
        await notice.edit_text(f"Sugoi! Found: *{title}* ✨", parse_mode="Markdown")
    else:
        title = parts[0]
        url = parts[1] if len(parts) > 1 else None
        if len(parts) > 2:
            ch_str = parts[2].lower().replace("ch", "").strip()
            chapter = int(ch_str) if ch_str.isdigit() else 0

    manga = add_manga(user_id, title, url, chapter)
    if manga:
        msg = f"Yatta! 🎉 *{title}* has joined your list!\n"
        if url:
            msg += f"🔗 [Link]({url})\n"
        msg += f"📖 Ch.{chapter} | 🆔 ID: `{manga['id']}`"
        await update.message.reply_text(msg, parse_mode="Markdown")
        await _send_manga_info_card(update.message, title)
    else:
        await update.message.reply_text("😱 Something went wrong... the scroll was lost! Try again.")


def build_status_filter_keyboard():
    return InlineKeyboardMarkup([
        [InlineKeyboardButton("📖 Reading", callback_data="filter_reading"),
         InlineKeyboardButton("✅ Completed", callback_data="filter_completed")],
        [InlineKeyboardButton("❌ Dropped", callback_data="filter_dropped"),
         InlineKeyboardButton("📚 All", callback_data="filter_all")]
    ])


async def list_command(update: Update, context: ContextTypes.DEFAULT_TYPE):
    await update.message.reply_text(
        "Yosh! Which list shall I reveal to you? 👀",
        reply_markup=build_status_filter_keyboard(),
    )


async def search_command(update: Update, context: ContextTypes.DEFAULT_TYPE):
    user_id = update.effective_user.id
    keyword = " ".join(context.args).strip()

    if not keyword:
        await update.message.reply_text("Usage: `/search <keyword>`", parse_mode="Markdown")
        return

    mangas = search_manga(user_id, keyword)

    if not mangas:
        await update.message.reply_text(f"Nani?! 😲 Can't find *{keyword}* anywhere in your list!", parse_mode="Markdown")
        return

    lines = [f"🔍 *Results for \"{keyword}\"* — found it! 💥", ""]
    for m in mangas:
        emoji = STATUS_EMOJI.get(m["status"], "📖")
        title_part = f"[{m['title']}]({m['url']})" if m.get("url") else m["title"]
        lines.append(f"{emoji} {title_part} — Ch.{m['chapter']} `#{m['id']}`")

    await update.message.reply_text("\n".join(lines), parse_mode="Markdown", disable_web_page_preview=True)


async def info_command(update: Update, context: ContextTypes.DEFAULT_TYPE):
    user_id = update.effective_user.id

    if not context.args or not context.args[0].isdigit():
        await update.message.reply_text("Usage: `/info <id>`", parse_mode="Markdown")
        return

    manga = get_manga(user_id, int(context.args[0]))
    if not manga:
        await update.message.reply_text("Nani?! 😱 That manga doesn't exist in your scroll!")
        return

    emoji = STATUS_EMOJI.get(manga["status"], "📖")
    title_part = f"[{manga['title']}]({manga['url']})" if manga.get("url") else manga["title"]
    msg = (
        f"{emoji} *{manga['title']}*\n"
        f"🔗 {title_part}\n"
        f"📖 Chapter: {manga['chapter']}\n"
        f"📌 Status: {manga['status']}\n"
        f"🆔 ID: `{manga['id']}`\n"
    )
    if manga.get("notes"):
        msg += f"📝 Notes: {manga['notes']}\n"
    msg += f"🕒 Updated: {manga['updated_at'][:10]}"
    await update.message.reply_text(msg, parse_mode="Markdown", disable_web_page_preview=True)


async def update_command(update: Update, context: ContextTypes.DEFAULT_TYPE):
    user_id = update.effective_user.id
    args = context.args

    if len(args) < 2 or not args[0].isdigit():
        await update.message.reply_text("Usage: `/update <id> ch<number>`\nExample: `/update 3 ch45`", parse_mode="Markdown")
        return

    manga_id = int(args[0])
    ch_str = args[1].lower().replace("ch", "").strip()

    if not ch_str.isdigit():
        await update.message.reply_text("Chapter must be a number. Example: `/update 3 ch45`", parse_mode="Markdown")
        return

    chapter = int(ch_str)
    manga = update_chapter(user_id, manga_id, chapter)
    if manga:
        await update.message.reply_text(
            f"🔥 *{manga['title']}* — progress saved at Ch.{chapter}! Keep going!", parse_mode="Markdown"
        )
    else:
        await update.message.reply_text("Nani?! 😱 That manga doesn't exist in your scroll!")


async def status_command(update: Update, context: ContextTypes.DEFAULT_TYPE):
    user_id = update.effective_user.id
    valid = ["reading", "completed", "on_hold", "dropped"]

    if len(context.args) < 2 or not context.args[0].isdigit():
        await update.message.reply_text(
            "Usage: `/status <id> <status>`\n"
            f"Statuses: {' | '.join(valid)}",
            parse_mode="Markdown",
        )
        return

    manga_id = int(context.args[0])
    new_status = context.args[1].lower()

    if new_status not in valid:
        await update.message.reply_text(f"Invalid status. Choose: {' | '.join(valid)}")
        return

    manga = update_status(user_id, manga_id, new_status)
    if manga:
        emoji = STATUS_EMOJI.get(new_status, "📖")
        await update.message.reply_text(
            f"{emoji} *{manga['title']}* is now *{new_status}*! The arc has shifted! ⚡", parse_mode="Markdown"
        )
    else:
        await update.message.reply_text("Nani?! 😱 That manga doesn't exist in your scroll!")


async def note_command(update: Update, context: ContextTypes.DEFAULT_TYPE):
    user_id = update.effective_user.id

    if len(context.args) < 2 or not context.args[0].isdigit():
        await update.message.reply_text("Usage: `/note <id> <your note>`\nExample: `/note 3 great arc starts ch40`", parse_mode="Markdown")
        return

    manga_id = int(context.args[0])
    note = " ".join(context.args[1:])

    manga = update_note(user_id, manga_id, note)
    if manga:
        await update.message.reply_text(
            f"📝 Noted, senpai! Saved for *{manga['title']}*: _{note}_", parse_mode="Markdown"
        )
    else:
        await update.message.reply_text("Nani?! 😱 That manga doesn't exist in your scroll!")


async def delete_command(update: Update, context: ContextTypes.DEFAULT_TYPE):
    user_id = update.effective_user.id

    if not context.args or not context.args[0].isdigit():
        await update.message.reply_text("Usage: `/delete <id>`", parse_mode="Markdown")
        return

    manga_id = int(context.args[0])
    result = delete_manga(user_id, manga_id)

    if result:
        await update.message.reply_text(f"💨 Poof! Manga `#{manga_id}` has been erased from existence!", parse_mode="Markdown")
    else:
        await update.message.reply_text(f"Nani?! 😱 No manga with ID `#{manga_id}` found!", parse_mode="Markdown")


async def suggest_command(update: Update, context: ContextTypes.DEFAULT_TYPE):
    user_id = update.effective_user.id
    thinking = await update.message.reply_text("🤔 Thinking about your next read...")

    mangas = list_manga(user_id)
    suggestion = suggest_manga(mangas)

    await thinking.edit_text(f"🤖 AI Suggestion\n\n{suggestion}")


def build_confirm_keyboard():
    return InlineKeyboardMarkup([
        [
            InlineKeyboardButton("✅ Yes", callback_data="confirm_yes"),
            InlineKeyboardButton("❌ No", callback_data="confirm_no"),
        ]
    ])


def describe_action(parsed: dict) -> str:
    """Build a human-readable summary of what the bot is about to do."""
    intent = parsed.get("intent")
    title = parsed.get("title", "?")
    chapter = parsed.get("chapter")
    status = parsed.get("status")
    url = parsed.get("url")

    if intent == "add":
        msg = f"📚 Add *{title}* to your list"
        if chapter:
            msg += f" at Ch.{chapter}"
        if status:
            msg += f" ({status})"
        if url:
            msg += f"\n🔗 {url}"
    elif intent == "update_chapter":
        msg = f"📖 Save *{title}*"
        if chapter is not None:
            msg += f" at Ch.{chapter}"
        if url:
            msg += f"\n🔗 {url}"
    elif intent == "update_status":
        msg = f"🔄 Mark *{title}* as *{status}*"
    elif intent == "delete":
        msg = f"🗑️ Delete *{title}* from your list"
    elif intent == "delete_bulk":
        keyword = parsed.get("keyword") or title or "?"
        status_words = {"reading", "completed", "dropped", "on_hold", "finished", "complete"}
        if keyword.lower().replace(" ", "_") in status_words or keyword.lower() in status_words:
            msg = f"🗑️ Delete ALL manga with status: *{keyword}*"
        else:
            msg = f"🗑️ Delete ALL manga matching: *{keyword}*"
    elif intent == "rate":
        rating = parsed.get("chapter")
        msg = f"⭐ Rate *{title}* — {rating}/10"
    elif intent == "rename":
        old = parsed.get("keyword", "?")
        msg = f"✏️ Rename *{old}* → *{title}*"
    elif intent == "update_url":
        msg = f"🔗 Update link for *{title}*\n{parsed.get('url', '')}"
    elif intent == "note":
        msg = f"📝 Save note for *{title}*: _{parsed.get('note')}_"
    elif intent == "suggest":
        msg = "🤖 Get an AI suggestion for what to read next"
    elif intent == "list":
        msg = "📋 Show your manga list"
    elif intent == "search":
        msg = f"🔍 Search for *{parsed.get('keyword') or title}*"
    else:
        msg = parsed.get("reply", "Do this action")
    return msg


async def echo(update: Update, context: ContextTypes.DEFAULT_TYPE):
    user_id = update.effective_user.id
    text = update.message.text.strip()

    thinking = await update.message.reply_text("🧠 Activating my manga brain...")

    try:
        mangas = list_manga(user_id)
        parsed = parse_message(text, mangas)
        intent = parsed.get("intent")

        # Actions that don't need confirmation (read-only)
        if intent in ("list", "search", "suggest", "suggest_new", "stats", "unknown"):
            await thinking.delete()
            try:
                await execute_action(update, context, parsed, mangas, user_id, text)
            except Exception as ex:
                logger.error(f"execute_action error (intent={intent}): {ex}", exc_info=True)
                await update.message.reply_text(f"😵 Oops: {ex}")
            return

        # For write actions — show confirmation
        summary = describe_action(parsed)
        context.user_data["pending"] = parsed
        context.user_data["pending_mangas"] = mangas
        context.user_data["pending_text"] = text

        await thinking.edit_text(
            f"Sugoi! I got it! 👀\n\n{summary}\n\nShall I proceed, senpai?",
            parse_mode="Markdown",
            reply_markup=build_confirm_keyboard(),
        )

    except Exception as e:
        logger.error(f"Echo handler error: {e}")
        try:
            await thinking.edit_text(f"😵 Oops, something went wrong: {e}")
        except Exception:
            await update.message.reply_text(f"😵 Oops, something went wrong. Try again!")


async def confirm_callback(update: Update, context: ContextTypes.DEFAULT_TYPE):
    query = update.callback_query
    await query.answer()
    user_id = query.from_user.id

    # Status filter button from list
    if query.data.startswith("filter_"):
        status = query.data.split("_", 1)[1]
        status_filter = None if status == "all" else status
        mangas = list_manga(user_id, status_filter)
        if not mangas:
            label = "All" if not status_filter else status_filter.title()
            await query.edit_message_text(f"Nani?! Your {label} list is empty... the arc hasn't started yet! 😤")
            return
        header = "📚 Your saga awaits — tap a title! ✨" if not status_filter else f"📚 {status_filter.title()} — tap a title! ✨"
        keyboard = []
        for m in mangas:
            emoji = STATUS_EMOJI.get(m["status"], "📖")
            keyboard.append([InlineKeyboardButton(f"{emoji} {m['title']}", callback_data=f"info_{m['id']}")])
        await query.edit_message_text(header, reply_markup=InlineKeyboardMarkup(keyboard))
        return

    # Info button from list
    if query.data.startswith("info_"):
        manga_id = int(query.data.split("_")[1])
        manga = get_manga(user_id, manga_id)
        if not manga:
            await query.answer("Manga not found.", show_alert=True)
            return
        emoji = STATUS_EMOJI.get(manga["status"], "📖")
        msg = (
            f"{emoji} {manga['title']}\n"
            f"📖 Chapter: {manga['chapter']}\n"
            f"📌 Status: {manga['status']}\n"
            f"🆔 ID: {manga['id']}\n"
        )
        if manga.get("url"):
            msg += f"🔗 {manga['url']}\n"
        if manga.get("rating"):
            stars = "⭐" * manga["rating"]
            msg += f"⭐ Rating: {manga['rating']}/10 {stars}\n"
        if manga.get("notes"):
            msg += f"📝 {manga['notes']}\n"
        msg += f"🕒 Updated: {manga['updated_at'][:10]}"
        await query.message.reply_text(msg, disable_web_page_preview=True)
        return

    if query.data == "confirm_no":
        await query.edit_message_text("Yare yare... 😮‍💨 Cancelled! Nothing was changed.")
        context.user_data.pop("pending", None)
        return

    parsed = context.user_data.pop("pending", None)
    mangas = context.user_data.pop("pending_mangas", [])
    original_text = context.user_data.pop("pending_text", "")

    if not parsed:
        await query.edit_message_text("😵 Session expired! Try again, I believe in you!")
        return

    await query.edit_message_text("⚡ On it! Deploying full power...")

    try:
        result_msg = await execute_action_data(parsed, mangas, user_id, original_text)
        await query.edit_message_text(result_msg, parse_mode="Markdown", disable_web_page_preview=True)
        if parsed.get("intent") == "add":
            title = parsed.get("title") or parsed.get("url", "")
            await _send_manga_info_card(query.message, title)
        await send_random_sticker(query.message.chat_id, context)
    except Exception as e:
        logger.error(f"Confirm callback error: {e}")
        await query.edit_message_text("😱 Something went wrong... my power wasn't enough! Try again.")


async def execute_action(update: Update, context: ContextTypes.DEFAULT_TYPE, parsed: dict, mangas: list, user_id: int, text: str = ""):
    """Execute read-only actions directly without confirmation."""
    intent = parsed.get("intent")

    if intent == "stats":
        all_manga = list_manga(user_id)
        total = len(all_manga)
        if not total:
            await update.message.reply_text("Nani?! 😲 Your scroll is empty — no stats yet!")
            return
        reading = sum(1 for m in all_manga if m["status"] == "reading")
        completed = sum(1 for m in all_manga if m["status"] == "completed")
        dropped = sum(1 for m in all_manga if m["status"] == "dropped")
        total_chapters = sum(m["chapter"] for m in all_manga)
        avg_chapters = round(total_chapters / total, 1)
        most_read = max(all_manga, key=lambda m: m["chapter"])
        rated = [m for m in all_manga if m.get("rating")]
        top_rated = max(rated, key=lambda m: m["rating"]) if rated else None
        msg = (
            f"📊 Your Manga Stats\n\n"
            f"📚 Total manga: {total}\n"
            f"📖 Reading: {reading}\n"
            f"✅ Completed: {completed}\n"
            f"❌ Dropped: {dropped}\n\n"
            f"📈 Total chapters read: {total_chapters}\n"
            f"⌀ Avg chapters per manga: {avg_chapters}\n"
            f"🏆 Most read: {most_read['title']} (Ch.{most_read['chapter']})"
        )
        if top_rated:
            msg += f"\n⭐ Top rated: {top_rated['title']} ({top_rated['rating']}/10)"
        await update.message.reply_text(msg)
        await send_random_sticker(update.message.chat_id, context)
        return

    if intent == "list":
        status_filter = parsed.get("status")
        if status_filter:
            results = list_manga(user_id, status_filter)
            if not results:
                await update.message.reply_text(f"Nani?! Your {status_filter.title()} list is empty... the arc hasn't started yet! 😤")
                return
            header = f"📚 {status_filter.title()} — tap a title for details:"
            keyboard = [[InlineKeyboardButton(f"{STATUS_EMOJI.get(m['status'], '📖')} {m['title']}", callback_data=f"info_{m['id']}")] for m in results]
            await update.message.reply_text(header, reply_markup=InlineKeyboardMarkup(keyboard))
        else:
            await update.message.reply_text(
                "Yosh! Which list shall I reveal to you? 👀",
                reply_markup=build_status_filter_keyboard(),
            )
        return

    elif intent == "search":
        keyword = parsed.get("keyword") or parsed.get("title")
        if keyword:
            results = search_manga(user_id, keyword)
            if results:
                lines = [f"🔍 *Results for \"{keyword}\"*\n"]
                for m in results:
                    emoji = STATUS_EMOJI.get(m["status"], "📖")
                    title_part = f"[{m['title']}]({m['url']})" if m.get("url") else m["title"]
                    lines.append(f"{emoji} {title_part} — Ch.{m['chapter']} `#{m['id']}`")
                msg = "\n".join(lines)
            else:
                msg = f"Nani?! 😲 Can't find *{keyword}* anywhere in your scroll!"
        else:
            msg = "Oi oi, what are we searching for? 👀"

    elif intent in ("suggest", "suggest_new"):
        try:
            msg, emotion = chat_manga(text or "Recommend me some good manga to read.", mangas)
        except Exception as e:
            logger.error(f"suggest error: {e}")
            msg, emotion = "🤖 Couldn't generate a suggestion. Try again.", "sad"

    else:
        try:
            msg, emotion = chat_manga(text, mangas)
        except Exception as e:
            logger.error(f"chat_manga error: {e}")
            msg, emotion = "🤔 I'm not sure what you mean. Try: \"I'm reading One Piece ch1120\" or \"show my list\"", "thinking"

    await update.message.reply_text(msg, disable_web_page_preview=True)
    await send_random_sticker(update.message.chat_id, context, emotion)



async def _send_manga_info_card(message, title: str):
    """Fetch MangaDex info and send cover + synopsis as a follow-up message."""
    info = fetch_manga_info(title)
    if not info:
        return
    meta = []
    if info.get("status"):
        meta.append(info["status"])
    if info.get("total_chapters"):
        meta.append(f"{info['total_chapters']} chapters")
    caption = f"📖 {info['title']}"
    if meta:
        caption += f"  •  {' | '.join(meta)}"
    if info.get("synopsis"):
        caption += f"\n\n{info['synopsis']}"
    try:
        if info.get("cover_url"):
            await message.reply_photo(photo=info["cover_url"], caption=caption)
        else:
            await message.reply_text(caption)
    except Exception:
        pass


_STATUS_KEYWORDS = {
    "completed": "completed", "complete": "completed", "finished": "completed", "finish": "completed",
    "dropped": "dropped", "drop": "dropped", "quit": "dropped",
    "reading": "reading",
}


async def execute_action_data(parsed: dict, mangas: list, user_id: int, original_text: str = "") -> str:
    """Execute write actions and return result message."""
    from fetcher import fetch_manga_title, fetch_manga_info
    intent = parsed.get("intent")
    title = parsed.get("title")
    url = parsed.get("url")
    chapter = parsed.get("chapter") or 0
    status = parsed.get("status") or "reading"

    # Fallback: if AI missed the status, detect it from the original message
    if status == "reading" and original_text:
        for kw, mapped in _STATUS_KEYWORDS.items():
            if kw in original_text.lower() and mapped != "reading":
                status = mapped
                break

    if not title and url:
        title = fetch_manga_title(url)

    if intent == "add":
        if not title:
            return "😅 I couldn't catch the title! Tell me the manga name, senpai!"
        manga = add_manga(user_id, title, url, chapter)
        if manga:
            if status != "reading":
                update_status(user_id, manga["id"], status)
            return f"Yatta! 🎉 *{title}* has joined your list! Ch.{chapter} | ID: `{manga['id']}`"
        return "😱 Something went wrong... the scroll was lost! Try again."

    elif intent == "update_chapter":
        if not title:
            return "😅 I couldn't catch the title! Tell me the manga name, senpai!"
        results = search_manga(user_id, title)
        if results:
            m = results[0]
            update_chapter(user_id, m["id"], chapter)
            if status != "reading":
                update_status(user_id, m["id"], status)
            status_note = f" Marked as {status}! ✅" if status != "reading" else " Keep going!"
            return f"🔥 *{m['title']}* — Ch.{chapter} saved!{status_note}"
        else:
            manga = add_manga(user_id, title, url, chapter)
            if manga and status != "reading":
                update_status(user_id, manga["id"], status)
            return f"Yatta! 🎉 *{title}* added to your list at Ch.{chapter}!"

    elif intent == "update_status":
        if title and status:
            results = search_manga(user_id, title)
            if results:
                m = results[0]
                update_status(user_id, m["id"], status)
                emoji = STATUS_EMOJI.get(status, "📖")
                return f"{emoji} *{m['title']}* is now *{status}*! The arc has shifted! ⚡"
            return f"Nani?! 😲 Can't find *{title}* in your scroll!"
        return "😅 Tell me which manga and what status, senpai!"

    elif intent == "rate":
        rating = parsed.get("chapter")
        if title and rating is not None:
            if not (1 <= int(rating) <= 10):
                return "😅 Rating must be between 1 and 10, senpai!"
            results = search_manga(user_id, title)
            if results:
                m = results[0]
                update_rating(user_id, m["id"], int(rating))
                stars = "⭐" * int(rating)
                return f"⭐ Rated *{m['title']}* {rating}/10!\n{stars}"
            return f"Nani?! 😲 Can't find *{title}* in your scroll!"
        return "😅 Tell me which manga and the rating (1-10), senpai!"

    elif intent == "rename":
        old_name = parsed.get("keyword")
        new_name = title
        if old_name and new_name:
            results = search_manga(user_id, old_name)
            if results:
                m = results[0]
                update_title(user_id, m["id"], new_name)
                return f"✏️ Renamed *{old_name}* → *{new_name}*! Sugoi! ✨"
            return f"Nani?! 😲 Can't find *{old_name}* in your scroll!"
        return "😅 Tell me the old name and new name, senpai!"

    elif intent == "update_url":
        if title and url:
            results = search_manga(user_id, title)
            if results:
                m = results[0]
                update_url(user_id, m["id"], url)
                return f"🔗 Link updated for *{m['title']}*! Sugoi! ✨"
            return f"Nani?! 😲 Can't find *{title}* in your scroll!"
        return "😅 Tell me which manga and the new link, senpai!"

    elif intent == "note":
        note = parsed.get("note")
        if title and note:
            results = search_manga(user_id, title)
            if results:
                m = results[0]
                update_note(user_id, m["id"], note)
                return f"📝 Noted, senpai! Sealed into the scroll for *{m['title']}*!"
            return f"Nani?! 😲 Can't find *{title}* in your scroll!"
        return "😅 Tell me which manga and what note, senpai!"

    elif intent == "delete":
        if title:
            results = search_manga(user_id, title)
            if results:
                m = results[0]
                delete_manga(user_id, m["id"])
                return f"💨 Poof! *{m['title']}* has been erased from existence!"
            return f"Nani?! 😲 Can't find *{title}* in your scroll!"
        return "😅 Which manga shall be erased, senpai?"

    elif intent == "delete_bulk":
        keyword_str = parsed.get("keyword") or parsed.get("title")
        status_keywords = {"reading", "completed", "dropped", "on_hold", "on hold", "finished", "complete"}
        if keyword_str:
            keywords = [k.strip() for k in keyword_str.split(",") if k.strip()]
            all_deleted = []
            for kw in keywords:
                kw_norm = kw.lower().replace(" ", "_")
                if kw_norm in {"reading", "completed", "dropped", "on_hold"} or kw.lower() in status_keywords:
                    status = "completed" if kw.lower() in ("finished", "complete", "completed") else kw_norm.replace(" ", "_")
                    matches = list_manga(user_id, status)
                    for m in matches:
                        delete_manga(user_id, m["id"])
                        all_deleted.append(m["title"])
                else:
                    deleted = delete_manga_by_keyword(user_id, kw)
                    all_deleted.extend(deleted)
            if all_deleted:
                titles = "\n".join(f"• {t}" for t in all_deleted)
                return f"💨 Poof! {len(all_deleted)} manga erased from existence:\n{titles}"
            return f"Nani?! 😲 Can't find anything matching *{keyword_str}* in your scroll!"
        return "😅 What shall be erased, senpai?"

    return "😵 Unknown jutsu... I don't know what to do with that!"


def main():
    if not BOT_TOKEN:
        raise ValueError("BOT_TOKEN is not set in .env file")

    loop = asyncio.new_event_loop()
    asyncio.set_event_loop(loop)

    app = ApplicationBuilder().token(BOT_TOKEN).concurrent_updates(True).build()

    app.add_handler(CommandHandler("start", start))
    app.add_handler(CommandHandler("help", help_command))
    app.add_handler(CommandHandler("add", add_command))
    app.add_handler(CommandHandler("list", list_command))
    app.add_handler(CommandHandler("search", search_command))
    app.add_handler(CommandHandler("delete", delete_command))
    app.add_handler(CommandHandler("info", info_command))
    app.add_handler(CommandHandler("update", update_command))
    app.add_handler(CommandHandler("status", status_command))
    app.add_handler(CommandHandler("note", note_command))
    app.add_handler(CommandHandler("suggest", suggest_command))
    app.add_handler(CallbackQueryHandler(confirm_callback))
    app.add_handler(MessageHandler(filters.TEXT & ~filters.COMMAND, echo))

    logger.info("Bot is running...")
    app.run_polling()


if __name__ == "__main__":
    main()
