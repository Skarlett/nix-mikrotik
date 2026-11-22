//! Rendering a diff as a `.rsc` script.
//!
//! Every line here is a console command a device accepts, not a description:
//! the whole point of the tool is that the output can be uploaded and
//! `/import`ed. Three rules shape it:
//!
//! * **Argument text comes from the target file.** An `add` or `set` prints the
//!   target's own `key=value` tokens, so quoting, escaping and argument order
//!   are the ones the target file already proved parse. Re-spelling from a
//!   decoded value is how a base64 key ending in `=` gets truncated.
//! * **Sections in target order, removals after adds** within a section, so an
//!   object that something else references still exists when the reference is
//!   added.
//! * **Nothing is invented.** An operation the device cannot perform is
//!   emitted as a `#` comment naming the property, and `rsc verify` reports it.

use crate::diff::{AddReason, Diff, Op};
use crate::model::Selector;
use crate::syntax::lexer::spell;

#[derive(Debug, Clone)]
pub struct RenderOptions {
    /// What this patch is applied to, for the header.
    pub from: String,
    /// What it should produce.
    pub to: String,
    /// Append `:log info "…"` as the last line. RouterOS refuses a script it
    /// cannot parse *whole* and exits 0 either way, so the log line is the only
    /// positive evidence that the file ran to the end.
    pub sentinel: Option<String>,
}

impl RenderOptions {
    pub fn new(from: &str, to: &str) -> Self {
        RenderOptions {
            from: from.to_string(),
            to: to.to_string(),
            sentinel: None,
        }
    }
}

/// Render the diff as a script.
pub fn render(diff: &Diff, opts: &RenderOptions) -> String {
    let stats = diff.stats();
    let mut out = String::new();

    out.push_str("# rsc patch -- generated, do not edit\n");
    out.push_str(&format!("# from: {}\n", opts.from));
    out.push_str(&format!("# to:   {}\n", opts.to));
    out.push_str(&format!(
        "# ops:  {} add, {} set, {} remove, {} replace, {} move, {} unperformable\n",
        stats.added, stats.changed, stats.removed, stats.replaced, stats.moved, stats.unresolvable
    ));
    if stats.withheld > 0 {
        out.push_str(&format!(
            "# withheld: {} operation(s) would delete; this patch is an upsert and leaves them out\n",
            stats.withheld
        ));
    }
    out.push_str(&format!(
        "# exact: {}\n",
        if diff.is_exact() {
            "yes -- every operation addresses its object"
        } else {
            "no -- see the notes below; verify against the device"
        }
    ));

    let mut wrote_section = String::new();
    for section in &diff.sections {
        if section.ops.is_empty() && section.withheld.is_empty() {
            continue;
        }
        if wrote_section != section.path {
            out.push_str(&format!("/{}\n", section.path));
            wrote_section = section.path.clone();
        }
        for note in &section.notes {
            out.push_str(&format!("# note: {}\n", note));
        }
        for op in &section.ops {
            for line in render_op(op) {
                out.push_str(&line);
                out.push('\n');
            }
        }
        // What the patch deliberately does not do, spelled as the command it
        // would have been, so a reader can run one by hand if that is what they
        // meant. A comment, because `/import` would otherwise perform it.
        for op in &section.withheld {
            out.push_str(&format!("# withheld: {}\n", op.describe()));
        }
    }

    if diff.is_empty() {
        out.push_str("# nothing to do: the configurations are equivalent\n");
    }

    if let Some(marker) = &opts.sentinel {
        out.push_str(&format!(
            ":log info \"{}\"\n",
            crate::syntax::lexer::escape(marker)
        ));
    }

    out
}

fn render_op(op: &Op) -> Vec<String> {
    match op {
        Op::Add {
            props,
            place_before,
            reason,
            ..
        } => {
            let mut line = String::from("add");
            for p in props {
                line.push(' ');
                line.push_str(&p.raw);
            }
            if let Some(sel) = place_before {
                line.push_str(&format!(" place-before={}", selector(sel)));
            }
            match reason {
                AddReason::New => vec![line],
                // The reader has to know an object was recreated, and RouterOS
                // has no end-of-line comment that survives a `;`.
                AddReason::Replaced => vec![
                    format!(
                        "# replace: {} is removed and re-created below",
                        selector_or_none(place_before)
                    ),
                    line,
                ],
            }
        }
        Op::Set {
            selector: sel,
            changes,
            ..
        } => {
            let mut line = format!("set {}", selector(sel));
            for p in changes {
                line.push(' ');
                line.push_str(&p.raw);
            }
            vec![line]
        }
        Op::Remove {
            selector: sel,
            exact,
            ..
        } => {
            let line = format!("remove {}", selector(sel));
            if *exact {
                vec![line]
            } else {
                vec![
                    "# by position: this menu has no stable handle, so the index assumes the device matches the source".to_string(),
                    line,
                ]
            }
        }
        Op::Move {
            selector: sel, to, ..
        } => {
            vec![format!("move {} destination={}", selector(sel), to)]
        }
        Op::SingletonSet { changes, .. } => {
            let mut line = String::from("set");
            for p in changes {
                line.push(' ');
                line.push_str(&p.raw);
            }
            vec![line]
        }
        Op::Unresolvable {
            selector: sel,
            prop,
            ..
        } => vec![format!(
            "# rsc: cannot reset {} on {} -- RouterOS has no unset; recreate the object by hand",
            prop, sel
        )],
    }
}

fn selector_or_none(sel: &Option<Selector>) -> String {
    sel.as_ref()
        .map(selector)
        .unwrap_or_else(|| "object".to_string())
}

/// Spell a selector the way a console command takes it.
pub fn selector(sel: &Selector) -> String {
    match sel {
        Selector::Singleton => String::new(),
        Selector::Named(n) => find_expr(&[("name".to_string(), n.clone())]),
        Selector::Comment(c) => find_expr(&[("comment".to_string(), c.clone())]),
        Selector::Find(pairs) => find_expr(pairs),
        Selector::Index(i) => i.to_string(),
        Selector::Expr(e) => e.clone(),
    }
}

fn find_expr(pairs: &[(String, String)]) -> String {
    let body: Vec<String> = pairs
        .iter()
        .map(|(k, v)| format!("{}={}", k, spell(v)))
        .collect();
    format!("[find {}]", body.join(" "))
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::diff::{diff, Options};
    use crate::parse_config;

    fn patch(a: &str, b: &str) -> String {
        let d = diff(
            &parse_config(a).unwrap(),
            &parse_config(b).unwrap(),
            &Options::default(),
        );
        render(&d, &RenderOptions::new("a.rsc", "b.rsc"))
    }

    #[test]
    fn an_add_reuses_the_target_files_argument_text() {
        let out = patch(
            "/ip pool\nadd name=lan ranges=1\n",
            "/ip pool\nadd name=lan ranges=1\nadd name=wan ranges=2 comment=\"has space\"\n",
        );
        assert!(
            out.contains("add name=wan ranges=2 comment=\"has space\""),
            "{}",
            out
        );
    }

    #[test]
    fn a_set_addresses_its_object_by_find() {
        let out = patch(
            "/ip pool\nadd name=lan ranges=1\n",
            "/ip pool\nadd name=lan ranges=2\n",
        );
        assert!(out.contains("set [find name=lan] ranges=2"), "{}", out);
    }

    #[test]
    fn a_comment_keyed_rule_is_anchored_and_moved() {
        let out = patch(
            "/ip firewall filter\nadd chain=input action=accept comment=a\nadd chain=input action=accept comment=b\n",
            "/ip firewall filter\nadd chain=input action=accept comment=b\nadd chain=input action=accept comment=a\n",
        );
        assert!(
            out.contains("move [find comment=b] destination=0"),
            "{}",
            out
        );
    }

    #[test]
    fn an_empty_diff_says_so() {
        let out = patch(
            "/ip pool\nadd name=a ranges=1\n",
            "/ip pool\nadd name=a ranges=1\n",
        );
        assert!(out.contains("nothing to do"), "{}", out);
    }

    #[test]
    fn a_quoted_comment_is_quoted_in_the_selector() {
        let out = patch(
            "/ip firewall filter\nadd chain=input action=accept comment=keep\n",
            "/ip firewall filter\nadd chain=input action=accept comment=\"a b\"\nadd chain=input action=accept comment=keep\n",
        );
        assert!(
            out.contains(
                "add chain=input action=accept comment=\"a b\" place-before=[find comment=keep]"
            ),
            "{}",
            out
        );
    }
}
