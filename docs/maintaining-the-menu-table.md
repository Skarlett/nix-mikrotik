# Maintaining the menu table

`lib/menus.nix` is what turns `mikrotik.ip."dhcp-server".network` into an
option path, what makes a misspelt attribute an evaluation error, and what
decides that `interfaces = "ether1,ether2"` is the wrong spelling. Two
assertions make it load-bearing for every repository that consumes this one, so
a change to it is a promise to them:

* `checkMenuAttributes` — an attribute name the table does not list is refused;
* `checkMenuLists` — a comma-joined string on an argument the device stores as
  several values is refused.

This is how to change it without breaking either.

## Three files, one table

| file | who writes it |
|---|---|
| `lib/menus.generated.nix` | `scripts/gen-menus.py`, from a real RouterOS. Never edit. |
| `lib/menus.overlay.nix` | a person, one entry per thing the generator cannot see, each with a `why` |
| `lib/menus.nix` | merges the two; the only file `modules/menus.nix` imports |

`lib/menus.generated.nix` carries three things per menu: `path` (RouterOS'
spelling), `kind` (`list` for a menu of objects, `object` for a singleton), and
`attrs` — the argument names the router reports for that menu's `add` or `set`
command. It may also carry `lists`: the arguments RouterOS stores as several
values. Both `attrs` and `lists` come out of the device; the overlay exists
because a CHR has no switch chip, no radio, and no memory of the menus whose
keys are names rather than arguments.

## Regenerating

```sh
scripts/regenerate-menus.sh                # fetch, boot, walk, probe, generate
scripts/regenerate-menus.sh --skip-boot    # walk and probe a device already up
```

There is no argument to skip the probe: a table without `lists` is a table that
lets the comma-joined spelling through silently, which is the thing the previous
four releases did.

What the script does, in order:

1. fetch `chr-$VERSION-$VARIANT.qcow2` from `elseif/MikroTikPatch` and check it
   against the release's published sha256 — a wrong image is a wrong table,
   silently;
2. boot it, once, into `$CHR_STATE` (default
   `~/.hermes/cache/scratch/chrgen-$VERSION`); the disk keeps its licence and
   host keys, so a second run reuses it;
3. wait for the router to answer on `$CHR_SSH_PORT` (2325 by default);
4. `scripts/walk-menus.py` — `/console/inspect` down the whole CLI tree;
5. `scripts/probe-menu-lists.py` — ask what each argument does with a
   comma-separated value (this one **writes to the device**; lab only);
6. `scripts/gen-menus.py` — write `lib/menus.generated.nix`
   (`tree-$VERSION.json` and `lists-$VERSION.json` are kept beside it, because
   the review below is mostly a reading of those two).

Environment: `VERSION` (default `7.25`), `VARIANT` (default `legacy-bios`),
`CHR_SSH_PORT`, `CHR_STATE`.

**The image has to be the `legacy-bios` one.** The plain `chr-<v>.qcow2` in the
same release is UEFI: booted under `-machine q35` with no firmware it runs,
writes nothing to the console, and never answers SSH — which reads as a network
problem and sends you looking in the wrong place.

**The walk is version-bound and the repository is currently two versions.**
`chr/default.nix` pins **7.15.3** for the lab and `checks.chr-deploy`;
`regenerate-menus.sh` walks **7.25**, which is what the table's header claims.
Walking a version other than the one you deploy against is how a menu the fleet
uses disappears from the table — the failure lands downstream, as an unknown
attribute in someone else's build. Keep them in step, and when you bump one,
bump the other (this is a gap, listed in [Not done yet](roadmap.md)).

## Reading the probe's answer

`lists-$VERSION.json` separates what the device proved from what it merely
reported, and the generated file keeps that distinction in the comment above
each entry:

* **proven** — the device *took* a comma-separated value for the argument. The
  probe writes a garbage value first (taken ⇒ a free string, where a comma is
  content — `comment`, `note`, `password`), then a pair (taken ⇒ the comma
  separates values), then a triple (a fixed-arity syntax like `limit=10,5` is a
  count and a block-time, and refuses the third);
* **device type only** — the device reports the argument as `array`, but the
  menu already had objects and writing to a live object is not the probe's
  business. `/ip vrf interfaces` is one; `/user group policy` another.

An argument **absent** from `lists` was not proven to be a list. That is not
the same as proven scalar, and it is why the assertion is a shape check rather
than a type: a menu the probe could not answer stays writable the old way.

Two ways to promote a `device type only` entry to proven: give the probe a way
to make an object in that menu (`MINIMAL_ADD`, and `PRELUDE` when something else
has to exist first — a bridge for a bridge port, a WireGuard interface for a
peer), which the next run promotes by itself; or add the name to the overlay
entry's `lists`, which is a hand claim and should say so.

## Reviewing the diff

`git diff lib/menus.generated.nix` is the review. In this order:

1. **the menu count must not fall.** A shrinking walk is a lost subtree far more
   often than it is RouterOS removing a menu — that is why
   `scripts/walk-menus.py` treats a failed inspect as fatal instead of as "no
   children". A count that *rises* is new surface (or a version bump).
2. **new `lists` entries.** Read them one by one. A surprise is either a new
   multi-value argument or a false positive, and the two look identical in a
   diff. The known traps: a flag set reads back as `str`, and a fixed-arity
   comma syntax (`limit`, `connection-limit`, `nth`) takes a pair without being
   a list.
3. **attributes that vanished.** RouterOS renamed something. The overlay may now
   be wrong, and the fleet may still be writing it.
4. **`scripts/menu-coverage.sh <path to Infra/lunix>`** — renders the fleet's
   routers and reports an attribute the table has lost, *and* an argument the
   fleet still writes comma-joined. Exit 0 covered, 1 not covered, 2 could not
   be asked. Note what it cannot see: the fleet takes this class through
   `ccpkgs`, so its `--override-input nix-mikrotik` does not reach the library
   it renders with. The table comparison is still real — it reads the rendered
   script — but a pass is not a statement about this checkout.
5. **`nix build .#checks.x86_64-linux.menus`** at minimum, and the rest of
   `checks` before a release.

Commit the generated file on its own, with the version and build time from its
header in the message. A regeneration that also carries a hand-edit to the
overlay is two changes in one commit and cannot be reviewed.

## Adding one by hand

Only for what a virtual router cannot answer: a switch-chip menu, a menu whose
keys are names, the renderer's own `no_label`. In `lib/menus.overlay.nix`:

```nix
{
  path = "/interface ethernet switch egress-vlan-tag";
  kind = "list";
  mode = "add";                  # "add" | "union" | "replace"
  attrs = [ "tagged-ports" "vlan-id" ];
  lists = [ "tagged-ports" ];    # optional, same meaning as in the table
  why = ''
    Switch-chip menu. A CHR has no switch chip, so the walk never reaches it,
    and the fleet's CRS226 configuration uses it.
  '';
}
```

`mode` says what the entry knows that the generator does not: `add` a menu it
never saw, `union` names missing from what it found, `replace` names that are
wrong for this menu's typing (the name-keyed menus — `/ip service` — where the
router reports a service's properties as the `set` arguments). `lists` always
unions: an overlay can add a multi-value argument, never remove one the device
answered for.

When the device *can* be asked, ask it. A hand-written claim is one nothing
tests, and the next regeneration does not delete it — it sits there contradicting
the file beside it.

## Operating the lab

`nix run .#chr-lab -- start` gives the two-VM pair documented in
[Testing against a real RouterOS](testing-against-a-router.md); regeneration
boots its own single VM instead, so the two do not collide. The things that cost
time:

* **one ssh connection, not one per command.** A dozen sequential ssh sessions
  wedge qemu's user-mode networking (the hostfwd stops answering, `kex_exchange_identification:
  read: Connection reset by peer`) until the VM is restarted. ControlMaster
  reuses one socket at ~6 ms per command; `scripts/probe-menu-lists.py` does
  this.
* **`-F /dev/null` on every ssh to a lab device.** It has an empty admin
  password, and the operator's own `~/.ssh/config` is not part of the question —
  a home-managed config with the wrong permissions turns every call into a
  failure that looks like "the router is down".
* **a failed `/ip vrf add` still creates the VRF.** RouterOS reports
  `input does not match any value of interface` *and* creates it with
  `interfaces=all`, which moves every interface into it — the management address
  included. SSH and REST stop answering; the serial socket is the way back
  (`/ip vrf remove [find name=…]`).
* **the console is a serial socket**, `-serial unix:…,server=on,wait=off`. After
  login RouterOS probes the terminal with `ESC[6n` and waits for
  `ESC[row;colR`; a client that ignores it sits at a blank screen and every
  later command is typed into nothing.
* **a fresh CHR is licensed `free`**, which caps throughput at 1 Mbit/s. The
  patched images need `keygen` and then a reboot (`/system license print`
  reports the new licence immediately; the packet path keeps the cap until the
  restart). Nothing about the menu table needs throughput, so a lab that is only
  being walked can skip the licence.

## What each check covers

| check | the question |
|---|---|
| `checks.menus` | both spellings render byte-identically; every menu is reachable at its option path; a menu typo, an attribute typo and a comma-joined string are refused |
| `checks.render` | the renderer against two goldens, including upstream's own |
| `checks.eval` | the module class: options, assertions, the fleet form |
| `checks.cli` | `render`/`build`/`generate`/`deploy`, and the refusals |
| `checks.chr-smoke` | the pinned image still boots to a login prompt |
| `checks.chr-deploy` | a rendered script is applied to a CHR, and the device state read back |

None of them can answer "is the table current": that is
`scripts/menu-coverage.sh` against a fleet checkout, and it is the job the
`options` workflow runs on a schedule.