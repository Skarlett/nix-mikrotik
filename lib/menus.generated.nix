# GENERATED -- do not edit. Run scripts/regenerate-menus.sh instead.
#
# The whole menu surface of RouterOS 7.25, as the router describes itself:
# 346 menus walked out of `/console/inspect` on a CHR (build 2026-10-22 14:12:00),
# 250 of them `add`-style and 96 `set`-style. A further 119 nodes are
# containers -- they have no `add` and no `set`, so they are not menus this table
# can declare, and they are deliberately absent rather than null.
#
# `attrs` here is not hand-curated: it is the argument list the router reports for
# that menu's `add` (list) or `set` (object) command. That makes it wider than
# anything a person maintained, and it makes it wrong in a way the overlay fixes
# -- see lib/menus.overlay.nix for the menus whose keys are names rather than
# arguments.
#
# `lists` is the half of an argument the walk cannot see: the ones RouterOS
# stores as several values (`interfaces=ether1,ether2`), which the typed menu
# options write as a Nix list. It is probed by scripts/probe-menu-lists.py, and
# only attributes the device *took* a comma-separated value for are listed --
# an attribute that is absent was not proven to be scalar, it was not proven to
# be a list. See lib/menus.overlay.nix for the ones the probe cannot reach.
#
# Regenerate with the CHR pinned in chr/default.nix (or the newer image the
# generator uses) and a walker that retries: a timed-out inspect and an empty
# child list look identical from outside, so a walk without retries returns a
# *narrower* tree that still looks complete.
[
  {
    path = "/certificate";
    kind = "list";
    attrs = [
      "common-name"
      "copy-from"
      "country"
      "days-valid"
      "digest-algorithm"
      "key-size"
      "key-usage"
      "locality"
      "name"
      "organization"
      "state"
      "subject-alt-name"
      "trust-store"
      "trusted"
      "unit"
    ];
  }
  {
    path = "/certificate crl";
    kind = "list";
    attrs = [
      "copy-from"
      "url"
    ];
  }
  {
    path = "/certificate scep-server";
    kind = "list";
    attrs = [
      "ca-cert"
      "copy-from"
      "days-valid"
      "disabled"
      "next-ca-cert"
      "path"
      "request-lifetime"
    ];
  }
  {
    path = "/certificate scep-server ra";
    kind = "list";
    attrs = [
      "ca-identity"
      "challenge-password"
      "copy-from"
      "disabled"
      "fingerprint-algorithm"
      "name"
      "on-smart-card"
      "ra-path"
      "ra-transaction-lifetime"
      "server-url"
      "template"
    ];
  }
  {
    path = "/certificate settings";
    kind = "object";
    attrs = [
      "builtin-trust-store"
      "crl-download"
      "crl-store"
      "crl-use"
      "current-defaults"
    ];
    # multi-value: written as a list in the typed menu
    lists = [
      "current-defaults"
    ];
  }
  {
    path = "/cmr-client";
    kind = "object";
    attrs = [
      "controller-addresses"
      "enabled"
      "local-id"
      "nfc-pairing"
      "pairing-requirement"
      "peer-id"
    ];
    # multi-value: written as a list in the typed menu
    lists = [
      "controller-addresses"
    ];
  }
  {
    path = "/console alias";
    kind = "list";
    attrs = [
      "copy-from"
      "key"
      "path"
      "scope"
      "script"
      "users"
    ];
  }
  {
    path = "/console settings";
    kind = "object";
    attrs = [
      "log-script-errors"
      "sanitize-names"
      "tab-width"
    ];
  }
  {
    path = "/disk";
    kind = "list";
    attrs = [
      "comment"
      "compress"
      "copy-from"
      "crypt-mode"
      "disabled"
      "extra-mount-opts"
      "file-offset"
      "file-path"
      "file-size"
      "media-interface"
      "media-sharing"
      "mount-filesystem"
      "mount-point-template"
      "mount-read-only"
      "parent"
      "partition-number"
      "partition-offset"
      "partition-size"
      "slot"
      "smb-address"
      "smb-encryption"
      "smb-password"
      "smb-server-encryption"
      "smb-server-password"
      "smb-server-user"
      "smb-share"
      "smb-sharing"
      "smb-user"
      "sshfs-address"
      "sshfs-password"
      "sshfs-path"
      "sshfs-port"
      "sshfs-user"
      "swap"
      "tmpfs-max-size"
      "type"
    ];
  }
  {
    path = "/disk settings";
    kind = "object";
    attrs = [
      "auto-media-interface"
      "auto-media-sharing"
      "auto-smb-sharing"
      "auto-smb-user"
      "default-mount-point-template"
    ];
  }
  {
    path = "/figman accept";
    kind = "list";
    attrs = [
      "action"
      "blob"
      "comment"
      "copy-from"
      "disabled"
      "local-id"
      "params"
      "peer-id"
      "place-before"
      "store"
      "tag"
    ];
  }
  {
    path = "/figman connect";
    kind = "list";
    attrs = [
      "comment"
      "connect"
      "copy-from"
      "disabled"
      "listen"
      "local-id"
      "name"
      "peer-id"
      "request"
    ];
  }
  {
    path = "/figman local";
    kind = "list";
    attrs = [
      "blob"
      "comment"
      "copy-from"
      "disabled"
      "params"
      "store"
      "tag"
    ];
  }
  {
    path = "/figman peer";
    kind = "list";
    attrs = [
      "comment"
      "copy-from"
      "disabled"
      "ids"
      "name"
      "transient"
    ];
  }
  {
    path = "/figman remote";
    kind = "list";
    attrs = [
      "blob"
      "comment"
      "copy-from"
      "disabled"
      "params"
      "peer"
      "store"
      "tag"
    ];
  }
  {
    path = "/figman store";
    kind = "list";
    attrs = [
      "blob"
      "comment"
      "copy-from"
      "disabled"
      "name"
    ];
  }
  {
    path = "/file";
    kind = "list";
    attrs = [
      "contents"
      "name"
      "type"
    ];
  }
  {
    path = "/interface";
    kind = "object";
    attrs = [
      "comment"
      "disabled"
      "l2mtu"
      "mtu"
      "name"
      "numbers"
    ];
  }
  {
    path = "/interface 6to4";
    kind = "list";
    attrs = [
      "clamp-tcp-mss"
      "comment"
      "copy-from"
      "disabled"
      "dont-fragment"
      "dscp"
      "ipsec-secret"
      "keepalive"
      "local-address"
      "mtu"
      "name"
      "remote-address"
    ];
  }
  {
    path = "/interface bonding";
    kind = "list";
    attrs = [
      "arp"
      "arp-interval"
      "arp-ip-targets"
      "arp-timeout"
      "comment"
      "copy-from"
      "disabled"
      "down-delay"
      "forced-mac-address"
      "lacp-mode"
      "lacp-rate"
      "lacp-system-id"
      "lacp-system-priority"
      "lacp-user-key"
      "link-monitoring"
      "mii-interval"
      "min-links"
      "mlag-id"
      "mode"
      "mtu"
      "name"
      "primary"
      "slaves"
      "transmit-hash-policy"
      "up-delay"
    ];
  }
  {
    path = "/interface bridge";
    kind = "list";
    attrs = [
      "admin-mac"
      "ageing-time"
      "arp"
      "arp-inspection"
      "arp-timeout"
      "auto-mac"
      "comment"
      "copy-from"
      "dhcp-agent-circuit-id"
      "dhcp-agent-remote-id"
      "dhcp-snooping"
      "dhcpv6-agent-circuit-id"
      "dhcpv6-agent-remote-id"
      "dhcpv6-snooping"
      "disabled"
      "ether-type"
      "fast-forward"
      "forward-delay"
      "forward-reserved-addresses"
      "frame-types"
      "igmp-snooping"
      "igmp-version"
      "ingress-filtering"
      "ip-source-guard"
      "last-member-interval"
      "last-member-query-count"
      "last-member-query-interval"
      "max-hops"
      "max-learned-entries"
      "max-message-age"
      "membership-interval"
      "mlag-heartbeat"
      "mlag-init-delay"
      "mlag-lacp-fallback"
      "mlag-peer-port"
      "mlag-priority"
      "mld-version"
      "mtu"
      "multicast-querier"
      "multicast-router"
      "mvrp"
      "name"
      "port-cost-mode"
      "priority"
      "protocol-mode"
      "pvid"
      "querier-interval"
      "querier-uses-bridge-address"
      "query-interval"
      "query-response-interval"
      "ra-guard"
      "region-name"
      "region-revision"
      "startup-query-count"
      "startup-query-interval"
      "sys-bundleid"
      "transmit-hold-count"
      "vlan-filtering"
    ];
  }
  {
    path = "/interface bridge calea";
    kind = "list";
    attrs = [
      "802.3-sap"
      "802.3-type"
      "action"
      "arp-dst-address"
      "arp-dst-mac-address"
      "arp-gratuitous"
      "arp-hardware-type"
      "arp-opcode"
      "arp-packet-type"
      "arp-src-address"
      "arp-src-mac-address"
      "chain"
      "comment"
      "copy-from"
      "disabled"
      "dst-address"
      "dst-address6"
      "dst-mac-address"
      "dst-port"
      "in-bridge"
      "in-bridge-list"
      "in-interface"
      "in-interface-list"
      "ingress-priority"
      "ip-protocol"
      "limit"
      "log"
      "log-prefix"
      "mac-protocol"
      "out-bridge"
      "out-bridge-list"
      "out-interface"
      "out-interface-list"
      "packet-mark"
      "packet-type"
      "place-before"
      "sniff-id"
      "sniff-target"
      "sniff-target-port"
      "src-address"
      "src-address6"
      "src-mac-address"
      "src-port"
      "stp-flags"
      "stp-forward-delay"
      "stp-hello-time"
      "stp-max-age"
      "stp-msg-age"
      "stp-port"
      "stp-root-address"
      "stp-root-cost"
      "stp-root-priority"
      "stp-sender-address"
      "stp-sender-priority"
      "stp-type"
      "tls-host"
      "vlan-encap"
      "vlan-id"
      "vlan-priority"
    ];
  }
  {
    path = "/interface bridge filter";
    kind = "list";
    attrs = [
      "802.3-sap"
      "802.3-type"
      "action"
      "arp-dst-address"
      "arp-dst-mac-address"
      "arp-gratuitous"
      "arp-hardware-type"
      "arp-opcode"
      "arp-packet-type"
      "arp-src-address"
      "arp-src-mac-address"
      "chain"
      "comment"
      "copy-from"
      "disabled"
      "dst-address"
      "dst-address6"
      "dst-mac-address"
      "dst-port"
      "in-bridge"
      "in-bridge-list"
      "in-interface"
      "in-interface-list"
      "ingress-priority"
      "ip-protocol"
      "jump-target"
      "limit"
      "log"
      "log-prefix"
      "mac-protocol"
      "new-packet-mark"
      "new-priority"
      "out-bridge"
      "out-bridge-list"
      "out-interface"
      "out-interface-list"
      "packet-mark"
      "packet-type"
      "passthrough"
      "place-before"
      "src-address"
      "src-address6"
      "src-mac-address"
      "src-port"
      "stp-flags"
      "stp-forward-delay"
      "stp-hello-time"
      "stp-max-age"
      "stp-msg-age"
      "stp-port"
      "stp-root-address"
      "stp-root-cost"
      "stp-root-priority"
      "stp-sender-address"
      "stp-sender-priority"
      "stp-type"
      "tls-host"
      "vlan-encap"
      "vlan-id"
      "vlan-priority"
    ];
  }
  {
    path = "/interface bridge host";
    kind = "list";
    attrs = [
      "bridge"
      "comment"
      "copy-from"
      "disabled"
      "interface"
      "mac-address"
      "vid"
    ];
  }
  {
    path = "/interface bridge mdb";
    kind = "list";
    attrs = [
      "bridge"
      "comment"
      "copy-from"
      "disabled"
      "group"
      "interface"
      "vid"
    ];
  }
  {
    path = "/interface bridge msti";
    kind = "list";
    attrs = [
      "bridge"
      "comment"
      "copy-from"
      "disabled"
      "identifier"
      "priority"
      "vlan-mapping"
    ];
  }
  {
    path = "/interface bridge nat";
    kind = "list";
    attrs = [
      "802.3-sap"
      "802.3-type"
      "action"
      "arp-dst-address"
      "arp-dst-mac-address"
      "arp-gratuitous"
      "arp-hardware-type"
      "arp-opcode"
      "arp-packet-type"
      "arp-src-address"
      "arp-src-mac-address"
      "chain"
      "comment"
      "copy-from"
      "disabled"
      "dst-address"
      "dst-address6"
      "dst-mac-address"
      "dst-port"
      "in-bridge"
      "in-bridge-list"
      "in-interface"
      "in-interface-list"
      "ingress-priority"
      "ip-protocol"
      "jump-target"
      "limit"
      "log"
      "log-prefix"
      "mac-protocol"
      "new-packet-mark"
      "new-priority"
      "out-bridge"
      "out-bridge-list"
      "out-interface"
      "out-interface-list"
      "packet-mark"
      "packet-type"
      "passthrough"
      "place-before"
      "src-address"
      "src-address6"
      "src-mac-address"
      "src-port"
      "stp-flags"
      "stp-forward-delay"
      "stp-hello-time"
      "stp-max-age"
      "stp-msg-age"
      "stp-port"
      "stp-root-address"
      "stp-root-cost"
      "stp-root-priority"
      "stp-sender-address"
      "stp-sender-priority"
      "stp-type"
      "tls-host"
      "to-arp-reply-mac-address"
      "to-dst-mac-address"
      "to-src-mac-address"
      "vlan-encap"
      "vlan-id"
      "vlan-priority"
    ];
  }
  {
    path = "/interface bridge port";
    kind = "list";
    attrs = [
      "auto-isolate"
      "bpdu-guard"
      "bridge"
      "broadcast-flood"
      "comment"
      "copy-from"
      "disabled"
      "edge"
      "fast-leave"
      "frame-types"
      "horizon"
      "hw"
      "ingress-filtering"
      "interface"
      "internal-path-cost"
      "learn"
      "multicast-router"
      "mvrp-applicant-state"
      "mvrp-registrar-state"
      "neigh-suppress"
      "path-cost"
      "place-before"
      "point-to-point"
      "priority"
      "pvid"
      "restricted-role"
      "restricted-tcn"
      "sys-bundleid"
      "tag-stacking"
      "trusted"
      "trusted-arp"
      "trusted-dhcpv6"
      "trusted-ra"
      "unknown-multicast-flood"
      "unknown-unicast-flood"
    ];
  }
  {
    path = "/interface bridge port mst-override";
    kind = "list";
    attrs = [
      "comment"
      "copy-from"
      "disabled"
      "identifier"
      "interface"
      "internal-path-cost"
      "priority"
    ];
  }
  {
    path = "/interface bridge settings";
    kind = "object";
    attrs = [
      "allow-fast-path"
      "use-ip-firewall"
      "use-ip-firewall-for-pppoe"
      "use-ip-firewall-for-vlan"
    ];
  }
  {
    path = "/interface bridge vlan";
    kind = "list";
    attrs = [
      "bridge"
      "comment"
      "copy-from"
      "disabled"
      "mvrp-forbidden"
      "sys-bundleid"
      "tagged"
      "untagged"
      "vlan-ids"
    ];
  }
  {
    path = "/interface detect-internet";
    kind = "object";
    attrs = [
      "detect-interface-list"
      "internet-interface-list"
      "lan-interface-list"
      "request-interval"
      "wan-interface-list"
    ];
  }
  {
    path = "/interface dot1x client";
    kind = "list";
    attrs = [
      "anon-identity"
      "certificate"
      "comment"
      "copy-from"
      "disabled"
      "eap-methods"
      "identity"
      "interface"
      "password"
    ];
  }
  {
    path = "/interface dot1x server";
    kind = "list";
    attrs = [
      "accounting"
      "auth-timeout"
      "auth-types"
      "comment"
      "copy-from"
      "disabled"
      "guest-vlan-id"
      "interface"
      "interim-update"
      "mac-auth-mode"
      "radius-mac-format"
      "reauth-period"
      "reauth-timeout"
      "reject-vlan-id"
      "retrans-timeout"
      "server-fail-vlan-id"
    ];
  }
  {
    path = "/interface dot1x server active";
    kind = "list";
    attrs = [
      "copy-from"
    ];
  }
  {
    path = "/interface eoip";
    kind = "list";
    attrs = [
      "allow-fast-path"
      "arp"
      "arp-accept"
      "arp-timeout"
      "clamp-tcp-mss"
      "comment"
      "copy-from"
      "disabled"
      "dont-fragment"
      "dscp"
      "ipsec-secret"
      "keepalive"
      "local-address"
      "loop-protect"
      "loop-protect-disable-time"
      "loop-protect-send-interval"
      "mac-address"
      "mtu"
      "name"
      "remote-address"
      "tunnel-id"
    ];
  }
  {
    path = "/interface eoipv6";
    kind = "list";
    attrs = [
      "arp"
      "arp-accept"
      "arp-timeout"
      "clamp-tcp-mss"
      "comment"
      "copy-from"
      "disabled"
      "dont-fragment"
      "dscp"
      "ipsec-secret"
      "keepalive"
      "local-address"
      "loop-protect"
      "loop-protect-disable-time"
      "loop-protect-send-interval"
      "mac-address"
      "mtu"
      "name"
      "remote-address"
      "tunnel-id"
    ];
  }
  {
    path = "/interface ethernet";
    kind = "object";
    attrs = [
      "advertise"
      "arp"
      "arp-accept"
      "arp-timeout"
      "auto-negotiation"
      "cable-settings"
      "combo-mode"
      "comment"
      "disable-running-check"
      "disabled"
      "fec-mode"
      "l2mtu"
      "loop-protect"
      "loop-protect-disable-time"
      "loop-protect-send-interval"
      "mac-address"
      "mdix-enable"
      "mtu"
      "name"
      "numbers"
      "orig-mac-address"
      "rx-flow-control"
      "sfp-ignore-rx-los"
      "sfp-rate-select"
      "sfp-shutdown-temperature"
      "speed"
      "tx-flow-control"
    ];
  }
  {
    path = "/interface ethernet pon";
    kind = "object";
    attrs = [
      "name"
      "numbers"
      "olt-max-mtu"
      "status"
    ];
  }
  {
    path = "/interface gre";
    kind = "list";
    attrs = [
      "allow-fast-path"
      "clamp-tcp-mss"
      "comment"
      "copy-from"
      "disabled"
      "dont-fragment"
      "dscp"
      "ipsec-secret"
      "keepalive"
      "local-address"
      "mtu"
      "name"
      "remote-address"
    ];
  }
  {
    path = "/interface gre6";
    kind = "list";
    attrs = [
      "clamp-tcp-mss"
      "comment"
      "copy-from"
      "disabled"
      "dont-fragment"
      "dscp"
      "ipsec-secret"
      "keepalive"
      "local-address"
      "mtu"
      "name"
      "remote-address"
    ];
  }
  {
    path = "/interface ipip";
    kind = "list";
    attrs = [
      "allow-fast-path"
      "clamp-tcp-mss"
      "comment"
      "copy-from"
      "disabled"
      "dont-fragment"
      "dscp"
      "ipsec-secret"
      "keepalive"
      "local-address"
      "mtu"
      "name"
      "remote-address"
    ];
  }
  {
    path = "/interface ipipv6";
    kind = "list";
    attrs = [
      "clamp-tcp-mss"
      "comment"
      "copy-from"
      "disabled"
      "dont-fragment"
      "dscp"
      "ipsec-secret"
      "keepalive"
      "local-address"
      "mtu"
      "name"
      "remote-address"
    ];
  }
  {
    path = "/interface l2tp-client";
    kind = "list";
    attrs = [
      "add-default-route"
      "allow"
      "allow-fast-path"
      "comment"
      "connect-to"
      "copy-from"
      "default-route-distance"
      "dial-on-demand"
      "disabled"
      "ipsec-secret"
      "keepalive-timeout"
      "l2tp-proto-version"
      "l2tpv3-circuit-id"
      "l2tpv3-cookie-length"
      "l2tpv3-digest-hash"
      "max-mru"
      "max-mtu"
      "mrru"
      "name"
      "password"
      "profile"
      "random-source-port"
      "src-address"
      "use-ipsec"
      "use-peer-dns"
      "user"
    ];
  }
  {
    path = "/interface l2tp-ether";
    kind = "list";
    attrs = [
      "allow-fast-path"
      "circuit-id"
      "comment"
      "connect-to"
      "cookie-length"
      "copy-from"
      "digest-hash"
      "disabled"
      "ipsec-secret"
      "l2tp-proto-version"
      "local-address"
      "local-session-id"
      "local-tunnel-id"
      "mac-address"
      "mtu"
      "name"
      "peer-cookie"
      "remote-session-id"
      "remote-tunnel-id"
      "send-cookie"
      "unmanaged-mode"
      "use-ipsec"
      "use-l2-specific-sublayer"
    ];
  }
  {
    path = "/interface l2tp-server";
    kind = "list";
    attrs = [
      "comment"
      "copy-from"
      "disabled"
      "name"
      "user"
    ];
  }
  {
    path = "/interface l2tp-server server";
    kind = "object";
    attrs = [
      "accept-proto-version"
      "accept-pseudowire-type"
      "allow-fast-path"
      "authentication"
      "caller-id-type"
      "default-profile"
      "enabled"
      "ipsec-secret"
      "keepalive-timeout"
      "l2tpv3-circuit-id"
      "l2tpv3-cookie-length"
      "l2tpv3-digest-hash"
      "l2tpv3-ether-interface-list"
      "max-mru"
      "max-mtu"
      "max-sessions"
      "mrru"
      "one-session-per-host"
      "use-ipsec"
    ];
    # multi-value: written as a list in the typed menu
    lists = [
      "authentication"
    ];
  }
  {
    path = "/interface list";
    kind = "list";
    attrs = [
      "comment"
      "copy-from"
      "exclude"
      "include"
      "name"
    ];
    # multi-value: written as a list in the typed menu (device type only)
    lists = [
      "exclude"
      "include"
    ];
  }
  {
    path = "/interface list member";
    kind = "list";
    attrs = [
      "comment"
      "copy-from"
      "disabled"
      "interface"
      "list"
    ];
  }
  {
    path = "/interface lte";
    kind = "object";
    attrs = [
      "allow-roaming"
      "apn-profiles"
      "band"
      "comment"
      "disabled"
      "modem-init"
      "mtu"
      "name"
      "network-mode"
      "nr-band"
      "numbers"
      "operator"
      "pin"
      "sms-protocol"
      "sms-read"
    ];
  }
  {
    path = "/interface lte apn";
    kind = "list";
    attrs = [
      "add-default-route"
      "apn"
      "authentication"
      "comment"
      "copy-from"
      "default-route-distance"
      "ip-type"
      "ipv6-interface"
      "name"
      "passthrough-interface"
      "passthrough-mac"
      "passthrough-subnet-size"
      "password"
      "use-network-apn"
      "use-peer-dns"
      "user"
    ];
  }
  {
    path = "/interface lte settings";
    kind = "object";
    attrs = [
      "control-ifnum"
      "delay-start"
      "esim-channel"
      "extended-logging"
      "firmware-path"
      "ignore-at-timeout"
      "imsi-override"
      "limit-mbim-ext2"
      "link-recovery-timer"
      "mode"
      "old-multiapn"
      "use-ra-for-ipv6-params"
    ];
  }
  {
    path = "/interface macsec";
    kind = "list";
    attrs = [
      "cak"
      "ckn"
      "comment"
      "copy-from"
      "disabled"
      "hw"
      "interface"
      "mtu"
      "name"
      "profile"
    ];
  }
  {
    path = "/interface macsec profile";
    kind = "list";
    attrs = [
      "ciphers"
      "copy-from"
      "name"
      "server-priority"
    ];
    # multi-value: written as a list in the typed menu (device type only)
    lists = [
      "ciphers"
    ];
  }
  {
    path = "/interface macvlan";
    kind = "list";
    attrs = [
      "arp"
      "arp-accept"
      "arp-timeout"
      "comment"
      "copy-from"
      "disabled"
      "interface"
      "loop-protect"
      "loop-protect-disable-time"
      "loop-protect-send-interval"
      "mac-address"
      "mode"
      "mtu"
      "name"
    ];
  }
  {
    path = "/interface mesh";
    kind = "list";
    attrs = [
      "admin-mac"
      "arp"
      "arp-timeout"
      "auto-mac"
      "comment"
      "copy-from"
      "disabled"
      "hwmp-default-hoplimit"
      "hwmp-prep-lifetime"
      "hwmp-preq-destination-only"
      "hwmp-preq-reply-and-forward"
      "hwmp-preq-retries"
      "hwmp-preq-waiting-time"
      "hwmp-rann-interval"
      "hwmp-rann-lifetime"
      "hwmp-rann-propagation-delay"
      "mesh-portal"
      "mtu"
      "name"
      "reoptimize-paths"
    ];
  }
  {
    path = "/interface mesh port";
    kind = "list";
    attrs = [
      "comment"
      "copy-from"
      "disabled"
      "hello-interval"
      "interface"
      "mesh"
      "path-cost"
      "port-type"
    ];
  }
  {
    path = "/interface ovpn-client";
    kind = "list";
    attrs = [
      "add-default-route"
      "auth"
      "certificate"
      "cipher"
      "comment"
      "connect-to"
      "copy-from"
      "disabled"
      "disconnect-notify"
      "mac-address"
      "max-mtu"
      "mode"
      "name"
      "password"
      "port"
      "profile"
      "protocol"
      "route-nopull"
      "tls-version"
      "use-peer-dns"
      "user"
      "verify-server-certificate"
    ];
  }
  {
    path = "/interface ovpn-server";
    kind = "list";
    attrs = [
      "comment"
      "copy-from"
      "disabled"
      "name"
      "user"
    ];
  }
  {
    path = "/interface ovpn-server server";
    kind = "list";
    attrs = [
      "auth"
      "certificate"
      "cipher"
      "comment"
      "copy-from"
      "default-profile"
      "disabled"
      "enable-tun-ipv6"
      "ipv6-prefix-len"
      "keepalive-timeout"
      "mac-address"
      "max-mtu"
      "mode"
      "name"
      "netmask"
      "port"
      "protocol"
      "push-routes"
      "push-routes-ipv6"
      "redirect-gateway"
      "reneg-sec"
      "require-client-certificate"
      "tls-version"
      "tun-server-ipv6"
      "user-auth-method"
      "vrf"
    ];
    # multi-value: written as a list in the typed menu
    lists = [
      "auth"
      "cipher"
      "push-routes"
      "redirect-gateway"
    ];
  }
  {
    path = "/interface ppp-client";
    kind = "list";
    attrs = [
      "add-default-route"
      "allow"
      "apn"
      "comment"
      "copy-from"
      "data-channel"
      "default-route-distance"
      "dial-command"
      "dial-on-demand"
      "disabled"
      "info-channel"
      "keepalive-timeout"
      "max-mru"
      "max-mtu"
      "modem-init"
      "mrru"
      "name"
      "network-mode"
      "null-modem"
      "password"
      "phone"
      "pin"
      "port"
      "profile"
      "remote-address"
      "use-peer-dns"
      "user"
    ];
    # multi-value: written as a list in the typed menu
    lists = [
      "allow"
    ];
  }
  {
    path = "/interface ppp-client settings";
    kind = "object";
    attrs = [
      "extended-logging"
    ];
  }
  {
    path = "/interface ppp-server";
    kind = "list";
    attrs = [
      "authentication"
      "comment"
      "copy-from"
      "data-channel"
      "disabled"
      "max-mru"
      "max-mtu"
      "modem-init"
      "mrru"
      "name"
      "null-modem"
      "port"
      "profile"
      "ring-count"
    ];
    # multi-value: written as a list in the typed menu
    lists = [
      "authentication"
    ];
  }
  {
    path = "/interface pppoe-client";
    kind = "list";
    attrs = [
      "ac-name"
      "add-default-route"
      "allow"
      "comment"
      "copy-from"
      "default-route-distance"
      "dial-on-demand"
      "disabled"
      "host-uniq"
      "interface"
      "keepalive-timeout"
      "max-mru"
      "max-mtu"
      "mrru"
      "name"
      "password"
      "profile"
      "service-name"
      "use-peer-dns"
      "user"
    ];
  }
  {
    path = "/interface pppoe-server";
    kind = "list";
    attrs = [
      "comment"
      "copy-from"
      "disabled"
      "name"
      "service"
      "user"
    ];
  }
  {
    path = "/interface pppoe-server server";
    kind = "list";
    attrs = [
      "accept-empty-service"
      "accept-untagged"
      "authentication"
      "comment"
      "copy-from"
      "default-profile"
      "disabled"
      "interface"
      "keepalive-timeout"
      "max-mru"
      "max-mtu"
      "max-sessions"
      "mrru"
      "one-session-per-host"
      "pado-delay"
      "pppoe-over-vlan-range"
      "service-name"
    ];
  }
  {
    path = "/interface pptp-client";
    kind = "list";
    attrs = [
      "add-default-route"
      "allow"
      "comment"
      "connect-to"
      "copy-from"
      "default-route-distance"
      "dial-on-demand"
      "disabled"
      "keepalive-timeout"
      "max-mru"
      "max-mtu"
      "mrru"
      "name"
      "password"
      "profile"
      "use-peer-dns"
      "user"
    ];
  }
  {
    path = "/interface pptp-server";
    kind = "list";
    attrs = [
      "comment"
      "copy-from"
      "disabled"
      "name"
      "user"
    ];
  }
  {
    path = "/interface pptp-server server";
    kind = "object";
    attrs = [
      "authentication"
      "default-profile"
      "enabled"
      "keepalive-timeout"
      "max-mru"
      "max-mtu"
      "mrru"
    ];
    # multi-value: written as a list in the typed menu
    lists = [
      "authentication"
    ];
  }
  {
    path = "/interface sstp-client";
    kind = "list";
    attrs = [
      "add-default-route"
      "add-sni"
      "authentication"
      "certificate"
      "ciphers"
      "comment"
      "connect-to"
      "copy-from"
      "default-route-distance"
      "dial-on-demand"
      "disabled"
      "http-proxy"
      "keepalive-timeout"
      "max-mru"
      "max-mtu"
      "mrru"
      "name"
      "password"
      "pfs"
      "port"
      "profile"
      "proxy-port"
      "tls-version"
      "user"
      "verify-server-address-from-certificate"
      "verify-server-certificate"
    ];
  }
  {
    path = "/interface sstp-server";
    kind = "list";
    attrs = [
      "comment"
      "copy-from"
      "disabled"
      "name"
      "user"
    ];
  }
  {
    path = "/interface sstp-server server";
    kind = "object";
    attrs = [
      "authentication"
      "certificate"
      "ciphers"
      "default-profile"
      "enabled"
      "keepalive-timeout"
      "max-mru"
      "max-mtu"
      "mrru"
      "pfs"
      "port"
      "tls-version"
      "verify-client-certificate"
    ];
    # multi-value: written as a list in the typed menu
    lists = [
      "authentication"
      "ciphers"
    ];
  }
  {
    path = "/interface vlan";
    kind = "list";
    attrs = [
      "arp"
      "arp-accept"
      "arp-timeout"
      "comment"
      "copy-from"
      "disabled"
      "forced-mac-address"
      "interface"
      "loop-protect"
      "loop-protect-disable-time"
      "loop-protect-send-interval"
      "mtu"
      "mvrp"
      "name"
      "use-service-tag"
      "vlan-id"
    ];
  }
  {
    path = "/interface vpls";
    kind = "list";
    attrs = [
      "arp"
      "arp-timeout"
      "bridge"
      "bridge-cost"
      "bridge-horizon"
      "bridge-pvid"
      "cisco-static-id"
      "comment"
      "copy-from"
      "disable-running-check"
      "disabled"
      "mac-address"
      "mtu"
      "name"
      "peer"
      "pw-control-word"
      "pw-l2mtu"
      "pw-type"
      "vpls-id"
    ];
  }
  {
    path = "/interface vrrp";
    kind = "list";
    attrs = [
      "arp"
      "arp-timeout"
      "authentication"
      "comment"
      "connection-tracking-mode"
      "connection-tracking-port"
      "copy-from"
      "disabled"
      "group-authority"
      "group-master"
      "interface"
      "interval"
      "name"
      "on-backup"
      "on-fail"
      "on-master"
      "password"
      "preemption-mode"
      "priority"
      "remote-address"
      "sync-connection-tracking"
      "v3-checksum-as-v2"
      "v3-protocol"
      "version"
      "vrid"
    ];
  }
  {
    path = "/interface vxlan";
    kind = "list";
    attrs = [
      "allow-fast-path"
      "arp"
      "arp-accept"
      "arp-timeout"
      "bridge"
      "bridge-pvid"
      "checksum"
      "comment"
      "copy-from"
      "disabled"
      "dont-fragment"
      "group"
      "hw"
      "interface"
      "learning"
      "local-address"
      "loop-protect"
      "loop-protect-disable-time"
      "loop-protect-send-interval"
      "mac-address"
      "max-fdb-size"
      "mtu"
      "name"
      "port"
      "rem-csum"
      "ttl"
      "vni"
      "vtep-vrf"
      "vteps-ip-version"
    ];
  }
  {
    path = "/interface vxlan vteps";
    kind = "list";
    attrs = [
      "comment"
      "copy-from"
      "disabled"
      "interface"
      "remote-ip"
    ];
  }
  {
    path = "/interface wifi";
    kind = "list";
    attrs = [
      "aaa"
      "aaa.called-format"
      "aaa.calling-format"
      "aaa.interim-update"
      "aaa.mac-caching"
      "aaa.nas-identifier"
      "aaa.password-format"
      "aaa.username-format"
      "arp"
      "arp-timeout"
      "channel"
      "channel.afc"
      "channel.afc-auth-token"
      "channel.afc-cert-check"
      "channel.afc-cert-id"
      "channel.afc-debug-resp"
      "channel.afc-dynamic-policy-mbm"
      "channel.afc-latitude"
      "channel.afc-longitude"
      "channel.afc-policy"
      "channel.afc-product-id"
      "channel.afc-registration-url"
      "channel.afc-request-url"
      "channel.afc-secret"
      "channel.afc-serial"
      "channel.band"
      "channel.deprioritize-unii-3-4"
      "channel.frequency"
      "channel.preamble-puncturing"
      "channel.puncture-frequencies"
      "channel.reselect-interval"
      "channel.reselect-time"
      "channel.secondary-frequency"
      "channel.skip-dfs-channels"
      "channel.width"
      "comment"
      "configuration"
      "configuration.antenna-gain"
      "configuration.atpc"
      "configuration.atpc-rssi-threshold"
      "configuration.beacon-interval"
      "configuration.chains"
      "configuration.country"
      "configuration.debug.flags"
      "configuration.distance"
      "configuration.dtim-period"
      "configuration.hide-ssid"
      "configuration.hw-protection-mode"
      "configuration.installation"
      "configuration.manager"
      "configuration.max-clients"
      "configuration.mode"
      "configuration.multicast-enhance"
      "configuration.qos-classifier"
      "configuration.ssid"
      "configuration.station-roaming"
      "configuration.tx-chains"
      "configuration.tx-power"
      "copy-from"
      "datapath"
      "datapath.batman-adv"
      "datapath.bridge"
      "datapath.bridge-cost"
      "datapath.bridge-horizon"
      "datapath.client-isolation"
      "datapath.interface-list"
      "datapath.traffic-processing"
      "datapath.vlan-id"
      "disable-running-check"
      "disabled"
      "interworking"
      "interworking.3gpp-info"
      "interworking.3gpp-info-raw"
      "interworking.authentication-types"
      "interworking.connection-capabilities"
      "interworking.domain-names"
      "interworking.esr"
      "interworking.hessid"
      "interworking.hotspot20"
      "interworking.hotspot20-dgaf"
      "interworking.internet"
      "interworking.ipv4-availability"
      "interworking.ipv6-availability"
      "interworking.network-type"
      "interworking.operational-classes"
      "interworking.operator-names"
      "interworking.realms"
      "interworking.realms-raw"
      "interworking.roaming-ois"
      "interworking.uesa"
      "interworking.venue"
      "interworking.venue-names"
      "interworking.wan-at-capacity"
      "interworking.wan-downlink"
      "interworking.wan-downlink-load"
      "interworking.wan-measurement-duration"
      "interworking.wan-status"
      "interworking.wan-symmetric"
      "interworking.wan-uplink"
      "interworking.wan-uplink-load"
      "l2mtu"
      "mac-address"
      "master-interface"
      "mld-interface"
      "mld-name"
      "mtu"
      "name"
      "radio-mac"
      "security"
      "security.authentication-types"
      "security.beacon-protection"
      "security.connect-group"
      "security.connect-priority"
      "security.dh-groups"
      "security.disable-pmkid"
      "security.dpp-bootstrap-info"
      "security.dpp-connector"
      "security.dpp-csign"
      "security.dpp-pmk"
      "security.dpp-pmkid"
      "security.dpp-ppkey"
      "security.dpp-priv-proto-key"
      "security.eap-accounting"
      "security.eap-anonymous-identity"
      "security.eap-certificate-mode"
      "security.eap-methods"
      "security.eap-password"
      "security.eap-tls-certificate"
      "security.eap-username"
      "security.encryption"
      "security.ft"
      "security.ft-mobility-domain"
      "security.ft-nas-identifier"
      "security.ft-over-ds"
      "security.ft-preserve-vlanid"
      "security.ft-r0-key-lifetime"
      "security.ft-reassociation-deadline"
      "security.group-encryption"
      "security.group-key-update"
      "security.management-encryption"
      "security.management-protection"
      "security.multi-passphrase-group"
      "security.owe-transition-interface"
      "security.passphrase"
      "security.sae-anti-clogging-threshold"
      "security.sae-max-failure-rate"
      "security.sae-pwe"
      "security.wps"
      "steering"
      "steering.2g-probe-delay"
      "steering.neighbor-group"
      "steering.probe-delay-interval"
      "steering.probe-delay-numprobes"
      "steering.probe-delay-snr"
      "steering.rrm"
      "steering.transition-request-count"
      "steering.transition-request-period"
      "steering.transition-threshold"
      "steering.transition-threshold-time"
      "steering.transition-time"
      "steering.wnm"
      "test.dfs.duty-cycle"
      "test.dfs.ignore-cac"
      "test.dfs.ignore-radar"
      "test.he.dlofdma"
      "test.he.ulmumimo"
      "test.he.ulofdma"
      "test.pktloss-filter"
      "test.rts-mode"
      "test.rts-threshold"
    ];
  }
  {
    path = "/interface wifi aaa";
    kind = "list";
    attrs = [
      "called-format"
      "calling-format"
      "comment"
      "copy-from"
      "disabled"
      "interim-update"
      "mac-caching"
      "name"
      "nas-identifier"
      "password-format"
      "username-format"
    ];
  }
  {
    path = "/interface wifi access-list";
    kind = "list";
    attrs = [
      "action"
      "allow-signal-out-of-range"
      "client-isolation"
      "comment"
      "copy-from"
      "days"
      "disabled"
      "interface"
      "mac-address"
      "mac-address-mask"
      "multi-passphrase-group"
      "passphrase"
      "place-before"
      "radius-accounting"
      "signal-range"
      "ssid-regexp"
      "time"
      "vlan-id"
    ];
  }
  {
    path = "/interface wifi cap";
    kind = "object";
    attrs = [
      "caps-man-addresses"
      "caps-man-certificate-common-names"
      "caps-man-names"
      "certificate"
      "discovery-interfaces"
      "enabled"
      "lock-to-caps-man"
      "mld-datapath"
      "mld-static"
      "slaves-datapath"
      "slaves-static"
    ];
    # multi-value: written as a list in the typed menu
    lists = [
      "caps-man-addresses"
      "caps-man-certificate-common-names"
      "caps-man-names"
      "discovery-interfaces"
    ];
  }
  {
    path = "/interface wifi capsman";
    kind = "object";
    attrs = [
      "ca-certificate"
      "certificate"
      "enabled"
      "interfaces"
      "package-path"
      "require-peer-certificate"
      "upgrade-policy"
    ];
    # multi-value: written as a list in the typed menu
    lists = [
      "interfaces"
    ];
  }
  {
    path = "/interface wifi channel";
    kind = "list";
    attrs = [
      "afc"
      "afc-auth-token"
      "afc-cert-check"
      "afc-cert-id"
      "afc-debug-resp"
      "afc-dynamic-policy-mbm"
      "afc-latitude"
      "afc-longitude"
      "afc-policy"
      "afc-product-id"
      "afc-registration-url"
      "afc-request-url"
      "afc-secret"
      "afc-serial"
      "band"
      "comment"
      "copy-from"
      "deprioritize-unii-3-4"
      "disabled"
      "frequency"
      "name"
      "preamble-puncturing"
      "puncture-frequencies"
      "reselect-interval"
      "reselect-time"
      "secondary-frequency"
      "skip-dfs-channels"
      "width"
    ];
    # multi-value: written as a list in the typed menu
    lists = [
      "puncture-frequencies"
      "secondary-frequency"
    ];
  }
  {
    path = "/interface wifi configuration";
    kind = "list";
    attrs = [
      "aaa"
      "aaa.called-format"
      "aaa.calling-format"
      "aaa.interim-update"
      "aaa.mac-caching"
      "aaa.nas-identifier"
      "aaa.password-format"
      "aaa.username-format"
      "antenna-gain"
      "atpc"
      "atpc-rssi-threshold"
      "beacon-interval"
      "chains"
      "channel"
      "channel.afc"
      "channel.afc-auth-token"
      "channel.afc-cert-check"
      "channel.afc-cert-id"
      "channel.afc-debug-resp"
      "channel.afc-dynamic-policy-mbm"
      "channel.afc-latitude"
      "channel.afc-longitude"
      "channel.afc-policy"
      "channel.afc-product-id"
      "channel.afc-registration-url"
      "channel.afc-request-url"
      "channel.afc-secret"
      "channel.afc-serial"
      "channel.band"
      "channel.deprioritize-unii-3-4"
      "channel.frequency"
      "channel.preamble-puncturing"
      "channel.puncture-frequencies"
      "channel.reselect-interval"
      "channel.reselect-time"
      "channel.secondary-frequency"
      "channel.skip-dfs-channels"
      "channel.width"
      "comment"
      "copy-from"
      "country"
      "datapath"
      "datapath.batman-adv"
      "datapath.bridge"
      "datapath.bridge-cost"
      "datapath.bridge-horizon"
      "datapath.client-isolation"
      "datapath.interface-list"
      "datapath.traffic-processing"
      "datapath.vlan-id"
      "debug.flags"
      "disabled"
      "distance"
      "dtim-period"
      "hide-ssid"
      "hw-protection-mode"
      "installation"
      "interworking"
      "interworking.3gpp-info"
      "interworking.3gpp-info-raw"
      "interworking.authentication-types"
      "interworking.connection-capabilities"
      "interworking.domain-names"
      "interworking.esr"
      "interworking.hessid"
      "interworking.hotspot20"
      "interworking.hotspot20-dgaf"
      "interworking.internet"
      "interworking.ipv4-availability"
      "interworking.ipv6-availability"
      "interworking.network-type"
      "interworking.operational-classes"
      "interworking.operator-names"
      "interworking.realms"
      "interworking.realms-raw"
      "interworking.roaming-ois"
      "interworking.uesa"
      "interworking.venue"
      "interworking.venue-names"
      "interworking.wan-at-capacity"
      "interworking.wan-downlink"
      "interworking.wan-downlink-load"
      "interworking.wan-measurement-duration"
      "interworking.wan-status"
      "interworking.wan-symmetric"
      "interworking.wan-uplink"
      "interworking.wan-uplink-load"
      "manager"
      "max-clients"
      "mode"
      "multicast-enhance"
      "name"
      "qos-classifier"
      "security"
      "security.authentication-types"
      "security.beacon-protection"
      "security.connect-group"
      "security.connect-priority"
      "security.dh-groups"
      "security.disable-pmkid"
      "security.dpp-bootstrap-info"
      "security.dpp-connector"
      "security.dpp-csign"
      "security.dpp-pmk"
      "security.dpp-pmkid"
      "security.dpp-ppkey"
      "security.dpp-priv-proto-key"
      "security.eap-accounting"
      "security.eap-anonymous-identity"
      "security.eap-certificate-mode"
      "security.eap-methods"
      "security.eap-password"
      "security.eap-tls-certificate"
      "security.eap-username"
      "security.encryption"
      "security.ft"
      "security.ft-mobility-domain"
      "security.ft-nas-identifier"
      "security.ft-over-ds"
      "security.ft-preserve-vlanid"
      "security.ft-r0-key-lifetime"
      "security.ft-reassociation-deadline"
      "security.group-encryption"
      "security.group-key-update"
      "security.management-encryption"
      "security.management-protection"
      "security.multi-passphrase-group"
      "security.owe-transition-interface"
      "security.passphrase"
      "security.sae-anti-clogging-threshold"
      "security.sae-max-failure-rate"
      "security.sae-pwe"
      "security.wps"
      "ssid"
      "station-roaming"
      "steering"
      "steering.2g-probe-delay"
      "steering.neighbor-group"
      "steering.probe-delay-interval"
      "steering.probe-delay-numprobes"
      "steering.probe-delay-snr"
      "steering.rrm"
      "steering.transition-request-count"
      "steering.transition-request-period"
      "steering.transition-threshold"
      "steering.transition-threshold-time"
      "steering.transition-time"
      "steering.wnm"
      "tx-chains"
      "tx-power"
    ];
    # multi-value: written as a list in the typed menu
    lists = [
      "chains"
      "channel.puncture-frequencies"
      "channel.secondary-frequency"
      "debug.flags"
      "interworking.authentication-types"
      "interworking.connection-capabilities"
      "interworking.domain-names"
      "interworking.operational-classes"
      "interworking.operator-names"
      "interworking.realms"
      "interworking.roaming-ois"
      "interworking.venue-names"
      "security.authentication-types"
      "security.dh-groups"
      "security.eap-methods"
      "security.encryption"
      "steering.neighbor-group"
      "tx-chains"
    ];
  }
  {
    path = "/interface wifi dashboard settings";
    kind = "object";
    attrs = [
      "wifi-log-bytes"
      "wifi-log-time"
    ];
  }
  {
    path = "/interface wifi datapath";
    kind = "list";
    attrs = [
      "batman-adv"
      "bridge"
      "bridge-cost"
      "bridge-horizon"
      "client-isolation"
      "comment"
      "copy-from"
      "disabled"
      "interface-list"
      "name"
      "traffic-processing"
      "vlan-id"
    ];
  }
  {
    path = "/interface wifi dpp-bootstrap-info";
    kind = "list";
    attrs = [
      "channels"
      "comment"
      "copy-from"
      "curve"
      "disabled"
      "name"
      "qr-uri"
      "supported-curves"
      "type"
    ];
    # multi-value: written as a list in the typed menu
    lists = [
      "channels"
      "supported-curves"
    ];
  }
  {
    path = "/interface wifi easymesh";
    kind = "object";
    attrs = [
      "bhaul-configuration"
      "bridge"
      "dpp-onboarding"
      "enabled"
      "fhaul-configurations"
      "role"
    ];
  }
  {
    path = "/interface wifi interworking";
    kind = "list";
    attrs = [
      "3gpp-info"
      "3gpp-info-raw"
      "authentication-types"
      "comment"
      "connection-capabilities"
      "copy-from"
      "disabled"
      "domain-names"
      "esr"
      "hessid"
      "hotspot20"
      "hotspot20-dgaf"
      "internet"
      "ipv4-availability"
      "ipv6-availability"
      "name"
      "network-type"
      "operational-classes"
      "operator-names"
      "realms"
      "realms-raw"
      "roaming-ois"
      "uesa"
      "venue"
      "venue-names"
      "wan-at-capacity"
      "wan-downlink"
      "wan-downlink-load"
      "wan-measurement-duration"
      "wan-status"
      "wan-symmetric"
      "wan-uplink"
      "wan-uplink-load"
    ];
    # multi-value: written as a list in the typed menu
    lists = [
      "authentication-types"
      "connection-capabilities"
      "domain-names"
      "operational-classes"
      "operator-names"
      "realms"
      "roaming-ois"
      "venue-names"
    ];
  }
  {
    path = "/interface wifi network";
    kind = "list";
    attrs = [
      "aaa.called-format"
      "aaa.calling-format"
      "aaa.interim-update"
      "aaa.mac-caching"
      "aaa.nas-identifier"
      "aaa.password-format"
      "aaa.username-format"
      "beacon-interval"
      "comment"
      "copy-from"
      "datapath.batman-adv"
      "datapath.bridge"
      "datapath.bridge-cost"
      "datapath.bridge-horizon"
      "datapath.client-isolation"
      "datapath.interface-list"
      "datapath.traffic-processing"
      "datapath.vlan-id"
      "debug.flags"
      "disabled"
      "dtim-period"
      "hide-ssid"
      "hw-protection-mode"
      "interworking.3gpp-info"
      "interworking.3gpp-info-raw"
      "interworking.authentication-types"
      "interworking.connection-capabilities"
      "interworking.domain-names"
      "interworking.esr"
      "interworking.hessid"
      "interworking.hotspot20"
      "interworking.hotspot20-dgaf"
      "interworking.internet"
      "interworking.ipv4-availability"
      "interworking.ipv6-availability"
      "interworking.network-type"
      "interworking.operational-classes"
      "interworking.operator-names"
      "interworking.realms"
      "interworking.realms-raw"
      "interworking.roaming-ois"
      "interworking.uesa"
      "interworking.venue"
      "interworking.venue-names"
      "interworking.wan-at-capacity"
      "interworking.wan-downlink"
      "interworking.wan-downlink-load"
      "interworking.wan-measurement-duration"
      "interworking.wan-status"
      "interworking.wan-symmetric"
      "interworking.wan-uplink"
      "interworking.wan-uplink-load"
      "labels"
      "max-clients"
      "mlo"
      "mode"
      "multicast-enhance"
      "qos-classifier"
      "security.authentication-types"
      "security.beacon-protection"
      "security.connect-group"
      "security.connect-priority"
      "security.dh-groups"
      "security.disable-pmkid"
      "security.dpp-bootstrap-info"
      "security.dpp-connector"
      "security.dpp-csign"
      "security.dpp-pmk"
      "security.dpp-pmkid"
      "security.dpp-ppkey"
      "security.dpp-priv-proto-key"
      "security.eap-accounting"
      "security.eap-anonymous-identity"
      "security.eap-certificate-mode"
      "security.eap-methods"
      "security.eap-password"
      "security.eap-tls-certificate"
      "security.eap-username"
      "security.encryption"
      "security.ft"
      "security.ft-mobility-domain"
      "security.ft-nas-identifier"
      "security.ft-over-ds"
      "security.ft-preserve-vlanid"
      "security.ft-r0-key-lifetime"
      "security.ft-reassociation-deadline"
      "security.group-encryption"
      "security.group-key-update"
      "security.management-encryption"
      "security.management-protection"
      "security.multi-passphrase-group"
      "security.owe-transition-interface"
      "security.passphrase"
      "security.sae-anti-clogging-threshold"
      "security.sae-max-failure-rate"
      "security.sae-pwe"
      "security.wps"
      "ssid"
      "station-roaming"
      "steering.2g-probe-delay"
      "steering.neighbor-group"
      "steering.probe-delay-interval"
      "steering.probe-delay-numprobes"
      "steering.probe-delay-snr"
      "steering.rrm"
      "steering.transition-request-count"
      "steering.transition-request-period"
      "steering.transition-threshold"
      "steering.transition-threshold-time"
      "steering.transition-time"
      "steering.wnm"
      "sys-bundleid"
    ];
  }
  {
    path = "/interface wifi network radio";
    kind = "list";
    attrs = [
      "channel.afc"
      "channel.afc-auth-token"
      "channel.afc-cert-check"
      "channel.afc-cert-id"
      "channel.afc-debug-resp"
      "channel.afc-dynamic-policy-mbm"
      "channel.afc-latitude"
      "channel.afc-longitude"
      "channel.afc-policy"
      "channel.afc-product-id"
      "channel.afc-registration-url"
      "channel.afc-request-url"
      "channel.afc-secret"
      "channel.afc-serial"
      "channel.band"
      "channel.deprioritize-unii-3-4"
      "channel.frequency"
      "channel.preamble-puncturing"
      "channel.puncture-frequencies"
      "channel.reselect-interval"
      "channel.reselect-time"
      "channel.secondary-frequency"
      "channel.skip-dfs-channels"
      "channel.width"
      "comment"
      "configuration.antenna-gain"
      "configuration.atpc"
      "configuration.atpc-rssi-threshold"
      "configuration.chains"
      "configuration.country"
      "configuration.distance"
      "configuration.installation"
      "configuration.tx-chains"
      "configuration.tx-power"
      "copy-from"
      "disabled"
      "extra-labels"
      "labels"
      "security.authentication-types"
      "sys-bundleid"
    ];
  }
  {
    path = "/interface wifi provisioning";
    kind = "list";
    attrs = [
      "action"
      "address-ranges"
      "comment"
      "common-name-regexp"
      "copy-from"
      "disabled"
      "identity-regexp"
      "master-configuration"
      "multi-link-mode"
      "name-format"
      "place-before"
      "radio-mac"
      "slave-configurations"
      "slave-name-format"
      "supported-bands"
      "supported-hw-caps"
    ];
  }
  {
    path = "/interface wifi radio settings";
    kind = "object";
    attrs = [
      "external-antenna"
      "wifi-band"
    ];
  }
  {
    path = "/interface wifi security";
    kind = "list";
    attrs = [
      "authentication-types"
      "beacon-protection"
      "comment"
      "connect-group"
      "connect-priority"
      "copy-from"
      "dh-groups"
      "disable-pmkid"
      "disabled"
      "dpp-bootstrap-info"
      "dpp-connector"
      "dpp-csign"
      "dpp-pmk"
      "dpp-pmkid"
      "dpp-ppkey"
      "dpp-priv-proto-key"
      "eap-accounting"
      "eap-anonymous-identity"
      "eap-certificate-mode"
      "eap-methods"
      "eap-password"
      "eap-tls-certificate"
      "eap-username"
      "encryption"
      "ft"
      "ft-mobility-domain"
      "ft-nas-identifier"
      "ft-over-ds"
      "ft-preserve-vlanid"
      "ft-r0-key-lifetime"
      "ft-reassociation-deadline"
      "group-encryption"
      "group-key-update"
      "management-encryption"
      "management-protection"
      "multi-passphrase-group"
      "name"
      "owe-transition-interface"
      "passphrase"
      "sae-anti-clogging-threshold"
      "sae-max-failure-rate"
      "sae-pwe"
      "wps"
    ];
    # multi-value: written as a list in the typed menu
    lists = [
      "authentication-types"
      "dh-groups"
      "eap-methods"
      "encryption"
    ];
  }
  {
    path = "/interface wifi security multi-passphrase";
    kind = "list";
    attrs = [
      "comment"
      "copy-from"
      "disabled"
      "expires"
      "group"
      "isolation"
      "passphrase"
      "vlan-id"
    ];
  }
  {
    path = "/interface wifi steering";
    kind = "list";
    attrs = [
      "2g-probe-delay"
      "comment"
      "copy-from"
      "disabled"
      "name"
      "neighbor-group"
      "probe-delay-interval"
      "probe-delay-numprobes"
      "probe-delay-snr"
      "rrm"
      "transition-request-count"
      "transition-request-period"
      "transition-threshold"
      "transition-threshold-time"
      "transition-time"
      "wnm"
    ];
    # multi-value: written as a list in the typed menu
    lists = [
      "neighbor-group"
    ];
  }
  {
    path = "/interface wifi steering neighbor-group";
    kind = "object";
    attrs = [
      "comment"
      "numbers"
    ];
  }
  {
    path = "/interface wireguard";
    kind = "list";
    attrs = [
      "comment"
      "copy-from"
      "disabled"
      "listen-port"
      "mtu"
      "name"
      "private-key"
      "vrf"
    ];
  }
  {
    path = "/interface wireguard peers";
    kind = "list";
    attrs = [
      "allowed-address"
      "client-address"
      "client-allowed-address"
      "client-dns"
      "client-endpoint"
      "client-keepalive"
      "client-listen-port"
      "client-mtu"
      "comment"
      "copy-from"
      "disabled"
      "endpoint-address"
      "endpoint-port"
      "interface"
      "name"
      "persistent-keepalive"
      "place-before"
      "preshared-key"
      "private-key"
      "public-key"
      "responder"
    ];
    # multi-value: written as a list in the typed menu
    lists = [
      "allowed-address"
      "client-address"
      "client-allowed-address"
      "client-dns"
      "client-endpoint"
      "endpoint-address"
    ];
  }
  {
    path = "/interface xfrm";
    kind = "list";
    attrs = [
      "comment"
      "copy-from"
      "disabled"
      "mtu"
      "name"
    ];
  }
  {
    path = "/ip address";
    kind = "list";
    attrs = [
      "address"
      "broadcast"
      "comment"
      "copy-from"
      "disabled"
      "interface"
      "netmask"
      "network"
    ];
  }
  {
    path = "/ip arp";
    kind = "list";
    attrs = [
      "address"
      "comment"
      "copy-from"
      "disabled"
      "interface"
      "mac-address"
      "published"
    ];
  }
  {
    path = "/ip cloud";
    kind = "object";
    attrs = [
      "back-to-home-vpn"
      "ddns-enabled"
      "ddns-update-interval"
      "update-time"
      "vpn-prefer-relay-code"
    ];
  }
  {
    path = "/ip cloud advanced";
    kind = "object";
    attrs = [
      "use-local-address"
    ];
  }
  {
    path = "/ip cloud back-to-home-file";
    kind = "list";
    attrs = [
      "allow-uploads"
      "comment"
      "copy-from"
      "disabled"
      "expires"
      "path"
    ];
  }
  {
    path = "/ip cloud back-to-home-file settings";
    kind = "object";
    attrs = [
      "prefer-relay-code"
    ];
  }
  {
    path = "/ip cloud back-to-home-user";
    kind = "list";
    attrs = [
      "allow-lan"
      "client-allowed-address"
      "client-dns"
      "comment"
      "copy-from"
      "disabled"
      "expires"
      "file-access"
      "file-access-path"
      "name"
      "private-key"
      "public-key"
      "slot"
    ];
  }
  {
    path = "/ip dhcp-client";
    kind = "list";
    attrs = [
      "add-default-route"
      "allow-reconfigure"
      "check-gateway"
      "comment"
      "copy-from"
      "default-route-distance"
      "default-route-tables"
      "dhcp-options"
      "disabled"
      "dscp"
      "interface"
      "name"
      "script"
      "use-broadcast"
      "use-peer-dns"
      "use-peer-ntp"
      "vlan-priority"
    ];
    # multi-value: written as a list in the typed menu (device type only)
    lists = [
      "default-route-tables"
      "dhcp-options"
    ];
  }
  {
    path = "/ip dhcp-client option";
    kind = "list";
    attrs = [
      "code"
      "comment"
      "copy-from"
      "name"
      "value"
    ];
  }
  {
    path = "/ip dhcp-relay";
    kind = "list";
    attrs = [
      "add-relay-info"
      "copy-from"
      "delay-threshold"
      "dhcp-server"
      "dhcp-server-vrf"
      "disabled"
      "interface"
      "local-address"
      "local-address-as-src-ip"
      "name"
      "relay-info-remote-id"
    ];
  }
  {
    path = "/ip dhcp-server";
    kind = "list";
    attrs = [
      "add-arp"
      "add-dns-entries"
      "add-dns-entries-suffix"
      "address-lists"
      "address-pool"
      "allow-dual-stack-queue"
      "always-broadcast"
      "authoritative"
      "bootp-lease-time"
      "bootp-support"
      "client-mac-limit"
      "comment"
      "conflict-detection"
      "copy-from"
      "delay-threshold"
      "dhcp-option-set"
      "disabled"
      "dynamic-lease-identifiers"
      "insert-queue-before"
      "interface"
      "ipv6-only-preferred"
      "lease-script"
      "lease-time"
      "name"
      "parent-queue"
      "relay"
      "server-address"
      "support-broadband-tr101"
      "use-framed-as-classless"
      "use-radius"
      "use-reconfigure"
    ];
    # multi-value: written as a list in the typed menu
    lists = [
      "address-lists"
      "dynamic-lease-identifiers"
    ];
  }
  {
    path = "/ip dhcp-server alert";
    kind = "list";
    attrs = [
      "alert-timeout"
      "comment"
      "copy-from"
      "disabled"
      "interface"
      "on-alert"
      "valid-server"
    ];
  }
  {
    path = "/ip dhcp-server config";
    kind = "object";
    attrs = [
      "accounting"
      "interim-update"
      "radius-password"
      "store-leases-disk"
    ];
  }
  {
    path = "/ip dhcp-server lease";
    kind = "list";
    attrs = [
      "address"
      "address-lists"
      "agent-circuit-id"
      "agent-remote-id"
      "allow-dual-stack-queue"
      "always-broadcast"
      "block-access"
      "client-id"
      "comment"
      "copy-from"
      "dhcp-option"
      "dhcp-option-set"
      "disabled"
      "insert-queue-before"
      "lease-time"
      "mac-address"
      "parent-queue"
      "queue-type"
      "rate-limit"
      "routes"
      "server"
      "use-src-mac"
    ];
  }
  {
    path = "/ip dhcp-server matcher";
    kind = "list";
    attrs = [
      "address-pool"
      "code"
      "comment"
      "copy-from"
      "disabled"
      "matching-type"
      "name"
      "option-set"
      "server"
      "value"
    ];
  }
  {
    path = "/ip dhcp-server network";
    kind = "list";
    attrs = [
      "address"
      "boot-file-name"
      "caps-manager"
      "cmr-none"
      "cmr-server"
      "comment"
      "copy-from"
      "dhcp-option"
      "dhcp-option-set"
      "dns-none"
      "dns-server"
      "domain"
      "gateway"
      "netmask"
      "next-server"
      "ntp-none"
      "ntp-server"
      "wins-server"
    ];
    # multi-value: written as a list in the typed menu
    lists = [
      "caps-manager"
      "dns-server"
      "gateway"
      "ntp-server"
      "wins-server"
    ];
  }
  {
    path = "/ip dhcp-server option";
    kind = "list";
    attrs = [
      "code"
      "comment"
      "copy-from"
      "force"
      "name"
      "value"
    ];
  }
  {
    path = "/ip dhcp-server option sets";
    kind = "list";
    attrs = [
      "comment"
      "copy-from"
      "name"
      "options"
    ];
  }
  {
    path = "/ip dns";
    kind = "object";
    attrs = [
      "address-list-extra-time"
      "allow-remote-requests"
      "cache-max-ttl"
      "cache-size"
      "doh-max-concurrent-queries"
      "doh-max-server-connections"
      "doh-timeout"
      "max-concurrent-queries"
      "max-concurrent-tcp-sessions"
      "max-udp-packet-size"
      "mdns-repeat-ifaces"
      "query-server-timeout"
      "query-total-timeout"
      "servers"
      "use-doh-server"
      "verify-doh-cert"
      "vrf"
    ];
    # multi-value: written as a list in the typed menu
    lists = [
      "mdns-repeat-ifaces"
      "servers"
    ];
  }
  {
    path = "/ip dns adlist";
    kind = "list";
    attrs = [
      "comment"
      "copy-from"
      "disabled"
      "file"
      "ssl-verify"
      "url"
    ];
  }
  {
    path = "/ip dns forwarders";
    kind = "list";
    attrs = [
      "comment"
      "copy-from"
      "disabled"
      "dns-servers"
      "doh-servers"
      "name"
      "verify-doh-cert"
    ];
  }
  {
    path = "/ip dns static";
    kind = "list";
    attrs = [
      "address"
      "address-list"
      "cname"
      "comment"
      "copy-from"
      "disabled"
      "forward-to"
      "match-subdomain"
      "mx-exchange"
      "mx-preference"
      "name"
      "ns"
      "place-before"
      "regexp"
      "srv-port"
      "srv-priority"
      "srv-target"
      "srv-weight"
      "text"
      "ttl"
      "type"
    ];
  }
  {
    path = "/ip firewall address-list";
    kind = "list";
    attrs = [
      "address"
      "comment"
      "copy-from"
      "disabled"
      "dynamic"
      "list"
      "timeout"
    ];
  }
  {
    path = "/ip firewall calea";
    kind = "list";
    attrs = [
      "action"
      "address-list"
      "address-list-timeout"
      "application-mark"
      "chain"
      "comment"
      "connection-bytes"
      "connection-limit"
      "connection-mark"
      "connection-rate"
      "connection-type"
      "content"
      "copy-from"
      "disabled"
      "dscp"
      "dst-address"
      "dst-address-list"
      "dst-address-type"
      "dst-limit"
      "dst-port"
      "fragment"
      "hotspot"
      "icmp-options"
      "in-bridge-port"
      "in-bridge-port-list"
      "in-interface"
      "in-interface-list"
      "ingress-priority"
      "ipsec-policy"
      "ipv4-options"
      "layer7-protocol"
      "limit"
      "log"
      "log-prefix"
      "nth"
      "out-bridge-port"
      "out-bridge-port-list"
      "out-interface"
      "out-interface-list"
      "packet-mark"
      "packet-size"
      "per-connection-classifier"
      "place-before"
      "port"
      "priority"
      "protocol"
      "psd"
      "random"
      "realm"
      "routing-mark"
      "sniff-id"
      "sniff-target"
      "sniff-target-port"
      "src-address"
      "src-address-list"
      "src-address-type"
      "src-mac-address"
      "src-port"
      "tcp-mss"
      "time"
      "tls-host"
      "tos"
      "ttl"
    ];
  }
  {
    path = "/ip firewall connection tracking";
    kind = "object";
    attrs = [
      "enabled"
      "generic-timeout"
      "icmp-timeout"
      "liberal-tcp-tracking"
      "loose-tcp-tracking"
      "tcp-close-timeout"
      "tcp-close-wait-timeout"
      "tcp-established-timeout"
      "tcp-fin-wait-timeout"
      "tcp-last-ack-timeout"
      "tcp-max-retrans-timeout"
      "tcp-syn-received-timeout"
      "tcp-syn-sent-timeout"
      "tcp-time-wait-timeout"
      "tcp-unacked-timeout"
      "udp-stream-timeout"
      "udp-timeout"
    ];
  }
  {
    path = "/ip firewall filter";
    kind = "list";
    attrs = [
      "action"
      "address-list"
      "address-list-timeout"
      "application-mark"
      "chain"
      "comment"
      "connection-bytes"
      "connection-limit"
      "connection-mark"
      "connection-nat-state"
      "connection-rate"
      "connection-state"
      "connection-type"
      "content"
      "copy-from"
      "disabled"
      "dscp"
      "dst-address"
      "dst-address-list"
      "dst-address-type"
      "dst-limit"
      "dst-port"
      "fragment"
      "hotspot"
      "icmp-options"
      "in-bridge-port"
      "in-bridge-port-list"
      "in-interface"
      "in-interface-list"
      "ingress-priority"
      "ipsec-policy"
      "ipv4-options"
      "jump-target"
      "layer7-protocol"
      "limit"
      "log"
      "log-prefix"
      "nth"
      "out-bridge-port"
      "out-bridge-port-list"
      "out-interface"
      "out-interface-list"
      "p2p"
      "packet-mark"
      "packet-size"
      "per-connection-classifier"
      "place-before"
      "port"
      "priority"
      "protocol"
      "psd"
      "random"
      "realm"
      "reject-with"
      "routing-mark"
      "src-address"
      "src-address-list"
      "src-address-type"
      "src-mac-address"
      "src-port"
      "tcp-flags"
      "tcp-mss"
      "time"
      "tls-host"
      "tos"
      "ttl"
    ];
    # multi-value: written as a list in the typed menu
    lists = [
      "connection-nat-state"
      "connection-state"
      "dst-address-type"
      "hotspot"
      "src-address-type"
    ];
  }
  {
    path = "/ip firewall layer7-protocol";
    kind = "list";
    attrs = [
      "comment"
      "copy-from"
      "name"
      "regexp"
    ];
  }
  {
    path = "/ip firewall mangle";
    kind = "list";
    attrs = [
      "action"
      "address-list"
      "address-list-timeout"
      "application-mark"
      "chain"
      "comment"
      "connection-bytes"
      "connection-limit"
      "connection-mark"
      "connection-nat-state"
      "connection-rate"
      "connection-state"
      "connection-type"
      "content"
      "copy-from"
      "disabled"
      "dscp"
      "dst-address"
      "dst-address-list"
      "dst-address-type"
      "dst-limit"
      "dst-port"
      "fragment"
      "hotspot"
      "icmp-options"
      "in-bridge-port"
      "in-bridge-port-list"
      "in-interface"
      "in-interface-list"
      "ingress-priority"
      "ipsec-policy"
      "ipv4-options"
      "jump-target"
      "layer7-protocol"
      "limit"
      "log"
      "log-prefix"
      "new-connection-mark"
      "new-dscp"
      "new-mss"
      "new-packet-mark"
      "new-priority"
      "new-routing-mark"
      "new-ttl"
      "nth"
      "out-bridge-port"
      "out-bridge-port-list"
      "out-interface"
      "out-interface-list"
      "p2p"
      "packet-mark"
      "packet-size"
      "passthrough"
      "per-connection-classifier"
      "place-before"
      "port"
      "priority"
      "protocol"
      "psd"
      "random"
      "realm"
      "route-dst"
      "routing-mark"
      "sniff-id"
      "sniff-target"
      "sniff-target-port"
      "src-address"
      "src-address-list"
      "src-address-type"
      "src-mac-address"
      "src-port"
      "tcp-flags"
      "tcp-mss"
      "time"
      "tls-host"
      "tos"
      "ttl"
    ];
    # multi-value: written as a list in the typed menu
    lists = [
      "connection-state"
      "dst-address-type"
      "hotspot"
      "src-address-type"
    ];
  }
  {
    path = "/ip firewall nat";
    kind = "list";
    attrs = [
      "action"
      "address-list"
      "address-list-timeout"
      "application-mark"
      "chain"
      "comment"
      "connection-bytes"
      "connection-limit"
      "connection-mark"
      "connection-rate"
      "connection-type"
      "content"
      "copy-from"
      "disabled"
      "dscp"
      "dst-address"
      "dst-address-list"
      "dst-address-type"
      "dst-limit"
      "dst-port"
      "fragment"
      "hotspot"
      "icmp-options"
      "in-bridge-port"
      "in-bridge-port-list"
      "in-interface"
      "in-interface-list"
      "ingress-priority"
      "ipsec-policy"
      "ipv4-options"
      "jump-target"
      "layer7-protocol"
      "limit"
      "log"
      "log-prefix"
      "nth"
      "out-bridge-port"
      "out-bridge-port-list"
      "out-interface"
      "out-interface-list"
      "packet-mark"
      "packet-size"
      "per-connection-classifier"
      "place-before"
      "port"
      "priority"
      "protocol"
      "psd"
      "random"
      "randomise-ports"
      "realm"
      "routing-mark"
      "same-not-by-dst"
      "socks5-port"
      "socks5-server"
      "socksify-service"
      "src-address"
      "src-address-list"
      "src-address-type"
      "src-mac-address"
      "src-port"
      "tcp-mss"
      "time"
      "to-addresses"
      "to-ports"
      "tos"
      "ttl"
    ];
    # multi-value: written as a list in the typed menu
    lists = [
      "dst-address-type"
      "hotspot"
      "src-address-type"
    ];
  }
  {
    path = "/ip firewall raw";
    kind = "list";
    attrs = [
      "action"
      "address-list"
      "address-list-timeout"
      "chain"
      "comment"
      "content"
      "copy-from"
      "disabled"
      "dscp"
      "dst-address"
      "dst-address-list"
      "dst-address-type"
      "dst-limit"
      "dst-port"
      "fragment"
      "hotspot"
      "icmp-options"
      "in-bridge-port"
      "in-bridge-port-list"
      "in-interface"
      "in-interface-list"
      "ingress-priority"
      "ipsec-policy"
      "ipv4-options"
      "jump-target"
      "limit"
      "log"
      "log-prefix"
      "nth"
      "out-bridge-port"
      "out-bridge-port-list"
      "out-interface"
      "out-interface-list"
      "packet-mark"
      "packet-size"
      "per-connection-classifier"
      "place-before"
      "port"
      "priority"
      "protocol"
      "psd"
      "random"
      "src-address"
      "src-address-list"
      "src-address-type"
      "src-mac-address"
      "src-port"
      "tcp-flags"
      "tcp-mss"
      "time"
      "tls-host"
      "tos"
      "ttl"
    ];
  }
  {
    path = "/ip firewall service-port";
    kind = "object";
    attrs = [
      "disabled"
      "numbers"
      "ports"
      "sip-direct-media"
      "sip-timeout"
    ];
  }
  {
    path = "/ip hotspot";
    kind = "list";
    attrs = [
      "address-pool"
      "addresses-per-mac"
      "copy-from"
      "disabled"
      "idle-timeout"
      "interface"
      "keepalive-timeout"
      "login-timeout"
      "name"
      "profile"
    ];
  }
  {
    path = "/ip hotspot ip-binding";
    kind = "list";
    attrs = [
      "address"
      "comment"
      "copy-from"
      "disabled"
      "mac-address"
      "place-before"
      "server"
      "to-address"
      "type"
    ];
  }
  {
    path = "/ip hotspot profile";
    kind = "list";
    attrs = [
      "copy-from"
      "dns-name"
      "hotspot-address"
      "html-directory"
      "html-directory-override"
      "http-cookie-lifetime"
      "http-proxy"
      "install-hotspot-queue"
      "login-by"
      "mac-auth-mode"
      "mac-auth-password"
      "name"
      "nas-port-type"
      "radius-accounting"
      "radius-default-domain"
      "radius-interim-update"
      "radius-location-id"
      "radius-location-name"
      "radius-mac-format"
      "rate-limit"
      "smtp-server"
      "split-user-domain"
      "ssl-certificate"
      "trial-uptime-limit"
      "trial-uptime-reset"
      "trial-user-profile"
      "use-radius"
    ];
    # multi-value: written as a list in the typed menu (device type only)
    lists = [
      "login-by"
    ];
  }
  {
    path = "/ip hotspot service-port";
    kind = "object";
    attrs = [
      "disabled"
      "numbers"
      "ports"
    ];
  }
  {
    path = "/ip hotspot user";
    kind = "list";
    attrs = [
      "address"
      "comment"
      "copy-from"
      "disabled"
      "email"
      "limit-bytes-in"
      "limit-bytes-out"
      "limit-bytes-total"
      "limit-uptime"
      "mac-address"
      "name"
      "otp-secret"
      "password"
      "profile"
      "routes"
      "server"
    ];
  }
  {
    path = "/ip hotspot user profile";
    kind = "list";
    attrs = [
      "add-mac-cookie"
      "address-list"
      "address-pool"
      "advertise"
      "advertise-interval"
      "advertise-timeout"
      "advertise-url"
      "copy-from"
      "idle-timeout"
      "incoming-filter"
      "incoming-packet-mark"
      "insert-queue-before"
      "keepalive-timeout"
      "mac-cookie-timeout"
      "name"
      "on-login"
      "on-logout"
      "open-status-page"
      "outgoing-filter"
      "outgoing-packet-mark"
      "parent-queue"
      "queue-type"
      "rate-limit"
      "session-timeout"
      "shared-users"
      "status-autorefresh"
      "transparent-proxy"
    ];
    # multi-value: written as a list in the typed menu (device type only)
    lists = [
      "address-list"
    ];
  }
  {
    path = "/ip hotspot walled-garden";
    kind = "list";
    attrs = [
      "action"
      "comment"
      "copy-from"
      "disabled"
      "dst-host"
      "dst-port"
      "method"
      "path"
      "place-before"
      "server"
      "src-address"
    ];
  }
  {
    path = "/ip hotspot walled-garden ip";
    kind = "list";
    attrs = [
      "action"
      "comment"
      "copy-from"
      "disabled"
      "dst-address"
      "dst-address-list"
      "dst-host"
      "dst-port"
      "place-before"
      "protocol"
      "server"
      "src-address"
      "src-address-list"
    ];
  }
  {
    path = "/ip ipsec active-peers";
    kind = "list";
    attrs = [
      "comment"
      "copy-from"
    ];
  }
  {
    path = "/ip ipsec identity";
    kind = "list";
    attrs = [
      "auth-method"
      "certificate"
      "comment"
      "copy-from"
      "disabled"
      "eap-methods"
      "generate-policy"
      "key"
      "match-by"
      "mode-config"
      "my-id"
      "notrack-chain"
      "password"
      "peer"
      "policy-template-group"
      "remote-certificate"
      "remote-id"
      "remote-key"
      "secret"
      "username"
    ];
  }
  {
    path = "/ip ipsec key psk";
    kind = "list";
    attrs = [
      "copy-from"
      "id"
      "key"
      "peer"
    ];
  }
  {
    path = "/ip ipsec key rsa";
    kind = "object";
    attrs = [
      "name"
      "numbers"
    ];
  }
  {
    path = "/ip ipsec mode-config";
    kind = "list";
    attrs = [
      "address"
      "address-pool"
      "address-prefix-length"
      "connection-mark"
      "copy-from"
      "name"
      "responder"
      "split-dns"
      "split-include"
      "src-address-list"
      "static-dns"
      "system-dns"
      "use-responder-dns"
    ];
  }
  {
    path = "/ip ipsec peer";
    kind = "list";
    attrs = [
      "address"
      "comment"
      "copy-from"
      "disabled"
      "exchange-mode"
      "local-address"
      "name"
      "passive"
      "port"
      "ppk-secret"
      "profile"
      "send-initial-contact"
    ];
  }
  {
    path = "/ip ipsec policy";
    kind = "list";
    attrs = [
      "action"
      "comment"
      "copy-from"
      "disabled"
      "dst-address"
      "dst-port"
      "group"
      "ipsec-protocols"
      "level"
      "peer"
      "place-before"
      "proposal"
      "protocol"
      "sa-dst-address"
      "sa-src-address"
      "src-address"
      "src-port"
      "template"
      "tunnel"
    ];
  }
  {
    path = "/ip ipsec policy group";
    kind = "list";
    attrs = [
      "comment"
      "copy-from"
      "interface"
      "name"
    ];
  }
  {
    path = "/ip ipsec profile";
    kind = "list";
    attrs = [
      "copy-from"
      "dh-group"
      "dpd-interval"
      "dpd-maximum-failures"
      "enc-algorithm"
      "hash-algorithm"
      "lifebytes"
      "lifetime"
      "name"
      "nat-traversal"
      "ppk"
      "prf-algorithm"
      "proposal-check"
    ];
    # multi-value: written as a list in the typed menu (device type only)
    lists = [
      "dh-group"
      "enc-algorithm"
    ];
  }
  {
    path = "/ip ipsec proposal";
    kind = "list";
    attrs = [
      "auth-algorithms"
      "comment"
      "copy-from"
      "disabled"
      "enc-algorithms"
      "lifetime"
      "name"
      "pfs-group"
    ];
    # multi-value: written as a list in the typed menu (device type only)
    lists = [
      "auth-algorithms"
      "enc-algorithms"
    ];
  }
  {
    path = "/ip ipsec settings";
    kind = "object";
    attrs = [
      "accounting"
      "ddos-cookie-threshold"
      "interim-update"
      "xauth-use-radius"
    ];
  }
  {
    path = "/ip kid-control";
    kind = "list";
    attrs = [
      "copy-from"
      "disabled"
      "fri"
      "mon"
      "name"
      "rate-limit"
      "sat"
      "sun"
      "thu"
      "tue"
      "tur-fri"
      "tur-mon"
      "tur-sat"
      "tur-sun"
      "tur-thu"
      "tur-tue"
      "tur-wed"
      "wed"
    ];
  }
  {
    path = "/ip kid-control device";
    kind = "list";
    attrs = [
      "copy-from"
      "disabled"
      "mac-address"
      "name"
      "user"
    ];
  }
  {
    path = "/ip media";
    kind = "list";
    attrs = [
      "allowed-hostname"
      "allowed-ip"
      "copy-from"
      "disabled"
      "friendly-name"
      "interface"
      "path"
    ];
  }
  {
    path = "/ip media settings";
    kind = "object";
    attrs = [
      "thumbnails"
    ];
  }
  {
    path = "/ip nat-pmp";
    kind = "object";
    attrs = [
      "enabled"
    ];
  }
  {
    path = "/ip nat-pmp interfaces";
    kind = "list";
    attrs = [
      "copy-from"
      "disabled"
      "forced-ip"
      "interface"
      "type"
    ];
  }
  {
    path = "/ip neighbor discovery-settings";
    kind = "object";
    attrs = [
      "add-dns-entries"
      "add-dns-entries-suffix"
      "discover-interface-list"
      "discover-interval"
      "dying-gasp"
      "lldp-mac-phy-config"
      "lldp-max-frame-size"
      "lldp-med"
      "lldp-med-net-policy-vlan"
      "lldp-vlan-info"
      "mode"
      "protocol"
    ];
    # multi-value: written as a list in the typed menu
    lists = [
      "protocol"
    ];
  }
  {
    path = "/ip packing";
    kind = "list";
    attrs = [
      "aggregated-size"
      "copy-from"
      "disabled"
      "interface"
      "packing"
      "unpacking"
    ];
  }
  {
    path = "/ip pool";
    kind = "list";
    attrs = [
      "comment"
      "copy-from"
      "name"
      "next-pool"
      "ranges"
    ];
    # multi-value: written as a list in the typed menu
    lists = [
      "ranges"
    ];
  }
  {
    path = "/ip pool used";
    kind = "object";
    attrs = [
      "address"
      "info"
      "numbers"
      "owner"
      "pool"
    ];
  }
  {
    path = "/ip proxy";
    kind = "object";
    attrs = [
      "always-from-cache"
      "anonymous"
      "cache-administrator"
      "cache-hit-dscp"
      "cache-on-disk"
      "cache-path"
      "enabled"
      "max-cache-object-size"
      "max-cache-size"
      "max-client-connections"
      "max-fresh-time"
      "max-server-connections"
      "parent-proxy"
      "parent-proxy-port"
      "port"
      "serialize-connections"
      "src-address"
    ];
    # multi-value: written as a list in the typed menu
    lists = [
      "port"
    ];
  }
  {
    path = "/ip proxy access";
    kind = "list";
    attrs = [
      "action"
      "action-data"
      "comment"
      "copy-from"
      "disabled"
      "dst-address"
      "dst-host"
      "dst-port"
      "local-port"
      "method"
      "path"
      "place-before"
      "src-address"
    ];
  }
  {
    path = "/ip proxy cache";
    kind = "list";
    attrs = [
      "action"
      "comment"
      "copy-from"
      "disabled"
      "dst-address"
      "dst-host"
      "dst-port"
      "local-port"
      "method"
      "path"
      "place-before"
      "src-address"
    ];
  }
  {
    path = "/ip proxy cache-contents";
    kind = "list";
    attrs = [
      "copy-from"
    ];
  }
  {
    path = "/ip proxy connections";
    kind = "object";
    attrs = [
      "comment"
      "numbers"
    ];
  }
  {
    path = "/ip proxy direct";
    kind = "list";
    attrs = [
      "action"
      "comment"
      "copy-from"
      "disabled"
      "dst-address"
      "dst-host"
      "dst-port"
      "local-port"
      "method"
      "path"
      "place-before"
      "src-address"
    ];
  }
  {
    path = "/ip reverse-proxy";
    kind = "list";
    attrs = [
      "certificate"
      "comment"
      "copy-from"
      "disabled"
      "ip-address"
      "port"
      "sni"
      "vrf"
    ];
  }
  {
    path = "/ip route";
    kind = "list";
    attrs = [
      "blackhole"
      "check-gateway"
      "comment"
      "copy-from"
      "disabled"
      "distance"
      "dst-address"
      "gateway"
      "pref-src"
      "routing-table"
      "scope"
      "target-scope"
      "te-tunnel-id"
      "vrf-interface"
    ];
  }
  {
    path = "/ip service";
    kind = "object";
    attrs = [
      "address"
      "available-from"
      "certificate"
      "disabled"
      "max-sessions"
      "numbers"
      "port"
      "tls-version"
      "vrf"
    ];
  }
  {
    path = "/ip service webserver";
    kind = "object";
    attrs = [
      "acme-plain"
      "crl-plain"
      "graphs-plain"
      "graphs-secure"
      "index-plain"
      "index-secure"
      "rest-plain"
      "rest-secure"
      "scep-plain"
      "webfig-plain"
      "webfig-secure"
    ];
  }
  {
    path = "/ip settings";
    kind = "object";
    attrs = [
      "accept-redirects"
      "accept-source-route"
      "allow-fast-path"
      "arp-timeout"
      "icmp-errors-use-inbound-interface-address"
      "icmp-rate-limit"
      "icmp-rate-mask"
      "ip-forward"
      "ipv4-fragment-time"
      "ipv4-high-fragment-thresh"
      "ipv4-multipath-hash-policy"
      "max-neighbor-entries"
      "rp-filter"
      "secure-redirects"
      "send-redirects"
      "tcp-syncookies"
      "tcp-timestamps"
    ];
  }
  {
    path = "/ip smb";
    kind = "object";
    attrs = [
      "comment"
      "domain"
      "enabled"
      "interfaces"
    ];
    # multi-value: written as a list in the typed menu
    lists = [
      "interfaces"
    ];
  }
  {
    path = "/ip smb shares";
    kind = "list";
    attrs = [
      "comment"
      "copy-from"
      "directory"
      "disabled"
      "invalid-users"
      "name"
      "read-only"
      "require-encryption"
      "valid-users"
    ];
    # multi-value: written as a list in the typed menu (device type only)
    lists = [
      "invalid-users"
      "valid-users"
    ];
  }
  {
    path = "/ip smb users";
    kind = "list";
    attrs = [
      "comment"
      "copy-from"
      "disabled"
      "name"
      "password"
      "read-only"
    ];
  }
  {
    path = "/ip socks";
    kind = "object";
    attrs = [
      "auth-method"
      "connection-idle-timeout"
      "enabled"
      "max-connections"
      "port"
      "version"
      "vrf"
    ];
  }
  {
    path = "/ip socks access";
    kind = "list";
    attrs = [
      "action"
      "comment"
      "copy-from"
      "disabled"
      "dst-address"
      "dst-port"
      "place-before"
      "src-address"
      "src-port"
    ];
  }
  {
    path = "/ip socks connections";
    kind = "object";
    attrs = [
      "dst-address"
      "numbers"
      "rx"
      "src-address"
      "tx"
      "type"
    ];
  }
  {
    path = "/ip socks users";
    kind = "list";
    attrs = [
      "copy-from"
      "disabled"
      "name"
      "only-one"
      "password"
      "rate-limit"
    ];
  }
  {
    path = "/ip socksify";
    kind = "list";
    attrs = [
      "comment"
      "connection-timeout"
      "copy-from"
      "disabled"
      "name"
      "port"
      "socks5-password"
      "socks5-port"
      "socks5-server"
      "socks5-user"
    ];
  }
  {
    path = "/ip ssh";
    kind = "object";
    attrs = [
      "ciphers"
      "forwarding-enabled"
      "host-key-size"
      "host-key-type"
      "known-hosts-trusted-subnets"
      "known-hosts-validation"
      "password-authentication"
      "publickey-authentication-options"
      "strong-crypto"
    ];
    # multi-value: written as a list in the typed menu (device type only)
    lists = [
      "ciphers"
      "known-hosts-trusted-subnets"
    ];
  }
  {
    path = "/ip ssh known-hosts";
    kind = "list";
    attrs = [
      "comment"
      "copy-from"
      "host"
      "key"
    ];
  }
  {
    path = "/ip tftp";
    kind = "list";
    attrs = [
      "allow"
      "allow-overwrite"
      "allow-rollover"
      "comment"
      "copy-from"
      "disabled"
      "ip-addresses"
      "place-before"
      "read-only"
      "reading-window-size"
      "real-filename"
      "req-filename"
    ];
  }
  {
    path = "/ip tftp settings";
    kind = "object";
    attrs = [
      "max-block-size"
      "vrf"
    ];
  }
  {
    path = "/ip traffic-flow";
    kind = "object";
    attrs = [
      "active-flow-timeout"
      "cache-entries"
      "enabled"
      "inactive-flow-timeout"
      "interfaces"
      "packet-sampling"
      "sampling-interval"
      "sampling-space"
    ];
    # multi-value: written as a list in the typed menu
    lists = [
      "interfaces"
    ];
  }
  {
    path = "/ip traffic-flow ipfix";
    kind = "object";
    attrs = [
      "bytes"
      "dst-address"
      "dst-address-mask"
      "dst-mac-address"
      "dst-port"
      "first-forwarded"
      "gateway"
      "icmp-code"
      "icmp-type"
      "igmp-type"
      "in-interface"
      "ip-header-length"
      "ip-total-length"
      "ipv6-flow-label"
      "is-multicast"
      "last-forwarded"
      "nat-dst-address"
      "nat-dst-port"
      "nat-events"
      "nat-src-address"
      "nat-src-port"
      "out-interface"
      "packets"
      "protocol"
      "src-address"
      "src-address-mask"
      "src-mac-address"
      "src-port"
      "sys-init-time"
      "tcp-ack-num"
      "tcp-flags"
      "tcp-seq-num"
      "tcp-window-size"
      "tos"
      "ttl"
      "udp-length"
    ];
  }
  {
    path = "/ip traffic-flow target";
    kind = "list";
    attrs = [
      "copy-from"
      "disabled"
      "dst-address"
      "port"
      "src-address"
      "v9-template-refresh"
      "v9-template-timeout"
      "version"
    ];
  }
  {
    path = "/ip upnp";
    kind = "object";
    attrs = [
      "allow-disable-external-interface"
      "enabled"
      "show-dummy-rule"
    ];
  }
  {
    path = "/ip upnp interfaces";
    kind = "list";
    attrs = [
      "copy-from"
      "disabled"
      "forced-ip"
      "interface"
      "type"
    ];
  }
  {
    path = "/ip vrf";
    kind = "list";
    attrs = [
      "comment"
      "copy-from"
      "disabled"
      "interfaces"
      "name"
      "place-before"
    ];
    # multi-value: written as a list in the typed menu (device type only)
    lists = [
      "interfaces"
    ];
  }
  {
    path = "/ipv6 address";
    kind = "list";
    attrs = [
      "address"
      "advertise"
      "auto-link-local"
      "comment"
      "copy-from"
      "disabled"
      "eui-64"
      "from-pool"
      "from-pool-policy"
      "interface"
      "no-dad"
    ];
  }
  {
    path = "/ipv6 dhcp-client";
    kind = "list";
    attrs = [
      "accept-prefix-without-address"
      "add-default-route"
      "allow-reconfigure"
      "check-gateway"
      "comment"
      "copy-from"
      "custom-duid"
      "custom-iana-id"
      "custom-iapd-id"
      "default-route-distance"
      "default-route-tables"
      "dhcp-options"
      "disabled"
      "interface"
      "pool-name"
      "pool-prefix-length"
      "prefix-address-lists"
      "prefix-hint"
      "rapid-commit"
      "request"
      "script"
      "use-interface-duid"
      "use-peer-dns"
      "validate-server-duid"
    ];
  }
  {
    path = "/ipv6 dhcp-client option";
    kind = "list";
    attrs = [
      "code"
      "comment"
      "copy-from"
      "name"
      "value"
    ];
  }
  {
    path = "/ipv6 dhcp-relay";
    kind = "list";
    attrs = [
      "comment"
      "copy-from"
      "delay-threshold"
      "dhcp-options"
      "dhcp-server"
      "disabled"
      "interface"
      "link-address"
      "name"
      "store-relayed-bindings"
    ];
  }
  {
    path = "/ipv6 dhcp-relay option";
    kind = "list";
    attrs = [
      "code"
      "comment"
      "copy-from"
      "name"
      "only-if-mac-available"
      "value"
    ];
  }
  {
    path = "/ipv6 dhcp-server";
    kind = "list";
    attrs = [
      "add-dns-entries"
      "add-dns-entries-suffix"
      "address-lists"
      "address-pool"
      "allow-dual-stack-queue"
      "binding-script"
      "comment"
      "copy-from"
      "dhcp-option"
      "disabled"
      "ignore-ia-na-bindings"
      "insert-queue-before"
      "interface"
      "lease-time"
      "name"
      "parent-queue"
      "preference"
      "prefix-pool"
      "rapid-commit"
      "route-distance"
      "use-radius"
      "use-reconfigure"
    ];
  }
  {
    path = "/ipv6 dhcp-server binding";
    kind = "list";
    attrs = [
      "address"
      "address-lists"
      "allow-dual-stack-queue"
      "comment"
      "copy-from"
      "dhcp-option"
      "disabled"
      "duid"
      "ia-type"
      "iaid"
      "insert-queue-before"
      "life-time"
      "parent-queue"
      "prefix-pool"
      "queue-type"
      "rate-limit"
      "server"
    ];
  }
  {
    path = "/ipv6 dhcp-server option";
    kind = "list";
    attrs = [
      "code"
      "comment"
      "copy-from"
      "name"
      "value"
    ];
  }
  {
    path = "/ipv6 dhcp-server option sets";
    kind = "list";
    attrs = [
      "comment"
      "copy-from"
      "name"
      "options"
    ];
  }
  {
    path = "/ipv6 firewall address-list";
    kind = "list";
    attrs = [
      "address"
      "comment"
      "copy-from"
      "disabled"
      "dynamic"
      "list"
      "timeout"
    ];
  }
  {
    path = "/ipv6 firewall filter";
    kind = "list";
    attrs = [
      "action"
      "address-list"
      "address-list-timeout"
      "application-mark"
      "chain"
      "comment"
      "connection-bytes"
      "connection-limit"
      "connection-mark"
      "connection-nat-state"
      "connection-rate"
      "connection-state"
      "connection-type"
      "content"
      "copy-from"
      "disabled"
      "dscp"
      "dst-address"
      "dst-address-list"
      "dst-address-type"
      "dst-limit"
      "dst-port"
      "headers"
      "hop-limit"
      "icmp-options"
      "in-bridge-port"
      "in-bridge-port-list"
      "in-interface"
      "in-interface-list"
      "ingress-priority"
      "ipsec-policy"
      "jump-target"
      "limit"
      "log"
      "log-prefix"
      "nth"
      "out-bridge-port"
      "out-bridge-port-list"
      "out-interface"
      "out-interface-list"
      "packet-mark"
      "packet-size"
      "per-connection-classifier"
      "place-before"
      "port"
      "priority"
      "protocol"
      "random"
      "reject-with"
      "routing-mark"
      "src-address"
      "src-address-list"
      "src-address-type"
      "src-mac-address"
      "src-port"
      "tcp-flags"
      "tcp-mss"
      "time"
      "tls-host"
      "tos"
    ];
  }
  {
    path = "/ipv6 firewall mangle";
    kind = "list";
    attrs = [
      "action"
      "address-list"
      "address-list-timeout"
      "application-mark"
      "chain"
      "comment"
      "connection-bytes"
      "connection-limit"
      "connection-mark"
      "connection-nat-state"
      "connection-rate"
      "connection-state"
      "connection-type"
      "content"
      "copy-from"
      "disabled"
      "dscp"
      "dst-address"
      "dst-address-list"
      "dst-address-type"
      "dst-limit"
      "dst-port"
      "dst-prefix"
      "headers"
      "hop-limit"
      "icmp-options"
      "in-bridge-port"
      "in-bridge-port-list"
      "in-interface"
      "in-interface-list"
      "ingress-priority"
      "ipsec-policy"
      "jump-target"
      "limit"
      "log"
      "log-prefix"
      "new-connection-mark"
      "new-dscp"
      "new-hop-limit"
      "new-mss"
      "new-packet-mark"
      "new-priority"
      "new-routing-mark"
      "nth"
      "out-bridge-port"
      "out-bridge-port-list"
      "out-interface"
      "out-interface-list"
      "packet-mark"
      "packet-size"
      "passthrough"
      "per-connection-classifier"
      "place-before"
      "port"
      "priority"
      "protocol"
      "random"
      "routing-mark"
      "sniff-id"
      "sniff-target"
      "sniff-target-port"
      "src-address"
      "src-address-list"
      "src-address-type"
      "src-mac-address"
      "src-port"
      "src-prefix"
      "tcp-flags"
      "tcp-mss"
      "time"
      "tls-host"
      "tos"
    ];
  }
  {
    path = "/ipv6 firewall nat";
    kind = "list";
    attrs = [
      "action"
      "address-list"
      "address-list-timeout"
      "application-mark"
      "chain"
      "comment"
      "connection-bytes"
      "connection-limit"
      "connection-mark"
      "connection-rate"
      "connection-state"
      "connection-type"
      "content"
      "copy-from"
      "disabled"
      "dscp"
      "dst-address"
      "dst-address-list"
      "dst-address-type"
      "dst-limit"
      "dst-port"
      "headers"
      "hop-limit"
      "icmp-options"
      "in-bridge-port"
      "in-bridge-port-list"
      "in-interface"
      "in-interface-list"
      "ingress-priority"
      "ipsec-policy"
      "jump-target"
      "limit"
      "log"
      "log-prefix"
      "nth"
      "out-bridge-port"
      "out-bridge-port-list"
      "out-interface"
      "out-interface-list"
      "packet-mark"
      "packet-size"
      "per-connection-classifier"
      "place-before"
      "port"
      "priority"
      "protocol"
      "random"
      "routing-mark"
      "src-address"
      "src-address-list"
      "src-address-type"
      "src-mac-address"
      "src-port"
      "tcp-flags"
      "tcp-mss"
      "time"
      "to-address"
      "to-ports"
      "tos"
    ];
  }
  {
    path = "/ipv6 firewall raw";
    kind = "list";
    attrs = [
      "action"
      "address-list"
      "address-list-timeout"
      "chain"
      "comment"
      "content"
      "copy-from"
      "disabled"
      "dscp"
      "dst-address"
      "dst-address-list"
      "dst-address-type"
      "dst-limit"
      "dst-port"
      "headers"
      "hop-limit"
      "icmp-options"
      "in-bridge-port"
      "in-bridge-port-list"
      "in-interface"
      "in-interface-list"
      "ingress-priority"
      "ipsec-policy"
      "jump-target"
      "limit"
      "log"
      "log-prefix"
      "nth"
      "out-bridge-port"
      "out-bridge-port-list"
      "out-interface"
      "out-interface-list"
      "packet-mark"
      "packet-size"
      "per-connection-classifier"
      "place-before"
      "port"
      "priority"
      "protocol"
      "random"
      "src-address"
      "src-address-list"
      "src-address-type"
      "src-mac-address"
      "src-port"
      "tcp-flags"
      "tcp-mss"
      "time"
      "tls-host"
      "tos"
    ];
  }
  {
    path = "/ipv6 nd";
    kind = "list";
    attrs = [
      "advertise-dns"
      "advertise-mac-address"
      "comment"
      "copy-from"
      "disabled"
      "dns"
      "hop-limit"
      "interface"
      "managed-address-configuration"
      "mtu"
      "other-configuration"
      "pref64"
      "ra-delay"
      "ra-interval"
      "ra-lifetime"
      "ra-preference"
      "reachable-time"
      "retransmit-interval"
    ];
  }
  {
    path = "/ipv6 nd prefix";
    kind = "list";
    attrs = [
      "6to4-interface"
      "autonomous"
      "comment"
      "copy-from"
      "dhcp6-pd-preferred"
      "disabled"
      "interface"
      "on-link"
      "preferred-lifetime"
      "prefix"
      "valid-lifetime"
    ];
  }
  {
    path = "/ipv6 nd prefix default";
    kind = "object";
    attrs = [
      "autonomous"
      "dhcp6-pd-preferred"
      "preferred-lifetime"
      "valid-lifetime"
    ];
  }
  {
    path = "/ipv6 nd proxy";
    kind = "list";
    attrs = [
      "address"
      "comment"
      "copy-from"
      "disabled"
      "interface"
    ];
  }
  {
    path = "/ipv6 nd settings";
    kind = "object";
    attrs = [
      "router-advertisement-ignored-options"
      "router-advertisement-route-distance"
    ];
    # multi-value: written as a list in the typed menu
    lists = [
      "router-advertisement-ignored-options"
    ];
  }
  {
    path = "/ipv6 neighbor";
    kind = "list";
    attrs = [
      "address"
      "comment"
      "copy-from"
      "disabled"
      "interface"
      "mac-address"
    ];
  }
  {
    path = "/ipv6 pool";
    kind = "list";
    attrs = [
      "comment"
      "copy-from"
      "from-pool"
      "name"
      "prefix"
      "prefix-length"
    ];
  }
  {
    path = "/ipv6 route";
    kind = "list";
    attrs = [
      "blackhole"
      "check-gateway"
      "comment"
      "copy-from"
      "disabled"
      "distance"
      "dst-address"
      "gateway"
      "pref-src"
      "routing-table"
      "scope"
      "target-scope"
      "vrf-interface"
    ];
  }
  {
    path = "/ipv6 settings";
    kind = "object";
    attrs = [
      "accept-redirects"
      "accept-router-advertisements"
      "accept-router-advertisements-on"
      "allow-fast-path"
      "disable-ipv6"
      "disable-link-local-address"
      "forward"
      "max-neighbor-entries"
      "min-neighbor-entries"
      "multipath-hash-policy"
      "soft-max-neighbor-entries"
      "stale-neighbor-detect-interval"
      "stale-neighbor-timeout"
    ];
  }
  {
    path = "/mpls interface";
    kind = "list";
    attrs = [
      "comment"
      "copy-from"
      "disabled"
      "input"
      "interface"
      "mpls-mtu"
      "place-before"
    ];
  }
  {
    path = "/mpls ldp";
    kind = "list";
    attrs = [
      "afi"
      "comment"
      "copy-from"
      "disabled"
      "distribute-for-default"
      "hop-limit"
      "loop-detect"
      "lsr-id"
      "path-vector-limit"
      "preferred-afi"
      "transport-addresses"
      "use-explicit-null"
      "vrf"
    ];
  }
  {
    path = "/mpls ldp accept-filter";
    kind = "list";
    attrs = [
      "accept"
      "comment"
      "copy-from"
      "disabled"
      "neighbor"
      "place-before"
      "prefix"
      "vrf"
    ];
  }
  {
    path = "/mpls ldp advertise-filter";
    kind = "list";
    attrs = [
      "advertise"
      "comment"
      "copy-from"
      "disabled"
      "neighbor"
      "place-before"
      "prefix"
      "vrf"
    ];
  }
  {
    path = "/mpls ldp interface";
    kind = "list";
    attrs = [
      "accept-dynamic-neighbors"
      "afi"
      "comment"
      "copy-from"
      "disabled"
      "hello-interval"
      "hold-time"
      "interface"
      "transport-addresses"
    ];
  }
  {
    path = "/mpls ldp local-mapping";
    kind = "list";
    attrs = [
      "comment"
      "copy-from"
      "disabled"
      "dst-address"
      "label"
      "vrf"
    ];
  }
  {
    path = "/mpls ldp neighbor";
    kind = "list";
    attrs = [
      "comment"
      "copy-from"
      "disabled"
      "send-targeted"
      "transport"
    ];
  }
  {
    path = "/mpls ldp remote-mapping";
    kind = "list";
    attrs = [
      "comment"
      "copy-from"
      "disabled"
      "dst-address"
      "label"
      "nexthop"
      "vrf"
    ];
  }
  {
    path = "/mpls mangle";
    kind = "list";
    attrs = [
      "chain"
      "comment"
      "copy-from"
      "disabled"
      "exp"
      "set-exp"
      "set-mark"
    ];
  }
  {
    path = "/mpls settings";
    kind = "object";
    attrs = [
      "allow-fast-path"
      "dynamic-label-range"
      "propagate-ttl"
    ];
  }
  {
    path = "/mpls traffic-eng interface";
    kind = "list";
    attrs = [
      "bandwidth"
      "blockade-k-factor"
      "comment"
      "copy-from"
      "disabled"
      "down-flood-thresholds"
      "igp-flood-period"
      "interface"
      "k-factor"
      "refresh-time"
      "resource-class"
      "te-metric"
      "up-flood-thresholds"
      "use-udp"
    ];
  }
  {
    path = "/mpls traffic-eng path";
    kind = "list";
    attrs = [
      "affinity-exclude"
      "affinity-include-all"
      "affinity-include-any"
      "comment"
      "copy-from"
      "disabled"
      "holding-priority"
      "hops"
      "name"
      "record-route"
      "reoptimize-interval"
      "setup-priority"
      "use-cspf"
    ];
  }
  {
    path = "/mpls traffic-eng tunnel";
    kind = "list";
    attrs = [
      "affinity-exclude"
      "affinity-include-all"
      "affinity-include-any"
      "auto-bandwidth-avg-interval"
      "auto-bandwidth-range"
      "auto-bandwidth-reserve"
      "auto-bandwidth-update-interval"
      "bandwidth"
      "bandwidth-limit"
      "comment"
      "copy-from"
      "disabled"
      "from-address"
      "holding-priority"
      "name"
      "primary-path"
      "primary-retry-interval"
      "record-route"
      "reoptimize-interval"
      "secondary-paths"
      "secondary-standby"
      "setup-priority"
      "to-address"
      "vrf"
    ];
  }
  {
    path = "/port";
    kind = "object";
    attrs = [
      "baud-rate"
      "data-bits"
      "dtr"
      "flow-control"
      "latency-timer"
      "name"
      "numbers"
      "parity"
      "rts"
      "stop-bits"
    ];
  }
  {
    path = "/port remote-access";
    kind = "list";
    attrs = [
      "channel"
      "comment"
      "copy-from"
      "disabled"
      "ip-port"
      "local-address"
      "log-file"
      "port"
      "protocol"
      "remote-addresses"
    ];
  }
  {
    path = "/ppp aaa";
    kind = "object";
    attrs = [
      "accounting"
      "enable-ipv6-accounting"
      "interim-update"
      "use-circuit-id-in-nas-port-id"
      "use-radius"
    ];
  }
  {
    path = "/ppp l2tp-secret";
    kind = "list";
    attrs = [
      "address"
      "comment"
      "copy-from"
      "secret"
    ];
  }
  {
    path = "/ppp profile";
    kind = "list";
    attrs = [
      "address-list"
      "bridge"
      "bridge-horizon"
      "bridge-learning"
      "bridge-path-cost"
      "bridge-port-priority"
      "bridge-port-trusted"
      "bridge-port-vid"
      "change-tcp-mss"
      "comment"
      "copy-from"
      "dhcpv6-lease-time"
      "dhcpv6-pd-pool"
      "dhcpv6-use-radius"
      "dns-server"
      "idle-timeout"
      "incoming-filter"
      "insert-queue-before"
      "interface-list"
      "local-address"
      "name"
      "on-down"
      "on-up"
      "only-one"
      "outgoing-filter"
      "parent-queue"
      "queue-type"
      "rate-limit"
      "remote-address"
      "remote-ipv6-prefix-pool"
      "remote-ipv6-prefix-reuse"
      "session-timeout"
      "use-compression"
      "use-encryption"
      "use-ipv6"
      "use-mpls"
      "use-upnp"
      "wins-server"
    ];
    # multi-value: written as a list in the typed menu (device type only)
    lists = [
      "address-list"
    ];
  }
  {
    path = "/ppp secret";
    kind = "list";
    attrs = [
      "caller-id"
      "comment"
      "copy-from"
      "disabled"
      "ipv6-routes"
      "limit-bytes-in"
      "limit-bytes-out"
      "local-address"
      "name"
      "password"
      "profile"
      "remote-address"
      "remote-ipv6-prefix"
      "routes"
      "service"
    ];
  }
  {
    path = "/queue interface";
    kind = "object";
    attrs = [
      "numbers"
      "queue"
    ];
  }
  {
    path = "/queue simple";
    kind = "list";
    attrs = [
      "bucket-size"
      "burst-limit"
      "burst-threshold"
      "burst-time"
      "comment"
      "copy-from"
      "disabled"
      "dst"
      "limit-at"
      "max-limit"
      "name"
      "packet-marks"
      "parent"
      "place-before"
      "priority"
      "queue"
      "target"
      "time"
      "total-bucket-size"
      "total-burst-limit"
      "total-burst-threshold"
      "total-burst-time"
      "total-limit-at"
      "total-max-limit"
      "total-priority"
      "total-queue"
    ];
    # multi-value: written as a list in the typed menu
    lists = [
      "packet-marks"
      "target"
    ];
  }
  {
    path = "/queue tree";
    kind = "list";
    attrs = [
      "bucket-size"
      "burst-limit"
      "burst-threshold"
      "burst-time"
      "comment"
      "copy-from"
      "disabled"
      "limit-at"
      "max-limit"
      "name"
      "packet-mark"
      "parent"
      "priority"
      "queue"
    ];
  }
  {
    path = "/queue type";
    kind = "list";
    attrs = [
      "bfifo-limit"
      "cake-ack-filter"
      "cake-atm"
      "cake-autorate-ingress"
      "cake-bandwidth"
      "cake-diffserv"
      "cake-flowmode"
      "cake-memlimit"
      "cake-mpu"
      "cake-nat"
      "cake-overhead"
      "cake-overhead-scheme"
      "cake-rtt"
      "cake-rtt-scheme"
      "cake-wash"
      "codel-ce-threshold"
      "codel-ecn"
      "codel-interval"
      "codel-limit"
      "codel-target"
      "copy-from"
      "fq-codel-ce-threshold"
      "fq-codel-ecn"
      "fq-codel-flows"
      "fq-codel-interval"
      "fq-codel-limit"
      "fq-codel-memlimit"
      "fq-codel-quantum"
      "fq-codel-target"
      "kind"
      "mq-pfifo-limit"
      "name"
      "pcq-burst-rate"
      "pcq-burst-threshold"
      "pcq-burst-time"
      "pcq-classifier"
      "pcq-dst-address-mask"
      "pcq-dst-address6-mask"
      "pcq-limit"
      "pcq-rate"
      "pcq-src-address-mask"
      "pcq-src-address6-mask"
      "pcq-total-limit"
      "pfifo-limit"
      "red-avg-packet"
      "red-burst"
      "red-limit"
      "red-max-threshold"
      "red-min-threshold"
      "sfq-allot"
      "sfq-perturb"
    ];
  }
  {
    path = "/radius";
    kind = "list";
    attrs = [
      "accounting-backup"
      "accounting-port"
      "address"
      "authentication-port"
      "called-id"
      "certificate"
      "comment"
      "copy-from"
      "disabled"
      "domain"
      "place-before"
      "protocol"
      "radsec-timeout"
      "realm"
      "require-message-auth"
      "secret"
      "service"
      "src-address"
      "timeout"
    ];
  }
  {
    path = "/radius incoming";
    kind = "object";
    attrs = [
      "accept"
      "port"
      "vrf"
    ];
  }
  {
    path = "/routing bfd configuration";
    kind = "list";
    attrs = [
      "address-list"
      "addresses"
      "comment"
      "copy-from"
      "disabled"
      "forbid-bfd"
      "interfaces"
      "min-rx"
      "min-tx"
      "multiplier"
      "place-before"
      "vrf"
    ];
  }
  {
    path = "/routing bgp connection";
    kind = "list";
    attrs = [
      "afi"
      "as"
      "cisco-vpls-nlri-len-fmt"
      "comment"
      "connect"
      "copy-from"
      "disabled"
      "hold-time"
      "input.accept-communities"
      "input.accept-ext-communities"
      "input.accept-large-communities"
      "input.accept-nlri"
      "input.add-path"
      "input.affinity"
      "input.allow-as"
      "input.attr-error-handling"
      "input.filter"
      "input.filter-communities"
      "input.filter-ext-communities"
      "input.filter-large-communities"
      "input.filter-nlri"
      "input.filter-unknown"
      "input.limit-process-routes-ipv4"
      "input.limit-process-routes-ipv6"
      "instance"
      "keepalive-time"
      "listen"
      "local.address"
      "local.port"
      "local.role"
      "local.ttl"
      "multihop"
      "name"
      "nexthop-choice"
      "output.add-path"
      "output.affinity"
      "output.as-override"
      "output.default-originate"
      "output.default-prepend"
      "output.filter-chain"
      "output.filter-select"
      "output.keep-sent-attributes"
      "output.network"
      "output.network-blackhole"
      "output.no-client-to-client-reflection"
      "output.no-early-cut"
      "output.redistribute"
      "output.remove-private-as"
      "remote.address"
      "remote.allowed-as"
      "remote.as"
      "remote.port"
      "remote.ttl"
      "routing-table"
      "save-to"
      "tcp-md5-key"
      "templates"
      "use-bfd"
      "vrf"
    ];
  }
  {
    path = "/routing bgp evpn";
    kind = "list";
    attrs = [
      "comment"
      "copy-from"
      "disabled"
      "export.route-targets"
      "import.route-targets"
      "instance"
      "name"
      "place-before"
      "rd"
      "vni"
      "vrf"
    ];
  }
  {
    path = "/routing bgp instance";
    kind = "list";
    attrs = [
      "always-compare-med"
      "as"
      "cluster-id"
      "comment"
      "copy-from"
      "disabled"
      "ignore-as-path-len"
      "multipath"
      "name"
      "router-id"
      "routing-table"
      "vrf"
    ];
  }
  {
    path = "/routing bgp template";
    kind = "list";
    attrs = [
      "afi"
      "as"
      "cisco-vpls-nlri-len-fmt"
      "comment"
      "copy-from"
      "disabled"
      "hold-time"
      "input.accept-communities"
      "input.accept-ext-communities"
      "input.accept-large-communities"
      "input.accept-nlri"
      "input.add-path"
      "input.affinity"
      "input.allow-as"
      "input.attr-error-handling"
      "input.filter"
      "input.filter-communities"
      "input.filter-ext-communities"
      "input.filter-large-communities"
      "input.filter-nlri"
      "input.filter-unknown"
      "input.limit-process-routes-ipv4"
      "input.limit-process-routes-ipv6"
      "keepalive-time"
      "multihop"
      "name"
      "nexthop-choice"
      "output.add-path"
      "output.affinity"
      "output.as-override"
      "output.default-originate"
      "output.default-prepend"
      "output.filter-chain"
      "output.filter-select"
      "output.keep-sent-attributes"
      "output.network"
      "output.network-blackhole"
      "output.no-client-to-client-reflection"
      "output.no-early-cut"
      "output.redistribute"
      "output.remove-private-as"
      "routing-table"
      "save-to"
      "templates"
      "use-bfd"
      "vrf"
    ];
  }
  {
    path = "/routing bgp vpls";
    kind = "list";
    attrs = [
      "bridge"
      "bridge-cost"
      "bridge-horizon"
      "bridge-pvid"
      "cisco-id"
      "comment"
      "copy-from"
      "disabled"
      "export-route-targets"
      "import-route-targets"
      "interface-list"
      "local-pref"
      "name"
      "pw-control-word"
      "pw-l2mtu"
      "pw-type"
      "rd"
      "site-id"
      "vrf"
    ];
  }
  {
    path = "/routing bgp vpn";
    kind = "list";
    attrs = [
      "comment"
      "copy-from"
      "disabled"
      "export.filter-chain"
      "export.filter-select"
      "export.redistribute"
      "export.route-targets"
      "import.filter-chain"
      "import.route-targets"
      "instance"
      "label-allocation-policy"
      "name"
      "route-distinguisher"
      "vrf"
    ];
  }
  {
    path = "/routing fantasy";
    kind = "list";
    attrs = [
      "comment"
      "copy-from"
      "count"
      "dealer-id"
      "disabled"
      "dst-address"
      "gateway"
      "instance-id"
      "name"
      "offset"
      "prefix-length"
      "priv-offs"
      "priv-size"
      "scope"
      "seed"
      "target-scope"
      "use-hold"
    ];
  }
  {
    path = "/routing filter community-ext-list";
    kind = "list";
    attrs = [
      "comment"
      "communities"
      "copy-from"
      "disabled"
      "list"
      "place-before"
      "regexp"
    ];
  }
  {
    path = "/routing filter community-large-list";
    kind = "list";
    attrs = [
      "comment"
      "communities"
      "copy-from"
      "disabled"
      "list"
      "place-before"
      "regexp"
    ];
  }
  {
    path = "/routing filter community-list";
    kind = "list";
    attrs = [
      "comment"
      "communities"
      "copy-from"
      "disabled"
      "list"
      "place-before"
      "regexp"
    ];
  }
  {
    path = "/routing filter num-list";
    kind = "list";
    attrs = [
      "comment"
      "copy-from"
      "disabled"
      "list"
      "place-before"
      "range"
    ];
  }
  {
    path = "/routing filter rule";
    kind = "list";
    attrs = [
      "chain"
      "comment"
      "copy-from"
      "disabled"
      "place-before"
      "rule"
    ];
  }
  {
    path = "/routing filter select-rule";
    kind = "list";
    attrs = [
      "chain"
      "comment"
      "copy-from"
      "disabled"
      "do-group-num"
      "do-group-prfx"
      "do-jump"
      "do-select-num"
      "do-select-prfx"
      "do-take"
      "do-where"
      "place-before"
    ];
  }
  {
    path = "/routing gmp";
    kind = "list";
    attrs = [
      "comment"
      "copy-from"
      "disabled"
      "exclude"
      "groups"
      "interfaces"
      "sources"
    ];
  }
  {
    path = "/routing id";
    kind = "list";
    attrs = [
      "comment"
      "copy-from"
      "disabled"
      "id"
      "name"
      "select-dynamic-id"
      "select-from-vrf"
    ];
    # multi-value: written as a list in the typed menu (device type only)
    lists = [
      "select-dynamic-id"
    ];
  }
  {
    path = "/routing igmp-proxy";
    kind = "object";
    attrs = [
      "last-member-query-interval"
      "query-interval"
      "query-response-interval"
      "robustness"
    ];
  }
  {
    path = "/routing igmp-proxy interface";
    kind = "list";
    attrs = [
      "alternative-subnets"
      "comment"
      "copy-from"
      "disabled"
      "interface"
      "last-member-query-interval"
      "query-interval"
      "query-response-interval"
      "robustness"
      "threshold"
      "upstream"
    ];
  }
  {
    path = "/routing igmp-proxy mfc";
    kind = "list";
    attrs = [
      "copy-from"
      "disabled"
      "downstream-interfaces"
      "group"
      "source"
      "upstream-interface"
    ];
  }
  {
    path = "/routing isis instance";
    kind = "list";
    attrs = [
      "afi"
      "areas"
      "areas-max"
      "comment"
      "copy-from"
      "disabled"
      "in-filter-chain"
      "l1.lsp-max-age"
      "l1.lsp-max-size"
      "l1.lsp-refresh-interval"
      "l1.lsp-update-interval"
      "l1.originate-default"
      "l1.out-filter-chain"
      "l1.out-filter-select"
      "l1.redistribute"
      "l2.lsp-max-age"
      "l2.lsp-max-size"
      "l2.lsp-refresh-interval"
      "l2.lsp-update-interval"
      "l2.originate-default"
      "l2.out-filter-chain"
      "l2.out-filter-select"
      "l2.redistribute"
      "metric-type"
      "name"
      "system-id"
      "vrf"
    ];
  }
  {
    path = "/routing isis interface";
    kind = "object";
    attrs = [
      "hello-interval"
      "instance"
      "interface"
      "l1.csnp-interval"
      "l1.hello-dr-interval"
      "l1.hello-interval"
      "l1.hello-multiplier"
      "l1.metric"
      "l1.passive"
      "l1.priority"
      "l1.psnp-interval"
      "l2.csnp-interval"
      "l2.hello-dr-interval"
      "l2.hello-interval"
      "l2.hello-multiplier"
      "l2.metric"
      "l2.passive"
      "l2.priority"
      "l2.psnp-interval"
      "numbers"
      "ptp"
      "ptp.3way-state"
      "ptp.usage"
    ];
  }
  {
    path = "/routing isis interface-template";
    kind = "list";
    attrs = [
      "bcast.l1.csnp-interval"
      "bcast.l1.hello-interval"
      "bcast.l1.hello-interval-dr"
      "bcast.l1.hello-multiplier"
      "bcast.l1.metric"
      "bcast.l1.priority"
      "bcast.l1.psnp-interval"
      "bcast.l2.csnp-interval"
      "bcast.l2.hello-interval"
      "bcast.l2.hello-interval-dr"
      "bcast.l2.hello-multiplier"
      "bcast.l2.metric"
      "bcast.l2.priority"
      "bcast.l2.psnp-interval"
      "comment"
      "copy-from"
      "disabled"
      "instance"
      "interfaces"
      "levels"
      "passive"
      "place-before"
      "ptp"
      "ptp.hello-3way"
      "ptp.hello-interval"
      "ptp.hello-multiplier"
      "ptp.l1.csnp-interval"
      "ptp.l1.metric"
      "ptp.l1.psnp-interval"
      "ptp.l2.csnp-interval"
      "ptp.l2.metric"
      "ptp.l2.psnp-interval"
    ];
  }
  {
    path = "/routing isis lsp";
    kind = "object";
    attrs = [
      "age"
      "body"
      "checksum"
      "instance"
      "level"
      "lsp-id"
      "numbers"
      "sequence"
    ];
  }
  {
    path = "/routing isis neighbor";
    kind = "object";
    attrs = [
      "instance"
      "interface"
      "level-type"
      "numbers"
      "snpa"
      "srcid"
      "state"
    ];
  }
  {
    path = "/routing ospf area";
    kind = "list";
    attrs = [
      "area-id"
      "comment"
      "copy-from"
      "default-cost"
      "disabled"
      "instance"
      "name"
      "no-summaries"
      "nssa-translator"
      "type"
    ];
  }
  {
    path = "/routing ospf area range";
    kind = "list";
    attrs = [
      "advertise"
      "area"
      "comment"
      "copy-from"
      "cost"
      "disabled"
      "prefix"
    ];
  }
  {
    path = "/routing ospf instance";
    kind = "list";
    attrs = [
      "comment"
      "copy-from"
      "disabled"
      "domain-id"
      "domain-tag"
      "in-filter-chain"
      "mpls-te-address"
      "mpls-te-area"
      "name"
      "originate-default"
      "out-filter-chain"
      "out-filter-select"
      "redistribute"
      "router-id"
      "routing-table"
      "use-dn"
      "version"
      "vrf"
    ];
    # multi-value: written as a list in the typed menu
    lists = [
      "redistribute"
    ];
  }
  {
    path = "/routing ospf interface";
    kind = "list";
    attrs = [
      "address"
      "area"
      "auth"
      "auth-id"
      "auth-key"
      "comment"
      "copy-from"
      "cost"
      "dead-interval"
      "disabled"
      "hello-interval"
      "instance-id"
      "interface"
      "passive"
      "priority"
      "retransmit-interval"
      "transmit-delay"
      "type"
      "use-bfd"
      "vlink-neighbor-id"
      "vlink-transit-area"
    ];
  }
  {
    path = "/routing ospf interface-template";
    kind = "list";
    attrs = [
      "area"
      "auth"
      "auth-id"
      "auth-key"
      "comment"
      "copy-from"
      "cost"
      "dead-interval"
      "disabled"
      "hello-interval"
      "instance-id"
      "interfaces"
      "networks"
      "passive"
      "place-before"
      "prefix-list"
      "priority"
      "retransmit-interval"
      "transmit-delay"
      "type"
      "use-bfd"
    ];
  }
  {
    path = "/routing ospf neighbor";
    kind = "object";
    attrs = [
      "comment"
      "numbers"
    ];
  }
  {
    path = "/routing ospf static-neighbor";
    kind = "list";
    attrs = [
      "address"
      "area"
      "comment"
      "copy-from"
      "disabled"
      "instance-id"
      "poll-interval"
    ];
  }
  {
    path = "/routing pimsm bsr candidate";
    kind = "list";
    attrs = [
      "address"
      "copy-from"
      "disabled"
      "hash-mask-length"
      "instance"
      "priority"
      "scope4"
      "scope6"
    ];
  }
  {
    path = "/routing pimsm bsr rp-candidate";
    kind = "list";
    attrs = [
      "address"
      "copy-from"
      "disabled"
      "group"
      "holdtime"
      "instance"
      "priority"
    ];
  }
  {
    path = "/routing pimsm igmp-interface-template";
    kind = "list";
    attrs = [
      "copy-from"
      "disabled"
      "instance"
      "interfaces"
      "last-member-query-interval"
      "place-before"
      "query-interval"
      "query-response-interval"
      "robustness"
    ];
  }
  {
    path = "/routing pimsm instance";
    kind = "list";
    attrs = [
      "afi"
      "bsm-forward-back"
      "copy-from"
      "crp-advertise-contained"
      "disabled"
      "name"
      "rp-hash-mask-length"
      "rp-static-override"
      "ssm-range"
      "switch-to-spt"
      "switch-to-spt-bytes"
      "switch-to-spt-interval"
      "vrf"
    ];
  }
  {
    path = "/routing pimsm interface-template";
    kind = "list";
    attrs = [
      "copy-from"
      "disabled"
      "hello-delay"
      "hello-period"
      "instance"
      "interfaces"
      "join-prune-period"
      "join-tracking-support"
      "override-interval"
      "place-before"
      "priority"
      "propagation-delay"
      "source-addresses"
    ];
  }
  {
    path = "/routing pimsm static-rp";
    kind = "list";
    attrs = [
      "address"
      "comment"
      "copy-from"
      "disabled"
      "group"
      "instance"
    ];
  }
  {
    path = "/routing rip instance";
    kind = "list";
    attrs = [
      "afi"
      "copy-from"
      "disabled"
      "in-filter-chain"
      "name"
      "originate-default"
      "out-filter-chain"
      "out-filter-select"
      "redistribute"
      "route-gc-timeout"
      "route-timeout"
      "routing-table"
      "update-interval"
      "vrf"
    ];
    # multi-value: written as a list in the typed menu
    lists = [
      "redistribute"
    ];
  }
  {
    path = "/routing rip interface-template";
    kind = "list";
    attrs = [
      "copy-from"
      "cost"
      "disabled"
      "instance"
      "interfaces"
      "key-chain"
      "mode"
      "password"
      "poison-reverse"
      "source-addresses"
      "split-horizon"
      "use-bfd"
    ];
  }
  {
    path = "/routing rip keys";
    kind = "list";
    attrs = [
      "chain"
      "copy-from"
      "disabled"
      "key"
      "key-id"
      "valid-from"
      "valid-till"
    ];
  }
  {
    path = "/routing rip static-neighbor";
    kind = "list";
    attrs = [
      "address"
      "copy-from"
      "disabled"
      "instance"
    ];
  }
  {
    path = "/routing route";
    kind = "object";
    attrs = [
      "comment"
      "disabled"
      "numbers"
    ];
  }
  {
    path = "/routing rpki";
    kind = "list";
    attrs = [
      "address"
      "comment"
      "copy-from"
      "disabled"
      "expire-interval"
      "group"
      "port"
      "preference"
      "refresh-interval"
      "retry-interval"
      "vrf"
    ];
  }
  {
    path = "/routing rule";
    kind = "list";
    attrs = [
      "action"
      "chain"
      "comment"
      "copy-from"
      "disabled"
      "dst-address"
      "interface"
      "min-prefix"
      "place-before"
      "realm"
      "routing-mark"
      "src-address"
      "table"
      "vrf"
    ];
  }
  {
    path = "/routing settings";
    kind = "object";
    attrs = [
      "check-gateway-ping-count"
      "check-gateway-ping-interval"
      "check-gateway-ping-timeout"
      "connected-in-chain"
      "dynamic-in-chain"
      "policy-rules"
      "single-process"
    ];
  }
  {
    path = "/routing table";
    kind = "list";
    attrs = [
      "comment"
      "copy-from"
      "disabled"
      "fib"
      "name"
    ];
  }
  {
    path = "/snmp";
    kind = "object";
    attrs = [
      "contact"
      "enabled"
      "engine-id-suffix"
      "location"
      "src-address"
      "trap-community"
      "trap-generators"
      "trap-interfaces"
      "trap-target"
      "trap-version"
      "vrf"
    ];
    # multi-value: written as a list in the typed menu
    lists = [
      "trap-generators"
      "trap-interfaces"
      "trap-target"
    ];
  }
  {
    path = "/snmp community";
    kind = "list";
    attrs = [
      "addresses"
      "authentication-password"
      "authentication-protocol"
      "comment"
      "copy-from"
      "denied-oids"
      "disabled"
      "encryption-password"
      "encryption-protocol"
      "name"
      "read-access"
      "security"
      "write-access"
    ];
    # multi-value: written as a list in the typed menu (device type only)
    lists = [
      "addresses"
      "denied-oids"
    ];
  }
  {
    path = "/special-login";
    kind = "list";
    attrs = [
      "channel"
      "copy-from"
      "disabled"
      "port"
      "user"
    ];
  }
  {
    path = "/suggestion";
    kind = "object";
    attrs = [
      "comment"
      "disabled"
      "numbers"
    ];
  }
  {
    path = "/system clock";
    kind = "object";
    attrs = [
      "date"
      "time"
      "time-zone-autodetect"
      "time-zone-name"
    ];
  }
  {
    path = "/system clock manual";
    kind = "object";
    attrs = [
      "dst-delta"
      "dst-end"
      "dst-start"
      "time-zone"
    ];
  }
  {
    path = "/system console";
    kind = "list";
    attrs = [
      "channel"
      "copy-from"
      "disabled"
      "port"
      "term"
    ];
  }
  {
    path = "/system console screen";
    kind = "object";
    attrs = [
      "blank-interval"
      "line-count"
    ];
  }
  {
    path = "/system dashboard settings";
    kind = "object";
    attrs = [
      "uplink-interfaces"
    ];
    # multi-value: written as a list in the typed menu
    lists = [
      "uplink-interfaces"
    ];
  }
  {
    path = "/system health";
    kind = "object";
    attrs = [
      "state-after-reboot"
    ];
  }
  {
    path = "/system keymat-provider";
    kind = "list";
    attrs = [
      "copy-from"
      "disabled"
      "hkdf-hash"
      "hkdf-secret"
      "key-size"
      "name"
      "qkd-address"
      "qkd-cache-size"
      "qkd-certificate"
      "qkd-kme-id"
      "qkd-peer-sae-id"
      "type"
    ];
  }
  {
    path = "/system leds";
    kind = "list";
    attrs = [
      "color"
      "copy-from"
      "disabled"
      "interface"
      "leds"
      "modem-signal-threshold"
      "type"
    ];
  }
  {
    path = "/system leds settings";
    kind = "object";
    attrs = [
      "all-leds-off"
    ];
  }
  {
    path = "/system logging";
    kind = "list";
    attrs = [
      "action"
      "comment"
      "copy-from"
      "disabled"
      "prefix"
      "regex"
      "topics"
    ];
    # multi-value: written as a list in the typed menu (device type only)
    lists = [
      "topics"
    ];
  }
  {
    path = "/system logging action";
    kind = "list";
    attrs = [
      "add-topics-string"
      "cef-event-delimiter"
      "check-certificate"
      "comment"
      "copy-from"
      "disk-file-count"
      "disk-file-name"
      "disk-lines-per-file"
      "disk-stop-on-full"
      "email-cc"
      "email-start-tls"
      "email-to"
      "memory-lines"
      "memory-stop-on-full"
      "name"
      "remember"
      "remote"
      "remote-log-format"
      "remote-port"
      "remote-protocol"
      "script"
      "src-address"
      "syslog-facility"
      "syslog-severity"
      "syslog-time-format"
      "target"
      "vrf"
    ];
  }
  {
    path = "/system note";
    kind = "object";
    attrs = [
      "note"
      "show-at-cli-login"
      "show-at-login"
    ];
  }
  {
    path = "/system ntp client";
    kind = "object";
    attrs = [
      "enabled"
      "mode"
      "servers"
      "vrf"
    ];
    # multi-value: written as a list in the typed menu
    lists = [
      "servers"
    ];
  }
  {
    path = "/system ntp client servers";
    kind = "list";
    attrs = [
      "address"
      "auth-key"
      "comment"
      "copy-from"
      "disabled"
      "iburst"
      "max-poll"
      "min-poll"
    ];
  }
  {
    path = "/system ntp key";
    kind = "list";
    attrs = [
      "comment"
      "copy-from"
      "key-id"
      "key-val"
    ];
  }
  {
    path = "/system ntp server";
    kind = "object";
    attrs = [
      "auth-key"
      "broadcast"
      "broadcast-addresses"
      "enabled"
      "local-clock-stratum"
      "manycast"
      "multicast"
      "use-local-clock"
      "vrf"
    ];
    # multi-value: written as a list in the typed menu
    lists = [
      "broadcast-addresses"
    ];
  }
  {
    path = "/system package local-update mirror";
    kind = "object";
    attrs = [
      "check-interval"
      "enabled"
      "password"
      "primary-server"
      "secondary-server"
      "user"
    ];
  }
  {
    path = "/system package local-update update-package-source";
    kind = "list";
    attrs = [
      "address"
      "copy-from"
      "password"
      "user"
    ];
  }
  {
    path = "/system package update";
    kind = "object";
    attrs = [
      "channel"
      "check-certificate"
      "ip-version"
      "mode"
    ];
  }
  {
    path = "/system ptp";
    kind = "list";
    attrs = [
      "comment"
      "copy-from"
      "delay-mode"
      "disabled"
      "domain"
      "name"
      "priority1"
      "priority2"
      "profile"
      "ptp-mode"
      "transport"
    ];
  }
  {
    path = "/system ptp port";
    kind = "list";
    attrs = [
      "announce-interval"
      "comment"
      "copy-from"
      "delay-interval"
      "disabled"
      "egress-latency"
      "ingress-latency"
      "interface"
      "pdelay-interval"
      "ptp"
      "role"
      "sync-interval"
      "vlan-id"
    ];
  }
  {
    path = "/system resource hardware usb-settings";
    kind = "object";
    attrs = [
      "authorization"
    ];
  }
  {
    path = "/system resource irq";
    kind = "object";
    attrs = [
      "cpu"
      "numbers"
    ];
  }
  {
    path = "/system resource irq rps";
    kind = "object";
    attrs = [
      "disabled"
      "numbers"
    ];
  }
  {
    path = "/system scheduler";
    kind = "list";
    attrs = [
      "comment"
      "copy-from"
      "days"
      "disabled"
      "interval"
      "name"
      "on-event"
      "policy"
      "start-date"
      "start-time"
    ];
    # multi-value: written as a list in the typed menu
    lists = [
      "policy"
    ];
  }
  {
    path = "/system script";
    kind = "list";
    attrs = [
      "comment"
      "copy-from"
      "dont-require-permissions"
      "name"
      "owner"
      "policy"
      "source"
    ];
    # multi-value: written as a list in the typed menu
    lists = [
      "policy"
    ];
  }
  {
    path = "/system script environment";
    kind = "object";
    attrs = [
      "comment"
      "numbers"
      "value"
    ];
  }
  {
    path = "/system script job";
    kind = "object";
    attrs = [
      "comment"
      "numbers"
      "started"
      "type"
    ];
  }
  {
    path = "/system ups";
    kind = "list";
    attrs = [
      "alarm-setting"
      "check-capabilities"
      "comment"
      "copy-from"
      "disabled"
      "min-runtime"
      "name"
      "offline-time"
      "port"
    ];
  }
  {
    path = "/system watchdog";
    kind = "object";
    attrs = [
      "auto-send-supout"
      "automatic-supout"
      "ping-start-after-boot"
      "ping-timeout"
      "send-email-from"
      "send-email-to"
      "send-smtp-server"
      "watch-address"
      "watchdog-timer"
    ];
  }
  {
    path = "/task";
    kind = "list";
    attrs = [
      "append"
      "copy-from"
      "file-name"
      "max-lines"
      "max-size"
      "no-header-paging"
      "save-interval"
      "save-timestamp"
      "source"
      "switch-to"
    ];
  }
  {
    path = "/tool apptraffic";
    kind = "object";
    attrs = [
      "enabled"
    ];
  }
  {
    path = "/tool bandwidth-server";
    kind = "object";
    attrs = [
      "allocate-udp-ports-from"
      "allowed-addresses4"
      "allowed-addresses6"
      "authenticate"
      "enabled"
      "max-sessions"
    ];
    # multi-value: written as a list in the typed menu
    lists = [
      "allowed-addresses4"
    ];
  }
  {
    path = "/tool e-mail";
    kind = "object";
    attrs = [
      "certificate-verification"
      "from"
      "password"
      "port"
      "server"
      "tls"
      "user"
      "vrf"
    ];
  }
  {
    path = "/tool graphing";
    kind = "object";
    attrs = [
      "page-refresh"
      "store-every"
    ];
  }
  {
    path = "/tool graphing interface";
    kind = "list";
    attrs = [
      "allow-address"
      "comment"
      "copy-from"
      "disabled"
      "interface"
      "store-on-disk"
    ];
  }
  {
    path = "/tool graphing queue";
    kind = "list";
    attrs = [
      "allow-address"
      "allow-target"
      "comment"
      "copy-from"
      "disabled"
      "simple-queue"
      "store-on-disk"
    ];
  }
  {
    path = "/tool graphing resource";
    kind = "list";
    attrs = [
      "allow-address"
      "comment"
      "copy-from"
      "disabled"
      "store-on-disk"
    ];
  }
  {
    path = "/tool mac-server";
    kind = "object";
    attrs = [
      "allowed-interface-list"
    ];
  }
  {
    path = "/tool mac-server mac-winbox";
    kind = "object";
    attrs = [
      "allowed-interface-list"
    ];
  }
  {
    path = "/tool mac-server ping";
    kind = "object";
    attrs = [
      "enabled"
    ];
  }
  {
    path = "/tool mac-server sessions";
    kind = "object";
    attrs = [
      "interface"
      "numbers"
      "src-address"
      "uptime"
    ];
  }
  {
    path = "/tool netwatch";
    kind = "list";
    attrs = [
      "accept-icmp-time-exceeded"
      "certificate"
      "check-certificate"
      "comment"
      "copy-from"
      "disabled"
      "dns-server"
      "down-script"
      "early-failure-detection"
      "early-success-detection"
      "host"
      "http-codes"
      "ignore-initial-down"
      "ignore-initial-up"
      "interval"
      "name"
      "packet-count"
      "packet-interval"
      "packet-size"
      "port"
      "record-type"
      "src-address"
      "start-delay"
      "startup-delay"
      "test-script"
      "thr-avg"
      "thr-http-time"
      "thr-jitter"
      "thr-loss-count"
      "thr-loss-percent"
      "thr-max"
      "thr-stdev"
      "thr-tcp-conn-time"
      "timeout"
      "ttl"
      "type"
      "up-script"
    ];
  }
  {
    path = "/tool romon";
    kind = "object";
    attrs = [
      "enabled"
      "id"
      "secrets"
    ];
    # multi-value: written as a list in the typed menu
    lists = [
      "secrets"
    ];
  }
  {
    path = "/tool romon port";
    kind = "list";
    attrs = [
      "comment"
      "copy-from"
      "cost"
      "disabled"
      "forbid"
      "interface"
      "secrets"
    ];
    # multi-value: written as a list in the typed menu (device type only)
    lists = [
      "secrets"
    ];
  }
  {
    path = "/tool sms";
    kind = "object";
    attrs = [
      "allowed-number"
      "channel"
      "polling"
      "port"
      "receive-enabled"
      "remove-sent-sms-after-send"
      "secret"
      "sim-pin"
      "sms-storage"
    ];
    # multi-value: written as a list in the typed menu
    lists = [
      "allowed-number"
    ];
  }
  {
    path = "/tool sniffer";
    kind = "object";
    attrs = [
      "file-limit"
      "file-name"
      "filter-cpu"
      "filter-direction"
      "filter-dst-ip-address"
      "filter-dst-ipv6-address"
      "filter-dst-mac-address"
      "filter-dst-port"
      "filter-interface"
      "filter-ip-address"
      "filter-ip-protocol"
      "filter-ipv6-address"
      "filter-mac-address"
      "filter-mac-protocol"
      "filter-operator-between-entries"
      "filter-port"
      "filter-size"
      "filter-src-ip-address"
      "filter-src-ipv6-address"
      "filter-src-mac-address"
      "filter-src-port"
      "filter-stream"
      "filter-vlan"
      "max-packet-size"
      "memory-limit"
      "memory-scroll"
      "only-headers"
      "quick-rows"
      "quick-show-frame"
      "streaming-enabled"
      "streaming-server"
    ];
    # multi-value: written as a list in the typed menu
    lists = [
      "filter-cpu"
      "filter-dst-ip-address"
      "filter-dst-mac-address"
      "filter-dst-port"
      "filter-interface"
      "filter-ip-address"
      "filter-ip-protocol"
      "filter-mac-address"
      "filter-mac-protocol"
      "filter-port"
      "filter-size"
      "filter-src-ip-address"
      "filter-src-mac-address"
      "filter-src-port"
      "filter-vlan"
    ];
  }
  {
    path = "/tool traffic-generator";
    kind = "object";
    attrs = [
      "latency-distribution-max"
      "measure-out-of-order"
      "stats-samples-to-keep"
      "test-id"
    ];
  }
  {
    path = "/tool traffic-generator packet-template";
    kind = "list";
    attrs = [
      "comment"
      "compute-checksum-from-offset"
      "copy-from"
      "data"
      "data-byte"
      "header-stack"
      "interface"
      "ip-dscp"
      "ip-dst"
      "ip-frag-off"
      "ip-gateway"
      "ip-id"
      "ip-protocol"
      "ip-src"
      "ip-ttl"
      "ipv6-dst"
      "ipv6-flow-label"
      "ipv6-gateway"
      "ipv6-hop-limit"
      "ipv6-next-header"
      "ipv6-src"
      "ipv6-traffic-class"
      "mac-dst"
      "mac-protocol"
      "mac-src"
      "name"
      "port"
      "random-byte-offsets-and-masks"
      "random-ranges"
      "raw-header"
      "special-footer"
      "tcp-ack"
      "tcp-data-offset"
      "tcp-dst-port"
      "tcp-flags"
      "tcp-src-port"
      "tcp-syn"
      "tcp-urgent-pointer"
      "tcp-window-size"
      "udp-checksum"
      "udp-dst-port"
      "udp-src-port"
      "vlan-id"
      "vlan-priority"
      "vlan-protocol"
    ];
    # multi-value: written as a list in the typed menu
    lists = [
      "header-stack"
      "ip-dscp"
      "ip-dst"
      "ip-frag-off"
      "ip-id"
      "ip-protocol"
      "ip-src"
      "ip-ttl"
      "ipv6-flow-label"
      "ipv6-hop-limit"
      "ipv6-next-header"
      "ipv6-traffic-class"
      "mac-dst"
      "mac-protocol"
      "mac-src"
      "random-byte-offsets-and-masks"
      "tcp-ack"
      "tcp-data-offset"
      "tcp-dst-port"
      "tcp-flags"
      "tcp-src-port"
      "tcp-syn"
      "tcp-urgent-pointer"
      "tcp-window-size"
      "udp-checksum"
      "udp-dst-port"
      "udp-src-port"
      "vlan-id"
      "vlan-priority"
      "vlan-protocol"
    ];
  }
  {
    path = "/tool traffic-generator port";
    kind = "list";
    attrs = [
      "copy-from"
      "disabled"
      "interface"
      "name"
    ];
  }
  {
    path = "/tool traffic-generator raw-packet-template";
    kind = "list";
    attrs = [
      "comment"
      "compute-checksum-from-offset"
      "copy-from"
      "data"
      "data-byte"
      "header"
      "ip-header-offset"
      "ipv6-header-offset"
      "name"
      "port"
      "random-byte-offsets-and-masks"
      "random-ranges"
      "special-footer"
      "tcp-header-offset"
      "udp-compute-checksum"
      "udp-header-offset"
    ];
    # multi-value: written as a list in the typed menu
    lists = [
      "ip-header-offset"
      "ipv6-header-offset"
      "random-byte-offsets-and-masks"
    ];
  }
  {
    path = "/tool traffic-generator stream";
    kind = "list";
    attrs = [
      "copy-from"
      "cpu-core"
      "disabled"
      "id"
      "mbps"
      "name"
      "packet-count"
      "packet-size"
      "port"
      "pps"
      "tx-template"
    ];
  }
  {
    path = "/tool traffic-monitor";
    kind = "list";
    attrs = [
      "comment"
      "copy-from"
      "disabled"
      "interface"
      "name"
      "on-event"
      "threshold"
      "traffic"
      "trigger"
    ];
  }
  {
    path = "/user";
    kind = "list";
    attrs = [
      "address"
      "comment"
      "copy-from"
      "disabled"
      "group"
      "inactivity-policy"
      "inactivity-timeout"
      "name"
      "password"
    ];
    # multi-value: written as a list in the typed menu (device type only)
    lists = [
      "address"
    ];
  }
  {
    path = "/user aaa";
    kind = "object";
    attrs = [
      "accounting"
      "default-group"
      "exclude-groups"
      "interim-update"
      "use-radius"
    ];
    # multi-value: written as a list in the typed menu
    lists = [
      "exclude-groups"
    ];
  }
  {
    path = "/user active";
    kind = "list";
    attrs = [
      "copy-from"
    ];
  }
  {
    path = "/user group";
    kind = "list";
    attrs = [
      "comment"
      "copy-from"
      "name"
      "policy"
      "skin"
    ];
    # multi-value: written as a list in the typed menu (device type only)
    lists = [
      "policy"
    ];
  }
  {
    path = "/user settings";
    kind = "object";
    attrs = [
      "minimum-categories"
      "minimum-password-length"
    ];
  }
  {
    path = "/user ssh-keys";
    kind = "list";
    attrs = [
      "comment"
      "copy-from"
      "info"
      "key"
      "user"
    ];
  }
]
