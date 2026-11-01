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

      # Pure evaluation, system-independent: consumers and `nix eval` read this.
      evaluated = lib.mapAttrs
        (_: modules: mt.evalMikrotik { inherit modules; })
        exampleModules;

      # The configuration `checks.chr-deploy` applies to a real RouterOS.
      # Written for a CHR -- one ethernet port, no wireless -- rather than
      # reusing an example, which describes upstream's router (ether2 … sfp1).
      chrFixture = mt.evalMikrotik {
        modules = [ ./tests/fixtures/chr-configuration.nix ];
      };
    in
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [ "x86_64-linux" "aarch64-linux" ];

      flake = {
        # The module class itself.
        lib = mt;

        mikrotikModules = {
          base = ./modules/base.nix;
          hardening = ./modules/hardening.nix;
          # The typed menu options. It is part of the class, so `evalMikrotik`
          # always includes it; exporting it here is for consumers that build a
          # module list by hand.
          menus = ./modules/menus.nix;
        };

        mikrotikConfigurations = lib.mapAttrs
          (_: config: {
            inherit config;
            script = mt.render config;
          })
          evaluated;
      };

      perSystem = { pkgs, config, ... }:
        let
          chr = pkgs.callPackage ./chr { };
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
            nix-mikrotik = pkgs.callPackage ./pkgs/nix-mikrotik.nix { };
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
            default = chr.lab;
          };

          apps = {
            chr-lab = {
              type = "app";
              program = lib.getExe config.packages.chr-lab;
              meta.description = "Boot two MikroTik CHR VMs on a point-to-point link";
            };
            nix-mikrotik = {
              type = "app";
              program = lib.getExe config.packages.nix-mikrotik;
              meta.description = "Build, secret-deliver and deploy RouterOS scripts";
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
              inherit (mt) evalMikrotik evalMikrotikRaw mkSecret;
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
              refusedScript = ./tests/fixtures/refused.rsc;
            };

            # Several routers in one configuration: they compose instead of
            # colliding, each script keeps its own identity, and a refusal names
            # the router that is wrong.
            fleet = import ./tests/fleet.nix {
              inherit pkgs;
              inherit (mt) evalMikrotik evalMikrotikFleet evalMikrotikRaw mkSecret;
            };
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
