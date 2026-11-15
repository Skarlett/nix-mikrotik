# Discover `routers/`, the way clan discovers `machines/`.
#
# A router is not a NixOS machine, so there is no `nixosConfigurations.<name>` to
# hang it on -- which left a fleet either keeping a table of router modules by
# hand, or (worse) inventing a stub machine so that a directory-shaped tool could
# find it. This module is the directory-shaped tool: point it at a tree
#
#     routers/
#       chr1/configuration.nix        a module of class `mikrotik`
#       homelab-router/configuration.nix
#
# and it publishes `flake.mikrotikConfigurations.<name>` for each one, plus a
# `mikrotik-<name>` package per system. A router that is contributed by a clan
# service instead (`flake.classModules.mikrotik.<machine>`) goes through
# `extraModules`; both routes land in the same output, so consumers do not care
# which one a given router came from.
#
# Usage, in the consuming flake:
#
#     imports = [ inputs.nix-mikrotik.flakeModules.routers ];
#     mikrotik.routers.directory = ./routers;
#     mikrotik.routers.extraModules = [ config.flake.classModules.mikrotik.flagship ];
#
# The options live at `mikrotik.routers.*` rather than under `flake.*` so that a
# consumer's own flake-level options do not collide with them.
# `mt` is nix-mikrotik's own library, captured at the flake that defines this
# module: inside a *consumer*, `self` is the consumer, so the class had to be
# passed in rather than reached for.
{ mt }:
{ lib, config, ... }:
let
  cfg = config.mikrotik.routers;

  # `<name>/configuration.nix` is the convention; `<name>.nix` is accepted too,
  # so a one-file router does not need a directory of its own.
  entries = if cfg.directory == null then { } else builtins.readDir cfg.directory;

  fromDirectory = lib.mapAttrs
    (name: _: "${toString cfg.directory}/${name}/configuration.nix")
    (lib.filterAttrs (_: type: type == "directory") entries);

  looseFiles = lib.mapAttrs'
    (name: _:
      lib.nameValuePair (lib.removeSuffix ".nix" name) "${toString cfg.directory}/${name}")
    (lib.filterAttrs (name: type: type == "regular" && lib.hasSuffix ".nix" name) entries);

  moduleFiles = fromDirectory // looseFiles;

  # One router per entry, evaluated on its own -- a router is its own
  # configuration, and `extraModules` is the only thing shared between them.
  #
  # Evaluated through the *fleet* form (`mikrotik.routers.<name>`) rather than as
  # a lone configuration, so that a contribution keyed by router name merges into
  # the right one: the address-space sections a flake adds to exactly one router,
  # or a clan service's `mikrotik.routers.<instance>`. A lone evaluation would
  # have nowhere to put either.
  evaluated = lib.mapAttrs
    (name: file:
      (mt.evalMikrotikFleetConfigs {
        modules = [ { mikrotik.routers.${name} = file; } ] ++ cfg.extraModules;
        inherit (cfg) pkgs specialArgs;
      }).${name})
    moduleFiles;

  # Routers a clan service contributed: one module holding
  # `mikrotik.routers.<name>`, evaluated per name.
  fromServices = mt.evalMikrotikFleetConfigs {
    modules = cfg.extraModules;
    inherit (cfg) pkgs specialArgs;
  };

  # What a consumer reads: the script to send, and the generators that have to
  # run before it can be sent (their placeholders are what it contains).
  rendered = lib.mapAttrs
    (_: router: {
      script = mt.renderConfig router;
      generators = mt.generators router;
      manifest = mt.manifest router;
    })
    (evaluated // fromServices);
in
{
  options.mikrotik.routers = {
    directory = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      example = lib.literalExpression "./routers";
      description = ''
        Directory of routers. Each subdirectory (or sibling `.nix` file) is one
        router, written as a module of class `mikrotik` in `configuration.nix`
        -- the same convention `machines/` uses, for the same reason.
      '';
    };

    extraModules = lib.mkOption {
      type = lib.types.listOf lib.types.deferredModule;
      default = [ ];
      example = lib.literalExpression ''
        [ config.flake.classModules.mikrotik.flagship ]
      '';
      description = ''
        Modules appended to every router's evaluation. This is where a clan
        service's contribution goes: `flake.classModules.mikrotik.<machine>` is
        one module holding `mikrotik.routers.<name>` for every instance, and
        `evalMikrotikFleet` renders it.
      '';
    };

    pkgs = lib.mkOption {
      type = lib.types.attrs;
      description = ''
        The package set handed to every router as the `pkgs` module argument, and
        to the evaluator as a required one. A router declares a generator with
        `runtimeInputs = [ pkgs.… ]`, so the values that end up in the script are
        built from a real package set, not resolved lazily at deploy time.

        There is no default and no null: evaluating a router without `pkgs` would
        only postpone the failure to a generator that needs a tool, so the
        flake does not offer that shape at all. Set it from `perSystem`
        (`mikrotik.routers.pkgs = pkgs;` inside `perSystem`, or
        `mkDefault inputs.nixpkgs.legacyPackages.<system>.pkgs` at flake level).
      '';
    };

    specialArgs = lib.mkOption {
      type = lib.types.attrsOf lib.types.anything;
      default = { };
      description = ''
        Extra module arguments for every router, on top of `mkSecret` and `pkgs`
        -- for a router module that wants, say, its address plan handed in rather
        than imported.
      '';
    };
  };

  config = lib.mkMerge [
    (lib.mkIf (cfg.directory != null || cfg.extraModules != [ ]) {
      # One definition for both sources: a directory router and a service
      # contribution are two ways to fill the same output, and two assignments
      # would collide rather than merge.
      flake.mikrotikConfigurations = rendered;
    })

    (lib.mkIf (cfg.directory != null || cfg.extraModules != [ ]) {
      perSystem = { pkgs, ... }: {
        packages = lib.mapAttrs'
          (name: router: lib.nameValuePair "mikrotik-${name}" (pkgs.writeTextDir "router-config.rsc" router.script))
          rendered
        // lib.mapAttrs'
          # The manifest `nix-mikrotik generate` and `--generators` read: what it
          # can mint, and what it has to read from `--secrets-dir`. A package
          # rather than a string so a deploy unit can name it like any other
          # path, and so `nix build .#mikrotik-<name>-generators` prints it.
          (name: router: lib.nameValuePair "mikrotik-${name}-generators" (pkgs.writeText "${name}-generators.json" (builtins.toJSON router.manifest)))
          rendered;
      };
    })
  ];
}
