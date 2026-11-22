{
  description = "Declarative MikroTik RouterOS configuration: a module class, a build tool, a deploy tool";

  inputs = {
    # Unstable, deliberately: this repository ships a module *class* and a CLI,
    # not a NixOS system, and its consumers (ccpkgs, the lunix fleet) ride
    # unstable. Pinning a release branch here would evaluate the class with a
    # different `lib` than the flake that consumes it.
    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";

    flake-parts.url = "github:hercules-ci/flake-parts";
  };

  outputs = inputs@{ flake-parts, ... }:
    let
      lib = inputs.nixpkgs.lib;
      mt = import ./lib { inherit lib; };

      # Every example is a list of modules of class "mikrotik".
      exampleModules = {
        # The router written the way this fork expects.
        example = [ ./examples/module-configuration.nix ];
        # The same router with the typed menu options instead of string-keyed
        # sections; `checks.menus` requires the two renders to be identical.
        typed = [ ./examples/typed-module-configuration.nix ];
        # Upstream's configuration, wrapped rather than rewritten: proof that an
        # existing config ports by moving it under `mikrotik.sections`.
        legacy = [ ./examples/legacy-wrapper.nix ];
      };

      # Pure evaluation, system-independent in what it *means* -- but a
      # generator's `runtimeInputs` are store paths, so the config is evaluated
      # per system rather than once here. `nix eval` still reads
      # `flake.lib.evalMikrotik` for the pure form.
      evaluatedFor = pkgs: lib.mapAttrs
        (_: modules: mt.evalMikrotik { inherit modules pkgs; })
        exampleModules;

      # The configuration `checks.chr-deploy` applies to a real RouterOS.
      # Written for a CHR -- one ethernet port, no wireless -- rather than
      # reusing an example, which describes upstream's router (ether2 … sfp1).
      chrFixtureFor = pkgs: mt.evalMikrotik {
        modules = [ ./tests/fixtures/chr-configuration.nix ];
        inherit pkgs;
      };

      # Inside `perSystem` neither `config` nor `self'` is the flake-level view
      # -- `config` is the per-system module's config and `self'` is the flake
      # cut down to one system -- so the names `routers.nix` published are
      # handed down as a module argument. A separate module rather than a
      # `perSystem._module.args` line next to `perSystem` itself: two
      # definitions of `perSystem` in one module would have to merge, and one
      # of them is a function.
      routerNamesModule = { config, lib, ... }: {
        perSystem._module.args.routerNames =
          lib.sort lib.lessThan (lib.attrNames config.flake.mikrotikConfigurations);
      };
    in
    flake-parts.lib.mkFlake { inherit inputs; } {
      imports = [
        (import ./modules/flake/routers.nix { inherit mt; })
        routerNamesModule
      ];

      systems = [ "x86_64-linux" "aarch64-linux" ];

      # This repository's own routers/ convention, exercised on the examples:
      # `examples/routers/<name>/configuration.nix` publishes
      # `mikrotikConfigurations.<name>`, which is what a consumer gets without
      # writing any wiring of its own.
      mikrotik.routers.directory = ./examples/routers;

      # A router is evaluated against a package set, and there is exactly one
      # per flake output. The script is text and identical everywhere; what is
      # not identical is a generator's `runtimeInputs`, which are store paths
      # for the machine that will run the generator -- the deployer. This
      # repository deploys to CHRs and x86_64 hosts, so that is the set; a
      # consumer whose routers are built for several systems evaluates them
      # under `perSystem`, where `pkgs` is the system in question.
      mikrotik.routers.pkgs = inputs.nixpkgs.legacyPackages.x86_64-linux;

      flake = {
        # The module class itself.
        lib = mt;

        # The `routers/` convention, for consumers that would rather keep one
        # directory of routers than a table of modules.
        flakeModules.routers = import ./modules/flake/routers.nix { inherit mt; };

        mikrotikModules = {
          base = ./modules/base.nix;
          hardening = ./modules/hardening.nix;
          # The typed menu options. It is part of the class, so `evalMikrotik`
          # always includes it; exporting it here is for consumers that build a
          # module list by hand.
          menus = ./modules/menus.nix;
        };

        # `mikrotikConfigurations` is published by modules/flake/routers.nix,
        # from `examples/routers/` -- the same convention a consumer uses. The
        # `evaluated` set above stays for the checks, which assert on the
        # evaluated config rather than the rendered script.
      };

      perSystem = { pkgs, config, routerNames, ... }:
        let
          chr = pkgs.callPackage ./chr { };
          evaluated = evaluatedFor pkgs;
          chrFixture = chrFixtureFor pkgs;

          # Every router `mikrotik.routers.directory` published, in name order.
          # `nix run .#generate -- --state-dir ./vars` is then the one command
          # that mints the values of a whole `routers/` directory: the manifests
          # are store paths passed to one `nix-mikrotik generate` call, so the
          # tool sees them all and a shared generator runs once.
          #
          # `routerNames` is handed in from the flake module (see
          # `perSystem._module.args` below) because neither `config` nor `self'`
          # inside `perSystem` is the flake-level view: `config` is the
          # per-system config and `self'` is the flake cut down to one system,
          # so `mikrotikConfigurations` is not on either.
          routerManifests = map
            (name: config.packages."mikrotik-${name}-generators")
            routerNames;
        in
        {
          # One script derivation per example, per system: `nix build
          # .#packages.x86_64-linux.mikrotik-example-script`.
          packages = lib.mapAttrs'
            (name: cfg:
              lib.nameValuePair "mikrotik-${name}-script"
                (mt.mkRouterScript { inherit pkgs name; config = cfg; }))
            evaluated
          // {
            nix-mikrotik = pkgs.callPackage ./pkgs/nix-mikrotik.nix {
              # The differ `deploy` drives, from this same flake: one pin, so
              # the CLI and the crate cannot disagree about a patch.
              rsc = config.packages.rsc;
            };
            # The `.rsc` parser, differ and patch generator. Its own test suite
            # runs in the build, so `nix build .#rsc` is the check.
            rsc = pkgs.callPackage ./pkgs/rsc.nix { };
            chr-lab = chr.lab;
            mikrotik-chr = chr.image;
            mikrotik-option = chr.optionPackage;
            # `checks.chr-deploy` applies this one to a CHR; it is a package so
            # that the same script can be deployed by hand to a lab device.
            mikrotik-chr-fixture-script = mt.mkRouterScript {
              inherit pkgs;
              name = "chr-fixture";
              config = chrFixture;
            };
            # The same configuration's generators, as the manifest the tool
            # reads: `checks.chr-deploy` mints the router's key from this
            # instead of being handed one, which is the path a consumer takes.
            mikrotik-chr-fixture-generators = pkgs.writeText "chr-fixture-generators.json"
              (builtins.toJSON (mt.manifest chrFixture));
            # The `routers/` convention as one command. Each router publishes its
            # own manifest; this passes all of them to one `generate` call, so
            # the tool runs the generators in dependency order across the
            # directory instead of per router, and a generator two routers share
            # is minted once.
            mikrotik-generate = pkgs.writeShellApplication {
              name = "mikrotik-generate";
              runtimeInputs = [ config.packages.nix-mikrotik ];
              text = ''
                manifests=${toString (builtins.length routerManifests)}
                if [ "$manifests" -eq 0 ]; then
                  echo "mikrotik-generate: no routers under mikrotik.routers.directory" >&2
                  exit 2
                fi
                exec nix-mikrotik generate ${lib.concatStringsSep " " (map toString routerManifests)} "$@"
              '';
              meta.description =
                "Generate the vars every router under mikrotik.routers.directory declares";
            };
            default = chr.lab;
          };

          apps = {
            chr-lab = {
              type = "app";
              program = lib.getExe config.packages.chr-lab;
              meta.description = "Boot two MikroTik CHR VMs on a point-to-point link";
            };
            # `nix run .#generate -- --state-dir ./vars`, and the same app with
            # `--prompt NAME=VALUE` for a generator that asks something.
            generate = {
              type = "app";
              program = lib.getExe config.packages.mikrotik-generate;
              meta.description = "Run every router's secret generators into a state directory";
            };
            nix-mikrotik = {
              type = "app";
              program = lib.getExe config.packages.nix-mikrotik;
              meta.description = "Build, secret-deliver and deploy RouterOS scripts";
            };
            rsc = {
              type = "app";
              program = lib.getExe config.packages.rsc;
              meta.description = "Parse, diff and patch RouterOS .rsc scripts";
            };
            default = config.apps.chr-lab;
          };

          checks = {
            # The renderer against upstream's own generator's output for
            # upstream's own example: the same `add`/`set` lines in the same
            # order, plus four documented deviations (tests/golden/README.md).
            render = import ./tests/render.nix {
              inherit pkgs;
              inherit (mt) render;
              legacy = evaluated.legacy;
              example = evaluated.example;
            };

            # The typed menu options render what `sections` renders: one
            # configuration written both ways, byte-compared.
            menus = import ./tests/menus.nix {
              inherit pkgs lib;
              inherit (mt) evalMikrotik render menus;
              inherit (evaluated) example typed;
            };

            # The `networks.<name>` schema fixture: the whole render, and the
            # generator manifest the deploy tool reads off the same config.
            networks = import ./tests/networks.nix {
              inherit pkgs;
              inherit (mt) render generators;
              config = mt.evalMikrotik {
                modules = [
                  ./examples/networks.nix
                  { networks."9600-baud".enable = true; }
                ];
                inherit pkgs;
              };
            };

            # `nix run .#generate` against the example `routers/` directory: one
            # command mints a whole fleet's vars, and it has to reach *every*
            # router -- a routers/ that silently generated for one of two is the
            # failure this check exists for.
            routers-generate = pkgs.runCommand "check-routers-generate" { } ''
              set -eu
              mkdir -p "$out"
              generate=${config.packages.mikrotik-generate}/bin/mikrotik-generate

              "$generate" --state-dir "$out/state" > "$out/first.txt"
              # One value per router, filed under its key in `mikrotik.routers`
              # -- not its hostname -- in clan's `per-machine` layout.
              grep -qx 'example-wg-key/privkey' "$out/first.txt"
              grep -qx 'legacy-key/privkey' "$out/first.txt"
              example_key="$out/state/per-machine/example/example-wg-key/privkey"
              legacy_key="$out/state/per-machine/legacy/legacy-key/privkey"
              [ -f "$example_key" ]
              [ -f "$legacy_key" ]
              [ "$(stat -c %a "$example_key")" = "400" ]
              # `wg genkey` output: 32 bytes of base64, so 44 characters and a
              # newline. A generator that quietly wrote nothing would leave an
              # empty file here and still exit 0.
              [ "$(wc -c < "$example_key")" = "45" ]
              [ "$(wc -c < "$legacy_key")" = "45" ]

              # Running it again reads what it minted: a second key would break
              # the tunnel the first one already opened.
              cp "$example_key" "$out/before"
              "$generate" --state-dir "$out/state" > "$out/second.txt"
              grep -qx 'example-wg-key/privkey' "$out/second.txt"
              cmp "$out/before" "$example_key"
            '';

            # The CLI's secret handling: placeholders listed, substituted with
            # the quoting RouterOS needs, and refused when a value or a name is
            # unusable -- plus the claim its failure message is allowed to make.
            cli = import ./tests/cli.nix {
              inherit pkgs;
              nix-mikrotik = config.packages.nix-mikrotik;
              cliSource = ./pkgs/nix_mikrotik.py;
            };

            # The class refuses what it says it refuses, with a diagnostic that
            # names the fix: every assertion, plus the control that must pass.
            eval = import ./tests/eval.nix {
              inherit pkgs;
              inherit (mt) evalMikrotik evalMikrotikRaw generators manifest;
            };

            # Boot the pinned CHR image and wait for a RouterOS login prompt.
            chr-smoke = import ./tests/chr-smoke.nix {
              inherit pkgs;
              imageFile = chr.imageFile;
            };

            # Apply a rendered configuration to that CHR and read the device
            # back: the renderer's output has to be something RouterOS accepts
            # and ends up holding, which no pure check can see.
            chr-deploy = import ./tests/chr-deploy.nix {
              inherit lib pkgs;
              inherit (chr) imageFile;
              nix-mikrotik = config.packages.nix-mikrotik;
              harness = pkgs.runCommandLocal "chr-deploy-check" { } ''
                install -Dm755 ${./tests/chr-deploy.py} $out/bin/chr-deploy-check
                patchShebangs $out/bin
              '';
              script = config.packages.mikrotik-chr-fixture-script;
              generators = config.packages.mikrotik-chr-fixture-generators;
              refusedScript = ./tests/fixtures/refused.rsc;
            };

            # Several routers in one configuration: they compose instead of
            # colliding, each script keeps its own identity, and a refusal names
            # the router that is wrong.
            fleet = import ./tests/fleet.nix {
              inherit pkgs;
              inherit (mt) evalMikrotik evalMikrotikFleet evalMikrotikFleetConfigs evalMikrotikRaw mkSecret generators;
            };

            # The `.rsc` parser's own suite: the round trip over the renderer's
            # goldens and a real 7.15.3 export, and the upsert property (applying
            # the patch to the model of the first file yields the second). It
            # runs in the package's check phase, so this check is that build.
            rsc = config.packages.rsc;
          };

          devShells.default = pkgs.mkShell {
            packages = with pkgs; [
              nixpkgs-fmt
              python3
              qemu
              openssh
            ];
            shellHook = ''
              echo "nix-mikrotik dev shell"
              echo "  nix build .#mikrotik-example-script"
              echo "  nix run .#chr-lab -- start"
            '';
          };

          formatter = pkgs.nixpkgs-fmt;
        };
    };
}
