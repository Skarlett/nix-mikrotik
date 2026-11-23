//! Fidelity: the parser must not lose a byte of what it was given.
//!
//! Two checks, because they fail differently:
//!
//! * the byte round trip (`parse` then print must equal the input), which
//!   catches the parser dropping or reshuffling lines;
//! * re-rendering each command from its tokens, which catches a lexer and a
//!   printer that agree with each other but not with RouterOS.

use rsc::syntax::ast::Item;
use rsc::syntax::print;
use std::path::{Path, PathBuf};

fn manifest(rel: &str) -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR")).join(rel)
}

fn every_rsc() -> Vec<PathBuf> {
    let mut out = Vec::new();
    // This crate's own fixtures.
    for name in [
        "a.rsc",
        "b.rsc",
        "export-7.15.3.rsc",
        "wrapped-string.rsc",
        "block-script.rsc",
    ] {
        let p = manifest(&format!("tests/fixtures/{}", name));
        if p.exists() {
            out.push(p);
        }
    }
    // Everything the repository's renderer produces, which is the corpus that
    // has to keep parsing: the golden files and the fixtures used by the
    // deploy check.
    for rel in [
        "../tests/golden/legacy.rsc",
        "../tests/golden/legacy-upstream.rsc",
        "../tests/golden/networks.rsc",
        "../tests/fixtures/refused.rsc",
    ] {
        let p = manifest(rel);
        if p.exists() {
            out.push(p);
        }
    }
    out
}

#[test]
fn every_script_round_trips_byte_for_byte() {
    let files = every_rsc();
    assert!(files.len() >= 4, "expected a corpus, found {:?}", files);
    for path in files {
        let src = std::fs::read_to_string(&path).unwrap();
        let doc = rsc::parse(&src).unwrap_or_else(|e| panic!("{}: {}", path.display(), e));
        let out = print::document(&doc);
        assert_eq!(out, src, "{} did not round trip", path.display());
    }
}

#[test]
fn every_command_re_renders_from_its_tokens() {
    use rsc::syntax::lexer::tokenize;

    for path in every_rsc() {
        let src = std::fs::read_to_string(&path).unwrap();
        let doc = rsc::parse(&src).unwrap();
        for item in &doc.items {
            if let Item::Command(cmd) = item {
                // Compare token by token rather than character by character:
                // a wrapped line joins with whitespace between tokens and with
                // nothing inside a string, and the printer drops the space
                // after `=`, all of which the lexer reads the same way.
                let want: Vec<(bool, Option<String>, String)> = tokenize(&cmd.text)
                    .unwrap()
                    .into_iter()
                    .map(|t| {
                        (
                            t.is_pair(),
                            t.key.clone(),
                            t.value.map(|v| v.text).unwrap_or_default(),
                        )
                    })
                    .collect();
                let got: Vec<(bool, Option<String>, String)> = tokenize(&print::command(cmd))
                    .unwrap()
                    .into_iter()
                    .map(|t| {
                        (
                            t.is_pair(),
                            t.key.clone(),
                            t.value.map(|v| v.text).unwrap_or_default(),
                        )
                    })
                    .collect();
                assert_eq!(got, want, "{}: command re-render differs", path.display());
            }
        }
    }
}

#[test]
fn a_wrapped_value_is_joined_not_truncated() {
    let src = std::fs::read_to_string(manifest("tests/fixtures/export-7.15.3.rsc")).unwrap();
    let cfg = rsc::parse_config(&src).unwrap();
    let dns = cfg.section("ip dns static").expect("ip dns static");
    assert_eq!(dns.objects.len(), 1);
    // The real export wraps `name=` onto the next line and carries escaped
    // `"`, `\` and `$` in the comment.
    let obj = &dns.objects[0];
    let name = obj.props.iter().find(|p| p.key == "name").unwrap();
    assert_eq!(name.value.text, "chr-deploy.lan");
    let comment = obj.props.iter().find(|p| p.key == "comment").unwrap();
    assert_eq!(comment.value.text, "chr\"deploy\\test$value");
}

/// A continuation *inside* a quoted string is not a token continuation: the
/// backslash and the indentation RouterOS puts after it are not content. A
/// `/system script` with a wrapped `source="…"` is the case that matters, and
/// getting it wrong inserts a space per line into the script body, which the
/// device then stores.
#[test]
fn a_continuation_inside_a_string_adds_nothing() {
    let src = std::fs::read_to_string(manifest("tests/fixtures/wrapped-string.rsc")).unwrap();
    let cfg = rsc::parse_config(&src).unwrap();
    let script = cfg.section("system script").expect("system script");
    assert_eq!(script.objects.len(), 1);
    let source = script.objects[0]
        .props
        .iter()
        .find(|p| p.key == "source")
        .expect("source");

    assert!(
        source
            .value
            .text
            .starts_with("\\n:local url \"https://example.invalid/"),
        "the value starts with {:?}",
        &source.value.text[..40.min(source.value.text.len())]
    );
    // No indentation and no injected separator before a line break.
    assert!(
        !source.value.text.contains(" \\n"),
        "{:?}",
        source.value.text
    );
    assert!(
        source
            .value
            .text
            .contains("\\n:local interface \"luninet-clients\""),
        "{:?}",
        source.value.text
    );
    // The wrapped `policy=` argument is still two arguments, not one value.
    let policy = script.objects[0]
        .props
        .iter()
        .find(|p| p.key == "policy")
        .expect("policy");
    assert_eq!(policy.value.text, "read,write,test");
}

#[test]
fn a_script_with_a_positional_selector_parses() {
    let src = "/port\nset 0 name=serial0\n";
    let cfg = rsc::parse_config(src).unwrap();
    let port = cfg.section("port").unwrap();
    assert_eq!(port.objects.len(), 1);
    assert_eq!(port.objects[0].selector.to_string(), "#0");
}

/// A script that addresses a menu with a block is still a file the tool has to
/// read: `/interface { wireguard { add … } }` is how RouterOS lets a script
/// choose a menu by variable. What such a line adds is not a configuration, so
/// the block is kept verbatim — but refusing the file, which an unclosed `{` in
/// a tokeniser does, means the tool cannot be pointed at half the fleet's
/// scripts.
#[test]
fn a_script_that_addresses_menus_with_blocks_is_kept_verbatim() {
    let src = std::fs::read_to_string(manifest("tests/fixtures/block-script.rsc")).unwrap();
    let doc = rsc::parse(&src).expect("a block-form script must parse");
    assert_eq!(
        rsc::syntax::print::document(&doc),
        src,
        "the block script did not round trip"
    );

    // The block body is unmodelled: no `/interface` section was invented from
    // it, and the `add name=$IFNAME` inside it is not an object.
    let cfg = rsc::parse_config(&src).unwrap();
    assert!(
        cfg.section("interface").is_none(),
        "the block form was read as a menu"
    );
    assert!(cfg.section("interface wireguard").is_none());

    // The top-level commands after the loop are real, and are modelled.
    let option = cfg
        .section("ip dhcp-server option")
        .expect("ip dhcp-server option");
    assert_eq!(option.objects.len(), 1);
    assert_eq!(
        option.objects[0]
            .props
            .iter()
            .find(|p| p.key == "code")
            .unwrap()
            .value
            .text,
        "121"
    );
}

#[test]
fn unparsable_input_is_an_error_not_a_panic() {
    let err = rsc::parse("add comment=\"unterminated\n").unwrap_err();
    assert_eq!(err.line, 1);
    assert!(err.to_string().contains("unterminated quote"), "{}", err);
}
