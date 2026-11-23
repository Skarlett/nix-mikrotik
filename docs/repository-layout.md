# Layout

What lives where, and which check covers what.

```
lib/            evalMikrotik, generators, mkRouterScript, the renderer, the menu
                table (menus.nix) and the value types (types.nix)
modules/        base.nix (the class), menus.nix (the typed menu options),
                hardening.nix (composable defaults)
pkgs/           the nix-mikrotik CLI
rsc/            the `.rsc` parser, differ and patch generator (Rust, no
                dependencies; `cargo test` or `nix build .#rsc`)
chr/            pinned CHR images and the two-VM lab
scripts/        the generator (walk-menus, probe-menu-lists, gen-menus,
                regenerate-menus), menu-coverage, compare-rsc
docs/           this page, the menu table's maintenance, and the rest of the map
                (README.md indexes it)
examples/       module-configuration.nix and its typed twin, plus upstream's
                untouched example
tests/          render (two goldens), menus (typed vs sections), cli, eval,
                chr-smoke, chr-deploy
                (+ fixtures/: the configuration a CHR is given, and a script it
                must refuse)
```
