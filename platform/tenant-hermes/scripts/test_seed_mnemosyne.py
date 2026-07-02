#!/usr/bin/env python3
# Minimal self-check for seed-mnemosyne.py: no real Mnemosyne install
# required, just stubs the `mnemosyne` module before importing the script.

import sys
import types
import importlib.util
from pathlib import Path
from unittest import mock

SCRIPT = Path(__file__).with_name("seed-mnemosyne.py")


def load_script(remember_fn):
    stub = types.ModuleType("mnemosyne")
    stub.remember = remember_fn
    sys.modules["mnemosyne"] = stub
    spec = importlib.util.spec_from_file_location("seed_mnemosyne", SCRIPT)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def test_skips_blanks_and_comments(tmp_path):
    f = tmp_path / "MEMORY.md"
    f.write_text("# header comment\n\nBusiness: Blue Oak Cafe\nBrand tone: warm\n\n")
    calls = []
    mod = load_script(lambda content, **kw: calls.append((content, kw)) or "id-1")
    with mock.patch.object(sys, "argv", ["seed-mnemosyne.py", str(f), "fact"]):
        rc = mod.main()
    assert rc == 0
    assert [c[0] for c in calls] == ["Business: Blue Oak Cafe", "Brand tone: warm"]
    assert all(kw["scope"] == "global" and kw["source"] == "fact" for _, kw in calls)


def test_fails_loud_on_store_error(tmp_path):
    f = tmp_path / "MEMORY.md"
    f.write_text("one fact\nbad fact\n")

    def flaky_remember(content, **kw):
        if content == "bad fact":
            raise RuntimeError("db locked")
        return "id-1"

    mod = load_script(flaky_remember)
    with mock.patch.object(sys, "argv", ["seed-mnemosyne.py", str(f), "fact"]):
        rc = mod.main()
    assert rc == 1  # must not report success on a partial seed


if __name__ == "__main__":
    import tempfile

    with tempfile.TemporaryDirectory() as d:
        test_skips_blanks_and_comments(Path(d))
    with tempfile.TemporaryDirectory() as d:
        test_fails_loud_on_store_error(Path(d))
    print("OK")
