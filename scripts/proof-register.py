#!/usr/bin/env python3
"""meteroid proof-register gate — static, toolchain-independent.

Ported from `linkfold/scripts/proof-register.py` (itself ported from
`intent/scripts/proof-register.py`) — same mechanical half of the register
rule, adapted to this repo's schema (`proof/PROOF.md`):

  * every ``#[pure_core]`` function in the tree has exactly one ``[[core]]``
    row in ``proof/register.toml``;
  * every ``[[core]]`` row names a function that carries ``#[pure_core]``;
  * every row carries a ``status`` and at least one control;
  * a ``"Lean (native)"`` row names a ``lean_module``/``lean_file`` and that
    file exists (checking `lake build` actually passed is `lake build`'s job,
    not this script's — this gate only checks the row is honestly filled in);
  * an ``"Aeneas"`` row carries a 40-hex proof-repo commit and a 64-hex
    artifact hash (unused today — Phase 3's real Aeneas attempt failed on a
    confirmed float-support gap, `proof/RESEARCH.md` — kept for the day a
    future integer-only target uses it);
  * ``"owed"`` rows are allowed to be otherwise empty — that is the honest,
    unproved status, not a violation.

Run directly::

    python3 scripts/proof-register.py        # check this repo
    python3 scripts/proof-register.py --root DIR
"""

from __future__ import annotations

import argparse
import re
import sys
import tomllib
from pathlib import Path

MARKER = "#[pure_core]"
# Anchored to the start of a line (mod leading whitespace): a bare substring
# search also matches `#[pure_core]` mentioned inside a `///` doc comment
# (e.g. "Not `#[pure_core]`: ...") — linkfold's own script hit exactly this
# false-positive the first time it ran; anchoring avoids repeating it.
_MARKER_RE = re.compile(r"^[ \t]*#\[pure_core\]", re.MULTILINE)
REGISTER = "proof/register.toml"

_HEX40 = re.compile(r"^[0-9a-f]{40}$")
_HEX64 = re.compile(r"^[0-9a-f]{64}$")
_KNOWN_STATUSES = {"lean (native)", "aeneas", "named trust", "encoding boundary", "owed"}


def marked_functions(root: Path) -> dict[str, str]:
    """Every ``#[pure_core]`` function name -> its file (relative to root)."""
    found: dict[str, str] = {}
    for f in sorted(root.rglob("*.rs")):
        if "target" in f.parts:
            continue
        text = f.read_text()
        for m in _MARKER_RE.finditer(text):
            tail = text[m.end() : m.end() + 600]
            fn = re.search(r"\bfn\s+([A-Za-z_][A-Za-z0-9_]*)", tail)
            if fn:
                found[fn.group(1)] = str(f.relative_to(root))
    return found


def check(root: Path) -> list[str]:
    register = root / REGISTER
    if not register.exists():
        return [f"{REGISTER}: missing the proof register (proof/PROOF.md)"]

    try:
        data = tomllib.loads(register.read_text())
    except tomllib.TOMLDecodeError as e:
        return [f"{REGISTER}: invalid TOML: {e}"]

    problems: list[str] = []

    rows = data.get("core", [])
    if not rows:
        problems.append(f"{REGISTER}: no [[core]] rows")

    by_name: dict[str, dict] = {}
    for i, row in enumerate(rows):
        name = row.get("function")
        if not name:
            problems.append(f"{REGISTER}: [[core]] #{i} has no `function`")
            continue
        if name in by_name:
            problems.append(f"{REGISTER}: duplicate row for `{name}`")
        by_name[name] = row

        status_raw = str(row.get("status", "")).strip()
        status = status_raw.lower()
        if not status_raw:
            problems.append(f"{REGISTER}: row `{name}` has no status")
        elif status not in _KNOWN_STATUSES:
            problems.append(
                f"{REGISTER}: row `{name}` has an unrecognized status "
                f"`{status_raw}` (proof/PROOF.md lists the known statuses)"
            )

        if status == "lean (native)":
            lean_module = str(row.get("lean_module", "")).strip()
            lean_file = str(row.get("lean_file", "")).strip()
            if not lean_module:
                problems.append(f"{REGISTER}: row `{name}` has no `lean_module`")
            if not lean_file:
                problems.append(f"{REGISTER}: row `{name}` has no `lean_file`")
            elif not (root / lean_file).exists():
                problems.append(
                    f"{REGISTER}: row `{name}` names a missing lean_file `{lean_file}`"
                )
        elif status == "aeneas":
            if not _HEX64.match(str(row.get("artifact_sha256", ""))):
                problems.append(
                    f"{REGISTER}: row `{name}` claims Aeneas but has no proof "
                    "artifact hash (artifact_sha256)"
                )
            if not _HEX40.match(str(row.get("proof_repo_commit", ""))):
                problems.append(
                    f"{REGISTER}: row `{name}` claims Aeneas but has no proof-repo commit"
                )

        if status and status != "owed" and not row.get("controls"):
            problems.append(f"{REGISTER}: row `{name}` has no control")

        f = row.get("file")
        if f and not (root / f).exists():
            problems.append(f"{REGISTER}: row `{name}` names a missing file `{f}`")

    marked = marked_functions(root)
    for name, path in sorted(marked.items()):
        if name not in by_name:
            problems.append(
                f"{path}: `{name}` is #[pure_core] but has no row in {REGISTER}"
            )
    for name, row in sorted(by_name.items()):
        if name not in marked:
            problems.append(
                f"{REGISTER}: row `{name}` has no #[pure_core] marker in the tree"
            )
    return problems


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", default=str(Path(__file__).resolve().parents[1]))
    args = ap.parse_args()
    root = Path(args.root)
    problems = check(root)
    if problems:
        print("FAIL proof_register")
        for p in problems:
            print(f"     {p}")
        print(f"\nproof register: {len(problems)} problem(s)")
        return 1
    print("ok   proof_register")
    print("\nproof register: green")
    return 0


if __name__ == "__main__":
    sys.exit(main())
