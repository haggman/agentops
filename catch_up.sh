#!/usr/bin/env bash
# Put the demo in the known-good state for the START of a module, whatever happened before:
#   bash ~/agentops/catch_up.sh <module you are about to teach: 1-6, or done>
# Prior state is not preserved (agent code is overwritten from stages/). Safe to rerun.
#
#   1, 2   local agent at baseline, no evalset in the agent folder. Nothing deployed needed.
#   3      + agent DEPLOYED to Agent Runtime with --otel_to_cloud, and its BigQuery access REMOVED (the M3 mystery)
#   4      + BigQuery access granted (M3 fixed). Agent folder has no evalset: M4 builds one live.
#   5      + fallback evalset in the agent folder, prompts.py at baseline (M4's bad tweak undone), guardrail OFF
#   6      + Model Armor guardrail wired into agent.py
#   done   same as 6
# Deploying (3+) takes 5-10 minutes the first time; after that an existing deployment is reused.
set -euo pipefail
PACK="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
M="${1:?usage: bash ~/agentops/catch_up.sh <module you are about to teach: 1-6, or done>}"
[ "$M" = "done" ] && M=6
case "$M" in 1|2|3|4|5|6) ;; *) echo "Module must be 1-6 (or done)"; exit 1;; esac
trap 'echo; echo "catch_up.sh stopped (line $LINENO). Fix what the message above says and rerun it."' ERR

echo "######## Catching up to the start of M${M}"
bash "$PACK/setup.sh"
# shellcheck disable=SC1091
source "$PACK/scripts/lib.sh"
AG="$PACK/diabetes_agent"

echo "== Agent code"
cp "$PACK/stages/baseline/prompts.py" "$AG/prompts.py"
if [ "$M" -ge 6 ]; then cp "$PACK/stages/guarded/agent.py" "$AG/agent.py"; made "agent.py: Model Armor guardrail ON"
else cp "$PACK/stages/baseline/agent.py" "$AG/agent.py"; made "agent.py + prompts.py at baseline (guardrail off)"; fi

echo "== Evalsets in the agent folder"
if [ "$M" -le 4 ]; then
  shopt -s nullglob; EVS=("$AG"/*.evalset.json); shopt -u nullglob
  if [ ${#EVS[@]} -gt 0 ]; then
    mkdir -p "$PACK/.old_evalsets" && mv "${EVS[@]}" "$PACK/.old_evalsets/" && made "moved ${#EVS[@]} evalset(s) to .old_evalsets/ (M4 builds one live)"
  else ok "none (M4 builds one live)"; fi
else
  cp "$PACK/04-evaluate/agentops_baseline.evalset.json" "$AG/" && made "agentops_baseline.evalset.json (fallback) in the agent folder"
fi

if [ "$M" -ge 3 ]; then
  echo "== Deployed agent"
  NAME="$(find_agent)"
  if [ -n "$NAME" ]; then ok "${NAME##*/} in ${AGENT_REGION} (reusing it; redeploy with scripts/deploy.sh)"
  else echo "   … no deployment yet: deploying now (5-10 minutes)"; bash "$PACK/scripts/deploy.sh"; fi
  echo "== Agent's BigQuery access"
  if [ "$M" -eq 3 ]; then bash "$PACK/scripts/bq_access.sh" revoke; echo "   (M3 starts broken on purpose: data questions fail on the deployed agent)"
  else bash "$PACK/scripts/bq_access.sh" grant; fi
fi

echo
echo "✓ Ready for M${M}. In any new Cloud Shell tab: source ~/agentops/activate.sh"
echo "  Local dev UI:  cd ~/agentops && adk web --reload_agents --allow_origins \"*\"   (already running? reload the browser page)"
