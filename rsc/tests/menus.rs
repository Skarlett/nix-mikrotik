//! Dogfood the generated menu table.
//!
//! `lib/menus.generated.nix` is this repository's model of RouterOS' whole menu
//! surface — 346 menus walked out of `/console/inspect`, with the argument list
//! the device reports for each. It is the file a consumer's typed options are
//! checked against, so it is also the right thing to test the parser and the
//! identity table against: every menu name and every argument name in it is a
//! string the tool has to handle, and none of them were chosen by this crate.
//!
//! The extractor below reads that file's generated shape directly rather than
//! going through nix, so the test needs nothing but `cargo test`. It is strict
//! on purpose: a line inside `attrs` or `lists` that is not a quoted entry is a
//! failure, not a skip, so a regeneration that changes the shape breaks this
//! test instead of quietly testing nothing.
//!
//! Three questions:
//!
//! * does every menu path parse as *that menu* — not as a command, and not with
//!   a word eaten by the verb heuristic that splits `/ip address add …`?
//! * does every argument name survive the lexer, the model and the printer?
//! * does the identity table know every menu that has a name to key on? A menu
//!   it does not know is treated as ordered, which means every diff of that menu
//!   rebuilds it — the failure this table exists to catch when it grows.

use rsc::diff::{diff, Options, Strategy};
use rsc::identity::{identity_for, Identity};
use rsc::parse_config;
use rsc::syntax::ast::Item;
use rsc::syntax::lexer::tokenize;
use rsc::syntax::print;
use std::path::{Path, PathBuf};

fn manifest(rel: &str) -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR")).join(rel)
}

#[derive(Debug, Clone)]
struct Menu {
    /// As written in the table, with the leading slash: `/ip firewall filter`.
    path: String,
    /// `list` (the menu has `add`) or `object` (it has `set`).
    kind: String,
    /// The argument names the device reports.
    attrs: Vec<String>,
    /// The arguments the device stores as several values.
    lists: Vec<String>,
}

impl Menu {
    /// The menu path as a `.rsc` header, without the slash.
    fn header(&self) -> String {
        self.path.trim_start_matches('/').to_string()
    }
}

fn table() -> Vec<Menu> {
    let path = manifest("../lib/menus.generated.nix");
    let src = std::fs::read_to_string(&path).unwrap_or_else(|e| {
        panic!(
            "{}: {} — the generated menu table has to be readable from the crate",
            path.display(),
            e
        )
    });

    let mut out: Vec<Menu> = Vec::new();
    let mut cur: Option<Menu> = None;
    // Which list we are inside, if any.
    let mut collecting: Option<bool> = None; // Some(true) = attrs, Some(false) = lists

    for (n, line) in src.lines().enumerate() {
        let t = line.trim();
        let at = n + 1;

        if t == "{" {
            assert!(cur.is_none(), "line {}: nested menu block", at);
            cur = Some(Menu {
                path: String::new(),
                kind: String::new(),
                attrs: Vec::new(),
                lists: Vec::new(),
            });
            collecting = None;
            continue;
        }
        if t == "}" {
            let menu = cur
                .take()
                .unwrap_or_else(|| panic!("line {}: stray }}", at));
            assert!(!menu.path.is_empty(), "line {}: menu with no path", at);
            assert!(
                !menu.kind.is_empty(),
                "line {}: {} has no kind",
                at,
                menu.path
            );
            out.push(menu);
            collecting = None;
            continue;
        }
        if t.is_empty() || t.starts_with('#') {
            continue;
        }
        // The whole table is one list.
        if t == "[" || t == "]" {
            assert!(
                cur.is_none(),
                "line {}: list bracket inside a menu block",
                at
            );
            continue;
        }

        if let Some(rest) = t.strip_prefix("path = ") {
            let menu = cur
                .as_mut()
                .unwrap_or_else(|| panic!("line {}: path outside a menu", at));
            menu.path = quoted(rest).unwrap_or_else(|| panic!("line {}: bad path {:?}", at, rest));
            continue;
        }
        if let Some(rest) = t.strip_prefix("kind = ") {
            let menu = cur
                .as_mut()
                .unwrap_or_else(|| panic!("line {}: kind outside a menu", at));
            menu.kind = quoted(rest).unwrap_or_else(|| panic!("line {}: bad kind {:?}", at, rest));
            continue;
        }
        if t == "attrs = [" {
            collecting = Some(true);
            continue;
        }
        if t == "lists = [" {
            collecting = Some(false);
            continue;
        }
        if t == "];" {
            collecting = None;
            continue;
        }

        match collecting {
            Some(is_attrs) => {
                let value = quoted(t).unwrap_or_else(|| {
                    panic!(
                        "line {}: {:?} is not a quoted entry — the generated shape changed",
                        at, t
                    )
                });
                let menu = cur.as_mut().expect("entry outside a menu");
                if is_attrs {
                    menu.attrs.push(value);
                } else {
                    menu.lists.push(value);
                }
            }
            None => panic!("line {}: unexpected line {:?}", at, t),
        }
    }

    assert!(cur.is_none(), "the file ends inside a menu block");
    out
}

/// The string literal a generated line carries, `"foo";` or `"foo"`.
fn quoted(s: &str) -> Option<String> {
    let start = s.find('"')? + 1;
    let end = start + s[start..].find('"')?;
    Some(s[start..end].to_string())
}

/// A value that parses and is the same for every argument: the point is the
/// argument *name*, not what it holds.
const DUMMY: &str = "x";

fn script_for(menu: &Menu) -> String {
    let verb = if menu.kind == "list" { "add" } else { "set" };
    let args: Vec<String> = menu
        .attrs
        .iter()
        .map(|a| format!("{}={}", a, DUMMY))
        .collect();
    format!("/{}\n{} {}\n", menu.header(), verb, args.join(" "))
}

#[test]
fn the_table_is_the_one_this_repository_ships() {
    let menus = table();
    assert!(
        menus.len() >= 300,
        "extracted {} menus — the generated table has more than that",
        menus.len()
    );
    for kind in ["list", "object"] {
        assert!(
            menus.iter().any(|m| m.kind == kind),
            "no {} menu was extracted",
            kind
        );
    }
    for known in [
        "/ip address",
        "/ipv6 address",
        "/ip firewall filter",
        "/ip pool",
        "/interface bridge port",
        "/interface ethernet",
        "/interface wireguard peers",
        "/queue simple",
        "/routing table",
        "/system note",
    ] {
        assert!(
            menus.iter().any(|m| m.path == known),
            "{} is not in the extracted table — the extractor is reading the wrong file",
            known
        );
    }
    let with_attrs = menus.iter().filter(|m| !m.attrs.is_empty()).count();
    assert!(
        with_attrs * 10 >= menus.len() * 9,
        "only {} of {} menus have arguments",
        with_attrs,
        menus.len()
    );
}

/// `/ip address add …` is a path and a command on one line, so the parser has to
/// decide where the path ends. A menu whose last word happens to be a verb would
/// be split in the wrong place — this is the test that says none is.
#[test]
fn every_menu_header_parses_as_that_menu() {
    for menu in table() {
        let src = format!("/{}\n", menu.header());
        let doc = rsc::parse(&src).unwrap_or_else(|e| panic!("{}: {}", menu.path, e));
        match &doc.items[0] {
            Item::Section { path, .. } => assert_eq!(
                path.join(" "),
                menu.header(),
                "{} did not parse as a section with that path",
                menu.path
            ),
            other => panic!("{} parsed as {:?}", menu.path, other.raw()),
        }
    }
}

/// Every argument name the device reports has to survive the lexer, land in the
/// model under its own name, and be printed back unchanged.
#[test]
fn every_argument_of_every_menu_parses_and_re_renders() {
    for menu in table() {
        let src = script_for(&menu);
        let doc = rsc::parse(&src).unwrap_or_else(|e| panic!("{}: {}\n{}", menu.path, e, src));

        let cmd = doc
            .items
            .iter()
            .find_map(|i| match i {
                Item::Command(c) => Some(c),
                _ => None,
            })
            .unwrap_or_else(|| panic!("{}: no command parsed\n{}", menu.path, src));

        let got: Vec<String> = cmd.args.iter().filter_map(|a| a.key.clone()).collect();
        assert_eq!(got, menu.attrs, "{}: argument names changed", menu.path);

        // The printer has to reproduce the line it was given, argument for
        // argument — this is what a patch prints when it writes an object.
        assert_eq!(
            print::command(cmd),
            src.lines().nth(1).unwrap(),
            "{}: the printer did not reproduce the command",
            menu.path
        );

        // And the model has to hold them as properties of one object.
        let cfg = rsc::model::build(&doc);
        let section = cfg
            .section(&menu.header())
            .unwrap_or_else(|| panic!("{}: no section in the model", menu.path));
        assert_eq!(
            section.objects.len(),
            1,
            "{}: {}",
            menu.path,
            section.objects.len()
        );
        let props: Vec<&str> = section.objects[0]
            .props
            .iter()
            .map(|p| p.key.as_str())
            .collect();
        let want: Vec<&str> = menu.attrs.iter().map(|a| a.as_str()).collect();
        assert_eq!(props, want, "{}: properties lost or reordered", menu.path);
    }
}

/// Every menu the identity table keys on *several* properties has to behave like
/// a keyed menu, not a list: a one-property change is one `set` whose selector
/// names every key part the object carries, and a removal takes out exactly one
/// object.
///
/// This is the failure the composite half of the table exists for. A selector
/// that lost a part removes every object sharing the rest -- `/ipv6 firewall
/// address-list` keyed on `address` alone takes an entry out of every list that
/// holds it -- and the patch then says one `remove` while the device loses
/// several. It is also where the fleet's CRS exports live: the switch menus key
/// on `vlan-id`, or on `ports`+`customer-vid`, and have no name at all.
#[test]
fn every_composite_menu_keys_on_all_of_its_parts() {
    use rsc::diff::{diff, Op, Options, Strategy};
    use rsc::model::Selector;
    use rsc::simulate;

    let mut checked: Vec<String> = Vec::new();
    for menu in table() {
        let Identity::Composite(keys) = identity_for(menu.header().as_str()) else {
            continue;
        };
        if menu.kind != "list" {
            continue;
        }
        // Only keys the device reports as arguments can be generated, and a menu
        // with no other property cannot express a "change something else".
        if keys.iter().any(|k| !menu.attrs.iter().any(|a| a == k)) {
            continue;
        }
        let Some(other) = menu.attrs.iter().find(|a| !keys.contains(&a.as_str())) else {
            continue;
        };

        // Three objects: A and B share every key part but the last, C shares the
        // last with A. A selector missing a part would match two of them. (A menu
        // keyed on one property is included: A and B differ in it, C differs
        // again -- the single-key composite is still a composite.)
        let last_index = keys.len() - 1;
        let obj = |which: &str, other_v: &str| -> String {
            let mut parts: Vec<String> = Vec::new();
            for (i, k) in keys.iter().enumerate() {
                let v = match which {
                    "A" if i == last_index => "1",
                    "B" if i == last_index => "2",
                    "C" if i == 0 => "c",
                    "C" if i == last_index => "1",
                    _ => "shared",
                };
                parts.push(format!("{}={}", k, v));
            }
            parts.push(format!("{}={}", other, other_v));
            parts.join(" ")
        };
        let header = menu.header();
        let a = format!(
            "/{}\nadd {}\nadd {}\nadd {}\n",
            header,
            obj("A", "one"),
            obj("B", "two"),
            obj("C", "three"),
        );

        // 1. a one-property change on B is one `set`, not a rebuild
        let changed = format!(
            "/{}\nadd {}\nadd {}\nadd {}\n",
            header,
            obj("A", "one"),
            obj("B", "changed"),
            obj("C", "three"),
        );
        let opts = Options::default();
        let ca = parse_config(&a).unwrap();
        let cb = parse_config(&changed).unwrap();
        let d = diff(&ca, &cb, &opts);
        let section = &d.sections[0];
        assert_eq!(
            section.strategy,
            Strategy::Keyed,
            "{}: a composite key fell back to {:?}",
            menu.path,
            section.strategy
        );
        assert_eq!(
            section.ops.len(),
            1,
            "{}: one property change produced {:?}",
            menu.path,
            section.ops
        );
        match &section.ops[0] {
            Op::Set { selector, .. } => {
                let Selector::Find(pairs) = selector else {
                    panic!("{}: selector is {:?}, not a find", menu.path, selector)
                };
                let named: Vec<&str> = pairs.iter().map(|(k, _)| k.as_str()).collect();
                for k in keys {
                    assert!(
                        named.contains(k),
                        "{}: the selector {named:?} does not name the key part {k}",
                        menu.path
                    );
                }
            }
            other => panic!("{}: a change became {:?}", menu.path, other.describe()),
        }
        // ... and it applies to exactly one object
        let applied = simulate::apply(&ca, &d);
        assert_eq!(
            applied.section(&header).unwrap().objects.len(),
            3,
            "{}: the patch changed the object count",
            menu.path
        );

        // 2. a removal takes out exactly one object, and the right one
        let removed = format!(
            "/{}\nadd {}\nadd {}\n",
            header,
            obj("A", "one"),
            obj("B", "two"),
        );
        let cr = parse_config(&removed).unwrap();
        let dr = diff(&ca, &cr, &opts);
        let section = &dr.sections[0];
        assert_eq!(
            section.ops.len(),
            1,
            "{}: one removal produced {:?}",
            menu.path,
            section.ops
        );
        match &section.ops[0] {
            Op::Remove { selector, exact, .. } => {
                assert!(*exact, "{}: the removal is positional", menu.path);
                let Selector::Find(pairs) = selector else {
                    panic!("{}: selector is {:?}, not a find", menu.path, selector)
                };
                let named: Vec<&str> = pairs.iter().map(|(k, _)| k.as_str()).collect();
                for k in keys {
                    assert!(
                        named.contains(k),
                        "{}: the removal names {named:?} but not the key part {k} -- \
                         it would delete every object sharing the rest",
                        menu.path
                    );
                }
            }
            other => panic!("{}: a removal became {:?}", menu.path, other.describe()),
        }
        let applied = simulate::apply(&ca, &dr);
        let left = &applied.section(&header).unwrap().objects;
        assert_eq!(left.len(), 2, "{}: the patch removed the wrong number", menu.path);
        let texts: Vec<String> = left.iter().map(|o| o.selector.key()).collect();
        assert!(
            !texts.iter().any(|t| t.contains(&format!("{}={}", keys[0], "c"))),
            "{}: C survived a removal aimed at it: {texts:?}",
            menu.path
        );
        // 3. An object that *lacks* one of its key parts must not be removed by a
        //    selector that also matches its neighbour. `/ip route` is the live
        //    case: `routing-mark` is optional, so a marked and an unmarked route
        //    can share dst-address and gateway. A `remove [find …]` built from
        //    the parts that are present then deletes both while the patch says
        //    one.
        if keys.len() > 1 {
            let sparse = format!(
                "/{}\nadd {}\nadd {}\n",
                header,
                obj("A", "one"),
                {
                    let mut parts: Vec<String> = Vec::new();
                    for (i, k) in keys.iter().enumerate() {
                        if i == last_index {
                            continue;                 // the optional part is absent
                        }
                        let v = if i == 0 { "shared" } else { "shared" };
                        parts.push(format!("{}={}", k, v));
                    }
                    parts.push(format!("{}=two", other));
                    parts.join(" ")
                }
            );
            let keep = format!("/{}\nadd {}\n", header, obj("A", "one"));
            let cs = parse_config(&sparse).unwrap();
            let ck = parse_config(&keep).unwrap();
            let ds = diff(&cs, &ck, &opts);
            let applied = simulate::apply(&cs, &ds);
            let survivors = &applied.section(&header).unwrap().objects;
            // The object the target kept is the one *with* the last key part. If
            // the removal matched the neighbour instead, the survivor is the
            // sparse one -- and on a device `remove [find k1=shared]` deletes
            // both, so the model and the device would disagree in the worst way.
            // Two answers are correct, and one is not. Removing exactly the
            // object the target dropped is correct; so is refusing, because the
            // selector cannot name it without naming its neighbour. Deleting the
            // neighbour *and* saying one is the failure.
            let refused = ds.sections[0]
                .notes
                .iter()
                .any(|n| n.starts_with("UNAPPLIED:"));
            let kept_the_right_one = survivors.len() == 1
                && rsc::model::prop_text(&survivors[0].props, keys[last_index]) == Some("1");
            assert!(
                refused || kept_the_right_one,
                "{}: a removal aimed at the object with no {} took the wrong object(s) \
                 without saying so: {:?} (ops: {:?})",
                menu.path,
                keys[last_index],
                survivors.iter().map(|o| o.selector.key()).collect::<Vec<_>>(),
                ds.sections[0].ops.iter().map(|o| o.describe()).collect::<Vec<_>>()
            );
        }

        checked.push(menu.path.clone());
    }
    // A count is not enough: the menus that matter most are the ones the fleet
    // actually exports. Every composite menu whose key parts are arguments is
    // exercised; the switch menus are skipped only where the table does not
    // report their key as an argument, and that is a gap worth knowing about
    // rather than a pass.
    for known in [
        "/ip address",
        "/ipv6 address",
        "/ip firewall address-list",
        "/ipv6 firewall address-list",
        "/interface list member",
        "/interface bridge port",
    ] {
        assert!(
            checked.iter().any(|p| p == known),
            "{} was not exercised (checked: {:?})",
            known,
            checked
        );
    }
    assert!(
        checked.len() >= 8,
        "only {} composite menus were exercised: {:?}",
        checked.len(),
        checked
    );
}

/// The multi-value arguments the table records have to be usable as written: a
/// comma-joined value is one token, and the model keeps it as one property.
#[test]
fn every_multi_value_argument_is_one_token() {
    let mut checked = 0;
    for menu in table() {
        for arg in &menu.lists {
            let src = format!(
                "/{}\nadd {}={},{} name=probe\n",
                menu.header(),
                arg,
                DUMMY,
                DUMMY
            );
            let doc = rsc::parse(&src).unwrap_or_else(|e| panic!("{}: {}", menu.path, e));
            let cmd = doc
                .items
                .iter()
                .find_map(|i| match i {
                    Item::Command(c) => Some(c),
                    _ => None,
                })
                .unwrap_or_else(|| panic!("{}: no command", menu.path));
            let value = cmd
                .arg(arg)
                .unwrap_or_else(|| panic!("{}: {} was not parsed as an argument", menu.path, arg));
            assert_eq!(
                value.text,
                format!("{},{}", DUMMY, DUMMY),
                "{}: {} did not survive as one value",
                menu.path,
                arg
            );
            // One token, not three.
            let toks = tokenize(&format!("add {}={},{}", arg, DUMMY, DUMMY)).unwrap();
            assert_eq!(
                toks.len(),
                2,
                "{}: {} split into several tokens",
                menu.path,
                arg
            );
            checked += 1;
        }
    }
    assert!(
        checked >= 50,
        "only {} multi-value arguments checked",
        checked
    );
}

/// The coverage question the hand-written table has to answer, asked the way a
/// user would notice it going wrong: changing one value of one object in a menu
/// that has a `name` must emit a `set`, not rebuild the menu.
///
/// The table's default for a menu it does not know is "ordered", and the
/// generated table has menus it does not know — `/interface vxlan`, `/file`,
/// `/interface wifi`, 92 of them at the time of writing. Left positional, every
/// change to one of them would remove and re-add every object in it.
#[test]
fn every_menu_with_a_name_diffs_as_a_set_not_a_rebuild() {
    let opts = Options::default();
    let mut checked = 0;

    for menu in table() {
        if !menu.attrs.iter().any(|a| a == "name") {
            continue;
        }
        let a = format!("/{}\nadd name=probe comment=one\n", menu.header());
        let b = format!("/{}\nadd name=probe comment=two\n", menu.header());
        let d = diff(
            &parse_config(&a).unwrap(),
            &parse_config(&b).unwrap(),
            &opts,
        );
        let s = &d.sections[0];
        assert_eq!(
            s.strategy,
            Strategy::Keyed,
            "{} is compared as {}, so one changed value rebuilds the menu: {:?}",
            menu.path,
            s.strategy.as_str(),
            s.ops
        );
        assert_eq!(
            (
                s.stats.changed,
                s.stats.added,
                s.stats.removed,
                s.stats.replaced
            ),
            (1, 0, 0, 0),
            "{}: expected exactly one `set`: {:?}",
            menu.path,
            s.ops
        );
        checked += 1;
    }

    assert!(checked >= 100, "only {} name-keyed menus checked", checked);
}

/// The `ipv6` twin of a menu has to key the way its `ip` twin does. The table is
/// written per menu, so `/ip firewall address-list` was composite while
/// `/ipv6 firewall address-list` fell through to `address` alone — and an
/// address can be in two lists, so a removal keyed on the address would take the
/// entry out of both.
#[test]
fn every_ipv6_menu_keys_the_way_its_ip_twin_does() {
    let mut checked = 0;
    for menu in table() {
        let Some(rest) = menu.path.strip_prefix("/ipv6 ") else {
            continue;
        };
        let twin = format!("ip {}", rest);
        let want = identity_for(&twin);
        // Only menus whose ip twin has a real key; a menu with no ip twin is
        // ordered by default and says nothing.
        if matches!(want, Identity::Ordered) {
            continue;
        }
        assert_eq!(
            identity_for(&menu.header()),
            want,
            "{} keys as {:?} but its twin /{} keys as {:?}",
            menu.path,
            identity_for(&menu.header()),
            twin,
            want
        );
        checked += 1;
    }
    assert!(checked >= 4, "only {} ipv6 menus checked", checked);
}

/// The same question for the other natural key: a menu keyed by an address and
/// nothing else must be addressable too.
#[test]
fn every_menu_with_an_address_diffs_as_a_set_not_a_rebuild() {
    let opts = Options::default();
    let mut checked = 0;

    for menu in table() {
        let has_address = menu.attrs.iter().any(|a| a == "address");
        if !has_address || menu.attrs.iter().any(|a| a == "name") {
            continue;
        }
        let a = format!("/{}\nadd address=10.0.0.1 comment=one\n", menu.header());
        let b = format!("/{}\nadd address=10.0.0.1 comment=two\n", menu.header());
        let d = diff(
            &parse_config(&a).unwrap(),
            &parse_config(&b).unwrap(),
            &opts,
        );
        let s = &d.sections[0];
        assert_eq!(
            s.strategy,
            Strategy::Keyed,
            "{} is compared as {}, so one changed value rebuilds the menu: {:?}",
            menu.path,
            s.strategy.as_str(),
            s.ops
        );
        assert_eq!(
            (
                s.stats.changed,
                s.stats.added,
                s.stats.removed,
                s.stats.replaced
            ),
            (1, 0, 0, 0),
            "{}: expected exactly one `set`: {:?}",
            menu.path,
            s.ops
        );
        checked += 1;
    }

    assert!(
        checked >= 20,
        "only {} address-keyed menus checked",
        checked
    );
}
