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
  # not a value: it renders to __MIKROTIK_SECRET_<generator>/<file>__ and is
  # substituted by the deploy tool on the machine that holds the value.
  #
  # Prefer the declared placeholder -- `clan.core.vars.generators.<g>.files.<f>.placeholder`
  # -- because the assertion that matches placeholders against declarations
  # names the generator and the file when it fails. This is for a module that
  # has to build a set of cells and has no declaration to reach for.
  mkSecret = name: { __mikrotikSecret = name; };

  # modules: modules of class "mikrotik"; the evaluated config together with the
  # assertions it failed, without deciding what to do about them.
  #
  # `evalMikrotik` throws on those, and a `throw`'s text cannot be read back
  # through `builtins.tryEval` -- so a test that checks the *diagnostic* rather
  # than only that something was refused asks here.
  #
  # menus.nix is part of the class and comes straight after base.nix, because it
  # is the front end that compiles the typed menu options into
  # `mikrotik.sections`. Its position matters only where a path is written both
  # ways: definitions are merged in reverse module order, so the menus module --
  # first here -- contributes its `add …` lines after those of the
  # configuration's own `sections`. That is the order the fleet's routers already
  # render in (their own sections before the sections a later module appends), so
  # a menu can move from `sections` to the typed options without moving its
  # lines.
  # pkgs is a required argument, not an optional one: a generator's
  # `runtimeInputs` are store paths and `finalScript` puts `pkgs.coreutils` on
  # the PATH it will run under, so a configuration cannot be evaluated without a
  # package set. It is handed to the modules through `specialArgs` as well,
  # because a module that mentions `pkgs` at all may only do so under the name
  # the argument set actually carries.
  evalMikrotikRaw =
    { modules
    , pkgs
    , specialArgs ? { }
    }:
    let
      result = lib.evalModules {
        class = "mikrotik";
        modules = [ ../modules/base.nix ../modules/menus.nix ] ++ modules;
        # `pkgs` is handed to the modules here and *cannot* be replaced by a
        # caller: the evaluator's `pkgs` is the one a generator's `runtimeInputs`
        # and `finalScript` were rendered against, so a module seeing a different
        # set would be reading a different configuration than the one that was
        # built. `specialArgs` extends the argument set; it does not override it.
        specialArgs = specialArgs // { inherit mkSecret pkgs; };
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
    , pkgs
    , specialArgs ? { }
    }:
    let
      plan = evalMikrotikRaw { inherit modules specialArgs pkgs; };
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

  # The generators a configuration declares, as data the deploy tool reads.
  # The shape is clan's generator interface flattened for a manifest:
  #
  #   [ { name = "wg-9600-baud";
  #       share = false;
  #       dependencies = [ "wg-key" ];
  #       files = [ { name = "privkey"; secret = true;  mode = "0400"; deploy = true;  relDir = "per-machine/r1/wg-9600-baud"; }
  #                 { name = "pubkey";  secret = false; mode = "0400"; deploy = true;  relDir = "per-machine/r1/wg-9600-baud"; } ];
  #       prompts = [ { name = "passphrase"; description = "…"; type = "hidden"; persist = true; } ];
  #       validation = null;
  #       validationHash = null;
  #       runtimeInputs = [ "/nix/store/…-wireguard-tools" ];
  #       script = "…finalScript…"; } ]
  #
  # A list, in dependency order, because one generator reads another's output:
  # the tool runs it top to bottom and never has to sort. Each file carries its
  # own `relDir`, so the tool does not repeat the var-store layout.
  #
  # `script` is `finalScript` -- the text the tool actually runs -- not the
  # `script` a configuration wrote.
  generators = config:
    let
      all = config.clan.core.vars.generators;

      # Every generator after the ones it depends on. An unresolved dependency
      # (or a cycle, which base.nix refuses) leaves a name out of `ready`, and
      # the loop then stops instead of spinning: the configuration's own
      # assertions are what report it.
      order =
        let
          step = done: pending:
            let
              ready = builtins.filter
                (n: builtins.all (d: builtins.elem d done) all.${n}.dependencies)
                pending;
              done' = done ++ ready;
            in
            if ready == [ ] then done else step done' (builtins.filter (n: !builtins.elem n done') pending);
        in
        step [ ] (lib.attrNames all);
    in
    map
      (name: {
        inherit name;
        inherit (all.${name}) share dependencies validation validationHash;
        files = lib.mapAttrsToList
          (file: f: {
            name = file;
            inherit (f) secret mode deploy relDir;
          })
          all.${name}.files;
        prompts = lib.mapAttrsToList
          (prompt: p: {
            name = prompt;
            inherit (p) description type persist;
          })
          all.${name}.prompts;
        runtimeInputs = map toString all.${name}.runtimeInputs;
        script = all.${name}.finalScript;
      })
      order;

  # The values a configuration expects from elsewhere, as data the deploy tool
  # reads alongside the generators:
  #
  #   { "mesh-chr1-private-key" = { path = "per-machine/flagship/mikrotik-lab-peers/chr1"; description = "…"; }; }
  #
  # Keyed by the *placeholder* name, so the tool can join a placeholder it found
  # in the script to the path it should read it from. `path` is clan's own
  # spelling of where a generated file sits -- `per-machine/<machine>/<generator>`
  # or `shared/<generator>`, plus the file name -- relative to the vars directory
  # the deploy is pointed at with `--secrets-dir`; the class derives it from the
  # machine and the generator's `share` flag, so it cannot drift from what
  # `clan vars generate` wrote.
  varFiles = config:
    lib.mapAttrs
      (name: v: { inherit (v) path description; })
      config.mikrotik.varFiles;

  # Everything the deploy tool needs to resolve placeholders: what it can mint
  # (`generators`), and what it has to read from `--secrets-dir` (`varFiles`).
  #
  # One document rather than two files, because the tool is given one path
  # (`--generators`) and a value is either minted or read -- never both.
  manifest = config: {
    generators = generators config;
    varFiles = varFiles config;
  };

  # The fleet form, unevaluated: every router declared under `mikrotik.routers`,
  # as the config `evalMikrotik` would return for it.
  #
  # Each entry is a *module*, not a value: a router is a configuration of its
  # own, so it is evaluated on its own (and its own assertions run there) rather
  # than being merged into the fleet's configuration. That is also what lets a
  # clan service contribute one: a service instance holds a module, and two
  # instances compose because `mikrotik.routers.<name>` is keyed by name.
  #
  # The single-router options are not evaluated here -- a configuration that
  # fills them in as well is refused by an assertion rather than silently
  # producing a script the fleet does not name.
  evalMikrotikFleetConfigs =
    { modules
    , pkgs
    , specialArgs ? { }
    }:
    let
      cfg = (evalMikrotik { inherit modules specialArgs pkgs; }).mikrotik;
    in
    lib.mapAttrs
      (name: routerModule:
      # The router's own assertions say "mikrotik.secrets", which in a fleet
      # of twenty points at no router in particular; the context line is what
      # makes the failure findable.
      builtins.addErrorContext "while evaluating mikrotik.routers.${name}" (
        evalMikrotik {
          modules = [
            routerModule
            # The fleet key names the router's var directory, not its hostname:
            # renaming the router keeps its generated keys, and no two routers
            # can land in the same directory. `mkForce` because a router that
            # set `routerName` itself would quietly file its secrets somewhere
            # the rest of the fleet does not look.
            { mikrotik.routerName = lib.mkForce name; }
          ];
          inherit specialArgs pkgs;
        }
      ))
      cfg.routers;

  # The fleet form: every router declared under `mikrotik.routers`, rendered.
  evalMikrotikFleet =
    { modules
    , pkgs
    , specialArgs ? { }
    }:
    lib.mapAttrs
      (_: config: renderConfig config)
      (evalMikrotikFleetConfigs { inherit modules specialArgs pkgs; });

  # The fleet as derivations, one directory per router: `$out/<name>/router-config.rsc`.
  mkRouterFleetScripts =
    { pkgs
    , modules
    , specialArgs ? { }
    }:
    let
      rendered = evalMikrotikFleet { inherit modules specialArgs pkgs; };
    in
    pkgs.runCommandLocal "mikrotik-fleet-scripts" { } (
      lib.concatStringsSep "\n" (
        lib.mapAttrsToList
          (name: script: ''
            mkdir -p $out/${name}
            cp ${pkgs.writeText "${name}-config.rsc" script} $out/${name}/router-config.rsc
          '')
          rendered
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
