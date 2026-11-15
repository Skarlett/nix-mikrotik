{ pkgs, render, generators, config }:

# The schema fixture: the `networks.<name>` module in `examples/networks.nix`,
# rendered and turned into the generator manifest the deploy tool reads.
#
# The golden is the whole script, not a handful of greps, because the point of
# this check is the *translation*: a Nix list becomes one comma-joined RouterOS
# argument, a `placeholder` becomes a bare `__MIKROTIK_SECRET_…__` marker for the
# deploy tool to substitute, and every attribute name in the example is one the
# menu vocabulary accepts (a misspelt one would have been refused at evaluation,
# so reaching this render at all is half the assertion).
pkgs.runCommand "check-networks" { } ''
  mkdir -p $out

  cp ${pkgs.writeText "networks.rsc" (render config)} $out/networks.rsc
  diff -u ${./golden/networks.rsc} $out/networks.rsc

  # The secret stays a marker: nothing in the store holds the key.
  grep -qx 'add listen-port=64192 mtu=1420 name=wg.9600-baud.net private-key=__MIKROTIK_SECRET_wg-9600-baud-net-key/privkey__' $out/networks.rsc
  grep -q 'wg genkey' $out/networks.rsc && {
    echo "the generator's script leaked into the rendered script" >&2
    exit 1
  }

  # The manifest says what to run, and which half of the output is public.
  cp ${pkgs.writeText "networks-generators.json" (builtins.toJSON (generators config))} $out/networks-generators.json
  ${pkgs.jq}/bin/jq -e '
    length == 1
    and .[0].name == "wg-9600-baud-net-key"
    and (.[0].files | map({(.name): .secret}) | add) == { "privkey": true, "pubkey": false }
    and (.[0].runtimeInputs | length) == 1
    and (.[0].runtimeInputs[0] | test("wireguard-tools"))
    and (.[0].script | test("wg genkey"))
  ' $out/networks-generators.json > /dev/null

  cat $out/networks.rsc
  touch $out/pass
''