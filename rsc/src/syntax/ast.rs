//! The document model: what a `.rsc` file is, line by line.
//!
//! Every item keeps the exact source text it came from (`raw`). That is what
//! makes the round trip byte-identical and what lets a patch reuse the *second*
//! file's own argument text instead of re-spelling values from a decoded form.
//! Re-spelling is how a tool silently changes `comment="a  b"` or drops the
//! quoting of a base64 key that ends in `=`.

use super::lexer::{Tok, Value};

/// A parsed script.
#[derive(Debug, Clone, Default)]
pub struct Document {
    pub items: Vec<Item>,
}

impl Document {
    /// Every section path in the order it first appears.
    pub fn section_paths(&self) -> Vec<Vec<String>> {
        let mut out: Vec<Vec<String>> = Vec::new();
        for item in &self.items {
            if let Item::Section { path, .. } = item {
                if !out.contains(path) {
                    out.push(path.clone());
                }
            }
        }
        out
    }

    /// Every command in the document, with the section it belongs to.
    pub fn commands(&self) -> Vec<(&[String], &Command)> {
        let mut out = Vec::new();
        let mut current: &[String] = &[];
        for item in &self.items {
            match item {
                Item::Section { path, .. } => current = path,
                Item::Command(cmd) => out.push((current, cmd)),
                _ => {}
            }
        }
        out
    }
}

/// One item of a script.
#[derive(Debug, Clone)]
pub enum Item {
    /// An empty line.
    Blank { raw: String },
    /// A `#` comment, with its text (the `#` stripped) and its source text.
    Comment { text: String, raw: String },
    /// A menu header, `/ip firewall filter`.
    Section { path: Vec<String>, raw: String },
    /// A command: `add`, `set`, `remove`, `move`, …
    Command(Command),
    /// Anything else — a `:local`, a `:if`, a `/import`, a bare word. Kept
    /// verbatim so that a script that is not an `/export` still round-trips.
    Script { raw: String },
}

impl Item {
    /// The item's source text, exactly as it appeared.
    pub fn raw(&self) -> &str {
        match self {
            Item::Blank { raw }
            | Item::Comment { raw, .. }
            | Item::Section { raw, .. }
            | Item::Script { raw } => raw,
            Item::Command(cmd) => &cmd.raw,
        }
    }
}

/// A menu command.
#[derive(Debug, Clone)]
pub struct Command {
    /// The menu path when the command was written on the header's own line
    /// (`/ip address add …`); `None` when it follows a header line.
    pub path: Option<Vec<String>>,
    /// The verb as written: `add`, `set`, `remove`, `move`, `print`, …
    pub verb: String,
    /// The bare token that selects the object(s) a `set`/`remove`/`move`
    /// applies to: `[find name=x]`, a bare name such as `api`, or an index.
    pub selector: Option<Tok>,
    /// `key=value` arguments, in written order.
    pub args: Vec<Arg>,
    /// Bare tokens after the selector that are not arguments (`move 1 2`).
    pub extra: Vec<Tok>,
    /// The logical line as written, continuations joined.
    pub raw: String,
    /// The command's own text, continuations joined: what the printer has to
    /// reproduce. For a command written on a header's line (`/ip address add
    /// …`) this starts at the verb, not at the path.
    pub text: String,
    /// The physical line the command starts on, 1-based.
    pub line: usize,
}

impl Command {
    /// The value of an argument, decoded.
    pub fn arg(&self, key: &str) -> Option<&Value> {
        self.args
            .iter()
            .find(|a| a.key.as_deref() == Some(key))
            .map(|a| &a.value)
    }
}

/// One `key=value` argument.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Arg {
    /// The key, or `None` for a positional argument.
    pub key: Option<String>,
    pub value: Value,
    /// The argument exactly as written, `key="value"` included.
    pub raw: String,
}

impl Arg {
    pub fn key_str(&self) -> &str {
        self.key.as_deref().unwrap_or("")
    }
}
