#!/usr/bin/env bash
# OPTIONAL M5 demo: Model Armor "inline" for the whole project, no code. A floor setting that screens every
# Gemini call made through Agent Platform in this project and blocks what matches.
#   bash ~/agentops/05-secure/floor_setting.sh on     enforce: prompt injection/jailbreak, RAI, malicious URLs, basic SDP
#   bash ~/agentops/05-secure/floor_setting.sh off    stop enforcing on Agent Platform (the default state)
#   bash ~/agentops/05-secure/floor_setting.sh show
# Allow a few minutes after "on"/"off" before testing. Works only for non-streaming model calls: in adk web,
# leave Token Streaming OFF. A blocked call comes back with promptFeedback.blockReason = MODEL_ARMOR (not an error).
set -euo pipefail
# shellcheck disable=SC1091
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts/lib.sh"
URI="projects/${PROJECT_ID}/locations/global/floorSetting"
RAI='[{"filterType":"HATE_SPEECH","confidenceLevel":"MEDIUM_AND_ABOVE"},{"filterType":"HARASSMENT","confidenceLevel":"MEDIUM_AND_ABOVE"},{"filterType":"SEXUALLY_EXPLICIT","confidenceLevel":"MEDIUM_AND_ABOVE"},{"filterType":"DANGEROUS","confidenceLevel":"MEDIUM_AND_ABOVE"}]'

on() {  # $1 = how this gcloud spells "enable" (the docs show both)
  gcloud model-armor floorsettings update --full-uri="$URI" \
    --enable-floor-setting-enforcement=TRUE \
    --add-integrated-services=VERTEX_AI \
    --vertex-ai-enforcement-type=INSPECT_AND_BLOCK \
    --enable-vertex-ai-cloud-logging \
    --pi-and-jailbreak-filter-settings-enforcement="$1" \
    --pi-and-jailbreak-filter-settings-confidence-level=medium-and-above \
    --malicious-uri-filter-settings-enforcement="$1" \
    --basic-config-filter-enforcement="$1" \
    --rai-settings-filters="$RAI" >/dev/null
}

case "${1:-show}" in
  on)
    # Agent Platform's service agent must be allowed to call Model Armor.
    gcloud projects add-iam-policy-binding "$PROJECT_ID" \
      --member="serviceAccount:service-${PROJECT_NUMBER}@gcp-sa-aiplatform.iam.gserviceaccount.com" \
      --role=roles/modelarmor.user --condition=None >/dev/null && ok "Agent Platform service agent has roles/modelarmor.user"
    { on enable 2>/dev/null || on ENABLED; } && made "floor setting: INSPECT_AND_BLOCK for Agent Platform. Wait 2-3 minutes, then test." ;;
  off)
    gcloud model-armor floorsettings update --full-uri="$URI" --remove-integrated-services=VERTEX_AI >/dev/null \
      && made "floor setting: Agent Platform no longer enforced (allow a few minutes)" ;;
  show) gcloud model-armor floorsettings describe --full-uri="$URI" ;;
  *) die "usage: floor_setting.sh on|off|show" ;;
esac
