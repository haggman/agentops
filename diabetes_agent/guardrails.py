"""
Model Armor guardrail for the diabetes agent (M5 demo, "do-it-yourself" API mode).

This ships with the pack and does nothing until agent.py wires it in:

    from .guardrails import model_armor_guard
    root_agent = Agent(..., before_model_callback=model_armor_guard)

Every time the root agent is about to call Gemini with a NEW user message, the text is
sent to Model Armor first (template = MODEL_ARMOR_TEMPLATE in diabetes_agent/.env,
created by setup.sh). If any filter matches - prompt injection / jailbreak, sensitive
data (SSNs, card numbers ...), responsible-AI filters, malicious URLs - the callback
returns its own response and the model is never called. Same callback hook the M3
deck uses for logging; here it short-circuits the run.

Failure policy: if Model Armor itself can't be reached, the guard FAILS OPEN (lets the
prompt through and logs a warning), which is what Model Armor's inline integration does
too. For a real health product you might choose to fail closed:
set MODEL_ARMOR_FAIL_OPEN=false in the environment.
"""

import json
import logging
import os
from typing import Optional

from google.adk.agents.callback_context import CallbackContext
from google.adk.models import LlmRequest, LlmResponse
from google.genai import types

log = logging.getLogger("diabetes_agent.guardrails")

_client = None

# Field on a FilterResult -> the name we show the user and log
_FILTERS = {
    "pi_and_jailbreak_filter_result": "prompt injection / jailbreak",
    "sdp_filter_result": "sensitive data",
    "rai_filter_result": "responsible AI",
    "malicious_uri_filter_result": "malicious URL",
    "csam_filter_filter_result": "CSAM",
}


def _get_client(location: str):
    global _client
    if _client is None:
        from google.api_core.client_options import ClientOptions
        from google.cloud import modelarmor_v1

        _client = modelarmor_v1.ModelArmorClient(
            transport="rest",
            client_options=ClientOptions(
                api_endpoint=f"modelarmor.{location}.rep.googleapis.com"
            ),
        )
    return _client


def _new_user_text(llm_request: LlmRequest) -> Optional[str]:
    """The user's message, but only on the first model call of a turn.

    Later calls in the same turn end with a function response (role "user", no text),
    so they are skipped: the user's words are checked once per turn.
    """
    if not llm_request.contents:
        return None
    last = llm_request.contents[-1]
    if last.role != "user" or not last.parts:
        return None
    text = "\n".join(p.text for p in last.parts if getattr(p, "text", None))
    return text or None


def _matched_filters(sanitization_result) -> list[str]:
    from google.cloud import modelarmor_v1

    found = []
    for key, result in sanitization_result.filter_results.items():
        for field, label in _FILTERS.items():
            inner = getattr(result, field, None)
            if inner is None:
                continue
            # sdp_filter_result wraps the real result one level down
            if field == "sdp_filter_result":
                inner = inner.inspect_result
            state = getattr(inner, "match_state", None)
            if state == modelarmor_v1.FilterMatchState.MATCH_FOUND and label not in found:
                found.append(label)
    return found


def model_armor_guard(
    callback_context: CallbackContext, llm_request: LlmRequest
) -> Optional[LlmResponse]:
    template = os.environ.get("MODEL_ARMOR_TEMPLATE", "")
    text = _new_user_text(llm_request)
    if not template or not text:
        return None

    from google.cloud import modelarmor_v1

    location = template.split("/locations/")[1].split("/")[0]
    try:
        response = _get_client(location).sanitize_user_prompt(
            request=modelarmor_v1.SanitizeUserPromptRequest(
                name=template,
                user_prompt_data=modelarmor_v1.DataItem(text=text),
            )
        )
    except Exception as exc:  # Model Armor unreachable, template missing, no permission ...
        fail_open = os.environ.get("MODEL_ARMOR_FAIL_OPEN", "true").lower() != "false"
        log.warning(json.dumps({
            "event": "model_armor_error", "agent": callback_context.agent_name,
            "error": str(exc)[:300], "action": "allowed" if fail_open else "blocked",
        }))
        if fail_open:
            return None
        return _blocked(["guardrail unavailable"])

    result = response.sanitization_result
    if result.filter_match_state != modelarmor_v1.FilterMatchState.MATCH_FOUND:
        return None

    found = _matched_filters(result) or ["policy"]
    # Structured log line: shows up in Cloud Logging when deployed (M3), never logs the prompt itself.
    log.warning(json.dumps({
        "event": "model_armor_block", "agent": callback_context.agent_name,
        "filters": found, "template": template.rsplit("/", 1)[-1],
    }))
    return _blocked(found)


def _blocked(found: list[str]) -> LlmResponse:
    return LlmResponse(
        content=types.Content(
            role="model",
            parts=[types.Part(text=(
                "I can't process that message. It was stopped before it reached the model "
                f"(Model Armor: {', '.join(found)}).\n\n"
                "If you shared personal identifiers such as a Social Security number, please "
                "leave them out: I only need age, gender, BMI, HbA1c, blood glucose, "
                "blood pressure, heart disease and smoking history."
            ))],
        )
    )
