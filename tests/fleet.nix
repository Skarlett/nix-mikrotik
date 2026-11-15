{ pkgs, evalMikrotik, evalMikrotikFleet, evalMikrotikFleetConfigs, evalMikrotikRaw, generators, mkSecret }:

# The fleet form: several routers declared side by side must not collide.
#
# `mikrotik.routers.<name>` exists for clan services, where each instance
# contributes the module of the router it manages. A router is a configuration of
# its own -- a separate device -- so each entry is a *module* and is evaluated on
# its own; this proves the claim that makes: routers compose instead of
# overwriting each other, each script keeps its own identity and secrets, its
# generated values are filed under its own name, the typed menu surface is
# written the same way inside a router as outside, and a broken router fails the
# evaluation of that router rather than of the fleet.
let
  lib = pkgs.lib;

  # chr1 mints a key; its menu cell holds the placeholder, not a value.
  chr1 = { config, ... }: {
    mikrotik.hostname = "gw.chr1.luninet.org";
    # The typed menu surface, inside a router: the same option tree a lone
    # router carries, not a second spelling of the same menu.
    mikrotik.interface.wireguard.items = [
      {
        name = "wg.test";
        private-key = config.clan.core.vars.generators.wg-key.files.privkey.placeholder;
      }
    ];
    clan.core.vars.generators.wg-key = {
      files.privkey = { };
      files.pubkey.secret = false;
      script = "wg genkey | tee $out/privkey | wg pubkey > $out/pubkey";
    };
  };

  # chr2 declares a generator of the same name. The two must land in different
  # var directories: that is what `routerName` buys, and what would quietly
  # break if it defaulted to the hostname of whichever router was evaluated.
  chr2 = {
    mikrotik.hostname = "gw.chr2.luninet.org";
    mikrotik.sections."/ip dns".servers = "1.1.1.1";
    clan.core.vars.generators.wg-key = {
      files.privkey = { };
      script = "wg genkey > $out/privkey";
    };
  };

  fleetModule = {
    mikrotik.routers.chr1 = chr1;
    mikrotik.routers.chr2 = chr2;
    # Two modules for one router merge into it, which is how one service
    # contributes the router and another (the address space, say) contributes
    # a slice of the same router.
    mikrotik.routers.chr3.mikrotik.hostname = "gw.chr3.luninet.org";
    mikrotik.routers.chr3.mikrotik.ip.address = [
      {
        address = "10.9.0.1/24";
        interface = "ether1";
      }
    ];
  };

  fleet = evalMikrotikFleet { inherit pkgs; modules = [ fleetModule ]; };

  # Each router's generators, as the deploy tool would read them.
  fleetConfigs = evalMikrotikFleetConfigs { inherit pkgs; modules = [ fleetModule ]; };
  relDirs = name:
    lib.unique (lib.concatMap (g: map (f: f.relDir) g.files) (generators fleetConfigs.${name}));

  # The single-router form is untouched by the fleet option.
  single = evalMikrotik {
    inherit pkgs;
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
        inherit pkgs;
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
      name = "a router with an unpaired placeholder";
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
      expect = "has no matching file";
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
        plan = evalMikrotikRaw { inherit (r) modules pkgs; };
        messages = map (a: a.message) plan.failed;
      in
      {
        inherit (r) name;
        ok = plan.failed != [ ] && lib.any (m: lib.hasInfix r.expect m) messages;
      }
    )
    refusals;

  failedRefusals = map (r: r.name) (builtins.filter (r: !r.ok) refusalResults);

  chr1KeyFile = builtins.head (builtins.head (generators fleetConfigs.chr1)).files;
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
  grep -q 'private-key=__MIKROTIK_SECRET_wg-key/privkey__' $out/chr1.rsc
  ! grep -q 'wg-key' $out/chr2.rsc

  # Two routers declaring a generator of the same name file it under their own
  # keys, not under whichever hostname came last.
  [ ${lib.escapeShellArg chr1KeyFile.relDir} = 'per-machine/chr1/wg-key' ]
  [ ${lib.escapeShellArg (lib.concatStringsSep " " (relDirs "chr1"))} = 'per-machine/chr1/wg-key' ]
  [ ${lib.escapeShellArg (lib.concatStringsSep " " (relDirs "chr2"))} = 'per-machine/chr2/wg-key' ]

  # Each keeps its own sections.
  grep -q 'servers=1.1.1.1' $out/chr2.rsc
  ! grep -q 'servers=1.1.1.1' $out/chr1.rsc

  # A router assembled from two modules keeps both halves, and the typed menu
  # surface is written the same way inside a router as outside it.
  grep -q 'add address=10.9.0.1/24 interface=ether1' $out/chr3.rsc

  touch $out/pass
''