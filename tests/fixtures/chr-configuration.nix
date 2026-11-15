# The configuration `tests/chr-deploy.nix` applies to a real RouterOS.
#
# It is written for the device the check has, not for the router the examples
# describe, and that is not a shortcut -- `examples/module-configuration.nix`
# and `examples/configuration.nix` both describe a box with ether2, ether3,
# ether4, ether5 and sfp1. A CHR has **one** ethernet port (ether1, the
# management NIC), so an `/ip address … interface=ether2` line is refused by the
# device at runtime: measured on 7.15.3, `script error: input does not match any
# value of interface` at line 20, with the identity, both bridges and the vlan
# from the lines above it already applied. Those examples stay as they are --
# they are upstream's router, ported -- and this fixture is the one written for
# a CHR.
#
# What it is here to exercise is the renderer's hard parts, each of which a
# device can reject in a way no pure check can see:
#
#   * section order -- `/interface bridge` before the address that sits on it,
#     the pool before the dhcp-server that draws from it;
#   * quoting -- `comment="masquerade (cost \$5/GB)"` and a WireGuard key that
#     is substituted at deploy time; unquoted, the `=` padding of a base64 key
#     ends the command early and the device refuses the whole script;
#   * secrets -- two placeholders, delivered by `nix-mikrotik deploy`; one goes
#     into a `private-key=` slot (a value that must be quoted) and one into a
#     comment, where it can be read back byte for byte.
#
# It deliberately does *not* import `modules/hardening.nix`: that module ends in
# `/ip service set www disabled=yes`, which turns off the REST API this check
# reads the device back through. `checks.render` covers that module's lines;
# deploying them would cost the check its independent view of the device.
{ config, ... }:
{
  mikrotik = {
    hostname = "chr-deploy";
    comment = "applied by tests/chr-deploy.nix -- not a router configuration";

    sectionOrder = [
      "/interface bridge"
      "/interface list"
      "/interface list member"
      "/ip pool"
      "/ip address"
      "/ip dhcp-server"
      "/ip dhcp-server network"
      "/ip firewall address-list"
      "/ip firewall filter"
      "/ip firewall nat"
      "/ip dns static"
      "/interface wireguard"
    ];

    sections = {
      # No member ports: a bridge with `auto-mac=no` and no ports has no MAC to
      # derive and the import dies with "invalid mac address" (that is what
      # upstream's example does on a fresh device), so the MAC is left to
      # RouterOS. ether1 stays out of the bridge -- it is the check's own way in.
      "/interface bridge" = [
        { name = "lan"; comment = "chr-deploy-check"; }
      ];

      "/interface list" = [ { name = "LAN"; } { name = "WAN"; } ];

      "/interface list member" = [
        { list = "LAN"; interface = "lan"; }
        { list = "WAN"; interface = "ether1"; }
      ];

      "/ip pool" = [
        { name = "lan-pool"; ranges = "192.168.88.10-192.168.88.254"; }
      ];

      "/ip address" = [
        { address = "192.168.88.1/24"; network = "192.168.88.0"; interface = "lan"; }
      ];

      "/ip dhcp-server" = [
        { name = "lan-dhcp"; interface = "lan"; address-pool = "lan-pool"; disabled = false; }
      ];

      "/ip dhcp-server network" = [
        { address = "192.168.88.0/24"; gateway = "192.168.88.1"; netmask = "24"; }
      ];

      "/ip dns static" = [
        {
          name = "chr-deploy.lan";
          address = "192.168.88.1";
          # A secret in a place the device reads back verbatim.
          comment = config.clan.core.vars.generators.dns.files.comment.placeholder;
        }
      ];

      "/ip firewall address-list" = [
        { list = "allowed_to_router"; address = "192.168.88.0/24"; }
      ];

      "/ip firewall filter" = [
        { chain = "input"; action = "accept"; src-address-list = "allowed_to_router"; }
        { chain = "input"; action = "accept"; protocol = "icmp"; }
      ];

      "/ip firewall nat" = [
        {
          chain = "srcnat";
          action = "masquerade";
          out-interface-list = "WAN";
          # `$` starts a variable reference inside a quoted value, so the
          # renderer escapes it; this is the line the read-back checks.
          comment = "masquerade (cost $5/GB)";
        }
      ];

      # The secret-bearing interface: `private-key=` is filled in at deploy
      # time, and an unquoted base64 value would abort the entire script.
      "/interface wireguard" = [
        { name = "wg.check"; listen-port = 51820; mtu = 1420; private-key = config.clan.core.vars.generators.wg.files.private-key.placeholder; }
      ];

      "/system clock" = { time-zone-name = "UTC"; };
    };
  };

  # Two generators, because a generator is the unit clan generates: one mints
  # the key the interface needs, one holds the value that is read back out of
  # a comment. Neither is run by this check -- the values are handed to
  # `deploy` on the command line -- but a placeholder with no declaration is
  # refused at evaluation, which is the point of declaring them here.
  #
  # Declared next to `mikrotik`, not inside it: `clan.core.*` is not a
  # RouterOS menu, and `mikrotik` refuses an option it does not know.
  clan.core.vars.generators.wg = {
    files.private-key = { };
    script = "wg genkey > $out/private-key";
  };
  clan.core.vars.generators.dns = {
    files.comment = { };
    # A persisted prompt *is* a file of the generator: the deploy tool copies
    # it from `$prompts` to `$out`, so this generator needs no script of its
    # own. It is how a value a human knows but the machine cannot mint is
    # declared.
    prompts.comment = {
      description = "the value the harness supplies";
      persist = true;
    };
    script = "";
  };
}
