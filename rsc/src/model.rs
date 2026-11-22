//! The semantic layer: a script projected into the configuration it describes.
//!
//! A `.rsc` export is a flat list of menu headers and commands. This module
//! folds that into `section → object → property`, which is the shape a diff can
//! work on:
//!
//! * `add k=v …` creates an object.
//! * `set [find …] k=v` / `set <name> k=v` modifies the object the selector
//!   addresses, creating it in the model if the export started from a default
//!   object (an ethernet port is written that way).
//! * `set k=v` with no selector at all is a *singleton* menu: `/ip dns`,
//!   `/system identity`. There is exactly one object and it always exists.
//!
//! Anything else — `remove`, `move`, `print`, `:local`, `/import` — is kept as
//! an extra line and reported rather than interpreted: a file that removes
//! things is a script, not a state, and this model describes states.

use crate::identity;
use crate::syntax::ast::{Arg, Command, Document, Item};
use crate::syntax::lexer::Value;
use std::fmt;

/// A configuration: the sections a script declares.
#[derive(Debug, Clone, Default)]
pub struct Config {
    pub sections: Vec<Section>,
    /// Lines that appear before any section header.
    pub preamble: Vec<String>,
}

/// A menu and the objects it holds.
#[derive(Debug, Clone)]
pub struct Section {
    /// The menu path as written without the leading slash: `ip firewall filter`.
    pub path: String,
    pub kind: SectionKind,
    pub objects: Vec<Object>,
    /// Lines under this header that the model does not interpret.
    pub extras: Vec<String>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SectionKind {
    /// A list of objects.
    Objects,
    /// One settings object, addressed by `set k=v` with no selector.
    Singleton,
    /// A menu whose lines could not be modelled.
    Unmodelled,
}

/// One object of a menu.
#[derive(Debug, Clone)]
pub struct Object {
    pub selector: Selector,
    pub props: Vec<Prop>,
    /// 1-based line the object was first described on.
    pub line: usize,
    pub origin: Origin,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Origin {
    /// Created by an `add`.
    Add,
    /// Described by a `set` on an object the export assumed to exist.
    Set,
}

/// One property of an object.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Prop {
    pub key: String,
    pub value: Value,
    /// The property exactly as written, `key="value"` included. Patches print
    /// this rather than re-spelling the decoded value.
    pub raw: String,
}

impl Prop {
    pub fn new(key: &str, value: Value) -> Prop {
        let raw = format!("{}={}", key, value.raw);
        Prop {
            key: key.to_string(),
            value,
            raw,
        }
    }

    /// A property reset to its default by writing an empty string.
    ///
    /// This is only used for properties where it is *measured* to work: a
    /// string-valued property whose default is empty. RouterOS has no general
    /// `unset`, so for anything else the object has to be re-created.
    pub fn cleared(key: &str) -> Prop {
        Prop {
            key: key.to_string(),
            value: Value {
                raw: "\"\"".to_string(),
                text: String::new(),
                quoted: true,
            },
            raw: format!("{}=\"\"", key),
        }
    }

    pub fn from_arg(a: &Arg) -> Option<Prop> {
        a.key.as_ref().map(|k| Prop {
            key: k.clone(),
            value: a.value.clone(),
            raw: a.raw.clone(),
        })
    }
}

impl fmt::Display for Prop {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(&self.raw)
    }
}

/// How an object is addressed.
#[derive(Debug, Clone, PartialEq, Eq, PartialOrd, Ord, Hash)]
pub enum Selector {
    /// The single settings object of a singleton menu.
    Singleton,
    /// Addressed by name.
    Named(String),
    /// Addressed by comment — the only stable handle an ordered menu offers.
    Comment(String),
    /// Addressed by a `find` expression over these properties.
    Find(Vec<(String, String)>),
    /// Addressed by position, for a menu with no other handle.
    Index(usize),
    /// A selector the model could not reduce to properties.
    Expr(String),
}

impl Selector {
    /// A canonical string, used to compare selectors and to key maps.
    pub fn key(&self) -> String {
        match self {
            Selector::Singleton => "@singleton".to_string(),
            Selector::Named(n) => format!("name={}", n),
            Selector::Comment(c) => format!("comment={}", c),
            Selector::Find(pairs) => {
                let body: Vec<String> = pairs.iter().map(|(k, v)| format!("{}={}", k, v)).collect();
                body.join(",")
            }
            Selector::Index(i) => format!("#{}", i),
            Selector::Expr(e) => format!("expr:{}", e),
        }
    }

    /// The `find` pairs this selector addresses, if it has any.
    pub fn pairs(&self) -> Vec<(String, String)> {
        match self {
            Selector::Named(n) => vec![("name".to_string(), n.clone())],
            Selector::Comment(c) => vec![("comment".to_string(), c.clone())],
            Selector::Find(pairs) => pairs.clone(),
            _ => Vec::new(),
        }
    }

    /// Whether the selector addresses an object by position, which is only
    /// stable while nothing else in the menu moves.
    pub fn is_positional(&self) -> bool {
        matches!(self, Selector::Index(_))
    }
}

impl fmt::Display for Selector {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Selector::Singleton => f.write_str("@singleton"),
            Selector::Named(n) => write!(f, "name={}", n),
            Selector::Comment(c) => write!(f, "comment={}", c),
            Selector::Find(pairs) => {
                let body: Vec<String> = pairs.iter().map(|(k, v)| format!("{}={}", k, v)).collect();
                f.write_str(&body.join(" "))
            }
            Selector::Index(i) => write!(f, "#{}", i),
            Selector::Expr(e) => f.write_str(e),
        }
    }
}

impl Config {
    pub fn section(&self, path: &str) -> Option<&Section> {
        self.sections.iter().find(|s| s.path == path)
    }

    pub fn section_mut(&mut self, path: &str) -> Option<&mut Section> {
        self.sections.iter_mut().find(|s| s.path == path)
    }

    /// Every section path, in order.
    pub fn paths(&self) -> Vec<&str> {
        self.sections.iter().map(|s| s.path.as_str()).collect()
    }
}

impl Section {
    pub fn object(&self, sel: &Selector) -> Option<&Object> {
        let key = sel.key();
        self.objects.iter().find(|o| o.selector.key() == key)
    }

    pub fn object_mut(&mut self, sel: &Selector) -> Option<&mut Object> {
        let key = sel.key();
        self.objects.iter_mut().find(|o| o.selector.key() == key)
    }

    pub fn has_comment_everywhere(&self) -> bool {
        !self.objects.is_empty()
            && self.objects.iter().all(|o| {
                o.props
                    .iter()
                    .any(|p| p.key == "comment" && !p.value.text.is_empty())
            })
    }

    pub fn comment_of(&self, obj: &Object) -> Option<String> {
        obj.props
            .iter()
            .find(|p| p.key == "comment")
            .map(|p| p.value.text.clone())
            .filter(|c| !c.is_empty())
    }
}

/// Build the configuration model from a parsed document.
pub fn build(doc: &Document) -> Config {
    let mut cfg = Config::default();
    let mut current: Option<usize> = None;

    for item in &doc.items {
        match item {
            Item::Section { path, .. } => {
                current = Some(ensure_section(&mut cfg, &path.join(" ")));
            }
            Item::Command(cmd) => {
                let path = match (&cmd.path, current) {
                    (Some(p), _) => {
                        let joined = p.join(" ");
                        Some(ensure_section(&mut cfg, &joined))
                    }
                    (None, Some(i)) => Some(i),
                    (None, None) => None,
                };
                match path {
                    Some(idx) => apply_command(&mut cfg.sections[idx], cmd),
                    None => cfg.preamble.push(cmd.raw.trim_end().to_string()),
                }
            }
            Item::Script { raw } => {
                let line = raw.trim_end().to_string();
                match current {
                    Some(i) => cfg.sections[i].extras.push(line),
                    None => cfg.preamble.push(line),
                }
            }
            Item::Comment { .. } | Item::Blank { .. } => {}
        }
    }

    for section in &mut cfg.sections {
        if section.objects.is_empty() && !section.extras.is_empty() {
            section.kind = SectionKind::Unmodelled;
        }
    }

    cfg
}

fn ensure_section(cfg: &mut Config, path: &str) -> usize {
    if let Some(i) = cfg.sections.iter().position(|s| s.path == path) {
        return i;
    }
    cfg.sections.push(Section {
        path: path.to_string(),
        kind: SectionKind::Objects,
        objects: Vec::new(),
        extras: Vec::new(),
    });
    cfg.sections.len() - 1
}

fn props_of(cmd: &Command) -> Vec<Prop> {
    cmd.args.iter().filter_map(Prop::from_arg).collect()
}

fn apply_command(section: &mut Section, cmd: &Command) {
    match cmd.verb.as_str() {
        "add" => {
            let props = props_of(cmd);
            let index = section.objects.len();
            let selector = identity::selector_from_props(&section.path, &props, index);
            section.objects.push(Object {
                selector,
                props,
                line: cmd.line,
                origin: Origin::Add,
            });
        }
        "set" => match &cmd.selector {
            Some(tok) => {
                let sel = identity::selector_from_tok(tok);
                let props = props_of(cmd);
                match section.object_mut(&sel) {
                    Some(obj) => merge_props(&mut obj.props, props),
                    None => section.objects.push(Object {
                        selector: sel,
                        props,
                        line: cmd.line,
                        origin: Origin::Set,
                    }),
                }
            }
            None => {
                // A `set` with no selector is the menu's single settings object.
                section.kind = SectionKind::Singleton;
                let props = props_of(cmd);
                match section.object_mut(&Selector::Singleton) {
                    Some(obj) => merge_props(&mut obj.props, props),
                    None => section.objects.push(Object {
                        selector: Selector::Singleton,
                        props,
                        line: cmd.line,
                        origin: Origin::Set,
                    }),
                }
            }
        },
        // A state export contains no removes or moves; a script that does is
        // kept as text so that nothing is silently dropped.
        _ => section.extras.push(cmd.raw.trim_end().to_string()),
    }
}

fn merge_props(into: &mut Vec<Prop>, new: Vec<Prop>) {
    for p in new {
        match into.iter_mut().find(|e| e.key == p.key) {
            Some(slot) => *slot = p,
            None => into.push(p),
        }
    }
}

/// A property's decoded value, if present.
pub fn prop_text<'a>(props: &'a [Prop], key: &str) -> Option<&'a str> {
    props
        .iter()
        .find(|p| p.key == key)
        .map(|p| p.value.text.as_str())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::parse;

    #[test]
    fn adds_become_objects_with_selectors() {
        let cfg = parse_config(
            "/ip pool\nadd name=lan ranges=10.0.0.10-10.0.0.20\nadd name=wan ranges=10.1.0.10-10.1.0.20\n",
        );
        let s = cfg.section("ip pool").unwrap();
        assert_eq!(s.objects.len(), 2);
        assert_eq!(s.objects[0].selector, Selector::Named("lan".into()));
        assert_eq!(s.objects[1].selector, Selector::Named("wan".into()));
    }

    #[test]
    fn a_set_without_a_selector_is_a_singleton() {
        let cfg = parse_config("/ip dns\nset servers=1.1.1.1\n");
        let s = cfg.section("ip dns").unwrap();
        assert_eq!(s.kind, SectionKind::Singleton);
        assert_eq!(prop_text(&s.objects[0].props, "servers"), Some("1.1.1.1"));
    }

    #[test]
    fn a_set_with_a_selector_creates_the_object_it_addresses() {
        let cfg = parse_config("/interface ethernet\nset [ find default-name=ether1 ] mtu=9000\n");
        let s = cfg.section("interface ethernet").unwrap();
        assert_eq!(s.kind, SectionKind::Objects);
        assert_eq!(
            s.objects[0].selector,
            Selector::Find(vec![("name".into(), "ether1".into())])
        );
        assert_eq!(prop_text(&s.objects[0].props, "mtu"), Some("9000"));
    }

    #[test]
    fn two_sets_on_one_object_merge() {
        let cfg = parse_config("/ip service\nset api disabled=yes\nset api port=8728\n");
        let s = cfg.section("ip service").unwrap();
        assert_eq!(s.objects.len(), 1);
        assert_eq!(prop_text(&s.objects[0].props, "disabled"), Some("yes"));
        assert_eq!(prop_text(&s.objects[0].props, "port"), Some("8728"));
    }

    #[test]
    fn a_repeated_section_merges() {
        let cfg = parse_config(
            "/ip pool\nadd name=a ranges=1\n/ip address\n/ip pool\nadd name=b ranges=2\n",
        );
        let s = cfg.section("ip pool").unwrap();
        assert_eq!(s.objects.len(), 2);
    }

    #[test]
    fn an_inline_command_knows_its_section() {
        let cfg = parse_config("/ip address add address=10.0.0.1/24 interface=ether1\n");
        let s = cfg.section("ip address").unwrap();
        assert_eq!(s.objects.len(), 1);
    }

    #[test]
    fn uninterpreted_lines_are_kept() {
        let cfg = parse_config("/ip firewall filter\nremove [find comment=x]\n:local a 1\n");
        let s = cfg.section("ip firewall filter").unwrap();
        assert_eq!(s.extras.len(), 2);
    }

    fn parse_config(src: &str) -> Config {
        super::build(&parse(src).unwrap())
    }
}
