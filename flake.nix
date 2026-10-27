{
  description = "Declarative MikroTik RouterOS configuration: a module class, a build tool, a deploy tool";

  inputs.nixpkgs.url = "github:nixos/nixpkgs/nixos-25.11";

  outputs = { self, nixpkgs }:
    let
      inherit (nixpkgs) lib;
      mt = import ./lib { inherit lib; };

      systems = [ "x86_64-linux" "aarch64-linux" ];
      eachSystem = lib.genAttrs systems;

      # Every example is a list of modules of class "mikrotik".
      exampleModules = {
        # The router written the way this fork expects.
        example = [ ./examples/module-configuration.nix ];
        # Upstream's configuration, wrapped rather than rewritten: proof that an
        # existing config ports by moving it under `mikrotik.sections`.
        legacy = [ ./examples/legacy-wrapper.nix ];
      };

      # Pure evaluation, system-independent: consumers and `nix eval` read this.
      evaluated = lib.mapAttrs
        (_: modules: mt.evalMikrotik { inherit modules; })
        exampleModules;
    in
    {
      # The module class itself.
      lib = mt;

      mikrotikModules = {
        base = ./modules/base.nix;
        hardening = ./modules/hardening.nix;
      };

      mikrotikConfigurations = lib.mapAttrs
        (name: config: { inherit config; script = mt.render config; })
        evaluated;

      # One script derivation per example, per system: `nix build
      # .#packages.x86_64-linux.mikrotik-example-script`.
      packages = eachSystem (system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          chr = pkgs.callPackage ./chr { };
        in
        lib.mapAttrs'
          (name: config:
            lib.nameValuePair "mikrotik-${name}-script"
              (mt.mkRouterScript { inherit pkgs name config; }))
          evaluated
        // {
          nix-mikrotik = pkgs.callPackage ./pkgs/nix-mikrotik.nix { };
          chr-lab = chr.lab;
          mikrotik-chr = chr.image;
          mikrotik-option = chr.optionPackage;
          default = chr.lab;
        });

      apps = eachSystem (system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        {
          chr-lab = {
            type = "app";
            program = lib.getExe self.packages.${system}.chr-lab;
            meta.description = "Boot two MikroTik CHR VMs on a point-to-point link";
          };
          nix-mikrotik = {
            type = "app";
            program = lib.getExe self.packages.${system}.nix-mikrotik;
            meta.description = "Build, secret-deliver and deploy RouterOS scripts";
          };
          default = self.apps.${system}.chr-lab;
        });

      checks = eachSystem (system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          chr = pkgs.callPackage ./chr { };
        in
        {
          # The renderer is byte-compatible with upstream for upstream's own
          # example, and the module class adds the rest.
          render = import ./tests/render.nix {
            inherit pkgs;
            inherit (mt) render;
            legacy = evaluated.legacy;
            example = evaluated.example;
          };

          # The CLI's secret handling: placeholders listed, substituted, and
          # refused when a value is missing.
          cli = import ./tests/cli.nix {
            inherit pkgs;
            nix-mikrotik = pkgs.callPackage ./pkgs/nix-mikrotik.nix { };
          };

          # Boot the pinned CHR image and wait for a RouterOS login prompt.
          chr-smoke = import ./tests/chr-smoke.nix {
            inherit pkgs;
            imageFile = chr.imageFile;
          };
        });

      devShells = eachSystem (system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        {
          default = pkgs.mkShell {
            packages = with pkgs; [
              nixpkgs-fmt
              python3
              qemu
              openssh
            ];
            shellHook = ''
              echo "nix-mikrotik dev shell"
              echo "  nix build .#packages.$(nix eval --impure --raw --expr builtins.currentSystem).mikrotik-example-script"
              echo "  nix run .#chr-lab -- start"
            '';
          };
        });

      formatter = eachSystem (system: nixpkgs.legacyPackages.${system}.nixpkgs-fmt);
    };
}
