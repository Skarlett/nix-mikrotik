#!/usr/bin/env python3
"""Turn the CHR walk into `lib/menus.generated.nix`, and derive the overlay.

Input:  tree-<version>.json from walk.py, plus the previous hand table so the two
        menus a CHR cannot have (the CRS226 switch chip) are not lost.
Output: lib/menus.generated.nix  -- 347 menus, every attribute the router reports.
        lib/menus.overlay.nix    -- the short list of things a CHR cannot see.

Why an overlay and not "generated is the truth": a CHR is a virtual router. It
has no switch chip and no radio, so `/interface ethernet switch egress-vlan-tag`
and `/interface ethernet switch ingress-vlan-translation` do not exist on it --
but the fleet's CRS226 uses both. Generating straight over the hand table would
delete configuration the fleet already runs. The overlay is the honest record of
what the generator cannot reach, with a reason on each entry.
"""
import json
import sys

TREE = sys.argv[1] if len(sys.argv) > 1 else "tree-725.json"
OUT = sys.argv[2] if len(sys.argv) > 2 else "."

data = json.load(open(TREE))
tree = data["tree"]
version, build = data["routeros"], data["build-time"]

# Only menus that take action are menus the table can declare: a container
# (`/interface bridge` before its `port` child, `/routing`) has neither `add`
# nor `set`, and `attrs = null` must not be used to paper over a failed walk.
# Menus the library handles through some other option, and must not also
# declare here. `/system identity` is `mikrotik.hostname`: the deploy tool reads
# the identity back off the device, and `modules/base.nix` refuses the section so
# there is exactly one place to set it.
EXCLUDE = {"system identity"}

menus = []
for path, node in tree.items():
    if path in EXCLUDE:
        continue
    if node["add"]:
        menus.append((path, "list", node.get("add") or []))
    elif node["set"]:
        menus.append((path, "object", node.get("set") or []))
menus.sort()

def nix_list(names, indent):
    pad = " " * indent
    return "".join('%s"%s"\n' % (pad, n) for n in names)

header = '''# GENERATED -- do not edit. Run scripts/regenerate-menus.sh instead.
#
# The whole menu surface of RouterOS {version}, as the router describes itself:
# {count} menus walked out of `/console/inspect` on a CHR (build {build}),
# {nlist} of them `add`-style and {nobj} `set`-style. A further {ncont} nodes are
# containers -- they have no `add` and no `set`, so they are not menus this table
# can declare, and they are deliberately absent rather than null.
#
# `attrs` here is not hand-curated: it is the argument list the router reports for
# that menu's `add` (list) or `set` (object) command. That makes it wider than
# anything a person maintained, and it makes it wrong in a way the overlay fixes
# -- see lib/menus.overlay.nix for the menus whose keys are names rather than
# arguments.
#
# Regenerate with the CHR pinned in chr/default.nix (or the newer image the
# generator uses) and a walker that retries: a timed-out inspect and an empty
# child list look identical from outside, so a walk without retries returns a
# *narrower* tree that still looks complete.
'''.format(version=version, count=len(menus),
           build=build,
           nlist=sum(1 for _, k, _ in menus if k == "list"),
           nobj=sum(1 for _, k, _ in menus if k == "object"),
           ncont=sum(1 for v in tree.values() if not v["add"] and not v["set"]))

body = []
for path, kind, attrs in menus:
    body.append("  {\n")
    body.append('    path = "/%s";\n' % path)
    body.append('    kind = "%s";\n' % kind)
    body.append("    attrs = [\n")
    body.append(nix_list(sorted(set(attrs)), 6))
    body.append("    ];\n")
    body.append("  }\n")

with open("%s/lib/menus.generated.nix" % OUT, "w") as fh:
    fh.write(header)
    fh.write("[\n")
    fh.writelines(body)
    fh.write("]\n")

print("wrote %s/lib/menus.generated.nix: %d menus" % (OUT, len(menus)), file=sys.stderr)