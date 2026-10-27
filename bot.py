import asyncio
import logging
import os
from dotenv import load_dotenv
from telegram import Update, InlineKeyboardButton, InlineKeyboardMarkup
from telegram.ext import ApplicationBuilder, CommandHandler, MessageHandler, CallbackQueryHandler, filters, ContextTypes

from manga_db import (
    add_manga, list_manga, search_manga, delete_manga,
    get_manga, update_chapter, update_status, update_note,
    delete_manga_by_keyword,
)
from ai import suggest_manga, parse_message, chat_manga
from fetcher import fetch_manga_title

load_dotenv()

logging.basicConfig(
    format="%(asctime)s - %(name)s - %(levelname)s - %(message)s",
    level=logging.INFO,
)
logger = logging.getLogger(__name__)

BOT_TOKEN = os.getenv("BOT_TOKEN")

STATUS_EMOJI = {
    "reading": "📖",
    "completed": "✅",
    "on_hold": "⏸️",
    "dropped": "❌",
}


async def start(update: Update, context: ContextTypes.DEFAULT_TYPE):
    user = update.effective_user.first_name
    await update.message.reply_text(
        f"Hey {user}! 👋 I'm your Manga Bookmark Bot.\n\n"
        "I'll help you save and track your manga reading list.\n\n"
        "Type /help to see available commands.\n\n"
        "Or just talk naturally! Examples:\n"
        "• \"I'm reading One Piece ch1120\"\n"
        "• \"I finished Berserk\"\n"
        "• \"What should I read next?\"\n"
        "• \"Show me my list\""
    )


async def help_command(update: Update, context: ContextTypes.DEFAULT_TYPE):
    await update.message.reply_text(
        "📚 *Manga Bookmark Bot — Commands*\n\n"
        "*Add manga:*\n"
        "`/add <title>` — add by title\n"
        "`/add <title> | <url>` — add with link\n"
        "`/add <title> | <url> | ch<number>` — add with chapter\n\n"
        "*View manga:*\n"
        "`/list` — show all manga\n"
        "`/list reading` — filter by status\n"
        "`/search <keyword>` — search by title\n\n"
        "*Progress:*\n"
        "`/info <id>` — full manga details\n"
        "`/update <id> ch<n>` — update chapter\n"
        "`/status <id> <status>` — change status\n"
        "`/note <id> <text>` — save a note\n\n"
        "*Remove manga:*\n"
        "`/delete <id>` — delete by ID\n\n"
        "*Statuses:* reading \\| completed \\| on\\_hold \\| dropped",
        parse_mode="MarkdownV2",
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
        notice = await update.message.reply_text("🔍 Fetching manga info from link...")
        title = fetch_manga_title(url)
        if not title:
            await notice.edit_text("⚠️ Couldn't fetch title. Use `/add <title> | <url>` instead.", parse_mode="Markdown")
            return
        await notice.edit_text(f"✅ Found: *{title}*", parse_mode="Markdown")
    else:
        title = parts[0]
        url = parts[1] if len(parts) > 1 else None
        if len(parts) > 2:
            ch_str = parts[2].lower().replace("ch", "").strip()
            chapter = int(ch_str) if ch_str.isdigit() else 0

    manga = add_manga(user_id, title, url, chapter)
    if manga:
        msg = f"📚 *{title}* saved!\n"
        if url:
            msg += f"🔗 [Link]({url})\n"
        msg += f"📖 Chapter: {chapter} | 🆔 ID: `{manga['id']}`"
        await update.message.reply_text(msg, parse_mode="Markdown")
    else:
        await update.message.reply_text("❌ Failed to add manga. Try again.")


def build_status_filter_keyboard():
    return InlineKeyboardMarkup([
        [InlineKeyboardButton("📖 Reading", callback_data="filter_reading"),
         InlineKeyboardButton("✅ Completed", callback_data="filter_completed")],
        [InlineKeyboardButton("❌ Dropped", callback_data="filter_dropped"),
         InlineKeyboardButton("📚 All", callback_data="filter_all")],
    ])


async def list_command(update: Update, context: ContextTypes.DEFAULT_TYPE):
    await update.message.reply_text(
        "Which list do you want to see?",
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
        await update.message.reply_text(f"No manga found matching *{keyword}*.", parse_mode="Markdown")
        return

    lines = [f"🔍 *Results for \"{keyword}\"*", ""]
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
        await update.message.reply_text("❌ Manga not found.")
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
            f"✅ *{manga['title']}* updated to Chapter {chapter}!", parse_mode="Markdown"
        )
    else:
        await update.message.reply_text("❌ Manga not found.")


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
            f"{emoji} *{manga['title']}* marked as *{new_status}*!", parse_mode="Markdown"
        )
    else:
        await update.message.reply_text("❌ Manga not found.")


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
            f"📝 Note saved for *{manga['title']}*: _{note}_", parse_mode="Markdown"
        )
    else:
        await update.message.reply_text("❌ Manga not found.")


async def delete_command(update: Update, context: ContextTypes.DEFAULT_TYPE):
    user_id = update.effective_user.id

    if not context.args or not context.args[0].isdigit():
        await update.message.reply_text("Usage: `/delete <id>`", parse_mode="Markdown")
        return

    manga_id = int(context.args[0])
    result = delete_manga(user_id, manga_id)

    if result:
        await update.message.reply_text(f"🗑️ Manga `#{manga_id}` deleted.", parse_mode="Markdown")
    else:
        await update.message.reply_text(f"❌ No manga found with ID `#{manga_id}`.", parse_mode="Markdown")


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
        msg = f"🗑️ Delete ALL manga matching: *{keyword}*"
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

    thinking = await update.message.reply_text("💭 Understanding your message...")

    try:
        mangas = list_manga(user_id)
        parsed = parse_message(text, mangas)
        intent = parsed.get("intent")

        # Actions that don't need confirmation (read-only)
        if intent in ("list", "search", "suggest", "suggest_new", "unknown"):
            await thinking.delete()
            await execute_action(update, context, parsed, mangas, user_id, text)
            return

        # For write actions — show confirmation
        summary = describe_action(parsed)
        context.user_data["pending"] = parsed
        context.user_data["pending_mangas"] = mangas

        await thinking.edit_text(
            f"I understood:\n\n{summary}\n\nIs this correct?",
            parse_mode="Markdown",
            reply_markup=build_confirm_keyboard(),
        )

    except Exception as e:
        logger.error(f"Echo handler error: {e}")
        await thinking.edit_text(f"❌ Error: {e}")


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
            await query.edit_message_text(f"No manga in {label} list yet.")
            return
        header = "📚 All Manga — tap a title for details:" if not status_filter else f"📚 {status_filter.title()} — tap a title for details:"
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
        if manga.get("notes"):
            msg += f"📝 {manga['notes']}\n"
        msg += f"🕒 Updated: {manga['updated_at'][:10]}"
        await query.message.reply_text(msg, disable_web_page_preview=True)
        return

    if query.data == "confirm_no":
        await query.edit_message_text("❌ Cancelled. Nothing was saved.")
        context.user_data.pop("pending", None)
        return

    parsed = context.user_data.pop("pending", None)
    mangas = context.user_data.pop("pending_mangas", [])

    if not parsed:
        await query.edit_message_text("❌ Session expired. Please try again.")
        return

    await query.edit_message_text("⏳ Doing it...")

    try:
        result_msg = await execute_action_data(parsed, mangas, user_id)
        await query.edit_message_text(result_msg, parse_mode="Markdown", disable_web_page_preview=True)
    except Exception as e:
        logger.error(f"Confirm callback error: {e}")
        await query.edit_message_text("❌ Something went wrong.")


async def execute_action(update: Update, context: ContextTypes.DEFAULT_TYPE, parsed: dict, mangas: list, user_id: int, text: str = ""):
    """Execute read-only actions directly without confirmation."""
    intent = parsed.get("intent")

    if intent == "list":
        status_filter = parsed.get("status")
        if status_filter:
            results = list_manga(user_id, status_filter)
            if not results:
                await update.message.reply_text(f"No manga in your {status_filter.title()} list yet.")
                return
            header = f"📚 {status_filter.title()} — tap a title for details:"
            keyboard = [[InlineKeyboardButton(f"{STATUS_EMOJI.get(m['status'], '📖')} {m['title']}", callback_data=f"info_{m['id']}")] for m in results]
            await update.message.reply_text(header, reply_markup=InlineKeyboardMarkup(keyboard))
        else:
            await update.message.reply_text(
                "Which list do you want to see?",
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
                msg = f"No manga found matching *{keyword}*."
        else:
            msg = "What are you looking for?"

    elif intent in ("suggest", "suggest_new"):
        try:
            msg = chat_manga(text or "Recommend me some good manga to read.", mangas)
        except Exception as e:
            logger.error(f"suggest error: {e}")
            msg = "🤖 Couldn't generate a suggestion. Try again."

    else:
        try:
            msg = chat_manga(text, mangas)
        except Exception as e:
            logger.error(f"chat_manga error: {e}")
            msg = "🤔 I'm not sure what you mean. Try: \"I'm reading One Piece ch1120\" or \"show my list\""

    await update.message.reply_text(msg, disable_web_page_preview=True)


async def execute_action_data(parsed: dict, mangas: list, user_id: int) -> str:
    """Execute write actions and return result message."""
    from fetcher import fetch_manga_title
    intent = parsed.get("intent")
    title = parsed.get("title")
    url = parsed.get("url")
    chapter = parsed.get("chapter") or 0
    status = parsed.get("status") or "reading"

    if not title and url:
        title = fetch_manga_title(url)

    if intent == "add":
        if not title:
            return "❌ Couldn't get the title. Please tell me the manga name."
        manga = add_manga(user_id, title, url, chapter)
        if manga:
            if status != "reading":
                update_status(user_id, manga["id"], status)
            return f"✅ *{title}* saved! Ch.{chapter} | ID: `{manga['id']}`"
        return "❌ Failed to save. Try again."

    elif intent == "update_chapter":
        if not title:
            return "❌ Couldn't get the title."
        results = search_manga(user_id, title)
        if results:
            m = results[0]
            update_chapter(user_id, m["id"], chapter)
            if status != "reading":
                update_status(user_id, m["id"], status)
            return f"✅ *{m['title']}* updated to Ch.{chapter}!"
        else:
            manga = add_manga(user_id, title, url, chapter)
            if manga and status != "reading":
                update_status(user_id, manga["id"], status)
            return f"✅ Added *{title}* to your list at Ch.{chapter}!"

    elif intent == "update_status":
        if title and status:
            results = search_manga(user_id, title)
            if results:
                m = results[0]
                update_status(user_id, m["id"], status)
                emoji = STATUS_EMOJI.get(status, "📖")
                return f"{emoji} *{m['title']}* marked as *{status}*!"
            return f"❌ Couldn't find *{title}* in your list."
        return "❌ Tell me which manga and what status."

    elif intent == "note":
        note = parsed.get("note")
        if title and note:
            results = search_manga(user_id, title)
            if results:
                m = results[0]
                update_note(user_id, m["id"], note)
                return f"📝 Note saved for *{m['title']}*!"
            return f"❌ Couldn't find *{title}* in your list."
        return "❌ Tell me which manga and what note."

    elif intent == "delete":
        if title:
            results = search_manga(user_id, title)
            if results:
                m = results[0]
                delete_manga(user_id, m["id"])
                return f"🗑️ *{m['title']}* removed from your list."
            return f"❌ Couldn't find *{title}* in your list."
        return "❌ Which manga do you want to delete?"

    elif intent == "delete_bulk":
        keyword_str = parsed.get("keyword") or parsed.get("title")
        if keyword_str:
            keywords = [k.strip() for k in keyword_str.split(",") if k.strip()]
            all_deleted = []
            for kw in keywords:
                deleted = delete_manga_by_keyword(user_id, kw)
                all_deleted.extend(deleted)
            if all_deleted:
                titles = "\n".join(f"• {t}" for t in all_deleted)
                return f"🗑️ Deleted {len(all_deleted)} manga:\n{titles}"
            return f"❌ No manga found matching *{keyword_str}*."
        return "❌ What should I delete?"

    return "❌ Unknown action."


def main():
    if not BOT_TOKEN:
        raise ValueError("BOT_TOKEN is not set in .env file")

    loop = asyncio.new_event_loop()
    asyncio.set_event_loop(loop)

    app = ApplicationBuilder().token(BOT_TOKEN).build()

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
