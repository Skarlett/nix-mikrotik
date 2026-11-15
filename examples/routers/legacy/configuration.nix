# The same convention with the string-keyed `sections` spelling, so a ported
# router does not have to be rewritten to be discovered.
{ config, pkgs, ... }:
{
  # The key the tunnel needs, declared as the generator that mints it. It sits
  # next to `mikrotik` rather than inside it: a generator is not a RouterOS menu.
  #
  # `runtimeInputs` is not decoration: the script runs on the machine that
  # deploys, and without it `wg` is whatever that machine happens to have on its
  # PATH -- or nothing, and the generator fails after the tunnel was configured.
  clan.core.vars.generators.legacy-key = {
    files.privkey = { };
    runtimeInputs = [ pkgs.wireguard-tools ];
    script = "wg genkey > $out/privkey";
  };

  mikrotik = {
    hostname = "legacy";
    sections."/interface wireguard" = [
      {
        name = "wg0";
        private-key = config.clan.core.vars.generators.legacy-key.files.privkey.placeholder;
      }
    ];
  };
}
