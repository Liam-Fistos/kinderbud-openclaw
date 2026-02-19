# Architecture: Kinderbud + OpenClaw Integration

This document covers the key design decisions for integrating Kinderbud (a hosted parenting guidance app) with OpenClaw (a personal AI agent running on the user's own infrastructure). It is the source of truth for how the two repos interact.

**Repos:**
- **Kinderbud** ([Liam-Fistos/kinderbud](https://github.com/Liam-Fistos/kinderbud)) — FastAPI backend, API endpoints, auth
- **kinderbud-openclaw** ([Liam-Fistos/kinderbud-openclaw](https://github.com/Liam-Fistos/kinderbud-openclaw)) — OpenClaw skill folder, helper scripts, docs

---

## 1. API Authentication Model

### Decision: Per-user bearer tokens, generated from the web UI

**Token lifecycle:**
1. User logs into Kinderbud web UI → Settings → API Tokens
2. Clicks "Generate Token", enters a label (e.g., "OpenClaw on my Mac")
3. Backend generates a token: `kb_live_` + 32 random hex characters
4. Token is shown **once** — user copies it to their OpenClaw config
5. Backend stores a **SHA-256 hash** of the token (not plaintext, not Argon2)
6. User can revoke tokens from the Settings page at any time

**Why SHA-256 (not Argon2):** API tokens are 32 hex chars = 128 bits of entropy. Brute-force is infeasible regardless of hash speed. SHA-256 is fast enough for per-request lookups without being a bottleneck. Argon2 is intentionally slow and designed for low-entropy passwords — it would add unnecessary latency to every API call.

**Why per-user (not per-household):** The token carries the user's identity for audit logging (`performed_by` in `action_log`). Multiple household members can each have their own tokens. The household_id is derived from the user's record at lookup time.

**Database schema (new table):**
```sql
CREATE TABLE IF NOT EXISTS api_tokens (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id INTEGER NOT NULL REFERENCES users(id),
    household_id INTEGER NOT NULL REFERENCES households(id),
    token_hash TEXT NOT NULL UNIQUE,      -- SHA-256 hex digest
    name TEXT NOT NULL,                    -- User-assigned label
    last_used_at TIMESTAMP,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    revoked_at TIMESTAMP                   -- NULL = active, non-NULL = revoked
);
CREATE INDEX IF NOT EXISTS idx_api_tokens_hash ON api_tokens(token_hash);
```

**Auth flow per request:**
1. Client sends `Authorization: Bearer kb_live_<hex>`
2. Middleware computes SHA-256 of the full token
3. Looks up `api_tokens` WHERE `token_hash = ? AND revoked_at IS NULL`
4. Joins to `users` table to get current `role`, `household_id`, `display_name`
5. Returns a user dict identical to what `require_login` returns (same shape, same downstream compatibility)
6. Updates `last_used_at` (debounced — at most once per minute to avoid write amplification)

**Multiple tokens per user:** Supported. Label helps identify which to revoke. No hard limit, but UI shows a warning if >5 active tokens.

**Token scope:** A token has the same permissions as the user's web session. Admin users get admin API access; member users get member access. Role is re-validated on every request (same pattern as `require_admin`).

**No expiry by default:** This is a personal/family app. Forced expiry would just annoy parents who configured their OpenClaw months ago. Tokens are revocable if compromised.

---

## 2. API Endpoint Design

### Decision: RESTful JSON API under `/api/v1/`, no household_id in URLs

The household is derived from the authenticated token. This simplifies the API and eliminates a class of authorization bugs (user A accessing household B's data by changing the URL).

**Base URL:** `https://api.kinderbud.org/api/v1/`

### Endpoint catalog

#### Account & Profile
| Method | Path | Description |
|--------|------|-------------|
| `GET` | `/api/v1/me` | Current user profile, household info, all participants (children + adults) with ages |

#### Daily Selection (the core "morning brief")
| Method | Path | Description |
|--------|------|-------------|
| `GET` | `/api/v1/today` | Today's curated selection: activities, milestones, custom todos, daily note. Triggers LLM curation if not yet cached for today. |

#### Todos
| Method | Path | Description |
|--------|------|-------------|
| `GET` | `/api/v1/todos` | All active todos. Filters: `?participant_id=`, `?category=activity\|milestone\|custom`, `?status=pending\|completed\|snoozed` |
| `GET` | `/api/v1/todos/{id}` | Single todo with full details including source guide item info |
| `POST` | `/api/v1/todos/{id}/complete` | Mark complete. Body: `{"notes": "optional"}` |
| `POST` | `/api/v1/todos/{id}/snooze` | Snooze. Body: `{"days": 1, "reason": "optional"}`. Default: 1 day for activities, 7 for milestones. |
| `POST` | `/api/v1/todos` | Create custom todo. Body: `{"title": "...", "frequency": "once", "description": "...", "participant_id": null}` |

#### Chat (todo clarification / parenting guidance)
| Method | Path | Description |
|--------|------|-------------|
| `POST` | `/api/v1/chat` | Send a message. Body: `{"message": "..."}`. Returns assistant response. Context includes child profiles, active plans, and todo history. |
| `GET` | `/api/v1/chat` | Recent chat history. Query: `?limit=20` |

#### Guides
| Method | Path | Description |
|--------|------|-------------|
| `GET` | `/api/v1/guides` | All available guides (default + household custom). Includes subscription status per participant. |
| `GET` | `/api/v1/guides/{id}` | Guide detail: stages, items, age ranges |

#### Plans (subscriptions)
| Method | Path | Description |
|--------|------|-------------|
| `GET` | `/api/v1/plans` | Active plans for the household |
| `POST` | `/api/v1/plans` | Subscribe participant to guide. Body: `{"participant_id": 1, "guide_id": 2}` |
| `DELETE` | `/api/v1/plans/{id}` | Unsubscribe (soft-delete: sets active=FALSE) |

#### History & Stats
| Method | Path | Description |
|--------|------|-------------|
| `GET` | `/api/v1/history` | Action log entries. Query: `?days=7&participant_id=`. Grouped by date. |
| `GET` | `/api/v1/stats` | Completion stats: streak, weekly/daily counts, totals by participant |

### Response format

**Success:**
```json
{
  "ok": true,
  "data": { ... }
}
```

**Error:**
```json
{
  "ok": false,
  "error": "Human-readable error message",
  "code": "VALIDATION_ERROR"
}
```

**Error codes:** `UNAUTHORIZED`, `FORBIDDEN`, `NOT_FOUND`, `VALIDATION_ERROR`, `RATE_LIMITED`, `INTERNAL_ERROR`

**Why `ok` boolean:** Simpler than checking HTTP status codes from a shell script. The skill's helper script can `jq .ok` and branch cleanly.

### Design principles

- **No household_id in URLs.** Derived from token. Prevents IDOR bugs.
- **CSRF exemption for `/api/v1/`.** Token-based auth doesn't use cookies, so CSRF protection is not needed (and would break non-browser clients). The existing CSRF middleware should skip paths under `/api/v1/`.
- **Independent of HTMX routes.** The API is a parallel route tree. Both trees call the same service functions (e.g., `todo_engine.get_todays_todos`, `daily_curator.get_or_create_daily_selection`). No duplication of business logic.
- **Pagination for list endpoints.** `?limit=` and `?offset=` with sensible defaults. Response includes `total` count.
- **Dates in ISO 8601.** All dates are `YYYY-MM-DD`, all timestamps are ISO 8601 with timezone.

---

## 3. Skill Execution Model

### Decision: Helper shell script (`kb.sh`) wrapping curl + jq

**Why a script (not raw curl in SKILL.md):**
- Auth headers, base URL, content-type, and error handling are boilerplate repeated on every call
- A script centralizes this in ~50 lines, keeping SKILL.md focused on recipes
- The script is transparent and auditable (no compiled binary, no dependencies beyond curl + jq)
- jq is available on all major platforms and commonly installed on developer machines

**Script interface:**
```bash
# GET request
kb.sh get /me
kb.sh get /today
kb.sh get "/todos?participant_id=1&category=activity"

# POST request with JSON body
kb.sh post /todos/42/complete '{"notes": "she loved it"}'
kb.sh post /todos/42/snooze '{"days": 3, "reason": "sick day"}'
kb.sh post /chat '{"message": "What does serve and return mean?"}'

# DELETE request
kb.sh delete /plans/5
```

**Environment variables consumed by the script:**
- `KINDERBUD_API_KEY` — Bearer token (required, injected via OpenClaw config `apiKey`)
- `KINDERBUD_API_URL` — Base URL (default: `https://api.kinderbud.org`, configurable for self-hosted instances)

**Error handling:**
- Non-2xx HTTP status → print error message from response body, exit 1
- Network failure → print "Connection failed", exit 1
- Missing env vars → print setup instructions, exit 1

**SKILL.md references the script as:** `{baseDir}/scripts/kb.sh`

**Platform notes:** The script uses POSIX shell (`#!/usr/bin/env bash`). Works on macOS, Linux, and Windows (via Git Bash, WSL, or Cygwin — all common in OpenClaw setups). jq is declared as a required binary in the skill's metadata gating.

---

## 4. Chat Routing

### Decision: Route through Kinderbud's API (not skill-side Claude calls)

**Current state:** Kinderbud has a `chat_messages` table in the schema but **no chat service or route yet**. The guide chat (`guide_chat.py`) is for guide creation only. Building the todo clarification chat is a new feature that needs to be implemented in the Kinderbud backend.

**Architecture:**
```
User (OpenClaw) → POST /api/v1/chat → chat_service.py → Claude API → response
                                        ↑
                                        | Builds context from:
                                        | - Child profiles (names, ages, stages)
                                        | - Active plans and their guide items
                                        | - Today's curated selection
                                        | - Recent action history
                                        | - Chat message history
```

**Why server-side (not skill-side):**
1. **Shared context.** Chat messages are stored in `chat_messages` and visible from both the web UI and OpenClaw. Starting a conversation in one and continuing in the other works naturally.
2. **Developmental context.** The system prompt needs the child's age, current stage, active guide items, and recent activity history. This data lives in Kinderbud's database — having the skill fetch it all via API and then call Claude directly would be fragile and slow.
3. **Single API key.** The household's Claude API key is stored (encrypted) in Kinderbud's DB. The skill doesn't need to know about it.
4. **Consistent behavior.** One system prompt, one context-building pipeline, one set of safety guardrails. No divergence between web and chat interfaces.

**Scope of the chat:** This is a **todo clarification and parenting guidance** chat, scoped to the household's active guides and children. It is NOT a general-purpose parenting Q&A. The system prompt should instruct Claude to ground responses in the specific guides, activities, and developmental stages the family is tracking.

**Implementation notes:**
- New `app/services/chat_service.py` with a `send_chat_message(household_id, user_id, message)` function
- System prompt template includes: child profiles, current stage per guide, today's curated activities, and recent completion/snooze history
- Uses the household's Claude API key via `claude_client.get_household_api_key()`
- Messages stored in `chat_messages` table (already exists in schema)
- Context window: last 20 messages (configurable) for conversation continuity

---

## 5. Account Creation

### Decision: Web-only registration, token-based API onboarding

**Flow:**
1. User hears about Kinderbud (through OpenClaw's skill description, word of mouth, etc.)
2. Goes to `https://api.kinderbud.org/register` in a browser
3. Completes registration (CAPTCHA, ToS, email/password)
4. Goes through onboarding (add child, set birthday, pick a guide, configure API key)
5. Goes to Settings → API Tokens → Generate Token
6. Copies token into OpenClaw config

**Why not API-based registration:**
- **CAPTCHA.** Cloudflare Turnstile is browser-based (JavaScript widget). An API endpoint can't render it.
- **ToS acceptance.** Legal compliance requires the user to see and accept terms. A CLI flow can technically present text, but it's not standard and may not hold up.
- **Onboarding complexity.** Registration creates a household, user, and adult participant atomically. The onboarding flow then adds children, sets birthdays, picks guides — this is a multi-step wizard that doesn't map well to API calls.
- **One-time cost.** Registration happens once. The marginal UX cost of "open a browser, register, paste a token" is negligible compared to the security risk of an unauthenticated registration API.

**Skill behavior when no token is configured:** The skill detects the missing `KINDERBUD_API_KEY` env var (via metadata gating) and won't load. If the user asks about Kinderbud without the skill loaded, OpenClaw's default behavior is to say it doesn't know about that. If they invoke `/kinderbud` directly, OpenClaw will tell them the skill requires configuration.

**Skill behavior when token is invalid/expired:** The first API call returns 401. The skill instructions tell the agent to display: "Your Kinderbud token is invalid or has been revoked. Generate a new one at https://api.kinderbud.org/settings."

---

## 6. Rate Limiting

### Decision: Per-token, generous defaults, separate tiers for expensive operations

| Category | Limit | Rationale |
|----------|-------|-----------|
| Read endpoints (`GET`) | 120/minute | Morning brief + browsing. A family checking their schedule shouldn't hit this. |
| Write endpoints (`POST`, `DELETE`) | 60/minute | Completing todos, snoozing. Even a very active parent won't do 60 actions per minute. |
| Chat (`POST /api/v1/chat`) | 30/hour | Each call triggers a Claude API call using the household's key. Protects against runaway conversations. |
| Daily curation trigger | 5/day | `GET /today` triggers LLM curation if not cached. 5 is generous (normally 1 per day, but allows for timezone edge cases and cache invalidation). |

**Implementation:**
- Token-level tracking (not IP-based — multiple family members share a network)
- In-memory counter with sliding window (SQLite write per request would be too expensive)
- Returns `429 Too Many Requests` with `Retry-After` header
- Middleware that runs after token auth but before route handlers
- Exempt: the existing HTMX routes (they use session auth, not tokens)

**Why these specific limits:** This is a personal/family app, not a SaaS with enterprise customers. The limits exist to catch misconfigured automation (e.g., a cron job hitting `/today` every minute) rather than intentional abuse. A single family might have 2-3 users, each doing 5-15 actions per day. The limits are 10-100x above normal usage.

---

## 7. Suggested Additional Capabilities (Nice-to-Have)

After reading the codebase, these three capabilities are natural fits:

### 7a. Partner Activity Feed
> "What did Sarah complete today?"

The `action_log` table already tracks `performed_by` (user_id). A simple query joining `action_log` → `users` → `todos` filtered by date and user gives a partner's activity feed. This requires no new backend infrastructure — just a query parameter on the `/history` endpoint (`?performed_by=user_id`) and a skill recipe.

### 7b. Quick-Add Custom Todos from Chat
> "Add 'practice counting to 10' as a weekly activity for Emma"

The `POST /api/v1/todos` endpoint already supports creating custom todos with title, frequency, description, and participant_id. The skill just needs a recipe that extracts these fields from natural language and calls the endpoint. The LLM in OpenClaw handles the NLU; the API is just a structured create.

### 7c. Milestone Progress Check
> "How is Emma doing on milestones?"

The codebase already has `get_active_milestones()` in `todo_engine.py` which returns all displayable milestones with `achieved` status and `achieved_date`. A new `GET /api/v1/milestones` endpoint (or a filter on `/todos?category=milestone`) can expose this. Combined with completion stats from `/stats`, the skill can generate a meaningful progress narrative.

---

## 8. Cross-Repo Dependency Map

```
Phase 1 — API Foundation (Liam-Fistos/kinderbud):
  #213: API token generation, storage, and management
  #214: API auth middleware and route scaffold         [depends on #213]
  #215: GET /me, GET /today endpoints                  [depends on #214]
  #216: Todo action endpoints (complete, snooze, create) [depends on #214]
  #217: Chat service + endpoint (new service)          [depends on #214]
  #218: Guide and plan endpoints                       [depends on #214]
  #219: History and stats endpoints                    [depends on #214]
  #220: Rate limiting middleware                        [depends on #214]
  #221: API integration tests                          [depends on #213–#220]

Phase 2 — Skill Core (Liam-Fistos/kinderbud-openclaw):  [depends on Phase 1 deployed]
  #1: SKILL.md with full instructions and metadata     [depends on #2, #3]
  #2: kb.sh helper script                              [standalone]
  #3: API reference and data model docs                [standalone]
  #4: Setup and installation guide                     [depends on #1]

Phase 3 — Advanced Features (both repos):  [depends on Phases 1-2 stable]
  kinderbud#222: Weekly summary endpoint
  kinderbud-openclaw#5: Weekly summary recipe          [depends on kinderbud#222]
  kinderbud-openclaw#6: Milestone progress check recipe [uses existing endpoints]
  kinderbud-openclaw#7: Partner activity feed recipe   [uses existing endpoints]
  kinderbud-openclaw#8: Cron-triggered daily brief guide [docs only]
  kinderbud-openclaw#9: Quick-add custom todos recipe  [uses existing endpoints]
```

---

## 9. What This Document Does NOT Cover

- **Mobile app API.** The API is designed to be generic, but mobile-specific concerns (push notifications, offline sync, binary uploads) are out of scope.
- **Multi-household tokens.** A token is bound to one user in one household. If someone is in multiple households (not currently supported), this would need revisiting.
- **OAuth / third-party auth.** The API uses first-party bearer tokens only. OAuth flows (for publishing on an app store, etc.) are a future consideration.
- **WebSocket / streaming.** Chat responses are request/response, not streamed. The LLM response is fully generated server-side before returning. Streaming could be added later if latency is a concern.
- **Billing / usage metering.** The household's own Claude API key is used for LLM calls. There's no Kinderbud-side billing.
