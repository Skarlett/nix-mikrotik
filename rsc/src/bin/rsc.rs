//! `rsc` — parse, diff and patch MikroTik RouterOS configuration scripts.

use rsc::diff::{diff, Diff, Options, Removals};
use rsc::model::SectionKind;
use rsc::patch::{render, RenderOptions};
use rsc::simulate;
use rsc::{parse, syntax};
use std::process::ExitCode;

const USAGE: &str = "\
rsc -- parse, diff and patch MikroTik RouterOS .rsc scripts

USAGE
  rsc parse  <file>              describe what the parser found
  rsc fmt    <file> [--check]    re-print the file; --check exits 1 if it differs
  rsc diff   <a.rsc> <b.rsc>     the operations that turn a into b
  rsc patch  <a.rsc> <b.rsc>     those operations as a .rsc script
  rsc verify <a.rsc> <b.rsc>     apply the patch to a in the model and compare

OPTIONS
  --json        machine-readable output (parse, diff)
  --sentinel M  append `:log info \"M\"` to the patch: the only positive
                evidence that a device ran the whole file
  --all         diff: also list sections with no changes
  --upsert      adds and sets only: every operation that would delete is
                withheld and reported instead (the mode a deploy uses when it
                cannot own the device's objects)
  --keep-derived
                do not ignore properties RouterOS computes (ip address network)

EXIT STATUS
  0 success; 1 verification or check failed; 2 usage or parse error
";

fn main() -> ExitCode {
    let args: Vec<String> = std::env::args().skip(1).collect();
    if args.is_empty() || args[0] == "--help" || args[0] == "-h" {
        print!("{}", USAGE);
        return ExitCode::SUCCESS;
    }

    let cmd = args[0].clone();
    let rest = &args[1..];
    let flags: Vec<String> = rest
        .iter()
        .filter(|a| a.starts_with("--"))
        .cloned()
        .collect();
    let positional: Vec<String> = rest
        .iter()
        .filter(|a| !a.starts_with("--"))
        .cloned()
        .collect();

    let json = flags.iter().any(|f| f == "--json");
    let all = flags.iter().any(|f| f == "--all");
    let check = flags.iter().any(|f| f == "--check");
    let sentinel = flag_value(rest, "--sentinel");
    let opts = Options {
        ignore_derived: !flags.iter().any(|f| f == "--keep-derived"),
        removals: if flags.iter().any(|f| f == "--upsert") {
            Removals::Withhold
        } else {
            Removals::Apply
        },
    };
    let upsert = opts.removals == Removals::Withhold;

    match cmd.as_str() {
        "parse" => {
            let Some(path) = positional.first() else {
                return usage("parse needs a file");
            };
            let src = match read(path) {
                Ok(s) => s,
                Err(code) => return code,
            };
            let doc = match parse(&src) {
                Ok(d) => d,
                Err(e) => {
                    eprintln!("rsc: {}: {}", path, e);
                    return ExitCode::from(2);
                }
            };
            let cfg = rsc::model::build(&doc);
            if json {
                println!("{}", doc_json(&doc, &cfg));
            } else {
                print_parse_summary(path, &doc, &cfg);
            }
            ExitCode::SUCCESS
        }

        "fmt" => {
            let Some(path) = positional.first() else {
                return usage("fmt needs a file");
            };
            let src = match read(path) {
                Ok(s) => s,
                Err(code) => return code,
            };
            let doc = match parse(&src) {
                Ok(d) => d,
                Err(e) => {
                    eprintln!("rsc: {}: {}", path, e);
                    return ExitCode::from(2);
                }
            };
            let out = syntax::print::document(&doc);
            if check {
                if out == src {
                    eprintln!("rsc: {}: round trip is byte-identical", path);
                    ExitCode::SUCCESS
                } else {
                    eprintln!("rsc: {}: round trip differs", path);
                    ExitCode::from(1)
                }
            } else {
                print!("{}", out);
                ExitCode::SUCCESS
            }
        }

        "diff" | "patch" | "verify" => {
            if positional.len() < 2 {
                return usage(&format!("{} needs two files", cmd));
            }
            let (a_path, b_path) = (&positional[0], &positional[1]);
            let a_src = match read(a_path) {
                Ok(s) => s,
                Err(code) => return code,
            };
            let b_src = match read(b_path) {
                Ok(s) => s,
                Err(code) => return code,
            };
            let (a_doc, b_doc) = match (parse(&a_src), parse(&b_src)) {
                (Ok(a), Ok(b)) => (a, b),
                (Err(e), _) => {
                    eprintln!("rsc: {}: {}", a_path, e);
                    return ExitCode::from(2);
                }
                (_, Err(e)) => {
                    eprintln!("rsc: {}: {}", b_path, e);
                    return ExitCode::from(2);
                }
            };
            let ca = rsc::model::build(&a_doc);
            let cb = rsc::model::build(&b_doc);
            let d = diff(&ca, &cb, &opts);

            match cmd.as_str() {
                "patch" => {
                    let mut ro = RenderOptions::new(a_path, b_path);
                    ro.sentinel = sentinel;
                    print!("{}", render(&d, &ro));
                    ExitCode::SUCCESS
                }
                "diff" => {
                    if json {
                        println!("{}", diff_json(a_path, b_path, &d));
                    } else {
                        print_diff(a_path, b_path, &d, all);
                    }
                    ExitCode::SUCCESS
                }
                _ => {
                    let applied = simulate::apply(&ca, &d);
                    let problems = simulate::compare(&cb, &applied, &d, &opts);
                    let stats = d.stats();
                    println!("rsc verify {} -> {}", a_path, b_path);
                    println!(
                        "  patch: {} operations ({} add, {} set, {} remove, {} replace, {} move)",
                        stats.total(),
                        stats.added,
                        stats.changed,
                        stats.removed,
                        stats.replaced,
                        stats.moved
                    );
                    if upsert {
                        println!(
                            "  upsert: {} operation(s) withheld -- the patch adds and sets, and deletes nothing",
                            stats.withheld
                        );
                    }
                    println!(
                        "  model: {} -> {} ({} sections, {} objects)",
                        count_objects(&ca),
                        count_objects(&cb),
                        cb.sections.len(),
                        count_objects(&cb)
                    );
                    if problems.is_empty() {
                        println!("{}", if upsert {
                            "  OK: the patch reaches everything the target declares (deletions withheld)"
                        } else {
                            "  OK: the patch reaches the target exactly"
                        });
                        ExitCode::SUCCESS
                    } else {
                        println!("  MISMATCH: {} difference(s)", problems.len());
                        for p in &problems {
                            println!("    {}", p);
                        }
                        ExitCode::from(1)
                    }
                }
            }
        }

        other => usage(&format!("unknown command {:?}", other)),
    }
}

fn read(path: &str) -> Result<String, ExitCode> {
    std::fs::read_to_string(path).map_err(|e| {
        eprintln!("rsc: {}: {}", path, e);
        ExitCode::from(2)
    })
}

fn usage(message: &str) -> ExitCode {
    eprintln!("rsc: {}", message);
    eprint!("{}", USAGE);
    ExitCode::from(2)
}

fn flag_value(args: &[String], name: &str) -> Option<String> {
    let mut it = args.iter();
    while let Some(a) = it.next() {
        if a == name {
            return it.next().cloned();
        }
        if let Some(v) = a.strip_prefix(&format!("{}=", name)) {
            return Some(v.to_string());
        }
    }
    None
}

fn count_objects(cfg: &rsc::Config) -> usize {
    cfg.sections.iter().map(|s| s.objects.len()).sum()
}

fn print_parse_summary(path: &str, doc: &syntax::ast::Document, cfg: &rsc::Config) {
    let mut sections = 0;
    let mut commands = 0;
    let mut comments = 0;
    let mut scripts = 0;
    for item in &doc.items {
        match item {
            syntax::ast::Item::Section { .. } => sections += 1,
            syntax::ast::Item::Command(_) => commands += 1,
            syntax::ast::Item::Comment { .. } => comments += 1,
            syntax::ast::Item::Script { .. } => scripts += 1,
            syntax::ast::Item::Blank { .. } => {}
        }
    }
    println!("{}", path);
    println!(
        "  {} lines: {} sections, {} commands, {} comments, {} unmodelled",
        doc.items.len(),
        sections,
        commands,
        comments,
        scripts
    );
    println!("  {} objects", count_objects(cfg));
    for section in &cfg.sections {
        let kind = match section.kind {
            SectionKind::Objects => "",
            SectionKind::Singleton => " (settings)",
            SectionKind::Unmodelled => " (unmodelled)",
        };
        println!(
            "  /{}{}  {} object{}",
            section.path,
            kind,
            section.objects.len(),
            if section.objects.len() == 1 { "" } else { "s" }
        );
        for obj in &section.objects {
            let props = obj
                .props
                .iter()
                .map(|p| p.raw.clone())
                .collect::<Vec<_>>()
                .join(" ");
            println!("      {:<40} {}", obj.selector.to_string(), props);
        }
        if !section.extras.is_empty() {
            println!("      + {} unmodelled line(s)", section.extras.len());
        }
    }
}

fn print_diff(a: &str, b: &str, d: &Diff, all: bool) {
    let stats = d.stats();
    println!("{} -> {}", a, b);
    println!(
        "  {} operations: {} add, {} set, {} remove, {} replace, {} move, {} unperformable",
        stats.total(),
        stats.added,
        stats.changed,
        stats.removed,
        stats.replaced,
        stats.moved,
        stats.unresolvable
    );
    if stats.withheld > 0 {
        println!(
            "  {} withheld (upsert): these would delete, and an upsert does not",
            stats.withheld
        );
    }
    if stats.asserted > 0 {
        println!(
            "  assertions: {} (the export cannot show these properties, so a diff cannot confirm them)",
            stats.asserted
        );
    }
    // The one line a drift check can branch on. A device whose only remaining
    // writes are values `/export` cannot show is converged as far as a diff can
    // tell, and no amount of re-running will make the plan empty.
    if d.is_assertion_only() {
        println!(
            "  converged: the device holds this configuration; {} value(s) /export cannot show are re-asserted",
            stats.asserted
        );
        if stats.unresolvable > 0 {
            println!(
                "             {} property/ies the target drops cannot be unset on RouterOS and are left in place",
                stats.unresolvable
            );
        }
    }
    println!(
        "  exact: {}",
        if d.is_exact() {
            "yes"
        } else {
            "no -- a positional remove or an unperformable reset is present"
        }
    );
    for note in &d.notes {
        println!("  note: {}", note);
    }
    for section in &d.sections {
        if section.ops.is_empty() && section.withheld.is_empty() && !all {
            continue;
        }
        println!();
        println!("/{}  ({})", section.path, section.strategy.as_str());
        for note in &section.notes {
            println!("  note: {}", note);
        }
        for op in &section.ops {
            println!("  {}", op.describe());
        }
        for op in &section.withheld {
            println!("  withheld: {}", op.describe());
        }
        if section.ops.is_empty() && section.withheld.is_empty() {
            println!("  (no changes)");
        }
    }
}

fn json_escape(s: &str) -> String {
    let mut out = String::with_capacity(s.len() + 2);
    for c in s.chars() {
        match c {
            '"' => out.push_str("\\\""),
            '\\' => out.push_str("\\\\"),
            '\n' => out.push_str("\\n"),
            '\r' => out.push_str("\\r"),
            '\t' => out.push_str("\\t"),
            c if (c as u32) < 0x20 => out.push_str(&format!("\\u{:04x}", c as u32)),
            c => out.push(c),
        }
    }
    out
}

fn doc_json(doc: &syntax::ast::Document, cfg: &rsc::Config) -> String {
    let items: Vec<String> = doc
        .items
        .iter()
        .map(|i| {
            let kind = match i {
                syntax::ast::Item::Blank { .. } => "blank",
                syntax::ast::Item::Comment { .. } => "comment",
                syntax::ast::Item::Section { .. } => "section",
                syntax::ast::Item::Command(_) => "command",
                syntax::ast::Item::Script { .. } => "script",
            };
            format!(
                "{{\"kind\":\"{}\",\"raw\":\"{}\"}}",
                kind,
                json_escape(i.raw().trim_end_matches('\n'))
            )
        })
        .collect();

    let sections: Vec<String> = cfg
        .sections
        .iter()
        .map(|s| {
            let objects: Vec<String> = s
                .objects
                .iter()
                .map(|o| {
                    let props: Vec<String> = o
                        .props
                        .iter()
                        .map(|p| {
                            format!(
                                "{{\"key\":\"{}\",\"value\":\"{}\"}}",
                                json_escape(&p.key),
                                json_escape(&p.value.text)
                            )
                        })
                        .collect();
                    format!(
                        "{{\"selector\":\"{}\",\"props\":[{}]}}",
                        json_escape(&o.selector.to_string()),
                        props.join(",")
                    )
                })
                .collect();
            format!(
                "{{\"path\":\"{}\",\"objects\":[{}]}}",
                json_escape(&s.path),
                objects.join(",")
            )
        })
        .collect();

    format!(
        "{{\"items\":[{}],\"sections\":[{}]}}",
        items.join(","),
        sections.join(",")
    )
}

fn diff_json(a: &str, b: &str, d: &Diff) -> String {
    let sections: Vec<String> = d
        .sections
        .iter()
        .filter(|s| !s.ops.is_empty())
        .map(|s| {
            let ops: Vec<String> = s
                .ops
                .iter()
                .map(|op| format!("{{\"op\":\"{}\"}}", json_escape(&op.describe())))
                .collect();
            format!(
                "{{\"path\":\"{}\",\"strategy\":\"{}\",\"ops\":[{}]}}",
                json_escape(&s.path),
                s.strategy.as_str(),
                ops.join(",")
            )
        })
        .collect();
    let stats = d.stats();
    format!(
        "{{\"from\":\"{}\",\"to\":\"{}\",\"exact\":{},\"stats\":{{\"add\":{},\"set\":{},\"remove\":{},\"replace\":{},\"move\":{},\"unperformable\":{},\"withheld\":{},\"asserted\":{}}},\"sections\":[{}]}}",
        json_escape(a),
        json_escape(b),
        d.is_exact(),
        stats.added,
        stats.changed,
        stats.removed,
        stats.replaced,
        stats.moved,
        stats.unresolvable,
        stats.withheld,
        stats.asserted,
        sections.join(",")
    )
}
