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
