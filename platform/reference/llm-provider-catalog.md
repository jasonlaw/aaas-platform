# Reference: LLM Provider Catalog

**Read by:** `skills/setup-admin-hermes.md` (Step 5.2), `skills/manage-agent-vault.md`
(Section 2.1), `sop/onboard-tenant.md` (Step 1), `sop/provision-tenant-vault.md`
(Section 2). This file is the single source of truth for provider hostnames and
env var names — no other file should hardcode this table. If a table entry
here ever needs to change, change it here only.

## Purpose

Whoever is running setup (operator, tenant owner) should only ever have to say
*which provider and model* they want — e.g. `opencode-zen/big-pickle`,
`openrouter/free`, or `provider = openrouter, model = openai/gpt-oss-120b`.
**The env var name is never something to ask the human for — it is always
derived or looked up here.** This is what lets step 1 of onboarding (and the
equivalent admin "Ask The Operator" step) skip a question entirely.

## Derivation rule (for any provider on this list)

```
ENV_VAR = PROVIDER_ID.upper().replace('-', '_') + '_API_KEY'
```

This rule is confirmed consistent across every provider in the table below —
it is not a guess, it is the documented pattern. Apply it mechanically; do not
ask the operator to confirm the resulting name.

## Provider table

Only the **Provider ID** and **Hostname** columns carry real information — the
**Env var** column is always just the derivation rule applied to the Provider
ID, included here for convenience so nobody has to compute it by hand.

| Provider ID     | Display name       | Hostname                   | Env var                  |
|------------------|--------------------|-----------------------------|---------------------------|
| `openrouter`     | OpenRouter         | `openrouter.ai`             | `OPENROUTER_API_KEY`      |
| `openai`         | OpenAI             | `api.openai.com`            | `OPENAI_API_KEY`          |
| `anthropic`      | Anthropic          | `api.anthropic.com`         | `ANTHROPIC_API_KEY`       |
| `nous`           | Nous Portal        | `api.nous.ai`               | `NOUS_API_KEY`            |
| `opencode-zen`   | OpenCode Zen       | `opencode.ai`               | `OPENCODE_ZEN_API_KEY`    |
| `opencode-go`    | OpenCode Go        | `opencode.ai`               | `OPENCODE_GO_API_KEY`     |
| `gemini`         | Google Gemini      | `generativelanguage.googleapis.com` | `GEMINI_API_KEY`  |
| `xai`            | xAI (Grok, API key)| `api.x.ai`                  | `XAI_API_KEY`             |
| `deepseek`       | DeepSeek           | `api.deepseek.com`          | `DEEPSEEK_API_KEY`        |
| `groq`           | Groq               | `api.groq.com`              | `GROQ_API_KEY`            |
| `mistral`        | Mistral            | `api.mistral.ai`            | `MISTRAL_API_KEY`         |
| `together`       | Together AI        | `api.together.xyz`          | `TOGETHER_API_KEY`        |
| `fireworks`      | Fireworks AI       | `api.fireworks.ai`          | `FIREWORKS_API_KEY`       |
| `perplexity`     | Perplexity         | `api.perplexity.ai`         | `PERPLEXITY_API_KEY`      |
| `cohere`         | Cohere             | `api.cohere.com`            | `COHERE_API_KEY`          |
| `alibaba`        | Alibaba / Qwen Cloud | `dashscope.aliyuncs.com`  | `ALIBABA_API_KEY`         |
| `nvidia`         | NVIDIA NIM         | `integrate.api.nvidia.com`  | `NVIDIA_API_KEY`          |
| `zai`            | Z.ai (GLM)         | `api.z.ai`                  | `ZAI_API_KEY`             |
| `minimax`        | MiniMax            | `api.minimax.chat`          | `MINIMAX_API_KEY`         |
| `huggingface`    | Hugging Face Inference | `api-inference.huggingface.co` | `HUGGINGFACE_API_KEY` |

If runtime source code or a provider's own docs appear to contradict a
hostname or env var name in this table, **stop and escalate to the operator**
before writing any credential — do not silently self-resolve the conflict,
and do not add or change a row without operator confirmation.

## Provider not in this table

If the operator/tenant names a provider not listed here (plain API-key,
OpenAI-compatible provider), do not guess at a hostname. Ask the operator for
the provider's API hostname only — never ask for the env var name, which is
still derived by the rule above once you have the Provider ID. Add the
confirmed row to this table so future setups skip the question.

## Exceptions — do not attempt automatic setup for these

These do not fit the single-hostname / single-bearer-token model this
platform's Agent Vault integration is built on ({PROVIDER_VAR} + one
`agent-vault vault service add --host` per provider — see
`manage-agent-vault.md`). If one of these is requested, stop and escalate to
the operator rather than attempting to force it into the standard flow:

- **OAuth-only providers** (e.g. `xai-oauth`, `minimax-oauth`, `qwen-oauth`,
  `copilot`, `copilot-acp`) — no static API key exists to store in Agent
  Vault; these require an interactive browser/device login flow that has no
  place in headless admin/tenant provisioning.
- **Multi-credential providers** (e.g. `bedrock` — AWS access key + secret,
  not one bearer token; `azure-foundry` — endpoint + key pair) — these need
  more than one secret and don't map onto the `{PROVIDER_VAR}=` /
  `Bearer {PROVIDER_VAR}` pattern this platform's vault registration assumes.

## Out of scope: no custom-endpoint / arbitrary base_url support

This platform does not support arbitrary self-hosted or non-cataloged
OpenAI-compatible endpoints (`provider: custom` + `base_url` in Hermes's own
config schema). Every provider onboarded here must be a named entry in this
table, going through the standard `model.provider` + Agent Vault hostname
registration path — see `setup-admin-hermes.md` Step 5.2 and
`manage-agent-vault.md` Section 2.1 for why the custom path is intentionally
out of scope for now.
