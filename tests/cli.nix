{ pkgs, nix-mikrotik, cliSource }:

# The deploy tool's contract, minus the device: placeholders are enumerated,
# substituted from files, and an unresolved one is a hard failure rather than a
# script with a literal __MIKROTIK_SECRET_… in it. What a *failure* is allowed
# to claim is part of that contract too, and is asserted here against the
# function `deploy` calls (`cliSource` is the same file the package installs,
# so the message is tested once, not copied into a fixture).
#
# What a substituted value is *spelled* like is part of that contract, not
# cosmetics. RouterOS ends the command early on an unquoted value containing
# `=`, and a base64 WireGuard private key (32 bytes, so always a trailing `=`)
# is exactly that shape: the device then aborts the *entire* script, applies
# nothing, and `/import` still exits 0. A fixture value like `sekret-key` cannot
# see that, which is why one of the cases below is base64-shaped.
#
# Two decisions the tool makes before it opens a socket are tested the same way,
# on the module rather than on a device: that `--reset` without `--yes` is
# refused *before* it uploads anything, and that the ssh/scp argv a caller gets
# is one it can point at a known_hosts file it owns. Both were defects that a
# device-side test could not have caught cheaply -- one needed a refused deploy
# to reach the wire to be visible, the other needed a unit with no home.
pkgs.runCommand "check-cli" { } ''
  set -eu
  work=$(mktemp -d)
  cd "$work"

  cli=${nix-mikrotik}/bin/nix-mikrotik

  cat > router.rsc <<'EOF'
  /interface wireguard
  set name=wg.luninet private-key=__MIKROTIK_SECRET_wg-private-key__
  /interface wifi security
  set name=default passphrase=__MIKROTIK_SECRET_wifi-password__
  EOF

  $cli list-secrets router.rsc > listed
  grep -qx wg-private-key listed
  grep -qx wifi-password listed
  [ "$(wc -l < listed)" -eq 2 ]

  # ------------------------------------------------------- how a value reads --
  # A value that cannot be anything but one bare token is left bare ...
  printf 'sekret-key' > wg-private-key
  printf 'sekret-pass' > wifi-password
  $cli secretize router.rsc -o out.rsc --secrets-dir .
  grep -q 'private-key=sekret-key' out.rsc
  grep -q 'passphrase=sekret-pass' out.rsc
  ! grep -q '__MIKROTIK_SECRET_' out.rsc

  # ... and the rendered copy is not world-readable.
  [ "$(stat -c %a out.rsc)" = "600" ]

  # A base64 value -- always a trailing `=` -- has to come out quoted, or the
  # device refuses the whole script while `deploy` looks like it worked.
  printf 'QUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUE=' > wg-private-key
  $cli secretize router.rsc -o base64.rsc --secrets-dir .
  grep -q 'private-key="QUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUE="' base64.rsc

  # The three characters RouterOS gives meaning to inside a quoted string are
  # escaped, exactly once. The rendered file is shell text, so this is not JSON
  # quoting: the bytes in escaped.rsc are  passphrase="a\"b\\c\$d"
  printf 'a"b\\c$d' > wifi-password
  $cli secretize router.rsc -o escaped.rsc --secrets-dir .
  grep -qF 'passphrase="a\"b\\c\$d"' escaped.rsc

  # A value with a newline cannot be one line at all; refusing is the only
  # honest answer.
  printf 'two\nlines' > wifi-password
  if $cli secretize router.rsc -o newline.rsc --secrets-dir . 2>err-nl; then
    echo "secretize accepted a value containing a newline" >&2
    exit 1
  fi
  grep -q 'contains a newline' err-nl
  printf 'sekret-pass' > wifi-password

  # 0600 holds for a destination that already exists too: the mode passed to
  # open(2) applies only when the file is created.
  printf 'sekret-key' > wg-private-key
  : > existing.rsc
  chmod 644 existing.rsc
  $cli secretize router.rsc -o existing.rsc --secrets-dir .
  [ "$(stat -c %a existing.rsc)" = "600" ]
  grep -q 'private-key=sekret-key' existing.rsc

  # A missing value must fail, not ship a placeholder.
  if $cli secretize router.rsc -o bad.rsc --secret wg-private-key=wg-private-key 2>err; then
    echo "secretize succeeded with an unresolved placeholder" >&2
    exit 1
  fi
  grep -q 'unresolved secret placeholders: wifi-password' err

  # -------------------------------------------------- declared generators ----
  # A configuration can say which script mints its secrets instead of the
  # deployer holding files. The manifest is what `lib.generators` renders and
  # what a flake publishes as `mikrotik-<router>-generators`; `generate` runs it
  # once, `secretize --generators` runs it if needed and substitutes the result.
  # The script here is pure shell so the check needs nothing but a shell.
  #
  # Each file carries the clan `relDir` it belongs at, and the tool writes it
  # there and nowhere else -- so a state directory this check builds is
  # byte-for-byte the layout `clan vars get` reads.
  cat > generators.json <<'EOF'
  [
    {
      "name": "wg-test-key",
      "files": [
        { "name": "privkey", "secret": true,  "relDir": "per-machine/chr-1/wg-test-key" },
        { "name": "pubkey",  "secret": false, "relDir": "shared/wg-test-key" }
      ],
      "runtimeInputs": [],
      "script": "printf 'sekret-key\\n' > $out/privkey; printf 'public-key\\n' > $out/pubkey"
    }
  ]
  EOF

  $cli generate generators.json --state-dir state > generated
  grep -qx 'wg-test-key/privkey' generated
  # The secret half lands under the router's own tree at 0400, the published
  # half in the shared tree at 0444 -- clan's modes, because clan's layout is
  # what a var store holds.
  [ "$(stat -c %a state/per-machine/chr-1/wg-test-key/privkey)" = "400" ]
  [ "$(stat -c %a state/shared/wg-test-key/pubkey)" = "444" ]
  grep -qx 'sekret-key' state/per-machine/chr-1/wg-test-key/privkey
  grep -qx 'public-key' state/shared/wg-test-key/pubkey
  # The published path is reported, so the caller can hand the public half over
  # without knowing where the state directory keeps it.
  grep -qxF 'published state/shared/wg-test-key/pubkey' generated

  cat > gen-router.rsc <<'EOF'
  /interface wireguard
  set name=wg.9600-baud.net private-key=__MIKROTIK_SECRET_wg-test-key/privkey__
  EOF

  # A generated value is substituted the same way a read one is ...
  $cli secretize gen-router.rsc -o gen-out.rsc --generators generators.json --generator-state-dir state
  grep -q 'private-key=sekret-key' gen-out.rsc

  # ... and the second run reads the value it minted, rather than minting a new
  # key that the peer already holding the old public key would not know.
  $cli generate generators.json --state-dir state > /dev/null
  grep -qx 'sekret-key' state/per-machine/chr-1/wg-test-key/privkey

  # A generator has to be kept somewhere: without a state directory there is
  # nowhere to put the value the next run would read.
  if $cli generate generators.json 2>err-state; then
    echo "generate ran without a state directory" >&2
    exit 1
  fi
  grep -q -- '--state-dir' err-state

  # Half a generator on disk is refused, not re-run and not topped up: the file
  # it did write is the half something else may already depend on. The two files
  # sit in two different trees here, so this also checks that the refusal clears
  # both of them rather than the one it happened to look at first.
  mkdir -p half/per-machine/chr-1/wg-test-key
  printf 'x' > half/per-machine/chr-1/wg-test-key/privkey
  if $cli generate generators.json --state-dir half 2>err-half; then
    echo "generate accepted a half-generated generator" >&2
    exit 1
  fi
  grep -q 'half-generated' err-half
  [ ! -e half/per-machine/chr-1/wg-test-key ]
  [ ! -e half/shared/wg-test-key ]

  # A script that does not write a file it declared is caught before anything is
  # kept -- otherwise the next run reads a directory that looks generated.
  cat > bad-generators.json <<'EOF'
  [
    {
      "name": "short-key",
      "files": [
        { "name": "privkey", "relDir": "per-machine/chr-1/short-key" },
        { "name": "pubkey",  "relDir": "per-machine/chr-1/short-key" }
      ],
      "runtimeInputs": [],
      "script": "printf 'x\\n' > $out/privkey"
    }
  ]
  EOF
  if $cli generate bad-generators.json --state-dir badstate 2>err-short; then
    echo "generate accepted a script that skipped a declared file" >&2
    exit 1
  fi
  grep -q 'did not write' err-short
  [ ! -e badstate/per-machine/chr-1/short-key ]

  # A manifest that does not say where a file belongs is refused: a default
  # would be a second spelling of the layout, and the two would drift into the
  # tool reading a value from a path clan never wrote.
  cat > norel-generators.json <<'EOF'
  [
    {
      "name": "no-dir",
      "files": [ { "name": "privkey", "secret": true } ],
      "runtimeInputs": [],
      "script": "printf 'x\\n' > $out/privkey"
    }
  ]
  EOF
  if $cli generate norel-generators.json --state-dir norelstate 2>err-norel; then
    echo "generate accepted a file with no relDir" >&2
    exit 1
  fi
  grep -q 'no relDir' err-norel

  # A relDir that points out of the state directory is refused before anything
  # is written, for the same reason the secret-file lookup refuses it: the state
  # directory is a boundary, not a suggestion.
  cat > escape-generators.json <<'EOF'
  [
    {
      "name": "escape",
      "files": [ { "name": "privkey", "secret": true, "relDir": "../outside" } ],
      "runtimeInputs": [],
      "script": "printf 'x\\n' > $out/privkey"
    }
  ]
  EOF
  if $cli generate escape-generators.json --state-dir escstate 2>err-esc; then
    echo "generate accepted a relDir outside the state directory" >&2
    exit 1
  fi
  grep -q 'not inside the state directory' err-esc
  [ ! -e outside/privkey ]

  # --------------------------------------------- values minted elsewhere ----
  # A value the configuration does not mint is declared, not generated: the
  # manifest carries a `varFiles` map from the placeholder name to the path the
  # value sits at under --secrets-dir, and the tool reads it from there. This is
  # the shape a controller-minted WireGuard key arrives in -- its file is under a
  # clan generator's directory, so the name and the path differ.
  #
  # The manifest is an object rather than a bare list when `varFiles` is
  # involved, and `generators` is still a list, so both forms have to read.
  cat > handoff-generators.json <<'EOF'
  {
    "generators": [],
    "varFiles": {
      "mesh-chr1-private-key": {
        "path": "per-machine/chr-1/mikrotik-lab-peers/chr1",
        "description": "chr1's tunnel key, minted on the controller"
      }
    }
  }
  EOF
  cat > handoff.rsc <<'EOF'
  /interface wireguard
  set name=wg.mesh private-key=__MIKROTIK_SECRET_mesh-chr1-private-key__
  EOF
  mkdir -p vars/per-machine/chr-1/mikrotik-lab-peers
  printf 'mesh-key' > vars/per-machine/chr-1/mikrotik-lab-peers/chr1
  $cli secretize handoff.rsc -o handoff-out.rsc \
    --secrets-dir vars --generators handoff-generators.json
  grep -q 'private-key=mesh-key' handoff-out.rsc
  ! grep -q '__MIKROTIK_SECRET_' handoff-out.rsc

  # `generate` reads the same manifest: an object with no generators is an
  # answer, not a parse error.
  if $cli generate handoff-generators.json --state-dir handoff-state 2>err-handoff; then
    :
  else
    echo "generate rejected a manifest with a varFiles section" >&2
    cat err-handoff >&2
    exit 1
  fi

  # A hand-off whose file is not there names the path it looked at, because the
  # next thing the operator does is go and put the file there.
  rm vars/per-machine/chr-1/mikrotik-lab-peers/chr1
  if $cli secretize handoff.rsc -o missing-out.rsc \
    --secrets-dir vars --generators handoff-generators.json 2>err-handoff-missing; then
    echo "secretize substituted a hand-off whose file does not exist" >&2
    exit 1
  fi
  grep -q 'mikrotik.varFiles' err-handoff-missing
  grep -q 'mikrotik-lab-peers/chr1' err-handoff-missing
  [ ! -e missing-out.rsc ]

  # A varFiles path that would walk out of --secrets-dir is refused where it is
  # declared, not joined onto the directory.
  cat > escape-varfiles.json <<'EOF'
  { "generators": [], "varFiles": { "mesh-chr1-private-key": { "path": "per-machine/../../outside" } } }
  EOF
  if $cli secretize handoff.rsc -o escape-out.rsc \
    --secrets-dir vars --generators escape-varfiles.json 2>err-varfiles-esc; then
    echo "secretize accepted a varFiles path outside --secrets-dir" >&2
    exit 1
  fi
  grep -q 'not a path under the vars directory' err-varfiles-esc

  # clan's own store keeps a var in a directory: `secret` holds a secret,
  # `value` a published one. So a deploy can be pointed at the per-machine tree
  # and the placeholder name is the path -- no restatement of the layout.
  mkdir -p varstore/per-machine/chr-1/wg-keys/wg.layer
  printf 'clan-key' > varstore/per-machine/chr-1/wg-keys/wg.layer/secret
  printf 'clan-pub' > varstore/per-machine/chr-1/wg-keys/wg.layer/value
  cat > clanlayout.rsc <<'EOF'
  /interface wireguard
  set name=wg.layer private-key=__MIKROTIK_SECRET_wg-keys/wg.layer__
  EOF
  $cli secretize clanlayout.rsc -o clanlayout.out \
    --secrets-dir varstore/per-machine/chr-1
  grep -q 'private-key=clan-key' clanlayout.out
  ! grep -q '__MIKROTIK_SECRET_' clanlayout.out

  # ---------------------------------------------------------------- names ----
  # The name is also the file name the value is read from, so a name that is not
  # one is refused. This is the half modules/base.nix asserts at build time, for
  # a script the tool was handed rather than one it rendered -- and it is what
  # makes the failure visible before a deploy instead of as a literal
  # placeholder on a router.
  cat > oddname.rsc <<'EOF'
  /interface wireguard
  set name=wg.luninet private-key=__MIKROTIK_SECRET_wg+key__
  EOF
  if $cli list-secrets oddname.rsc 2>err-odd; then
    echo "list-secrets accepted a name that is not a file name" >&2
    exit 1
  fi
  grep -q 'not usable as a file name' err-odd

  # ... and a name that would walk out of --secrets-dir is refused before it is
  # joined onto the directory: `./secrets/../outside` used to be read.
  mkdir -p secrets
  printf 'outside-value' > outside
  cat > trav.rsc <<'EOF'
  /interface wireguard
  set name=wg.luninet private-key=__MIKROTIK_SECRET_../outside__
  EOF
  if $cli secretize trav.rsc -o trav.out.rsc --secrets-dir ./secrets 2>err-trav; then
    echo "secretize read a secret file from outside --secrets-dir" >&2
    exit 1
  fi
  grep -q 'not usable as a file name' err-trav
  ! test -e trav.out.rsc

  # ------------------------------------------------ where ssh may write -------
  # `--known-hosts` is what lets a caller with no operator home -- a unit
  # running as root under `ProtectHome`, where ssh's `~` (which it resolves
  # through the passwd entry, not `$HOME`) is nowhere ssh can write -- say where
  # a host key may be recorded, so that `accept-new` pins rather than starting
  # from nothing on every deploy. Offered by both subcommands that speak ssh;
  # the argv it produces is asserted below, against the module.
  $cli deploy --help | grep -q -- '--known-hosts'
  $cli diff --help | grep -q -- '--known-hosts'

  # ------------------------------------------------ what a failure claims ----
  # A failed import cannot be told apart from a partial one: a parse abort
  # applies nothing, a runtime abort has applied a prefix. So the message must
  # not tell the operator the device is unchanged -- that invites a re-run, and
  # RouterOS has no reconciliation, so a repeated `add` makes a second object
  # (measured on 7.15.3: identity set and one filter rule applied, then a
  # duplicate after the invited re-deploy). Asserted against the function the
  # tool actually calls, so a rewording that drifts back fails here.
  #
  # The two sections below it are the same shape: the deploy guard and the
  # transport's argv, asserted on the module rather than on a device, because
  # both are decisions the tool makes before it opens a socket.
  ${pkgs.python3}/bin/python3 - ${cliSource} <<'PY'
  import contextlib
  import importlib.util
  import io
  import os
  import sys
  import tempfile
  from importlib.machinery import SourceFileLoader

  spec = importlib.util.spec_from_loader(
      "nix_mikrotik", SourceFileLoader("nix_mikrotik", sys.argv[1]))
  module = importlib.util.module_from_spec(spec)
  spec.loader.exec_module(module)

  message = module.import_failed(
      "script,error script error: value of range must have ip address before '/'")
  lowered = message.lower()
  assert "kept its previous configuration" not in lowered, message
  assert "may already have been applied" in lowered, message
  assert "prefix" in lowered, message
  assert "re-run" in lowered, message
  print("failed-import message claims a possible prefix and warns against a blind re-run")

  # ------------------------------------------- where ssh records a host key ----
  # The transport builds its own ssh/scp argv, so the selectable known_hosts is
  # asserted on the argv: a caller that has no operator home can name the file,
  # and the *semantics* of accept-new are untouched (the file changes, nothing
  # else does).
  work = tempfile.mkdtemp()
  known_hosts = os.path.join(work, "known_hosts")
  talk = []

  def recording_run(argv, *args, **kwargs):
      talk.append(list(argv))
      return module.subprocess.CompletedProcess(argv, 0, "", "")

  module.subprocess.run = recording_run

  router = module.Router("192.0.2.1", known_hosts=known_hosts)
  router.run("/system identity print")
  router.upload(os.path.join(work, "router-config.rsc"))
  assert len(talk) == 2, talk
  for argv in talk:
      assert f"UserKnownHostsFile={known_hosts}" in argv, argv
      assert "StrictHostKeyChecking=accept-new" in argv, argv
      assert "BatchMode=yes" in argv, argv
      assert argv.index("-o") < argv.index(f"UserKnownHostsFile={known_hosts}"), argv

  # Omitting it changes nothing: no option, so the operator's ssh behaves
  # exactly as it did before this flag existed.
  default = module.Router("192.0.2.1")._common()
  assert not any("UserKnownHostsFile" in arg for arg in default), default

  # A path ssh could not write is refused up front. ssh treats a failed append
  # as a warning, so the alternative is a deploy that looks pinned and is not.
  try:
      module.Router("192.0.2.1", known_hosts="/nonexistent-dir/known_hosts")
  except module.ToolError as exc:
      assert "not a directory" in str(exc), str(exc)
  else:
      raise AssertionError("Router accepted a known_hosts path ssh cannot write")

  # Both subcommands that speak ssh take it, and it reaches the Router.
  parser = module.build_parser()
  for command in ("deploy", "diff"):
      ns = parser.parse_args(
          [command, "router.rsc", "--host", "192.0.2.1", "--known-hosts", known_hosts])
      assert ns.known_hosts == known_hosts, ns
  assert parser.parse_args(["deploy", "router.rsc", "--host", "192.0.2.1"]).known_hosts is None
  print("known_hosts is selectable on the argv, and accept-new is unchanged")

  # ---------------------------------------- what a refusal is allowed to do ----
  # `deploy --reset` without `--yes` must be refused *before* the secretized
  # script is uploaded: it used to be refused only after `Router.upload()` had
  # put it on the device, so the confirmation was doing nothing of what it read
  # as. Both halves are asserted here -- that the refusal reaches no transport,
  # and that `--yes` is what changes that.
  script = os.path.join(work, "router.rsc")
  with open(script, "w") as handle:
      handle.write("/interface wireguard\n"
                   "set name=wg.luninet private-key=__MIKROTIK_SECRET_wg-private-key__\n")
  with open(os.path.join(work, "wg-private-key"), "w") as handle:
      handle.write("QUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUE=")

  talk.clear()
  err = io.StringIO()
  with contextlib.redirect_stderr(err):
      rc = module.main(["deploy", script, "--host", "192.0.2.1", "--reset",
                        "--secrets-dir", work])
  assert rc == 2, rc
  assert "pass --yes" in err.getvalue(), err.getvalue()
  assert talk == [], f"a refused --reset deploy reached the transport: {talk}"

  # ... and it is refused before the secrets are read, too: with no value
  # supplied at all the message is still the confirmation, not "unresolved".
  err = io.StringIO()
  with contextlib.redirect_stderr(err):
      rc = module.main(["deploy", script, "--host", "192.0.2.1", "--reset"])
  assert rc == 2, rc
  assert "pass --yes" in err.getvalue(), err.getvalue()
  assert "unresolved" not in err.getvalue(), err.getvalue()

  # The control: confirmed, it does reach the transport. `upload` is where the
  # secretized script would leave the machine, so that is where this stops.
  uploaded = []

  def record_upload(self, local):
      uploaded.append(local)
      raise module.ToolError("stopped at upload for the test")

  module.Router.upload = record_upload
  err = io.StringIO()
  with contextlib.redirect_stderr(err):
      rc = module.main(["deploy", script, "--host", "192.0.2.1", "--reset",
                        "--yes", "--secrets-dir", work])
  assert rc == 2 and "stopped at upload" in err.getvalue(), err.getvalue()
  assert uploaded, "a confirmed --reset deploy never reached the upload"
  print("--reset is refused before upload without --yes, and passes the guard with it")
  PY


  # ------------------------------------------- secrets that are not files here --
  # `--secret-command`: the value is fetched, not stored. A host that must not
  # hold the router's keys passes a command (sops, clan vars, pass) and the
  # plaintext exists only inside this process.
  $cli secretize router.rsc -o cmd.rsc --secret-command 'printf %s "cmd-{name}"'
  grep -q 'private-key=cmd-wg-private-key' cmd.rsc
  grep -q 'passphrase=cmd-wifi-password' cmd.rsc

  # A command that fails is a refusal, not an empty value.
  if $cli secretize router.rsc -o cmd-bad.rsc --secret-command 'false'; then
    echo "a failing --secret-command was accepted"; exit 1
  fi
  # ... and one that prints nothing is the same refusal.
  if $cli secretize router.rsc -o cmd-empty.rsc --secret-command 'true'; then
    echo "a silent --secret-command was accepted"; exit 1
  fi

  # An explicit --secret wins over the command: the cheap path does not need it.
  printf 'explicit-value' > explicit
  $cli secretize router.rsc -o explicit.rsc \
    --secret wg-private-key=explicit --secret-command 'printf %s "cmd-{name}"'
  grep -q 'private-key=explicit-value' explicit.rsc
  grep -q 'passphrase=cmd-wifi-password' explicit.rsc

  # `--sops-file`: the tool decrypts each entry itself. `sops` is stubbed here --
  # the point under test is the argv and the substitution, not sops.
  mkdir -p stub
  # sops -d FILE --extract <pattern>; the stub prints the name it was asked for.
  printf '%s\n' '#!/bin/sh' 'printf "sops-%s" "$(printf %s "$4" | tr -d "[]{}\\\"")"' > stub/sops
  chmod +x stub/sops
  PATH=$PWD/stub:$PATH $cli secretize router.rsc -o sops.rsc \
    --sops-file secrets.yaml --sops-key-file /var/lib/sops-nix/key.txt
  grep -q 'private-key=sops-wg-private-key' sops.rsc
  grep -q 'passphrase=sops-wifi-password' sops.rsc

  # ------------------------------------------------ generators: minted, once --
  # `--secret-generator` creates a value that does not exist yet, and
  # `--generator-state-dir` keeps it -- a generator that ran on every deploy
  # would mint a second key and break the tunnel it was minting for.
  $cli secretize router.rsc -o gen.rsc \
    --secret-generator 'printf gen-{name}' --generator-state-dir gen-state
  grep -q 'private-key=gen-wg-private-key' gen.rsc
  [ "$(stat -c %a gen-state/wg-private-key)" = "600" ]

  # The stored value is reused: the generator below would fail if it ran.
  $cli secretize router.rsc -o gen2.rsc \
    --secret-generator 'false' --generator-state-dir gen-state
  grep -q 'private-key=gen-wg-private-key' gen2.rsc

  # ---------------------------- generators: the clan interface, end to end ----
  # A generator is a script plus the files it declares, and `generate` is what
  # runs it once and keeps what it wrote. The cases below are the parts of
  # clan's interface that a port gets subtly wrong: the layout of the state
  # directory, `$in`, prompts, the validation hash, and the two flags a file
  # carries (`deploy` and `mode`).
  mkdir -p man

  cat > man/wg.json <<'JSON'
  [
    {
      "name": "wg-key",
      "files": [
        { "name": "privkey", "secret": true, "relDir": "per-machine/r1/wg-key" },
        { "name": "pubkey", "secret": false, "relDir": "per-machine/r1/wg-key" },
        { "name": "seed", "secret": false, "deploy": false, "relDir": "per-machine/r1/wg-key" }
      ],
      "runtimeInputs": [],
      "script": "printf 'priv-A\\n' > $out/privkey; printf 'pub-A\\n' > $out/pubkey; printf 'seed-A\\n' > $out/seed"
    }
  ]
  JSON

  $cli generate man/wg.json --state-dir st1 > generated
  grep -qx 'wg-key/privkey' generated
  # The public half is offered as a path, not a value: it is meant to be handed
  # to a peer, and the peer reads it off a machine that already has the state.
  grep -q '^published st1/per-machine/r1/wg-key/pubkey$' generated
  if grep -q 'seed' generated; then
    echo "an intermediate (deploy=false) was offered as a value"; exit 1
  fi
  [ "$(cat st1/per-machine/r1/wg-key/privkey)" = "priv-A" ]
  [ "$(cat st1/per-machine/r1/wg-key/pubkey)" = "pub-A" ]
  [ "$(stat -c %a st1/per-machine/r1/wg-key/privkey)" = "400" ]
  [ "$(stat -c %a st1/per-machine/r1/wg-key/pubkey)" = "444" ]
  [ "$(stat -c %a st1/per-machine/r1/wg-key/seed)" = "400" ]

  # The second run reads what the first wrote: the script below would fail, and
  # a generator that re-ran on every deploy would mint a second key for a tunnel
  # whose peer already has the first.
  cat > man/wg-dead.json <<'JSON'
  [
    {
      "name": "wg-key",
      "files": [
        { "name": "privkey", "secret": true, "relDir": "per-machine/r1/wg-key" },
        { "name": "pubkey", "secret": false, "relDir": "per-machine/r1/wg-key" },
        { "name": "seed", "secret": false, "deploy": false, "relDir": "per-machine/r1/wg-key" }
      ],
      "runtimeInputs": [],
      "script": "exit 1"
    }
  ]
  JSON
  $cli generate man/wg-dead.json --state-dir st1 > generated-again
  grep -qx 'wg-key/privkey' generated-again
  [ "$(cat st1/per-machine/r1/wg-key/privkey)" = "priv-A" ]

  # `$in/<generator>/<file>` is how one generator reads another's output.
  cat > man/peer.json <<'JSON'
  [
    {
      "name": "wg-key",
      "files": [
        { "name": "privkey", "secret": true, "relDir": "per-machine/r1/wg-key" },
        { "name": "pubkey", "secret": false, "relDir": "per-machine/r1/wg-key" },
        { "name": "seed", "secret": false, "deploy": false, "relDir": "per-machine/r1/wg-key" }
      ],
      "runtimeInputs": [],
      "script": "printf 'priv-A\\n' > $out/privkey; printf 'pub-A\\n' > $out/pubkey; printf 'seed-A\\n' > $out/seed"
    },
    {
      "name": "peer",
      "dependencies": [ "wg-key" ],
      "files": [
        { "name": "psk", "secret": true, "relDir": "per-machine/r1/peer" }
      ],
      "runtimeInputs": [],
      "script": "printf 'psk-of-%s\\n' \"$(cat $in/wg-key/pubkey)\" > $out/psk"
    }
  ]
  JSON
  $cli generate man/peer.json --state-dir st-in > generated-peer
  grep -qx 'peer/psk' generated-peer
  [ "$(cat st-in/per-machine/r1/peer/psk)" = "psk-of-pub-A" ]

  # The dependency has to be declared *before* the generator that reads it: the
  # manifest is the order, so the tool never has to sort a graph.
  cat > man/peer-first.json <<'JSON'
  [
    {
      "name": "peer",
      "dependencies": [ "wg-key" ],
      "files": [
        { "name": "psk", "secret": true, "relDir": "per-machine/r1/peer" }
      ],
      "runtimeInputs": [],
      "script": "printf 'psk-of-%s\\n' \"$(cat $in/wg-key/pubkey)\" > $out/psk"
    },
    {
      "name": "wg-key",
      "files": [
        { "name": "privkey", "secret": true, "relDir": "per-machine/r1/wg-key" },
        { "name": "pubkey", "secret": false, "relDir": "per-machine/r1/wg-key" },
        { "name": "seed", "secret": false, "deploy": false, "relDir": "per-machine/r1/wg-key" }
      ],
      "runtimeInputs": [],
      "script": "printf 'priv-A\\n' > $out/privkey; printf 'pub-A\\n' > $out/pubkey; printf 'seed-A\\n' > $out/seed"
    }
  ]
  JSON
  if $cli generate man/peer-first.json --state-dir st-order 2> err-order; then
    echo "a generator whose dependency is declared after it was accepted"; exit 1
  fi
  grep -q 'depends on wg-key, which this manifest does not declare before it' err-order

  # `$in` is a copy: a script that writes to it cannot reach back into the state
  # directory and change a value another generator already published.
  cat > man/tamper.json <<'JSON'
  [
    {
      "name": "wg-key",
      "files": [
        { "name": "privkey", "secret": true, "relDir": "per-machine/r1/wg-key" },
        { "name": "pubkey", "secret": false, "relDir": "per-machine/r1/wg-key" },
        { "name": "seed", "secret": false, "deploy": false, "relDir": "per-machine/r1/wg-key" }
      ],
      "runtimeInputs": [],
      "script": "printf 'priv-A\\n' > $out/privkey; printf 'pub-A\\n' > $out/pubkey; printf 'seed-A\\n' > $out/seed"
    },
    {
      "name": "snoop",
      "dependencies": [ "wg-key" ],
      "files": [
        { "name": "seen", "secret": true, "deploy": false, "relDir": "per-machine/r1/snoop" }
      ],
      "runtimeInputs": [],
      "script": "chmod 600 $in/wg-key/pubkey; printf 'tampered' > $in/wg-key/pubkey; cat $in/wg-key/pubkey > $out/seen"
    }
  ]
  JSON
  $cli generate man/tamper.json --state-dir st-in > /dev/null
  [ "$(cat st-in/per-machine/r1/wg-key/pubkey)" = "pub-A" ]
  [ "$(cat st-in/per-machine/r1/snoop/seen)" = "tampered" ]

  # Prompts: a value a human knows and the machine cannot mint.
  cat > man/ask.json <<'JSON'
  [
    {
      "name": "psk2",
      "files": [
        { "name": "passphrase", "secret": true, "relDir": "per-machine/r1/psk2" }
      ],
      "prompts": [
        { "name": "passphrase", "description": "tunnel passphrase", "persist": true }
      ],
      "runtimeInputs": [],
      "script": "cat $prompts/passphrase > $out/passphrase"
    }
  ]
  JSON

  # No answer and no terminal is a refusal naming all three ways in -- never an
  # empty value written into a key.
  if $cli generate man/ask.json --state-dir st-ask 2> err-ask; then
    echo "a prompt with no value was accepted"; exit 1
  fi
  grep -q -- '--prompt NAME=VALUE' err-ask
  grep -q -- '--prompts-dir' err-ask
  grep -q 'terminal' err-ask
  [ ! -e st-ask/per-machine/r1/psk2/passphrase ]

  $cli generate man/ask.json --state-dir st-ask --prompt passphrase=hunter2 > /dev/null
  [ "$(cat st-ask/per-machine/r1/psk2/passphrase)" = "hunter2" ]

  mkdir -p prompts
  printf 'from-dir' > prompts/passphrase
  $cli generate man/ask.json --state-dir st-dir --prompts-dir prompts > /dev/null
  [ "$(cat st-dir/per-machine/r1/psk2/passphrase)" = "from-dir" ]

  # `--prompt` wins over the directory, so one value can be overridden without
  # rewriting the directory a deploy unit was handed.
  $cli generate man/ask.json --state-dir st-both --prompts-dir prompts \
    --prompt passphrase=cli-wins > /dev/null
  [ "$(cat st-both/per-machine/r1/psk2/passphrase)" = "cli-wins" ]

  # A changed validation hash re-runs the generator -- and a persisted prompt
  # answers it from the value the first run wrote, without asking again.
  cat > man/ask2.json <<'JSON'
  [
    {
      "name": "psk2",
      "files": [
        { "name": "passphrase", "secret": true, "relDir": "per-machine/r1/psk2" }
      ],
      "prompts": [
        { "name": "passphrase", "description": "tunnel passphrase", "persist": true }
      ],
      "validation": "test -n yes",
      "validationHash": "def456",
      "runtimeInputs": [],
      "script": "printf '%s-v2\\n' \"$(cat $prompts/passphrase)\" > $out/passphrase"
    }
  ]
  JSON
  $cli generate man/ask2.json --state-dir st-ask > /dev/null
  [ "$(cat st-ask/per-machine/r1/psk2/passphrase)" = "hunter2-v2" ]

  # The control: same hash, a script that would fail -- read, not re-run. The
  # hash is the definition's fingerprint, and a file that exists is not evidence
  # that it is still the file the definition describes.
  cat > man/ask2-dead.json <<'JSON'
  [
    {
      "name": "psk2",
      "files": [
        { "name": "passphrase", "secret": true, "relDir": "per-machine/r1/psk2" }
      ],
      "prompts": [
        { "name": "passphrase", "description": "tunnel passphrase", "persist": true }
      ],
      "validation": "test -n yes",
      "validationHash": "def456",
      "runtimeInputs": [],
      "script": "exit 1"
    }
  ]
  JSON
  $cli generate man/ask2-dead.json --state-dir st-ask > /dev/null
  [ "$(cat st-ask/per-machine/r1/psk2/passphrase)" = "hunter2-v2" ]

  # `mode` and `deploy`: a generated secret can be handed to a service on the
  # deploying machine (0440), and a file that only another generator reads is
  # not part of the set a menu cell may substitute.
  cat > man/carrier.json <<'JSON'
  [
    {
      "name": "creds",
      "files": [
        { "name": "token", "secret": true, "deploy": false, "relDir": "per-machine/r1/creds" },
        { "name": "svc", "secret": true, "mode": "0440", "relDir": "per-machine/r1/creds" },
        { "name": "apikey", "secret": true, "relDir": "per-machine/r1/creds" }
      ],
      "runtimeInputs": [],
      "script": "echo tok > $out/token; echo svc > $out/svc; echo api > $out/apikey"
    }
  ]
  JSON
  $cli generate man/carrier.json --state-dir st-carrier > carrier
  grep -qx 'creds/svc' carrier
  grep -qx 'creds/apikey' carrier
  if grep -q 'creds/token' carrier; then
    echo "an intermediate was offered as a value"; exit 1
  fi
  [ "$(stat -c %a st-carrier/per-machine/r1/creds/token)" = "400" ]
  [ "$(stat -c %a st-carrier/per-machine/r1/creds/svc)" = "440" ]
  [ "$(stat -c %a st-carrier/per-machine/r1/creds/apikey)" = "400" ]

  printf '%s\n' '/interface wireguard' \
    'set name=wg.gen private-key=__MIKROTIK_SECRET_creds/svc__' > carrier-ok.rsc
  $cli secretize carrier-ok.rsc -o carrier-ok.out \
    --generators man/carrier.json --generator-state-dir st-carrier
  grep -q 'private-key=svc' carrier-ok.out

  # An intermediate is another generator's input, never a script's value.
  printf '%s\n' '/interface wireguard' \
    'set name=wg.gen private-key=__MIKROTIK_SECRET_creds/token__' > carrier-bad.rsc
  if $cli secretize carrier-bad.rsc -o carrier-bad.out \
       --generators man/carrier.json --generator-state-dir st-carrier 2> err-carrier; then
    echo "an intermediate was substituted into a script"; exit 1
  fi
  grep -q 'unresolved secret placeholders: creds/token' err-carrier

  # A manifest with nowhere to keep what it mints is refused: the next deploy
  # would mint a second key for the same tunnel.
  if $cli secretize carrier-ok.rsc -o nope.out --generators man/carrier.json 2> err-nostate; then
    echo "--generators without --generator-state-dir was accepted"; exit 1
  fi
  grep -q 'needs --generator-state-dir' err-nostate


  # ------------------------------------------------- the deploy is a patch ----
  # `deploy` applies the difference between the device's `/export` and the
  # script, not the script. The device half of that is checked on a CHR
  # (`checks.chr-deploy`); what is checked here is the half that is a decision
  # before anything is sent -- which flags reach the differ, what an empty plan
  # is, and what a differ that is missing or cannot parse is allowed to say.
  $cli deploy --help | grep -q -- '--prune'
  $cli deploy --help | grep -q -- '--check'
  $cli deploy --help | grep -q -- '--import-whole'
  $cli deploy --help | grep -q -- '--allow-partial'
  $cli deploy --help | grep -q -- '--command-timeout'
  ${pkgs.python3}/bin/python3 - ${cliSource} <<'PY'
  import contextlib
  import importlib.util
  import io
  import os
  import stat
  import sys
  import tempfile
  from importlib.machinery import SourceFileLoader

  spec = importlib.util.spec_from_loader(
      "nix_mikrotik", SourceFileLoader("nix_mikrotik", sys.argv[1]))
  module = importlib.util.module_from_spec(spec)
  spec.loader.exec_module(module)

  # ------------------------------------------- what counts as an operation ----
  # A patch is mostly comments: the header, the notes, and every operation that
  # was withheld. A file with no command left is a deploy with nothing to do, and
  # sending it would only prove the sentinel works.
  assert module.patch_commands(
      "# header\n/system identity\nset name=x\n"
      "# withheld: remove name=stale\n:log info \"marker\"\n\n") == ["set name=x"]
  assert module.patch_commands("# nothing to do\n") == []

  # ------------------------------------------------ what the differ is asked --
  # The mode is the whole safety property: `--upsert` withholds every operation
  # that deletes, and `--prune` is the one thing that turns it off. The sentinel
  # travels with the patch because RouterOS exits 0 for an import it refused.
  calls = []

  class Proc:
      def __init__(self, stdout=""):
          self.returncode = 0
          self.stdout = stdout
          self.stderr = ""

  def fake_run(argv, *args, **kwargs):
      calls.append(list(argv))
      return Proc("  3 operations: 0 add, 2 set, 0 remove, 0 replace, 0 move, 1 unperformable\n"
                  if argv[1] == "diff" else "set name=x\n:log info \"marker\"\n")

  module.subprocess.run = fake_run
  os.environ["NIX_MIKROTIK_RSC"] = "fake-rsc"

  class Router:
      def export(self):
          return "/system identity\nset name=old\n"

  work = tempfile.mkdtemp()
  patch, report = module.render_patch(Router(), "/system identity\nset name=x\n",
                                      work, prune=False, marker="marker")
  assert [c[0] for c in calls] == ["fake-rsc", "fake-rsc"], calls
  assert calls[0][1] == "diff" and "--upsert" in calls[0], calls[0]
  assert calls[1][1] == "patch" and "--upsert" in calls[1], calls[1]
  assert "--sentinel" in calls[1] and "marker" in calls[1], calls[1]
  assert "0 add" in report, report
  # Both sides of the diff are written 0600: one holds the secretized target,
  # the other the device's configuration.
  for name in ("live.rsc", "target.rsc"):
      mode = stat.S_IMODE(os.stat(os.path.join(work, name)).st_mode)
      assert mode == 0o600, (name, oct(mode))

  # `--prune` is the only thing that turns deletions back on.
  calls.clear()
  module.render_patch(Router(), "/system identity\nset name=x\n", work,
                      prune=True, marker="marker")
  assert "--upsert" not in calls[0], calls[0]
  assert "--upsert" not in calls[1], calls[1]

  # ------------------------------------------------ what a failure may say ----
  # A differ that is not there is a packaging problem, and the message has to
  # say which binary is missing rather than raising FileNotFoundError.
  def missing(argv, *args, **kwargs):
      raise FileNotFoundError(2, "No such file or directory", argv[0])

  module.subprocess.run = missing
  os.environ["NIX_MIKROTIK_RSC"] = "no-such-rsc"
  try:
      module.run_rsc(["diff", "a", "b"], "the difference")
  except module.ToolError as exc:
      assert "not on PATH" in str(exc) and "no-such-rsc" in str(exc), str(exc)
  else:
      raise AssertionError("a missing rsc was not reported")

  # A file the differ cannot parse is exit 2, and for a device's /export the
  # answer is the path that does not read it: `--import-whole`.
  def unparseable(argv, *args, **kwargs):
      proc = Proc()
      proc.returncode = 2
      proc.stderr = "rsc: live.rsc: line 3: unexpected token"
      return proc

  module.subprocess.run = unparseable
  try:
      module.run_rsc(["diff", "a", "b"], "the difference")
  except module.ToolError as exc:
      assert "--import-whole" in str(exc), str(exc)
      assert "unexpected token" in str(exc), str(exc)
  else:
      raise AssertionError("a parse failure was not reported")

  # ------------------------------------------ what the plan admits it cannot do --
  # A deploy that reports success for a device it only partly configured is the
  # one failure an operator cannot see, so `rsc` marks such a section
  # `UNAPPLIED:` and `deploy` refuses on it. The three shapes are measured: a
  # line the differ cannot model, a menu with no stable handle that would have to
  # be rebuilt, and an object whose re-creation needs a property to disappear.
  report = (
      "  exact: yes\n"
      "/ip firewall filter  (positional)\n"
      "  note: UNAPPLIED: this menu has no stable handle, so reaching the target "
      "means rebuilding it -- 4 removal(s) withheld\n"
      "/ip pool  (keyed)\n"
      "  note: 1 removal(s) withheld: the device keeps what the target does not declare\n")
  gaps = module.unapplied(report)
  assert len(gaps) == 1, gaps
  assert "no stable handle" in gaps[0], gaps
  assert module.unapplied("/ip pool\n  note: 1 removal(s) withheld\n") == []

  # "Converged" is the one line a drift gate branches on: it is present only
  # when every operation left writes a value `/export` cannot show. Counting
  # operations instead made a correct device report `2 set` forever.
  assert module.converged(
      "  2 operations: 0 add, 2 set, 0 remove, 0 replace, 0 move, 0 unperformable\n"
      "  converged: the device holds this configuration; 2 value(s) /export "
      "cannot show are re-asserted\n")
  assert not module.converged(
      "  1 operations: 0 add, 1 set, 0 remove, 0 replace, 0 move, 0 unperformable\n")

  # An empty script is a broken render, not a request to empty the device.
  empty = os.path.join(work, "empty.rsc")
  with open(empty, "w") as handle:
      handle.write("# Generated by nix-mikrotik -- do not edit.\n")
  err = io.StringIO()
  with contextlib.redirect_stderr(err):
      rc = module.main(["deploy", empty, "--host", "192.0.2.1"])
  assert rc == 2, rc
  assert "no commands" in err.getvalue(), err.getvalue()

  # ------------------------------------------- the uploaded name is per run ----
  # A device has one flat file store, so a fixed `router-config.rsc` is shared by
  # every deploy to it: two runs race, and one's cleanup can delete the file the
  # other is importing. The name carries the run's marker, which is also what
  # makes a leftover attributable.
  a, b = module.remote_name("aaa"), module.remote_name("bbb")
  assert a != b, (a, b)
  assert a.endswith(".rsc") and b.endswith(".rsc"), (a, b)
  assert "/" not in a and a.startswith("router-config-"), a

  # Cleanup is a `finally`, so a SIGKILLed deploy leaves the secretized script
  # on the device. Nothing sweeps it (that would delete a concurrent run's file),
  # so the next run names it.
  assert module.stale_warning([]) is None
  warned = module.stale_warning(["router-config-deadbeef.rsc"])
  assert "interrupted" in warned and "router-config-deadbeef.rsc" in warned, warned
  assert "secrets" in warned or "secret" in warned, warned

  # --------------------------------------------- --check sends nothing --------
  # `--check` is the first run against a live router: the plan, and no transport
  # at all. The whole-script path has no plan to show, so it is refused.
  print("the deploy is a patch: mode, empty plan, and the failures it may name")
  PY
  touch $out
''
