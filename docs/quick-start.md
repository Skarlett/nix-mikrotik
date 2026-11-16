# Quick start

A configuration, rendered three ways, then built, deployed and diffed.
Everything else here assumes you can produce a `.rsc` from a flake.

```sh
# render a configuration through the flake
nix eval --raw .#mikrotikConfigurations.example.script

# or as a store path
nix build .#packages.x86_64-linux.mikrotik-example-script
cat result/router-config.rsc

# or with the tool, which copies the script out of the store
nix run .#nix-mikrotik -- render --name example -o router.rsc
```

A configuration is a module:

```nix
{ config, pkgs, ... }:
{
  imports = [ (import "${nix-mikrotik}/modules/hardening.nix") ];

  # The key the tunnel needs, as the generator that mints it. This is clan's own
  # generator interface, unchanged: a generator is a shell script plus the files
  # it declares, and each file says whether it is a secret.
  clan.core.vars.generators.wg-private-key = {
    files.privkey.secret = true;
    runtimeInputs = [ pkgs.wireguard-tools ];
    script = "wg genkey > $out/privkey";
  };

  mikrotik = {
    hostname = "router1";

    sections = {
      "/interface bridge" = [ { name = "bridge"; } ];
      "/ip address" = [
        { address = "10.10.10.1/24"; interface = "bridge"; }
      ];
      "/interface wireguard" = [
        {
          name = "wg0";
          private-key = config.clan.core.vars.generators.wg-private-key.files.privkey.placeholder;
        }
      ];
    };
  };
}
```
