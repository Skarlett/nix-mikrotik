//! The property the tool exists to have: a patch derived from two files, when
//! applied to the first, produces the second.

use rsc::diff::{diff, Op, Options};
use rsc::patch::{render, RenderOptions};
use rsc::{parse_config, simulate};
use std::path::{Path, PathBuf};

fn manifest(rel: &str) -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR")).join(rel)
}

fn fixture(name: &str) -> String {
    std::fs::read_to_string(manifest(&format!("tests/fixtures/{}", name))).unwrap()
}

fn patch_between(a: &str, b: &str) -> (String, rsc::Diff) {
    let opts = Options::default();
    let ca = parse_config(a).unwrap();
    let cb = parse_config(b).unwrap();
    let d = diff(&ca, &cb, &opts);
    let text = render(&d, &RenderOptions::new("a.rsc", "b.rsc"));
    (text, d)
}

fn assert_upsert(a: &str, b: &str) {
    let opts = Options::default();
    let ca = parse_config(a).unwrap();
    let cb = parse_config(b).unwrap();
    let d = diff(&ca, &cb, &opts);
    let applied = simulate::apply(&ca, &d);
    let problems = simulate::compare(&cb, &applied, &d, &opts);
    assert!(problems.is_empty(), "{}", problems.join("\n"));
}

#[test]
fn a_to_b_reaches_b() {
    assert_upsert(&fixture("a.rsc"), &fixture("b.rsc"));
}

#[test]
fn b_to_a_reaches_a() {
    assert_upsert(&fixture("b.rsc"), &fixture("a.rsc"));
}

#[test]
fn the_patch_is_itself_a_parseable_script() {
    let (text, _) = patch_between(&fixture("a.rsc"), &fixture("b.rsc"));
    let doc = rsc::parse(&text).expect("the patch must parse");
    // Every non-comment line has to be a command; a stray word would be a
    // script line the device would try to run.
    for item in &doc.items {
        match item {
            rsc::syntax::ast::Item::Command(_)
            | rsc::syntax::ast::Item::Comment { .. }
            | rsc::syntax::ast::Item::Section { .. }
            | rsc::syntax::ast::Item::Blank { .. } => {}
            other => panic!("patch contains a non-command: {:?}", other.raw()),
        }
    }
}

#[test]
fn the_patch_addresses_every_object_it_touches() {
    let (text, d) = patch_between(&fixture("a.rsc"), &fixture("b.rsc"));
    assert!(d.is_exact(), "diff was not exact:\n{}", text);
    assert!(!text.contains("cannot reset"), "{}", text);
    assert!(!text.contains("by position"), "{}", text);
}

#[test]
fn the_changes_are_the_ones_a_reader_would_make() {
    let (text, d) = patch_between(&fixture("a.rsc"), &fixture("b.rsc"));

    // The identity is a singleton: one `set`, no object copied.
    assert!(text.contains("/system identity"), "{}", text);
    assert!(text.contains("set name=\"chr-b\""), "{}", text);

    // A new VLAN interface and its address.
    assert!(text.contains("/interface vlan"), "{}", text);
    assert!(
        text.contains("add interface=bridge name=vlan20 vlan-id=20"),
        "{}",
        text
    );
    assert!(
        text.contains("add address=10.10.20.1/24 interface=vlan20 network=10.10.20.0"),
        "{}",
        text
    );

    // The address that went away is removed by identity, not by index.
    assert!(
        text.contains("remove [find address=10.10.11.1/24 interface=ether3]"),
        "{}",
        text
    );

    // The pool's comment disappears: `comment=""` is the one reset RouterOS
    // accepts, so the object is not re-created for it.
    let pool = d.sections.iter().find(|s| s.path == "ip pool").unwrap();
    assert_eq!(pool.stats.replaced, 0, "{:?}", pool.ops);
    assert!(pool.ops.iter().any(|o| matches!(o, Op::Set { .. })));
    assert!(text.contains("set [find name=lan-pool]"), "{}", text);
    assert!(text.contains("comment=\"\""), "{}", text);

    // The reordered input chain is reached with a move, not by rebuilding it.
    let filter = d
        .sections
        .iter()
        .find(|s| s.path == "ip firewall filter")
        .unwrap();
    assert_eq!(filter.strategy, rsc::Strategy::CommentKeyed);
    assert!(filter.stats.moved >= 1, "{:?}", filter.ops);
    assert!(
        text.contains("move [find comment=\"defconf: accept icmp\"] destination=0"),
        "{}",
        text
    );

    // The new rule is inserted before the drop rule, not appended past it.
    assert!(
        text.contains("place-before=[find comment=\"defconf: drop all not coming from LAN\"]"),
        "{}",
        text
    );

    // A section that exists only in the target is created object by object.
    assert!(text.contains("/ip service"), "{}", text);
    assert!(
        text.contains("set [find name=telnet] disabled=yes"),
        "{}",
        text
    );
}

#[test]
fn a_section_that_disappears_is_removed_by_identity() {
    let (text, d) = patch_between(&fixture("a.rsc"), &fixture("b.rsc"));
    let dns = d
        .sections
        .iter()
        .find(|s| s.path == "ip dns static")
        .unwrap();
    assert_eq!(dns.stats.removed, 1);
    assert!(text.contains("remove [find name=router.lan]"), "{}", text);
}

#[test]
fn an_unchanged_configuration_produces_no_commands() {
    let src = fixture("a.rsc");
    let (text, d) = patch_between(&src, &src);
    assert!(d.is_empty());
    let commands = text
        .lines()
        .filter(|l| !l.trim().is_empty() && !l.trim_start().starts_with('#'))
        .count();
    assert_eq!(commands, 0, "{}", text);
}

#[test]
fn a_full_configuration_can_be_built_from_nothing() {
    assert_upsert("", &fixture("a.rsc"));
}

/// The other direction cannot be exact, and the tool says so rather than
/// pretending: a singleton menu has one settings object that always exists and
/// whose properties cannot be unset, so "delete `/ip dns`" has no spelling.
#[test]
fn emptying_a_configuration_reports_what_it_cannot_do() {
    let opts = Options::default();
    let ca = parse_config(&fixture("a.rsc")).unwrap();
    let empty = parse_config("").unwrap();
    let d = diff(&ca, &empty, &opts);
    assert!(!d.is_exact());
    let unresolvable: usize = d.stats().unresolvable;
    assert!(unresolvable >= 3, "{:?}", d.stats());
    let text = render(&d, &RenderOptions::new("a.rsc", "empty.rsc"));
    assert!(text.contains("cannot reset"), "{}", text);
}

/// A patch is only useful if the device ends up holding exactly what the
/// second file says. The model-level check above says the tool agrees with
/// itself; this one pins the spelling of the operations a device will actually
/// be given, so a change in wording is a test failure rather than a surprise on
/// a router.
#[test]
fn the_patch_spells_operations_the_way_a_console_does() {
    let (text, _) = patch_between(&fixture("a.rsc"), &fixture("b.rsc"));
    for line in text.lines() {
        let t = line.trim_start();
        if t.is_empty() || t.starts_with('#') || t.starts_with('/') || t.starts_with(':') {
            continue;
        }
        let verb = t.split(' ').next().unwrap();
        assert!(
            ["add", "set", "remove", "move", "enable", "disable"].contains(&verb),
            "unexpected verb in patch: {}",
            line
        );
    }
}
