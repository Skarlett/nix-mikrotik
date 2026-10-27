{ pkgs, render, legacy, example }:

# The renderer is the one piece that must not drift: a RouterOS script that
# changes shape between two versions of this tool is a router that changes
# behaviour. Upstream's own example is the fixture, and it is compared
# byte-for-byte against a committed golden file.
pkgs.runCommand "check-render" { } ''
  mkdir -p $out

  cp ${pkgs.writeText "legacy.rsc" (render legacy)} $out/legacy.rsc
  diff -u ${./golden/legacy.rsc} $out/legacy.rsc

  cp ${pkgs.writeText "module.rsc" (render example)} $out/module.rsc

  # A secret is a placeholder in the store, never a value.
  grep -q 'private-key=__MIKROTIK_SECRET_wg-private-key__' $out/module.rsc
  grep -q 'passphrase=__MIKROTIK_SECRET_wifi-password__' $out/module.rsc

  # sectionOrder puts the bridge before anything that references it.
  bridge_line=$(grep -n '^/interface bridge' $out/module.rsc | cut -d: -f1)
  address_line=$(grep -n '^/ip address' $out/module.rsc | cut -d: -f1)
  [ "$bridge_line" -lt "$address_line" ]

  # Booleans render the way RouterOS spells them, not the way Nix does.
  grep -q 'disabled=no' $out/module.rsc
  ! grep -q 'disabled=false' $out/module.rsc

  # A value RouterOS cannot parse unquoted is quoted; one it can, is not.
  # `public-key=<base64>=` broke an import at "expected end of command".
  grep -q 'public-key="l0VH8y3T0nKzZ9Qq2m4Xo8b1y6wR5cJ7dE3fG9hI2kA="' $out/module.rsc
  grep -q 'address=10.10.10.1/24' $out/module.rsc

  # The hardening module composed with the example rather than replacing it.
  grep -q '^/tool mac-server ping' $out/module.rsc
  grep -q 'allowed-interface-list=none' $out/module.rsc

  touch $out/pass
''
