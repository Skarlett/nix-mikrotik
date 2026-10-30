# The typed menu surface: `mikrotik.ip."dhcp-server".network = [ … ]` rather than
# `mikrotik.sections."/ip dhcp-server network" = [ … ]`.
#
# This module is a front end and nothing else. It declares one option per menu
# in `lib/menus.nix` and compiles what was set into `mikrotik.sections` -- the
# same attrset `lib/render.nix` has always rendered, with the same keys and the
# same values. The renderer does not know this module exists, which is the whole
# argument for render parity: the two spellings agree on the value handed to
# RouterOS syntax before any RouterOS syntax is involved.
#
# It also means the typed layer inherits everything `sections` already does:
# `sectionOrder` orders it, `mkSecret` works in it, the secret-completeness
# assertion sees it, and a module may extend a menu another module started.
#
# The one rule worth knowing: a menu that has submenus carries its own body
# under `items`.
#
#   /interface wireguard             is a list of interfaces
#   /interface wireguard peers       is a list of peers
#
# so `interface.wireguard` cannot be both a list and an attrset of children:
#
#   mikrotik.interface.wireguard.items = [ { name = "wg0"; … } ];
#   mikrotik.interface.wireguard.peers = [ { interface = "wg0"; … } ];
#
# Every other menu is written directly (`mikrotik.ip.address = [ … ]`), because
# making the common case carry a wrapper to make the collision case uniform is
# the wrong trade. `items` is chosen over a per-menu name like `interfaces`
# because there is one rule to remember instead of one per colliding menu.
{ config, lib, ... }:
let
  inherit (lib)
    concatStringsSep filter filterAttrs foldl' getAttrFromPath hasPrefix
    listToAttrs map mkOption nameValuePair optional optionalString recursiveUpdate
    setAttrByPath splitString subtractLists;

  typeLib = import ../lib/types.nix { inherit lib; };
  menus = import ../lib/menus.nix;

  # `/ip dhcp-server network` -> [ "ip" "dhcp-server" "network" ]. The segment
  # keeps RouterOS' spelling, dashes and all: it is the option *name*, so it
  # only needs quoting in Nix source (`ip."dhcp-server"`), never rewriting.
  segments = m: splitString " " (lib.removePrefix "/" m.path);

  # A menu has children when another menu's path extends it by a whole segment.
  hasChildren = m:
    lib.any (o: o.path != m.path && hasPrefix "${m.path} " o.path) menus;

  # Where the user writes this menu's body: at the menu's own attribute path,
  # plus `items` when the menu has submenus.
  #
  # This is not a stylistic choice. A submenu needs `mikrotik.interface.6to4` to
  # be an attribute *set of options*, so the parent cannot also be a single
  # option at that path -- and that is true whether the parent's body is a list
  # or a `set` body. `/interface` is the case that proves it: it is a real
  # `set`-able menu (`/interface set mtu=…` applies to every port) *and* the
  # parent of 96 menus, so without `items` the option tree and the body collide
  # and nothing evaluates.
  #
  # The cost is real -- a full generated table gives nine menus a submenu nobody
  # writes and therefore an `items` wrapper -- and it is paid once, in the
  # configurations that write those menus, rather than by making the option tree
  # depend on where the collision happens to be.
  needsItems = hasChildren;

  accessPath = m: segments m ++ optional (needsItems m) "items";

  bodyType = m: if m.kind == "list" then typeLib.menuItems else typeLib.menuObject;

  emptyBody = m: if m.kind == "list" then [ ] else { };

  renderVerb = m: if m.kind == "list" then "repeated `add …` lines" else "`set …` lines";

  menuOption = m: mkOption {
    type = bodyType m;
    default = emptyBody m;
    description = ''
      RouterOS `${m.path}`, rendered as ${renderVerb m}.
      ${optionalString (needsItems m) ''
        Written under `items`: this attribute set holds the menu's submenus,
        and `items` holds its own objects, because the two cannot share one
        attribute set.
      ''}
      ${optionalString (m.attrs != null) ''
        Known attribute names: ${concatStringsSep ", " (map (a: "`${a}`") m.attrs)}.
      ''}
      ${optionalString (m.attrs == null) ''
        Attribute names are not checked for this menu.
      ''}
      The same menu is expressible as `mikrotik.sections."${m.path}"`; both
      render identically, so a configuration can mix the two spellings.
    '';
  };

  # The option tree, one leaf per menu. Nested attribute sets are how a module
  # system declares `foo.bar.baz` without a `foo` and a `foo.bar` option.
  optionTree = foldl' (acc: m: recursiveUpdate acc (setAttrByPath (accessPath m) (menuOption m))) { } menus;

  # The compiler: what was set, keyed the way the renderer wants it. Menus left
  # at their default are dropped, because an empty body is not the same router
  # configuration as no section at all -- `sections."/ip address" = [ ]` renders
  # the bare menu header, and a menu nobody set must not do that.
  compiled = filterAttrs (_: body: body != [ ] && body != { })
    (listToAttrs (map
      (m: nameValuePair m.path (getAttrFromPath (accessPath m) config.mikrotik))
      menus));

  # The attribute names the user wrote for a menu, at the level they wrote them:
  # element keys for a list menu, body keys for a `set` menu.
  written = m:
    let body = getAttrFromPath (accessPath m) config.mikrotik;
    in if m.kind == "list" then lib.concatMap lib.attrNames body else lib.attrNames body;

  # A typo on the left of the `=` is the failure this layer exists to catch: as
  # a string the renderer would happily emit `add widht=80` and the router would
  # reject the script at deploy time, on the device.
  unknownAttributes = map
    (m: { inherit (m) path; inherit (m) attrs; names = subtractLists m.attrs (written m); })
    (filter (m: m.attrs != null) menus);
in
{
  options.mikrotik = optionTree // {
    checkMenuAttributes = mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Reject an attribute name a menu does not list in `lib/menus.nix`.

        On by default: an unknown name is far more often a typo than a new
        RouterOS feature, and the failure belongs in evaluation rather than in
        an import on a live router. Turn it off for a menu surface the table has
        not caught up with yet, and add the name to the table when it has.
      '';
    };
  };

  config = {
    mikrotik.sections = compiled;

    assertions = map
      (u: {
        assertion = u.names == [ ];
        message =
          "mikrotik.${concatStringsSep "." (segments u)}: ${u.path} has no "
          + (if builtins.length u.names == 1 then "attribute named " else "attributes named ")
          + "${concatStringsSep ", " u.names}. Known names for this menu: ${concatStringsSep ", " u.attrs}. "
          + "If that is a real RouterOS attribute, add it to lib/menus.nix; "
          + "otherwise write the menu as mikrotik.sections.\"${u.path}\", or set "
          + "mikrotik.checkMenuAttributes = false to write it unchecked.";
      })
      (filter (u: config.mikrotik.checkMenuAttributes && u.names != [ ]) unknownAttributes);
  };
}