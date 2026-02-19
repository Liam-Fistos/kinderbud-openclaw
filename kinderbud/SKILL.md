---
name: kinderbud
description: Manage Kinderbud parenting activities and child development tracking. Use when the user asks about daily activities, today's schedule, completing or snoozing todos, child development guides, parenting activity tips, developmental milestones, or weekly progress for their children. Handles morning briefs, todo management, guide subscriptions, and parenting guidance chat.
user-invocable: true
metadata: {"openclaw":{"emoji":"seedling","primaryEnv":"KINDERBUD_API_KEY","requires":{"env":["KINDERBUD_API_KEY"],"anyBins":["curl"]},"os":["darwin","linux","win32"]}}
---

<!-- Skill implementation will be added in Phase 2 (see GitHub issues) -->
# Kinderbud

You help manage a Kinderbud household — a parenting app that converts developmental curricula into daily actionable activities that adapt as children grow.

## Setup

- API key is provided via `KINDERBUD_API_KEY` environment variable
- API base URL is in `KINDERBUD_API_URL` (default: `https://api.kinderbud.org`)
- Helper script: `{baseDir}/scripts/kb.sh`
- For full API details, read `{baseDir}/references/api_endpoints.md`
- For the data model, read `{baseDir}/references/data_model.md`
