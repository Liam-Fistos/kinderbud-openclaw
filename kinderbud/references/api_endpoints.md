# Kinderbud API Reference

Base URL: `https://api.kinderbud.org/api/v1`
Auth: `Authorization: Bearer kb_live_...` (all endpoints except `/health`)

## Response Format

**Success:**
```json
{"ok": true, "data": { ... }}
```

**Error:**
```json
{"ok": false, "error": "Human-readable message", "code": "ERROR_CODE"}
```

**Error codes:** `UNAUTHORIZED`, `FORBIDDEN`, `NOT_FOUND`, `VALIDATION_ERROR`, `RATE_LIMITED`, `NO_API_KEY`, `ALREADY_SUBSCRIBED`, `INTERNAL_ERROR`

## Rate Limits

| Tier | Endpoints | Limit | Header |
|------|-----------|-------|--------|
| Read | All `GET` | 120/min | `X-RateLimit-Limit`, `X-RateLimit-Remaining` |
| Write | `POST`, `PUT`, `DELETE` (except chat) | 60/min | same |
| Chat | `POST /chat` | 30/hr | same |

429 responses include a `Retry-After` header (seconds).

---

## Health

### GET /health

Unauthenticated connectivity check.

```bash
kb.sh get /health
```

```json
{"ok": true, "data": {"version": "1"}}
```

---

## Profile

### GET /me

Returns the authenticated user's profile, household info, and all participants with ages and current stages.

```bash
kb.sh get /me
```

```json
{
  "ok": true,
  "data": {
    "user": {
      "id": 1,
      "display_name": "Sarah",
      "email": "sarah@example.com",
      "role": "admin"
    },
    "household": {
      "id": 1,
      "name": "The Johnsons",
      "timezone": "America/New_York",
      "daily_task_count": 8
    },
    "participants": [
      {
        "id": 2,
        "name": "Emma",
        "is_adult": false,
        "birthday": "2024-11-15",
        "age_display": "14 months",
        "age_months": 14,
        "current_stages": [
          {
            "guide_id": 1,
            "guide_title": "Early Development",
            "stage_name": "12 to 18 Months"
          }
        ]
      },
      {
        "id": 3,
        "name": "Sarah",
        "is_adult": true,
        "birthday": null,
        "age_display": null,
        "age_months": null,
        "current_stages": []
      }
    ]
  }
}
```

---

## Daily Selection

### GET /today

Returns today's LLM-curated activity selection. First call of the day triggers curation (5-15 seconds); subsequent calls return from cache.

**Query params:**
| Param | Type | Description |
|-------|------|-------------|
| `participant_id` | int (optional) | Filter activities/milestones to one participant |

```bash
kb.sh get /today
kb.sh get "/today?participant_id=2"
```

```json
{
  "ok": true,
  "data": {
    "date": "2026-02-19",
    "daily_note": "Today we're focusing on motor skills and early literacy...",
    "source": "llm",
    "cached": true,
    "activities": [
      {
        "id": 42,
        "title": "Tummy Time",
        "description": "Place baby on their tummy for 3-5 minutes...",
        "category": "activity",
        "frequency": "daily",
        "participant_id": 2,
        "participant_name": "Emma",
        "status": "pending",
        "guide_item_id": 15,
        "guide_title": "Early Development",
        "achieved": null
      }
    ],
    "milestones": [
      {
        "id": 55,
        "title": "Pulls to stand",
        "description": "Baby pulls themselves up using furniture...",
        "category": "milestone",
        "frequency": "once",
        "participant_id": 2,
        "participant_name": "Emma",
        "status": "pending",
        "guide_item_id": 28,
        "guide_title": "Early Development",
        "achieved": false
      }
    ],
    "custom_todos": [
      {
        "id": 101,
        "title": "Read bedtime story",
        "description": null,
        "category": "activity",
        "frequency": "daily",
        "participant_id": 2,
        "participant_name": "Emma",
        "status": "completed",
        "guide_item_id": null,
        "guide_title": null,
        "achieved": null
      }
    ]
  }
}
```

**Status values:** `pending`, `completed`, `snoozed`, `skipped`

---

## Todos

### GET /todos/{id}

Get a single todo with full details, including guide item info for guide-sourced todos.

```bash
kb.sh get /todos/42
```

```json
{
  "ok": true,
  "data": {
    "id": 42,
    "title": "Tummy Time",
    "description": "Place baby on their tummy for 3-5 minutes...",
    "category": "activity",
    "frequency": "daily",
    "participant_id": 2,
    "participant_name": "Emma",
    "status": "pending",
    "guide_item_id": 15,
    "guide_title": "Early Development",
    "achieved": null,
    "source_type": "guide",
    "guide_item": {
      "id": 15,
      "title": "Tummy Time",
      "description": "Extended description with how-to details...",
      "evidence_summary": "Research shows tummy time strengthens...",
      "guide_title": "Early Development"
    }
  }
}
```

### POST /todos/{id}/complete

Mark a todo as completed for today. Idempotent — calling twice returns success without duplicating the action.

**Body (optional):**
```json
{"notes": "She loved it today!"}
```

```bash
kb.sh post /todos/42/complete '{"notes": "She loved it today!"}'
```

```json
{
  "ok": true,
  "data": {
    "todo_id": 42,
    "action": "completed",
    "action_date": "2026-02-19",
    "notes": "She loved it today!"
  }
}
```

### POST /todos/{id}/snooze

Snooze a todo (hide temporarily) or permanently dismiss it.

**Body:**
```json
{
  "days": 3,
  "reason": "Sick day",
  "permanent": false
}
```

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `days` | int (1-90) | 1 (activities), 7 (milestones) | Days to snooze |
| `reason` | string (max 500) | null | Optional reason (fed to LLM curator) |
| `permanent` | bool | false | If true, permanently dismisses (sets active=FALSE) |

```bash
kb.sh post /todos/42/snooze '{"days": 3}'
kb.sh post /todos/55/snooze '{"permanent": true, "reason": "She already does this"}'
```

**Timed snooze response:**
```json
{
  "ok": true,
  "data": {
    "todo_id": 42,
    "action": "snoozed",
    "action_date": "2026-02-19",
    "snoozed_to": "2026-02-22",
    "reason": null
  }
}
```

**Permanent dismiss response:**
```json
{
  "ok": true,
  "data": {
    "todo_id": 55,
    "action": "skipped",
    "action_date": "2026-02-19",
    "reason": "She already does this"
  }
}
```

### POST /todos/{id}/undo

Undo the most recent action on a todo (soft-deletes the action_log entry). Re-activates the todo if the action had deactivated it.

**Body (required):**
```json
{"action_id": 123}
```

The `action_id` can be found from `GET /history`.

```bash
kb.sh post /todos/42/undo '{"action_id": 123}'
```

```json
{
  "ok": true,
  "data": {
    "todo_id": 42,
    "undone_action_id": 123,
    "undone_action_type": "completed"
  }
}
```

**Errors:** 404 if action_id doesn't exist, doesn't match the todo_id, or was already undone.

### PUT /todos/{id}

Edit a custom todo. Only works for `source_type='custom'` todos — guide-sourced todos return 404.

**Body:**
```json
{
  "title": "Updated title",
  "description": "New description",
  "frequency": "weekly",
  "participant_id": 2
}
```

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `title` | string (max 200) | yes | New title |
| `description` | string (max 2000) | no | New description (null to clear) |
| `frequency` | string | no | `once`, `daily`, `weekly`, `monthly`, `quarterly`. Omit to keep current. |
| `participant_id` | int | no | Omit to keep current. Must belong to your household. |

```bash
kb.sh put /todos/101 '{"title": "Read two bedtime stories", "frequency": "daily"}'
```

```json
{
  "ok": true,
  "data": {
    "id": 101,
    "title": "Read two bedtime stories",
    "description": null,
    "frequency": "daily",
    "participant_id": 2,
    "source_type": "custom"
  }
}
```

### DELETE /todos/{id}

Soft-delete a custom todo (sets active=FALSE). Only works for `source_type='custom'` — guide-sourced todos return 404. Action log entries are preserved for history.

```bash
kb.sh delete /todos/101
```

```json
{
  "ok": true,
  "data": {
    "todo_id": 101,
    "active": false
  }
}
```

### POST /todos

Create a custom todo.

**Body:**
```json
{
  "title": "Practice counting to 10",
  "description": "Count objects around the house",
  "frequency": "daily",
  "participant_id": 2
}
```

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `title` | string (max 200) | yes | Activity title |
| `description` | string (max 2000) | no | Details |
| `frequency` | string | no | Default: `once`. Options: `once`, `daily`, `weekly`, `monthly`, `quarterly` |
| `participant_id` | int | no | Defaults to youngest child if omitted |

```bash
kb.sh post /todos '{"title": "Practice counting to 10", "frequency": "daily", "participant_id": 2}'
```

```json
{
  "ok": true,
  "data": {
    "id": 102,
    "title": "Practice counting to 10",
    "description": null,
    "frequency": "daily",
    "participant_id": 2,
    "source_type": "custom",
    "category": "activity"
  }
}
```

---

## Guides

### GET /guides

List all available guides with subscription status per participant.

```bash
kb.sh get /guides
```

```json
{
  "ok": true,
  "data": {
    "guides": [
      {
        "id": 1,
        "title": "Early Development: Motor, Sensory, Cognitive & Self-Regulation",
        "description": "A comprehensive guide covering...",
        "source_type": "default",
        "color": "#4F46E5",
        "stage_count": 12,
        "item_count": 156,
        "subscribed_participants": [
          {
            "participant_id": 2,
            "participant_name": "Emma",
            "plan_id": 1
          }
        ]
      }
    ]
  }
}
```

### GET /guides/{id}

Get guide detail with all stages and items.

```bash
kb.sh get /guides/1
```

```json
{
  "ok": true,
  "data": {
    "id": 1,
    "title": "Early Development",
    "description": "...",
    "source_type": "default",
    "color": "#4F46E5",
    "stages": [
      {
        "id": 1,
        "stage_key": "12_to_18_months",
        "name": "12 to 18 Months",
        "age_start_months": 12,
        "age_end_months": 18,
        "goals": "Focus on walking, first words...",
        "items": [
          {
            "id": 15,
            "item_key": "tummy_time",
            "category": "activity",
            "title": "Tummy Time",
            "description": "Place baby on their tummy...",
            "frequency": "daily"
          }
        ]
      }
    ]
  }
}
```

---

## Plans (Guide Subscriptions)

### GET /plans

List active plans (guide subscriptions) for the household.

```bash
kb.sh get /plans
```

```json
{
  "ok": true,
  "data": {
    "plans": [
      {
        "id": 1,
        "participant_id": 2,
        "participant_name": "Emma",
        "guide_id": 1,
        "guide_title": "Early Development",
        "active": true,
        "created_at": "2026-01-15T10:30:00",
        "current_stage": "12 to 18 Months"
      }
    ]
  }
}
```

### POST /plans

Subscribe a participant to a guide.

**Body:**
```json
{"participant_id": 2, "guide_id": 3}
```

```bash
kb.sh post /plans '{"participant_id": 2, "guide_id": 3}'
```

```json
{
  "ok": true,
  "data": {
    "id": 5,
    "participant_id": 2,
    "participant_name": "Emma",
    "guide_id": 3,
    "guide_title": "Early Math & Numeracy Development",
    "current_stage": "12 to 18 Months",
    "active": true
  }
}
```

**Error:** 409 `ALREADY_SUBSCRIBED` if participant is already subscribed to that guide.

### DELETE /plans/{id}

Unsubscribe from a guide (soft-delete). Also deactivates all todos from that plan.

```bash
kb.sh delete /plans/5
```

```json
{
  "ok": true,
  "data": {
    "plan_id": 5,
    "active": false
  }
}
```

---

## Chat

### POST /chat

Send a parenting question and get an AI response. Uses the household's Claude API key. Context includes child profiles, active guides, and recent activity history.

**Body:**
```json
{"message": "How should I do the serve-and-return activity with a 14-month-old?"}
```

```bash
kb.sh post /chat '{"message": "How should I do serve-and-return?"}'
```

```json
{
  "ok": true,
  "data": {
    "role": "assistant",
    "content": "Serve and return is a simple but powerful interaction pattern...",
    "created_at": "2026-02-19T14:30:00"
  }
}
```

**Error:** 400 `NO_API_KEY` if the household hasn't configured a Claude API key.

### GET /chat

Return recent chat messages for the household.

**Query params:**
| Param | Type | Default | Description |
|-------|------|---------|-------------|
| `limit` | int (1-100) | 20 | Number of messages to return |

```bash
kb.sh get /chat
kb.sh get "/chat?limit=10"
```

```json
{
  "ok": true,
  "data": {
    "messages": [
      {
        "role": "user",
        "content": "How should I do serve-and-return?",
        "created_at": "2026-02-19T14:29:00"
      },
      {
        "role": "assistant",
        "content": "Serve and return is a simple but powerful...",
        "created_at": "2026-02-19T14:30:00"
      }
    ]
  }
}
```

---

## History & Stats

### GET /history

Return action log entries grouped by date.

**Query params:**
| Param | Type | Default | Description |
|-------|------|---------|-------------|
| `days` | int (1-90) | 7 | Number of days to look back |
| `participant_id` | int | null | Filter to one participant |
| `action_type` | string | null | Filter: `completed`, `snoozed`, `skipped` |

```bash
kb.sh get /history
kb.sh get "/history?days=7&action_type=completed"
```

```json
{
  "ok": true,
  "data": {
    "days": 7,
    "total_actions": 23,
    "entries": [
      {
        "date": "2026-02-19",
        "actions": [
          {
            "id": 123,
            "todo_id": 42,
            "todo_title": "Tummy Time",
            "action_type": "completed",
            "performed_by": "Sarah",
            "notes": null,
            "created_at": "2026-02-19T09:15:00"
          }
        ]
      }
    ]
  }
}
```

The `id` field on each action is the `action_id` needed for the undo endpoint.

### GET /stats

Return completion statistics: streak, weekly summary, and per-participant counts.

```bash
kb.sh get /stats
```

```json
{
  "ok": true,
  "data": {
    "streak": 5,
    "week": {
      "completed": 18,
      "total": 40,
      "by_day": {
        "Mon": 3,
        "Tue": 4,
        "Wed": 3,
        "Thu": 4,
        "Fri": 4,
        "Sat": 0,
        "Sun": 0
      }
    },
    "by_participant": [
      {
        "participant_id": 2,
        "participant_name": "Emma",
        "completed_7d": 18,
        "completed_30d": 65
      }
    ]
  }
}
```
