# One router, in the `routers/<name>/configuration.nix` convention.
#
# Written in the typed menu surface, and self-contained: a router directory is
# picked up and evaluated on its own, so it may not import a file relative to
# somewhere outside its own directory unless that file is in the flake too.
#
# This router is published as `mikrotikConfigurations.example`, which carries the
# generators it declares as well as its rendered script -- the values are filed
# under `vars/per-machine/example/...`, named for its key in `mikrotik.routers`
# rather than for its hostname.
{ config, pkgs, ... }:
{
  clan.core.vars.generators.example-wg-key = {
    files.privkey = { };
    runtimeInputs = [ pkgs.wireguard-tools ];
    script = "wg genkey > $out/privkey";
  };

  mikrotik = {
    hostname = "example";
    comment = "the routers/ convention, exercised";

    interface.wireguard.items = [
      {
        name = "wg0";
        listen-port = 51820;
        private-key = config.clan.core.vars.generators.example-wg-key.files.privkey.placeholder;
      }
    ];

    ip.dns.items.servers = "9.9.9.9";
  };
}
