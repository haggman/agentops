#!/usr/bin/env bash
# Ask the DEPLOYED agent a question (Agent Runtime REST API, streamQuery). New session every time.
#   bash ~/agentops/scripts/ask.sh "What percentage of people in your study dataset had diabetes?"
#   bash ~/agentops/scripts/ask.sh --tools "..."     also print each tool call and what came back
set -euo pipefail
# shellcheck disable=SC1091
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"
SHOW_TOOLS=0; [ "${1:-}" = "--tools" ] && { SHOW_TOOLS=1; shift; }
Q="${1:?usage: ask.sh [--tools] \"question\"}"
NAME="$(find_agent)"
[ -n "$NAME" ] || die "No deployed agent called \"$AGENT_DISPLAY_NAME\" in ${AGENT_REGION}. Run: bash ~/agentops/scripts/deploy.sh"

echo "→ ${NAME##*/} (${AGENT_REGION})"
BODY="$(python3 -c 'import json,sys; print(json.dumps({"class_method":"async_stream_query","input":{"user_id":"patrick","message":sys.argv[1]}}))' "$Q")"
curl -sN -X POST -H "Authorization: Bearer $(token)" -H "Content-Type: application/json" \
     "https://${AGENT_REGION}-aiplatform.googleapis.com/v1/${NAME}:streamQuery?alt=sse" -d "$BODY" \
| SHOW_TOOLS=$SHOW_TOOLS python3 -c '
import json, os, sys
show = os.environ["SHOW_TOOLS"] == "1"
text, raw = [], []
for line in sys.stdin:
    line = line.strip()
    if line.startswith("data:"):
        line = line[5:].strip()
    if not line:
        continue
    try:
        ev = json.loads(line)
    except ValueError:
        raw.append(line); continue
    if "error" in ev and "content" not in ev:
        print("✗ API error:", json.dumps(ev["error"])[:600]); continue
    for p in (ev.get("content") or {}).get("parts", []):
        if "function_call" in p and show:
            fc = p["function_call"]
            name, args = fc.get("name"), json.dumps(fc.get("args", {}))[:300]
            print(f"  ⚙ {name}({args})")
        elif "function_response" in p and show:
            fr = p["function_response"]
            name, resp = fr.get("name"), json.dumps(fr.get("response", {}))[:300]
            print(f"  ↩ {name}: {resp}")
        elif p.get("text") and not p.get("thought"):
            text.append(p["text"])
print()
print("".join(text).strip() or "(no text in the reply)")
if raw and not text:
    print("\n(raw response)\n" + "\n".join(raw)[:1500])
'
