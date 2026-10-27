{ pkgs, nix-mikrotik }:

# The deploy tool's contract, minus the device: placeholders are enumerated,
# substituted from files, and an unresolved one is a hard failure rather than a
# script with a literal __MIKROTIK_SECRET_… in it.
pkgs.runCommand "check-cli" { } ''
  set -eu
  work=$(mktemp -d)
  cd "$work"

  cat > router.rsc <<'EOF'
  /interface wireguard
  set name=wg.luninet private-key=__MIKROTIK_SECRET_wg-private-key__
  /interface wifi security
  set name=default passphrase=__MIKROTIK_SECRET_wifi-password__
  EOF

  ${nix-mikrotik}/bin/nix-mikrotik list-secrets router.rsc > listed
  grep -qx wg-private-key listed
  grep -qx wifi-password listed
  [ "$(wc -l < listed)" -eq 2 ]

  printf 'sekret-key' > wg-private-key
  printf 'sekret-pass' > wifi-password
  ${nix-mikrotik}/bin/nix-mikrotik secretize router.rsc -o out.rsc --secrets-dir .
  grep -q 'private-key=sekret-key' out.rsc
  grep -q 'passphrase=sekret-pass' out.rsc
  ! grep -q '__MIKROTIK_SECRET_' out.rsc

  # the rendered copy is not world-readable
  [ "$(stat -c %a out.rsc)" = "600" ]

  # a missing value must fail, not ship a placeholder
  if ${nix-mikrotik}/bin/nix-mikrotik secretize router.rsc -o bad.rsc \
       --secret wg-private-key=wg-private-key 2>err; then
    echo "secretize succeeded with an unresolved placeholder" >&2
    exit 1
  fi
  grep -q 'unresolved secret placeholders: wifi-password' err

  touch $out
''
