//! Rendering.
//!
//! Two jobs, deliberately separate:
//!
//! * [`document`] reproduces the parsed file byte for byte, by concatenating
//!   the stored source text of each item. This is the round-trip check.
//! * [`command`] renders a command from its tokens. A patch uses it only for
//!   lines it synthesises; for the arguments it takes from the target document
//!   it prints those arguments' own source text, so quoting and escaping are
//!   never re-derived.

use super::ast::{Command, Document};
use super::lexer::spell;

/// Reproduce the document's source text exactly.
pub fn document(doc: &Document) -> String {
    let mut out = String::new();
    for item in &doc.items {
        out.push_str(item.raw());
    }
    out
}

/// Render a command from its tokens: `verb selector args…`.
pub fn command(cmd: &Command) -> String {
    let mut parts: Vec<String> = Vec::with_capacity(2 + cmd.args.len() + cmd.extra.len());
    parts.push(cmd.verb.clone());
    if let Some(sel) = &cmd.selector {
        parts.push(sel.raw.clone());
    }
    for tok in &cmd.extra {
        parts.push(tok.raw.clone());
    }
    for arg in &cmd.args {
        parts.push(arg.raw.clone());
    }
    parts.join(" ")
}

/// Render a `find` selector from key/value pairs, quoting where needed.
pub fn find_expr(pairs: &[(String, String)]) -> String {
    let body: Vec<String> = pairs
        .iter()
        .map(|(k, v)| format!("{}={}", k, spell(v)))
        .collect();
    format!("[find {}]", body.join(" "))
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::syntax::ast::Item;
    use crate::syntax::parser::parse;

    /// Re-rendering each command from its tokens must reproduce the logical
    /// line. This is the test that the lexer and the printer agree; the byte
    /// round trip alone would pass even if both were broken in the same way.
    #[test]
    fn commands_re_render_from_their_tokens() {
        let cases = [
            "add chain=input action=drop comment=\"a b\"",
            "set [find name=x] mtu=9000",
            "set api disabled=yes",
            "add public-key=\"k9ZR/a+g=\" name=peer",
            "remove [find comment=\"managed:drop\"]",
        ];
        for case in cases {
            let doc = parse(&format!("{}\n", case)).unwrap();
            let Item::Command(cmd) = &doc.items[0] else {
                panic!("not a command: {}", case)
            };
            assert_eq!(command(cmd), case);
        }
    }

    #[test]
    fn a_find_expression_quotes_where_needed() {
        let expr = find_expr(&[("comment".into(), "managed:drop rest".into())]);
        assert_eq!(expr, "[find comment=\"managed:drop rest\"]");
    }
}
