"""
M4: turn a recorded evalset into a regression test (slide 32, step 3: "Edit and refine").

adk web's "Add current session" records EVERYTHING the agent did as the expected path:
a get_table_info before the SQL, a second search for lifestyle tips, the exact SQL text.
Re-run the same question and the agent takes a slightly different route, so a strict
trajectory check fails even when the agent did the right thing.

This keeps only the decision we actually care about in each turn: which tool the agent
reached for FIRST to answer it (BigQuery's execute_sql or the search_agent). Everything
else in the case (the question, the recorded answer) is left as it was. A backup of the
original is written next to it.

    cd ~/agentops && python 04-evaluate/curate_evalset.py diabetes_agent/agentops_live.evalset.json
"""

import json
import shutil
import sys
from pathlib import Path

KEY_TOOLS = ("execute_sql", "search_agent")


def calls_in(intermediate):
    """Function calls, in order, from either evalset shape adk writes."""
    if not intermediate:
        return []
    if "tool_uses" in intermediate:                       # IntermediateData
        return [c.get("name") for c in intermediate.get("tool_uses") or []]
    names = []                                            # InvocationEvents (what adk web records)
    for ev in intermediate.get("invocation_events") or []:
        for part in ((ev.get("content") or {}).get("parts") or []):
            fc = part.get("function_call")
            if fc:
                names.append(fc.get("name"))
    return names


def main(path_str):
    path = Path(path_str)
    data = json.loads(path.read_text())
    backup = path.with_name(path.name.replace(".evalset.json", ".recorded.json"))
    if not backup.exists():
        shutil.copy(path, backup)

    for case in data.get("eval_cases", []):
        for inv in case.get("conversation") or []:
            recorded = calls_in(inv.get("intermediate_data"))
            first = next((n for n in recorded if n in KEY_TOOLS), None)
            question = "".join(p.get("text", "") for p in inv["user_content"].get("parts", []))[:60]
            inv["intermediate_data"] = {"tool_uses": [{"name": first, "args": {}}] if first else []}
            shown = " → ".join(recorded) or "(no tools)"
            print(f"  {case['eval_id'][:18]:18}  {question:60}")
            print(f"      recorded: {shown}")
            print(f"      expected: {first or '(no tool: answered directly)'}")

    path.write_text(json.dumps(data, indent=2))
    print(f"\n+ {path.name} now expects one key tool per turn (original kept as {backup.name})")


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit("usage: python 04-evaluate/curate_evalset.py diabetes_agent/<name>.evalset.json")
    main(sys.argv[1])
