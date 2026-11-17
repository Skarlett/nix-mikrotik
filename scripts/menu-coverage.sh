#!/usr/bin/env bash
# Does `lib/menus.nix` still describe what the fleet's routers actually use?
#
# The table is hand-maintained: per RouterOS menu, the attribute names a body may
# use, and `checkMenuAttributes` turns a name that is not in it into an
# evaluation error. `lists` -- the attributes the device stores as several values
# -- is part of the same promise: `checkMenuLists` refuses a comma-joined string,
# so a fleet that still writes one stops building when the pin moves. That makes the table a promise, and a promise drifts -- the
# fleet grows a `/ip firewall filter` attribute, the table does not know it, and
# the failure lands in the consuming repository rather than here, where the table
# is.
#
# This script asks the question from this side. It renders the fleet's two
# routers against *this* checkout and compares the menus and attribute names they
# emit with the table:
#
#     scripts/menu-coverage.sh /path/to/Infra/lunix
#
# Exit 0 when the table covers everything the fleet uses, 1 when it does not, and
# 2 when it could not be asked (no nix, no checkout, a router that does not
# evaluate) -- a distinct code because "cannot tell" must not read as "fine".
set -euo pipefail

repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
fleet=${1:-}

if [[ -z $fleet || ! -f $fleet/flake.nix ]]; then
  printf 'usage: %s <path to an Infra/lunix checkout>\n' "$0" >&2
  exit 2
fi

for tool in nix python3; do
  command -v "$tool" >/dev/null || { printf 'missing %s\n' "$tool" >&2; exit 2; }
done

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

# The table, as data rather than as Nix source to grep.
nix eval --impure --json --expr "import $repo/lib/menus.nix" > "$work/menus.json" 2>"$work/table.err" || {
  echo 'could not evaluate lib/menus.nix:' >&2
  cat "$work/table.err" >&2
  exit 2
}

routers=$(nix eval --impure --json --expr \
  "builtins.attrNames (builtins.getFlake \"path:$fleet\").mikrotikConfigurations" 2>"$work/routers.err") || {
  echo "could not read mikrotikConfigurations from $fleet:" >&2
  cat "$work/routers.err" >&2
  exit 2
}

for r in $(python3 -c 'import json,sys; print(" ".join(json.load(sys.stdin)))' <<<"$routers"); do
  # Render with *this* checkout standing in for the fleet's pinned nix-mikrotik,
  # which is the whole point: the table under test is this one.
  nix eval --raw --impure \
    --override-input nix-mikrotik "path:$repo" \
    "path:$fleet#mikrotikConfigurations.$r.script" > "$work/$r.rsc" 2>"$work/$r.err" || {
    # A render failure is usually the answer rather than an obstacle: the typed
    # surface refuses an attribute the table does not list, so a fleet that grew
    # one fails here with exactly the sentence this script exists to produce.
    if grep -q 'has no attribute named\|no menu for' "$work/$r.err"; then
      printf 'lib/menus.nix does not describe what the fleet uses (%s):\n\n' "$r" >&2
      grep -o 'mikrotik\.[^:]*: [^.]*\. Known names[^.]*\.' "$work/$r.err" | head -5 >&2
      exit 1
    fi
    printf '%s: does not render against this checkout:\n' "$r" >&2
    tail -20 "$work/$r.err" >&2
    exit 2
  }
done

python3 - "$work" <<'PY'
import json, re, shlex, sys
from collections import defaultdict

work = sys.argv[1]
menus = {m["path"]: (m.get("attrs"), m.get("kind"), m.get("lists") or []) for m in json.load(open(f"{work}/menus.json"))}

# Menus that reach the render through `extraScript` rather than through the
# table, and cannot be told apart from a section once rendered: chr1 sets an
# ethernet property with a selector (`set [ find default-name=ether1 ] …`) and
# carries a ~70-line `/system script` block, neither of which the section model
# can express. They are the documented escape hatch, not table drift.
EXTRA_SCRIPT = {"/interface ethernet", "/system script"}
# The identity is `mikrotik.hostname` on purpose, so the deploy tool can read it
# back off the device; the table refuses the section for that reason.
DELIBERATE = {"/system identity"}

def parse(path):
    """{section: {attribute: [values]}}, for the `add` lines only.

    Only `add` lines are attributed. A `set` line keys on an object name
    (`set ftp disabled=yes vrf=…`) rather than on attributes, so reading its
    `k=v` pairs as attribute names would report every value as drift.
    """
    raw = re.sub(r"\\\n\s*", "", open(path, newline="").read().replace("\r\n", "\n"))
    section, out = None, defaultdict(dict)
    for line in raw.split("\n"):
        s = line.strip()
        if not s or s.startswith("#"):
            continue
        if s.startswith("/"):
            section = s
            out.setdefault(section, {})
            continue
        if section is None or not s.startswith("add "):
            continue
        for tok in shlex.split(s[4:]):
            if "=" in tok:
                key, value = tok.split("=", 1)
                out[section].setdefault(key, []).append(value)
            else:
                out[section].setdefault(tok, [])
    return out

used = defaultdict(lambda: defaultdict(list))
for r in ("homelab-router", "chr1"):
    for sec, attrs in parse(f"{work}/{r}.rsc").items():
        for k, vs in attrs.items():
            used[sec][k].extend(vs)

missing_menus, missing_attrs, comma = [], [], []
for sec in sorted(used):
    if sec in EXTRA_SCRIPT or sec in DELIBERATE:
        continue
    if sec not in menus:
        missing_menus.append(sec)
        continue
    known, kind, lists = menus[sec]
    if known is None or kind != "list":   # object menus key on names, not attributes
        continue
    unknown = sorted(set(used[sec]) - set(known))
    if unknown:
        missing_attrs.append((sec, unknown))
    # An argument the device stores as several values, written as one
    # comma-joined string. The script renders the same either way, so nothing
    # else can see it -- and this repository now refuses it at evaluation time,
    # which means the fleet has to be migrated rather than discovered.
    for k in lists:
        for v in used[sec].get(k, []):
            if "," in v:
                comma.append((sec, k, v))

if not missing_menus and not missing_attrs and not comma:
    covered = len([s for s in used if s not in EXTRA_SCRIPT and s not in DELIBERATE])
    print(f"menu table covers the fleet: {covered} menus, every `add` attribute known")
    sys.exit(0)

if comma and not missing_menus and not missing_attrs:
    print("the fleet still writes an argument this table now requires as a list:\n")
    for sec, k, v in comma:
        print(f'  {sec}: {k}="{v}"  ->  {k} = [ … ]')
    print("\nThe typed menu refuses the comma-joined string at evaluation time, so a")
    print("pin bump lands on a fleet that does not build until these are lists.")
    print("A *single* value on one of these arguments cannot be told apart here --")
    print("it renders the same as a one-element list -- and it has to become")
    print("`k = [ \"v\" ]` as well; that part only the fleet's own evaluation shows.")
    sys.exit(1)

print("lib/menus.nix does not describe what the fleet uses.\n")
for sec in missing_menus:
    print(f"  no menu for {sec}")
for sec, attrs in missing_attrs:
    print(f"  {sec}: unknown attribute(s) {', '.join(attrs)}")
print("\nAdd them to lib/menus.nix (path/kind/attrs). Until then the fleet's build")
print("is the thing that fails, there, with 'has no attribute named …'.")
sys.exit(1)
PY
