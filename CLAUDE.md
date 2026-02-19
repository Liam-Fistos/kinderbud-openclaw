# kinderbud-openclaw

OpenClaw skill for Kinderbud — manage parenting activities and child development tracking via AI chat.

## Repo Structure

```
kinderbud/                 # The OpenClaw skill folder (what users install)
├── SKILL.md               # Skill definition: frontmatter + agent instructions
├── scripts/
│   └── kb.sh              # API helper script (curl wrapper with auth/error handling)
└── references/
    ├── api_endpoints.md   # Full Kinderbud API reference
    └── data_model.md      # Guides → Plans → Todos domain model
```

## Relationship to Kinderbud

**Kinderbud is a hosted service. OpenClaw runs on the user's own infrastructure.** The skill makes authenticated API calls over HTTPS to Kinderbud's `/api/v1/` endpoints. The API lives in the [Kinderbud repo](https://github.com/Liam-Fistos/kinderbud) — no API code belongs in this repo.

- API auth: per-user bearer tokens (`kb_live_` prefix), generated from Kinderbud's web UI Settings page
- Token is configured in OpenClaw via `skills.entries.kinderbud.apiKey` in `openclaw.json`
- Base URL defaults to `https://api.kinderbud.org`, configurable via `KINDERBUD_API_URL` env var

## Kinderbud Backend Context

Agents working on this repo need to understand the Kinderbud backend they're calling into. You don't need access to the Kinderbud repo to work on skill issues, but this context is essential.

### Tech Stack (backend)

- **Backend:** Python 3.13, FastAPI, Uvicorn
- **Database:** SQLite3 with WAL mode (no ORM — raw SQL via `db.fetch_one`, `db.fetch_all`, `db.execute`, `db.transaction()`)
- **AI:** Anthropic Claude API for daily activity curation and guide generation
- **Security:** Argon2 password hashing, Fernet encryption for API keys, CSRF double-submit cookie (exempted for `/api/v1/` bearer-token routes), Cloudflare Turnstile for registration
- **Deployment:** Docker + Caddy reverse proxy on Hetzner VPS

### Data Model

Three-layer model: **Guides** (curriculum) → **Plans** (household opt-in) → **Todos** (daily actionable items).

- **Household:** top-level container. Multiple users share a household. Stores timezone and the shared Claude API key (encrypted).
- **User:** individual account within a household. Has `role` (admin or member).
- **Participant:** a child or adult in the household, with `birthday` for age calculations. Adults use `1900-01-01` as a sentinel birthday and have `is_adult=TRUE`.
- **Guide:** a versioned developmental curriculum (system default or user-created). Contains stages.
- **Guide Stage:** an age-banded section (e.g., "12 to 18 Months") with `age_start_months` and `age_end_months`.
- **Guide Item:** a specific activity, milestone, or guidance within a stage. Has `category` (activity, milestone, guidance, custom) and `frequency` (daily, weekly, monthly, quarterly, once).
- **Plan:** a household's subscription of a participant to a guide. `UNIQUE(household_id, participant_id, guide_id)`.
- **Todo:** a daily actionable item, either guide-sourced or custom. Has `source_type` (guide, custom, ai_generated) and `category`.
- **Action Log:** completion/snooze/skip records. Tracks `performed_by` (user_id), `action_date`, `snoozed_to`, and supports soft-delete via `deleted_at`.
- **Daily Selection:** the LLM-curated set of activities for a given day. One per household per day, cached in `daily_selections` table.
- **Chat Messages:** general parenting chat history, stored per-household.

### Key Patterns

- **Daily todo pipeline:** `todo_engine.py` generates candidates → `daily_curator.py` uses Claude to pick 8-10 age-appropriate activities → cached in `daily_selections` table. First call of the day triggers LLM curation (5-15s latency).
- **Guide creation:** conversational chat (`guide_chat.py`) → Claude generates JSON guide with age-banded stages and items.
- **Households share one Claude API key;** multiple users collaborate on shared plans/todos.
- **Thin routes, fat services:** routes handle HTTP; business logic lives in `app/services/`.
- **Naming:** `snake_case` for functions/variables/db columns, `PascalCase` for classes, `UPPER_SNAKE_CASE` for constants.

### API Endpoint Catalog

All under `/api/v1/`. Auth via `Authorization: Bearer kb_live_...`. Household derived from token (not in URLs).

| Method | Path | Description |
|--------|------|-------------|
| `GET` | `/health` | Connectivity check (no auth required) |
| `GET` | `/me` | User profile, household, participants with ages/stages |
| `GET` | `/today` | Today's curated selection (triggers LLM if uncached) |
| `GET` | `/todos/{id}` | Single todo with guide item details |
| `POST` | `/todos/{id}/complete` | Mark complete (optional `notes`) |
| `POST` | `/todos/{id}/snooze` | Snooze (optional `days`, `reason`) |
| `POST` | `/todos` | Create custom todo |
| `POST` | `/chat` | Send parenting chat message |
| `GET` | `/chat` | Recent chat history |
| `GET` | `/guides` | Available guides with subscription status |
| `GET` | `/guides/{id}` | Guide detail with stages and items |
| `GET` | `/plans` | Active plans |
| `POST` | `/plans` | Subscribe participant to guide |
| `DELETE` | `/plans/{id}` | Unsubscribe (soft-delete) |
| `GET` | `/history` | Action log (filterable by days, participant, action_type) |
| `GET` | `/stats` | Streak, weekly stats, per-participant counts |
| `GET` | `/summary` | Period summary (Phase 3) |

**Response envelope:** `{"ok": true, "data": {...}}` on success, `{"ok": false, "error": "...", "code": "..."}` on error.

**Error codes:** `UNAUTHORIZED`, `FORBIDDEN`, `NOT_FOUND`, `VALIDATION_ERROR`, `RATE_LIMITED`, `INTERNAL_ERROR`, `NO_API_KEY`, `ALREADY_SUBSCRIBED`.

## Architecture & Design Decisions

See [ARCHITECTURE.md](ARCHITECTURE.md) for the full design document covering:
1. API auth model (per-user bearer tokens, SHA-256 hashed)
2. API endpoint catalog (RESTful under `/api/v1/`, no household_id in URLs)
3. Skill execution model (kb.sh helper script wrapping curl + jq)
4. Chat routing (through Kinderbud's backend, not skill-side)
5. Account creation (web-only registration, token paste into OpenClaw)
6. Rate limiting (per-token, generous defaults)

## Issue Tracker & Phases

Work is split across two repos. Always create issues in the correct repo.

### Phase 1 — API Foundation ([Liam-Fistos/kinderbud](https://github.com/Liam-Fistos/kinderbud))

| Issue | Title | Depends on |
|-------|-------|------------|
| kinderbud#213 | API token generation, storage, and management | — |
| kinderbud#214 | API auth middleware and route scaffold | #213 |
| kinderbud#215 | GET /me and GET /today endpoints | #214 |
| kinderbud#216 | Todo action endpoints (complete, snooze, create) | #214 |
| kinderbud#217 | Parenting chat service and API endpoint | #214 |
| kinderbud#218 | Guide and plan endpoints | #214 |
| kinderbud#219 | History and stats endpoints | #214 |
| kinderbud#220 | Rate limiting middleware | #214 |
| kinderbud#221 | API integration tests | #213–#220 |

### Phase 2 — Skill Core (this repo)

| Issue | Title | Depends on |
|-------|-------|------------|
| #1 | SKILL.md with full instructions and metadata | #2, #3 |
| #2 | kb.sh helper script | standalone |
| #3 | API reference and data model docs | standalone |
| #4 | Setup and installation guide | #1 |

### Phase 3 — Advanced Features (both repos)

| Issue | Repo | Title |
|-------|------|-------|
| kinderbud#222 | kinderbud | Weekly summary endpoint |
| #5 | this repo | Weekly summary recipe |
| #6 | this repo | Milestone progress check recipe |
| #7 | this repo | Partner activity feed recipe |
| #8 | this repo | Cron-triggered daily brief guide |
| #9 | this repo | Quick-add custom todos recipe |

### Critical Path

```
kinderbud#213 → #214 → #215–#220 (parallelizable) → #221 → Deploy
  → Then Phase 2: #2 + #3 (parallel) → #1 → #4
  → Then Phase 3 (all independent)
```

## Conventions for Agents Working on This Repo

- **SKILL.md body must stay under ~500 lines.** Detailed docs go in `references/`. The agent reads them on demand via `{baseDir}/references/`.
- **All API calls go through `kb.sh`.** SKILL.md recipes reference it as `{baseDir}/scripts/kb.sh`. Don't put raw curl commands in SKILL.md.
- **`{baseDir}` is an OpenClaw placeholder** that resolves to the skill's installed folder path at runtime. Use it in SKILL.md instructions, not hardcoded paths.
- **The `description` field in SKILL.md frontmatter is the trigger.** OpenClaw reads it to decide when the skill is relevant. Include all nouns and verbs users might say.
- **No Kinderbud API code in this repo.** If a feature needs a new endpoint, create an issue in the Kinderbud repo and note the cross-repo dependency.
- **Test against the real API.** The skill can't be meaningfully tested without Phase 1 deployed. Manual testing: install the skill in OpenClaw, configure a token, try each recipe.
- **SKILL.md frontmatter uses `user-invocable` (with a 'c').** The IDE linter may flag this as unsupported and suggest `user-invokable` — ignore it. The official OpenClaw docs and source code use the `user-invocable` spelling.

## Agent Usage

When using agents, call the Task tool as many times as needed in a single message (do NOT use `run_in_background`). They will execute in parallel and return results directly — no need to read output files or resume agents.

## Debugging

- **Verify assumptions before fixing.** A plausible-sounding explanation can mask the real root cause. Fix the verified cause, not the assumed one.
- **Don't break intended behavior.** Kinderbud has nuanced domain rules (frequency windows, age blending, stage transitions, curation pool filtering) where "looks like a bug" may actually be "works as designed." If unsure, ask the user.

## Risks & Known Gaps

1. **`chat_service.py` doesn't exist in Kinderbud yet.** The `chat_messages` table exists but no service or route. kinderbud#217 builds it from scratch — it's the largest Phase 1 issue.
2. **First-call latency on `GET /today`.** If the daily curation isn't cached, it triggers an LLM call (5-15s). The morning brief recipe should handle this gracefully.
3. **`kb.sh` assumes bash.** Works on macOS/Linux natively, Windows via Git Bash or WSL. No pure-Windows fallback.

## Self-Improvement

When a command fails, a tool call is rejected, the user corrects you, or you discover something unexpected about the codebase or environment, pause and consider: **would adding a note to this CLAUDE.md file prevent the same mistake in the future?** If so, propose the addition to the user.

Examples of things worth capturing:
- A command or tool that doesn't work as expected on this platform (e.g., Windows/bash quirks).
- A codebase convention you got wrong that the user had to correct.
- A workflow or process detail that wasn't documented and caused confusion.
- An assumption you made that turned out to be wrong (e.g., file locations, API behavior, naming patterns).
- An OpenClaw spec detail that differs from what you'd expect (e.g., the `user-invocable` spelling).

Keep additions concise and place them in the most relevant existing section. If no section fits, add a bullet to this section. The goal is to build a persistent memory of project-specific lessons so the same mistakes aren't repeated across sessions.
