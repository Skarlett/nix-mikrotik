# The value types shared by `mikrotik.sections` and the typed menu options.
#
# Both spellings end up as the same value: the typed layer compiles to a
# `sections` entry before the renderer is ever called. Keeping the types in one
# file is what makes that true by construction rather than by agreement -- a
# menu body and a section body are built from the same component types, so the
# renderer cannot tell which spelling produced the value it is handed.
{ lib }:
let
  inherit (lib) isAttrs isBool isInt isString types;

  # What RouterOS accepts as one `key=value`: a string, an integer, a boolean, a
  # secret marker (an attrset that renders as a placeholder rather than a
  # value), or a nested attrset, which renders as an argument group -- the
  # `no_label` spelling upstream uses for a `set` line with several arguments.
  #
  # The check is a courtesy, not a source of truth: `lib/render.nix` still
  # decides what it can print, and anything that slips through fails there with
  # the message about an unsupported scalar.
  isCell = v:
    isString v || isBool v || isInt v
    || (isAttrs v && (v ? __mikrotikSecret || lib.all isCell (lib.attrValues v)));

  cell = types.addCheck types.anything isCell // {
    description = "RouterOS value (string, integer, boolean, secret or argument group)";
  };
in
rec {
  inherit isCell cell;

  # A list menu (`add …` lines): repeated attribute sets.
  menuItems = types.listOf cell;

  # A `set …` menu: one line per key, whose value is a scalar, a secret or an
  # argument group. `/ip service` and `/tool mac-server` are this shape too --
  # there the key is the object being set, not an attribute of the menu.
  menuObject = types.attrsOf cell;

  # Upstream's section body, unchanged: an attrset renders as `set …` lines, a
  # list of attrsets as repeated `add …` lines. `mikrotik.sections` is still
  # typed by exactly this, which is why a configuration written that way keeps
  # evaluating the way it always did.
  sectionBody = types.oneOf [ (types.attrsOf types.anything) (types.listOf (types.attrsOf types.anything)) ];
}