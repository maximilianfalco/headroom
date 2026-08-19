#!/bin/bash
# Fetches Claude Code plan usage and writes a normalized snapshot for the widget to read.
set -uo pipefail

OUT_DIR="$HOME/Library/Application Support/Headroom"
OUT_FILE="$OUT_DIR/usage.json"
mkdir -p "$OUT_DIR"

write_out() {
  # Atomic write so a reader never sees a half-written file.
  local tmp
  tmp=$(mktemp "$OUT_DIR/.usage.XXXXXX")
  cat > "$tmp"
  mv -f "$tmp" "$OUT_FILE"
}

fail() {
  printf '{"ok":false,"error":%s,"fetched_at":"%s"}\n' \
    "$(printf '%s' "$1" | python3 -c 'import sys,json; print(json.dumps(sys.stdin.read()))')" \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" | write_out
  exit 1
}

CREDS=$(security find-generic-password -s "Claude Code-credentials" -w 2>/dev/null) \
  || fail "keychain read failed"

TOKEN=$(printf '%s' "$CREDS" | python3 -c \
  'import sys,json; print(json.load(sys.stdin)["claudeAiOauth"]["accessToken"])' 2>/dev/null) \
  || fail "could not parse access token"

RESP=$(curl -sS --max-time 20 -w '\n%{http_code}' https://api.anthropic.com/api/oauth/usage \
  -H "Authorization: Bearer $TOKEN" \
  -H "anthropic-beta: oauth-2025-04-20" 2>&1) || fail "network error: $RESP"

CODE=$(printf '%s' "$RESP" | tail -n1)
BODY=$(printf '%s' "$RESP" | sed '$d')

[ "$CODE" = "401" ] && fail "token expired, open Claude Code to refresh"
[ "$CODE" = "200" ] || fail "http $CODE"

printf '%s' "$BODY" | python3 -c '
import sys, json, datetime

raw = json.load(sys.stdin)
now = datetime.datetime.now(datetime.timezone.utc)

def bucket(key, label):
    b = raw.get(key)
    if not isinstance(b, dict) or b.get("utilization") is None:
        return None
    return {"key": key, "label": label, "percent": round(b["utilization"]), "resets_at": b.get("resets_at")}

buckets = [b for b in (bucket("five_hour", "Session"), bucket("seven_day", "Weekly")) if b]

# Per-model caps only show up in limits[], not as top-level buckets.
for lim in raw.get("limits") or []:
    scope = (lim.get("scope") or {}).get("model") or {}
    name = scope.get("display_name")
    if lim.get("kind") == "weekly_scoped" and name:
        buckets.append({"key": "weekly_" + name.lower(), "label": name + " weekly",
                        "percent": lim.get("percent"), "resets_at": lim.get("resets_at")})

for b in buckets:
    b["severity"] = "critical" if b["percent"] >= 95 else "warning" if b["percent"] >= 80 else "normal"
    try:
        r = datetime.datetime.fromisoformat(b["resets_at"])
        mins = max(0, int((r - now).total_seconds() // 60))
        b["resets_in"] = f"{mins // 1440}d {(mins % 1440) // 60}h" if mins >= 1440 else \
                         f"{mins // 60}h {mins % 60}m" if mins >= 60 else f"{mins}m"
    except (TypeError, ValueError):
        b["resets_in"] = None

extra = raw.get("extra_usage") or {}
print(json.dumps({
    "ok": True,
    "fetched_at": now.strftime("%Y-%m-%dT%H:%M:%SZ"),
    "buckets": buckets,
    "worst": max((b["percent"] for b in buckets), default=0),
    "extra_usage_enabled": bool(extra.get("is_enabled")),
    "raw": raw,
}, indent=2))
' | write_out || fail "could not parse usage response"
