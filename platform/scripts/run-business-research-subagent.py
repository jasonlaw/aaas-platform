#!/usr/bin/env python3
# Run the business intelligence sub-agent during tenant onboarding.
#
# Called by onboard-tenant.md step 1.15 via the research-tenant-business skill.
# Reads a JSON context block from stdin, calls the Anthropic API, and writes
# the sub-agent's structured JSON response to --output-file.
#
# Exits 0 on success. Exits non-zero on any failure — the caller (admin agent)
# is responsible for falling back to cold generation when this script fails.
# Never raises unhandled exceptions: all errors are printed to stderr and
# result in a clean non-zero exit so the SOP fallback path can proceed.
#
# Usage:
#   python3 run-business-research-subagent.py \
#     --tenant-id    "my-tenant" \
#     --output-file  "/tmp/aaas-research-my-tenant.json" \
#     < context.json
#
# Environment:
#   ANTHROPIC_API_KEY   Required. The Anthropic API key used to call the model.
#                       On the AaaS platform this is set in the host environment
#                       (not inside a tenant container).
#   SUBAGENT_MODEL      Optional. Defaults to claude-sonnet-4-6.
#   SUBAGENT_MAX_TOKENS Optional. Defaults to 2048.

import argparse
import json
import os
import sys
import urllib.error
import urllib.request

MODEL_DEFAULT     = "claude-sonnet-4-6"
MAX_TOKENS_DEFAULT = 2048

SYSTEM_PROMPT = """\
You are a business analyst helping set up an AI assistant for a small business.
You receive raw notes from an operator interview and web research about the
business, and you produce a structured JSON object that will be used to
configure the assistant.

Your output must be valid JSON and nothing else — no preamble, no markdown
fences, no explanation outside the JSON object.

Be specific to this actual business. Do not produce generic capability
descriptions. Everything you write should be grounded in the interview or
research text provided. If a field cannot be grounded in the provided
information, write a concise placeholder marked with "[TO CONFIRM]" rather
than inventing facts.\
"""

USER_PROMPT_TEMPLATE = """\
Business: {business_name}, a {business_type} in {location}.
Brand tone: {brand_tone}. Language: {language}.
Owner: {owner_name}. Communication style: {communication_style}.
Timezone: {timezone}.
Additional details from operator: {vertical_details}

Web research findings:
{web_research}

Produce a JSON object with exactly these fields:

{{
  "vertical_capabilities_block": [
    "string — one concrete capability per item, 4–6 items",
    "ground each in the actual business type and details above",
    "write as '- <capability>' lines, e.g. '- Help draft responses to Google reviews in your brand voice'",
    "avoid generic phrasing like 'help manage your business' — be specific to this vertical"
  ],
  "vertical_brand_facts_block": [
    "string — one stable fact per item, 2–5 items",
    "only facts that do not change unless the owner makes a deliberate business decision",
    "e.g. founding year, location, owner name, brand story, core service categories",
    "do NOT include prices, hours, current offerings, or anything the owner changes routinely"
  ],
  "business_data_context_section": [
    "string — one item per context note, 3–8 items",
    "these are NOT operational facts (no prices/hours — those belong in the operational section)",
    "these are insider context lines that help the assistant sound like it knows this business:",
    "  - how customers typically describe their needs in this vertical",
    "  - common questions or objections the owner handles regularly",
    "  - local context (neighbourhood, nearby landmarks, how locals refer to things)",
    "  - seasonal or calendar patterns specific to this business",
    "  - tone or phrasing the owner uses (drawn from web research where possible)",
    "write as plain declarative sentences, not headings or bullets"
  ],
  "vault_seed_notes": {{
    "Reference/Business Overview.md": "string — a full Markdown note (200–400 words) ...",
    "Reference/Vertical Playbook.md": "string — a full Markdown note (150–300 words) ...",
    "Recurring/Patterns to Watch.md": "string — a full Markdown note (100–200 words) ..."
  }},
  "research_sources_used": [
    "string — list the actual sources consulted"
  ],
  "confidence": "high|medium|low"
}}
"""

REQUIRED_FIELDS = [
    "vertical_capabilities_block",
    "vertical_brand_facts_block",
    "business_data_context_section",
    "vault_seed_notes",
    "research_sources_used",
    "confidence",
]

REQUIRED_VAULT_NOTES = [
    "Reference/Business Overview.md",
    "Reference/Vertical Playbook.md",
    "Recurring/Patterns to Watch.md",
]


def fail(msg: str, code: int = 1) -> int:
    print(f"ERROR  {msg}", file=sys.stderr)
    return code


def build_user_prompt(interview: dict, web_research: str) -> str:
    return USER_PROMPT_TEMPLATE.format(
        business_name=interview.get("business_name", "[TO CONFIRM]"),
        business_type=interview.get("business_type", "[TO CONFIRM]"),
        location=interview.get("location", "[TO CONFIRM]"),
        brand_tone=interview.get("brand_tone", "[TO CONFIRM]"),
        language=interview.get("language", "English"),
        owner_name=interview.get("owner_name", "[TO CONFIRM]"),
        communication_style=interview.get("communication_style", "[TO CONFIRM]"),
        timezone=interview.get("timezone", "[TO CONFIRM]"),
        vertical_details=interview.get("vertical_details", "None provided."),
        web_research=web_research if web_research.strip() else "None available.",
    )


def call_api(api_key: str, model: str, max_tokens: int, user_prompt: str) -> dict:
    payload = {
        "model": model,
        "max_tokens": max_tokens,
        "system": SYSTEM_PROMPT,
        "messages": [{"role": "user", "content": user_prompt}],
    }
    body = json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(
        "https://api.anthropic.com/v1/messages",
        data=body,
        headers={
            "Content-Type": "application/json",
            "x-api-key": api_key,
            "anthropic-version": "2023-06-01",
        },
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=120) as resp:
        return json.loads(resp.read().decode("utf-8"))


def extract_text(api_response: dict) -> str:
    """Pull the assistant's text content from an Anthropic v1/messages response."""
    content = api_response.get("content", [])
    parts = [block.get("text", "") for block in content if block.get("type") == "text"]
    return "\n".join(parts).strip()


def validate_output(parsed: dict) -> list[str]:
    """Return a list of validation warnings (empty = all good)."""
    warnings = []
    for field in REQUIRED_FIELDS:
        if field not in parsed:
            warnings.append(f"missing field: {field}")
    vault = parsed.get("vault_seed_notes", {})
    for note in REQUIRED_VAULT_NOTES:
        if note not in vault:
            warnings.append(f"missing vault note: {note}")
    if parsed.get("confidence") not in ("high", "medium", "low"):
        warnings.append(f"unexpected confidence value: {parsed.get('confidence')!r}")
    return warnings


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Run the business intelligence sub-agent for tenant onboarding."
    )
    parser.add_argument("--tenant-id",   required=True, help="Tenant ID (for logging)")
    parser.add_argument("--output-file", required=True, help="Path to write JSON output")
    args = parser.parse_args()

    # --- API key ---
    api_key = os.environ.get("ANTHROPIC_API_KEY", "").strip()
    if not api_key:
        return fail("ANTHROPIC_API_KEY is not set or empty")

    model      = os.environ.get("SUBAGENT_MODEL", MODEL_DEFAULT)
    max_tokens = int(os.environ.get("SUBAGENT_MAX_TOKENS", MAX_TOKENS_DEFAULT))

    # --- Read context from stdin ---
    try:
        raw_stdin = sys.stdin.read()
        context = json.loads(raw_stdin)
    except json.JSONDecodeError as exc:
        return fail(f"stdin is not valid JSON: {exc}")

    interview    = context.get("interview", {})
    web_research = context.get("web_research", "")

    if not interview:
        return fail("context.interview is missing or empty")

    print(f"[research-subagent] tenant={args.tenant_id} model={model}", file=sys.stderr)

    # --- Build prompt ---
    user_prompt = build_user_prompt(interview, web_research)

    # --- Call API ---
    try:
        api_response = call_api(api_key, model, max_tokens, user_prompt)
    except urllib.error.HTTPError as exc:
        body = exc.read().decode("utf-8", errors="replace")
        return fail(f"Anthropic API HTTP {exc.code}: {body[:400]}")
    except urllib.error.URLError as exc:
        return fail(f"Anthropic API network error: {exc.reason}")
    except Exception as exc:  # noqa: BLE001
        return fail(f"Anthropic API unexpected error: {exc}")

    # --- Extract text ---
    text = extract_text(api_response)
    if not text:
        return fail("API response contained no text content")

    # --- Strip markdown fences if the model added them despite instructions ---
    if text.startswith("```"):
        lines = text.splitlines()
        # drop opening fence line and closing fence line
        lines = [l for l in lines if not l.strip().startswith("```")]
        text = "\n".join(lines).strip()

    # --- Parse JSON ---
    try:
        parsed = json.loads(text)
    except json.JSONDecodeError as exc:
        # Write the raw text to a sidecar file for diagnosis
        raw_path = args.output_file + ".raw"
        try:
            with open(raw_path, "w", encoding="utf-8") as f:
                f.write(text)
            print(f"[research-subagent] raw response saved to {raw_path}", file=sys.stderr)
        except OSError:
            pass
        return fail(f"sub-agent response is not valid JSON: {exc}")

    # --- Validate ---
    warnings = validate_output(parsed)
    if warnings:
        for w in warnings:
            print(f"[research-subagent] WARN {w}", file=sys.stderr)
        # Partial output is still useful — write it and exit 0 so the caller
        # can use whatever fields are present and fall back on missing ones.
        parsed["_validation_warnings"] = warnings

    # Stamp the tenant_id and model into the output for traceability
    parsed["_meta"] = {
        "tenant_id": args.tenant_id,
        "model": model,
        "confidence": parsed.get("confidence", "unknown"),
    }

    # --- Write output ---
    try:
        with open(args.output_file, "w", encoding="utf-8") as f:
            json.dump(parsed, f, indent=2, ensure_ascii=False)
            f.write("\n")
    except OSError as exc:
        return fail(f"could not write output file {args.output_file}: {exc}")

    sources = parsed.get("research_sources_used", [])
    print(
        f"[research-subagent] OK  confidence={parsed.get('confidence', '?')} "
        f"sources={len(sources)}  output={args.output_file}",
        file=sys.stderr,
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
