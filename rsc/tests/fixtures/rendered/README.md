# Rendered configurations

Verbatim copies of what this repository's own renderer produces, so the differ
is tested against the configurations it will actually be given rather than only
against fixtures written for it.

| file | source |
|---|---|
| `example.rsc` | `nix build .#mikrotik-example-script` — `examples/module-configuration.nix` |
| `typed.rsc` | `nix build .#mikrotik-typed-script` — its typed twin; byte-identical to `example.rsc`, which `checks.menus` asserts and `tests/dogfood.rs` re-checks through the differ |
| `legacy.rsc` | `nix build .#mikrotik-legacy-script` — upstream's configuration wrapped, not rewritten |
| `chr-fixture.rsc` | `nix build .#mikrotik-chr-fixture-script` — the configuration `checks.chr-deploy` applies to a CHR |
| `routers-example.rsc` | `nix build .#mikrotik-example` — `examples/routers/example`, the `routers/` convention |
| `routers-legacy.rsc` | `nix build .#mikrotik-legacy` — `examples/routers/legacy` |

`../export-7.15.3.rsc` is in the same corpus from the other side: the real
`/export` of a CHR 7.15.3, which is the file a converge would be handed as
"where the router is now".

Regenerate after a renderer change:

```sh
for p in mikrotik-example-script:example mikrotik-typed-script:typed \
         mikrotik-legacy-script:legacy mikrotik-chr-fixture-script:chr-fixture \
         mikrotik-example:routers-example mikrotik-legacy:routers-legacy; do
  pkg=${p%%:*}; name=${p##*:}
  cp "$(nix build .#$pkg --no-link --print-out-paths)/router-config.rsc" "$name.rsc"
done
```

`tests/dogfood.rs` runs every ordered pair of these files through the whole
pipeline — parse, diff, render, apply, compare — and requires that a diff which
claims to be exact reaches its target, with a mismatch allowed only in a section
that reported it cannot be converged. That is what found the two positional bugs
this corpus exists to catch: an index compared across two files, and removals
applied in ascending order.
