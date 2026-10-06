#!/usr/bin/env bash
# AgentOps demo: EVERYTHING that isn't a lesson, in one command (Cloud Shell, in the class project):
#   bash ~/agentops/setup.sh
# Safe to run any number of times (tonight, again in the morning, after a Cloud Shell reset): each step checks
# first and only creates what's missing. Lines start with ✓ (already there) or + (created now).
# Does NOT deploy the agent (that's the M2 demo; catch_up.sh 3 does it if you skipped M2).
set -euo pipefail
PACK="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
trap 'echo; echo "setup.sh stopped (line $LINENO). Fix what the message above says and run it again: finished steps are skipped."' ERR
[ -n "$(gcloud config get-value project 2>/dev/null)" ] || { echo "No project set. Run: gcloud config set project <class-project-id>"; exit 1; }

echo "== 1/5 APIs"
APIS=(aiplatform.googleapis.com bigquery.googleapis.com cloudresourcemanager.googleapis.com iam.googleapis.com
      telemetry.googleapis.com cloudtrace.googleapis.com logging.googleapis.com monitoring.googleapis.com
      modelarmor.googleapis.com)
ENABLED="$(gcloud services list --enabled --format='value(config.name)' 2>/dev/null || true)"
MISSING=(); for a in "${APIS[@]}"; do grep -qx "$a" <<<"$ENABLED" || MISSING+=("$a"); done
if [ ${#MISSING[@]} -eq 0 ]; then echo "   ✓ all ${#APIS[@]} APIs enabled"
else gcloud services enable "${MISSING[@]}" && echo "   + enabled: ${MISSING[*]}"; fi

echo "== 2/5 Python environment (.venv, ADK 2.x)"
if [ -x "$PACK/.venv/bin/adk" ] && "$PACK/.venv/bin/python" -c 'import google.adk, google.cloud.modelarmor_v1, pandas, rouge_score, tabulate' 2>/dev/null; then
  echo "   ✓ .venv with $("$PACK/.venv/bin/adk" --version 2>/dev/null)"
else
  echo "   … creating .venv and installing requirements (2-3 minutes)"
  [ -d "$PACK/.venv" ] || python3 -m venv "$PACK/.venv"
  "$PACK/.venv/bin/pip" install --quiet --upgrade pip wheel
  "$PACK/.venv/bin/pip" install --quiet -r "$PACK/requirements.txt"
  echo "   + .venv with $("$PACK/.venv/bin/adk" --version)"
fi

# From here on, scripts run inside the venv with the demo's settings (and diabetes_agent/.env is written).
# shellcheck disable=SC1091
source "$PACK/scripts/lib.sh"
ok "diabetes_agent/.env for ${PROJECT_ID} (model ${AGENT_MODEL} @ ${GEMINI_LOCATION}, agent region ${AGENT_REGION})"

echo "== 3/5 BigQuery: data, model, prediction function"
bash "$PACK/scripts/bq_setup.sh"

echo "== 4/5 Model Armor template for M5 (${MA_TEMPLATE_ID} in ${MA_LOCATION})"
bash "$PACK/05-secure/model_armor_template.sh" ensure || echo "   ! Model Armor template not created (see the error above). Everything except the M5 guardrail still works."

echo "== 5/5 Where things stand"
NAME="$(find_agent)"
if [ -n "$NAME" ]; then ok "deployed agent: ${NAME##*/} in ${AGENT_REGION}"
else echo "   (no deployed agent yet: M2 deploys it live, or run: bash ~/agentops/catch_up.sh 3)"; fi
bash "$PACK/scripts/bq_access.sh" show

echo
echo "Setup complete. Before each module:  bash ~/agentops/catch_up.sh <module you are about to teach, 1-6>"
echo "Every new Cloud Shell tab:            source ~/agentops/activate.sh"
