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
| `mikrotik.sectionOrder` | sections to render first, for objects that must exist before they are referenced |
| `mikrotik.secrets` | secrets the configuration references, by name |
| `mikrotik.extraScript` | raw lines appended verbatim, for anything the data model cannot express |

Assertions fail the *evaluation*, not a device: an empty hostname, a section
path that is not a RouterOS command path, a `mkSecret` with no matching
declaration, or a `/system identity` section that would fight the option.

Booleans render as `yes`/`no` and integers bare, so a configuration reads like
Nix rather than like a stringly-typed script.

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

## Layout

```
lib/            evalMikrotik, mkSecret, mkRouterScript, the renderer
modules/        base.nix (the class), hardening.nix (composable defaults)
pkgs/           the nix-mikrotik CLI
chr/            pinned CHR images and the two-VM lab
examples/       module-configuration.nix, plus upstream's untouched example
tests/          render (golden), cli, chr-smoke
```

## Differences from upstream

* the configuration is a module, not a bare attribute set — and the bare
  attribute set still works (`mikrotik.nix`, `examples/legacy-wrapper.nix`);
* `/system identity` is an option, so the deploy tool can verify a device;
* secrets are references, not strings;
* booleans and integers are typed rather than written as `"yes"`/`"no"`;
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
