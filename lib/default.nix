# The public interface of the mikrotik module class.
#
# `evalMikrotik` is the whole point: it evaluates modules of class "mikrotik"
# and hands back the same `config` shape a NixOS module set would, so a
# configuration composes with `imports` exactly like a NixOS one does -- while
# what comes out is a RouterOS script rather than a system closure.
{ lib }:

let
  renderer = import ./render.nix { inherit lib; };
in
rec {
  inherit (renderer) render referencedSecrets isSecret placeholder;

  # The RouterOS menus the typed options are generated from, for callers that
  # want to enumerate or document them rather than hard-code a path.
  menus = import ./menus.nix;

  # The value a configuration writes where a secret belongs. It is a marker,
  # not a value: it renders to __MIKROTIK_SECRET_<name>__ and is substituted by
  # the deploy tool on the machine that holds the secret.
  mkSecret = name: { __mikrotikSecret = name; };

  # modules: modules of class "mikrotik"; base.nix is always included.
  #
  # menus.nix is included too, and included *first*, because it is the front end
  # that compiles the typed menu options into `mikrotik.sections`. Position
  # matters only where a path is written both ways: definitions are merged in
  # reverse module order, so the menus module -- first here -- contributes its
  # `add …` lines after those of the configuration's own `sections`. That is the
  # order the fleet's routers already render in (their own sections before the
  # sections a later module appends), so a menu can move from `sections` to the
  # typed options without moving its lines.
  #
  # The assertions are forced here rather than left in the config, because a
  # custom module class has no activation step to run them: a configuration
  # that silently keeps a broken assertion is worse than one that fails to
  # evaluate.
  evalMikrotik =
    { modules
    , specialArgs ? { }
    }:
    let
      result = lib.evalModules {
        class = "mikrotik";
        modules = [ ../modules/base.nix ../modules/menus.nix ] ++ modules;
        specialArgs = { inherit mkSecret; } // specialArgs;
      };
      failed = builtins.filter (a: !a.assertion) result.config.assertions;
    in
    if failed == [ ] then
      result.config
    else
      throw ''
        nix-mikrotik: this configuration does not evaluate:
        ${lib.concatMapStrings (a: "\n  - ${a.message}\n") failed}
      '';

  # Evaluate and render in one step. `config` is what `evalMikrotik` returns.
  renderConfig = config: renderer.render config;

  # A derivation holding router-config.rsc, so a build of the router's
  # configuration is a store path like any other.
  mkRouterScript =
    { pkgs
    , name ? "router"
    , config
    }:
    pkgs.runCommandLocal "mikrotik-${name}-script" { } ''
      mkdir -p $out
      cp ${pkgs.writeText "router-config.rsc" (renderer.render config)} $out/router-config.rsc
    '';
}
