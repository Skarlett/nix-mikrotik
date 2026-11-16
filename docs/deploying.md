# Deploying

`nix-mikrotik deploy` is the whole path from a `.rsc` to a configured device:
substitute, upload, import, verify, clean up — and refuse when it cannot say
the import ran.

```sh
nix-mikrotik list-secrets router.rsc      # what this script still needs
nix-mikrotik secretize router.rsc -o out.rsc --secrets-dir ./secrets
nix-mikrotik deploy router.rsc --host 10.0.0.1 --verify
nix-mikrotik diff router.rsc --host 10.0.0.1
```

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
* `deploy --reset` **without** `--yes` is refused before anything happens:
  before the transport, and before a secret value is read. It used to be refused
  after the secretized script had already been uploaded, which made the
  confirmation not the guard it reads as.
* `deploy` **imports** by default, which merges into the running
  configuration. RouterOS has no reconciliation — a repeated `add` makes a
  second object — so importing the same script twice is not idempotent.
* an import that did not run to the end is a failure, not a silent no-op:
  RouterOS logs a parse error and still exits 0, so `deploy` appends a sentinel
  line to the uploaded copy and reads the device's log back before it reports
  success. When the sentinel never appears it exits 2 and says **a prefix of the
  script may have been applied** — the tool cannot tell a parse abort (nothing
  applied) from a runtime one (everything above the failing line applied).
  Check the device (`nix-mikrotik diff`) before re-deploying: a repeated `add`
  makes a second object.
* `deploy --reset --yes` runs `/system reset-configuration
  no-defaults=yes run-after-reset=…` instead: the device reboots into exactly
  the script. That is the declarative path, and it wipes the configuration.
* `diff` exports the live configuration and diffs it textually against the
  script. It is a review aid, not a plan: it cannot see that two differently
  written rules mean the same thing.
