#!/usr/bin/env bash
# Deploy (or update) the diabetes agent on Agent Runtime, with OpenTelemetry to Cloud Trace + Cloud Logging.
#   bash ~/agentops/scripts/deploy.sh
# Takes 5-10 minutes. Creates the agent the first time; after that it UPDATES the same instance in place,
# so the agent's resource id (and its trace history) stays the same all day.
#
# What it deliberately does NOT do: give the agent's identity any BigQuery access. That is the M3 demo.
set -euo pipefail
# shellcheck disable=SC1091
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"
cd "$DEMO_ROOT"
command -v adk >/dev/null || die "adk not found. Run: bash ~/agentops/setup.sh"
[ "$AGENT_REGION" != "global" ] || die "AGENT_REGION can't be 'global': that's the MODEL location. Use a region, e.g. us-central1."

# What travels with the agent: the code folder, its requirements.txt, and its .env (as environment variables).
cp requirements.txt diabetes_agent/requirements.txt
EXISTING="$(find_agent)"

ARGS=(--project="$PROJECT_ID" --region="$AGENT_REGION"
      --display_name="$AGENT_DISPLAY_NAME"
      --description="Educational diabetes risk agent (BigQuery ML + ADK). AgentOps course demo."
      --otel_to_cloud)
if [ -n "$EXISTING" ]; then
  echo "== Updating ${EXISTING##*/} in place (${AGENT_REGION})"
  ARGS+=(--agent_engine_id="${EXISTING##*/}")
else
  echo "== Creating a new Agent Runtime instance in ${AGENT_REGION}"
fi
echo "   model calls: ${GEMINI_LOCATION} · agent hosted: ${AGENT_REGION} · telemetry: --otel_to_cloud"
echo "   expect: 'Ignoring GOOGLE_CLOUD_LOCATION in .env as --region was explicitly passed' (correct)"
echo

adk deploy agent_engine "${ARGS[@]}" diabetes_agent

NAME="$(find_agent)"
echo
if [ -n "$NAME" ]; then
  echo "✓ Deployed: ${NAME}"
  echo "  Ask it:  bash ~/agentops/scripts/ask.sh \"What percentage of people in your study dataset had diabetes?\""
else
  echo "! Deploy finished but no instance named \"$AGENT_DISPLAY_NAME\" was found in ${AGENT_REGION}."
fi
