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
| **deploy tool** | `nix-mikrotik deploy` diffs the device against the script, imports the difference, verifies and cleans up |
| **a real RouterOS to test against** | pinned CHR images, and a two-VM lab, so a script is proven before it reaches a router |

Upstream's example still renders, and `nix-build mikrotik.nix` still works. It is
not byte-identical any more: a generated header, `/system identity` rendered first
with a quoted value, a final newline and a pinned section order are deliberate, and
[Upstream differences](docs/upstream-differences.md) names them and the rest.

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

A configuration is a module, and every RouterOS menu is an option path: the
menu's own path with the slashes dropped and the spaces turned into dots, so
`/interface wireguard` is written `mikrotik.interface.wireguard`. A typo in a
menu name or in an argument is then an evaluation error rather than a
`script error` on the device.

The shortest useful module declares the key its WireGuard interface needs as the
generator that mints it, and references the placeholder in the menu body:

```nix
{ config, pkgs, ... }:
{
  clan.core.vars.generators.wg-private-key = {
    files.privkey.secret = true;
    runtimeInputs = [ pkgs.wireguard-tools ];
    script = "wg genkey > $out/privkey";
  };

  mikrotik = {
    hostname = "router1";

    # `/interface wireguard` has `/interface wireguard peers` under it, so the
    # interfaces themselves are the menu's `items`.
    interface.wireguard.items = [
      {
        name = "wg0";
        private-key = config.clan.core.vars.generators.wg-private-key.files.privkey.placeholder;
      }
    ];
  };
}
```

A menu, or an argument inside one, that the table does not cover is still
written the raw way — `mikrotik.sections."/the menu" = [ … ]`, keyed by the
RouterOS command path. The typed options compile to exactly that, so the two
spellings mix in one configuration and render the same script.

[Quick start](docs/quick-start.md) takes that configuration through render, build
and deploy.

## Documentation

| page | what it covers |
|---|---|
| [Quick start](docs/quick-start.md) | a configuration end to end: render, build, run the tool |
| [The module class](docs/module-class.md) | `evalMikrotik`, the options, what fails evaluation |
| [The menu options](docs/menu-options.md) | typed menus, `items`, quoting, mixing with `sections` |
| [Maintaining the menu table](docs/maintaining-the-menu-table.md) | regenerating it from a CHR, reading the probe, the overlay |
| [Secrets](docs/secrets.md) | generators, placeholders, what `generate` and `deploy` do with them |
| [Clan vars](docs/clan-vars.md) | reading a clan machine's var store, and where the parity stops |
| [Deploying](docs/deploying.md) | `deploy`, `diff`, `secretize`, transport, and the refusals |
| [Testing against a real RouterOS](docs/testing-against-a-router.md) | the CHR lab, and the checks that use it |
| [Repository layout](docs/repository-layout.md) | what lives where, and which check covers what |
| [The `.rsc` parser](docs/rsc-parser.md) | `rsc`: parse, diff and patch two configurations, and what a patch cannot say |
| [Upstream differences](docs/upstream-differences.md) | what changed from Plommonsorbet's generator |
| [Not done yet](docs/roadmap.md) | the deliberate gaps, and what would close each |
| [Wiring into clan's service model](docs/clan-mikrotik-module.md) | the per-instance module design, and what it needs |

## Status

The class, the CLI and the CHR checks are in use: the fleet's homelab router is
described this way, and a rendered script is applied to a real RouterOS by
`checks.chr-deploy` before it reaches a device. `deploy` applies the *difference*
between the device's `/export` and the script — computed by `rsc/`, which parses
`.rsc`, diffs two of them and emits a patch verified against a CHR ([the `.rsc`
parser](docs/rsc-parser.md)) — so a second deploy converges instead of
duplicating objects. Deletions are withheld unless `--prune` asks for them: the
ownership predicate that would make them safe in general is still missing. The
rest of what is missing is deliberate and listed in
[Not done yet](docs/roadmap.md).
