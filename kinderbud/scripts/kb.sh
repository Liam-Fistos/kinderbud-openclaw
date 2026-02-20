#!/usr/bin/env bash
# kb.sh — Kinderbud API helper for OpenClaw skills
# Usage: kb.sh get /path
#        kb.sh post /path '{"json":"body"}'
#        kb.sh put /path '{"json":"body"}'
#        kb.sh delete /path

set -euo pipefail

if [ -z "${KINDERBUD_API_KEY:-}" ]; then
    echo "Error: KINDERBUD_API_KEY is not set." >&2
    echo "" >&2
    echo "To configure:" >&2
    echo "  1. Log in at https://api.kinderbud.org" >&2
    echo "  2. Go to Settings > API Tokens" >&2
    echo "  3. Generate a token and add it to your OpenClaw config" >&2
    exit 1
fi

BASE_URL="${KINDERBUD_API_URL:-https://api.kinderbud.org}"
METHOD="${1:?Usage: kb.sh <get|post|put|delete> <path> [body]}"
PATH_ARG="${2:?Usage: kb.sh <get|post|put|delete> <path> [body]}"
BODY="${3:-}"

URL="${BASE_URL}/api/v1${PATH_ARG}"

CURL_ARGS=(
    -s -S
    --fail-with-body
    -H "Authorization: Bearer ${KINDERBUD_API_KEY}"
    -H "Content-Type: application/json"
    -X "$(echo "$METHOD" | tr '[:lower:]' '[:upper:]')"
)

if [ -n "$BODY" ]; then
    CURL_ARGS+=(-d "$BODY")
fi

CURL_ERR=$(mktemp)
trap "rm -f '$CURL_ERR'" EXIT

HTTP_RESPONSE=$(curl "${CURL_ARGS[@]}" "$URL" 2>"$CURL_ERR") || {
    if grep -qi "Could not resolve\|Connection refused\|Connection timed out\|Failed to connect" "$CURL_ERR" 2>/dev/null; then
        echo "Connection failed" >&2
        exit 1
    fi
    if [ -n "$HTTP_RESPONSE" ]; then
        echo "$HTTP_RESPONSE" | jq -r '.error // "Request failed"' 2>/dev/null || echo "$HTTP_RESPONSE" >&2
    else
        echo "Request failed" >&2
    fi
    exit 1
}

echo "$HTTP_RESPONSE"
