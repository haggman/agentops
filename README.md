# AgentOps demos: the Diabetes Risk Agent

One small ADK agent, taken from "works on my laptop" to deployed, traced, debugged, evaluated, guarded and priced across the six modules of Google Cloud's **Agent Operations on Google Cloud** course. Every demo is scripted, and one command puts the project in the start state for any module.

*The agent is an educational diabetes assistant built on a public 100,000-row diabetes prediction dataset and a BigQuery ML model. It is not a clinical tool. This is not an official Google product, and the course slide decks are not included; slide numbers in the docs refer to the M1–M6 decks, but every demo stands on its own.*

---

## Quick start (Cloud Shell)

You need a Google Cloud project where you are **Owner** (a Qwiklabs class project works). Cloud Shell starts in your home folder, so the clone lands in `~/agentops`, which is where every script and doc expects it:

```bash
cd ~ && git clone https://github.com/haggman/agentops.git
bash ~/agentops/setup.sh                 # everything that isn't a lesson; safe to rerun
bash ~/agentops/catch_up.sh 3            # optional tonight: deploy once so the day never waits on it
```

Then open [docs/TELEPROMPTER.md](docs/TELEPROMPTER.md) and start at block 1, or jump to any module:

```bash
bash ~/agentops/catch_up.sh 4            # the start of Module 4
```

Two Cloud Shell tabs:

| Tab | Runs |
|---|---|
| TAB 1 | `source ~/agentops/activate.sh && cd ~/agentops && adk web --reload_agents --allow_origins "*"` (open the 127.0.0.1:8000 link) |
| TAB 2 | `source ~/agentops/activate.sh`, then every other command |

---

## What's in the repo

```
agentops/                              ~/agentops in Cloud Shell
├── README.md                          you are here
├── setup.sh                           APIs, .venv (ADK 2.x), BigQuery data/model/function, Model Armor template. Idempotent
├── catch_up.sh                        start state for module 1-6 (or "done")
├── activate.sh                        settings; writes diabetes_agent/.env; activates .venv
├── requirements.txt                   the agent's dependencies (deploy.sh copies it into the agent folder)
├── diabetes_agent/                    THE AGENT: agent.py, prompts.py, guardrails.py (M5, off until wired in)
├── stages/                            known-good agent.py / prompts.py: baseline/ and guarded/
├── scripts/
│   ├── bq_setup.sh                    dataset, 100k-row table, logistic-regression model, predict_diabetes()
│   ├── deploy.sh                      adk deploy agent_engine --otel_to_cloud (creates, then updates in place)
│   ├── ask.sh                         ask the DEPLOYED agent (REST streamQuery); --tools shows tool calls
│   ├── bq_access.sh                   show | grant | revoke the deployed agent's BigQuery roles
│   └── lib.sh                         shared helpers
├── 04-evaluate/                       test_config.json, cost_tweak.sh (the "harmless" prompt edit), fallback evalset
├── 05-secure/                         model_armor_template.sh, floor_setting.sh (optional inline mode)
├── 06-finops/                         cost_per_turn.py, prices.json
├── docs/                              GENERATED: TELEPROMPTER (Word + Markdown), PLANNING GUIDE (Word)
└── src/                               content.js (the single source for the docs) + renderers + build.sh
```

---

## The story

The agent has a Gemini root agent, a Google Search sub-agent for medical facts, read-only BigQuery access to a 100,000-patient study dataset, and a BigQuery ML model behind a table function for personal risk assessments. Three questions exercise three tool paths, which is what makes the traces, evals and costs worth looking at.

Two threads run through the day:

- **The missing permission.** `deploy.sh` grants the deployed agent's identity nothing. In M3 the agent answers medical questions but apologises for every data question; the trace shows a BigQuery 403 as `service-…@gcp-sa-aiplatform-re`. One grant fixes it, and M5 turns it into the least-privilege discussion.
- **The cost tweak.** In M4 a teammate adds a "cost controls" paragraph to the prompt that sends statistics questions to search instead of BigQuery. It reads fine in review; the trajectory eval catches it. In M6 it is the example of an Optimize step that skipped Validate.

## The demos

| # | Module · slide | Demo | Min |
|---|---|---|---|
| 1 | M1 · 19–20 | Meet the agent: three questions, three tool paths in adk web | 8 |
| 2 | M2 · 9–12 | Ship it to Agent Runtime with `--otel_to_cloud` (and leave it cooking) | 10 |
| 3 | M3 · 9, 12 | Support ticket: find the 403 in the trace, grant two roles, confirm | 12 |
| 4 | M4 · 31–32 | Turn three chats into an evalset in the Eval tab | 7 |
| 5 | M4 · 35–38 | Run it from the CLI; catch the cost tweak | 8 |
| 6 | M5 · 25–27 | Model Armor in front of the model (ADK callback, DIY mode) | 9 |
| 7 | M5 · 31, 37–38 | What the agent can't do: write mode + IAM | 4 |
| 8 | M6 · 4, 9, 16 | Cost per turn per model; is flash-lite good enough? (eval) | 10 |

About 68 minutes of demos in total.

## Test data

- `demo_diabetes.diabetes_raw`: 100,000 rows. 8,500 have diabetes (8.5%).
- Hero profile: male, 55, former smoker, BMI 28.5, HbA1c 6.8, glucose 145, hypertension, no heart disease → High Risk.
- Prompts that Model Armor should stop: a jailbreak asking for an insulin dose, and an assessment that includes an SSN (123-45-6789, a well-known example number).

## Cost and cleanup

Model calls are cents for a day of demos. The deployed agent costs while it exists. When you are done:

```bash
source ~/agentops/activate.sh
NAME=$(bash -c 'source ~/agentops/scripts/lib.sh; find_agent')
curl -X DELETE -H "Authorization: Bearer $(gcloud auth print-access-token)" "https://${AGENT_REGION}-aiplatform.googleapis.com/v1/${NAME}?force=true"
bash ~/agentops/05-secure/floor_setting.sh off        # only if you turned it on
bq rm -r -f -d "${PROJECT_ID}:demo_diabetes"
```

A Qwiklabs project is deleted when its timer ends, which cleans up everything.

## Rebuilding the docs

On a machine with Node: `npm install` once, then `bash src/build.sh`. Edit `src/content.js`, never the generated documents.

## Lessons from real runs

- `adk eval` and the adk web Eval tab need `google-adk[eval]`; plain `[gcp]` stops with "Eval module is not installed". requirements.txt now asks for `[gcp,eval]`, and setup.sh reinstalls into the venv when the eval packages are missing.

- `gemini-flash-latest` returns 404 on Agent Platform's global endpoint (it's a Gemini Developer API alias). The pack pins `gemini-3.8-flash` (agent and eval judge) and `gemini-3.5-flash-lite` (M6). 3.6 and 3.7 Flash are being removed.

- Both Cloud Shell tabs need `source ~/agentops/activate.sh` first. Without it, `adk` is Cloud Shell's preinstalled ADK, which can't import the agent (no BigQuery/Model Armor packages, older ADK).

- (first delivery: October 6, 2026)
