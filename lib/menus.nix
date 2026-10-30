# The RouterOS menus this fork knows, and what a body may say.
#
# Two layers, because neither alone is right:
#
#   lib/menus.generated.nix  every menu and argument list a RouterOS 7.25 CHR
#                            reports about itself -- 347 menus, read off the
#                            router with `/console/inspect`. Generated; do not
#                            edit, run `scripts/regenerate-menus.sh`.
#
#   lib/menus.overlay.nix    the few things a *virtual* router cannot report:
#                            switch-chip menus (a CHR has no chip), the
#                            renderer's own `no_label`, and menus whose keys are
#                            names rather than arguments. Each entry says why.
#
# This file merges the two, and is the only thing `modules/menus.nix` imports.
# The entry shape is unchanged:
#
#   path   the RouterOS command path, as `/export` spells it. The option lives
#          at the same path with `/` dropped and spaces turned into `.`:
#          `/ip dhcp-server network` is `mikrotik.ip."dhcp-server".network`.
#   kind   "list"   -- a menu of objects: renders as repeated `add …` lines.
#          "object" -- a menu of settings: renders as one `set …` per key.
#   attrs  the names the body may use, checked at evaluation time; or null for
#          "no check". The check is what turns a typo from a `script error` on a
#          live router into a Nix evaluation error.
#
# The generated list is the router's own answer rather than a guess assembled
# from three documents, so it is wider than the hand-written table it replaces
# and the typo check now rejects less. It is not narrower in the direction that
# matters: the overlay restores what the walk could not reach, and
# `checks.menus` proves nothing was lost.
#
# Two conventions this table cannot express, on purpose:
#
#   * `/system identity` is absent. The identity is `mikrotik.hostname`, so that
#     the deploy tool can read it back off the device; `mikrotik.sections`
#     refuses the section for the same reason.
#   * Menus not in this table are still expressible through
#     `mikrotik.sections."/the menu"` and `mikrotik.extraScript`, which is the
#     escape hatch, not a fallback to be ashamed of.
let
  generated = import ./menus.generated.nix;
  overlay = import ./menus.overlay.nix;

  sortStrings = builtins.sort (a: b: a < b);

  # One overlay entry. `mode` is what the overlay knows that the generator does
  # not:
  #   add     the menu is missing from the generated table entirely
  #   union   these names are missing from what the generator found
  #   replace the generated names are wrong for this menu's typing
  apply =
    acc: o:
    let
      existing = acc.${o.path} or null;
      merged =
        if existing == null then
          {
            inherit (o) path kind attrs;
          }
        else
          existing
          // {
            kind = o.kind;
            attrs =
              if o.mode == "replace" then
                sortStrings o.attrs
              else if existing.attrs == null then
                null
              else
                sortStrings (existing.attrs ++ o.attrs);
          };
    in
    acc // { ${o.path} = merged; };
in
builtins.attrValues (
  builtins.foldl' apply (builtins.listToAttrs (map (m: {
    name = m.path;
    value = m;
  }) generated)) overlay
)