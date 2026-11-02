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

  touch $out
''
