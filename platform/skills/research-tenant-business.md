---
name: research-tenant-business
description: >
  Run a focused sub-agent to synthesise raw interview answers and web
  research into richer, structured tenant context during onboarding
  (onboard-tenant step 1.15). Produces four artifacts consumed by later
  onboarding steps: VERTICAL_CAPABILITIES_BLOCK, VERTICAL_BRAND_FACTS_BLOCK,
  enriched business-data content, and vault seed notes. Use only from within
  onboard-tenant.md — never called standalone.
---

# Skill: Research Tenant Business (sub-agent)

This skill is called at onboard-tenant step 1.15, after the operator interview
(step 1) and web research (step 1.1) are complete. Its job is synthesis, not
more collection: it turns raw material into the specific artifacts that make the
tenant agent genuinely useful from day one rather than starting from a shallow
template.

The sub-agent runs as a single Anthropic API call from the host. The admin
agent assembles the prompt, calls the API, validates the JSON output, and
feeds the result into the rest of the onboarding SOP.

---

## When to call this skill

After completing onboard-tenant steps 1 and 1.1. You should have:
- Operator interview answers (business name, type, location, brand tone,
  owner name, vertical details, communication style, timezone)
- Web research text from step 1.1 (website copy, review snippets, social
  bios, Google Business data — whatever was found)

If web research found nothing (private/unlaunched business, access blocked),
proceed with interview answers only. The sub-agent handles sparse input.

---

## How to call the sub-agent

Run this Python one-liner from the host. Substitute the placeholders before
running — do not pass unsanitised shell variables directly into the JSON body.

```bash
python3 /opt/aaas/platform/scripts/run-business-research-subagent.py \
  --tenant-id    "{tenant-id}" \
  --output-file  "/tmp/aaas-research-{tenant-id}.json"
# The script reads the interview + research context from stdin (see below)
```

The script is a thin wrapper that:
1. Reads the JSON context block you pipe to it on stdin
2. Calls `POST https://api.anthropic.com/v1/messages` using
   `$ANTHROPIC_API_KEY` (or the platform's configured LLM key)
3. Writes the sub-agent's structured JSON response to `--output-file`
4. Exits non-zero if the API call fails or the response cannot be parsed

### Context block (stdin JSON)

Pipe a JSON object with two fields:

```json
{
  "interview": {
    "business_name": "...",
    "business_type": "...",
    "location": "...",
    "brand_tone": "...",
    "owner_name": "...",
    "language": "...",
    "communication_style": "...",
    "timezone": "...",
    "vertical_details": "...",
    "primary_color": "...",
    "secondary_color": "..."
  },
  "web_research": "...raw text from step 1.1, or empty string if nothing found..."
}
```

### Full invocation example

```bash
python3 /opt/aaas/platform/scripts/run-business-research-subagent.py \
  --tenant-id    "sunny-paws-grooming" \
  --output-file  "/tmp/aaas-research-sunny-paws-grooming.json" \
  <<'CONTEXT'
{
  "interview": {
    "business_name": "Sunny Paws Grooming",
    "business_type": "pet grooming salon",
    "location": "Fremantle, WA",
    "brand_tone": "warm, playful, reassuring",
    "owner_name": "Sam",
    "language": "English",
    "communication_style": "casual, emoji-friendly",
    "timezone": "Australia/Perth",
    "vertical_details": "mobile and in-salon grooming for dogs and cats. specialises in anxious pets. 3 groomers. appointment-only.",
    "primary_color": "#F4A03A",
    "secondary_color": "#FFFFFF"
  },
  "web_research": "Sunny Paws Grooming Fremantle — 4.9 stars on Google (127 reviews). Known for gentle handling of nervous dogs. Offers breed-specific cuts. Popular services: bath & brush, full groom, nail trim. Opens 8am–5pm Tue–Sat. Closed Sun–Mon. Waitlist often 2–3 weeks. Owner Sam has 12 years experience."
}
CONTEXT
```

---

## Sub-agent prompt

The script sends the following system prompt and user message to the API.
This is the source of truth for what the sub-agent is asked to produce —
if the output format ever needs to change, update both this skill file and
`run-business-research-subagent.py`.

**System prompt:**

```
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
than inventing facts.
```

**User message template** (assembled by the script from the context block):

```
Business: {business_name}, a {business_type} in {location}.
Brand tone: {brand_tone}. Language: {language}.
Owner: {owner_name}. Communication style: {communication_style}.
Timezone: {timezone}.
Additional details from operator: {vertical_details}

Web research findings:
{web_research or "None available."}

Produce a JSON object with exactly these fields:

{
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
  "vault_seed_notes": {
    "Reference/Business Overview.md": "string — a full Markdown note (200–400 words) covering: what this business does, its positioning, what makes it distinctive, who its customers are, and how the owner wants it to be perceived. Use the research and interview to make this specific. Include frontmatter: type: reference, created_utc: <placeholder>.",
    "Reference/Vertical Playbook.md": "string — a full Markdown note (150–300 words) covering: typical workflows in this vertical that the assistant will help with, common patterns (recurring tasks, seasonal rhythms, peak periods), and anything the owner should know about how the assistant will approach tasks in this space. Use the interview details and research findings. Include frontmatter: type: reference, created_utc: <placeholder>.",
    "Recurring/Patterns to Watch.md": "string — a full Markdown note (100–200 words) listing 3–5 recurring patterns specific to this business that the assistant should track over time (e.g. 'Waitlist fills 2–3 weeks ahead — flag when slots open', 'Google review replies should be posted within 48h'). Draw from research and interview. Include frontmatter: type: recurring, created_utc: <placeholder>."
  },
  "research_sources_used": [
    "string — list the actual sources consulted (website URL, 'Google Business listing', 'Instagram bio', etc.)",
    "or ['operator interview only'] if no web research was available"
  ],
  "confidence": "high|medium|low — high if research corroborated interview answers, medium if research was sparse, low if only interview answers were available with no external validation"
}
```

---

## Reading the output

After the script exits 0, read the output file:

```bash
cat /tmp/aaas-research-{tenant-id}.json
```

Parse each field and use it as follows in the onboarding SOP:

| Output field | Used in onboarding step |
|---|---|
| `vertical_capabilities_block` | Step 1.2 → `VERTICAL_CAPABILITIES_BLOCK` (replaces cold generation) |
| `vertical_brand_facts_block` | Step 1.2 → `VERTICAL_BRAND_FACTS_BLOCK` for `MEMORY.md` seeding |
| `business_data_context_section` | Step 4.1 → appended to `business-data.md` as a "Context" section |
| `vault_seed_notes` | Step 4.2 → written as seed notes into the scaffolded vault |
| `research_sources_used` | Step 19 → include in task report under "Sources used" |
| `confidence` | Step 2 → surface to operator in confirmation summary |

**Do not pass the raw JSON to the operator.** Render each field in plain
language as part of the step 2 confirmation summary. The JSON is an internal
intermediate artifact, not operator-facing output.

---

## Handling failures

**API call fails (network, auth, rate limit):**
Log the error and fall back to cold generation for step 1.2 (as the SOP
previously did). Note the fallback in the task report. Do not abort
onboarding — the sub-agent is an enhancement, not a hard dependency.

**Output is not valid JSON:**
Same fallback as above. If the response text looks like a partial JSON
object, do not attempt to parse or repair it — log it as a raw string in
the task report and proceed with cold generation.

**A field is missing or empty:**
Fall back to cold generation for that field only. Other fields from a
partial response can still be used.

**`[TO CONFIRM]` placeholders in output:**
Surface these to the operator at step 2 confirmation, clearly flagged as
"needs operator input before we continue." Do not write `[TO CONFIRM]`
into any rendered template file — resolve them first or omit that specific
line from the output.

**`confidence: low`:**
Flag this to the operator at step 2: "The business intelligence sub-agent
had limited research to work with — the generated context is based mainly
on your interview answers. Consider providing a website URL or Google
Business link after onboarding to let the agent update its Reference notes."

---

## Cleanup

After onboarding completes (step 19), remove the temp file:

```bash
rm -f /tmp/aaas-research-{tenant-id}.json
```
