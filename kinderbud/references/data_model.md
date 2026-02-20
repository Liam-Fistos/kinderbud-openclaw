# Kinderbud Data Model

Kinderbud uses a three-layer model: **Guides** (curriculum) → **Plans** (household opt-in) → **Todos** (daily actionable items).

## Household & Users

A **household** is the top-level container. Multiple users share a household. The household stores timezone and a shared Claude API key (encrypted).

A **user** is an individual account within a household. Has a `role` (admin or member). Admins can manage settings and invite others; members can use all todo/guide features.

## Participants

A **participant** is a child or adult in the household.

- **Children** have a `birthday` used for age-based stage matching. Age is calculated dynamically from the birthday.
- **Adults** have `is_adult=TRUE` and a sentinel birthday (`1900-01-01`). Each user account has a corresponding adult participant for subscribing to adult-facing guides.

The API returns age info for children:
- `age_display`: human-readable (e.g., "14 months", "2 years 3 months")
- `age_months`: integer for stage matching

## Layer 1: Guides (Curriculum)

A **guide** is a versioned developmental curriculum. Types:
- `default` — system-provided guides seeded on startup (e.g., "Early Development", "Early Literacy")
- `custom` — manually created by users
- `ai_generated` — created through the conversational guide builder

Each guide contains **stages** — age-banded sections with `age_start_months` and `age_end_months` (e.g., "12 to 18 Months"). The child's current age determines which stage is active.

Each stage contains **items** with:
- `category`: `activity` (daily tasks), `milestone` (developmental markers to observe), `guidance` (tips)
- `frequency`: `daily`, `weekly`, `monthly`, `quarterly`, `once`
- `title` and `description`: what to do
- `evidence_summary`: research backing for the activity (optional)

## Layer 2: Plans (Subscriptions)

A **plan** links a participant to a guide — it represents the household's opt-in to that curriculum for that child. One plan per participant per guide (enforced by unique constraint).

Plans can be active or inactive. Deactivating a plan (unsubscribing) also deactivates all todos generated from that plan.

> **CLI terminology:** Present plans as "subscribe to guide" / "unsubscribe from guide" — the plan abstraction shouldn't be exposed to end users.

## Layer 3: Todos (Daily Items)

A **todo** is a daily actionable item. Two sources:

| Field | Guide-sourced | Custom |
|-------|--------------|--------|
| `source_type` | `guide` | `custom` |
| `guide_item_id` | populated | NULL |
| `plan_id` | populated | NULL |
| `created_by` | NULL (system) | user_id |
| Editable? | No | Yes (title, description, frequency) |
| Deletable? | No | Yes (soft-delete via active=FALSE) |

**Frequencies:** `once`, `daily`, `weekly`, `monthly`, `quarterly`. One-time todos (`once`) are deactivated after completion (except milestones, which stay visible with an "Achieved" badge).

**Active flag:** `active=TRUE` means the todo appears in the daily pool. Set to FALSE when: completed (once-frequency), permanently dismissed, deleted, or plan unsubscribed.

## Action Log

The **action log** records what happened to each todo:

| action_type | Meaning |
|-------------|---------|
| `completed` | User marked it done |
| `snoozed` | Temporarily hidden (has `snoozed_to` date) |
| `skipped` | Permanently dismissed (has optional `snooze_reason`) |

Each entry records `performed_by` (user_id) and `action_date` (the calendar date the action applies to).

**Soft-delete for undo:** Action log entries have a `deleted_at` field. Undoing an action sets `deleted_at` rather than hard-deleting the row. Queries filter with `deleted_at IS NULL`.

## Daily Selection (LLM Curation)

Each day, the system curates a personalized set of activities:

1. The **todo engine** generates candidate todos from active plans (filtered by child's current stage, frequency windows, and snooze dates)
2. The **daily curator** sends candidates to Claude, which picks 8 activities (configurable 3-15) and writes a `daily_note` explaining the day's focus
3. The result is cached in `daily_selections` (one per household per day)

**First-call latency:** The first `GET /today` request of the day triggers LLM curation (5-15 seconds). All subsequent requests return instantly from cache.

**Fallback mode:** If no Claude API key is configured, the system returns a random selection from the candidate pool without LLM curation.
