# The `.rsc` parser, the differ, and what a patch can say

`rsc/` is a small Rust crate that reads RouterOS configuration scripts, compares
two of them, and writes the console commands that take a device from the first
to the second. It exists because re-importing a whole configuration is not
idempotent: `/import` of `add` lines fails on the second run, and a runtime error
leaves the prefix applied. A converge needs a difference, and a difference needs
a parser.

This page is the reasoning and the measurements. The crate's own `README.md` is
the usage reference.

## Why the model is not the text

A `.rsc` file is a list of menu headers and commands:

```
/ip pool
add name=lan-pool ranges=10.10.10.100-10.10.10.200
/ip firewall filter
add action=accept chain=input comment="defconf: accept icmp" protocol=icmp
```

Three layers turn that into something diffable, and each one answers a question
the next one needs:

1. **syntax** — what bytes are in the file. A lexer, a line-oriented parser, and
   an AST that keeps every item's source text, so nothing is lost and a patch can
   print the target's own spelling of a value.
2. **model** — what configuration the file describes. Sections become objects
   with property maps; `add` creates one, `set [find …]` modifies the one its
   selector addresses, `set k=v` with no selector is a singleton menu.
3. **diff** — which object is which, and therefore what to say. This is the hard
   part, and it is a per-menu question.

## Identity: the part that has no clean answer

An `/export` carries no internal ids — the `.id` RouterOS uses is per-boot and
not in the text. So a patch has to name what it changes the way a human would in
the console. `src/identity.rs` holds the table, and there are only four answers:

| strategy | when | how the patch addresses an object |
|---|---|---|
| keyed | the menu names its objects (`/ip pool name=`, `/ip address address=+interface=`) | `set [find name=…]`, `add`, `remove [find …]` |
| comment-keyed | an ordered menu where every object carries a comment | the comment is the key; `place-before=` and `move` restore order |
| positional | an ordered menu with no handle at all | same length: `set <n>`; different length: rebuild the section |
| singleton | one settings object (`/ip dns`, `/system identity`) | `set` only |

Two of those deserve a note.

**A comment is the only stable handle an ordered menu offers.** A firewall rule
has no name; `place-before` and `find` accept a comment, so a rule that carries
one can be inserted before and moved. That is also why the differ refuses to
treat a menu as comment-keyed unless *every* object has a comment and no two
share one: `remove [find comment=x]` removes every match, so a duplicate comment
is not a handle but a trap.

**Positional addressing is honest but not exact.** `set 2 action=drop` assumes
the device's rule list is the one the source file describes. When the length
changes there is nothing in the text that can address rule 3 of five, so the
section is removed and rebuilt in the target's order — exact, and churny. The
report says `exact: no` either way.

## What RouterOS will not let a patch say

Measured on a CHR 7.15.3 while writing this, because every one of these looked
like it should work:

```
/ip pool set [find name=probe1] !ranges      -> syntax error (line 1 column 33)
/ip pool unset [find name=probe1] ranges     -> expected end of command (line 1 column 26)
/ip pool set [find name=probe1] ranges=""    -> failure: no address ranges specified
/ip firewall filter set 0 !comment           -> syntax error (line 1 column 27)
/ip pool set [find name=lan-pool] comment="" -> (works; the next /export omits it)
```

So **there is no unset**. A property can be dropped only by re-creating the
object, and re-creating is not free: `remove` of a pool a DHCP server points at,
or an interface with addresses on it, is refused as `in use`. Two consequences:

* `comment=""` is special-cased because it is *measured* to reset in place, and
  a comment is the property most often dropped when a configuration changes. It
  turns the common case into a one-line `set`.
* Everything else costs a `remove` + `add`, which the patch marks with a
  `# replace:` line so a reader sees it before applying.

A **singleton** menu cannot be emptied at all — there is no object to re-create.
`/ip dns` losing a property is not expressible, so the differ emits a `#` line
naming the property and `rsc verify` reports it. Producing a patch that silently
does nothing would be worse.

## Fidelity

The parser keeps the source text of every item, and a patch prints the *target*
file's own argument text for the values it writes. That is not cosmetic:

* `/export` wraps long lines after `\`, and sometimes after `=`:
  `add ... name=\` / `    chr-deploy.lan`. Joining a continuation inserts a
  space, and a tokeniser that stops at the first whitespace after `=` reads the
  value as a new *argument name* — the object then silently loses it. Both wrap
  shapes are joined before tokenising, and whitespace after `=` is skipped.
* A value that ends in `=` (base64 padding) has to stay quoted, or the line ends
  at the padding and the rest is garbage. Re-spelling a decoded value is how that
  happens; printing the target's own token is how it does not.
* A comment may carry `"`, `\` and `$`; the round-trip test in
  `tests/roundtrip.rs` covers the real export that has all three.

The corpus for those tests is the repository's own renderer output
(`tests/golden/*.rsc`) plus a real `/export` from 7.15.3
(`rsc/tests/fixtures/export-7.15.3.rsc`), which is what a parser actually has to
read.

## The property the crate is built around

`rsc verify a.rsc b.rsc` applies the generated patch to the *model* of `a` and
compares the result with the model of `b`. Every test in `rsc/tests/upsert.rs`
asserts that, in both directions, and `tests/upsert.rs` also requires that the
patch itself parses and contains nothing but console commands.

That is a claim about the tool agreeing with itself. The claim about the device
was checked separately, on the same CHR 7.15.3, by deriving a target from the
device's own `/export`, applying only the patch, and comparing the device's next
`/export` with the target:

| round | what the patch did | result |
|---|---|---|
| 1 | added a pool, an address and a DNS entry; rebuilt a comment-less firewall section; set two singletons | `/export` matched the target; `rsc diff` of the two: 0 operations |
| 2 | `set 0/1/2 comment=…` on rules the source had no comments for | `/export` matched |
| 3 | `add … place-before=[find comment=…]` plus `move [find comment=…] destination=0` | `/export` matched; 0 operations |

The only difference between the device's export and the target in round 1 was
that the device writes `set name=chr-diff` where the target had
`set name="chr-diff"` — the same value, and the semantic diff is zero. That is
the level at which the two files are compared: quoting is not a difference.

## What is not here

* **Nothing in the deploy path uses it yet.** `nix-mikrotik deploy` still imports
  a whole script; wiring `rsc` in front of it is the next change, and it needs a
  decision about where the "current state" comes from (a fresh `/export`, or a
  previous generation's script).
* **The identity table is a table, not a schema.** It covers the menus this
  repository's renderer emits plus the neighbours it has met; a menu it does not
  know is keyed on whatever the object carries (`name`, then `address`), and
  only falls back to position when there is nothing to key on. `tests/menus.rs`
  keeps that honest: it reads `lib/menus.generated.nix` — 346 menus walked out of
  `/console/inspect` — and requires that a one-value change in any menu with a
  `name` (or an `address`) is a `set`, not a rebuild. `/console/inspect` is
  still the long-term source for the *composite* keys, the same source
  `scripts/walk-menus.py` uses.
* **Ordered menus without comments are the weak spot.** Adding a comment to
  every rule the fleet manages is what makes a converge exact there, and that is
  a configuration convention rather than a code change.
* **Cross-section dependency is not modelled.** A patch that re-creates a
  referenced object can be refused (`in use`). Ordering is target-file order for
  adds and reverse order for removals, which is right for the shapes the
  renderer emits, but a genuine dependency graph is not built.
