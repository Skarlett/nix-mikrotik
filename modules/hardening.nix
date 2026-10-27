# Baseline hardening, as a module of the `mikrotik` class.
#
# This is the same content the upstream example carried inline, expressed as
# something importable: a router configuration opts in with one import and
# still overrides any of it, because section attrsets merge.
#
# The settings themselves are the ones from MikroTik's own "securing your
# router" guidance: no plaintext management protocols, no neighbour discovery
# on the outside, no bandwidth server, no mac-server.
{ lib, ... }:
{
  mikrotik.sections = {
    "/ip service" = {
      telnet = { disabled = true; };
      ftp = { disabled = true; };
      www = { disabled = true; };
      winbox = { disabled = true; };
      api = { disabled = true; };
      api-ssl = { disabled = true; };
    };

    "/ip ssh" = { strong-crypto = true; };

    "/ip neighbor discovery-settings" = { discover-interface-list = "none"; };

    "/tool bandwidth-server" = { enabled = false; };
    "/tool mac-server" = { allowed-interface-list = "none"; };
    "/tool mac-server mac-winbox" = { allowed-interface-list = "none"; };
    "/tool mac-server ping" = { enabled = false; };

    "/ip cloud" = { update-time = false; };
  };
}
