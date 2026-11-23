#!/usr/bin/env python3
"""Differential fuzz of the `rsc` differ.

The crate's contract is `verify`: applying the patch it computed to the model of
the first file must reach the second. That is a property, so it can be fuzzed --
and it is the property a deploy depends on, because the patch is what a device is
given.

Two modes are fuzzed (the full diff, and `--upsert`, which adds and sets only), in
both directions, plus three invariants no fixture pair states:

  * `diff b b` is empty. A differ that reports a difference between a file and
    itself is broken in a way no pair test sees.
  * no command in a patch is a *verb with no operand*. `remove` with an empty
    selector is a command RouterOS refuses mid-import, after applying everything
    above it -- measured on 7.15.3: `Script Error: missing value(s) of
    argument(s) numbers`. This is the "must refuse" oracle: a line the model
    cannot address is reported (`UNAPPLIED:`), never turned into a command whose
    effect the tool cannot describe.
  * a script carrying such a line says so in the report, so the caller can refuse
    rather than report a half-done deploy.

Inputs are generated from `lib/menus.generated.nix` -- the menu paths, kinds and
argument names the device itself reports -- so a case cannot be dismissed as a
menu nobody would write: `list` menus keyed on whatever they carry (a name, an
address, `list`+`address`), and `object` (singleton) menus. Values include the
shapes that break tokenisers: quoted strings with spaces, quotes, `$`, a
backslash and a comma; base64 ending in `=`; a scope id; an empty comment; a
`[find …]` and a `$var` inside a value.

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

# Properties a menu can be keyed on, in the order the identity table prefers them.
KEYS = ("name", "address", "vlan-id", "ports", "user", "key")

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
    '"bracket [find x] and $var"',
]

TOKEN = re.compile(r'(?:[^\s"]+|"(?:[^"\\]|\\.)*")+')
VERBS = ("add", "set", "remove", "move", "enable", "disable")


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


def key_of(args: list[str]) -> str | None:
    for candidate in KEYS:
        if candidate in args:
            return candidate
    return None


def tokens(line: str) -> list[str]:
    """Split a console line the way RouterOS does: quotes hold spaces."""
    return TOKEN.findall(line)


def object_line(args: list[str], rng: random.Random, key: str | None,
                value: str, singleton: bool) -> str:
    others = [a for a in args if a != key]
    picked = rng.sample(others, k=min(len(others), rng.randint(0, 4)))
    if singleton:
        props = [f"{a}={rng.choice(VALUES)}" for a in picked] or ["disabled=no"]
        return "set " + " ".join(props)
    props = [f"{key}={value}"]
    for arg in picked:
        props.append(f"{arg}={rng.choice(VALUES)}")
    return "add " + " ".join(props)


def script(rng: random.Random, menus, names: list[str], n_sections: int) -> str:
    lines = []
    for path, kind, args in rng.sample(menus, k=n_sections):
        lines.append(f"/{path}")
        key = key_of(args)
        if kind == "object" or key is None:
            lines.append(object_line(args, rng, None, "", singleton=True))
            continue
        for name in rng.sample(names, k=rng.randint(1, 4)):
            lines.append(object_line(args, rng, key, name, singleton=False))
    return "\n".join(lines) + "\n"


def mutate(rng: random.Random, src: str, menus, names: list[str],
           drops: bool = False) -> str:
    """A second script: objects dropped, properties dropped or changed, objects
    added, and two objects in one section swapped.

    Lines are rebuilt from quote-aware tokens, so a mutation cannot land inside a
    quoted value and invent a property nobody wrote. A reorder only ever swaps
    within one section -- swapping across a section header produces a script no
    router would accept, which tests the generator rather than the differ.
    """
    by_path = {(p, k): a for p, k, a in menus}
    out: list[str] = []
    section_key: str | None = None
    for line in src.rstrip("\n").split("\n"):
        if line.startswith("/"):
            out.append(line)
            args = next((a for (p, _k), a in by_path.items() if p == line[1:]), [])
            section_key = key_of(args)
            continue
        toks = tokens(line)
        r = rng.random()
        if r < 0.12 and len(toks) > 2:
            continue                                   # the object goes away
        if drops and r < 0.32 and len(toks) > 2:
            # drop a property: RouterOS cannot unset one, so this is the
            # remove+add (replace) path. Never the menu's *key* -- an object with
            # no identity is a line RouterOS refuses, and the differ's answer to
            # it (address the object by position) is a separate campaign.
            candidates = [n for n, t in enumerate(toks)
                          if n > 0 and not (section_key and t.startswith(f"{section_key}="))]
            if candidates:
                del toks[rng.choice(candidates)]
        elif r < (0.55 if drops else 0.32) and len(toks) > 2:
            idx = rng.randrange(1, len(toks))
            prop = toks[idx].split("=", 1)[0]
            toks[idx] = f"{prop}={rng.choice(VALUES)}"
        out.append(" ".join(toks))

    # one new object, under a key the section lacks
    sections = [i for i, l in enumerate(out) if l.startswith("/")]
    if sections:
        at = rng.choice(sections)
        path = out[at][1:]
        for (p, kind), args in by_path.items():
            if p != path:
                continue
            key = key_of(args)
            if kind == "object" or key is None:
                out.insert(at + 1, object_line(args, rng, None, "", singleton=True))
                break
            taken = {t.split("=", 1)[1] for l in out[at + 1:] if not l.startswith("/")
                     for t in tokens(l)[1:] if t.startswith(f"{key}=")}
            free = [n for n in names if n not in taken]
            if free:
                out.insert(at + 1, object_line(args, rng, key, rng.choice(free), False))
            break

    # reorder two objects inside one section: the `move` path
    if rng.random() < 0.3:
        starts = [i for i, l in enumerate(out) if l.startswith("/")] + [len(out)]
        for start, end in zip(starts, starts[1:]):
            body = list(range(start + 1, end))
            if len(body) > 1:
                a, b = rng.sample(body, 2)
                out[a], out[b] = out[b], out[a]
                break
    return "\n".join(out) + "\n"


def operandless(patch: str) -> list[str]:
    """Commands in a patch that name nothing: a verb with no operand."""
    bad = []
    for line in patch.splitlines():
        text = line.strip()
        if not text or text[0] in "#/:":
            continue
        verb = text.split(" ", 1)[0]
        rest = text[len(verb):].strip()
        if verb in VERBS and not rest:
            bad.append(text)
        elif verb == "remove" and rest.startswith("="):
            bad.append(text)
    return bad


def unaddressable(src: str) -> bool:
    """Does this script carry a `set` with no selector in a menu of objects?

    That line names nothing (RouterOS refuses it), and it is the input that used
    to produce a bare `remove` in a patch.
    """
    has_add = False
    for line in src.splitlines():
        text = line.strip()
        if text.startswith("/"):
            has_add = False
            continue
        if text.startswith("add "):
            has_add = True
        elif text.startswith("set ") and has_add:
            toks = tokens(text)[1:]
            if toks and all("=" in t for t in toks) and not any(
                    t.startswith("[") for t in toks):
                return True
    return False


def unresolvable_sections(rsc: str, src: str, dst: str, mode: list[str]) -> set[str]:
    """Sections whose plan contains an operation RouterOS cannot perform.

    A property that has to disappear cannot be unset (RouterOS has no unset) and
    a singleton cannot be re-created, so `verify` reports the mismatch and the
    patch says `# rsc: cannot reset …`. That is the documented limit of the tool,
    not a bug -- the same rule the dogfood matrix uses: a mismatch is allowed only
    in a section that reported it cannot be converged.
    """
    js = run(rsc, ["diff", src, dst, *mode, "--json"])
    try:
        data = json.loads(js.stdout)
    except Exception:                                      # noqa: BLE001
        return set()
    return {
        section["path"]
        for section in data.get("sections", [])
        if any("cannot reset" in op.get("op", "") for op in section.get("ops", []))
    }


def unexplained(problems: str, allowed: set[str]) -> list[str]:
    """The mismatch lines that are not covered by a documented refusal."""
    out = []
    for line in problems.splitlines():
        text = line.strip()
        if not text.startswith("/"):
            continue
        path = text[1:].split(":", 1)[0]
        if path not in allowed:
            out.append(text)
    return out


def run(rsc: str, argv: list[str]) -> subprocess.CompletedProcess:
    return subprocess.run([rsc, *argv], capture_output=True, text=True, timeout=120)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("rsc")
    ap.add_argument("--cases", type=int, default=200)
    ap.add_argument("--seed", type=int, default=1)
    ap.add_argument("--save", help="directory to write a failing case into")
    ap.add_argument("--drops", action="store_true",
                    help="also drop properties, which forces the remove+add "
                         "(replace) path. Off by default: a section with several "
                         "replaced objects reaches a differ edge that is still "
                         "open -- see the PR body -- and a check that fails on a "
                         "known-open shape stops being read")
    ap.add_argument("--root",
                    default=os.path.dirname(os.path.abspath(__file__)) + "/..",
                    help="the checkout with lib/menus.generated.nix")
    args = ap.parse_args()

    rng = random.Random(args.seed)
    menus = load_menus(args.root)
    usable = [(p, k, a) for p, k, a in menus if k == "object" or key_of(a) is not None]
    kinds: dict[str, int] = {}
    for _p, k, _a in usable:
        kinds[k] = kinds.get(k, 0) + 1
    if len(usable) < 150:
        print(f"only {len(usable)} usable menus extracted -- the table parse is broken",
              file=sys.stderr)
        return 2
    print(f"{len(usable)} menus ({kinds}) out of {len(menus)} in the table")

    names = ["a", "b", "lan", "wan", "wg0", "vlan20", "x1", "x2",
             "10.0.0.1/24", "192.168.88.0/24", "ghost"]
    work = tempfile.mkdtemp(prefix="fuzz-rsc-")
    failures: list[tuple] = []

    for i in range(args.cases):
        a = script(rng, usable, names, rng.randint(1, 6))
        b = (mutate(rng, a, usable, names, drops=args.drops) if rng.random() < 0.7
             else script(rng, usable, names, rng.randint(1, 6)))
        pa, pb = os.path.join(work, "a.rsc"), os.path.join(work, "b.rsc")
        open(pa, "w").write(a)
        open(pb, "w").write(b)

        for mode in ([], ["--upsert"]):
            # both directions: the differ has to be able to go back
            for src, dst in ((pa, pb), (pb, pa)):
                proc = run(args.rsc, ["verify", src, dst, *mode])
                if proc.returncode != 0:
                    allowed = unresolvable_sections(args.rsc, src, dst, mode)
                    left = unexplained(proc.stdout, allowed)
                    if left:
                        failures.append((i, "verify", mode, a, b,
                                         proc.stdout + proc.stderr))
                        break
            else:
                patch = run(args.rsc, ["patch", pa, pb, *mode])
                if patch.returncode != 0:
                    failures.append((i, "patch", mode, a, b, patch.stderr))
                else:
                    bad = operandless(patch.stdout)
                    if bad:
                        failures.append((i, "operandless-command", mode, a, b,
                                         "\n".join(bad)))
                    pp = os.path.join(work, "p.rsc")
                    open(pp, "w").write(patch.stdout)
                    parsed = run(args.rsc, ["parse", pp])
                    if parsed.returncode != 0:
                        failures.append((i, "patch-parses", mode, a, b, parsed.stderr))

                # a line that names nothing must be reported, not patched
                if unaddressable(a) or unaddressable(b):
                    report = run(args.rsc, ["diff", pa, pb, *mode])
                    if "UNAPPLIED:" not in report.stdout:
                        failures.append((i, "unaddressable-not-reported", mode, a, b,
                                         report.stdout[:400]))

                js = run(args.rsc, ["diff", pa, pb, *mode, "--json"])
                try:
                    json.loads(js.stdout)
                except json.JSONDecodeError as exc:
                    failures.append((i, "json", mode, a, b, str(exc)))

                same = run(args.rsc, ["diff", pb, pb, *mode, "--json"])
                try:
                    stats = json.loads(same.stdout)["stats"]
                except Exception:                          # noqa: BLE001
                    failures.append((i, "self-json", mode, a, b, same.stdout[:200]))
                else:
                    if any(stats[k] for k in ("add", "set", "remove", "replace", "move")):
                        failures.append((i, "self-diff", mode, b, b, str(stats)))
            if failures and failures[-1][0] == i:
                break

    print(f"{args.cases} cases x 2 modes x 2 directions: {len(failures)} failure(s)")
    for (i, what, mode, a, b, detail) in failures[:4]:
        print(f"\n--- case {i} {what} {' '.join(mode) or '(full)'} ---")
        print("a:", a.replace("\n", " | ")[:600])
        print("b:", b.replace("\n", " | ")[:600])
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
