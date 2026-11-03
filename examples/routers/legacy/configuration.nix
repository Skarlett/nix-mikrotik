# The same convention with the string-keyed `sections` spelling, so a ported
# router does not have to be rewritten to be discovered.
{ mkSecret, ... }:
{
  mikrotik = {
    hostname = "legacy";
    secrets.legacy-key.file = "legacy-key";
    sections."/interface wireguard" = [
      {
        name = "wg0";
        private-key = mkSecret "legacy-key";
      }
    ];
  };
}
