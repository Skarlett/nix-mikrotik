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

  # The value a configuration writes where a secret belongs. It is a marker,
  # not a value: it renders to __MIKROTIK_SECRET_<name>__ and is substituted by
  # the deploy tool on the machine that holds the secret.
  mkSecret = name: { __mikrotikSecret = name; };

  # modules: modules of class "mikrotik"; the evaluated config together with the
  # assertions it failed, without deciding what to do about them.
  #
  # `evalMikrotik` throws on those, and a `throw`'s text cannot be read back
  # through `builtins.tryEval` -- so a test that checks the *diagnostic* rather
  # than only that something was refused asks here.
  evalMikrotikRaw =
    { modules
    , specialArgs ? { }
    }:
    let
      result = lib.evalModules {
        class = "mikrotik";
        modules = [ ../modules/base.nix ] ++ modules;
        specialArgs = { inherit mkSecret; } // specialArgs;
      };
    in
    {
      config = result.config;
      failed = builtins.filter (a: !a.assertion) result.config.assertions;
    };

  # modules: modules of class "mikrotik"; base.nix is always included.
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
      plan = evalMikrotikRaw { inherit modules specialArgs; };
    in
    if plan.failed == [ ] then
      plan.config
    else
      throw ''
        nix-mikrotik: this configuration does not evaluate:
        ${lib.concatMapStrings (a: "\n  - ${a.message}\n") plan.failed}
      '';

  # Evaluate and render in one step. `config` is what `evalMikrotik` returns.
  renderConfig = config: renderer.render config;

  # The fleet form: every router declared under `mikrotik.routers`, rendered.
  #
  # The single-router options are not rendered here -- a configuration that
  # fills them in as well is refused by an assertion rather than silently
  # producing a script the fleet does not name.
  evalMikrotikFleet =
    { modules
    , specialArgs ? { }
    }:
    let
      cfg = (evalMikrotik { inherit modules specialArgs; }).mikrotik;
    in
    lib.mapAttrs (_name: router: renderer.render { mikrotik = router; }) cfg.routers;

  # The fleet as derivations, one directory per router: `$out/<name>/router-config.rsc`.
  mkRouterFleetScripts =
    { pkgs
    , config
    }:
    pkgs.runCommandLocal "mikrotik-fleet-scripts" { } (
      lib.concatStringsSep "\n" (
        lib.mapAttrsToList
          (name: router: ''
            mkdir -p $out/${name}
            cp ${pkgs.writeText "${name}-config.rsc" (renderer.render { mikrotik = router; })} $out/${name}/router-config.rsc
          '')
          config.mikrotik.routers
      )
    );

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
