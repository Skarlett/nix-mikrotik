# A network written the way a router module should be: one `networks.<name>`
# option, one WireGuard tunnel, and the secret it carries declared as the
# generator that mints it.
#
# This is the shape `modules/base.nix` is aligned to, and the fixture that
# `checks.networks` evaluates:
#
#   * the generator interface is clan's own -- `clan.core.vars.generators`,
#     unchanged, not a `secrets.*` spelling of it. A generator is a shell script
#     plus the files it writes, so it has no RouterOS menu to belong to and lives
#     next to `mikrotik`, at the root. Each file declares whether it is a secret,
#     and the secret ones are referenced through `files.<file>.placeholder`,
#     which renders as `__MIKROTIK_SECRET_<generator>/<file>__` and is
#     substituted by `nix-mikrotik deploy` on the machine that holds the value.
#   * `share = true` files a generator under `vars/shared/<generator>` instead of
#     `vars/per-machine/<router>/<generator>`, for a value a whole fleet of
#     routers uses.
#   * Menu attributes are RouterOS' own, hyphenated (`listen-port`,
#     `private-key`, `allowed-address`, `dst-address`), because they are
#     type-checked against the generated menu vocabulary: a misspelt one is an
#     evaluation error naming the menu, not a dropped line on the device.
#   * A list-valued attribute is a Nix list. RouterOS spells it
#     `allowed-address=0.0.0.0/0,::/0`; the join happens in `lib/render.nix`, so
#     a configuration never builds that string by hand.
{ config, lib, pkgs, ... }:
{
  options.networks."9600-baud".enable =
    lib.mkEnableOption "Enable 9600-baud network";

  config = lib.mkIf config.networks."9600-baud".enable {
    clan.core.vars.generators."wg-9600-baud-net-key" = {
      # The tunnel's key pair: one secret, one published value. Publishing the
      # public half is what `secret = false` is for -- the peers on the other
      # side need it, and it is not a secret.
      files."privkey".secret = true;

      files."pubkey" = {
        secret = false;
        description = "The public half, for the peers on the other side";
      };

      runtimeInputs = [ pkgs.wireguard-tools ];
      script = ''
        wg genkey | tee $out/privkey | wg pubkey > $out/pubkey
      '';
    };

    mikrotik.interface.wireguard = {
      items = [
        {
          listen-port = 64192;
          mtu = 1420;
          name = "wg.9600-baud.net";
          private-key = config.clan.core.vars.generators."wg-9600-baud-net-key".files.privkey.placeholder;
        }
      ];

      peers = [
        {
          name = "core-couter";
          allowed-address = [ "0.0.0.0/0" "::/0" ];
          interface = "wg.9600-baud.net";
          public-key = "k9ZRM5a4m4qYDVuZmbksipA/gJ82mBH3MvgZaJRWIAo=";
        }
      ];
    };

    mikrotik.ip = {
      dns.items = {
        servers = [ "fd26:43c2:96bd::53" ];
      };

      vrf = [
        {
          name = "vrf.9600-baud.net";
          interfaces = [ "wg.9600-baud.net" ];
        }
      ];
    };

    mikrotik.ipv6 = {
      # Three addresses on the tunnel: this side of the point-to-point /127, the
      # peer side of it, and the /48 this network is the edge of.
      address = [
        {
          address = "fd26:43c2:96bd:300::a/127";
          interface = "wg.9600-baud.net";
          comment = "point to point";
        }

        {
          address = "fd26:43c2:96bd:300::b/127";
          advertise = false;
          interface = "wg.9600-baud.net";
          comment = "luni.0.nni-2.43c2.9600-baud.net";
        }

        {
          address = "fd12:7001:ac1d::1/48";
          interface = "wg.9600-baud.net";
          comment = "luni network";
        }
      ];

      route = [
        {
          dst-address = "fd26:43c2:96bd::/48";
          gateway = "fd26:43c2:96bd:300::b";
          vrf-interface = "vrf.9600-baud.net";
        }
      ];
    };
  };
}