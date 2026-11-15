# Upstream's entry point, kept working.
#
#   nix-build mikrotik.nix
#   nix-build mikrotik.nix --arg mikrotik-config ./my-config.nix
#
# It now renders through the same code as everything else, so a configuration
# built this way and one built through the flake cannot disagree. A bare
# attribute set (upstream's format) is lifted into the module class: the
# identity comes out of the set, the rest is `mikrotik.sections`.
{ mikrotik-config ? ./examples/configuration.nix }:

let
  pkgs = import <nixpkgs> { };
  inherit (pkgs) lib;

  mt = import ./lib { inherit lib; };

  raw = import mikrotik-config;
  hostname = raw."/system identity".name or "MikroTik";
  config = mt.evalMikrotik {
    inherit pkgs;
    modules = [
      {
        mikrotik.hostname = hostname;
        mikrotik.sections = builtins.removeAttrs raw [ "/system identity" ];
      }
    ];
  };
in
pkgs.runCommand "mikrotik-router-0.0.1" { } ''
  mkdir -p $out
  cp ${pkgs.writeText "router-config.rsc" (mt.render config)} $out/router-config.rsc
''
