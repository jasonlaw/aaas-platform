#!/usr/bin/env bash
# Scaffold the AaaS Platform knowledge vault: an Obsidian-compatible Markdown
# vault used as the platform's second brain. Safe to re-run; never overwrites
# existing notes.

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log()    { echo -e "${BLUE}[vault-init]${NC} $1"; }
success(){ echo -e "${GREEN}[OK]${NC} $1"; }
warn()   { echo -e "${YELLOW}[WARN]${NC} $1"; }
error()  { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

PLATFORM_ROOT="${PLATFORM_ROOT:-/opt/aaas/platform}"
VAULT_ROOT="${1:-$PLATFORM_ROOT/vault}"

log "Vault root: $VAULT_ROOT"

mkdir -p "$VAULT_ROOT/.obsidian"
mkdir -p "$VAULT_ROOT/Tenants"
mkdir -p "$VAULT_ROOT/Incidents"
mkdir -p "$VAULT_ROOT/SOPs"
mkdir -p "$VAULT_ROOT/Platform"
mkdir -p "$VAULT_ROOT/Daily"

# Minimal Obsidian app config so the folder opens cleanly as a vault with
# sane defaults. Deliberately small - no community plugins, no themes.
if [ ! -f "$VAULT_ROOT/.obsidian/app.json" ]; then
  cat > "$VAULT_ROOT/.obsidian/app.json" <<'EOF'
{
  "newFileLocation": "folder",
  "newFileFolderPath": "Daily",
  "alwaysUpdateLinks": true,
  "useMarkdownLinks": false
}
EOF
  success "Created .obsidian/app.json"
else
  warn ".obsidian/app.json already exists - leaving it unchanged"
fi

if [ ! -f "$VAULT_ROOT/.obsidian/community-plugins.json" ]; then
  echo "[]" > "$VAULT_ROOT/.obsidian/community-plugins.json"
fi

if [ ! -f "$VAULT_ROOT/Home.md" ]; then
  cat > "$VAULT_ROOT/Home.md" <<'EOF'
---
type: home
---

# AaaS Platform Knowledge Vault

This vault is the platform's second brain: curated, cross-linked notes that
sit on top of `/opt/aaas/platform/reports/` and `INDEX.jsonl`. The admin
agent writes here following
`/opt/aaas/platform/sop/sync-knowledge-vault.md`; the operator reads and
links freely in the Obsidian app.

This is about operating the platform, not any tenant's business. Each
tenant has its own, separate knowledge vault at
`/opt/aaas/tenants/{tenant-id}/vault/` (mounted into that tenant's container
at `/home/hermes/vault/`), maintained by the tenant agent itself, never by
the admin agent. If you're looking for a specific business's customer
notes, supplier list, or reference material, that lives in the tenant's own
vault, not here.

## Sections
- [[Tenants]] - one evolving note per tenant
- [[Incidents]] - timestamped incident write-ups with root cause and fix
- [[SOPs]] - accumulated commentary and gotchas per SOP (not the SOP text itself)
- [[Platform]] - architecture decisions and platform-wide notes
- [[Daily]] - optional running log, one note per day with activity worth tracking

## Conventions
- Link liberally with `[[Note Name]]`.
- Append dated entries to existing notes rather than rewriting history.
- Never store secrets, API keys, tokens, or customer private data here.
EOF
  success "Created Home.md"
else
  warn "Home.md already exists - leaving it unchanged"
fi

for section in Tenants Incidents SOPs Platform Daily; do
  placeholder="$VAULT_ROOT/$section/.gitkeep"
  [ -f "$placeholder" ] || touch "$placeholder"
done

success "Knowledge vault ready at $VAULT_ROOT"
echo ""
echo "Open this folder as a vault in the Obsidian app to browse it."
echo "Next: follow /opt/aaas/platform/sop/sync-knowledge-vault.md to start writing notes."