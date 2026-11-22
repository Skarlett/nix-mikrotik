//! Dogfood: the differ over the configurations this repository actually
//! produces, not only over fixtures written for the differ.
//!
//! `tests/fixtures/rendered/` holds the output of the renderer's own packages —
//! `nix build .#mikrotik-example-script` and friends — copied verbatim, plus the
//! real `/export` of a CHR 7.15.3. Every ordered pair of those files is run
//! through the whole pipeline, which is how the strategies meet shapes nobody
//! wrote a test for: a typed menu tree, upstream's wrapped legacy example, the
//! CHR fixture, and a device export with `set [ find default-name=… ]` and
//! `set 0 name=serial0` in it.
//!
//! The rule for a pair: if the diff claims it is exact, applying it must reach
//! the target. If it does not — a singleton property that has to disappear, a
//! menu with no stable handle — the mismatch is allowed *only* in a section that
//! says so, so an honest "I cannot do this" cannot hide a real bug.

use rsc::diff::{diff, Op, Options};
use rsc::patch::{render, RenderOptions};
use rsc::{parse, parse_config, simulate};
use std::path::{Path, PathBuf};

fn manifest(rel: &str) -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR")).join(rel)
}

/// Every rendered configuration in the corpus, by name.
fn corpus() -> Vec<(String, String)> {
    let mut out = Vec::new();
    let dir = manifest("tests/fixtures/rendered");
    let mut names: Vec<PathBuf> = std::fs::read_dir(&dir)
        .unwrap_or_else(|e| panic!("{}: {}", dir.display(), e))
        .filter_map(|e| e.ok().map(|e| e.path()))
        .filter(|p| p.extension().map(|x| x == "rsc").unwrap_or(false))
        .collect();
    names.sort();
    for path in names {
        let name = path.file_stem().unwrap().to_string_lossy().to_string();
        out.push((name, std::fs::read_to_string(&path).unwrap()));
    }
    // The device's own export is part of the corpus: it is the file a converge
    // would actually be given as "where the router is now".
    out.push((
        "export-7.15.3".to_string(),
        std::fs::read_to_string(manifest("tests/fixtures/export-7.15.3.rsc")).unwrap(),
    ));
    assert!(out.len() >= 7, "corpus is too small: {} files", out.len());
    out
}

fn object_count(cfg: &rsc::Config) -> usize {
    cfg.sections.iter().map(|s| s.objects.len()).sum()
}

#[test]
fn every_rendered_configuration_round_trips() {
    for (name, src) in corpus() {
        let doc = rsc::parse(&src).unwrap_or_else(|e| panic!("{}: {}", name, e));
        assert_eq!(
            rsc::syntax::print::document(&doc),
            src,
            "{} did not round trip",
            name
        );
    }
}

#[test]
fn every_rendered_configuration_models_something() {
    for (name, src) in corpus() {
        let cfg = parse_config(&src).unwrap();
        assert!(
            object_count(&cfg) >= 2,
            "{} parsed to {} objects -- a silently empty parse",
            name,
            object_count(&cfg)
        );
        // Every rendered file sets an identity, so at least one singleton menu
        // has to have been recognised.
        let identity = cfg
            .section("system identity")
            .unwrap_or_else(|| panic!("{}: no /system identity", name));
        assert_eq!(identity.kind, rsc::SectionKind::Singleton, "{}", name);
        assert!(
            identity
                .objects
                .iter()
                .any(|o| o.props.iter().any(|p| p.key == "name")),
            "{}: identity lost its name",
            name
        );
    }
}

/// The two spellings of one configuration render identically, so the differ
/// must see nothing between them either. This is the repository's own claim
/// (`checks.menus`) run through the other half of the tool.
#[test]
fn the_typed_and_sections_renders_are_the_same_configuration() {
    let corpus = corpus();
    let get = |name: &str| {
        corpus
            .iter()
            .find(|(n, _)| n == name)
            .map(|(_, s)| s.clone())
            .unwrap_or_else(|| panic!("{} missing from the corpus", name))
    };
    let a = get("example");
    let b = get("typed");
    assert_eq!(a, b, "the renderer's own claim no longer holds");

    let d = diff(
        &parse_config(&a).unwrap(),
        &parse_config(&b).unwrap(),
        &Options::default(),
    );
    assert!(d.is_empty(), "identical files differ: {:?}", d.sections);
}

/// Every ordered pair, both directions.
#[test]
fn every_pair_of_configurations_is_a_valid_upsert() {
    let opts = Options::default();
    let corpus = corpus();
    let mut checked = 0;

    for (a_name, a_src) in &corpus {
        for (b_name, b_src) in &corpus {
            if a_name == b_name {
                continue;
            }
            let ca = parse_config(a_src).unwrap();
            let cb = parse_config(b_src).unwrap();
            let d = diff(&ca, &cb, &opts);

            // The patch has to be a script, whatever the pair is.
            let text = render(&d, &RenderOptions::new(a_name, b_name));
            let doc = parse(&text).unwrap_or_else(|e| {
                panic!(
                    "{} -> {}: the patch does not parse: {}\n{}",
                    a_name, b_name, e, text
                )
            });
            for item in &doc.items {
                match item {
                    rsc::syntax::ast::Item::Command(_)
                    | rsc::syntax::ast::Item::Comment { .. }
                    | rsc::syntax::ast::Item::Section { .. }
                    | rsc::syntax::ast::Item::Blank { .. } => {}
                    other => panic!(
                        "{} -> {}: patch contains a non-command: {:?}",
                        a_name,
                        b_name,
                        other.raw()
                    ),
                }
            }

            // Applying it has to reach the target, except where the diff itself
            // said a section cannot be converged.
            let applied = simulate::apply(&ca, &d);
            let problems = simulate::compare(&cb, &applied, &d, &opts);
            let excused: Vec<String> = d
                .sections
                .iter()
                .filter(|s| s.ops.iter().any(|o| matches!(o, Op::Unresolvable { .. })))
                .map(|s| format!("/{}:", s.path))
                .collect();
            let unexpected: Vec<&String> = problems
                .iter()
                .filter(|p| !excused.iter().any(|e| p.starts_with(e.as_str())))
                .collect();
            assert!(
                unexpected.is_empty(),
                "{} -> {}: {} unexpected difference(s)\n{}\npatch:\n{}",
                a_name,
                b_name,
                unexpected.len(),
                unexpected
                    .iter()
                    .map(|p| p.as_str())
                    .collect::<Vec<_>>()
                    .join("\n"),
                text
            );
            checked += 1;
        }
    }

    assert!(checked >= 40, "only {} pairs checked", checked);
}

/// A configuration is its own target: no operations at all, in every file the
/// repository can produce.
#[test]
fn every_configuration_is_a_no_op_against_itself() {
    let opts = Options::default();
    for (name, src) in corpus() {
        let cfg = parse_config(&src).unwrap();
        let d = diff(&cfg, &cfg, &opts);
        assert!(
            d.is_empty(),
            "{}: self-diff is not empty: {:?}",
            name,
            d.sections
        );
        assert!(
            d.is_exact(),
            "{}: self-diff is not exact -- a strategy is guessing",
            name
        );
    }
}
