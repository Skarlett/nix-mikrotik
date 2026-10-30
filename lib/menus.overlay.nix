# What `lib/menus.generated.nix` cannot see, and why.
#
# The generated table is the whole menu surface of a RouterOS 7.25 CHR, read off
# the router itself. A CHR is a *virtual* router, so there are three ways its
# answers fall short of what this library has to describe, and each one is here
# rather than being silently absent:
#
#   * hardware it does not have -- no switch chip, no radio. `/interface ethernet
#     switch egress-vlan-tag` and `ingress-vlan-translation` exist only on a
#     device with the switch chip (the fleet's CRS226 uses both), so the walk
#     never sees them and they have to be carried by hand.
#
#   * conventions the renderer adds -- `no_label` is not a RouterOS attribute at
#     all; it is how `lib/render.nix` writes a `set` line with several arguments.
#     The router has no reason to report it.
#
#   * menus whose keys are *names*, not arguments. `/ip service` is `set`-style,
#     and the router reports its arguments as `address`, `certificate`,
#     `disabled`, `port`, `vrf` … -- the properties of a service. But the typed
#     surface keys on the service name (`mikrotik.ip.service.ssh = { … }`), so
#     the generated argument list would reject every existing use. Replacing is
#     the whole point here, not widening.
#
# `mode`:
#   "add"     the menu is absent from the generated table; add it whole.
#   "union"   add these names to whatever the generator found.
#   "replace" discard the generated names for this menu and use these.
[
  {
    path = "/interface ethernet switch egress-vlan-tag";
    kind = "list";
    mode = "add";
    attrs = [ "tagged-ports" "vlan-id" ];
    why = ''
      Switch-chip menu. A CHR has no switch chip, so the walk never reaches it,
      and the fleet's CRS226 configuration uses it.
    '';
  }
  {
    path = "/interface ethernet switch ingress-vlan-translation";
    kind = "list";
    mode = "add";
    attrs = [
      "customer-vid"
      "new-customer-vid"
      "new-customer-pcp"
      "ports"
      "protocol"
      "svlan"
    ];
    why = ''
      Switch-chip menu, same as the entry above: absent from a CHR, used by the
      CRS226.
    '';
  }
  {
    path = "/ip dns";
    kind = "object";
    mode = "union";
    attrs = [ "no_label" ];
    why = ''
      Not a RouterOS attribute. `no_label` drops the label when rendering a `set`
      line with several arguments (`lib/render.nix`), so the router cannot report
      it and the typed surface still has to accept it.
    '';
  }
  {
    path = "/ip service";
    kind = "object";
    mode = "replace";
    attrs = [
      "api"
      "api-ssl"
      "ftp"
      "reverse-proxy"
      "ssh"
      "telnet"
      "winbox"
      "www"
      "www-ssl"
    ];
    why = ''
      The generated names for this menu are the properties of a service
      (`address`, `certificate`, `disabled`, `port`, `vrf`, …), because that is
      what RouterOS lists as `set` arguments. The typed surface keys on the
      service name instead, so the generated list would reject every existing
      use. These are the services RouterOS 7.25 ships.
    '';
  }
]