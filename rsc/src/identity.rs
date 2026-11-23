//! Which object is which.
//!
//! RouterOS' internal `.id` is not in an `/export` and is not stable across a
//! reboot, so identity has to come from the configuration text. Each menu
//! answers the question differently, and the table below is the whole answer:
//!
//! * **Named** — one property names the object (`/ip pool name=…`).
//! * **Composite** — several properties together do (`/ip address
//!   address=… interface=…`, since the same address may sit on two interfaces).
//! * **Ordered** — nothing names the object, so position is all there is. A
//!   firewall rule is the case that matters; see [`crate::diff`] for what the
//!   differ does about it.
//!
//! Where a `set` line in the source already carries a selector, that selector
//! wins: it is what the device itself used to address the object, so a
//! `set [find default-name=ether1]` and an `add name=ether1` describe the same
//! object and both key as `name=ether1`.

use crate::model::{Prop, Selector};
use crate::syntax::{Tok, TokKind};

/// How a menu identifies its objects.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Identity {
    /// The menu holds one settings object (`/ip dns`).
    Singleton,
    /// One property names the object.
    Named(&'static str),
    /// These properties together identify the object.
    Composite(&'static [&'static str]),
    /// No stable identity; position is the only handle.
    Ordered,
}

/// The identity rule for a menu path, spelled as the menu is written without
/// its leading slash (`ip firewall filter`).
pub fn identity_for(menu: &str) -> Identity {
    match menu {
        // Settings objects: `set k=v` with no selector.
        "system identity"
        | "system clock"
        | "system note"
        | "system routerboard"
        | "system ntp client"
        | "ip dns"
        | "ip cloud"
        | "ip ssh"
        | "ip settings"
        | "ip neighbor discovery-settings"
        | "ip upnp"
        | "ip socks"
        | "ip tftp settings"
        | "tool bandwidth-server"
        | "tool mac-server"
        | "tool mac-server ping"
        | "tool mac-server mac-winbox"
        | "tool romon"
        | "tool sms"
        | "ip firewall connection tracking"
        | "ipv6 settings"
        | "interface detect-internet"
        | "snmp"
        | "system watchdog"
        | "system leds settings"
        | "disk" => Identity::Singleton,

        // One name per object.
        "interface bridge"
        | "interface ethernet"
        | "interface wireguard"
        | "interface vlan"
        | "interface vrrp"
        | "interface bonding"
        | "interface bridge vlan"
        | "interface list"
        | "interface ppp-client"
        | "interface lte"
        | "interface gre"
        | "interface eoip"
        | "interface ipip"
        | "interface sit"
        | "interface veth"
        | "interface ovpn-client"
        | "interface wireguard peers"
        | "interface vrf"
        | "interface macvlan"
        | "ip pool"
        | "ipv6 pool"
        | "ip dhcp-server"
        | "ipv6 dhcp-server"
        | "ip dns static"
        | "ip service"
        | "ip vrf"
        | "ip hotspot"
        | "ip hotspot user"
        | "ip smb"
        | "ip tftp"
        | "system script"
        | "system scheduler"
        | "system user"
        | "system user group"
        | "system backup"
        | "system package"
        | "system logging action"
        | "routing table"
        | "routing bgp instance"
        | "routing ospf instance"
        | "queue simple"
        | "queue type"
        | "queue tree"
        | "port"
        | "ppp secret"
        | "ppp profile"
        | "radius"
        | "certificate"
        | "container"
        | "container envs"
        | "ip kid control"
        | "user aaa" => Identity::Named("name"),

        // Several properties together.
        "interface list member" => Identity::Composite(&["list", "interface"]),
        "interface bridge port" => Identity::Composite(&["bridge", "interface"]),
        "ip address" | "ipv6 address" => Identity::Composite(&["address", "interface"]),
        "ip dhcp-server network" => Identity::Composite(&["address"]),
        "ip dhcp-client" | "ipv6 dhcp-client" => Identity::Composite(&["interface"]),
        "ip dhcp-server lease" => Identity::Composite(&["address", "mac-address"]),
        "ip firewall address-list" | "ipv6 firewall address-list" => {
            Identity::Composite(&["list", "address"])
        }
        "ip route" | "ipv6 route" => {
            Identity::Composite(&["dst-address", "gateway", "routing-mark", "vrf-interface"])
        }
        "ip firewall filter"
        | "ip firewall nat"
        | "ip firewall mangle"
        | "ip firewall raw"
        | "ip firewall filter rule" => Identity::Ordered,

        // Switch menus: a CRS-class device exports these and they have a
        // natural key even though it is not a name.
        "interface ethernet switch egress-vlan-tag" => Identity::Composite(&["vlan-id"]),
        "interface ethernet switch ingress-vlan-translation" => {
            Identity::Composite(&["ports", "customer-vid"])
        }
        "interface ethernet switch vlan" => Identity::Composite(&["vlan-id", "ports"]),
        "interface ethernet switch host" => Identity::Composite(&["mac-address", "vlan-id"]),
        "interface ethernet switch unicast-fdb" => Identity::Composite(&["mac-address", "vlan-id"]),
        "interface ethernet switch multicast-fdb" => {
            Identity::Composite(&["mac-address", "vlan-id"])
        }
        "interface ethernet switch port" => Identity::Named("name"),

        _ => Identity::Ordered,
    }
}

/// Canonicalise selector pairs so that two spellings of the same address compare
/// equal: `default-name` is the same object as `name` once a port has one, and
/// the pair order in a `find` expression carries no meaning.
pub fn normalize_pairs(pairs: &[(String, String)]) -> Vec<(String, String)> {
    let mut out: Vec<(String, String)> = pairs
        .iter()
        .map(|(k, v)| {
            let key = if k == "default-name" { "name" } else { k };
            (key.to_string(), v.clone())
        })
        .collect();
    out.sort();
    out.dedup();
    out
}

fn prop<'a>(props: &'a [Prop], key: &str) -> Option<&'a str> {
    props
        .iter()
        .find(|p| p.key == key)
        .map(|p| p.value.text.as_str())
}

/// Work out the selector for an object created by an `add`.
pub fn selector_from_props(menu: &str, props: &[Prop], index: usize) -> Selector {
    match identity_for(menu) {
        Identity::Singleton => Selector::Singleton,
        Identity::Named(k) => match prop(props, k) {
            Some(v) => Selector::Named(v.to_string()),
            None => fallback_selector(props, index),
        },
        Identity::Composite(keys) => {
            let mut pairs = Vec::new();
            for k in keys {
                if let Some(v) = prop(props, k) {
                    pairs.push((k.to_string(), v.to_string()));
                }
            }
            if pairs.is_empty() {
                fallback_selector(props, index)
            } else {
                Selector::Find(normalize_pairs(&pairs))
            }
        }
        Identity::Ordered => fallback_selector(props, index),
    }
}

fn fallback_selector(props: &[Prop], index: usize) -> Selector {
    if let Some(v) = prop(props, "name") {
        return Selector::Named(v.to_string());
    }
    if let Some(v) = prop(props, "default-name") {
        return Selector::Named(v.to_string());
    }
    if let Some(v) = prop(props, "address") {
        return Selector::Find(vec![("address".to_string(), v.to_string())]);
    }
    Selector::Index(index)
}

/// Read the selector a `set`/`remove`/`move` line used.
pub fn selector_from_tok(tok: &Tok) -> Selector {
    let raw = tok.raw.trim();

    if let Some(inner) = raw.strip_prefix('[').and_then(|r| r.strip_suffix(']')) {
        if let Ok(toks) = crate::syntax::lexer::tokenize(inner) {
            if toks.first().map(|t| t.raw.as_str()) == Some("find") {
                let mut pairs = Vec::new();
                let mut ok = true;
                for t in &toks[1..] {
                    match (t.kind, &t.key, &t.value) {
                        (TokKind::Pair, Some(k), Some(v)) => {
                            pairs.push((k.clone(), v.text.clone()))
                        }
                        _ => {
                            ok = false;
                            break;
                        }
                    }
                }
                if ok && !pairs.is_empty() {
                    return Selector::Find(normalize_pairs(&pairs));
                }
            }
        }
        return Selector::Expr(raw.to_string());
    }

    if let Ok(i) = raw.parse::<usize>() {
        return Selector::Index(i);
    }

    Selector::Named(raw.to_string())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::model::Prop;
    use crate::syntax::lexer::Value;

    fn p(key: &str, value: &str) -> Prop {
        Prop {
            key: key.to_string(),
            value: Value {
                raw: value.to_string(),
                text: value.to_string(),
                quoted: false,
            },
            raw: format!("{}={}", key, value),
        }
    }

    #[test]
    fn a_pool_is_named_by_name() {
        let sel = selector_from_props(
            "ip pool",
            &[p("ranges", "10.0.0.1-10.0.0.9"), p("name", "lan")],
            0,
        );
        assert_eq!(sel, Selector::Named("lan".into()));
    }

    #[test]
    fn an_address_needs_its_interface() {
        let sel = selector_from_props(
            "ip address",
            &[p("address", "10.0.0.1/24"), p("interface", "ether1")],
            0,
        );
        assert_eq!(
            sel,
            Selector::Find(vec![
                ("address".into(), "10.0.0.1/24".into()),
                ("interface".into(), "ether1".into())
            ])
        );
    }

    #[test]
    fn a_firewall_rule_falls_back_to_position() {
        let sel = selector_from_props(
            "ip firewall filter",
            &[p("chain", "input"), p("action", "drop")],
            3,
        );
        assert_eq!(sel, Selector::Index(3));
    }

    #[test]
    fn default_name_and_name_are_the_same_key() {
        let a = Selector::Find(normalize_pairs(&[("default-name".into(), "ether1".into())]));
        let b = Selector::Find(normalize_pairs(&[("name".into(), "ether1".into())]));
        assert_eq!(a.key(), b.key());
    }

    #[test]
    fn a_find_selector_is_read_from_the_source() {
        let toks = crate::syntax::lexer::tokenize("[ find default-name=ether1 ]").unwrap();
        assert_eq!(
            selector_from_tok(&toks[0]),
            Selector::Find(vec![("name".into(), "ether1".into())])
        );
    }

    #[test]
    fn a_bare_name_selector_is_a_name() {
        let toks = crate::syntax::lexer::tokenize("api").unwrap();
        assert_eq!(selector_from_tok(&toks[0]), Selector::Named("api".into()));
    }

    #[test]
    fn a_complex_selector_is_kept_as_an_expression() {
        let toks = crate::syntax::lexer::tokenize("[find where comment~\"x\"]").unwrap();
        assert!(matches!(selector_from_tok(&toks[0]), Selector::Expr(_)));
    }
}
