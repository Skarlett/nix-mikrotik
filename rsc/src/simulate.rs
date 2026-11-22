//! Applying a patch to a model, and comparing two models.
//!
//! This is the crate's correctness property, stated as code: applying
//! `diff(a, b)` to `a` must yield `b`. It is what `rsc verify` runs and what the
//! tests in `tests/upsert.rs` assert, and it is deliberately a *model*
//! simulation rather than a device run — the model is where "the same
//! configuration" can be decided without a router.
//!
//! What it cannot prove is that RouterOS behaves the way the model says. That
//! is a separate claim, checked against a CHR; see `README.md`.

use crate::diff::{Diff, Op, Options, Removals, Strategy};
use crate::identity;
use crate::model::{Object, Origin, Prop, Section, SectionKind, Selector};
use crate::Config;

/// Apply a diff to a configuration, returning the result.
pub fn apply(config: &Config, diff: &Diff) -> Config {
    let mut cfg = config.clone();
    for section in &diff.sections {
        for op in &section.ops {
            apply_op(&mut cfg, op);
        }
    }
    cfg
}

fn ensure<'a>(cfg: &'a mut Config, path: &str) -> &'a mut Section {
    if let Some(i) = cfg.sections.iter().position(|s| s.path == path) {
        return &mut cfg.sections[i];
    }
    cfg.sections.push(Section {
        path: path.to_string(),
        kind: SectionKind::Objects,
        objects: Vec::new(),
        extras: Vec::new(),
    });
    let last = cfg.sections.len() - 1;
    &mut cfg.sections[last]
}

fn merge(into: &mut Vec<Prop>, new: Vec<Prop>) {
    for p in new {
        match into.iter_mut().find(|e| e.key == p.key) {
            Some(slot) => *slot = p,
            None => into.push(p),
        }
    }
}

/// Whether a selector addresses this object.
///
/// The stored selector is not enough on its own: a comment-keyed section stores
/// positional selectors, and an object created by `set <name>` carries its name
/// in the selector rather than in its properties.
fn object_matches(obj: &Object, sel: &Selector) -> bool {
    if obj.selector.key() == sel.key() {
        return true;
    }
    match sel {
        Selector::Singleton | Selector::Index(_) | Selector::Expr(_) => false,
        Selector::Named(n) => crate::model::prop_text(&obj.props, "name") == Some(n.as_str()),
        Selector::Comment(c) => crate::model::prop_text(&obj.props, "comment") == Some(c.as_str()),
        Selector::Find(pairs) => pairs
            .iter()
            .all(|(k, v)| crate::model::prop_text(&obj.props, k) == Some(v.as_str())),
    }
}

fn find_index(sec: &Section, sel: &Selector) -> Option<usize> {
    sec.objects.iter().position(|o| object_matches(o, sel))
}

fn apply_op(cfg: &mut Config, op: &Op) {
    match op {
        Op::Add {
            section,
            props,
            place_before,
            ..
        } => {
            let path = section.clone();
            let sec = ensure(cfg, &path);
            let index = sec.objects.len();
            let selector = identity::selector_from_props(&sec.path, props, index);
            let obj = Object {
                selector,
                props: props.clone(),
                line: 0,
                origin: Origin::Add,
            };
            match place_before.as_ref().and_then(|anchor| {
                sec.objects
                    .iter()
                    .position(|o| o.selector.key() == anchor.key())
            }) {
                Some(pos) => sec.objects.insert(pos, obj),
                None => sec.objects.push(obj),
            }
        }
        Op::Set {
            section,
            selector,
            changes,
            ..
        } => {
            let path = section.clone();
            let sec = ensure(cfg, &path);
            match find_index(sec, selector) {
                Some(i) => merge(&mut sec.objects[i].props, changes.clone()),
                // A `set` on an object the source never created addresses a
                // device default, which is exactly what `set` does on a router:
                // the object is there, the file just never mentions it.
                None => sec.objects.push(Object {
                    selector: selector.clone(),
                    props: changes.clone(),
                    line: 0,
                    origin: Origin::Set,
                }),
            }
        }
        Op::Remove {
            section, selector, ..
        } => {
            if let Some(sec) = cfg.section_mut(section) {
                match selector {
                    Selector::Index(i) => {
                        if *i < sec.objects.len() {
                            sec.objects.remove(*i);
                        }
                    }
                    _ => {
                        if let Some(i) = find_index(sec, selector) {
                            sec.objects.remove(i);
                        }
                    }
                }
            }
        }
        Op::Move {
            section,
            selector,
            to,
        } => {
            if let Some(sec) = cfg.section_mut(section) {
                if let Some(pos) = find_index(sec, selector) {
                    let obj = sec.objects.remove(pos);
                    let at = (*to).min(sec.objects.len());
                    sec.objects.insert(at, obj);
                }
            }
        }
        Op::SingletonSet {
            section, changes, ..
        } => {
            let path = section.clone();
            let sec = ensure(cfg, &path);
            sec.kind = SectionKind::Singleton;
            match sec.object_mut(&Selector::Singleton) {
                Some(obj) => merge(&mut obj.props, changes.clone()),
                None => sec.objects.push(Object {
                    selector: Selector::Singleton,
                    props: changes.clone(),
                    line: 0,
                    origin: Origin::Set,
                }),
            }
        }
        Op::Unresolvable { .. } => {}
    }
}

/// Every way `actual` differs from `expected`, as readable lines.
///
/// Order matters only where the menu has no stable identity: an ordered section
/// is compared as a list, a keyed one as a map.
///
/// In upsert mode (`Options::removals = Withhold`) the claim being checked is
/// deliberately different, not weaker: the patch deletes nothing, so the result
/// has to *hold every object the target declares, with every property it
/// declares* — see [`compare_upsert`]. An object the device keeps that the
/// target does not mention, or a property the patch could not drop, is what
/// "upsert" means, and is reported by the diff as withheld rather than here.
pub fn compare(expected: &Config, actual: &Config, diff: &Diff, opts: &Options) -> Vec<String> {
    if opts.removals == Removals::Withhold {
        return compare_upsert(expected, actual, diff, opts);
    }
    let mut out = Vec::new();

    for section in &expected.sections {
        let Some(got) = actual.section(&section.path) else {
            out.push(format!("/{}: missing entirely", section.path));
            continue;
        };
        let strategy = diff
            .sections
            .iter()
            .find(|s| s.path == section.path)
            .map(|s| s.strategy)
            .unwrap_or(Strategy::Keyed);

        let want = fingerprint(section, strategy, opts);
        let have = fingerprint(got, strategy, opts);
        if want == have {
            continue;
        }

        for line in &want {
            if !have.contains(line) {
                out.push(format!("/{}: expected {}", section.path, line));
            }
        }
        for line in &have {
            if !want.contains(line) {
                out.push(format!("/{}: unexpected {}", section.path, line));
            }
        }
        if want.len() == have.len()
            && out
                .last()
                .map(|l| l.contains(&section.path))
                .unwrap_or(false)
        {
            out.push(format!(
                "/{}: same objects in a different order than the target",
                section.path
            ));
        }
    }

    for section in &actual.sections {
        // A section that ends up empty is not a difference: an export never
        // carries an empty menu, so a section the patch emptied is simply gone.
        if section.objects.is_empty() {
            continue;
        }
        if expected.section(&section.path).is_none() {
            out.push(format!("/{}: present but not in the target", section.path));
        }
    }

    out
}

/// The upsert claim: every object the target declares is on the device, with
/// every property the target gives it.
///
/// Objects are matched by *content*, not by index: the patch may not delete, so
/// the device's list can be longer than the target's and an index would name a
/// different object on the two sides. Extra objects, extra properties and the
/// order of a list are not failures here — they are the objects the patch was
/// told to leave alone, and the diff reports them as withheld.
///
/// Two kinds of object are exempt, because the patch itself says it did not
/// reach them and the diff already names them: an object whose *re-creation* was
/// withheld (a property had to disappear, which RouterOS can only do by
/// removing the object), and every object in a menu whose rebuild was withheld.
/// Without the exemption `verify --upsert` would fail on the tool's own honest
/// refusal, which is how a real mismatch would hide.
fn compare_upsert(expected: &Config, actual: &Config, diff: &Diff, opts: &Options) -> Vec<String> {
    use std::collections::HashSet;

    let mut skipped_objects: HashSet<(String, String)> = HashSet::new();
    let mut skipped_sections: HashSet<String> = HashSet::new();
    for (path, op) in diff.withheld() {
        if let Some(selector) = op.selector() {
            if selector.is_positional() {
                skipped_sections.insert(path.to_string());
            } else {
                skipped_objects.insert((path.to_string(), selector.key()));
            }
        }
    }

    let mut out = Vec::new();
    for section in &expected.sections {
        if skipped_sections.contains(&section.path) {
            continue;
        }
        let Some(got) = actual.section(&section.path) else {
            out.push(format!("/{}: missing entirely", section.path));
            continue;
        };
        for want in &section.objects {
            if skipped_objects.contains(&(section.path.clone(), want.selector.key())) {
                continue;
            }
            let props: Vec<&Prop> = want
                .props
                .iter()
                .filter(|p| !(opts.ignore_derived && is_derived(&section.path, &p.key)))
                // An empty value and an absent property are the same state:
                // `/export` omits both.
                .filter(|p| !p.value.text.is_empty())
                .collect();
            let found = got.objects.iter().any(|have| {
                props.iter().all(|p| {
                    crate::model::prop_text(&have.props, &p.key) == Some(p.value.text.as_str())
                })
            });
            if !found {
                let body = props
                    .iter()
                    .map(|p| format!("{}={}", p.key, p.value.text))
                    .collect::<Vec<_>>()
                    .join(" ");
                // The selector is the object's name for a keyed menu, and the
                // props already carry it: printing both says `name=x name=x`.
                let key = want.selector.key();
                let shown = if body.contains(&key) {
                    body
                } else {
                    format!("{} {}", want.selector, body)
                };
                out.push(format!("/{}: expected {}", section.path, shown));
            }
        }
    }
    out
}

fn fingerprint(section: &Section, strategy: Strategy, opts: &Options) -> Vec<String> {
    let ordered = matches!(strategy, Strategy::CommentKeyed | Strategy::Positional);
    let mut lines: Vec<String> = section
        .objects
        .iter()
        .map(|o| {
            let mut props: Vec<String> = o
                .props
                .iter()
                .filter(|p| !(opts.ignore_derived && is_derived(&section.path, &p.key)))
                // A property written as an empty string is the same state as a
                // property that is not there: `/export` omits both.
                .filter(|p| !p.value.text.is_empty())
                .map(|p| format!("{}={}", p.key, p.value.text))
                .collect();
            props.sort();
            let body = props.join(" ");
            // A positional selector is the *file's* index, not a name: two
            // files describing the same object can number it differently (one
            // has an extra entry above it). Comparing the index would report a
            // difference where the configurations agree, so an object without a
            // real key is compared by its content alone.
            if ordered || o.selector.is_positional() {
                body
            } else {
                format!("{} {}", o.selector, body)
            }
        })
        .collect();
    if !ordered {
        lines.sort();
    }
    lines
}

fn is_derived(menu: &str, key: &str) -> bool {
    matches!(
        (menu, key),
        ("ip address", "network") | ("ipv6 address", "network")
    )
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::diff::diff;
    use crate::parse_config;

    fn round_trip(a: &str, b: &str) {
        let opts = Options::default();
        let ca = parse_config(a).unwrap();
        let cb = parse_config(b).unwrap();
        let d = diff(&ca, &cb, &opts);
        let got = apply(&ca, &d);
        let problems = compare(&cb, &got, &d, &opts);
        assert!(problems.is_empty(), "{}", problems.join("\n"));
    }

    #[test]
    fn add_set_remove_round_trips() {
        round_trip(
            "/ip pool\nadd name=a ranges=1\nadd name=b ranges=2\n/ip dns\nset servers=1.1.1.1\n",
            "/ip pool\nadd name=a ranges=9\nadd name=c ranges=3\n/ip dns\nset servers=9.9.9.9\n",
        );
    }

    #[test]
    fn a_replacement_round_trips() {
        round_trip(
            "/ip pool\nadd name=a ranges=1 comment=x\n",
            "/ip pool\nadd name=a ranges=1\n",
        );
    }

    #[test]
    fn an_ordered_menu_round_trips_with_comments() {
        round_trip(
            "/ip firewall filter\nadd chain=input action=accept comment=a\nadd chain=input action=drop comment=b\n",
            "/ip firewall filter\nadd chain=input action=drop comment=b\nadd chain=input action=accept comment=a\nadd chain=input action=accept comment=c\n",
        );
    }

    #[test]
    fn a_rewritten_menu_round_trips() {
        round_trip(
            "/ip firewall filter\nadd chain=input action=accept\nadd chain=input action=drop\n",
            "/ip firewall filter\nadd chain=input action=accept\nadd chain=input action=accept protocol=icmp\nadd chain=input action=drop\n",
        );
    }
}
