#!/usr/bin/env python3
# Write vault seed notes produced by the business intelligence sub-agent
# into the scaffolded tenant knowledge vault.
#
# Called by onboard-tenant.md step 4.2, after vault-init-tenant.sh has
# scaffolded the vault directory structure. Reads the sub-agent JSON output
# file and writes each note under vault_seed_notes into the vault.
#
# Safe to re-run: never overwrites an existing note. If a note already exists
# (e.g. the operator ran this twice), the existing file is left unchanged and
# a SKIP line is printed. This matches the idempotency convention of
# vault-init-tenant.sh.
#
# Usage:
#   python3 seed-vault-context.py \
#     --research-file  "/tmp/aaas-research-{tenant-id}.json" \
#     --vault-dir      "/home/hermes/vault"
#
# Environment overrides (for testing):
#   VAULT_DIR   Overrides --vault-dir if set.
#
# Exit codes:
#   0   All notes written (or already existed — idempotent).
#   1   One or more notes failed to write.
#   2   Bad arguments or unreadable input file.

import argparse
import json
import os
import sys
from datetime import datetime, timezone


def fail(msg: str, code: int = 2) -> int:
    print(f"FAIL  {msg}", file=sys.stderr)
    return code


def now_utc() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def inject_created_utc(content: str, timestamp: str) -> str:
    """Replace the <placeholder> created_utc in frontmatter with a real timestamp."""
    return content.replace("created_utc: <placeholder>", f"created_utc: \"{timestamp}\"")


def write_note(vault_dir: str, relative_path: str, content: str, timestamp: str) -> str:
    """
    Write a vault note. Returns 'written', 'skipped', or 'failed:<reason>'.
    Never overwrites an existing file.
    """
    abs_path = os.path.join(vault_dir, relative_path)
    parent   = os.path.dirname(abs_path)

    if os.path.exists(abs_path):
        return "skipped"

    try:
        os.makedirs(parent, exist_ok=True)
    except OSError as exc:
        return f"failed:could not create directory {parent}: {exc}"

    content = inject_created_utc(content, timestamp)

    try:
        with open(abs_path, "w", encoding="utf-8") as f:
            f.write(content)
            if not content.endswith("\n"):
                f.write("\n")
    except OSError as exc:
        return f"failed:could not write {abs_path}: {exc}"

    return "written"


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Seed tenant vault with notes from the business intelligence sub-agent."
    )
    parser.add_argument(
        "--research-file", required=True,
        help="Path to the sub-agent JSON output file (from run-business-research-subagent.py)"
    )
    parser.add_argument(
        "--vault-dir", default="",
        help="Vault root directory. Overridden by $VAULT_DIR if set."
    )
    args = parser.parse_args()

    vault_dir = os.environ.get("VAULT_DIR", "").strip() or args.vault_dir
    if not vault_dir:
        return fail("--vault-dir is required (or set $VAULT_DIR)")

    if not os.path.isdir(vault_dir):
        return fail(f"vault directory not found: {vault_dir}")

    research_file = args.research_file
    if not os.path.isfile(research_file):
        return fail(f"research file not found: {research_file}")

    # --- Read sub-agent output ---
    try:
        with open(research_file, encoding="utf-8") as f:
            data = json.load(f)
    except json.JSONDecodeError as exc:
        return fail(f"research file is not valid JSON: {exc}")

    vault_seed_notes = data.get("vault_seed_notes", {})
    if not vault_seed_notes:
        print("WARN  vault_seed_notes is empty or missing in research file — nothing to write")
        return 0

    timestamp  = now_utc()
    written    = 0
    skipped    = 0
    failed     = 0

    for relative_path, content in vault_seed_notes.items():
        if not isinstance(content, str) or not content.strip():
            print(f"SKIP  {relative_path}  (empty content)")
            skipped += 1
            continue

        result = write_note(vault_dir, relative_path, content, timestamp)

        if result == "written":
            print(f"PASS  {relative_path}")
            written += 1
        elif result == "skipped":
            print(f"SKIP  {relative_path}  (already exists — leaving unchanged)")
            skipped += 1
        else:
            print(f"FAIL  {relative_path}  ({result.removeprefix('failed:')})", file=sys.stderr)
            failed += 1

    print(f"\n{written} written, {skipped} skipped, {failed} failed — vault: {vault_dir}")

    if failed > 0:
        return 1

    return 0


if __name__ == "__main__":
    sys.exit(main())
