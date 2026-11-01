# The base module of the `mikrotik` module class.
#
# A configuration is evaluated with `lib.evalMikrotik` (or a flake's
# `mikrotikConfigurations.<name>`), never imported into a NixOS system: RouterOS
# is not NixOS, and pretending otherwise is what makes router automation
# opaque. The class exists so that the same conventions apply -- options with
# types and defaults, modules that compose, assertions that fail the build --
# while the output is a RouterOS script.
{ config, lib, ... }:
let
  inherit (lib) mkOption types literalExpression;

  # RouterOS menus nest arbitrarily (`{ no_label = { a = "b"; }; }`), so the
  # section body is checked structurally and validated again at render time.
  #
  # The typed menu options (modules/menus.nix) are built from the same file, so
  # the two spellings accept the same values -- which is why a configuration may
  # move one menu at a time from `sections` to the typed options.
  inherit (import ../lib/types.nix { inherit lib; }) sectionBody;

  # The typed menu surface (`mikrotik.ip."dhcp-server".network`), spliced into
  # the option set below so that both forms carry it: a menu is then an option
  # path on `mikrotik` and on `mikrotik.routers.<name>`, and a mistyped
  # attribute is an evaluation error rather than a script error on the device.
  menuOptions = import ../lib/menu-options.nix { inherit lib; };

  # Collect every `mkSecret "name"` reference anywhere under a value.
  secretRefs = v:
    if lib.isAttrs v && v ? __mikrotikSecret then [ v.__mikrotikSecret ]
    else if lib.isAttrs v then lib.concatMap secretRefs (lib.attrValues v)
    else if lib.isList v then lib.concatMap secretRefs v
    else [ ];

  # One router's options, declared once: `mikrotik.<option>` is the
  # single-router form and `mikrotik.routers.<name>.<option>` is the fleet
  # form, and both are this same set. A service contributing a router wires
  # into the fleet form so that several routers, from several service
  # instances, compose instead of overwriting each other.
  #
  # The typed menu surface is spliced in at the bottom (`menuOptions`), so a
  # menu is an option on both forms rather than two declarations that drift.
  routerOptions = {

    hostname = mkOption {
      type = types.str;
      default = "MikroTik";
      description = ''
        RouterOS identity. Rendered first, so a script that fails halfway
        still leaves the device named.
      '';
    };

    comment = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "Optional line in the generated header.";
    };

    sections = mkOption {
      type = types.attrsOf sectionBody;
      default = { };
      description = ''
        RouterOS menus keyed by their command path, e.g. `"/ip address"`.

        An attrset renders as `set …` lines; a list of attrsets renders as
        repeated `add …` lines. This is upstream's data model, unchanged, so an
        existing configuration ports over by wrapping it in
        `mikrotik.sections`.
      '';
      example = literalExpression ''
        {
          "/ip address" = [
            { address = "10.10.10.1/24"; interface = "bridge"; }
          ];
        }
      '';
    };

    sectionOrder = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = ''
        Sections to render before the rest, in this order. RouterOS applies a
        script top to bottom, so an object that another section references has
        to exist first. Sections not listed follow alphabetically.
      '';
      example = literalExpression ''
        [ "/interface bridge" "/interface vlan" "/ip address" ]
      '';
    };

    extraScript = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = "Raw RouterOS lines appended verbatim. The escape hatch.";
    };

    secrets = mkOption {
      type = types.attrsOf (types.submodule {
        options = {
          description = mkOption {
            type = types.str;
            default = "";
            description = "What this secret is for; documentation only.";
          };
          file = mkOption {
            type = types.nullOr types.str;
            default = null;
            description = ''
              Name of the file the deploy tool should read this value from,
              relative to the secrets directory it is given. Purely advisory:
              the rendered script only carries the placeholder, and the deploy
              tool refuses to run while one is unresolved.
            '';
          };
        };
      });
      default = { };
      description = ''
        Secrets this configuration references through `mkSecret "name"`.

        They are declared here so that a typo in a reference is a build
        failure, and so that the deploy tool can enumerate what it must be
        handed. A secret has no value in the nix store: RouterOS cannot run
        sops-nix, so the value is delivered at deploy time (see README).

        The fleet supplies these from clan vars
        (`Infra/lunix` `modules/vars/generators/mikrotik.nix`), whose file
        names are these names — so the deployed var directory can be passed to
        `nix-mikrotik deploy --secrets-dir` unchanged. See README "Clan vars".
      '';
    };

    checkMenuAttributes = mkOption {
      type = types.bool;
      default = true;
      description = ''
        Reject an attribute name a menu does not list in `lib/menus.nix`.

        On by default: an unknown name is far more often a typo than a new
        RouterOS feature, and the failure belongs in evaluation rather than in
        an import on a live router. Turn it off for a menu surface the table has
        not caught up with yet, and add the name to the table when it has.
      '';
    };

  } // menuOptions.optionTree;

  cfg = config.mikrotik;

  # These apply to any router, whichever form declared it -- the single-router
  # options or one entry of `mikrotik.routers` -- so a fleet is checked as
  # strictly as a lone router.

  # A secret name is also a file name in a secrets directory (README "Clan
  # vars": the generator's file names are the mkSecret names), so it has to be
  # one. The deploy tool refuses anything else, and the *silent* half of that
  # failure is the worse one: a name the tool's pattern cannot see would be
  # listed as "no secret placeholders" and deployed as a literal
  # __MIKROTIK_SECRET_… to a router, while a name carrying `/` or `..` would
  # turn `--secrets-dir` into a read outside that directory.
  secretNameRe = "^[A-Za-z0-9][A-Za-z0-9._-]*$";
  problemsFor =
    r:
    let
      referenced = lib.unique (lib.concatMap secretRefs (lib.attrValues r.sections));
      undeclared = builtins.filter (n: !(r.secrets ? ${n})) referenced;
      badPaths = builtins.filter (n: !(lib.hasPrefix "/" n)) (builtins.attrNames r.sections);
      badSecretNames = builtins.filter
        (n: builtins.match secretNameRe n == null)
        (lib.unique (referenced ++ builtins.attrNames r.secrets));
    in
    {
      inherit undeclared badPaths badSecretNames;
      systemIdentity = r.sections ? "/system identity";
    };

  # One assertion set per router, so the message names the router that has the
  # problem instead of pointing at the fleet.
  routerAssertions =
    label: r:
    let
      p = problemsFor r;
    in
    [
      {
        assertion = !p.systemIdentity;
        message = ''
          ${label}.sections."/system identity" is not allowed: set
          ${label}.hostname instead.
        '';
      }
      {
        assertion = p.badPaths == [ ];
        message = ''
          ${label}.sections keys must be RouterOS command paths beginning with
          "/" (offending: ${toString p.badPaths})
        '';
      }
      {
        assertion = p.undeclared == [ ];
        message = ''
          a mkSecret reference has no matching ${label}.secrets.<name> entry:
          ${toString p.undeclared}
        '';
      }
      {
        assertion = p.badSecretNames == [ ];
        message = ''
          these secret names are not usable as file names, and a secret name is
          also the name of the file the deploy tool reads the value from:
          letters, digits, dot, dash and underscore only, starting with a letter
          or a digit (offending: ${toString p.badSecretNames})
        '';
      }
    ];
in
{
  _class = "mikrotik";

  options.assertions = mkOption {
    type = types.listOf (types.submodule {
      options = {
        assertion = mkOption {
          type = types.bool;
          description = "Condition that must hold.";
        };
        message = mkOption {
          type = types.str;
          default = "assertion failed";
          description = "What to say when it does not.";
        };
      };
    });
    default = [ ];
    description = ''
      Evaluated by `lib.evalMikrotik`, which throws before returning a config
      if any of them is false. A custom module class has no NixOS
      `assertions` machinery behind it, so this class carries its own.
    '';
  };

  options.mikrotik = routerOptions // {
    routers = mkOption {
      type = types.attrsOf types.deferredModule;
      default = { };
      description = ''
        A fleet of routers keyed by name. Each entry is a *module* that writes
        the single-router options above -- `mikrotik.hostname`,
        `mikrotik.ip.address`, `mikrotik.secrets` -- because a router is a
        configuration of its own, not a slice of this one: it is evaluated on
        its own, so two routers cannot collide and each one's assertions run
        against that router alone.

        This is the shape a clan service contributes to. One service instance
        writes one key, so instances compose the way
        `networking.wireguard.interfaces.<name>` does, and the module a service
        hands over is the same module it would evaluate alone. Evaluate a fleet
        with `lib.evalMikrotikFleet`, which renders
        `{ <name> = "<script>"; }`.
      '';
      example = literalExpression ''
        {
          chr1.mikrotik.hostname = "gateway.chr1.luninet.org";
          chr2.mikrotik.hostname = "gateway.chr2.luninet.org";
        }
      '';
    };
  };

  config = {
    assertions =
      [
        {
          assertion = cfg.hostname != "";
          message = "mikrotik.hostname must not be empty";
        }
        {
          # Both forms at once is a mistake, not a merge: the single-router
          # options would render a script nobody asked for, and the fleet would
          # not contain it.
          assertion = cfg.routers == { } || (cfg.sections == { } && cfg.extraScript == [ ]);
          message = ''
            this configuration sets both the single-router options
            (mikrotik.sections / mikrotik.extraScript) and mikrotik.routers.
            Move the single router into mikrotik.routers too, so every router in
            the fleet is named.
          '';
        }
      ]
      ++ routerAssertions "mikrotik" cfg;
  };
}
