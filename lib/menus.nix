# The RouterOS menus this fork knows, and what a body may say.
#
# One entry per menu, and the entry is the whole declaration: `modules/menus.nix`
# turns the list into options (`path` decides where) and into the `sections` key
# the renderer receives (`path` is that key, verbatim). Adding a menu is adding a
# line here -- there is no second place to keep in step.
#
#   path   the RouterOS command path, as `/export` spells it. The option lives
#          at the same path with `/` dropped and spaces turned into `.`:
#          `/ip dhcp-server network` is `mikrotik.ip."dhcp-server".network`.
#   kind   "list"   -- a menu of objects: renders as repeated `add …` lines.
#          "object" -- a menu of settings: renders as one `set …` per key.
#   attrs  the names the body may use, checked at evaluation time; or null for
#          "no check" (a menu whose surface is too wide to pin down). The check
#          is what turns a typo from a `script error` on a live router into a
#          Nix evaluation error.
#
# `attrs` is deliberately not a full RouterOS schema -- RouterOS ships none, and
# this file has no device to ask. It is the union of what the fleet's two
# routers, this repository's examples and the CRS226's own `/export`
# (`routers/homelab-router.rsc` in Infra/lunix, the oracle the render tests
# compare against) actually use, plus the neighbouring attributes of those menus
# that are documented and stable. A narrower list is the safe direction: it
# rejects a real attribute loudly at evaluation time, and the message says how
# to widen it. A wider list only weakens the typo check.
#
# Two conventions this table cannot express, on purpose:
#
#   * `/system identity` is absent. The identity is `mikrotik.hostname`, so that
#     the deploy tool can read it back off the device; `mikrotik.sections`
#     refuses the section for the same reason.
#   * Menus are not exhaustive. Anything not listed here is still expressible
#     through `mikrotik.sections."/the menu"` and `mikrotik.extraScript`, which
#     is the escape hatch, not a fallback to be ashamed of.
[
  {
    path = "/interface bridge";
    kind = "list";
    attrs = [
      "name"
      "admin-mac"
      "auto-mac"
      "arp"
      "comment"
      "disabled"
      "fast-forward"
      "igmp-snooping"
      "mtu"
      "protocol-mode"
      "pvid"
      "vlan-filtering"
    ];
  }

  {
    path = "/interface bridge port";
    kind = "list";
    attrs = [
      "bridge"
      "interface"
      "auto-isolate"
      "bpdu-guard"
      "broadcast-flood"
      "comment"
      "disabled"
      "edge"
      "fast-leave"
      "frame-types"
      "horizon"
      "hw"
      "ingress-filtering"
      "internal-path-cost"
      "learn"
      "multicast-router"
      "path-cost"
      "point-to-point"
      "priority"
      "pvid"
      "restricted-role"
      "restricted-tcn"
      "tag-stacking"
      "trusted"
      "unicast-flood"
      "unknown-multicast-flood"
      "unknown-unicast-flood"
    ];
  }

  {
    path = "/interface ethernet switch egress-vlan-tag";
    kind = "list";
    attrs = [ "tagged-ports" "vlan-id" ];
  }

  {
    path = "/interface ethernet switch ingress-vlan-translation";
    kind = "list";
    attrs = [
      "customer-vid"
      "new-customer-vid"
      "new-customer-pcp"
      "ports"
      "protocol"
      "svlan"
    ];
  }

  { path = "/interface list"; kind = "list"; attrs = [ "name" ]; }

  {
    path = "/interface list member";
    kind = "list";
    attrs = [ "interface" "list" ];
  }

  {
    path = "/interface ovpn-client";
    kind = "list";
    attrs = [
      "name"
      "connect-to"
      "port"
      "user"
      "password"
      "profile"
      "certificate"
      "auth"
      "cipher"
      "protocol"
      "mode"
      "mac-address"
      "disabled"
      "verify-server-certificate"
      "add-default-route"
      "route-nopull"
      "comment"
    ];
  }

  {
    path = "/interface vlan";
    kind = "list";
    attrs = [
      "name"
      "interface"
      "vlan-id"
      "arp"
      "comment"
      "disabled"
      "mtu"
    ];
  }

  {
    path = "/interface wifi security";
    kind = "list";
    attrs = [
      "name"
      "authentication-types"
      "passphrase"
      "group-ciphers"
      "group-key-update"
      "management-encryption"
      "static-sta-private-key"
    ];
  }

  {
    path = "/interface wireguard";
    kind = "list";
    attrs = [ "name" "listen-port" "mtu" "private-key" "comment" "disabled" ];
  }

  {
    path = "/interface wireguard peers";
    kind = "list";
    attrs = [
      "interface"
      "name"
      "allowed-address"
      "endpoint-address"
      "endpoint-port"
      "public-key"
      "preshared-key"
      "persistent-keepalive"
      "comment"
      "disabled"
    ];
  }

  {
    path = "/ip address";
    kind = "list";
    attrs = [ "address" "interface" "network" "comment" "disabled" ];
  }

  {
    path = "/ip cloud";
    kind = "object";
    attrs = [ "update-time" "ddns-enabled" "ddns-update-interval" "back-to-home-vpn" ];
  }

  {
    path = "/ip dhcp-client";
    kind = "list";
    attrs = [
      "interface"
      "name"
      "add-default-route"
      "use-peer-dns"
      "use-peer-ntp"
      "comment"
      "disabled"
    ];
  }

  {
    path = "/ip dhcp-server";
    kind = "list";
    attrs = [
      "name"
      "interface"
      "address-pool"
      "lease-time"
      "authoritative"
      "comment"
      "disabled"
    ];
  }

  {
    path = "/ip dhcp-server network";
    kind = "list";
    attrs = [
      "address"
      "gateway"
      "dns-server"
      "netmask"
      "domain"
      "ntp-server"
      "dns-none"
      "boot-file-name"
      "next-server"
      "comment"
    ];
  }

  {
    path = "/ip dns";
    kind = "object";
    attrs = [
      "servers"
      "dynamic-servers"
      "allow-remote-requests"
      "cache-size"
      "cache-max-ttl"
      "max-udp-packet-size"
      "query-server-timeout"
      "query-total-timeout"
      "use-doh-server"
      "verify-doh-cert"
      "vrf"
      "no_label"
    ];
  }

  {
    path = "/ip dns static";
    kind = "list";
    attrs = [
      "name"
      "address"
      "type"
      "ttl"
      "cname"
      "regexp"
      "text"
      "forward-to"
      "mx-exchange"
      "mx-preference"
      "comment"
      "disabled"
    ];
  }

  {
    path = "/ip firewall address-list";
    kind = "list";
    attrs = [ "address" "list" "timeout" "comment" "disabled" ];
  }

  {
    path = "/ip firewall filter";
    kind = "list";
    attrs = [
      "action"
      "chain"
      "comment"
      "connection-state"
      "connection-nat-state"
      "connection-mark"
      "content"
      "disabled"
      "dst-address"
      "dst-address-list"
      "dst-port"
      "dst-limit"
      "icmp-options"
      "in-interface"
      "in-interface-list"
      "jump-target"
      "log"
      "log-prefix"
      "out-interface"
      "out-interface-list"
      "packet-mark"
      "place-before"
      "protocol"
      "reject-with"
      "routing-mark"
      "src-address"
      "src-address-list"
      "src-port"
      "tcp-flags"
      "time"
      "ttl"
    ];
  }

  {
    path = "/ip firewall mangle";
    kind = "list";
    attrs = [
      "action"
      "chain"
      "comment"
      "disabled"
      "dst-address"
      "dst-address-list"
      "dst-port"
      "in-interface"
      "in-interface-list"
      "new-connection-mark"
      "new-packet-mark"
      "new-routing-mark"
      "out-interface"
      "out-interface-list"
      "packet-mark"
      "passthrough"
      "protocol"
      "routing-mark"
      "src-address"
      "src-address-list"
      "src-port"
      "time"
    ];
  }

  {
    path = "/ip firewall nat";
    kind = "list";
    attrs = [
      "action"
      "chain"
      "comment"
      "disabled"
      "dst-address"
      "dst-address-list"
      "dst-port"
      "in-interface"
      "in-interface-list"
      "jump-target"
      "log"
      "log-prefix"
      "out-interface"
      "out-interface-list"
      "protocol"
      "src-address"
      "src-address-list"
      "src-port"
      "to-addresses"
      "to-ports"
    ];
  }

  {
    path = "/ip neighbor discovery-settings";
    kind = "object";
    attrs = [ "discover-interface-list" "protocol" ];
  }

  { path = "/ip pool"; kind = "list"; attrs = [ "name" "ranges" "comment" ]; }

  {
    path = "/ip route";
    kind = "list";
    attrs = [
      "dst-address"
      "gateway"
      "distance"
      "routing-table"
      "check-gateway"
      "pref-src"
      "scope"
      "target-scope"
      "comment"
      "disabled"
    ];
  }

  {
    path = "/ip service";
    kind = "object";
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
  }

  {
    path = "/ip ssh";
    kind = "object";
    attrs = [
      "strong-crypto"
      "host-key-type"
      "host-key-size"
      "forwarding-enabled"
      "password-authentication"
      "allow-none-crypto"
      "always-allow-password-login"
    ];
  }

  {
    path = "/ip vrf";
    kind = "list";
    attrs = [ "name" "interfaces" "comment" "disabled" ];
  }

  {
    path = "/ipv6 address";
    kind = "list";
    attrs = [
      "address"
      "interface"
      "advertise"
      "eui-64"
      "from-pool"
      "no-dad"
      "comment"
      "disabled"
    ];
  }

  {
    path = "/ipv6 firewall filter";
    kind = "list";
    attrs = [
      "action"
      "chain"
      "comment"
      "connection-state"
      "disabled"
      "dst-address"
      "dst-address-list"
      "dst-port"
      "in-interface"
      "in-interface-list"
      "jump-target"
      "log"
      "log-prefix"
      "out-interface"
      "out-interface-list"
      "protocol"
      "src-address"
      "src-address-list"
      "src-port"
    ];
  }

  {
    path = "/ipv6 route";
    kind = "list";
    attrs = [
      "dst-address"
      "gateway"
      "distance"
      "routing-table"
      "check-gateway"
      "scope"
      "target-scope"
      "comment"
      "disabled"
    ];
  }

  {
    path = "/system clock";
    kind = "object";
    attrs = [ "time-zone-name" "time-zone-autodetect" ];
  }

  {
    path = "/tool bandwidth-server";
    kind = "object";
    attrs = [ "enabled" "authenticate" ];
  }

  {
    path = "/tool mac-server";
    kind = "object";
    attrs = [ "allowed-interface-list" ];
  }

  {
    path = "/tool mac-server mac-winbox";
    kind = "object";
    attrs = [ "allowed-interface-list" ];
  }

  { path = "/tool mac-server ping"; kind = "object"; attrs = [ "enabled" ]; }
]