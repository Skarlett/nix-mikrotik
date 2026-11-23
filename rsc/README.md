# rsc — parse, diff and patch RouterOS configuration

`rsc` reads MikroTik RouterOS `.rsc` scripts, tells you what changed between two
of them, and writes the console commands that take a device from the first to
the second. It is the machinery an import-independent deployment needs: instead
of re-importing a whole configuration and hoping the second import is harmless,
compute the difference and apply only that.

```
rsc parse  <file>              what the parser found
rsc fmt    <file> [--check]    re-print; --check fails if it differs
rsc diff   <a.rsc> <b.rsc>     the operations that turn a into b
rsc patch  <a.rsc> <b.rsc>     those operations as a .rsc script
rsc verify <a.rsc> <b.rsc>     apply the patch to a in the model and compare
```

An operation that only re-states a value `/export` cannot show is printed as
`assert` rather than `set`, and `rsc diff` says `converged:` when that is all
that is left — the one line a drift check can branch on:

```
$ rsc diff live.rsc wanted.rsc --upsert
  2 operations: 0 add, 2 set, 0 remove, 0 replace, 0 move, 0 unperformable
  assertions: 2 (the export cannot show these properties, so a diff cannot confirm them)
  converged: the device holds this configuration; 2 value(s) /export cannot show are re-asserted
```

`--upsert` changes what the plan may contain: adds and sets only, with every
operation that would delete withheld and reported (`# withheld: …` in the patch,
`withheld:` lines in `rsc diff`). That is the mode `nix-mikrotik deploy` uses —
an `/export` carries the device's whole configuration, so an object the target
does not mention is not necessarily one to delete. `rsc verify --upsert` checks
the claim that mode makes: every object the target declares is reached, with
every property it declares.

```
$ rsc patch live.rsc wanted.rsc --upsert --sentinel deploy-1
# ops:  0 add, 5 set, 0 remove, 0 replace, 0 move, 1 unperformable
# withheld: 17 operation(s) would delete; this patch is an upsert and leaves them out
/ip address
# note: 3 removal(s) withheld: the device keeps what the target does not declare
set [find address=10.0.0.1/24 interface=ether1] comment="managed"
# withheld: remove address=192.168.99.2/24 interface=ether1
```

A menu with no stable handle is rebuilt as one operation (its removes and its
adds), so an upsert withholds the whole menu rather than appending a second copy
of its rules; its note says so.

No dependencies, no build script: `cargo test` builds the parser, the differ and
the simulator from std alone.

## The property it is built around

`verify` is the point of the crate. It applies the generated patch to the *model*
of the first file and compares the result with the model of the second:

```
$ rsc verify tests/fixtures/a.rsc tests/fixtures/b.rsc
rsc verify tests/fixtures/a.rsc -> tests/fixtures/b.rsc
  patch: 16 operations (6 add, 6 set, 3 remove, 0 replace, 1 move)
  model: 22 -> 27 (17 sections, 27 objects)
  OK: the patch reaches the target exactly
```

Every test in `tests/upsert.rs` asserts that property for a fixture pair, and it
is checked in both directions. What it does not prove is that RouterOS behaves
the way the model says — that is a claim about the device, and it is checked
separately: the patches in this directory's history were applied to a CHR 7.15.3
and the device's own `/export` afterwards was compared with the target (see
`docs/rsc-parser.md` in the repository).

## Fidelity

The parser keeps the source text of every item, and a patch prints the *target*
file's own argument text rather than re-spelling decoded values. So:

* an untouched line is never reformatted;
* `comment="a  b"` keeps its spacing;
* a base64 key that ends in `=` keeps its quotes, which is the difference
  between a deploy that applies and `script error: expected end of command`.

`/export` wraps long lines after a `\` and sometimes after `=`; both are joined
before tokenising, because a value that starts on the next line reads as an
*argument name* to a naive tokeniser and the object then silently loses it.

**A dangling `=` only continues when the next line is indented.** A value that
simply ends in `=` — every base64 key ends in its padding — used to swallow the
line after it: `add name=a copy-from=QUFB…=` followed by `add name=b` became one
object carrying b's properties, and b was never created. That is a configuration
line silently lost, and a patch that then "converges" without it. `/export` writes
a continuation indented; a command never is, so the indentation is the test. Found
by fuzzing (`tests/fuzz-rsc.py`), not by reading.

## Identity, which is the actual problem

An `/export` carries no internal ids, so a patch has to name what it changes.
The menu table in `src/identity.rs` says how, per menu:

| strategy | when | how |
|---|---|---|
| keyed | the menu has a name or a composite key | `set [find name=…]`, `add`, `remove [find …]` |
| comment-keyed | an ordered menu where every object has a comment | the comment is the key; `place-before=` and `move` restore order |
| positional | an ordered menu with no handle at all | same length: `set <n>`; otherwise the section is rebuilt |
| singleton | one settings object (`/ip dns`) | `set` only |

## What RouterOS will not let a patch do

Measured on 7.15.3 (the assertions are in `src/diff.rs`):

* **There is no unset.** `set x !prop`, `unset x prop` and `set prop=` all fail.
  A property can only be dropped by re-creating the object — except `comment`,
  where `comment=""` clears it and the next `/export` omits it.
* **A singleton's property cannot be dropped at all**: there is no object to
  re-create. `rsc` emits a `#` line saying so and `verify` reports it, rather
  than producing a patch that quietly does nothing.
* **`remove [find comment=x]` removes every match**, so a duplicate comment is
  not a handle and the differ falls back to positional addressing.
* **Re-creating a referenced object can fail** (`in use`): a pool a DHCP server
  points at, an interface with addresses on it. The patch says which objects it
  re-creates; check them before applying.

## Reading the output

`rsc diff` is the review surface:

```
$ rsc diff tests/fixtures/a.rsc tests/fixtures/b.rsc
tests/fixtures/a.rsc -> tests/fixtures/b.rsc
  16 operations: 6 add, 6 set, 3 remove, 0 replace, 1 move, 0 unperformable
  exact: yes

/ip address  (keyed)
  add address=10.10.12.1/24 interface=ether3 network=10.10.12.0
  add address=10.10.20.1/24 interface=vlan20 network=10.10.20.0
  remove address=10.10.11.1/24 interface=ether3

/ip pool  (keyed)
  set name=lan-pool ranges=10.10.10.100-10.10.10.250 comment=""

/ip firewall filter  (comment-keyed)
  add action=accept chain=input comment="defconf: accept dhcp" dst-port=67 protocol=udp
  move comment=defconf: accept icmp to 0
```

`exact: no` means at least one operation addresses an object by position, or one
reset could not be expressed. The patch still says what it can.

## Layout

```
src/syntax/   lexer, AST, line-oriented parser, printer
src/model.rs  sections, objects, properties, selectors
src/identity.rs  the per-menu identity table
src/diff.rs   strategies, operations, the report
src/patch.rs  rendering operations as a script
src/simulate.rs  applying a patch to a model, comparing two models
src/bin/rsc.rs   the CLI
tests/        round trip, the upsert property, the dogfood matrix over the
              renderer's own configurations, and the generated menu table
              (every menu path, every argument name, every multi-value
              argument, and a `set`-not-a-rebuild diff per menu)
```
