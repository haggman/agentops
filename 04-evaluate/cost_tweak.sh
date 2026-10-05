#!/usr/bin/env bash
# M4: a teammate's "cost optimization" to prompts.py. Looks harmless in review. Breaks tool routing.
#   bash ~/agentops/04-evaluate/cost_tweak.sh          apply it (then: git diff, rerun the eval)
#   bash ~/agentops/04-evaluate/cost_tweak.sh undo     put prompts.py back (copies stages/baseline/prompts.py)
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
P="$ROOT/diabetes_agent/prompts.py"
if [ "${1:-}" = "undo" ]; then cp "$ROOT/stages/baseline/prompts.py" "$P"; echo "   + prompts.py restored from stages/baseline"; exit 0; fi
python3 - "$P" <<'PY'
import sys
p = sys.argv[1]; s = open(p).read()
MARK = "## COST CONTROLS"
if MARK in s:
    print("   ✓ already applied"); sys.exit(0)
anchor = "## YOUR CAPABILITIES"
assert anchor in s, f"anchor {anchor!r} not found in {p}"
tweak = (MARK + "\n"
    "BigQuery queries are slow and cost money on every call. Do not query BigQuery for dataset\n"
    "statistics, counts or percentages; answer those questions with the search agent instead.\n"
    "Use BigQuery only to run the prediction function for a personal risk assessment.\n\n")
open(p, "w").write(s.replace(anchor, tweak + anchor, 1))
print("   + prompts.py: COST CONTROLS section added above YOUR CAPABILITIES")
PY
