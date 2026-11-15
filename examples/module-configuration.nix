# The upstream example configuration, expressed in the `mikrotik` module class.
#
# `examples/configuration.nix` is kept exactly as upstream wrote it: it is the
# compatibility fixture, and the render check diffs this renderer against
# upstream's own output for it (`tests/golden/legacy-upstream.rsc`). This
# file is the same router written the way this fork expects -- as a module, so
# it can import hardening.nix, it is type-checked, and its secrets are
# references rather than strings.
#
# Two things here have no upstream equivalent: the Wi-Fi security profile and
# the WireGuard interface carry secrets. Each is declared as a generator -- in
# clan's own shape, `clan.core.vars.generators.<name>` -- and the menu cell
# holds `files.<file>.placeholder`, which renders as a marker and is replaced by
# `nix-mikrotik deploy` on the machine that runs the generator. Neither value is
# ever in the store, and neither is in this file.
{ config, pkgs, ... }:
{
  imports = [ ../modules/hardening.nix ];

  # The generators that mint this router's secrets, in the shape clan uses:
  # `files` says what the script writes, `prompts` asks a human for a value that
  # cannot be minted, and `script` runs on the deploying machine with `$out`,
  # `$in` and `$prompts` set.
  #
  # `nix-mikrotik generate` runs them and keeps the values under
  # `vars/per-machine/nidas/<generator>/<file>`; nothing here or in the store
  # holds a value.
  clan.core.vars.generators = {
    wg-private-key = {
      files.privkey.secret = true;
      # `wg` comes from here, not from whatever the deploying machine happens to
      # have on PATH.
      runtimeInputs = [ pkgs.wireguard-tools ];
      script = "wg genkey > $out/privkey";
    };

    wifi-password = {
      files.passphrase = { };
      # A passphrase is chosen, not derived: a persisted prompt *is* a file of
      # the generator, so the deploy tool copies it from `$prompts` to `$out`
      # and no script is needed.
      prompts.passphrase = {
        description = "WPA2 passphrase for the `wifi` bridge";
        type = "hidden";
        persist = true;
      };
      script = "";
    };
  };

  mikrotik = {
    hostname = "nidas";
    comment = "ported from the upstream nix-mikrotik example";

    # RouterOS applies a script top to bottom, so anything referenced has to
    # exist first. Everything else renders alphabetically.
    sectionOrder = [
      "/interface bridge"
      "/interface vlan"
      "/interface list"
      "/interface list member"
      "/ip pool"
      "/ip address"
      "/ip dhcp-server"
      "/ip dhcp-server network"
      "/ip firewall address-list"
      "/ip firewall filter"
      "/ip firewall nat"
    ];

    sections = {
      "/interface bridge" = [
        # `auto-mac = false` with no member ports gives the bridge no MAC to
        # derive from, and the import dies with "invalid mac address" -- which
        # is what upstream's example does on a fresh device. Either pin an
        # admin-mac (as the fleet router does) or let RouterOS choose.
        { name = "bridge"; comment = "defconf"; }
        { name = "wifi"; }
      ];

      "/interface vlan" = [
        { name = "vlan20"; interface = "bridge"; vlan-id = 20; }
      ];

      "/interface list" = [ { name = "LAN"; } { name = "WAN"; } ];

      "/interface list member" = [
        { list = "LAN"; interface = "bridge"; }
        { list = "WAN"; interface = "ether1"; }
      ];

      "/ip pool" = [
        { name = "wired-pool"; ranges = "10.10.10.10-10.10.10.254"; }
        { name = "wifi-pool"; ranges = "10.10.11.10-10.10.11.254"; }
      ];

      "/ip address" = [
        { address = "10.10.10.1/24"; network = "10.10.10.0"; interface = "ether2"; }
        { address = "10.10.11.1/24"; network = "10.10.11.0"; interface = "wifi"; }
      ];

      "/ip dhcp-server" = [
        { name = "wired-dhcp"; interface = "bridge"; address-pool = "wired-pool"; disabled = false; }
        { name = "wifi-dhcp"; interface = "wifi"; address-pool = "wifi-pool"; disabled = false; }
      ];

      "/ip dhcp-server network" = [
        { address = "10.10.10.0/24"; gateway = "10.10.10.1"; netmask = "24"; }
        { address = "10.10.11.0/24"; gateway = "10.10.11.1"; netmask = "24"; }
      ];

      "/ip dhcp-client" = [ { interface = "ether1"; disabled = false; } ];

      # `no_label` is upstream's spelling for a menu whose `set` arguments are
      # written as one line rather than as a sub-object.
      "/ip dns" = {
        no_label = {
          allow-remote-requests = true;
          servers = "1.1.1.1,1.0.0.1";
        };
      };

      "/ip dns static" = [ { name = "router.lan"; address = "10.10.10.1"; } ];

      "/ip firewall address-list" = [
        { list = "allowed_to_router"; address = "10.10.10.0/24"; }
      ];

      "/ip firewall filter" = [
        { chain = "input"; action = "accept"; src-address-list = "allowed_to_router"; }
        { chain = "input"; action = "accept"; protocol = "icmp"; }
        { chain = "input"; action = "drop"; in-interface-list = "WAN"; }
      ];

      "/ip firewall nat" = [
        { chain = "srcnat"; action = "masquerade"; out-interface-list = "WAN"; comment = "masquerade (cost $5/GB)"; }
      ];

      # A secret in a section: the value never reaches the store.
      "/interface wireguard" = [
        {
          name = "wg.luninet";
          listen-port = 57676;
          mtu = 1420;
          private-key = config.clan.core.vars.generators.wg-private-key.files.privkey.placeholder;
        }
      ];

      "/interface wireguard peers" = [
        {
          interface = "wg.luninet";
          public-key = "l0VH8y3T0nKzZ9Qq2m4Xo8b1y6wR5cJ7dE3fG9hI2kA=";
          allowed-address = "10.44.0.0/24";
          endpoint-address = "router.luninet";
          endpoint-port = 57676;
          persistent-keepalive = "25s";
        }
      ];

      "/interface wifi security" = [
        {
          name = "default";
          authentication-types = "wpa2-psk";
          passphrase = config.clan.core.vars.generators.wifi-password.files.passphrase.placeholder;
        }
      ];

      "/system clock" = { time-zone-name = "Europe/Stockholm"; };
    };
  };
}
