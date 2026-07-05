#!/usr/bin/env python3
# Run the business intelligence sub-agent during tenant onboarding.
#
# Called by onboard-tenant.md step 1.15 via the research-tenant-business skill.
# Reads a JSON context block from stdin, runs it through the admin Hermes
# agent's own one-shot completion path, and writes the sub-agent's
# structured JSON response to --output-file.
#
# Exits 0 on success. Exits non-zero on any failure — the caller (admin agent)
# is responsible for falling back to cold generation when this script fails.
# Never raises unhandled exceptions: all errors are printed to stderr and
# result in a clean non-zero exit so the SOP fallback path can proceed.
#
# --- Credential model (fixed 2026-07-05) -----------------------------------
# Previous versions of this script called api.anthropic.com directly with a
# raw ANTHROPIC_API_KEY read from the bare host environment. Nothing in
# setup-platform.sh / setup-prerequisites.sh / setup-admin-hermes.md actually
# provisions that variable, and it was never the same credential the admin
# or tenant Hermes agents use anyway: every provider key in this platform's
# .env files is the placeholder string "routed-via-agent-vault" — the real
# key lives only in Agent Vault and is injected at the network layer by its
# MITM proxy. A bare os.environ read could only ever find a *real* usable
# Anthropic key if someone had separately, manually exported one on the
# host — which nothing here asks anyone to do. In practice this meant the
# sub-agent failed on every onboarding whose admin/tenant provider wasn't
# literally a hand-provisioned Anthropic key sitting directly in the shell.
#
# Fixed by dropping the direct API call entirely and instead shelling out to
# `hermes -z` from the admin Hermes install (/opt/aaas/platform/admin) — the
# same one-shot invocation this platform already uses for proxy probes
# (setup-admin-hermes.md Step 7, manage-agent-vault.md, handle-watchdog-alert.md)
# and for tenant eval checks (eval-runner.sh). Running it from the admin
# install with the admin's own .env sourced means it automatically inherits:
#   - whichever model/provider the admin agent is actually configured with
#     (platform/admin/config.yaml's model.provider / model.default)
#   - the already-provisioned Agent Vault routing: HTTP_PROXY, HTTPS_PROXY,
#     AGENT_VAULT_TOKEN, SSL_CERT_FILE (platform/admin/.env)
# No second, unprovisioned credential is required, and no per-provider
# request/response format needs reimplementing here — Hermes already knows
# how to talk to whatever provider it's configured with.
#
# Usage:
#   python3 run-business-research-subagent.py \
#     --tenant-id    "my-tenant" \
#     --output-file  "/tmp/aaas-research-my-tenant.json" \
#     < context.json
#
# Environment (all optional — defaults match this platform's standard layout):
#   ADMIN_HERMES_HOME       Path to the admin Hermes install. Default:
#                           /opt/aaas/platform/admin
#   LLM_PROVIDER_CATALOG    Path to the shared provider catalog, used only
#                           for the pre-flight proxy reachability check.
#                           Default: /opt/aaas/platform/reference/llm-provider-catalog.md
#   SUBAGENT_HERMES_TIMEOUT Bounded timeout (seconds) for the hermes -z call.
#                           `hermes -z` has no internal timeout (see
#                           CHANGELOG / setup-admin-hermes.md Step 7), so this
#                           script enforces one itself rather than risking an
#                           indefinite hang during onboarding. Default: 180.

import argparse
import json
import os
import re
import subprocess
import sys
from pathlib import Path

ADMIN_HOME_DEFAULT = "/opt/aaas/platform/admin"
CATALOG_PATH_DEFAULT = "/opt/aaas/platform/reference/llm-provider-catalog.md"

HERMES_Z_TIMEOUT_DEFAULT = 180   # bounded — hermes -z itself has no timeout
PROXY_PRECHECK_TIMEOUT = 10      # matches setup-admin-hermes.md Step 7's curl pre-check

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

INSTRUCTION_ECHO_MARKERS = [
    "avoid generic phrasing",
    "one concrete capability per item",
    "one stable fact per item",
    "one item per context note",
    "do not change unless the owner makes",
]

ARRAY_LENGTH_BOUNDS = {
    "vertical_capabilities_block": (4, 6),
    "vertical_brand_facts_block": (2, 5),
    "business_data_context_section": (3, 8),
}


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


def load_env_file(path: Path) -> dict:
    """Minimal .env parser: KEY=VALUE lines, '#' comments, blank lines.
    No shell expansion — matches how this platform's env files are written
    (no $VAR references in values)."""
    env = {}
    if not path.is_file():
        return env
    for raw_line in path.read_text().splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, _, value = line.partition("=")
        env[key.strip()] = value.strip()
    return env


def read_admin_provider(admin_home: Path) -> str | None:
    """Best-effort read of platform/admin/config.yaml's model.provider, used
    only for the pre-flight proxy reachability check below — the hermes -z
    call itself always uses whatever the admin install is actually
    configured with, independent of whether this lookup succeeds."""
    config_path = admin_home / "config.yaml"
    if not config_path.is_file():
        return None
    in_model_block = False
    for line in config_path.read_text().splitlines():
        if re.match(r"^model:\s*$", line):
            in_model_block = True
            continue
        if in_model_block:
            if line and not line[0].isspace():
                break
            m = re.match(r"^\s+provider:\s*(\S+)", line)
            if m:
                return m.group(1).strip()
    return None


def read_catalog_hostname(catalog_path: Path, provider_id: str) -> str | None:
    """Look up provider_id's hostname from the shared catalog table instead
    of duplicating it here — llm-provider-catalog.md is this platform's
    documented single source of truth for the mapping."""
    if not catalog_path.is_file():
        return None
    row_re = re.compile(r"^\|\s*`?" + re.escape(provider_id) + r"`?\s*\|[^|]*\|\s*`?([^`|]+?)`?\s*\|")
    for line in catalog_path.read_text().splitlines():
        m = row_re.match(line.strip())
        if m:
            return m.group(1).strip()
    return None


def proxy_precheck(admin_env: dict, hostname: str | None, timeout: int) -> tuple[bool, str]:
    """Bounded connectivity check against the provider host through Agent
    Vault's proxy, mirroring setup-admin-hermes.md Step 7. `hermes -z` has
    no internal timeout, so a broken proxy path otherwise presents as an
    indefinite hang instead of a diagnosable error — this fails fast with
    an actual error first."""
    token = admin_env.get("AGENT_VAULT_TOKEN")
    if not token or not hostname:
        return True, "skipped (missing AGENT_VAULT_TOKEN or unresolved provider hostname); proceeding to hermes -z directly"
    proxy_url = f"http://{token}@localhost:14322"
    try:
        result = subprocess.run(
            ["curl", "-sS", "--max-time", str(timeout), "-o", "/dev/null",
             "-w", "%{http_code}", "--proxy", proxy_url, f"https://{hostname}/"],
            capture_output=True, text=True, timeout=timeout + 5,
        )
        code = result.stdout.strip() or "n/a"
        return True, f"proxy reachable to {hostname} (http_code={code})"
    except subprocess.TimeoutExpired:
        return False, f"proxy pre-check to {hostname} timed out after {timeout}s — check Agent Vault / nftables (docs/troubleshooting.md)"
    except Exception as exc:  # noqa: BLE001
        return False, f"proxy pre-check to {hostname} failed: {exc}"


def call_hermes(admin_home: Path, admin_env: dict, prompt: str, timeout: int) -> str:
    """Run one bounded one-shot completion via the admin Hermes install's
    own `hermes -z`, inheriting its configured provider/model and its
    already-provisioned Agent Vault routing. Same mechanism used for proxy
    probes elsewhere in this platform (setup-admin-hermes.md, manage-agent-
    vault.md, handle-watchdog-alert.md) and for tenant evals (eval-runner.sh)."""
    env = os.environ.copy()
    env.update(admin_env)
    try:
        result = subprocess.run(
            ["hermes", "-z", prompt],
            cwd=str(admin_home),
            env=env,
            capture_output=True,
            text=True,
            timeout=timeout,
        )
    except FileNotFoundError as exc:
        raise RuntimeError("`hermes` binary not found on PATH — this script must run on the admin host") from exc
    except subprocess.TimeoutExpired as exc:
        raise RuntimeError(
            f"hermes -z did not return within {timeout}s (it has no internal "
            f"timeout — see setup-admin-hermes.md Step 7). Check the proxy "
            f"pre-check result above for the likely cause."
        ) from exc
    if result.returncode != 0:
        raise RuntimeError(f"hermes -z exited {result.returncode}: {result.stderr.strip()[:500]}")
    return result.stdout.strip()


def extract_json_text(raw: str) -> str:
    """hermes -z prints plain text to stdout — strip accidental markdown
    fences before parsing, same defensive handling the JSON output needs
    regardless of which transport produced it."""
    cleaned = raw.strip()
    cleaned = re.sub(r"^```(?:json)?\s*", "", cleaned)
    cleaned = re.sub(r"\s*```$", "", cleaned)
    return cleaned


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

    for field, (low, high) in ARRAY_LENGTH_BOUNDS.items():
        value = parsed.get(field)
        if isinstance(value, list) and not (low <= len(value) <= high):
            warnings.append(f"{field} has {len(value)} items, expected {low}-{high}")
        items_to_scan = value if isinstance(value, list) else []
        for item in items_to_scan:
            if not isinstance(item, str):
                continue
            lowered = item.lower()
            for marker in INSTRUCTION_ECHO_MARKERS:
                if marker in lowered:
                    warnings.append(
                        f"{field} item looks like echoed schema instructions, not generated content: {item[:80]!r}"
                    )
                    break

    return warnings


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Run the business intelligence sub-agent for tenant onboarding."
    )
    parser.add_argument("--tenant-id",   required=True, help="Tenant ID (for logging)")
    parser.add_argument("--output-file", required=True, help="Path to write JSON output")
    args = parser.parse_args()

    admin_home = Path(os.environ.get("ADMIN_HERMES_HOME", ADMIN_HOME_DEFAULT))
    catalog_path = Path(os.environ.get("LLM_PROVIDER_CATALOG", CATALOG_PATH_DEFAULT))
    hermes_timeout = int(os.environ.get("SUBAGENT_HERMES_TIMEOUT", HERMES_Z_TIMEOUT_DEFAULT))

    admin_env_file = admin_home / ".env"
    admin_env = load_env_file(admin_env_file)
    if not admin_env:
        return fail(f"could not read admin env file at {admin_env_file} — is ADMIN_HERMES_HOME correct?")

    # --- Pre-flight: bounded proxy reachability check (fail fast, not hang) ---
    provider_id = read_admin_provider(admin_home)
    hostname = read_catalog_hostname(catalog_path, provider_id) if provider_id else None
    precheck_ok, precheck_msg = proxy_precheck(admin_env, hostname, PROXY_PRECHECK_TIMEOUT)
    print(f"[research-subagent] proxy pre-check: {precheck_msg}", file=sys.stderr)
    if not precheck_ok:
        return fail(f"Agent Vault proxy unreachable before calling hermes -z: {precheck_msg}")

    # --- Read context from stdin ---
    try:
        context = json.loads(sys.stdin.read())
    except json.JSONDecodeError as exc:
        return fail(f"stdin is not valid JSON: {exc}")

    interview    = context.get("interview", {})
    web_research = context.get("web_research", "")

    if not interview:
        return fail("context.interview is missing or empty")

    print(
        f"[research-subagent] tenant={args.tenant_id} provider={provider_id or 'unknown'} via='hermes -z' (admin install)",
        file=sys.stderr,
    )

    # --- Build prompt (system + user combined — hermes -z takes one prompt string) ---
    user_prompt = build_user_prompt(interview, web_research)
    full_prompt = f"{SYSTEM_PROMPT}\n\n---\n\n{user_prompt}"

    # --- Call hermes -z, inheriting the admin agent's provider + Agent Vault routing ---
    try:
        raw_output = call_hermes(admin_home, admin_env, full_prompt, hermes_timeout)
    except RuntimeError as exc:
        return fail(str(exc))

    if not raw_output:
        return fail("hermes -z returned no output")

    text = extract_json_text(raw_output)

    # --- Parse JSON ---
    try:
        parsed = json.loads(text)
    except json.JSONDecodeError as exc:
        raw_path = args.output_file + ".raw"
        try:
            with open(raw_path, "w", encoding="utf-8") as f:
                f.write(text)
            print(f"[research-subagent] raw response saved to {raw_path}", file=sys.stderr)
        except OSError:
            pass
        # Best-effort truncation heuristic: hermes -z doesn't expose a
        # stop_reason the way a raw Anthropic API response did, so we can no
        # longer detect max_tokens truncation directly — an unclosed
        # brace/bracket is the closest available signal.
        looks_truncated = bool(text) and text.rstrip()[-1] not in "}]"
        if looks_truncated:
            return fail(
                f"sub-agent response looks truncated (does not end in }} or ]) "
                f"— raw partial output saved to {raw_path}: {exc}"
            )
        return fail(f"sub-agent response is not valid JSON: {exc}")

    # --- Validate ---
    warnings = validate_output(parsed)
    if warnings:
        for w in warnings:
            print(f"[research-subagent] WARN {w}", file=sys.stderr)
        parsed["_validation_warnings"] = warnings

    parsed["_meta"] = {
        "tenant_id": args.tenant_id,
        "provider": provider_id or "unknown",
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
