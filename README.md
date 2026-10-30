# nix-mikrotik

Manage MikroTik RouterOS routers from Nix: describe the router as a module,
build a `.rsc` script from it, and deploy that script to the device.

This is a fork of [Plommonsorbet/nix-mikrotik](https://github.com/Plommonsorbet/nix-mikrotik)
(the copy we started from is `Skarlett-mirrors/nix-mikrotik`). Upstream is a
single-file generator: a Nix attribute set in, a RouterOS script out. That idea
is kept and everything around it is built out:

| | |
|---|---|
| **module class** | configurations are modules of class `mikrotik`, with typed options, composition and assertions |
| **build tool** | `nix build` produces the `.rsc` as a store path; `nix-mikrotik render` copies it out |
| **secrets** | a secret is a reference that renders to a placeholder; the value is delivered at deploy time |
| **deploy tool** | `nix-mikrotik deploy` uploads, imports, verifies and cleans up |
| **a real RouterOS to test against** | pinned CHR images, and a two-VM lab, so a script is proven before it reaches a router |

Upstream's example still renders byte-for-byte (`tests/golden/legacy.rsc`), and
`nix-build mikrotik.nix` still works.

## Quick start

```sh
# render a configuration through the flake
nix eval --raw .#mikrotikConfigurations.example.script

# or as a store path
nix build .#packages.x86_64-linux.mikrotik-example-script
cat result/router-config.rsc

# or with the tool, which copies the script out of the store
nix run .#nix-mikrotik -- render --name example -o router.rsc
```

A configuration is a module:

```nix
{ mkSecret, ... }:
{
  imports = [ (import "${nix-mikrotik}/modules/hardening.nix") ];

  mikrotik = {
    hostname = "router1";

    secrets.wg-private-key.file = "wg-private-key";

    sections = {
      "/interface bridge" = [ { name = "bridge"; } ];
      "/ip address" = [
        { address = "10.10.10.1/24"; interface = "bridge"; }
      ];
      "/interface wireguard" = [
        { name = "wg0"; private-key = mkSecret "wg-private-key"; }
      ];
    };
  };
}
```

## The module class

`_class = "mikrotik"` modules are evaluated by `lib.evalMikrotik`, which is
`lib.evalModules` with `class = "mikrotik"` plus the base module. That means
normal module semantics: `imports` composes, options have types and defaults,
and a section defined in two modules merges rather than colliding.

| option | |
|---|---|
| `mikrotik.hostname` | `/system identity`; rendered first, and read back by the deploy tool |
| `mikrotik.sections` | RouterOS menus keyed by command path — upstream's data model, unchanged |
| `mikrotik.<menu>` | the same menus as options, one per menu, e.g. `mikrotik.ip."dhcp-server".network` (see below) |
| `mikrotik.sectionOrder` | sections to render first, for objects that must exist before they are referenced |
| `mikrotik.secrets` | secrets the configuration references, by name |
| `mikrotik.extraScript` | raw lines appended verbatim, for anything the data model cannot express |
| `mikrotik.checkMenuAttributes` | reject an attribute name a menu does not list (on) |

Assertions fail the *evaluation*, not a device: an empty hostname, a section
path that is not a RouterOS command path, a `mkSecret` with no matching
declaration, or a `/system identity` section that would fight the option.

Booleans render as `yes`/`no` and integers bare, so a configuration reads like
Nix rather than like a stringly-typed script.

## The menu options

Every menu in `lib/menus.nix` is also an option, at the path `/export` gives it
with the slashes dropped and the spaces turned into dots:

```nix
mikrotik.ip."dhcp-server".network = [
  { address = "172.29.82.0/24"; gateway = "172.29.82.1"; dns-server = "1.1.1.1,8.8.8.8"; }
];
```

rather than

```nix
mikrotik.sections."/ip dhcp-server network" = [
  { address = "172.29.82.0/24"; gateway = "172.29.82.1"; dns-server = "1.1.1.1,8.8.8.8"; }
];
```

The two are the same value: the typed layer is a front end that compiles into
`mikrotik.sections`, so the renderer never learns which spelling produced a
script. `checks.menus` renders `examples/module-configuration.nix` and
`examples/typed-module-configuration.nix` and requires the bytes to match, and
the fleet's homelab router, transliterated into the typed options, renders the
same 62-statement script (same `sha256`) as the module it ships today.

What the spelling buys:

* **a menu typo is an evaluation error**, not a `script error` on a live router
  at import time — `mikrotik.ip."dhcp-servr"` does not exist, and the module
  system says so and suggests `dhcp-server`;
* **an attribute typo is an evaluation error too**, because each menu lists the
  attribute names it knows (also from `lib/menus.nix`). Misspell `address` and
  evaluation stops with the menu, the name and the alternatives;
* the menu path is an attribute path, so it is discoverable — `nix repl`, an
  editor's completion and `nixos-option`-style inspection all work on it.

### Menus with submenus: `items`

`/interface wireguard` is a list of interfaces and `/interface wireguard peers`
is a list of peers, so `interface.wireguard` would have to be both a list and an
attrset of children. A menu that has submenus carries its own body under
`items`; every other menu is written directly:

```nix
mikrotik.interface.wireguard.items = [ { name = "wg0"; listen-port = 51820; private-key = mkSecret "wg0"; } ];
mikrotik.interface.wireguard.peers = [ { interface = "wg0"; name = "peer1"; public-key = "…"; } ];

mikrotik.ip.address = [ { address = "10.0.0.3/24"; interface = "vlan10"; network = "10.0.0.0"; } ];
```

`items` is one rule for every such menu (`/interface bridge` +
`/interface bridge port`, `/ip dhcp-server` + `/ip dhcp-server network`,
`/interface list` + `/interface list member`, `/ip dns` + `/ip dns static`,
`/tool mac-server` + its two children), rather than a per-menu name to remember.
The alternative — always writing a wrapper, so the collision case is uniform —
was rejected: it taxes every menu for the shape of five.

### Dashes in menu names

`dhcp-server` is not a Nix identifier, so the attribute path needs a quoting
step: `mikrotik.ip."dhcp-server".network`. That is accepted as the ergonomics
rather than papered over with a mapping table (a table would need a name per
menu, two spellings to keep in step, and would break the property that the
option path *is* the RouterOS path). Eleven of the menus need it; the quoting
is standard Nix and survives `nix fmt` untouched.

### Mixing the two, and the order of `add` lines

A path written both ways merges, exactly as two `sections` definitions always
have — so a menu can move over one at a time, and a module still written against
`sections` (this repository's `hardening.nix`, the fleet's fabric) keeps
composing with one written against the menu options. Definitions merge in
reverse module order and the menus module is part of the class, so a typed menu's
lines come **after** the `sections` lines for the same path; `checks.menus`
pins that order rather than leaving it to be discovered.

`mikrotik.sectionOrder` keeps taking section paths (`"/ip dhcp-server"`): a menu
path is the same string with `.` for ` ` and a leading `/`.

Anything `lib/menus.nix` does not list is still expressible through
`mikrotik.sections` and `mikrotik.extraScript`. The table is not a RouterOS
schema (RouterOS ships none); it is what the fleet, the examples and the CRS226's
own `/export` use, and adding a menu or an attribute is one line in that file.

## Secrets

RouterOS cannot run sops-nix, so a secret cannot be *activated* onto a router
the way it is onto a NixOS host. It is **delivered** instead:

1. the configuration refers to a secret with `mkSecret "name"`;
2. the build renders `__MIKROTIK_SECRET_name__` — the value is never in the
   store, and the script is safe to build on any machine;
3. `nix-mikrotik deploy` substitutes the real value from a file **on the
   deploying machine** (a clan var, a sops file, anything that is a path),
   into a `0600` file under a `0700` temporary directory;
4. it uploads, imports, and **removes the uploaded copy from the router**,
   because that file holds the plaintext secret;
5. it refuses to deploy at all if any placeholder is unresolved.

```sh
nix-mikrotik deploy router.rsc --host 10.0.0.1 \
  --secret wg-private-key=/run/secrets/vars/shared/mikrotik/wg-private-key \
  --verify --expect-hostname router1
```

The value exists in three places, briefly: the deploying machine's secret
store, a temporary file on it, and the router's flash between upload and
removal. That last one is unavoidable — `/import` takes a file, not stdin — and
is why the file is removed in a `finally` block rather than at the end of the
happy path.

## Clan vars (how the fleet supplies these secrets)

This repository does not declare the generators — a clan vars generator belongs
to the machine that holds the value, so the fleet's lives in `Infra/lunix`,
`modules/vars/generators/mikrotik.nix` ([lunix #131](https://codex.unallocatedspace.luni/Infra/lunix/pulls/131)).
What makes the two halves fit is one convention:

> **the generator's file names are the `mkSecret` names.**

So the directory clan deploys the vars into *is* a secrets directory, and the
deploy is one command with no mapping layer:

```sh
# flagship holds the generator; clan deploys its files to
# /run/secrets/vars/per-machine/<machine>/<generator>/<file>
nix-mikrotik deploy router.rsc \
  --host 10.1.0.3 --user admin \
  --key /run/secrets/vars/per-machine/flagship/mikrotik-homelab-router/ssh-key \
  --secrets-dir /run/secrets/vars/per-machine/flagship/mikrotik-homelab-router \
  --verify --expect-hostname homelab
```

The generator there declares exactly `wg-chr1-luninet`, `wg-chr1-main`,
`wg-chr1-mgmt` (prompted, persisted — the router is in service and minting new
keys would break three tunnels), plus a generated `ssh-key`/`ssh-key.pub` pair
for the deployer. Three of those match `private-key = mkSecret "wg-chr1-…"` in
`modules/mikrotik/routers/homelab-router.nix`, which is the whole contract.

`--secrets-dir` reads only the files the script asks for, so the directory can
carry more than the script needs (the public half, for one). `tests/cli.nix`
exercises exactly this shape: a directory of files named after the
placeholders.

Where it stops: RouterOS cannot run sops-nix, so a var is **delivered**, not
activated. Nothing in the fleet's `sops.secrets` reaches the router; the value
travels from the deployed var, through a temporary file, to the device, and the
uploaded copy is deleted. `services.mikrotik` (ccpkgs) is the wrapper that
automates the invocation above as a oneshot unit once it is on the fleet's
`ccpkgs` pin.

## Deploying

```sh
nix-mikrotik list-secrets router.rsc      # what this script still needs
nix-mikrotik secretize router.rsc -o out.rsc --secrets-dir ./secrets
nix-mikrotik deploy router.rsc --host 10.0.0.1 --verify
nix-mikrotik diff router.rsc --host 10.0.0.1
```

* Transport is the system `ssh`/`scp`: key-based auth against the router's
  `admin` user, no library, no password handling of our own.
* `deploy` **imports** by default, which merges into the running
  configuration. RouterOS has no reconciliation — a repeated `add` makes a
  second object — so importing the same script twice is not idempotent.
* `deploy --reset --yes` runs `/system reset-configuration
  no-defaults=yes run-after-reset=…` instead: the device reboots into exactly
  the script. That is the declarative path, and it wipes the configuration.
* `diff` exports the live configuration and diffs it textually against the
  script. It is a review aid, not a plan: it cannot see that two differently
  written rules mean the same thing.

## Testing against a real RouterOS

`chr/` pins the patched CHR images from
[elseif/MikroTikPatch](https://github.com/elseif/MikroTikPatch) and provides a
two-VM lab:

```sh
nix run .#chr-lab -- start     # two CHRs, wired to each other
nix run .#chr-lab -- status    # pids and management ports
nix run .#chr-lab -- stop
```

`chr-a` is reachable at `127.0.0.1:2201` (ssh) and `127.0.0.1:8081` (REST),
`chr-b` at `2202`/`8082`. Their link is QEMU's tcp socket backend, not a tap:
no root, and ~1.5-2 Gbit/s between the two, where UDP (`dgram`) collapses to
~50-130 Mbit/s.

Two things about CHR that cost time if you do not know them:

* a fresh CHR is licensed `free`, which caps throughput at **1 Mbit/s**;
* the patched images need `keygen` (in the `option` package) run on the device,
  **and then a reboot** — `/system license print` reports the new licence
  immediately, but the packet path keeps the old cap until the device restarts.

`checks.chr-smoke` boots the pinned image and waits for the RouterOS login
prompt, so a broken image pin fails the build rather than a lab session.

`checks.menus` is the one that guards the two spellings: it renders one
configuration written both ways, a typed/section hybrid (to pin the merge order),
and every menu in the table, and requires the typed render to be byte-identical
to the section render.

## Layout

```
lib/            evalMikrotik, mkSecret, mkRouterScript, the renderer, the menu
                table (menus.nix) and the value types (types.nix)
modules/        base.nix (the class), menus.nix (the typed menu options),
                hardening.nix (composable defaults)
pkgs/           the nix-mikrotik CLI
chr/            pinned CHR images and the two-VM lab
examples/       module-configuration.nix and its typed twin, plus upstream's
                untouched example
tests/          render (golden), menus (typed vs sections), cli, chr-smoke
```

## Differences from upstream

* the configuration is a module, not a bare attribute set — and the bare
  attribute set still works (`mikrotik.nix`, `examples/legacy-wrapper.nix`);
* `/system identity` is an option, so the deploy tool can verify a device;
* secrets are references, not strings;
* booleans and integers are typed rather than written as `"yes"`/`"no"`;
* every menu is a typed option as well as a `sections` key
  (`mikrotik.ip."dhcp-server".network`), with the attribute names it knows, so a
  misspelt menu or attribute fails evaluation instead of a router import;
* section order can be pinned;
* upstream's example puts two `action=`/`chain=` entries under
  `/ip firewall address-list`, where RouterOS will reject them;
  `examples/module-configuration.nix` has them under `/ip firewall filter`
  where they belong. The golden test keeps upstream's version as-is.

## Not done yet

* **a real diff/reconcile**: upstream's stated goal of a structural diff needs
  a parser for `.rsc`, which does not exist here. `diff` is textual.
* **idempotent import**: without reconciliation, `--reset` is the only
  convergent mode, and it is destructive.
* **`/export`-based import of existing routers**: the migration path is still
  "read the export, write the module by hand".
