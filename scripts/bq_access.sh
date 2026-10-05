#!/usr/bin/env bash
# Who can the deployed agent read BigQuery as?
#   bash ~/agentops/scripts/bq_access.sh show     the agent's BigQuery roles right now
#   bash ~/agentops/scripts/bq_access.sh grant    jobUser + dataViewer: run SELECTs, read tables (the M3 fix)
#   bash ~/agentops/scripts/bq_access.sh revoke   back to no BigQuery access (the M3 start state)
# A deployed agent runs as the Reasoning Engine service agent, service-<number>@gcp-sa-aiplatform-re,
# not as you. It starts with no BigQuery access. IAM changes take 1-2 minutes to reach the agent.
set -euo pipefail
# shellcheck disable=SC1091
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"
ROLES=(roles/bigquery.jobUser roles/bigquery.dataViewer)

show() {
  local have
  have="$(gcloud projects get-iam-policy "$PROJECT_ID" --flatten='bindings[].members' \
          --filter="bindings.members:serviceAccount:${AGENT_SA} AND bindings.role~bigquery" \
          --format='value(bindings.role)' 2>/dev/null || true)"
  echo "   agent identity: ${AGENT_SA}"
  if [ -n "$have" ]; then echo "$have" | sed 's/^/   ✓ /'; else echo "   (no BigQuery roles)"; fi
}

case "${1:-show}" in
  show) show ;;
  grant)
    gcloud beta services identity create --service=aiplatform.googleapis.com --project="$PROJECT_ID" >/dev/null 2>&1 || true
    for r in "${ROLES[@]}"; do
      gcloud projects add-iam-policy-binding "$PROJECT_ID" --member="serviceAccount:${AGENT_SA}" \
        --role="$r" --condition=None >/dev/null && made "$r"
    done
    echo "   Give it 60-90 seconds before asking the agent again." ;;
  revoke)
    for r in "${ROLES[@]}"; do
      if gcloud projects remove-iam-policy-binding "$PROJECT_ID" --member="serviceAccount:${AGENT_SA}" \
           --role="$r" --condition=None >/dev/null 2>&1; then made "removed $r"; else ok "$r was not granted"; fi
    done ;;
  *) die "usage: bq_access.sh show|grant|revoke" ;;
esac
