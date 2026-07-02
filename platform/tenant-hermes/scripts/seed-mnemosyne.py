#!/usr/bin/env python3
# Seed Mnemosyne with atomic, per-line facts from a file.
#
# Replaces the old `mnemosyne store "$(sudo cat FILE)" SOURCE IMPORTANCE`
# pattern (see mnemosyne-seed-corruption.md): that piped a whole file through
# the CLI as one blob, with no scope, via host `sudo cat` + `docker exec`
# string interpolation. This script runs the SDK directly (no shell
# interpolation, no sudo), stores one memory per fact line, and sets
# scope="global" explicitly — a plain remember() defaults to session scope,
# which the seeding process's own throwaway invocation would never share
# with the tenant/admin agent's real sessions.
#
# Usage: seed-mnemosyne.py <file> <source> [importance]
#   <file>       path to a fact file, already curated to one fact per line
#                (comment lines starting with # and blank lines are skipped)
#   <source>     Mnemosyne source tag, e.g. "fact" or "preference"
#   [importance] 0.0-1.0, default 0.8
#
# Exits non-zero on ANY failed store, so a partial seed is never reported as
# success.

import sys

from mnemosyne import remember


def main() -> int:
    if len(sys.argv) < 3:
        print(f"usage: {sys.argv[0]} <file> <source> [importance]", file=sys.stderr)
        return 2

    path, source = sys.argv[1], sys.argv[2]
    importance = float(sys.argv[3]) if len(sys.argv) > 3 else 0.8

    with open(path, encoding="utf-8") as f:
        facts = [line.strip() for line in f]
    facts = [f for f in facts if f and not f.startswith("#")]

    if not facts:
        print(f"no facts found in {path}", file=sys.stderr)
        return 1

    for fact in facts:
        try:
            memory_id = remember(fact, importance=importance, source=source, scope="global")
        except Exception as exc:  # noqa: BLE001 - any SDK failure must abort the seed
            print(f"FAILED to store ({exc}): {fact!r}", file=sys.stderr)
            return 1
        if not memory_id:
            print(f"FAILED to store (no id returned): {fact!r}", file=sys.stderr)
            return 1

    print(f"stored {len(facts)} fact(s) from {path} as source={source}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
