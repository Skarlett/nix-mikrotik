{ pkgs, evalMikrotik, evalMikrotikFleet, evalMikrotikRaw, mkSecret }:

# The fleet form: several routers declared side by side must not collide.
#
# `mikrotik.routers.<name>` exists for clan services, where each instance
# contributes the module of the router it manages. A router is a configuration of
# its own -- a separate device -- so each entry is a *module* and is evaluated on
# its own; this proves the claim that makes: routers compose instead of
# overwriting each other, each script keeps its own identity and secrets, the
# typed menu surface is written the same way inside a router as outside, and a
# broken router fails the evaluation of that router rather than of the fleet.
let
  lib = pkgs.lib;

  fleet = evalMikrotikFleet {
    modules = [
      {
        mikrotik.routers.chr1 = {
          mikrotik.hostname = "gw.chr1.luninet.org";
          mikrotik.secrets.wg-key.file = "chr1-wg-key";
          # The typed menu surface, inside a router: the same option tree a lone
          # router carries, not a second spelling of the same menu.
          mikrotik.interface.wireguard.items = [
            {
              name = "wg.test";
              private-key = mkSecret "wg-key";
            }
          ];
        };
      }
      {
        mikrotik.routers.chr2 = {
          mikrotik.hostname = "gw.chr2.luninet.org";
          mikrotik.sections."/ip dns".servers = "1.1.1.1";
        };
      }
      # Two modules for one router merge into it, which is how one service
      # contributes the router and another (the address space, say) contributes
      # a slice of the same router.
      { mikrotik.routers.chr3.mikrotik.hostname = "gw.chr3.luninet.org"; }
      {
        mikrotik.routers.chr3.mikrotik.ip.address = [
          {
            address = "10.9.0.1/24";
            interface = "ether1";
          }
        ];
      }
    ];
  };

  # The single-router form is untouched by the fleet option.
  single = evalMikrotik {
    modules = [
      {
        mikrotik.hostname = "lonely";
        mikrotik.sections."/ip dns".servers = "9.9.9.9";
      }
    ];
  };

  # A broken router: refused by its own evaluation, not by the fleet's.
  # The rendered strings are forced here -- `tryEval` alone would stop at the
  # attrset of unevaluated thunks and report success.
  brokenFleet = builtins.tryEval (
    builtins.concatStringsSep "" (builtins.attrValues (
      evalMikrotikFleet {
        modules = [
          {
            mikrotik.routers.wrong.mikrotik.sections."/interface wireguard" = [
              {
                name = "wg0";
                private-key = mkSecret "no-such-secret";
              }
            ];
          }
        ];
      }
    ))
  );

  refusals = [
    {
      name = "a router with an unpaired secret";
      modules = [
        {
          mikrotik.sections."/interface wireguard" = [
            {
              name = "wg0";
              private-key = mkSecret "no-such-secret";
            }
          ];
        }
      ];
      expect = "mikrotik.secrets";
    }
    {
      name = "a router with a /system identity section";
      modules = [{ mikrotik.sections."/system identity".name = "x"; }];
      expect = "mikrotik.hostname";
    }
    {
      name = "both forms at once";
      modules = [
        {
          mikrotik.hostname = "single";
          mikrotik.sections."/ip dns".servers = "1.1.1.1";
          mikrotik.routers.other.mikrotik.hostname = "other";
        }
      ];
      expect = "Move the single router into mikrotik.routers";
    }
  ];

  refusalResults = map
    (r:
      let
        plan = evalMikrotikRaw { inherit (r) modules; };
        messages = map (a: a.message) plan.failed;
      in
      {
        inherit (r) name;
        ok = plan.failed != [ ] && lib.any (m: lib.hasInfix r.expect m) messages;
      }
    )
    refusals;

  failedRefusals = map (r: r.name) (builtins.filter (r: !r.ok) refusalResults);
in
# A refusal that does not fire is the failure mode this whole test exists for:
  # it is checked at evaluation, where the diagnostic is readable.
assert lib.asserts.assertMsg (failedRefusals == [ ])
  (
    "these refusals did not fire: ${builtins.concatStringsSep ", " failedRefusals}"
  );
assert lib.asserts.assertMsg
  (builtins.attrNames fleet == [
    "chr1"
    "chr2"
    "chr3"
  ]) "the fleet did not contain exactly chr1, chr2 and chr3";
assert lib.asserts.assertMsg (!brokenFleet.success)
  "a router with an unpaired secret rendered anyway";
assert lib.asserts.assertMsg (single.mikrotik.hostname == "lonely")
  "the single-router form stopped evaluating";
pkgs.runCommandLocal "mikrotik-fleet" { } ''
  mkdir -p $out
  cp ${pkgs.writeText "chr1.rsc" fleet.chr1} $out/chr1.rsc
  cp ${pkgs.writeText "chr2.rsc" fleet.chr2} $out/chr2.rsc
  cp ${pkgs.writeText "chr3.rsc" fleet.chr3} $out/chr3.rsc

  # Each router renders under its own identity: the failure this guards
  # against is one router silently winning and the other disappearing.
  grep -q 'set name="gw.chr1.luninet.org"' $out/chr1.rsc
  grep -q 'set name="gw.chr2.luninet.org"' $out/chr2.rsc
  grep -q 'set name="gw.chr3.luninet.org"' $out/chr3.rsc
  ! grep -q 'gw.chr2' $out/chr1.rsc
  ! grep -q 'gw.chr1' $out/chr2.rsc

  # A secret belongs to the router that declared it.
  grep -q 'private-key=__MIKROTIK_SECRET_wg-key__' $out/chr1.rsc
  ! grep -q 'wg-key' $out/chr2.rsc

  # Each keeps its own sections.
  grep -q 'servers=1.1.1.1' $out/chr2.rsc
  ! grep -q 'servers=1.1.1.1' $out/chr1.rsc

  # A router assembled from two modules keeps both halves, and the typed menu
  # surface is written the same way inside a router as outside it.
  grep -q 'add address=10.9.0.1/24 interface=ether1' $out/chr3.rsc

  touch $out/pass
''
