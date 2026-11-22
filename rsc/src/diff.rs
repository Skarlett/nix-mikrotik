//! The differ: two configurations in, the operations that turn the first into
//! the second.
//!
//! The hard part is not comparing properties, it is *addressing* objects. An
//! `/export` carries no `.id`, so a patch has to name what it changes the way a
//! human would in the console. Four strategies, one per section:
//!
//! * [`Strategy::Keyed`] — the menu has a stable identity (a name, an address
//!   plus interface). Match by it, emit `set [find …]`, `add`, `remove`.
//! * [`Strategy::CommentKeyed`] — an ordered menu whose every object carries a
//!   comment. The comment is the only stable handle RouterOS offers on a
//!   firewall rule, so it is used as the key, and `place-before=` plus `move`
//!   restore the declared order.
//! * [`Strategy::Positional`] — an ordered menu with no handle at all. Nothing in
//!   the text can address rule 3 of five, so the section is removed and rebuilt
//!   in order. Exact, and churny — which is the honest trade.
//! * [`Strategy::Singleton`] — one settings object. Properties can be added and
//!   changed, never removed: see [`Op::Unresolvable`].
//!
//! Property comparison is on decoded text, so `comment="a b"` and
//! `comment=a b` compare equal, and the patch re-prints whichever spelling the
//! *target* file used.

use crate::identity::{identity_for, Identity};
use crate::model::{Object, Origin, Prop, Section, SectionKind, Selector};
use crate::Config;
use std::collections::HashSet;

/// Knobs that change what counts as a difference.
#[derive(Debug, Clone)]
pub struct Options {
    /// Ignore properties RouterOS derives from another property, so that a file
    /// which omits them is not seen as wanting them removed. `/ip address`
    /// carries `network=`, which the device computes from `address=`.
    pub ignore_derived: bool,
}

impl Default for Options {
    fn default() -> Self {
        Options {
            ignore_derived: true,
        }
    }
}

/// How a section is compared.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Strategy {
    Keyed,
    CommentKeyed,
    Positional,
    Singleton,
    /// Lines the model could not interpret; reported, never patched.
    Unmodelled,
}

impl Strategy {
    pub fn as_str(&self) -> &'static str {
        match self {
            Strategy::Keyed => "keyed",
            Strategy::CommentKeyed => "comment-keyed",
            Strategy::Positional => "positional",
            Strategy::Singleton => "singleton",
            Strategy::Unmodelled => "unmodelled",
        }
    }
}

/// Why an object is being added.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum AddReason {
    /// The object is new.
    New,
    /// The object exists but a property has to disappear, and RouterOS cannot
    /// unset a property — so it is removed and re-created.
    Replaced,
}

/// One operation, in the order it has to run.
#[derive(Debug, Clone)]
pub enum Op {
    Add {
        section: String,
        props: Vec<Prop>,
        /// Insert before the object this selector addresses; `None` appends.
        place_before: Option<Selector>,
        reason: AddReason,
    },
    Set {
        section: String,
        selector: Selector,
        changes: Vec<Prop>,
    },
    Remove {
        section: String,
        selector: Selector,
        /// Whether the selector names the object (`find …`) rather than
        /// counting to it.
        exact: bool,
    },
    Move {
        section: String,
        selector: Selector,
        to: usize,
    },
    /// A `set` on a singleton menu.
    SingletonSet { section: String, changes: Vec<Prop> },
    /// A property the target file drops that no patch can drop.
    Unresolvable {
        section: String,
        selector: Selector,
        prop: String,
    },
}

impl Op {
    pub fn section(&self) -> &str {
        match self {
            Op::Add { section, .. }
            | Op::Set { section, .. }
            | Op::Remove { section, .. }
            | Op::Move { section, .. }
            | Op::SingletonSet { section, .. }
            | Op::Unresolvable { section, .. } => section,
        }
    }

    /// A one-line description, used by the human report.
    pub fn describe(&self) -> String {
        match self {
            Op::Add { props, reason, .. } => {
                let what = match reason {
                    AddReason::New => "add",
                    AddReason::Replaced => "add (replaces)",
                };
                format!("{} {}", what, render_props(props))
            }
            Op::Set {
                selector, changes, ..
            } => {
                format!("set {} {}", selector, render_props(changes))
            }
            Op::Remove {
                selector, exact, ..
            } => {
                let how = if *exact { "" } else { " (by position)" };
                format!("remove {}{}", selector, how)
            }
            Op::Move { selector, to, .. } => format!("move {} to {}", selector, to),
            Op::SingletonSet { changes, .. } => format!("set {}", render_props(changes)),
            Op::Unresolvable { selector, prop, .. } => {
                format!(
                    "cannot reset {} on {}: RouterOS has no unset",
                    prop, selector
                )
            }
        }
    }
}

fn render_props(props: &[Prop]) -> String {
    props
        .iter()
        .map(|p| p.raw.clone())
        .collect::<Vec<_>>()
        .join(" ")
}

/// Per-section counts, for the report.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct Stats {
    pub added: usize,
    pub changed: usize,
    pub removed: usize,
    pub replaced: usize,
    pub moved: usize,
    pub unresolvable: usize,
}

impl Stats {
    pub fn total(&self) -> usize {
        self.added + self.changed + self.removed + self.replaced + self.moved + self.unresolvable
    }
}

/// One section's share of the diff.
#[derive(Debug, Clone)]
pub struct SectionDiff {
    pub path: String,
    pub strategy: Strategy,
    pub ops: Vec<Op>,
    pub stats: Stats,
    pub notes: Vec<String>,
}

/// The whole diff.
#[derive(Debug, Clone, Default)]
pub struct Diff {
    pub sections: Vec<SectionDiff>,
    pub notes: Vec<String>,
}

impl Diff {
    pub fn is_empty(&self) -> bool {
        self.sections.iter().all(|s| s.ops.is_empty())
    }

    pub fn stats(&self) -> Stats {
        let mut total = Stats::default();
        for s in &self.sections {
            total.added += s.stats.added;
            total.changed += s.stats.changed;
            total.removed += s.stats.removed;
            total.replaced += s.stats.replaced;
            total.moved += s.stats.moved;
            total.unresolvable += s.stats.unresolvable;
        }
        total
    }

    /// Whether every operation the diff emitted is one the device can perform
    /// exactly. A positional remove is not: it assumes the device's list is the
    /// one the source file describes.
    pub fn is_exact(&self) -> bool {
        !self.sections.iter().any(|s| {
            s.ops.iter().any(|op| match op {
                Op::Remove { exact: false, .. } => true,
                Op::Unresolvable { .. } => true,
                Op::Set { selector, .. } | Op::Move { selector, .. } => selector.is_positional(),
                _ => false,
            })
        })
    }
}

/// A property RouterOS computes from another, so that its absence in the target
/// file does not mean "remove it".
fn is_derived(menu: &str, key: &str) -> bool {
    matches!(
        (menu, key),
        ("ip address", "network") | ("ipv6 address", "network")
    )
}

/// A property that can be reset to its default by writing an empty string.
///
/// Measured on 7.15.3: `set [find …] comment=""` clears a comment and the next
/// `/export` omits it, while `ranges=""` is refused (`failure: no address
/// ranges specified`) and `!ranges`, `!comment` and `unset` are syntax errors.
/// So this list holds the properties a patch can drop in place; every other
/// dropped property costs a re-create.
fn is_resettable(_menu: &str, key: &str) -> bool {
    key == "comment"
}

/// What has to change on one object: the properties to write, and the
/// properties whose absence has to be *earned* by re-creating the object.
fn property_changes(
    menu: &str,
    a: Option<&Object>,
    b: Option<&Object>,
    opts: &Options,
) -> (Vec<Prop>, Vec<String>) {
    let (mut changed, removed) = compare(a, b, menu, opts);
    let mut must_replace = Vec::new();
    for key in removed {
        if is_resettable(menu, &key) {
            changed.push(Prop::cleared(&key));
        } else {
            must_replace.push(key);
        }
    }
    (changed, must_replace)
}

/// Compute the operations that turn `a` into `b`.
pub fn diff(a: &Config, b: &Config, opts: &Options) -> Diff {
    let mut out = Diff::default();
    let mut seen: HashSet<String> = HashSet::new();

    for section in &b.sections {
        seen.insert(section.path.clone());
        let left = a.section(&section.path);
        out.sections
            .push(diff_section(&section.path, left, Some(section), opts));
    }
    for section in &a.sections {
        if seen.contains(&section.path) {
            continue;
        }
        out.sections
            .push(diff_section(&section.path, Some(section), None, opts));
    }

    out
}

fn strategy_for(path: &str, a: Option<&Section>, b: Option<&Section>, _opts: &Options) -> Strategy {
    let kind = b.or(a).map(|s| s.kind).unwrap_or(SectionKind::Objects);
    if kind == SectionKind::Unmodelled {
        return Strategy::Unmodelled;
    }
    if kind == SectionKind::Singleton {
        return Strategy::Singleton;
    }

    // Only a menu the identity table calls `Ordered` has no handle at all. A
    // keyed menu whose source addressed its objects by index (`/port set 0 …`)
    // still has a keyed comparison available; it is the *selector* that is
    // positional, and that is reported rather than made into a rewrite.
    let ordered = matches!(identity_for(path), Identity::Ordered);

    if !ordered {
        // A key that appears twice in one section cannot address one object.
        let dup = |s: &Section| {
            let mut keys: Vec<String> = s.objects.iter().map(|o| o.selector.key()).collect();
            keys.sort();
            keys.windows(2).any(|w| w[0] == w[1])
        };
        let dup = a.map(dup).unwrap_or(false) || b.map(dup).unwrap_or(false);
        return if dup {
            Strategy::Positional
        } else {
            Strategy::Keyed
        };
    }

    // An ordered menu is addressable only through its comments, and only if
    // every object has one and no two share it — `remove [find comment=x]`
    // removes *all* matches, so a duplicate comment is not a handle.
    let comments = |s: Option<&Section>| match s {
        None => true,
        Some(s) => {
            if !s.objects.is_empty() && !s.has_comment_everywhere() {
                return false;
            }
            let mut seen: Vec<String> = s.objects.iter().filter_map(|o| s.comment_of(o)).collect();
            seen.sort();
            !seen.windows(2).any(|w| w[0] == w[1])
        }
    };
    if comments(a) && comments(b) {
        Strategy::CommentKeyed
    } else {
        Strategy::Positional
    }
}

fn diff_section(
    path: &str,
    a: Option<&Section>,
    b: Option<&Section>,
    opts: &Options,
) -> SectionDiff {
    let strategy = strategy_for(path, a, b, opts);
    let mut out = SectionDiff {
        path: path.to_string(),
        strategy,
        ops: Vec::new(),
        stats: Stats::default(),
        notes: Vec::new(),
    };

    match strategy {
        Strategy::Unmodelled => {
            out.notes
                .push("lines here are not modelled; nothing is patched".to_string());
        }
        Strategy::Singleton => diff_singleton(path, a, b, opts, &mut out),
        Strategy::Keyed => diff_keyed(path, a, b, opts, &mut out),
        Strategy::CommentKeyed => diff_comment_keyed(path, a, b, opts, &mut out),
        Strategy::Positional => diff_positional(path, a, b, opts, &mut out),
    }

    out
}

fn empty_section(path: &str) -> Section {
    Section {
        path: path.to_string(),
        kind: SectionKind::Objects,
        objects: Vec::new(),
        extras: Vec::new(),
    }
}

fn diff_singleton(
    path: &str,
    a: Option<&Section>,
    b: Option<&Section>,
    opts: &Options,
    out: &mut SectionDiff,
) {
    let empty = empty_section(path);
    let a = a.unwrap_or(&empty);
    let b = b.unwrap_or(&empty);
    let aobj = a.object(&Selector::Singleton);
    let bobj = b.object(&Selector::Singleton);

    let (changed, removed) = compare(aobj, bobj, path, opts);
    if !changed.is_empty() {
        out.ops.push(Op::SingletonSet {
            section: path.to_string(),
            changes: changed.clone(),
        });
        out.stats.changed += changed.len();
    }
    for key in removed {
        out.ops.push(Op::Unresolvable {
            section: path.to_string(),
            selector: Selector::Singleton,
            prop: key,
        });
        out.stats.unresolvable += 1;
    }
}

fn diff_keyed(
    path: &str,
    a: Option<&Section>,
    b: Option<&Section>,
    opts: &Options,
    out: &mut SectionDiff,
) {
    let empty = empty_section(path);
    let a = a.unwrap_or(&empty);
    let b = b.unwrap_or(&empty);

    let mut adds = Vec::new();
    let mut replaces = Vec::new();
    let mut removes = Vec::new();

    for obj_b in &b.objects {
        match a.object(&obj_b.selector) {
            None => {
                // A `set`-origin object is a device default the source only
                // mentions: `set telnet disabled=yes` on a router that has
                // never listed it still works, and is a silent no-op if it
                // does not exist. Copying it with `add` would invent an object.
                if obj_b.origin == Origin::Set {
                    out.stats.changed += obj_b.props.len();
                    out.ops.push(Op::Set {
                        section: path.to_string(),
                        selector: obj_b.selector.clone(),
                        changes: obj_b.props.clone(),
                    });
                } else {
                    adds.push(Op::Add {
                        section: path.to_string(),
                        props: obj_b.props.clone(),
                        place_before: None,
                        reason: AddReason::New,
                    });
                    out.stats.added += 1;
                }
            }
            Some(obj_a) => {
                let (changed, removed) = property_changes(path, Some(obj_a), Some(obj_b), opts);
                if !removed.is_empty() {
                    // A property has to disappear and RouterOS cannot unset
                    // one, so the object is removed and re-created from the
                    // target's own text: that is exact by construction. The
                    // remove comes first because `add name=x` on an existing
                    // x is refused.
                    replaces.push((
                        index_of(&obj_a.selector),
                        vec![
                            Op::Remove {
                                section: path.to_string(),
                                selector: obj_a.selector.clone(),
                                exact: !obj_a.selector.is_positional(),
                            },
                            Op::Add {
                                section: path.to_string(),
                                props: obj_b.props.clone(),
                                place_before: if obj_a.selector.is_positional() {
                                    // Re-created where it was, so the indices
                                    // of the objects below it stay valid.
                                    Some(obj_a.selector.clone())
                                } else {
                                    None
                                },
                                reason: AddReason::Replaced,
                            },
                        ],
                    ));
                    out.stats.replaced += 1;
                } else if !changed.is_empty() {
                    out.stats.changed += changed.len();
                    out.ops.push(Op::Set {
                        section: path.to_string(),
                        selector: obj_a.selector.clone(),
                        changes: changed,
                    });
                }
            }
        }
    }

    for obj_a in &a.objects {
        if b.object(&obj_a.selector).is_none() {
            removes.push((
                index_of(&obj_a.selector),
                vec![Op::Remove {
                    section: path.to_string(),
                    selector: obj_a.selector.clone(),
                    exact: !obj_a.selector.is_positional(),
                }],
            ));
            out.stats.removed += 1;
        }
    }

    // Adds and replacements before removals: a stale object alive for one more
    // command is harmless, a missing one is not.
    out.ops.extend(adds);

    // Then the removals, positional ones first and from the end of the list:
    // an index is only the one the source file described while nothing below it
    // has moved, so a `remove 1` followed by `remove 2` deletes the wrong
    // objects. Find-based removals do not care and go afterwards.
    let mut tail: Vec<(Option<usize>, Vec<Op>)> = replaces;
    tail.extend(removes);
    tail.sort_by_key(|(idx, _)| match idx {
        Some(i) => (0u8, std::cmp::Reverse(*i)),
        None => (1u8, std::cmp::Reverse(0usize)),
    });
    for (_, ops) in tail {
        out.ops.extend(ops);
    }
}

/// The index a positional selector addresses.
fn index_of(sel: &Selector) -> Option<usize> {
    match sel {
        Selector::Index(i) => Some(*i),
        _ => None,
    }
}

fn diff_comment_keyed(
    path: &str,
    a: Option<&Section>,
    b: Option<&Section>,
    opts: &Options,
    out: &mut SectionDiff,
) {
    let empty = empty_section(path);
    let a = a.unwrap_or(&empty);
    let b = b.unwrap_or(&empty);

    let comment = |s: &Section, o: &Object| s.comment_of(o).unwrap_or_default();
    let akeys: Vec<String> = a.objects.iter().map(|o| comment(a, o)).collect();
    let bkeys: Vec<String> = b.objects.iter().map(|o| comment(b, o)).collect();
    let bset: HashSet<String> = bkeys.iter().cloned().collect();

    // Objects whose property set shrinks have to be re-created.
    let mut replace: HashSet<String> = HashSet::new();
    let mut sets = Vec::new();
    for (i, obj_b) in b.objects.iter().enumerate() {
        let key = &bkeys[i];
        if let Some(obj_a) = a.objects.iter().find(|o| comment(a, o) == *key) {
            let (changed, removed) = property_changes(path, Some(obj_a), Some(obj_b), opts);
            if !removed.is_empty() {
                replace.insert(key.clone());
            } else if !changed.is_empty() {
                out.stats.changed += changed.len();
                sets.push(Op::Set {
                    section: path.to_string(),
                    selector: Selector::Comment(key.clone()),
                    changes: changed,
                });
            }
        }
    }

    // A key that exists for the whole patch and may therefore be anchored to.
    let mut stable: HashSet<String> = akeys
        .iter()
        .filter(|k| bset.contains(*k) && !replace.contains(*k))
        .cloned()
        .collect();
    // The list as the device will see it while the ops run.
    let mut present: Vec<String> = akeys.clone();

    let place =
        |key: &str, present: &mut Vec<String>, stable: &mut HashSet<String>, from: usize| {
            let anchor = bkeys[from + 1..]
                .iter()
                .find(|k| stable.contains(*k))
                .cloned();
            present.retain(|k| k != key);
            match anchor
                .as_ref()
                .and_then(|anc| present.iter().position(|k| k == anc))
            {
                Some(pos) => present.insert(pos, key.to_string()),
                None => present.push(key.to_string()),
            }
            stable.insert(key.to_string());
            anchor
        };

    let mut replacements = Vec::new();
    for (i, obj_b) in b.objects.iter().enumerate() {
        let key = &bkeys[i];
        if !replace.contains(key) {
            continue;
        }
        // Remove first: `remove [find comment=x]` matches every rule carrying
        // that comment, so leaving the old one in place while the new one is
        // added would delete both.
        replacements.push(Op::Remove {
            section: path.to_string(),
            selector: Selector::Comment(key.clone()),
            exact: true,
        });
        present.retain(|k| k != key);
        let anchor = place(key, &mut present, &mut stable, i);
        replacements.push(Op::Add {
            section: path.to_string(),
            props: obj_b.props.clone(),
            place_before: anchor.map(Selector::Comment),
            reason: AddReason::Replaced,
        });
        out.stats.replaced += 1;
    }

    let mut adds = Vec::new();
    for (i, obj_b) in b.objects.iter().enumerate() {
        let key = &bkeys[i];
        if replace.contains(key) || akeys.contains(key) {
            continue;
        }
        if obj_b.origin == Origin::Set {
            out.stats.changed += obj_b.props.len();
            sets.push(Op::Set {
                section: path.to_string(),
                selector: Selector::Comment(key.clone()),
                changes: obj_b.props.clone(),
            });
            continue;
        }
        let anchor = place(key, &mut present, &mut stable, i);
        adds.push(Op::Add {
            section: path.to_string(),
            props: obj_b.props.clone(),
            place_before: anchor.map(Selector::Comment),
            reason: AddReason::New,
        });
        out.stats.added += 1;
    }

    let mut removes = Vec::new();
    for obj_a in &a.objects {
        let key = comment(a, obj_a);
        if bset.contains(&key) {
            continue;
        }
        removes.push(Op::Remove {
            section: path.to_string(),
            selector: Selector::Comment(key.clone()),
            exact: true,
        });
        out.stats.removed += 1;
        present.retain(|k| *k != key);
    }

    // Order: what the target declares, reached by moving objects that already
    // exist. The positions are those the device has after the adds and removes
    // above, which is exactly what the moves will see.
    let mut moves = Vec::new();
    for i in 0..bkeys.len() {
        if present.get(i) == Some(&bkeys[i]) {
            continue;
        }
        let Some(j) = present.iter().position(|k| *k == bkeys[i]) else {
            continue;
        };
        if j <= i {
            continue;
        }
        moves.push(Op::Move {
            section: path.to_string(),
            selector: Selector::Comment(bkeys[i].clone()),
            to: i,
        });
        out.stats.moved += 1;
        let key = present.remove(j);
        present.insert(i, key);
    }

    out.ops.extend(sets);
    out.ops.extend(replacements);
    out.ops.extend(adds);
    out.ops.extend(removes);
    out.ops.extend(moves);
}

fn diff_positional(
    path: &str,
    a: Option<&Section>,
    b: Option<&Section>,
    opts: &Options,
    out: &mut SectionDiff,
) {
    let empty = empty_section(path);
    let a = a.unwrap_or(&empty);
    let b = b.unwrap_or(&empty);

    // Same length: each rule still sits where it did, so the change is a `set`
    // at that position — what a human would type, and nothing is recreated.
    // RouterOS takes `place-before` as an index too, so a rule whose property
    // set shrinks can be replaced in place rather than moved to the end.
    if a.objects.len() == b.objects.len() {
        for i in 0..b.objects.len() {
            let obj_a = &a.objects[i];
            let obj_b = &b.objects[i];
            let (changed, removed) = property_changes(path, Some(obj_a), Some(obj_b), opts);
            if !removed.is_empty() {
                out.ops.push(Op::Remove {
                    section: path.to_string(),
                    selector: Selector::Index(i),
                    exact: false,
                });
                out.ops.push(Op::Add {
                    section: path.to_string(),
                    props: obj_b.props.clone(),
                    place_before: Some(Selector::Index(i)),
                    reason: AddReason::Replaced,
                });
                out.stats.replaced += 1;
            } else if !changed.is_empty() {
                out.stats.changed += changed.len();
                out.ops.push(Op::Set {
                    section: path.to_string(),
                    selector: Selector::Index(i),
                    changes: changed,
                });
            }
        }
        return;
    }

    // Different length: nothing in the text can address rule 3 of five, so the
    // section is removed and rebuilt in the target's order.
    for i in (0..a.objects.len()).rev() {
        out.ops.push(Op::Remove {
            section: path.to_string(),
            selector: Selector::Index(i),
            exact: false,
        });
        out.stats.removed += 1;
    }
    for obj_b in &b.objects {
        out.ops.push(Op::Add {
            section: path.to_string(),
            props: obj_b.props.clone(),
            place_before: None,
            reason: AddReason::New,
        });
        out.stats.added += 1;
    }
    if !a.objects.is_empty() || !b.objects.is_empty() {
        out.notes.push(
            "no stable handle in this menu, so the section is rebuilt: exact, but every object \
             is re-created"
                .to_string(),
        );
    }
}

/// Compare two objects: the properties to set, and the keys that have to
/// disappear.
fn compare(
    a: Option<&Object>,
    b: Option<&Object>,
    menu: &str,
    opts: &Options,
) -> (Vec<Prop>, Vec<String>) {
    let empty: Vec<Prop> = Vec::new();
    let ap = a.map(|o| &o.props).unwrap_or(&empty);
    let bp = b.map(|o| &o.props).unwrap_or(&empty);

    let mut changed = Vec::new();
    for p in bp {
        match ap.iter().find(|q| q.key == p.key) {
            Some(q) if q.value.text == p.value.text => {}
            _ => changed.push(p.clone()),
        }
    }

    let mut removed = Vec::new();
    for q in ap {
        if bp.iter().any(|p| p.key == q.key) {
            continue;
        }
        if opts.ignore_derived && is_derived(menu, &q.key) {
            continue;
        }
        removed.push(q.key.clone());
    }

    (changed, removed)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::parse_config;

    fn d(a: &str, b: &str) -> Diff {
        diff(
            &parse_config(a).unwrap(),
            &parse_config(b).unwrap(),
            &Options::default(),
        )
    }

    #[test]
    fn an_identical_config_has_no_operations() {
        let src = "/ip pool\nadd name=lan ranges=10.0.0.10-10.0.0.20\n";
        let diff = d(src, src);
        assert!(diff.is_empty(), "{:?}", diff);
        assert!(diff.is_exact());
    }

    #[test]
    fn a_new_object_is_an_add() {
        let diff = d(
            "/ip pool\nadd name=lan ranges=10.0.0.10-10.0.0.20\n",
            "/ip pool\nadd name=lan ranges=10.0.0.10-10.0.0.20\nadd name=wan ranges=10.1.0.10-10.1.0.20\n",
        );
        let stats = diff.stats();
        assert_eq!(stats.added, 1);
        assert_eq!(stats.removed, 0);
    }

    #[test]
    fn a_changed_value_is_a_set() {
        let diff = d(
            "/ip pool\nadd name=lan ranges=10.0.0.10-10.0.0.20\n",
            "/ip pool\nadd name=lan ranges=10.0.0.30-10.0.0.40\n",
        );
        let ops = &diff.sections[0].ops;
        assert_eq!(ops.len(), 1);
        assert!(matches!(ops[0], Op::Set { .. }), "{:?}", ops[0]);
    }

    #[test]
    fn a_dropped_property_forces_a_replacement() {
        let diff = d(
            "/interface wireguard\nadd listen-port=51820 mtu=1420 name=wg0\n",
            "/interface wireguard\nadd listen-port=51820 name=wg0\n",
        );
        let stats = diff.stats();
        assert_eq!(stats.replaced, 1, "{:?}", diff.sections[0]);
        assert!(diff.sections[0].ops.iter().any(|o| matches!(
            o,
            Op::Add {
                reason: AddReason::Replaced,
                ..
            }
        )));
    }

    /// `comment=""` is the one property measured to reset in place, so a
    /// dropped comment must not cost a re-create.
    #[test]
    fn a_dropped_comment_is_cleared_not_replaced() {
        let diff = d(
            "/ip pool\nadd name=lan ranges=1 comment=old\n",
            "/ip pool\nadd name=lan ranges=1\n",
        );
        let s = &diff.sections[0];
        assert_eq!(s.stats.replaced, 0, "{:?}", s.ops);
        assert_eq!(s.ops.len(), 1, "{:?}", s.ops);
        let Op::Set { changes, .. } = &s.ops[0] else {
            panic!("expected a set, got {:?}", s.ops[0])
        };
        assert_eq!(changes[0].raw, "comment=\"\"");
    }

    #[test]
    fn an_object_missing_from_the_target_is_removed() {
        let diff = d(
            "/ip pool\nadd name=lan ranges=1\nadd name=wan ranges=2\n",
            "/ip pool\nadd name=lan ranges=1\n",
        );
        assert_eq!(diff.stats().removed, 1);
    }

    #[test]
    fn a_derived_property_is_not_a_difference() {
        let diff = d(
            "/ip address\nadd address=10.0.0.1/24 interface=ether1 network=10.0.0.0\n",
            "/ip address\nadd address=10.0.0.1/24 interface=ether1\n",
        );
        assert!(diff.is_empty(), "{:?}", diff.sections[0]);
    }

    #[test]
    fn an_ordered_menu_with_comments_is_keyed_by_comment() {
        let diff = d(
            "/ip firewall filter\nadd chain=input action=accept comment=a\nadd chain=input action=drop comment=b\n",
            "/ip firewall filter\nadd chain=input action=accept comment=a\nadd chain=input action=accept comment=c\n",
        );
        let s = &diff.sections[0];
        assert_eq!(s.strategy, Strategy::CommentKeyed);
        let stats = &s.stats;
        assert_eq!((stats.added, stats.removed), (1, 1));
        // The new rule is anchored before nothing (b was last) and appended.
        assert!(s.ops.iter().any(|o| matches!(o, Op::Add { .. })));
    }

    #[test]
    fn an_ordered_menu_without_comments_is_set_by_position() {
        let diff = d(
            "/ip firewall filter\nadd chain=input action=accept\nadd chain=input action=drop\n",
            "/ip firewall filter\nadd chain=input action=accept\nadd chain=input action=accept protocol=icmp\n",
        );
        let s = &diff.sections[0];
        assert_eq!(s.strategy, Strategy::Positional);
        assert_eq!(s.stats.changed, 2, "{:?}", s.ops);
        assert_eq!(s.stats.added + s.stats.removed, 0, "{:?}", s.ops);
        // Addressing by position is not exact: it assumes the device's list is
        // the one the source describes.
        assert!(!diff.is_exact());
    }

    #[test]
    fn a_longer_ordered_menu_is_rebuilt() {
        let diff = d(
            "/ip firewall filter\nadd chain=input action=accept\nadd chain=input action=drop\n",
            "/ip firewall filter\nadd chain=input action=accept\nadd chain=input action=accept protocol=icmp\nadd chain=input action=drop\n",
        );
        let s = &diff.sections[0];
        assert_eq!(s.strategy, Strategy::Positional);
        assert_eq!((s.stats.removed, s.stats.added), (2, 3), "{:?}", s.ops);
        assert!(!diff.is_exact());
    }

    #[test]
    fn a_reordered_ordered_menu_emits_a_move() {
        let diff = d(
            "/ip firewall filter\nadd chain=input action=accept comment=a\nadd chain=input action=accept comment=b\n",
            "/ip firewall filter\nadd chain=input action=accept comment=b\nadd chain=input action=accept comment=a\n",
        );
        let s = &diff.sections[0];
        assert_eq!(s.stats.moved, 1, "{:?}", s.ops);
    }

    #[test]
    fn a_singleton_property_that_disappears_is_reported_not_patched() {
        let diff = d(
            "/ip dns\nset servers=1.1.1.1 allow-remote-requests=yes\n",
            "/ip dns\nset servers=1.1.1.1\n",
        );
        let s = &diff.sections[0];
        assert_eq!(s.strategy, Strategy::Singleton);
        assert_eq!(s.stats.unresolvable, 1);
        assert!(!diff.is_exact());
    }

    #[test]
    fn an_address_on_another_interface_is_a_different_object() {
        let diff = d(
            "/ip address\nadd address=10.0.0.1/24 interface=ether1\n",
            "/ip address\nadd address=10.0.0.1/24 interface=ether2\n",
        );
        let stats = diff.stats();
        assert_eq!((stats.added, stats.removed), (1, 1));
    }
}
