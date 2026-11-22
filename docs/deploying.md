# Deploying

`nix-mikrotik deploy` is the whole path from a `.rsc` to a configured device:
substitute, **diff against the device**, upload the difference, import it, verify,
clean up — and refuse when it cannot say the import ran.

```sh
nix-mikrotik list-secrets router.rsc      # what this script still needs
nix-mikrotik secretize router.rsc -o out.rsc --secrets-dir ./secrets
nix-mikrotik deploy router.rsc --host 10.0.0.1 --check    # the plan, nothing sent
nix-mikrotik deploy router.rsc --host 10.0.0.1 --verify   # apply it
nix-mikrotik diff router.rsc --host 10.0.0.1              # a textual diff, for reading
```

## The device is given the difference, not the script

`deploy` exports the device's own configuration (`/export terse`) and asks `rsc`
for the console commands between that and the script
([the `.rsc` parser](rsc-parser.md)). The patch is what gets uploaded and
imported, so a second deploy of the same script is a plan of `set`s — not a
second copy of every object.

That is the difference from re-importing: `/import` of `add` lines is not
idempotent, so the old path could only be run once against a device that already
held the configuration (`failure: already have interface with such name`, and the
import stops there with everything above it applied). A patch that says
`set [find name=…]` for an object that exists converges instead.

`--import-whole` keeps the old behaviour: upload the script and import all of it.
It is the path for a device whose `/export` the differ cannot read, and the one
that is not idempotent.

## Deletions are withheld (`--prune` applies them)

By default the patch is an **upsert**: adds and sets, and every operation that
would delete is withheld and printed as `# withheld: …` in the patch (and in
`rsc diff`'s report). The reason is not caution for its own sake — an `/export`
carries the device's *whole* configuration, so "not in the target" includes

* the address this deploy is talking to the device over,
* the ethernet interfaces and their settings,
* `/ip dhcp-client` on the uplink,
* and anything somebody added by hand.

Removing those is what "the device now holds exactly the script" means, and it
is not a decision a tool can make for you: measured on a lab CHR, the full diff
of the test fixture against a configured device was 15 removals, one of them the
management address the deploy was running over.

`--prune` applies them. It is the mode for a device whose configuration this
repository owns completely; the ownership predicate that would make it safe in
general does not exist yet ([Not done yet](roadmap.md)).

Two consequences of withholding, both reported rather than hidden:

* a menu with **no stable handle** (`/ip firewall filter` whose rules carry no
  comments) is compared as a list, and a rebuild is one operation — the removes
  and the adds that replace them. Withholding half of it would append a second
  copy of the target's rules on every deploy, so the whole menu is left alone and
  the patch says `# note: not applied: this menu needs N removal(s)`. Give the
  rules comments (a `comment` on every rule) and the menu becomes
  comment-keyed: then an upsert can add and move without deleting.
* a property that has to *disappear* from an object (`/export` never shows it,
  and RouterOS has no unset) costs a remove-and-re-add, so it is withheld with
  the removal it needs. `comment=""` is the one property that resets in place.

## Two properties that make a deploy never completely quiet

The diff is against `/export`, which is not a complete picture of the device:

* a **secret** (`/interface wireguard private-key`) is never exported, so the
  patch re-asserts it on every deploy. Same value, same object, `set` only.
* a property the script states **explicitly at its default value**
  (`disabled=no`) is omitted by `/export`, so the diff asks for it every time.

Both are harmless and idempotent; neither is a difference a diff against an
export can see. A plan of "nothing to do" therefore happens when the script
declares no secrets and no explicit defaults.

## A plan that cannot reach the target is refused

The differ cannot express everything. Three shapes are marked `UNAPPLIED:` in
the plan, and `deploy` **refuses** on them by default rather than applying the
rest and reporting success:

* a target line the differ cannot model — a block script (`/interface { … }`),
  anything a configuration put in `mikrotik.extraScript`;
* a menu with no stable handle whose change would have to be applied by
  *rebuilding* it, which is a deletion (see above);
* an object whose re-creation is needed because a property has to disappear
  (RouterOS has no unset, so that is a remove plus an add).

Refusing is the point: a deploy that applies 90% of a configuration and prints
`verified: identity is …` is worse than one that stops, because nothing on the
device says what is missing. `--allow-partial` applies what the differ can
express and prints what it could not; `--prune` is the answer when a deletion is
what was missing; `--import-whole` is the answer for lines the differ cannot
model.

Two other refusals come from the same principle:

* a script with **no commands** is refused. An empty render is a broken
  configuration (a module that evaluated to nothing, a flake output that changed
  shape), not a request to empty the device.
* a command that **does not finish** is a failure, not a wait. Every ssh/scp
  invocation carries a timeout (`--command-timeout`, default 120s) because a
  wedged sshd or a script that blocks the console would otherwise hold a deploy
  unit open forever — `ConnectTimeout` does not help once the connection is
  established.

## One file per run, and what a killed deploy leaves behind

The uploaded script is named `router-config-<marker>.rsc`, where the marker is the
same random string the sentinel uses. A device has one flat file store, so a fixed
name was shared by every deploy to it: two runs raced, and one's cleanup could
delete the file the other's `/import` was reading — which reads as a device error.

Cleanup is a `finally`, so a deploy that is SIGKILLed (or whose host dies) leaves
the *secretized* script — plaintext secrets — on the device's flash. Nothing
sweeps those automatically, because `router-config-*.rsc` includes a concurrent
run's file; instead the next run lists them and says what they are.

## The transport and the refusals

* Transport is the system `ssh`/`scp`: key-based auth against the router's
  `admin` user, no library, no password handling of our own.
* `--known-hosts PATH` is the one thing the transport will not take from the
  operator's environment. `accept-new` learns a host key by appending it to
  ssh's known_hosts file, and that `~` comes from the passwd entry rather than
  `$HOME` — so a caller with no operator home (a systemd unit as root under
  `ProtectHome = true`) has nowhere to record one and every deploy is a first
  contact. Pass a path the caller *can* write (ccpkgs' `services.mikrotik` hands
  the unit a `StateDirectory`-backed file) and the pin is learned again. A path
  whose directory does not exist is refused: ssh treats a failed append as a
  warning, so the alternative is a deploy that looks pinned and is not. Only the
  file is selectable — `accept-new` still means accept-new, and a key pinned
  machine-wide in `/etc/ssh/ssh_known_hosts` is still read.
* `deploy --check` prints the plan and exits — `1` when the device differs, `0`
  when it is converged — without uploading anything. That is the first run
  against a live router, and it is the drift gate a wrapper script can branch on.
  "Converged" means every operation left is an **assertion**: a write of a
  property `/export` cannot show (a WireGuard `private-key`, a property stated at
  its default), which no later diff can confirm. The report says so on its own
  line (`converged: … N value(s) /export cannot show are re-asserted`), because
  counting operations would make a correct device fail forever. A plan that
  cannot reach the target is `1` whatever it contains.
* `deploy --reset` **without** `--yes` is refused before anything happens:
  before the transport, and before a secret value is read. It used to be refused
  after the secretized script had already been uploaded, which made the
  confirmation not the guard it reads as.
* an import that did not run to the end is a failure, not a silent no-op:
  RouterOS logs a parse error and still exits 0, so `deploy` appends a sentinel
  line to the uploaded copy — `rsc` does it for a patch, the tool does it for a
  whole script — and reads the device's log back before it reports success. When
  the sentinel never appears it exits 2 and says **a prefix of the script may
  have been applied**: the tool cannot tell a parse abort (nothing applied) from
  a runtime one (everything above the failing line applied). Check the device
  (`deploy --check`, or `diff`) before re-deploying.
* `deploy --reset --yes` runs `/system reset-configuration
  no-defaults=yes run-after-reset=…` with the whole script instead: the device
  reboots into exactly the script. That is the declarative path, and it wipes
  the configuration.
* `diff` is the *textual* comparison of the device's export and the script. It is
  a review aid, not a plan: it cannot see that two differently written rules mean
  the same thing, which is exactly what `deploy --check` shows.
