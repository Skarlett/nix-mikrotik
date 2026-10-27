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

  # ------------------------------------------------ what a failure claims ----
  # A failed import cannot be told apart from a partial one: a parse abort
  # applies nothing, a runtime abort has applied a prefix. So the message must
  # not tell the operator the device is unchanged -- that invites a re-run, and
  # RouterOS has no reconciliation, so a repeated `add` makes a second object
  # (measured on 7.15.3: identity set and one filter rule applied, then a
  # duplicate after the invited re-deploy). Asserted against the function the
  # tool actually calls, so a rewording that drifts back fails here.
  ${pkgs.python3}/bin/python3 - ${cliSource} <<'PY'
  import importlib.util
  import sys
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
  PY

  touch $out
''