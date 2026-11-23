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

/// An address can sit in several lists, so removing one entry has to name the
/// list as well as the address — keying on the address alone would take it out
/// of every list that holds it. Found on a real 7.24.6 export, where the
/// `ipv6` twin of a menu this table knew had fallen through to `address` alone.
#[test]
fn an_address_in_two_lists_is_two_objects() {
    let opts = Options::default();
    let a = "/ipv6 firewall address-list\nadd address=fd23:b8ed:aa54:100::/64 list=bgp-exports\nadd address=fd23:b8ed:aa54:100::/64 list=other\n";
    let b = "/ipv6 firewall address-list\nadd address=fd23:b8ed:aa54:100::/64 list=bgp-exports\n";
    let d = diff(&parse_config(a).unwrap(), &parse_config(b).unwrap(), &opts);
    let s = &d.sections[0];
    assert_eq!(
        (s.stats.removed, s.stats.added, s.stats.replaced),
        (1, 0, 0),
        "{:?}",
        s.ops
    );

    let text = render(&d, &RenderOptions::new("a.rsc", "b.rsc"));
    assert!(
        text.contains("remove [find address=fd23:b8ed:aa54:100::/64 list=other]"),
        "{}",
        text
    );
    assert!(
        !text.contains("list=bgp-exports]\n"),
        "removed the wrong entry:\n{}",
        text
    );
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

// ---------------------------------------------------------------------------
// upsert mode: adds and sets only, for a deploy that does not own the device
// ---------------------------------------------------------------------------

fn upsert() -> Options {
    Options {
        removals: rsc::Removals::Withhold,
        ..Options::default()
    }
}

fn upsert_between(a: &str, b: &str) -> (String, rsc::Diff, Vec<String>) {
    let opts = upsert();
    let ca = parse_config(a).unwrap();
    let cb = parse_config(b).unwrap();
    let d = diff(&ca, &cb, &opts);
    let text = render(&d, &RenderOptions::new("a.rsc", "b.rsc"));
    let applied = simulate::apply(&ca, &d);
    let problems = simulate::compare(&cb, &applied, &d, &opts);
    (text, d, problems)
}

/// The whole point: a device's `/export` carries objects the target script never
/// mentions (the management address, the ethernet interfaces, a rule somebody
/// added by hand). An upsert must reach the target's objects and leave those
/// alone, and say what it left alone.
#[test]
fn an_upsert_adds_and_sets_and_deletes_nothing() {
    let a = "/ip pool\nadd name=lan ranges=10.0.0.10-10.0.0.20\nadd name=stale ranges=10.9.0.10-10.9.0.20\n\
             /ip dns\nset servers=1.1.1.1\n";
    let b = "/ip pool\nadd name=lan ranges=10.0.0.10-10.0.0.30\nadd name=wan ranges=10.1.0.10-10.1.0.20\n\
             /ip dns\nset servers=9.9.9.9\n";
    let (text, d, problems) = upsert_between(a, b);

    assert!(problems.is_empty(), "{}", problems.join("\n"));
    assert_eq!(d.stats().removed, 0, "{:?}", d.stats());
    let commands: Vec<&str> = text
        .lines()
        .map(|l| l.trim_start())
        .filter(|l| !l.is_empty() && !l.starts_with('#') && !l.starts_with('/'))
        .collect();
    assert!(
        commands.iter().all(|l| !l.starts_with("remove ")),
        "a removal reached the patch:\n{}",
        text
    );
    assert!(text.contains("set [find name=lan] ranges=10.0.0.10-10.0.0.30"), "{}", text);
    assert!(text.contains("add name=wan ranges=10.1.0.10-10.1.0.20"), "{}", text);
    assert!(text.contains("set servers=9.9.9.9"), "{}", text);
    // And the deletion is reported rather than silently dropped.
    assert!(text.contains("# withheld: remove name=stale"), "{}", text);
    assert!(text.contains("1 removal(s) withheld"), "{}", text);
}

/// A menu with no stable handle is rebuilt as one operation. Keeping half of it
/// -- the adds, dropping the removes -- would append a second copy of the
/// target's rules on every deploy, so an upsert leaves the whole menu alone.
#[test]
fn an_upsert_leaves_a_rebuild_it_cannot_finish_alone() {
    let a = "/ip firewall filter\nadd chain=input action=accept protocol=icmp\n\
             add chain=input action=drop\n";
    let b = "/ip firewall filter\nadd chain=input action=accept protocol=icmp\n";
    let (text, d, problems) = upsert_between(a, b);
    let filter = d.sections.iter().find(|s| s.path == "ip firewall filter").unwrap();

    assert_eq!(filter.strategy, rsc::Strategy::Positional);
    assert!(filter.ops.is_empty(), "half a rebuild reached the patch: {:?}", filter.ops);
    // Two removes and the one add that only makes sense after them.
    assert_eq!(filter.withheld.len(), 3, "{:?}", filter.withheld);
    assert!(problems.is_empty(), "{}", problems.join("\n"));
    assert!(!text.contains("\nadd chain"), "an add from a rebuild reached the patch:\n{}", text);
    assert!(text.contains("# note: UNAPPLIED"), "{}", text);
}

/// A replacement is a remove plus an add: keeping the add alone would duplicate
/// the object it meant to replace, so both halves are withheld.
#[test]
fn an_upsert_does_not_half_apply_a_replacement() {
    // `comment` is the one property that resets in place (comment=""), so the
    // property that has to disappear here is one RouterOS cannot unset.
    let a = "/ip dhcp-server\nadd name=lan-dhcp address-pool=lan interface=lan\n";
    let b = "/ip dhcp-server\nadd name=lan-dhcp interface=lan\n";
    let (text, d, problems) = upsert_between(a, b);
    let pool = d
        .sections
        .iter()
        .find(|s| s.path == "ip dhcp-server")
        .unwrap();
    assert!(pool.ops.is_empty(), "{:?}", pool.ops);
    assert_eq!(pool.stats.withheld, 2, "{:?}", pool.withheld);
    assert!(problems.is_empty(), "{}", problems.join("\n"));
    assert!(!text.contains("add name=lan-dhcp"), "{}", text);
}

/// The other direction of the same property: what the target declares is what
/// the device ends up holding, checked over the corpus the differ is dogfooded
/// on. Every ordered pair, because a fleet export and a rendered script differ
/// in both directions.
#[test]
fn an_upsert_reaches_the_targets_objects_for_every_fixture_pair() {
    let files = [
        ("a", fixture("a.rsc")),
        ("b", fixture("b.rsc")),
        ("export", fixture("export-7.15.3.rsc")),
        ("chr", fixture("rendered/chr-fixture.rsc")),
        ("example", fixture("rendered/example.rsc")),
    ];
    for (an, a) in &files {
        for (bn, b) in &files {
            if an == bn {
                continue;
            }
            let (text, d, problems) = upsert_between(a, b);
            // A menu the patch may not rebuild keeps whatever the device holds,
            // so a target object that lives there is legitimately absent. The
            // diff reports that as withheld, and a miss is tolerated only in a
            // section that says so -- the rule the dogfood matrix uses.
            let skipped: Vec<String> = d
                .sections
                .iter()
                .filter(|s| s.withheld.iter().any(|op| matches!(op, Op::Add { .. })))
                .map(|s| format!("/{}:", s.path))
                .collect();
            let unexpected: Vec<&String> = problems
                .iter()
                .filter(|p| !skipped.iter().any(|s| p.starts_with(s)))
                .collect();
            assert!(
                unexpected.is_empty(),
                "upsert {} -> {} did not reach the target:\n{}\n--- patch ---\n{}",
                an,
                bn,
                unexpected
                    .iter()
                    .map(|s| s.as_str())
                    .collect::<Vec<_>>()
                    .join("\n"),
                text
            );
            assert_eq!(
                d.stats().removed,
                0,
                "upsert {} -> {} emitted a removal:\n{}",
                an,
                bn,
                text
            );
        }
    }
}
