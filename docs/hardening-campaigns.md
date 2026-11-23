# The hardening campaigns

Six PRs stacked on the `.rsc` parser, differ and deploy path, each one closing a way
the tool could lie about what a device would do. This file is the **procedure** for
that work — how to run the pipeline, how to check a shape against a real router, how
to land a change — and the **backlog** of what is still open.

Everything stated here was measured on a RouterOS CHR running **7.15.3**, or by a
test that fails if the claim stops being true. Where a claim is not measured it says
so.

## The stack

Branches stack bottom-up; each PR's base is the branch below it.

| PR | branch | what it closed |
|----|--------|----------------|
| #26 | `feat/rsc-parser-diff` | the `.rsc` parser, the differ, and a patch generator — the base everything else sits on |
| #27 | `feat/deploy-diff-upsert` | `deploy` applies the *difference*, not the whole file; deletions withheld unless `--prune`; `--check`, `--import-whole` |
| #28 | `feat/menus-*` (from master) | regenerated the menu table for 7.25.1; the probe survives a wedged menu |
| #29 | `feat/chr-lab-*` (from master) | a management NIC the host can reach, and lab ports you choose |
| #30 | `fix/deploy-hardening` | refuses a plan it cannot apply, never hangs, and stops the parser losing a line |
| #31 | `feat/check-convergence` | `--check` is a drift gate: an assertion (a property `/export` cannot show) is not a change |
| #32 | `fix/selectorless-set-and-races` | a selector-less `set` named nothing; a patch never carries a verb with no operand; one upload name per run |
| #33 | `feat/composite-key-fuzz` | a composite selector that would take two objects is refused |

Each of #30–#33 exists because a *measurement* disagreed with the model, not because
the code looked wrong:

* #30 — a `set` with no selector in a menu of objects became a bare `remove`; the
  device answers `Script Error: missing value(s) of argument(s) numbers` and the
  import aborts **after** everything above it applied.
* #31 — a correct device reported `2 set` on every deploy forever, because `/export`
  never shows WireGuard `private-key` and omits properties at their default.
* #32 — the same selector-less `set` in `/ip pool` is refused by the device itself
  (rc 1, nothing changed), which is why it is modelled as unmodelled rather than
  guessed at; and two deploys to one device shared a fixed upload filename.
* #33 — `/interface bridge port` keyed on `bridge`+`interface`, with one object
  missing `interface`, produced `remove bridge=br`: a selector matching **both**
  objects while the patch said one.

## 1. Run the pipeline

Everything is a flake check. `chr-deploy` boots a CHR VM (minutes); the rest are
seconds.

```bash
nix build --no-link \
  .#checks.x86_64-linux.{cli,chr-deploy,rsc,rsc-fuzz,menus,render,networks,routers-generate,eval,fleet}
```

The crate alone — where a differ change lives:

```bash
cargo test --manifest-path rsc/Cargo.toml
```

Generated script pairs, both modes, both directions:

```bash
# the check, 200 cases, fixed seed, ~1s
python3 tests/fuzz-rsc.py ./rsc/target/debug/rsc --cases 200 --seed 1 --root .

# by hand, when hunting
python3 tests/fuzz-rsc.py ./rsc/target/debug/rsc --cases 2000 --seed $RANDOM --root .
```

`--save DIR` writes a failing case out so it can become a fixture. `--drops` turns on
property removal, which forces the remove+add path — off by default because a section
with several *replaced* objects still reaches an open edge (backlog item 1).

Read the assertion count, not the exit code, when a test "passes":

```bash
nix log .#checks.x86_64-linux.chr-deploy | grep 'assertions held'
```

## 2. Check a shape against the device, before believing the model

The lab is a CHR; `nix run .#chr-lab -- start` (or reuse a running one —
`chr-lab status` prints the SSH and REST ports it actually bound).

```bash
# the model's opinion
./rsc/target/debug/rsc parse live.rsc
./rsc/target/debug/rsc diff  live.rsc target.rsc
./rsc/target/debug/rsc patch live.rsc target.rsc
./rsc/target/debug/rsc verify --upsert live.rsc target.rsc

# the device's opinion
ssh -F /dev/null -o BatchMode=yes -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null -i "$KEY" -p "$SSH_PORT" admin@127.0.0.1 \
    '/ip pool set comment=x'          # the line under test, verbatim
curl -s -u admin: "http://127.0.0.1:$REST_PORT/rest/ip/pool"
```

**The device is right and the model is the bug.** Every one of #30–#33 came from
this comparison; none came from reading the differ. When a line is *rejected* by the
device, that is the strongest possible answer: there is no target to guess at, so the
model must refuse rather than approximate.

Two habits that made the difference:

* **Measure the premise.** "The device would refuse this" is a hypothesis until you
  run the line. The selector-less `set` in `/ip pool` answers
  `Script Error: missing value(s) of argument(s) numbers` with rc 1 and changes
  nothing — that measurement is what turned a cautious model change into a correct
  one.
* **Assert identity, not counts.** #33's first test asserted that *one* object
  survived, and passed, while the model removed the **wrong** one. Asserting which
  object survived (its key part) caught it. On a device the same selector deletes
  both, so the count was wrong in both directions.

## 3. Land a change

1. Branch off the **top of the stack**, never master:
   `git checkout -b <name> feat/composite-key-fuzz`.
2. One commit per bug; the message says what was measured and what the old
   behaviour did to a device.
3. Push, then verify the push against the remote rather than your memory:
   `git ls-remote origin <branch>` and compare with `git rev-parse HEAD`.
4. Open the PR with `--base <the branch below it>`; the body is the status report —
   what was measured, what is verified (with the assertion counts), what is left.
   Refresh it whenever the branch moves.
5. A doc-only or test-only PR still gets its own branch and its own base. Nothing
   lands on master by accident.

## 4. Backlog, in the order I would take it

### 1. Property drops in a section with several replaced objects

*Why:* a replacement is remove+add (RouterOS cannot unset a property), and when two
objects in one section are replaced, the applied model ends up with one object's
properties on another's identity.
*Reproduce:* `python3 tests/fuzz-rsc.py ./rsc/target/debug/rsc --cases 150 --seed 1 --drops --root .`
→ roughly 3 mismatches.
*Done when:* that command reports zero failures at 2000 cases, and `--drops` is on
in `checks.rsc-fuzz` with no note in its help text about an open edge.

### 2. Objects with no identity at all

*Why:* if a menu's key is absent the differ answers positionally — `remove <index>` —
which is the same guessing that #33 refused for a *partial* key. A command whose
effect depends on a list order the tool cannot know is not a plan.
*Reproduce:* drop the `name` from one object of a named menu and diff; the plan
contains a positional op with `exact: false` and no `UNAPPLIED:` note.
*Done when:* the differ refuses (a note naming the object) instead of emitting a
positional op for a keyed menu, and `rsc/tests/menus.rs` has a case that drops the
key and expects the refusal.

### 3. The switch menus' key arguments are missing from the generated table

*Why:* `interface ethernet switch vlan` keys on `vlan-id`, and `… switch
port-isolation` on `ports`+`customer-vid`; those arguments are not in
`lib/menus.generated.nix`, so the composite test skips them — the menus the fleet's
CRS exports actually use are the untested ones.
*Reproduce:* the composite test in `rsc/tests/menus.rs` silently skips them; count
`checked` and compare with the identity table.
*Done when:* the probe records those arguments, the composite test exercises both
menus, and they are named in its "these must be exercised" assertion.

### 4. Exercise the `/ip route` partial key on the device

*Why:* `/ip route` keys on `dst-address`+`gateway`+`routing-mark`+`vrf-interface`,
and the last two are optional — so a marked and an unmarked default route share a
selector. The refusal is implemented (#33) but only unit-tested; the live shape is
worth one CHR assertion.
*Done when:* `tests/chr-deploy.py` creates two default routes, removes the unmarked
one, and asserts the plan says `UNAPPLIED:` and `deploy` refuses without
`--allow-partial`.

### 5. Finish `docs/testing-against-a-router.md`

*Why:* it was written before the upsert path existed and still lacks the bullets for
a one-property change, the second deploy, and the `--import-whole` failure
(`failure: already have interface with such name`, measured).
*Done when:* the page matches `tests/chr-deploy.py` assertion for assertion.

### 6. A known-hosts option for the lab

*Why:* `chr-lab` accepts `--key` but no known-hosts file, so a rebuilt device at the
same `host:port` is refused until someone runs `ssh-keygen -R` by hand. `docs/roadmap.md`
ends mid-sentence on exactly this point.
*Done when:* the roadmap bullet is a finished TODO and `chr-lab` takes
`--known-hosts`, or the roadmap says why it will not.

### 7. Delegation hands children a different provider (not a repo item)

*Why:* two subagents on `deepseek-v4.1-flash` died with `custom rejected your API
key` (HTTP 401) after 15–45 calls while this session ran fine through the local
router. The second one was one measurement away from an answer that had to be taken
by hand.
*Done when:* a child inherits the parent's provider, or the router's key handling for
child sessions is understood and documented.

## 5. Traps that cost time in this work

* `/export` cannot show WireGuard private keys and omits defaults, so a *converged*
  device still produces `set` operations. They are assertions, not changes; the
  report says `converged:` when nothing else is left.
* RouterOS cannot unset a property. A change that needs one to disappear is a
  remove+add, and the remove comes first (`add name=x` on an existing `x` is
  refused).
* `place-before=<n>` is a **position**, not a key. Matching it as a selector key
  silently appends.
* A device has one flat file store: an upload name shared by concurrent deploys lets
  one run's cleanup delete the file another is importing. The name carries the run's
  marker, and leftovers are reported (they hold plaintext secrets), never swept.
* An `/import` applies everything above a bad line before failing there, so "it
  imported" is not "it applied". The sentinel (`:log info`) is the only positive
  evidence the whole file ran.
* `set` without a selector means the menu's settings object **only** in a menu that
  has one. In a list menu it is refused by the device and must be reported as
  unapplied.
