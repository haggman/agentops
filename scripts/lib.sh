#!/usr/bin/env bash
# Shared helpers for the AgentOps demo scripts. Sourced, never run.
# shellcheck disable=SC2034

ok()   { echo "   ✓ $*"; }
made() { echo "   + $*"; }
warn() { echo "   ! $*"; }
die()  { echo "   ✗ $*" >&2; exit 1; }

# shellcheck disable=SC1091
ACTIVATE_QUIET=1 source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/activate.sh" || exit 1

PROJECT_NUMBER="${PROJECT_NUMBER:-$(gcloud projects describe "$PROJECT_ID" --format='value(projectNumber)')}"
# The identity a deployed agent runs as: the Reasoning Engine service agent. Not you.
AGENT_SA="service-${PROJECT_NUMBER}@gcp-sa-aiplatform-re.iam.gserviceaccount.com"
API="https://${AGENT_REGION}-aiplatform.googleapis.com/v1/projects/${PROJECT_ID}/locations/${AGENT_REGION}"

token() { gcloud auth print-access-token; }

# Prints the resource name of the newest Agent Runtime instance called $AGENT_DISPLAY_NAME, or nothing.
find_agent() {
  curl -sf -H "Authorization: Bearer $(token)" "${API}/reasoningEngines?pageSize=100" 2>/dev/null \
  | python3 -c '
import json, os, sys
try:
    items = json.load(sys.stdin).get("reasoningEngines", [])
except Exception:
    items = []
want = os.environ["AGENT_DISPLAY_NAME"]
hits = sorted((e for e in items if e.get("displayName") == want), key=lambda e: e.get("createTime", ""))
print(hits[-1]["name"] if hits else "")'
}

# Retry a command a few times (first calls after enabling an API are often flaky).
retry() { local n=0; until "$@"; do n=$((n+1)); [ $n -ge 4 ] && return 1; echo "   … retrying in 10s ($n/3)"; sleep 10; done; }
