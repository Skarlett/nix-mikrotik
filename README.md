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

Upstream's example still renders, and `nix-build mikrotik.nix` still works. It is
not byte-identical any more, and the render check no longer pretends it is:
every `add`/`set` line comes out the same, in upstream's order, plus four
deliberate deviations (a generated header, `/system identity` first with a quoted
value, a final newline, and pinned section order). `tests/golden/legacy-upstream.rsc`
is upstream's own generator's output for that fixture, committed as it came out;
the check asserts the deviations by name and diffs everything else against it.
`tests/golden/README.md` lists them and says how to regenerate the file.

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
{ config, pkgs, ... }:
{
  imports = [ (import "${nix-mikrotik}/modules/hardening.nix") ];

  # The key the tunnel needs, as the generator that mints it. This is clan's own
  # generator interface, unchanged: a generator is a shell script plus the files
  # it declares, and each file says whether it is a secret.
  clan.core.vars.generators.wg-private-key = {
    files.privkey.secret = true;
    runtimeInputs = [ pkgs.wireguard-tools ];
    script = "wg genkey > $out/privkey";
  };

  mikrotik = {
    hostname = "router1";

    sections = {
      "/interface bridge" = [ { name = "bridge"; } ];
      "/ip address" = [
        { address = "10.10.10.1/24"; interface = "bridge"; }
      ];
      "/interface wireguard" = [
        {
          name = "wg0";
          private-key = config.clan.core.vars.generators.wg-private-key.files.privkey.placeholder;
        }
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
| `clan.core.vars.generators` | the values the configuration needs, as generators — clan's own interface, so a declaration moves between a clan machine and a router unchanged |
| `mikrotik.extraScript` | raw lines appended verbatim, for anything the data model cannot express |
| `mikrotik.checkMenuAttributes` | reject an attribute name a menu does not list (on) |

Assertions fail the *evaluation*, not a device: an empty hostname, a section
path that is not a RouterOS command path, a secret placeholder with no matching
generator file, or a `/system identity` section that would fight the option.

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
mikrotik.interface.wireguard.items = [
  { name = "wg0"; listen-port = 51820; private-key = config.clan.core.vars.generators.wg0.files.private-key.placeholder; }
];
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
option path *is* the RouterOS path). Twelve of the thirty-six menus need it;
the quoting is standard Nix and survives `nix fmt` untouched.

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
the way it is onto a NixOS host. It is **generated** on the deploying machine and
**delivered**:

1. the configuration declares a generator under `clan.core.vars.generators.<name>`
   — clan's own interface, not a spelling of it. A generator is a shell script
   plus the files it declares, and each file says whether it is a secret;
2. a menu cell takes `config.clan.core.vars.generators.<g>.files.<f>.placeholder`,
   which renders as `__MIKROTIK_SECRET_<g>/<f>__` — the value is never in the
   store, and the script is safe to build on any machine;
3. `nix-mikrotik generate <manifest>` runs the generators that script needs, once
   each, in dependency order, and keeps the values in a state directory laid out
   the way clan lays out its var store (`per-machine/<router>/<generator>/<file>`,
   or `shared/<generator>/<file>` for a `share = true` generator), because the
   manifest carries that `relDir` per file and the tool writes nowhere else. A
   file is written `0400`; a file declared `secret = false` is written `0444` and
   printed, because it is not a secret (a public key) and another machine has to
   read it;
4. `nix-mikrotik deploy` substitutes the real value into the script, quoting and
   escaping it the way RouterOS needs it, into a `0600` file under a `0700`
   temporary directory, uploads, imports, and **removes the uploaded copy from
   the router**, because that file holds the plaintext;
5. it refuses to deploy at all if any placeholder is unresolved — and it refuses
   a placeholder *name* whose parts are not usable as file names
   (`[A-Za-z0-9][A-Za-z0-9._-]*`, one `/` between generator and file), because
   that name is also the path the value is read from;
6. an unquoted base64 key — every WireGuard private key — makes the device end
   the command early, abort the whole script and still exit 0, which is why
   (4) quotes and escapes `"`, `\` and `$` rather than trusting the value;
7. a script the device did not finish running is a **failure, not a silent
   no-op**: `deploy` appends a one-line sentinel to the uploaded copy and reads
   the device's log back, so it cannot print `verified` for an import that
   stopped early. What stopped it is not recoverable — a parse abort applies
   nothing, a runtime abort has already applied a prefix — so the failure says
   exactly that rather than claiming the device is unchanged, and warns that a
   re-run can duplicate what the first attempt managed to apply.

```nix
clan.core.vars.generators.wg-chr1 = {
  files.private-key.secret = true;
  files.public-key.secret = false;        # published: the peers need it
  runtimeInputs = [ pkgs.wireguard-tools ];
  script = ''
    wg genkey | tee $out/private-key | wg pubkey > $out/public-key
  '';
};
```

The interface is clan's, with three deviations, each because the target is
RouterOS rather than a NixOS machine (`modules/base.nix` says so where the
options are declared):

* **no var store is read while evaluating.** `path`, `value` and `exists` throw
  with an explanation instead of resolving to a file: a router script is rendered
  on a machine that does not hold the values. Use `placeholder`.
* **`owner`, `group`, `neededFor` and `restartUnits` are accepted and ignored.**
  RouterOS has no users, no systemd and no activation step to restart.
* **`finalScript` is text, not a store path**, so a class can be evaluated
  without building anything.

Everything else is the real thing: `files`, `prompts` (a persisted prompt *is* a
file of the generator, so such a generator writes no script), `dependencies`
(`$in/<generator>/<file>`), `share`, `validation`, `runtimeInputs`. The
configuration asserts what it can: a generator with no files, a dependency on a
generator this router does not declare, a dependency cycle, and a placeholder no
declaration produces all fail the evaluation with a message that names the fix.

```sh
nix eval --impure --raw .#mikrotikConfigurations.r1.manifest \
  | jq . > manifest.json            # or: nix build .#...-generators

nix-mikrotik generate manifest.json --state-dir ./vars
nix-mikrotik deploy router.rsc --host 10.0.0.1 \
  --generators manifest.json --generator-state-dir ./vars \
  --verify --expect-hostname router1
```

The document is `{ generators, varFiles }`: generators to run, and hand-offs to
read from `--secrets-dir`. `generate` only looks at the first, `deploy` at both.

`--state-dir` is outside the repository on purpose: the values are the one thing
that must not be committed, and the layout is clan's so that the same directory
can be the one clan deploys into.

## Clan vars

The point of keeping the `clan.core.*` options is that this half needs no
adapter. A generator declared in a clan machine — in `Infra/lunix`,
`modules/vars/generators/mikrotik.nix` — files its values under
`vars/per-machine/<machine>/<generator>/<file>`, and a router declaring the same
generator reads exactly those files:

```sh
nix-mikrotik deploy router.rsc \
  --host 10.1.0.3 --user admin \
  --key /run/secrets/vars/per-machine/flagship/mikrotik-homelab-router/ssh-key \
  --secrets-dir /run/secrets/vars/per-machine/flagship/mikrotik-homelab-router \
  --verify --expect-hostname homelab
```

A name is therefore `<generator>/<file>`, and both parts are constrained to
`[A-Za-z0-9][A-Za-z0-9._-]*` — a dot-file name, a name with `..` is not a file
name in a directory and not a placeholder name either. The assertion is in
`modules/base.nix`, so it is a build failure rather than a placeholder the tool
silently skips or a path it reads from outside the state directory.

`--secrets-dir` reads only the files the script asks for, so the directory can
carry more than the script needs (the public half, for one). `tests/cli.nix`
exercises exactly this shape: a directory of files named after the placeholders.

A value this router does not mint is declared under `mikrotik.varFiles` instead
of `clan.core.vars.generators`. That is for a key another host already owns — a
WireGuard private key generated by the controller that owns the tunnel, for
instance. A `mkSecret` naming something neither option declares still fails the
evaluation, which is what keeps a typo from reaching a device as an empty cell.

An entry is clan's own description of a generated file, not a second scheme: a
generator, a file inside it, and the machine whose vars root holds it. clan files
a generator's files under `per-machine/<machine>/<generator>/<file>`, or
`shared/<generator>/<file>` for a generator with `share = true`, and `path` is
exactly that — relative to the vars directory `--secrets-dir` is pointed at. It
is derived, so a value clan generated is found without restating where clan put
it, and a generator that moves (a target renamed to a machine, `share` flipped
on) moves here too.

The attribute name is the placeholder a cell uses, and when it is written
`<generator>/<file>` the entry already says which generator files it — clan's
identity for the file inside a generator — so the common entry sets nothing but
`machine`.

```nix
mikrotik.varFiles."mikrotik-lab-peers/chr1" = {
  description = "chr1's key, generated on the controller";
  machine = "flagship";   # -> per-machine/flagship/mikrotik-lab-peers/chr1
};
mikrotik.sections."/interface wireguard" = [
  { name = "wg.mesh"; listen-port = 13231; private-key = mkSecret "mikrotik-lab-peers/chr1"; }
];
```

Both halves reach the tool in one document: `mikrotik-<name>-generators` is
`{ generators, varFiles }`, so `--generators` alone answers both "what can be
minted here" and "what has to be read from `--secrets-dir`". A value is minted
or read, never both. A `varFiles` path is clan's relative layout, and one that is
absolute, carries `..` or has an empty segment is refused where it is declared —
before it is joined onto `--secrets-dir` and before it can read outside it.

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
* `--known-hosts PATH` is the one thing the transport will not take from the
  operator's environment. `accept-new` learns a host key by appending it to
  ssh's known_hosts file, and that `~` comes from the passwd entry rather than
  `$HOME` — so a caller with no operator home (a systemd unit as root under
  `ProtectHome = true`) has nowhere to record one and every deploy is a first
  contact. Pass a path the caller *can* write (ccpkgs' `services.mikrotik` hands
  the unit a `StateDirectory`-backed file) and the pin is learned again. A path
  whose directory does not exist is refused: ssh treats a failed append as a
  warning, so the alternative is a deploy that looks pinned and is not. Only the
  file is selectable — `accept-new` still means accept-new, and a key pinned
  machine-wide in `/etc/ssh/ssh_known_hosts` is still read.
* `deploy --reset` **without** `--yes` is refused before anything happens:
  before the transport, and before a secret value is read. It used to be refused
  after the secretized script had already been uploaded, which made the
  confirmation not the guard it reads as.
* `deploy` **imports** by default, which merges into the running
  configuration. RouterOS has no reconciliation — a repeated `add` makes a
  second object — so importing the same script twice is not idempotent.
* an import that did not run to the end is a failure, not a silent no-op:
  RouterOS logs a parse error and still exits 0, so `deploy` appends a sentinel
  line to the uploaded copy and reads the device's log back before it reports
  success. When the sentinel never appears it exits 2 and says **a prefix of the
  script may have been applied** — the tool cannot tell a parse abort (nothing
  applied) from a runtime one (everything above the failing line applied).
  Check the device (`nix-mikrotik diff`) before re-deploying: a repeated `add`
  makes a second object.
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

`checks.chr-deploy` goes further: it boots that image, applies a rendered
configuration to the device, and reads the device's state back. It is the only
check that can answer whether RouterOS *accepts* what the renderer produced —
`/import` exits 0 for a script the device refused to parse, so nothing about the
build itself can. What it asserts, all read over REST afterwards:

* the identity, a bridge with an address on it, and a dhcp-server drawing from a
  pool created earlier in the same script (section order is real);
* a firewall comment carrying `$`, and a *secret* substituted into a dns
  comment, both read back byte for byte;
* the interface whose line carries the substituted WireGuard key — it exists at
  all only if the whole script ran, because unquoted that base64 `=` padding
  makes the device refuse the script from its first line;
* the uploaded copy is gone from the device afterwards;
* and, the other way round, that a deliberately broken script **fails** the
  deploy, with the device's own `script error: expected end of command` in the
  log and nothing applied. A check whose subject always applies cannot be shown
  to fail, so the refusal is part of the check rather than a claim about it.

`tests/chr-deploy.py` is the whole of it and needs nothing from nix, so it also
runs against a CHR from the lab above — which is how its assertions were written:

```sh
nix run .#chr-lab -- start
script=$(nix build --no-link --print-out-paths .#mikrotik-chr-fixture-script)
cli=$(nix build --no-link --print-out-paths .#nix-mikrotik)
tests/chr-deploy.py --host 127.0.0.1 --ssh-port 2201 --rest-port 8081 \
  --script "$script/router-config.rsc" --expect-hostname chr-deploy \
  --secret 'wg-private-key=QUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUE=' \
  --secret 'dns-comment=a"b\c$d' \
  --broken-script tests/fixtures/refused.rsc --cli "$cli/bin/nix-mikrotik"
```

It bootstraps its own ssh access rather than needing a console: it serves a
fresh public key to the guest at `http://10.0.2.2:<port>/` and has the device
import it over REST (`POST /tool/fetch`, then `POST /user/ssh-keys/import`),
then removes it again. The `--secret` values are obviously fake, and the fixture
is the only configuration here that a CHR can actually hold — the examples name
`ether2` … `sfp1` (see "Not done yet").

Two lab notes this leaves behind: a CHR rebuilt at a host:port you have already
deployed to comes back with a **new ssh host key**, and the deploy tool's
`accept-new` then refuses it (OpenSSH reads `known_hosts` from the password
database, not from `$HOME`, so nothing redirects it) — clear it with
`ssh-keygen -R '[127.0.0.1]:2201'`, or use a port you have not deployed to.
Inside the nixos test that cannot arise. And RouterOS logs `script,error
executing script from sshd failed` for *any* command a client runs over ssh that
exits non-zero — including the deploy's own `/file remove`, which is retried
because it races the import — so that line is not evidence about a script; the
device's `script error: …` line is.

## Layout

```
lib/            evalMikrotik, generators, mkRouterScript, the renderer, the menu
                table (menus.nix) and the value types (types.nix)
modules/        base.nix (the class), menus.nix (the typed menu options),
                hardening.nix (composable defaults)
pkgs/           the nix-mikrotik CLI
chr/            pinned CHR images and the two-VM lab
examples/       module-configuration.nix and its typed twin, plus upstream's
                untouched example
tests/          render (two goldens), menus (typed vs sections), cli, eval,
                chr-smoke, chr-deploy
                (+ fixtures/: the configuration a CHR is given, and a script it
                must refuse)
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
* **the examples on a CHR**: both describe a router with `ether2` … `ether5` and
  `sfp1`, and a CHR has one ethernet port, so an `/ip address … interface=ether2`
  line is refused at runtime (`script error: input does not match any value of
  interface`, measured on 7.15.3 — with the identity, both bridges and the vlan
  above it already applied). They are upstream's router, ported, and stay as
  they are; `checks.chr-deploy` applies `tests/fixtures/chr-configuration.nix`,
  which is written for a CHR.
* **the deploy tool's ssh trust**: `deploy`/`diff` accept `--host`, `--port` and
  `--key`, but not a known-hosts file, so a rebuilt lab device is refused at the
  same `host:port` until the stale key is removed by hand (`ssh-keygen -R`).
