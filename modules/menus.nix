# The typed menu surface: `mikrotik.ip."dhcp-server".network = [ … ]` rather than
# `mikrotik.sections."/ip dhcp-server network" = [ … ]`.
#
# This module is a front end and nothing else. The option tree it declares lives
# in `lib/menu-options.nix`, and `modules/base.nix` splices it into the one
# option set a router is written against -- so a router inside
# `mikrotik.routers.<name>` writes `mikrotik.ip.address` exactly as a lone router
# does, rather than a second spelling of the same menu. This file compiles what
# was set into `sections`: the same attrset `lib/render.nix` has always
# rendered, with the same keys and the same values. The renderer does not know
# this module exists, which is the whole argument for render parity: the two
# spellings agree on the value handed to RouterOS syntax before any RouterOS
# syntax is involved.
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
  mo = import ../lib/menu-options.nix { inherit lib; };

  cfg = config.mikrotik;

  # A typo on the left of the `=` is the failure this layer exists to catch: as a
  # string the renderer would happily emit `add widht=80` and the router would
  # reject the script at deploy time, on the device.
  #
  # Only the single-router options are checked here. A router in
  # `mikrotik.routers` is a module of its own, evaluated and checked by
  # `evalMikrotikFleet`; that evaluation reports its own name as the context of
  # the failure, so the diagnostic still says which router is wrong.
  unknown =
    if cfg.checkMenuAttributes then
      map (u: { label = "mikrotik"; inherit (u) path attrs names; }) (mo.unknownAttributes cfg)
    else
      [ ];

  # An attribute the device stores as several values, written as one
  # comma-joined string. It renders identically, so the only place it can be
  # caught is here, before the script exists.
  commaStrings =
    if cfg.checkMenuLists then
      map (c: { label = "mikrotik"; inherit (c) path attrs names; }) (mo.commaStrings cfg)
    else
      [ ];
in
{
  config = {
    mikrotik.sections = mo.compile cfg;

    assertions =
      map
        (u: {
          assertion = u.names == [ ];
          message = mo.messageFor u.label u;
        })
        unknown
      ++ map
        (c: {
          assertion = c.names == [ ];
          message = mo.messageForCommaStrings c.label c;
        })
        commaStrings;
  };
}
