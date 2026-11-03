# One router, in the `routers/<name>/configuration.nix` convention.
#
# Written in the typed menu surface, and self-contained: a router directory is
# picked up and evaluated on its own, so it may not import a file relative to
# somewhere outside its own directory unless that file is in the flake too.
{ mkSecret, ... }:
{
  mikrotik = {
    hostname = "example";
    comment = "the routers/ convention, exercised";

    interface.wireguard.items = [
      {
        name = "wg0";
        listen-port = 51820;
        private-key = mkSecret "example-wg-key";
      }
    ];

    secrets.example-wg-key.file = "example-wg-key";

    ip.dns.items.servers = "9.9.9.9";
  };
}
