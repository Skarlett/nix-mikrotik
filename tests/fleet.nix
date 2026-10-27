{ pkgs, evalMikrotik, evalMikrotikFleet, evalMikrotikRaw, mkSecret }:

# The fleet form: several routers declared side by side must not collide.
#
# `mikrotik.routers.<name>` exists for clan services, where each instance
# writes its own key the way `networking.wireguard.interfaces.<name>` does.
# This proves the claim that makes: routers compose instead of overwriting each
# other, each script keeps its own identity and secrets, and a configuration
# that is wrong is refused with the router named -- not with a bare "assertion
# failed" that could point anywhere in a fleet.
let
  lib = pkgs.lib;

  fleet = evalMikrotikFleet {
    modules = [
      {
        mikrotik.routers.chr1 = {
          hostname = "gw.chr1.luninet.org";
          secrets.wg-key.file = "chr1-wg-key";
          sections."/interface wireguard" = [
            {
              name = "wg.test";
              private-key = mkSecret "wg-key";
            }
          ];
        };
      }
      {
        mikrotik.routers.chr2 = {
          hostname = "gw.chr2.luninet.org";
          sections."/ip dns".servers = "1.1.1.1";
        };
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

  refusals = [
    {
      name = "a fleet entry with an unpaired secret";
      modules = [
        {
          mikrotik.routers.bad.sections."/interface wireguard" = [
            {
              name = "wg0";
              private-key = mkSecret "no-such-secret";
            }
          ];
        }
      ];
      expect = "mikrotik.routers.bad.secrets";
    }
    {
      name = "a fleet entry with a /system identity section";
      modules = [
        { mikrotik.routers.bad.sections."/system identity".name = "x"; }
      ];
      expect = "mikrotik.routers.bad.hostname";
    }
    {
      name = "both forms at once";
      modules = [
        {
          mikrotik.hostname = "single";
          mikrotik.sections."/ip dns".servers = "1.1.1.1";
          mikrotik.routers.other.hostname = "other";
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
assert lib.asserts.assertMsg (failedRefusals == [ ]) (
  "these refusals did not fire with the router named: ${builtins.concatStringsSep ", " failedRefusals}"
);
assert lib.asserts.assertMsg (builtins.attrNames fleet == [
  "chr1"
  "chr2"
]) "the fleet did not contain exactly chr1 and chr2";
assert lib.asserts.assertMsg (single.mikrotik.hostname == "lonely")
  "the single-router form stopped evaluating";
pkgs.runCommandLocal "mikrotik-fleet" { } ''
  mkdir -p $out
  cp ${pkgs.writeText "chr1.rsc" fleet.chr1} $out/chr1.rsc
  cp ${pkgs.writeText "chr2.rsc" fleet.chr2} $out/chr2.rsc
  cp ${pkgs.writeText "single.rsc" (pkgs.lib.concatMapStrings (n: "") [ ])} $out/.keep 2>/dev/null || true

  # Each router renders under its own identity: the failure this guards
  # against is one router silently winning and the other disappearing.
  grep -q 'set name="gw.chr1.luninet.org"' $out/chr1.rsc
  grep -q 'set name="gw.chr2.luninet.org"' $out/chr2.rsc
  ! grep -q 'gw.chr2' $out/chr1.rsc
  ! grep -q 'gw.chr1' $out/chr2.rsc

  # A secret belongs to the router that declared it.
  grep -q 'private-key=__MIKROTIK_SECRET_wg-key__' $out/chr1.rsc
  ! grep -q 'wg-key' $out/chr2.rsc

  # Each keeps its own sections.
  grep -q 'servers=1.1.1.1' $out/chr2.rsc
  ! grep -q 'servers=1.1.1.1' $out/chr1.rsc

  touch $out/pass
''