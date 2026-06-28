#!/usr/bin/env bash
# Scaffold this tenant's knowledge vault: an Obsidian-compatible Markdown
# vault that is this tenant's durable, owner-browsable second brain.
# Runs inside the tenant container by default, using /home/hermes/vault.
# Safe to re-run; never overwrites existing notes.
#
# This is NOT Mnemosyne (in-conversation recall) and NOT business-data.md
# (today's prices/menu/hours). See the README this script creates for the
# three-way split, and SOUL.md for the decision rule the tenant agent follows.

set -euo pipefail

TENANT_ROOT="${TENANT_ROOT:-/opt/aaas/tenants}"
TENANT_ID="${1:-}"

if [ -n "${TENANT_DIR:-}" ]; then
  TENANT_DIR="$TENANT_DIR"
elif [ -d /opt/data ]; then
  TENANT_DIR="/opt/data"
elif [ -n "$TENANT_ID" ]; then
  TENANT_DIR="$TENANT_ROOT/$TENANT_ID"
else
  echo "Usage: $0 [tenant-id]  (or set TENANT_DIR)" >&2
  exit 2
fi

if [ -n "${VAULT_DIR:-}" ]; then
  VAULT_ROOT="$VAULT_DIR"
elif [ -d /home/hermes ]; then
  VAULT_ROOT="/home/hermes/vault"
else
  VAULT_ROOT="$TENANT_DIR/vault"
fi

BUSINESS_NAME="${BUSINESS_NAME:-this business}"

log()    { echo "[vault-init-tenant] $1"; }
success(){ echo "[OK] $1"; }
warn()   { echo "[WARN] $1"; }

log "Vault root: $VAULT_ROOT"

mkdir -p "$VAULT_ROOT/.obsidian"
mkdir -p "$VAULT_ROOT/Customers"
mkdir -p "$VAULT_ROOT/Suppliers"
mkdir -p "$VAULT_ROOT/Recurring"
mkdir -p "$VAULT_ROOT/Reference"

if [ ! -f "$VAULT_ROOT/.obsidian/app.json" ]; then
  cat > "$VAULT_ROOT/.obsidian/app.json" <<'EOF'
{
  "newFileLocation": "folder",
  "newFileFolderPath": "Reference",
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

if [ ! -f "$VAULT_ROOT/README.md" ]; then
  cat > "$VAULT_ROOT/README.md" <<EOF
---
type: home
tenant_id: "${TENANT_ID:-}"
---

# ${BUSINESS_NAME} — Knowledge Vault

This is your assistant's knowledge vault: plain Markdown notes you can open,
read, edit, and link in the Obsidian app (https://obsidian.md). It is
separate from two other systems your assistant uses:

- **Mnemosyne** is in-conversation recall only - you won't see it as files,
  and it is not meant to be browsed.
- **business-data.md** (\`files/assets/business-data.md\`) is the one file
  with today's prices, menu, hours, and availability. Edit that file
  directly whenever those change - your assistant always re-reads it.

This vault is for everything else worth its own note over time: customers,
suppliers, recurring tasks, and reference material you've given your
assistant. Your assistant writes and updates notes here as it learns things
worth remembering in a structured way; you can also edit any note directly.

## Sections
- [[Customers]] - one note per customer, preferences and history
- [[Suppliers]] - one note per supplier or vendor
- [[Recurring]] - recurring tasks, patterns, or reminders
- [[Reference]] - material you've given your assistant to keep on hand

## Conventions
- Link freely with [[Note Name]] - that's what makes this a "second brain"
  rather than a pile of separate files.
- Your assistant appends dated entries to existing notes rather than
  rewriting their history, so a note becomes a timeline you can scroll back
  through.
- Nothing here should ever contain payment details, passwords, or other
  secrets - tell your assistant right away if you ever see something like
  that in a note.

---

## For the assistant (not the owner)

Everything above this line is written for the business owner. This section
is your own quick reference; skip it when summarizing the vault to the
owner.

- Search before writing: \`grep -ril "{keyword}" /home/hermes/vault --include='*.md'\`
  across a few keyword variants (customer name, supplier name, topic) before
  deciding a note doesn't exist yet.
- Update, don't duplicate: if a relevant note exists, append a dated entry
  (\`## YYYY-MM-DD\`) rather than rewriting it.
- New note frontmatter convention:
  \`\`\`markdown
  ---
  type: customer|supplier|recurring|reference
  created_utc: "YYYY-MM-DDTHH:MM:SSZ"
  ---
  \`\`\`
- Link both directions where it makes sense (a customer note linking to a
  recurring order pattern note, and vice versa).
- Never write current prices, menu items, hours, or availability here - that
  is business-data.md's job. Never write secrets here. See SOUL.md for the
  full three-way decision rule between Mnemosyne, business-data.md, and this
  vault.
EOF
  success "Created README.md"
else
  warn "README.md already exists - leaving it unchanged"
fi

for section in Customers Suppliers Recurring Reference; do
  placeholder="$VAULT_ROOT/$section/.gitkeep"
  [ -f "$placeholder" ] || touch "$placeholder"
done

success "Tenant knowledge vault ready at $VAULT_ROOT"