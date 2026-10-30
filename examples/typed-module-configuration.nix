# `examples/module-configuration.nix`, written with the typed menu options.
#
# This file exists to be compared: it configures the same router, records for
# record, as `module-configuration.nix`, and `tests/menus.nix` renders both and
# requires the two scripts to be byte-identical. If the typed layer ever learns
# to render something the section layer does not -- or loses an argument on the
# way -- that check fails.
#
# The visible difference is the menu: `/ip dhcp-server network` becomes
# `ip."dhcp-server".network`, and the menus with submenus move their own body
# under `items` (`interface.bridge.items` next to `interface.bridge.port`).
#
# `hardening.nix` is imported exactly as it is in the other file, and it still
# writes `mikrotik.sections`: a module written for the old spelling keeps
# working, and the two spellings merge in one configuration.
{ mkSecret, ... }:
{
  imports = [ ../modules/hardening.nix ];

  mikrotik = {
    hostname = "nidas";
    comment = "ported from the upstream nix-mikrotik example";

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

    secrets = {
      wifi-password = {
        description = "WPA2 passphrase for the `wifi` bridge";
        file = "wifi-password";
      };
      wg-private-key = {
        description = "WireGuard private key for wg.luninet";
        file = "wg-private-key";
      };
    };

    interface = {
      # `/interface bridge` also has `/interface bridge port` below it, so the
      # bridges themselves are the menu's `items`.
      bridge.items = [
        # `auto-mac = false` with no member ports gives the bridge no MAC to
        # derive from, and the import dies with "invalid mac address" -- which is
        # what upstream's example does on a fresh device. Either pin an
        # admin-mac (as the fleet router does) or let RouterOS choose.
        { name = "bridge"; comment = "defconf"; }
        { name = "wifi"; }
      ];

      vlan = [
        { name = "vlan20"; interface = "bridge"; vlan-id = 20; }
      ];

      # `/interface list` has `/interface list member` under it.
      list.items = [ { name = "LAN"; } { name = "WAN"; } ];

      list.member = [
        { list = "LAN"; interface = "bridge"; }
        { list = "WAN"; interface = "ether1"; }
      ];

      wireguard.items = [
        {
          name = "wg.luninet";
          listen-port = 57676;
          mtu = 1420;
          private-key = mkSecret "wg-private-key";
        }
      ];

      wireguard.peers = [
        {
          interface = "wg.luninet";
          public-key = "l0VH8y3T0nKzZ9Qq2m4Xo8b1y6wR5cJ7dE3fG9hI2kA=";
          allowed-address = "10.44.0.0/24";
          endpoint-address = "router.luninet";
          endpoint-port = 57676;
          persistent-keepalive = "25s";
        }
      ];

      wifi.security = [
        {
          name = "default";
          authentication-types = "wpa2-psk";
          passphrase = mkSecret "wifi-password";
        }
      ];
    };

    ip = {
      pool = [
        { name = "wired-pool"; ranges = "10.10.10.10-10.10.10.254"; }
        { name = "wifi-pool"; ranges = "10.10.11.10-10.10.11.254"; }
      ];

      address = [
        { address = "10.10.10.1/24"; network = "10.10.10.0"; interface = "ether2"; }
        { address = "10.10.11.1/24"; network = "10.10.11.0"; interface = "wifi"; }
      ];

      "dhcp-server".items = [
        { name = "wired-dhcp"; interface = "bridge"; address-pool = "wired-pool"; disabled = false; }
        { name = "wifi-dhcp"; interface = "wifi"; address-pool = "wifi-pool"; disabled = false; }
      ];

      "dhcp-server".network = [
        { address = "10.10.10.0/24"; gateway = "10.10.10.1"; netmask = "24"; }
        { address = "10.10.11.0/24"; gateway = "10.10.11.1"; netmask = "24"; }
      ];

      "dhcp-client" = [ { interface = "ether1"; disabled = false; } ];

      # `no_label` is upstream's spelling for a menu whose `set` arguments are
      # written as one line rather than as a sub-object. `/ip dns` has `/ip dns
      # static` under it, so its body is `items`.
      dns.items = {
        no_label = {
          allow-remote-requests = true;
          servers = "1.1.1.1,1.0.0.1";
        };
      };

      dns.static = [ { name = "router.lan"; address = "10.10.10.1"; } ];

      firewall."address-list" = [
        { list = "allowed_to_router"; address = "10.10.10.0/24"; }
      ];

      firewall.filter = [
        { chain = "input"; action = "accept"; src-address-list = "allowed_to_router"; }
        { chain = "input"; action = "accept"; protocol = "icmp"; }
        { chain = "input"; action = "drop"; in-interface-list = "WAN"; }
      ];

      firewall.nat = [
        { chain = "srcnat"; action = "masquerade"; out-interface-list = "WAN"; comment = "masquerade (cost $5/GB)"; }
      ];
    };

    system.clock = { time-zone-name = "Europe/Stockholm"; };
  };
}