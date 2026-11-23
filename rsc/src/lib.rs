//! A parser, differ and patch generator for MikroTik RouterOS `.rsc` scripts.
//!
//! The crate is layered so that each layer answers one question:
//!
//! * [`syntax`] — what bytes are in the file? A lexer, a line-oriented parser
//!   and an AST that keeps the source text of every item, so anything the tool
//!   does not understand is preserved verbatim.
//! * [`model`] — what configuration does the file describe? Menus become
//!   sections, `add`/`set` lines become objects with a property map.
//! * [`identity`] — which object is which? RouterOS has no portable ids, so a
//!   menu-aware table picks the properties that identify an object in it.
//! * [`diff`] — what changed between two files, as operations a device can be
//!   asked to perform.
//! * [`patch`] — how those operations are spelled as a `.rsc` script.
//! * [`simulate`] — applying the patch to the *model* of the first file must
//!   yield the model of the second. That is the correctness property this
//!   crate is built around, and it is checked in tests and by `rsc verify`.
//!
//! See `README.md` for what RouterOS does and does not let a patch express.

pub mod diff;
pub mod identity;
pub mod model;
pub mod patch;
pub mod simulate;
pub mod syntax;

pub use diff::{Diff, Options, Strategy};
pub use model::{Config, Object, Prop, Section, SectionKind, Selector};
pub use syntax::ast::Document;

/// Parse a script into a document. The error carries a line number and column.
pub fn parse(src: &str) -> Result<Document, syntax::parser::ParseError> {
    syntax::parser::parse(src)
}

/// Parse a script and project it into the semantic configuration model.
pub fn parse_config(src: &str) -> Result<Config, syntax::parser::ParseError> {
    let doc = parse(src)?;
    Ok(model::build(&doc))
}
