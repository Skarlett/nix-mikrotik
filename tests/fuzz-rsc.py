#!/usr/bin/env python3
"""Differential fuzz of the `rsc` differ.

The crate's contract is `verify`: applying the patch it computed to the model of
the first file must reach the second. That is a property, so it can be fuzzed --
and it is the property a deploy depends on, because the patch is what a device is
given.

Two modes are fuzzed: the full diff, and `--upsert` (adds and sets only, with
deletions withheld), whose contract is "every object the target declares is
reached, with every property it declares".

Inputs are generated from `lib/menus.generated.nix` -- the menu paths, kinds and
argument names the device itself reports -- so a case cannot be dismissed as a
menu nobody would write. Only `list` menus with a `name` are used, and a
generated object never repeats a property: the point is to test the differ, not
to feed it files RouterOS could not parse.

Values include the shapes that break tokenisers: a quoted string with spaces,
quotes, `$` and a backslash; base64 ending in `=`; a comma list; a bare token; an
empty comment; a scope id.

It is a tool as much as a check: `checks.rsc-fuzz` runs it with a fixed seed, and
a longer sweep by hand is `tests/fuzz-rsc.py <rsc> --cases 2000 --seed $RANDOM`.

Usage: fuzz-rsc.py <rsc> [--cases N] [--seed S] [--save DIR] [--root DIR]
"""
import argparse
import json
import os
import random
import re
import subprocess
import sys
import tempfile

MENUS = "lib/menus.generated.nix"


def load_menus(root: str) -> list[tuple[str, str, list[str]]]:
    """(path, kind, arguments) triples out of the generated table."""
    text = open(os.path.join(root, MENUS), encoding="utf-8").read()
    out = []
    for block in re.finditer(
            r'path = "([^"]+)";\s*kind = "([^"]+)";\s*attrs = \[(.*?)\];', text, re.S):
        path, kind, body = block.group(1), block.group(2), block.group(3)
        args = re.findall(r'"([^"]+)"', body)
        if args:
            out.append((path, kind, args))
    return out


VALUES = [
    "value",
    "10.0.0.1/24",
    "51820",
    "1d",
    "0x0A620002",
    "fe80::1%wg0",
    "!flag",
    '"a b"',
    '"has \\"quotes\\" and $dollar"',
    "QUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUE=",
    '"QUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUE="',
    '"eth1,eth2"',
    '""',
    '"multi word comment with = and ;"',
]

# An object line for a `list` menu: `name` first (the key), then a random subset
# of the menu's other arguments, never repeating a property.
def object_line(args: list[str], rng: random.Random, name: str) -> str:
    others = [a for a in args if a != "name"]
    picked = rng.sample(others, k=min(len(others), rng.randint(0, 4)))
    props = [f"name={name}"]
    for arg in picked:
        if arg == "comment" and rng.random() < 0.2:
            props.append('comment=""')
            continue
        props.append(f"{arg}={rng.choice(VALUES)}")
    return "add " + " ".join(props)


def script(rng: random.Random, menus, n_sections: int, names: list[str]) -> str:
    lines = []
    for path, args in rng.sample(menus, k=n_sections):
        lines.append(f"/{path}")
        for name in rng.sample(names, k=rng.randint(1, 4)):
            lines.append(object_line(args, rng, name))
    return "\n".join(lines) + "\n"


TOKEN = re.compile(r'(?:[^\s"]+|"(?:[^"\\]|\\.)*")+')


def tokens(line: str) -> list[str]:
    """Split a console line the way RouterOS does: quotes hold spaces."""
    return TOKEN.findall(line)


def name_of(line: str) -> str | None:
    for tok in tokens(line)[1:]:
        key, sep, value = tok.partition("=")
        if sep and key == "name":
            return value.strip('"')
    return None


def mutate(rng: random.Random, src: str, menus, names: list[str]) -> str:
    """A second script: objects dropped, values changed, objects added.

    Lines are rebuilt from quote-aware tokens, so a mutation cannot land inside a
    quoted value and invent a property nobody wrote -- a fuzzer that corrupts its
    own input tests the tokeniser, not the differ. Names are checked against the
    list as it stands *after* the mutations, so a generated script never carries
    two objects under one name (which RouterOS would refuse, and which the model
    would have to guess at).
    """
    by_path = {p: args for p, args in menus}
    out: list[str] = []
    for line in src.rstrip("\n").split("\n"):
        if line.startswith("/"):
            out.append(line)
            continue
        toks = tokens(line)
        name = name_of(line)
        r = rng.random()
        if r < 0.2 and name:
            continue                                   # the object goes away
        if r < 0.45 and len(toks) > 2:
            # change one value the object already carries, never its name
            candidates = [i for i, t in enumerate(toks)
                          if "=" in t and not t.startswith("name=")]
            if candidates:
                idx = rng.choice(candidates)
                key = toks[idx].split("=", 1)[0]
                toks[idx] = f"{key}={rng.choice(VALUES)}"
        out.append(" ".join(toks))

    # one new object in a section that exists, under a name the section lacks
    sections = [i for i, l in enumerate(out) if l.startswith("/")]
    if sections:
        at = rng.choice(sections)
        path = out[at][1:]
        taken = {n for n in (name_of(l) for l in out[at + 1:]
                             if not l.startswith("/")) if n}
        free = [n for n in names if n not in taken]
        if free and path in by_path:
            out.insert(at + 1, object_line(by_path[path], rng, rng.choice(free)))
    return "\n".join(out) + "\n"


def run(rsc: str, argv: list[str]) -> subprocess.CompletedProcess:
    return subprocess.run([rsc, *argv], capture_output=True, text=True, timeout=120)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("rsc")
    ap.add_argument("--cases", type=int, default=100)
    ap.add_argument("--seed", type=int, default=1)
    ap.add_argument("--save", help="directory to write a failing case into")
    ap.add_argument("--root", default=os.path.dirname(os.path.abspath(__file__)) + "/..",
                    help="the checkout with lib/menus.generated.nix")
    args = ap.parse_args()

    rng = random.Random(args.seed)
    menus = [(p, a) for (p, k, a) in load_menus(args.root)
             if k == "list" and "name" in a]
    if len(menus) < 100:
        print(f"only {len(menus)} keyed list menus extracted -- the table parse is broken",
              file=sys.stderr)
        return 2
    names = ["a", "b", "lan", "wan", "wg0", "vlan20", "x1", "x2", "ghost"]

    work = tempfile.mkdtemp(prefix="fuzz-rsc-")
    failures = []
    for i in range(args.cases):
        a = script(rng, menus, rng.randint(1, 6), names)
        b = (mutate(rng, a, menus, names) if rng.random() < 0.7
             else script(rng, menus, rng.randint(1, 6), names))
        pa = os.path.join(work, "a.rsc")
        pb = os.path.join(work, "b.rsc")
        open(pa, "w").write(a)
        open(pb, "w").write(b)

        for mode in ([], ["--upsert"]):
            proc = run(args.rsc, ["verify", pa, pb, *mode])
            if proc.returncode != 0:
                failures.append((i, "verify", mode, a, b, proc.stdout + proc.stderr))
                break
            patch = run(args.rsc, ["patch", pa, pb, *mode])
            if patch.returncode != 0:
                failures.append((i, "patch", mode, a, b, patch.stderr))
                break
            pp = os.path.join(work, "p.rsc")
            open(pp, "w").write(patch.stdout)
            parsed = run(args.rsc, ["parse", pp])
            if parsed.returncode != 0:
                failures.append((i, "patch-parses", mode, a, b, parsed.stderr))
                break
            js = run(args.rsc, ["diff", pa, pb, *mode, "--json"])
            if js.returncode != 0:
                failures.append((i, "json-exit", mode, a, b, js.stderr))
                break
            try:
                json.loads(js.stdout)
            except json.JSONDecodeError as exc:
                failures.append((i, "json-parse", mode, a, b, str(exc)))
                break

    print(f"{args.cases} cases x 2 modes: {len(failures)} failure(s)")
    for (i, what, mode, a, b, detail) in failures[:4]:
        print(f"\n--- case {i} {what} {' '.join(mode) or '(full)'} ---")
        print("a:", a.replace("\n", " | ")[:500])
        print("b:", b.replace("\n", " | ")[:500])
        print(detail.strip()[:900])
    if failures and args.save:
        os.makedirs(args.save, exist_ok=True)
        for n, (i, what, mode, a, b, detail) in enumerate(failures):
            tag = f"{n:02d}-{what}-{'upsert' if mode else 'full'}"
            open(os.path.join(args.save, f"{tag}-a.rsc"), "w").write(a)
            open(os.path.join(args.save, f"{tag}-b.rsc"), "w").write(b)
            open(os.path.join(args.save, f"{tag}.txt"), "w").write(detail)
        print(f"\nsaved {len(failures)} failing case(s) under {args.save}")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
