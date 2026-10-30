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

  # Collect every `mkSecret "name"` reference anywhere under a value.
  secretRefs = v:
    if lib.isAttrs v && v ? __mikrotikSecret then [ v.__mikrotikSecret ]
    else if lib.isAttrs v then lib.concatMap secretRefs (lib.attrValues v)
    else if lib.isList v then lib.concatMap secretRefs v
    else [ ];

  cfg = config.mikrotik;
  referenced = lib.unique (lib.concatMap secretRefs (lib.attrValues cfg.sections));
  undeclared = builtins.filter (n: !(cfg.secrets ? ${n})) referenced;
  badPaths = builtins.filter (n: !(lib.hasPrefix "/" n)) (builtins.attrNames cfg.sections);

  # A secret name is also a file name in a secrets directory (README "Clan
  # vars": the generator's file names are the mkSecret names), so it has to be
  # one. The deploy tool refuses anything else, and the *silent* half of that
  # failure is the worse one: a name the tool's pattern cannot see would be
  # listed as "no secret placeholders" and deployed as a literal
  # __MIKROTIK_SECRET_… to a router, while a name carrying `/` or `..` would
  # turn `--secrets-dir` into a read outside that directory.
  secretNameRe = "^[A-Za-z0-9][A-Za-z0-9._-]*$";
  badSecretNames = builtins.filter
    (n: builtins.match secretNameRe n == null)
    (lib.unique (referenced ++ builtins.attrNames cfg.secrets));
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

  options.mikrotik = {
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

        The menus in `lib/menus.nix` are also options in their own right
        (`mikrotik.ip."dhcp-server".network`), which is the same thing spelled
        as an attribute path. Both render identically and may be mixed; this
        option stays the way to reach a menu the table does not list.
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
  };

  config = {
    assertions = [
      {
        assertion = cfg.hostname != "";
        message = "mikrotik.hostname must not be empty";
      }
      {
        # A `/system identity` section would fight the hostname option, and
        # whichever renders second wins silently.
        assertion = !(cfg.sections ? "/system identity");
        message = ''
          mikrotik.sections."/system identity" is not allowed: set
          mikrotik.hostname instead.
        '';
      }
      {
        assertion = badPaths == [ ];
        message = ''
          mikrotik.sections keys must be RouterOS command paths beginning with
          "/" (offending: ${toString badPaths})
        '';
      }
      {
        assertion = undeclared == [ ];
        message = ''
          a mkSecret reference has no matching mikrotik.secrets.<name> entry:
          ${toString undeclared}
        '';
      }
      {
        assertion = badSecretNames == [ ];
        message = ''
          these secret names are not usable as file names, and a secret name is
          also the name of the file the deploy tool reads the value from:
          letters, digits, dot, dash and underscore only, starting with a letter
          or a digit (offending: ${toString badSecretNames})
        '';
      }
    ];
  };
}
