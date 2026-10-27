# Upstream's example, adapted without being rewritten.
#
# The one thing the module class refuses is a `/system identity` section: the
# identity is an option here, so that the deploy tool can read it back and
# verify a device. Everything else in an upstream configuration is already the
# `sections` data model, so porting is `removeAttrs` plus lifting the name out.
{ ... }:
let
  upstream = import ./configuration.nix;
in
{
  mikrotik.hostname = upstream."/system identity".name;
  mikrotik.sections = builtins.removeAttrs upstream [ "/system identity" ];
}
