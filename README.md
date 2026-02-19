# kinderbud-openclaw

OpenClaw skill for [Kinderbud](https://github.com/Liam-Fistos/kinderbud) — manage your parenting activities and child development tracking via AI chat.

## What This Does

This skill lets you interact with your Kinderbud account through OpenClaw, your personal AI agent. Ask about today's activities, mark todos complete, get guidance on developmental activities, manage guide subscriptions, and more — all from WhatsApp, Telegram, Discord, or any other OpenClaw-connected channel.

## Prerequisites

- A [Kinderbud](https://github.com/Liam-Fistos/kinderbud) account with at least one child profile and an active guide subscription
- [OpenClaw](https://openclaw.ai) installed and configured
- An API token generated from your Kinderbud Settings page

## Installation

### Via ClawHub (recommended)

```bash
clawhub install kinderbud
```

### Manual

Copy the `kinderbud/` folder into your OpenClaw skills directory:

```bash
cp -r kinderbud/ ~/.openclaw/skills/kinderbud/
```

## Configuration

Add your Kinderbud API token to `~/.openclaw/openclaw.json`:

```json
{
  "skills": {
    "entries": {
      "kinderbud": {
        "enabled": true,
        "apiKey": "kb_live_your_token_here",
        "env": {
          "KINDERBUD_API_URL": "https://api.kinderbud.org"
        }
      }
    }
  }
}
```

### Getting Your API Token

1. Log in to your Kinderbud account at https://api.kinderbud.org
2. Go to **Settings** > **API Tokens**
3. Click **Generate Token**, give it a name (e.g., "OpenClaw")
4. Copy the token (it's only shown once)
5. Paste it into your OpenClaw config as shown above

## What You Can Do

| Command | Example |
|---|---|
| Morning brief | "What's on the Kinderbud schedule today?" |
| Complete a todo | "Mark the reading activity as done" |
| Snooze a todo | "Snooze tummy time to tomorrow" |
| Get activity help | "How should I do the serve-and-return activity?" |
| Browse guides | "What Kinderbud guides are available?" |
| Subscribe to a guide | "Subscribe Emma to the early math guide" |
| Weekly summary | "How did we do on Kinderbud this week?" |

## Project Structure

```
kinderbud/
├── SKILL.md              # OpenClaw skill definition
├── scripts/
│   └── kb.sh             # API helper script (auth, requests, error handling)
└── references/
    ├── api_endpoints.md  # Full API reference
    └── data_model.md     # Kinderbud's data model (Guides → Plans → Todos)
```

## Architecture

See [ARCHITECTURE.md](ARCHITECTURE.md) for design decisions, API design, and how this skill interacts with the Kinderbud backend.

## Development

This skill depends on the Kinderbud API (`/api/v1/` endpoints). The API is implemented in the [Kinderbud repo](https://github.com/Liam-Fistos/kinderbud). See the architecture doc for the full endpoint list and cross-repo dependency map.

## License

MIT
