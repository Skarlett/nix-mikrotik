//! The lexical layer: one logical line in, a flat list of tokens out.
//!
//! RouterOS script tokens are separated by whitespace, except that a value may
//! be quoted (then it may contain anything) or bracketed (then it may contain
//! whitespace). A token is either a bare word — a selector, a variable, a
//! bracketed expression — or a `key=value` pair.
//!
//! Two details are easy to get wrong and both are load-bearing here:
//!
//! * `/export` wraps long lines after a `\`, and sometimes after the `=` of a
//!   value. The line joining happens in [`super::parser`]; the lexer only ever
//!   sees a line that has already been joined, so a wrapped `public-key=\n
//!   "abc…="` arrives as `public-key= "abc…="` and the whitespace after `=`
//!   is insignificant.
//! * An `=` inside a bracket expression is part of the expression, not a
//!   `key=value` separator, so the scan tracks bracket depth.

use std::fmt;

/// A token's value, kept in both its written and its decoded form.
///
/// `raw` is what has to be printed to reproduce the source byte for byte;
/// `text` is what the device will actually store, and is what comparisons use.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Value {
    /// The value exactly as written, including any surrounding quotes.
    pub raw: String,
    /// The decoded value: quotes removed, escapes resolved.
    pub text: String,
    /// Whether the source wrote the value inside double quotes.
    pub quoted: bool,
}

impl Value {
    /// Decode a value from its written form.
    pub fn parse(raw: &str) -> Value {
        if raw.len() >= 2 && raw.starts_with('"') && raw.ends_with('"') {
            Value {
                text: unescape(&raw[1..raw.len() - 1]),
                raw: raw.to_string(),
                quoted: true,
            }
        } else {
            Value {
                text: raw.to_string(),
                raw: raw.to_string(),
                quoted: false,
            }
        }
    }

    /// An empty value, as written by `key=`.
    pub fn empty() -> Value {
        Value {
            raw: String::new(),
            text: String::new(),
            quoted: false,
        }
    }

    /// How the value is spelled, which decides how it has to be re-spelled.
    pub fn kind(&self) -> ValueKind {
        let t = self.raw.trim();
        if t.is_empty() {
            ValueKind::Empty
        } else if t.starts_with('"') {
            ValueKind::Quoted
        } else if t.starts_with('[') {
            ValueKind::Bracket
        } else if t.starts_with('$') {
            ValueKind::Variable
        } else if t.starts_with("__MIKROTIK_SECRET_") {
            ValueKind::Placeholder
        } else {
            ValueKind::Bare
        }
    }
}

/// The spelling of a value. Used where a decision depends on how RouterOS will
/// read the text back (quoting, escaping) rather than on what it means.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ValueKind {
    Empty,
    Quoted,
    Bare,
    Bracket,
    Variable,
    Placeholder,
}

/// Resolve the escapes RouterOS understands inside a double-quoted value.
///
/// The renderer escapes exactly `\`, `"` and `$`; anything else after a
/// backslash is left as written rather than guessed at, because guessing would
/// make two spellings compare equal that the device treats differently.
pub fn unescape(s: &str) -> String {
    let mut out = String::with_capacity(s.len());
    let mut chars = s.chars();
    while let Some(c) = chars.next() {
        if c != '\\' {
            out.push(c);
            continue;
        }
        match chars.next() {
            Some('"') => out.push('"'),
            Some('\\') => out.push('\\'),
            Some('$') => out.push('$'),
            Some(other) => {
                out.push('\\');
                out.push(other);
            }
            None => out.push('\\'),
        }
    }
    out
}

/// The inverse of [`unescape`]: make a value safe to put between quotes.
pub fn escape(s: &str) -> String {
    let mut out = String::with_capacity(s.len());
    for c in s.chars() {
        match c {
            '\\' => out.push_str("\\\\"),
            '"' => out.push_str("\\\""),
            '$' => out.push_str("\\$"),
            other => out.push(other),
        }
    }
    out
}

/// Whether RouterOS would end the command on this value if it were bare.
///
/// Mirrors the renderer's rule (`lib/render.nix`): a space, `=`, `;`, `"`, `\`
/// or `$` has to be quoted. An empty value has to be quoted too, since a bare
/// `key=` and a `key=""` are read differently by a human even where the device
/// agrees.
pub fn needs_quote(s: &str) -> bool {
    s.is_empty()
        || s.chars()
            .any(|c| matches!(c, ' ' | '=' | ';' | '"' | '\\' | '$' | '\t'))
}

/// Spell a value the way `/export` does: bare where that parses, quoted where
/// it does not.
pub fn spell(text: &str) -> String {
    if needs_quote(text) {
        format!("\"{}\"", escape(text))
    } else {
        text.to_string()
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum TokKind {
    /// A bare token: a selector, a variable, or a bracketed expression.
    Bare,
    /// `key=value`.
    Pair,
}

/// One token of a logical line.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Tok {
    /// The token exactly as written, including quotes.
    pub raw: String,
    pub kind: TokKind,
    /// For a pair, the key as written.
    pub key: Option<String>,
    /// For a pair, the decoded value.
    pub value: Option<Value>,
    /// Byte offset of the token within the logical line.
    pub col: usize,
}

impl Tok {
    pub fn is_pair(&self) -> bool {
        self.kind == TokKind::Pair
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum LexError {
    UnterminatedQuote { col: usize },
    UnbalancedBracket { col: usize },
}

impl fmt::Display for LexError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            LexError::UnterminatedQuote { col } => {
                write!(f, "unterminated quote at column {}", col + 1)
            }
            LexError::UnbalancedBracket { col } => {
                write!(f, "unbalanced bracket at column {}", col + 1)
            }
        }
    }
}

/// Split one logical line into tokens.
pub fn tokenize(line: &str) -> Result<Vec<Tok>, LexError> {
    let b = line.as_bytes();
    let n = b.len();
    let mut toks = Vec::new();
    let mut i = 0usize;

    while i < n {
        while i < n && (b[i] == b' ' || b[i] == b'\t') {
            i += 1;
        }
        if i >= n {
            break;
        }
        let start = i;
        let mut depth = 0i32;
        let mut in_quote = false;
        let mut eq: Option<usize> = None;
        let mut vstart: Option<usize> = None;

        while i < n {
            let c = b[i];
            if in_quote {
                if c == b'\\' {
                    i += 2;
                    continue;
                }
                if c == b'"' {
                    in_quote = false;
                    i += 1;
                    continue;
                }
                i += 1;
                continue;
            }
            match c {
                b'"' => {
                    in_quote = true;
                    i += 1;
                }
                b'[' | b'(' | b'{' => {
                    depth += 1;
                    i += 1;
                }
                b']' | b')' | b'}' => {
                    depth -= 1;
                    i += 1;
                }
                b'=' if depth == 0 && eq.is_none() => {
                    eq = Some(i);
                    i += 1;
                }
                b' ' | b'\t' if depth == 0 => {
                    // Whitespace between `=` and its value is insignificant:
                    // `/export` wraps there, so `public-key=` and the value
                    // arrive on different lines and the join inserts a space.
                    if let Some(e) = eq {
                        if i == e + 1 {
                            while i < n && (b[i] == b' ' || b[i] == b'\t') {
                                i += 1;
                            }
                            vstart = Some(i);
                            continue;
                        }
                    }
                    break;
                }
                b'\\' => i += 2,
                _ => i += 1,
            }
        }

        if in_quote {
            return Err(LexError::UnterminatedQuote { col: start });
        }
        if depth != 0 {
            return Err(LexError::UnbalancedBracket { col: start });
        }

        let end = i.min(n);
        let raw = &line[start..end];

        match eq {
            Some(e) if e > start => {
                let key = &line[start..e];
                let vs = vstart.unwrap_or(e + 1);
                let vraw = &line[vs..end];
                // When the value started after skipped whitespace, the token's
                // text is normalised back to `key=value`: the spacing was the
                // join of a wrapped line, not something to carry around.
                let text = match vstart {
                    Some(_) => format!("{}={}", key, vraw),
                    None => raw.to_string(),
                };
                toks.push(Tok {
                    raw: text,
                    kind: TokKind::Pair,
                    key: Some(key.to_string()),
                    value: Some(Value::parse(vraw)),
                    col: start,
                });
            }
            _ => toks.push(Tok {
                raw: raw.to_string(),
                kind: TokKind::Bare,
                key: None,
                value: None,
                col: start,
            }),
        }
    }

    Ok(toks)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn raws(line: &str) -> Vec<String> {
        tokenize(line).unwrap().into_iter().map(|t| t.raw).collect()
    }

    #[test]
    fn splits_pairs_and_bare_tokens() {
        assert_eq!(
            raws("add chain=input action=drop comment=\"a b\""),
            vec!["add", "chain=input", "action=drop", "comment=\"a b\""]
        );
    }

    #[test]
    fn a_bracket_expression_is_one_token() {
        assert_eq!(
            raws("set [ find default-name=ether1 ] mtu=9000"),
            vec!["set", "[ find default-name=ether1 ]", "mtu=9000"]
        );
    }

    #[test]
    fn a_bracket_expression_may_contain_a_comparison() {
        let toks = tokenize("remove [find where comment~\"x y\"]").unwrap();
        assert_eq!(toks.len(), 2);
        assert_eq!(toks[1].kind, TokKind::Bare);
    }

    #[test]
    fn quoted_values_decode_escapes() {
        let toks = tokenize("add comment=\"chr\\\"deploy\\\\test\\$value\"").unwrap();
        assert_eq!(
            toks[1].value.as_ref().unwrap().text,
            "chr\"deploy\\test$value"
        );
        assert!(toks[1].value.as_ref().unwrap().quoted);
    }

    #[test]
    fn a_value_ending_in_padding_is_one_token() {
        let toks =
            tokenize("add public-key=\"k9ZRM5a4m4qYDVuZmbksipA/gJ82mBH3MvgZaJRWIAo=\"").unwrap();
        assert_eq!(toks.len(), 2);
        assert_eq!(
            toks[1].value.as_ref().unwrap().text,
            "k9ZRM5a4m4qYDVuZmbksipA/gJ82mBH3MvgZaJRWIAo="
        );
    }

    #[test]
    fn spelling_round_trips_through_the_lexer() {
        for text in [
            "plain",
            "has space",
            "a=b",
            "q\"uote",
            "back\\slash",
            "dollar$",
        ] {
            let spelled = spell(text);
            let toks = tokenize(&format!("k={}", spelled)).unwrap();
            assert_eq!(
                toks[0].value.as_ref().unwrap().text,
                text,
                "spelling {}",
                spelled
            );
        }
    }

    #[test]
    fn an_unterminated_quote_is_an_error() {
        assert!(matches!(
            tokenize("add comment=\"oops"),
            Err(LexError::UnterminatedQuote { .. })
        ));
    }
}
