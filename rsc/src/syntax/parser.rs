//! The parser: physical lines in, a [`Document`] out.
//!
//! RouterOS `/export` wraps long lines. There are two shapes in the wild and
//! both have to be joined before tokenising, because a value that starts on the
//! next line reads as an *argument name* to a naive tokeniser — the object then
//! silently loses that property and nothing errors:
//!
//! ```text
//! add ... name=\
//!     chr-deploy.lan
//! add ... policy=\
//!     ftp,reboot,read,write
//! ```
//!
//! A line ending in `\` continues; so does a line ending in `=` (a dangling `=`
//! cannot end a command, and older exports wrap that way). The continuation is
//! joined with a single space: RouterOS skips whitespace between tokens, and
//! whitespace after `=` is insignificant, so the joined line parses the same.

use super::ast::{Arg, Command, Document, Item};
use super::lexer::{tokenize, Tok, TokKind};
use std::fmt;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ParseError {
    /// 1-based physical line.
    pub line: usize,
    pub message: String,
}

impl fmt::Display for ParseError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "line {}: {}", self.line, self.message)
    }
}

impl std::error::Error for ParseError {}

/// Verbs that may follow a menu path on the same line (`/ip address print`,
/// `/system reboot`) and that introduce a command on their own line.
///
/// The list is used to decide where a menu path ends, so it deliberately holds
/// command words only — a menu whose last word happens to be one of these is
/// not reachable as a header, and none of RouterOS' menus are.
const VERBS: &[&str] = &[
    "add",
    "set",
    "remove",
    "move",
    "enable",
    "disable",
    "print",
    "export",
    "edit",
    "find",
    "get",
    "comment",
    "reset",
    "renew",
    "release",
    "reboot",
    "shutdown",
    "backup",
    "save",
    "restore",
    "upgrade",
    "check-for-updates",
    "make-dynamic",
    "make-static",
    "monitor",
    "sniff",
    "fetch",
    "send",
    "flush",
    "clear",
];

fn is_verb(word: &str) -> bool {
    VERBS.contains(&word)
}

/// A logical line: several physical lines joined, with the original text kept.
#[derive(Debug, Clone)]
struct Logical {
    /// The joined text, continuations replaced by a single space.
    text: String,
    /// The physical lines exactly as they appeared, terminators included.
    raw: String,
    /// 1-based physical line the logical line starts on.
    line: usize,
}

fn ends_with_unescaped_backslash(s: &str) -> bool {
    let n = s.chars().rev().take_while(|c| *c == '\\').count();
    n % 2 == 1
}

/// Join continuation lines.
fn logical_lines(src: &str) -> Vec<Logical> {
    let mut out = Vec::new();
    let mut text = String::new();
    let mut raw = String::new();
    let mut start = 1usize;
    let mut open = false;

    for (idx, phys) in src.split_inclusive('\n').enumerate() {
        let line_no = idx + 1;
        let content = phys.trim_end_matches('\n').trim_end_matches('\r');

        if !open {
            text.clear();
            raw.clear();
            start = line_no;
        }
        raw.push_str(phys);

        let trimmed = content.trim_end();
        let comment = trimmed.trim_start().starts_with('#');
        let backslash = !comment && ends_with_unescaped_backslash(trimmed);
        let dangling_eq = !comment && trimmed.ends_with('=') && !trimmed.ends_with("==");

        if backslash {
            let without = &trimmed[..trimmed.len() - 1];
            if !text.is_empty() {
                text.push(' ');
            }
            text.push_str(without.trim_end());
            open = true;
            continue;
        }
        if dangling_eq {
            if !text.is_empty() {
                text.push(' ');
            }
            text.push_str(trimmed);
            open = true;
            continue;
        }

        if !text.is_empty() {
            text.push(' ');
        }
        text.push_str(content);
        out.push(Logical {
            text: text.clone(),
            raw: raw.clone(),
            line: start,
        });
        open = false;
    }

    if open {
        out.push(Logical {
            text: text.clone(),
            raw: raw.clone(),
            line: start,
        });
    }
    out
}

/// Parse a script.
pub fn parse(src: &str) -> Result<Document, ParseError> {
    let mut items = Vec::new();

    for logical in logical_lines(src) {
        let item = classify(&logical)?;
        items.push(item);
    }

    Ok(Document { items })
}

fn classify(logical: &Logical) -> Result<Item, ParseError> {
    let text = logical.text.trim_end();
    let t = text.trim_start();

    if t.is_empty() {
        return Ok(Item::Blank {
            raw: logical.raw.clone(),
        });
    }

    if let Some(rest) = t.strip_prefix('#') {
        return Ok(Item::Comment {
            text: rest.trim().to_string(),
            raw: logical.raw.clone(),
        });
    }

    // A script statement: `:local x 1`, `:if (...) do={...}`, `:foreach ...`.
    if t.starts_with(':') {
        return Ok(Item::Script {
            raw: logical.raw.clone(),
        });
    }

    let toks = tokenize(t).map_err(|e| ParseError {
        line: logical.line,
        message: e.to_string(),
    })?;

    if toks.is_empty() {
        return Ok(Item::Blank {
            raw: logical.raw.clone(),
        });
    }

    let first = &toks[0];

    if first.raw.starts_with('/') {
        // `/ip firewall filter` is a header; `/ip address add ...` is a header
        // and a command; `/system reboot` is a path and a verb.
        let verb_idx = (1..toks.len())
            .rev()
            .find(|&i| toks[i].kind == TokKind::Bare && is_verb(&toks[i].raw));

        return match verb_idx {
            Some(i) => {
                let path = path_of(&toks[..i]);
                let cmd = command_from(&toks[i..], &logical.raw, logical.line);
                // A command with no path (`/import file=…`) is a script line.
                if path.is_empty() {
                    return Ok(Item::Script {
                        raw: logical.raw.clone(),
                    });
                }
                Ok(Item::Command(Command {
                    path: Some(path),
                    ..cmd
                }))
            }
            None => {
                // `/import file-name=x.rsc`: a command at the root, not a menu
                // with an argument in its path.
                if toks.iter().any(|t| t.is_pair()) {
                    return Ok(Item::Script {
                        raw: logical.raw.clone(),
                    });
                }
                Ok(Item::Section {
                    path: path_of(&toks),
                    raw: logical.raw.clone(),
                })
            }
        };
    }

    if is_verb(&first.raw) {
        return Ok(Item::Command(command_from(
            &toks,
            &logical.raw,
            logical.line,
        )));
    }

    Ok(Item::Script {
        raw: logical.raw.clone(),
    })
}

fn path_of(toks: &[Tok]) -> Vec<String> {
    toks.iter()
        .map(|t| t.raw.trim_start_matches('/').to_string())
        .filter(|s| !s.is_empty())
        .collect()
}

fn command_from(toks: &[Tok], raw: &str, line: usize) -> Command {
    let verb = toks[0].raw.clone();
    let mut selector = None;
    let mut args = Vec::new();
    let mut extra = Vec::new();

    for tok in &toks[1..] {
        match tok.kind {
            TokKind::Pair => args.push(Arg {
                key: tok.key.clone(),
                value: tok
                    .value
                    .clone()
                    .unwrap_or_else(crate::syntax::lexer::Value::empty),
                raw: tok.raw.clone(),
            }),
            TokKind::Bare => {
                if selector.is_none() {
                    selector = Some(tok.clone());
                } else {
                    extra.push(tok.clone());
                }
            }
        }
    }

    Command {
        path: None,
        verb,
        selector,
        args,
        extra,
        raw: raw.to_string(),
        line,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn joins_a_backslash_continuation() {
        let src = "add name=\\\n    chr-deploy.lan\n";
        let doc = parse(src).unwrap();
        assert_eq!(doc.items.len(), 1);
        let Item::Command(cmd) = &doc.items[0] else {
            panic!("not a command: {:?}", doc.items[0])
        };
        assert_eq!(cmd.arg("name").unwrap().text, "chr-deploy.lan");
        // The source text, continuations included, is preserved for printing.
        assert_eq!(cmd.raw, "add name=\\\n    chr-deploy.lan\n");
    }

    #[test]
    fn joins_a_dangling_equals_continuation() {
        let src = "set public-key=\n    \"abc=\"\n";
        let doc = parse(src).unwrap();
        let Item::Command(cmd) = &doc.items[0] else {
            panic!("not a command")
        };
        assert_eq!(cmd.arg("public-key").unwrap().text, "abc=");
    }

    #[test]
    fn a_header_and_an_inline_command_split() {
        let doc = parse("/ip address add address=10.0.0.1/24 interface=ether1\n").unwrap();
        let Item::Command(cmd) = &doc.items[0] else {
            panic!("not a command")
        };
        assert_eq!(cmd.path.as_ref().unwrap().join(" "), "ip address");
        assert_eq!(cmd.verb, "add");
        assert_eq!(cmd.arg("address").unwrap().text, "10.0.0.1/24");
    }

    #[test]
    fn a_path_only_line_is_a_section() {
        let doc = parse("/ip firewall filter\n").unwrap();
        let Item::Section { path, .. } = &doc.items[0] else {
            panic!("not a section")
        };
        assert_eq!(path.join(" "), "ip firewall filter");
    }

    #[test]
    fn a_set_keeps_its_selector() {
        let doc = parse("/ip service\nset api disabled=yes\n").unwrap();
        let Item::Command(cmd) = &doc.items[1] else {
            panic!("not a command")
        };
        assert_eq!(cmd.selector.as_ref().unwrap().raw, "api");
        assert_eq!(cmd.arg("disabled").unwrap().text, "yes");
    }

    #[test]
    fn a_bare_bracket_selector_is_one_selector() {
        let doc = parse("set [ find default-name=ether1 ] mtu=9000\n").unwrap();
        let Item::Command(cmd) = &doc.items[0] else {
            panic!("not a command")
        };
        assert_eq!(
            cmd.selector.as_ref().unwrap().raw,
            "[ find default-name=ether1 ]"
        );
        assert_eq!(cmd.args.len(), 1);
    }

    #[test]
    fn script_statements_are_kept_verbatim() {
        for line in [
            ":local x 1\n",
            ":if ($a = 1) do={ :put \"y\" }\n",
            "/import file-name=x.rsc\n",
            "some bare words\n",
        ] {
            let doc = parse(line).unwrap();
            assert!(
                matches!(doc.items[0], Item::Script { .. }),
                "{} classified as {:?}",
                line.trim(),
                doc.items[0]
            );
            assert_eq!(doc.items[0].raw(), line);
        }
    }

    #[test]
    fn a_comment_is_not_a_command() {
        let doc = parse("# add action=accept\n").unwrap();
        let Item::Comment { text, .. } = &doc.items[0] else {
            panic!("not a comment")
        };
        assert_eq!(text, "add action=accept");
    }
}
