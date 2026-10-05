"""
M6: what does one conversation turn cost, and what would a cheaper model save?

Runs the three questions from the M4 evalset against the agent once per model, counts every
model call (the root agent AND the search sub-agent) with an ADK plugin, and prices the tokens.

    cd ~/agentops && python 06-finops/cost_per_turn.py
    python 06-finops/cost_per_turn.py --models gemini-flash-latest gemini-flash-lite-latest
    python 06-finops/cost_per_turn.py --evalset diabetes_agent/my_live_evalset.evalset.json

Prices come from 06-finops/prices.json (USD per 1M tokens). Check them against the pricing page
before class; the "-latest" aliases move when Google ships a new model.
Thinking tokens are billed as output. Cached input tokens are billed at the cached rate.
"""

import argparse
import asyncio
import json
import os
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from dotenv import load_dotenv  # noqa: E402

load_dotenv(ROOT / "diabetes_agent" / ".env", override=False)

from google.adk.plugins.base_plugin import BasePlugin  # noqa: E402
from google.adk.runners import InMemoryRunner  # noqa: E402
from google.genai import types  # noqa: E402


class TokenMeter(BasePlugin):
    """Plugins see every model call in the run, including the sub-agent behind AgentTool."""

    def __init__(self):
        super().__init__(name="token_meter")
        self.calls = []

    async def after_model_callback(self, *, callback_context, llm_response):
        um = llm_response.usage_metadata
        if um:
            self.calls.append({
                "agent": callback_context.agent_name,
                "model_version": getattr(llm_response, "model_version", None),
                "input": um.prompt_token_count or 0,
                "cached": um.cached_content_token_count or 0,
                "output": (um.candidates_token_count or 0) + (um.thoughts_token_count or 0),
            })
        return None


def questions_from(evalset_path: Path):
    data = json.loads(evalset_path.read_text())
    out = []
    for case in data["eval_cases"]:
        first = case["conversation"][0]["user_content"]["parts"][0]["text"]
        out.append((case["eval_id"], first))
    return out


def price(call, p):
    fresh = call["input"] - call["cached"]
    cached_rate = p.get("cached_input", p["input"] * 0.1)
    return (fresh * p["input"] + call["cached"] * cached_rate + call["output"] * p["output"]) / 1_000_000


async def run_model(model, questions, prices):
    from diabetes_agent import agent as A  # imported late so .env is loaded first

    A.root_agent.model = model
    A.search_agent.model = model
    rows = []
    for eval_id, q in questions:
        meter = TokenMeter()
        runner = InMemoryRunner(agent=A.root_agent, app_name="diabetes_agent", plugins=[meter])
        session = await runner.session_service.create_session(app_name="diabetes_agent", user_id="patrick")
        t0 = time.time()
        async for _ in runner.run_async(user_id="patrick", session_id=session.id,
                                        new_message=types.Content(role="user", parts=[types.Part(text=q)])):
            pass
        secs = time.time() - t0
        p = prices.get(model)
        rows.append({
            "eval_id": eval_id, "seconds": secs,
            "calls": len(meter.calls),
            "sub_calls": sum(1 for c in meter.calls if c["agent"] != A.root_agent.name),
            "input": sum(c["input"] for c in meter.calls),
            "output": sum(c["output"] for c in meter.calls),
            "usd": sum(price(c, p) for c in meter.calls) if p else None,
            "versions": sorted({c["model_version"] for c in meter.calls if c["model_version"]}),
        })
    return rows


def show(model, rows, prices):
    versions = sorted({v for r in rows for v in r["versions"]})
    print(f"\n{model}" + (f"   (served as: {', '.join(versions)})" if versions else ""))
    print(f"  {'question':22} {'model calls':>11} {'input tok':>10} {'output tok':>11} {'secs':>6} {'$ / turn':>10}")
    for r in rows:
        usd = f"${r['usd']:.5f}" if r["usd"] is not None else "no price"
        calls = f"{r['calls']} ({r['sub_calls']} sub)"
        print(f"  {r['eval_id']:22} {calls:>11} {r['input']:>10,} {r['output']:>11,} {r['seconds']:>6.1f} {usd:>10}")
    if all(r["usd"] is not None for r in rows):
        avg = sum(r["usd"] for r in rows) / len(rows)
        print(f"  {'average turn':22} {'':>11} {'':>10} {'':>11} {'':>6} ${avg:.5f}")
        print(f"  → 100,000 turns a month ≈ ${avg * 100_000:,.0f}   (model tokens only: no search grounding, BigQuery or runtime)")
        return avg
    return None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--models", nargs="+", default=["gemini-flash-latest", "gemini-flash-lite-latest"])
    ap.add_argument("--evalset", default=str(ROOT / "04-evaluate" / "agentops_baseline.evalset.json"))
    args = ap.parse_args()

    prices_file = json.loads((ROOT / "06-finops" / "prices.json").read_text())
    prices = prices_file["models"]
    questions = questions_from(Path(args.evalset))
    print(f"{len(questions)} questions from {Path(args.evalset).name} · prices as of {prices_file['as_of']} (06-finops/prices.json)")

    avgs = {}
    for m in args.models:
        rows = asyncio.run(run_model(m, questions, prices))
        avgs[m] = show(m, rows, prices)

    known = {m: a for m, a in avgs.items() if a}
    if len(known) >= 2:
        base, *others = list(known)
        for o in others:
            print(f"\n{o} costs {known[o] / known[base]:.0%} of {base} per turn. "
                  f"Before switching: does it still pass the M4 eval?")


if __name__ == "__main__":
    main()
