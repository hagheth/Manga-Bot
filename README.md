# Manga Bookmark Bot & App

A personal manga tracking system with a Telegram bot and a Flutter web app (PWA), backed by Supabase and powered by AI via Groq.

## Features

- **Telegram Bot** — add, update, delete and query manga via natural language
- **Flutter Web App (PWA)** — mobile-friendly library view, AI chat, and stats, installable on iPhone/Android via Safari
- **AI Chat** — understands commands like "update one piece to chapter 1050" or "what should I read next"
- **MangaDex integration** — auto-fetches cover images, titles, and reading links
- **Single-user** — locked to one Telegram user ID

## Stack

| Layer | Tech |
|---|---|
| Database | Supabase (PostgreSQL) |
| Backend API | FastAPI + Uvicorn |
| AI | Groq (LLaMA) |
| Manga data | MangaDex API |
| Frontend | Flutter 3 (web/PWA) |
| Hosting | Render (free tier) |
| Bot | python-telegram-bot |

## Project Structure

```
manga/
├── api.py          # FastAPI backend (served on Render)
├── bot.py          # Telegram bot
├── ai.py           # AI intent parsing and chat
├── manga_db.py     # Supabase database helpers
├── fetcher.py      # MangaDex scraping and URL detection
├── flutter_web/    # Built Flutter web app (served by FastAPI)
├── render.yaml     # Render deployment config
└── .env            # Secrets (not committed)
```

## Setup

### 1. Clone and install

```bash
git clone https://github.com/hagheth/Manga-Bot.git
cd Manga-Bot
pip install -r requirements_api.txt   # for the API
pip install -r requirements.txt       # for the Telegram bot
```

### 2. Environment variables

Create a `.env` file:

```
BOT_TOKEN=your_telegram_bot_token
SUPABASE_URL=your_supabase_url
SUPABASE_KEY=your_supabase_anon_key
GROQ_API_KEY=your_groq_api_key
APP_USER_ID=your_telegram_user_id
```

### 3. Run locally

```bash
# API
uvicorn api:app --host 0.0.0.0 --port 8000 --reload

# Bot (separate terminal)
python bot.py
```

### 4. Deploy API to Render

Push to GitHub — Render auto-deploys via `render.yaml`. Set the 4 environment variables (`APP_USER_ID`, `SUPABASE_URL`, `SUPABASE_KEY`, `GROQ_API_KEY`) in the Render dashboard.

### 5. Flutter web app

The built Flutter web app lives in `flutter_web/` and is served by FastAPI at the root URL. To rebuild after Flutter changes:

```bash
cd manga_app
flutter build web
# copy build/web/* into ../manga/flutter_web/
# commit and push
```

## Web App (PWA)

Visit `https://manga-bot-k4yd.onrender.com` in Safari on iPhone, tap **Share → Add to Home Screen** to install as a PWA.

> Note: The free Render instance sleeps after inactivity — first load may take ~50 seconds.
