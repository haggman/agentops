#!/usr/bin/env bash
# The Model Armor template the M5 guardrail uses (diabetes_agent/guardrails.py reads MODEL_ARMOR_TEMPLATE).
#   bash ~/agentops/05-secure/model_armor_template.sh ensure     create it if missing (setup.sh runs this)
#   bash ~/agentops/05-secure/model_armor_template.sh show       print its filters
#   bash ~/agentops/05-secure/model_armor_template.sh test "text"  screen one prompt from the command line
# Filters: prompt injection + jailbreak (medium and above), malicious URLs, basic Sensitive Data Protection
# (SSNs, card numbers, credentials ...), and the four responsible-AI filters (medium and above).
set -euo pipefail
# shellcheck disable=SC1091
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts/lib.sh"
export CLOUDSDK_API_ENDPOINT_OVERRIDES_MODELARMOR="https://modelarmor.${MA_LOCATION}.rep.googleapis.com/"
RAI='[{"filterType":"HATE_SPEECH","confidenceLevel":"MEDIUM_AND_ABOVE"},{"filterType":"HARASSMENT","confidenceLevel":"MEDIUM_AND_ABOVE"},{"filterType":"SEXUALLY_EXPLICIT","confidenceLevel":"MEDIUM_AND_ABOVE"},{"filterType":"DANGEROUS","confidenceLevel":"MEDIUM_AND_ABOVE"}]'

exists() { gcloud model-armor templates describe "$MA_TEMPLATE_ID" --location="$MA_LOCATION" --project="$PROJECT_ID" >/dev/null 2>&1; }

create() {  # $1 = how this gcloud spells "enabled" (the docs show both)
  gcloud model-armor templates create "$MA_TEMPLATE_ID" --location="$MA_LOCATION" --project="$PROJECT_ID" \
    --rai-settings-filters="$RAI" \
    --basic-config-filter-enforcement="$1" \
    --pi-and-jailbreak-filter-settings-enforcement="$1" \
    --pi-and-jailbreak-filter-settings-confidence-level=medium-and-above \
    --malicious-uri-filter-settings-enforcement="$1" \
    --template-metadata-log-sanitize-operations >/dev/null
}

case "${1:-ensure}" in
  ensure)
    if exists; then ok "template ${MA_TEMPLATE_ID}"
    elif create enabled 2>/dev/null || create ENABLED 2>/dev/null || { sleep 15; create enabled; }; then made "template ${MA_TEMPLATE_ID} (${MA_LOCATION})"
    else die "could not create the Model Armor template. Run the create by hand to see the error: bash $0 show"; fi ;;
  show) gcloud model-armor templates describe "$MA_TEMPLATE_ID" --location="$MA_LOCATION" --project="$PROJECT_ID" ;;
  test)
    gcloud model-armor templates sanitize-user-prompt "$MA_TEMPLATE_ID" --location="$MA_LOCATION" \
      --project="$PROJECT_ID" --text="${2:?usage: test \"text to screen\"}" --format=json \
    | python3 -c '
import json, sys
r = json.load(sys.stdin).get("sanitizationResult", {})
print("overall:", r.get("filterMatchState"))
for k, v in (r.get("filterResults") or {}).items():
    inner = next(iter(v.values()), {})
    if "inspectResult" in inner: inner = inner["inspectResult"]
    state = inner.get("matchState", "?")
    print(f"  {k:28} {state}")' ;;
  *) die "usage: model_armor_template.sh ensure|show|test \"text\"" ;;
esac
