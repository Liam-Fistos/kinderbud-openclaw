---
name: kinderbud
description: Manage Kinderbud parenting activities and child development tracking. Use when the user asks about daily activities, today's schedule, completing or snoozing todos, child development guides, parenting activity tips, developmental milestones, or weekly progress for their children. Handles morning briefs, todo management, guide subscriptions, and parenting guidance chat.
user-invocable: true
metadata: {"openclaw":{"emoji":"seedling","primaryEnv":"KINDERBUD_API_KEY","requires":{"env":["KINDERBUD_API_KEY"],"anyBins":["curl"]},"os":["darwin","linux","win32"]}}
---

# Kinderbud

You help manage a Kinderbud household — a parenting app that converts developmental curricula into daily actionable activities that adapt as children grow.

## Setup

- API key is provided via `KINDERBUD_API_KEY` environment variable
- API base URL is in `KINDERBUD_API_URL` (default: `https://api.kinderbud.org`)
- Helper script: `{baseDir}/scripts/kb.sh`
- For full API details, read `{baseDir}/references/api_endpoints.md`
- For the data model, read `{baseDir}/references/data_model.md`

## Important Rules

1. **All API calls go through `{baseDir}/scripts/kb.sh`** — never use raw curl commands. The script handles auth headers, base URL, and error handling.
2. **Check `.ok` in responses.** Every API response has `{"ok": true/false, ...}`. Parse with jq: pipe through `jq -r '.data.field'` to extract values.
3. **Never dump raw JSON to the user.** Format results in a readable way — bullet lists, tables, or natural language. Only show raw JSON if the user explicitly asks.
4. **Match todos by name, not ID.** When the user says "mark tummy time as done", fetch today's list, find the best title match, then act on that ID. If ambiguous, ask.
5. **Plans = subscriptions.** Never say "plan" to the user — say "subscribe to guide" or "unsubscribe from guide".
6. **First call of the day is slow.** `GET /today` triggers LLM curation on first call (~5-15 seconds). Tell the user it's loading if they seem impatient. All subsequent calls are instant.
7. **Custom vs guide-sourced todos.** Only custom todos can be edited or deleted. Guide-sourced todos are read-only (the API returns 404 if you try). Don't offer to edit/delete guide todos.

## How to Use kb.sh

```bash
# GET request
{baseDir}/scripts/kb.sh get /me
{baseDir}/scripts/kb.sh get "/today?participant_id=2"

# POST request with JSON body
{baseDir}/scripts/kb.sh post /todos/42/complete '{"notes": "she loved it"}'

# PUT request with JSON body
{baseDir}/scripts/kb.sh put /todos/101 '{"title": "New title", "frequency": "weekly"}'

# DELETE request
{baseDir}/scripts/kb.sh delete /plans/5
```

The script exits 0 on success, 1 on failure. On failure it prints the error to stderr.

## Recipes

### Morning Brief

The primary use case — give the user an overview of today's activities.

1. Fetch household context:
   ```bash
   {baseDir}/scripts/kb.sh get /me
   ```
   Extract: participant names, children's ages, household name.

2. Fetch today's curated selection:
   ```bash
   {baseDir}/scripts/kb.sh get /today
   ```
   Extract: `daily_note`, `activities`, `milestones`, `custom_todos`, each item's `status`.

3. Fetch current streak:
   ```bash
   {baseDir}/scripts/kb.sh get /stats
   ```
   Extract: `streak`, `week.completed`.

4. Format the response:
   - Greeting with the household name or user's name
   - The daily note (curator's message about today's focus)
   - **Activities** grouped by participant, showing status (pending/completed/snoozed):
     - Pending items: show title and a brief description
     - Completed items: show with a checkmark
     - Snoozed items: note they're snoozed
   - **Milestones to Watch** — milestones with `achieved: false`
   - **Custom Todos** — user-created items
   - Streak and weekly progress at the bottom

If there's only one child, no need to group by participant.

### Complete a Todo

When the user says something like "mark tummy time as done" or "we did the reading activity":

1. Fetch today's list:
   ```bash
   {baseDir}/scripts/kb.sh get /today
   ```

2. Find the best match from `activities`, `milestones`, and `custom_todos` by comparing titles. If multiple partial matches, list them and ask which one.

3. Complete it:
   ```bash
   {baseDir}/scripts/kb.sh post /todos/{id}/complete '{"notes": "optional user notes"}'
   ```
   Include notes if the user provided any context (e.g., "she loved it", "he struggled a bit").

4. Confirm: "Marked **{title}** as completed!"

### Snooze a Todo

When the user wants to skip or delay an activity:

1. Find the todo (same matching as Complete).

2. Determine the intent:
   - "snooze", "skip today", "do it tomorrow" → timed snooze, default 1 day
   - "snooze for X days" → timed snooze with specific duration
   - "remove", "dismiss", "never show again", "she's past this" → permanent dismiss

3. Call the appropriate snooze:
   ```bash
   # Timed snooze
   {baseDir}/scripts/kb.sh post /todos/{id}/snooze '{"days": 3, "reason": "sick day"}'

   # Permanent dismiss
   {baseDir}/scripts/kb.sh post /todos/{id}/snooze '{"permanent": true, "reason": "she already does this"}'
   ```
   Include `reason` if the user gave one — it helps the LLM curator avoid suggesting similar items.

4. Confirm: "Snoozed **{title}** until {date}" or "Permanently dismissed **{title}**."

### Undo an Action

When the user says "undo that", "I didn't mean to complete that", "un-snooze tummy time":

1. Fetch recent history to find the action ID:
   ```bash
   {baseDir}/scripts/kb.sh get "/history?days=1"
   ```

2. Find the action entry that matches what the user wants to undo. Each action has an `id` (the action_id) and `todo_id`.

3. Undo it:
   ```bash
   {baseDir}/scripts/kb.sh post /todos/{todo_id}/undo '{"action_id": {action_id}}'
   ```

4. Confirm: "Undid **{action_type}** on **{todo_title}**. It's back to pending."

### Edit a Custom Todo

When the user wants to change a custom todo's title, description, frequency, or assignment:

1. Find the todo. Only custom todos (not guide-sourced) can be edited. Check `source_type` via:
   ```bash
   {baseDir}/scripts/kb.sh get /todos/{id}
   ```
   If `source_type` is not `custom`, tell the user this is a guide-sourced activity and can't be edited.

2. Apply the edit — only include changed fields:
   ```bash
   {baseDir}/scripts/kb.sh put /todos/{id} '{"title": "New title", "frequency": "weekly"}'
   ```
   `title` is always required. `description`, `frequency`, and `participant_id` are optional (omit to keep current values).

3. Confirm the changes.

### Delete a Custom Todo

When the user wants to remove a custom todo entirely:

1. Find the todo and confirm it's custom (same as Edit).

2. Confirm with the user: "Delete **{title}**? This will remove it from your daily activities."

3. Delete:
   ```bash
   {baseDir}/scripts/kb.sh delete /todos/{id}
   ```
   This is a soft-delete (sets active=FALSE). Past completions are preserved in history.

4. Confirm: "Deleted **{title}**."

### Create a Custom Todo

When the user says "add a todo", "create an activity for counting", "remind me to do X":

1. Extract from the user's request:
   - **title** (required): the activity name
   - **description** (optional): details or instructions
   - **frequency** (optional): `once` (default), `daily`, `weekly`, `monthly`, `quarterly`
   - **participant** (optional): which child; defaults to youngest

2. If a participant is needed and the household has multiple children, fetch the list:
   ```bash
   {baseDir}/scripts/kb.sh get /me
   ```
   Match the child by name.

3. Create:
   ```bash
   {baseDir}/scripts/kb.sh post /todos '{"title": "Practice counting to 10", "frequency": "daily", "participant_id": 2}'
   ```

4. Confirm: "Created **{title}** as a {frequency} activity for {participant_name}."

### Browse Guides

When the user asks "what guides are available?" or "show me the guides":

1. Fetch guides:
   ```bash
   {baseDir}/scripts/kb.sh get /guides
   ```

2. Format as a list showing:
   - Title
   - Description (brief)
   - Stage count and item count
   - Which participants are subscribed (if any)

3. For detail on a specific guide:
   ```bash
   {baseDir}/scripts/kb.sh get /guides/{id}
   ```
   Show stages with age ranges and sample items.

### Subscribe to a Guide

When the user says "subscribe Emma to the math guide" or "add the literacy guide":

1. Get participant IDs:
   ```bash
   {baseDir}/scripts/kb.sh get /me
   ```

2. Get guide IDs:
   ```bash
   {baseDir}/scripts/kb.sh get /guides
   ```

3. Match names to IDs and subscribe:
   ```bash
   {baseDir}/scripts/kb.sh post /plans '{"participant_id": 2, "guide_id": 3}'
   ```

4. If already subscribed, the API returns 409. Tell the user: "{participant} is already subscribed to {guide}."

5. Confirm: "Subscribed **{participant}** to **{guide}**! New activities will appear starting tomorrow."

### Unsubscribe from a Guide

When the user says "unsubscribe from the math guide" or "remove the literacy guide":

1. Fetch current plans to find the plan ID:
   ```bash
   {baseDir}/scripts/kb.sh get /plans
   ```

2. Match by guide title and/or participant name.

3. Confirm with the user: "Unsubscribe **{participant}** from **{guide}**? This will remove all activities from this guide."

4. Delete the plan:
   ```bash
   {baseDir}/scripts/kb.sh delete /plans/{id}
   ```

5. Confirm: "Unsubscribed **{participant}** from **{guide}**."

### Parenting Chat

When the user asks a parenting question like "how should I do serve-and-return?" or "what activities are good for teething?":

1. Send the message:
   ```bash
   {baseDir}/scripts/kb.sh post /chat '{"message": "How should I do serve-and-return with a 14-month-old?"}'
   ```

2. Display the assistant's response. The response is grounded in the family's active guides and child profiles.

3. For conversation history:
   ```bash
   {baseDir}/scripts/kb.sh get "/chat?limit=10"
   ```

**Important:** If the API returns a `NO_API_KEY` error, tell the user: "Your household needs a Claude API key configured in Kinderbud settings to use the chat feature."

### View History

When the user asks "what did we do this week?" or "show me yesterday's completions":

1. Fetch history:
   ```bash
   {baseDir}/scripts/kb.sh get "/history?days=7"
   ```
   Optional filters: `&participant_id=2`, `&action_type=completed`

2. Format grouped by date, showing:
   - Date header
   - Each action: todo title, action type, who did it, any notes

### View Stats

When the user asks "how are we doing?" or "what's our streak?":

1. Fetch stats:
   ```bash
   {baseDir}/scripts/kb.sh get /stats
   ```

2. Format:
   - Current streak (days in a row with at least one completion)
   - This week: X completed out of Y
   - Per-participant: 7-day and 30-day completion counts

## Error Handling

Handle these error scenarios gracefully:

| Error | User-facing message |
|-------|-------------------|
| 401 Unauthorized | "Your Kinderbud token is invalid or has been revoked. Generate a new one at https://api.kinderbud.org/settings." |
| 404 Not Found | "That item wasn't found. It may have been removed or doesn't belong to your household." |
| 400 Validation Error | Display the `error` message from the response (it's user-friendly). |
| 429 Rate Limited | "You've made too many requests. Please wait a moment and try again." |
| `NO_API_KEY` | "Your household needs a Claude API key configured. Add one at https://api.kinderbud.org/settings." |
| Connection failure | "Couldn't connect to Kinderbud. Check your internet connection and try again." |
| Script missing | If kb.sh isn't found, tell the user the skill may not be installed correctly. |

## Tips

- When listing activities, show the most important info first: title, then a one-line description. Don't overwhelm with details.
- Use the `daily_note` from `/today` as conversation context — it explains why certain activities were chosen today.
- For milestones, be encouraging: "Keep watching for **{title}** — it typically happens around {age}."
- When the user completes multiple items at once ("we did tummy time and reading"), batch them — complete each one and confirm all at the end.
- If the user's question is about parenting rather than their todo list, route it through the chat endpoint instead of trying to answer from the skill's own knowledge.
