# The same convention with the string-keyed `sections` spelling, so a ported
# router does not have to be rewritten to be discovered.
{ config, ... }:
{
  # The key the tunnel needs, declared as the generator that mints it. It sits
  # next to `mikrotik` rather than inside it: a generator is not a RouterOS menu.
  clan.core.vars.generators.legacy-key = {
    files.privkey = { };
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
