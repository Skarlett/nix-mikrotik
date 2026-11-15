# The base module of the `mikrotik` module class.
#
# A configuration is evaluated with `lib.evalMikrotik` (or a flake's
# `mikrotikConfigurations.<name>`), never imported into a NixOS system: RouterOS
# is not NixOS, and pretending otherwise is what makes router automation
# opaque. The class exists so that the same conventions apply -- options with
# types and defaults, modules that compose, assertions that fail the build --
# while the output is a RouterOS script.
{ config, lib, pkgs, ... }:
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

    # A value this router does not mint: it was generated somewhere else (a clan
    # machine's generator, typically the controller that owns the tunnel) and the
    # deploy tool only has to read it out of `--secrets-dir`. Naming it here is
    # what separates "the value exists elsewhere" from "the value does not exist
    # at all" -- and the failure mode being guarded against is a typo in a
    # `mkSecret` call, which is silent unless the name is known in advance.
    #
    # The entry describes a *generated file the way clan describes one*, not a
    # second scheme: clan files a generator's files under
    #
    #     per-machine/<machine>/<generator>/<file>    (generator.share = false)
    #     shared/<generator>/<file>                   (generator.share = true)
    #
    # and `path` below is exactly that, relative to the vars directory the deploy
    # is pointed at with `--secrets-dir`. `relDir` is derived the way clan derives
    # it -- from the machine and the generator's `share` flag -- so a value clan
    # generated is found without restating where clan put it, and a value that
    # moves (a target renamed to a machine, `share` flipped on) moves here too.
    varFiles = mkOption {
      type = types.attrsOf (types.submodule ({ name, config, ... }:
        let
          # The placeholder name is already clan's identity for a file *inside* a
          # generator (`<generator>/<file>`), so the common entry states nothing
          # at all: no generator, no file, no path.
          parts = lib.splitString "/" name;
          named = lib.length parts == 2;
        in
        {
          options = {
            description = mkOption {
              type = types.nullOr types.str;
              default = null;
              description = "What the value is, for generated documentation.";
            };
            generator = mkOption {
              type = types.nullOr types.str;
              default = if named then lib.head parts else null;
              defaultText = literalExpression "the `<generator>` half of the attribute name";
              description = ''
                The generator that mints it (`clan.core.vars.generators.<name>`),
                which is also the directory clan files it in. Taken from the
                attribute name when that is `<generator>/<file>`.
              '';
            };
            file = mkOption {
              type = types.str;
              default = if named then lib.elemAt parts 1 else name;
              defaultText = literalExpression "the `<file>` half of the attribute name";
              description = "The file's name inside that generator (`files.<name>`).";
            };
            machine = mkOption {
              type = types.nullOr types.str;
              default = null;
              defaultText = literalExpression "config.mikrotik.routerName";
              description = ''
                The vars root that holds it: clan files a non-shared generator
                under `per-machine/<machine>/<generator>`. Defaults to this
                router's own name, which is where its own generators land; set it
                for a value minted on the machine that deploys (the usual case,
                since that is the machine that holds the tunnel's other end).
              '';
            };
            share = mkOption {
              type = types.bool;
              default = false;
              description = ''
                Mirror of the generator's `share` flag: a shared var is filed
                once under `shared/<generator>` instead of per machine.
              '';
            };
            relDir = mkOption {
              type = types.str;
              readOnly = true;
              description = ''
                The generator's directory, spelled the way clan spells its
                `rel_dir` -- the one thing a deploy has to agree on.
              '';
              default =
                if config.share then
                  "shared/${toString config.generator}"
                else
                  "per-machine/${if config.machine != null then config.machine else cfg.routerName}/${toString config.generator}";
            };
            path = mkOption {
              type = types.str;
              readOnly = true;
              description = ''
                `relDir` and the file name: the path of the value under
                `--secrets-dir`, which is the vars directory (`vars/`) the deploy
                is pointed at. This is what the manifest carries, and what the
                deploy tool joins to `--secrets-dir`.
              '';
              default = "${config.relDir}/${config.file}";
            };
          };
        }));
      default = { };
      example = literalExpression ''
        {
          # Minted on the machine that deploys, by a generator of its own.
          "wg-mesh-chr1-private-key" = { machine = "flagship"; };

          # A shared var: `shared/<generator>/<file>`, no machine.
          "lab-peers/chr1" = { share = true; };
        }
      '';
      description = ''
        Values that are not produced by this router's own generators, keyed by
        the name a menu cell references with `mkSecret`.

        An entry is clan's description of a generated file: a generator, a file
        inside it, and the machine whose vars root holds it. `path` is derived
        from those (`per-machine/<machine>/<generator>/<file>`, or
        `shared/<generator>/<file>`), so it agrees with `clan vars generate` by
        construction rather than by a second convention that has to be kept in
        step by hand.

        Prefer a `clan.core.vars.generators` declaration whenever the value can
        be minted at deploy time; this option is for a key another host already
        owns, such as a router's WireGuard key generated on its controller.
      '';
    };

    routerName = mkOption {
      type = types.str;
      default = config.mikrotik.hostname;
      description = ''
        The name this router's vars are filed under:
        `vars/per-machine/<routerName>/<generator>/<file>`.

        Defaults to the hostname, which is what a lone router is called. A
        fleet sets it to the fleet key (`mikrotik.routers.<name>`), so a router
        keeps its vars when its hostname changes and two routers never share a
        directory by accident.
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

  # Secret names are also paths in the var store
  # (`vars/per-machine/<router>/<generator>/<file>`), so they have to be
  # usable as one. The deploy tool refuses anything else, and the *silent*
  # half of that failure is the worse one: a name the tool's pattern cannot
  # see would be listed as "no secret placeholders" and deployed as a literal
  # __MIKROTIK_SECRET_… to a router, while a name carrying `..` would turn
  # `--vars-dir` into a read outside that directory.
  #
  # A generated file is named `<generator>/<file>`: exactly one level, because
  # it is also the path the deploy tool keeps the value at, and a second level
  # would be a directory the tool never creates.
  secretPartRe = "[A-Za-z0-9][A-Za-z0-9._-]*";
  secretNameRe = "^${secretPartRe}(/${secretPartRe})?$";

  # A `varFiles` entry has to resolve to a real file under the vars directory:
  # a generator (which is a directory), the file inside it, and -- unless the
  # generator is shared -- the machine. `..` and an absolute path are both ways
  # to read outside `--secrets-dir`, and an empty segment is a path that exists
  # nowhere; all three are refused here rather than at a deploy.
  varPathRe = "^(${secretPartRe}/)+${secretPartRe}$";
  badVarFiles = lib.filter
    (name:
      let entry = cfg.varFiles.${name}; in
      entry.generator == null
      || builtins.match varPathRe entry.path == null
      || lib.any (segment: segment == "." || segment == "..") (lib.splitString "/" entry.path))
    (lib.attrNames cfg.varFiles);

  # Every `<generator>/<file>` this router's
  # `clan.core.vars.generators` declarations produce: the identities a menu
  # body may put in a cell, and the ones the deploy tool generates before it
  # substitutes.
  generatorFiles = builtins.listToAttrs (lib.concatMap
    (name: map
      (file: {
        name = "${name}/${file}";
        value = null;
      })
      (lib.attrNames config.clan.core.vars.generators.${name}.files))
    (lib.attrNames config.clan.core.vars.generators));

  # `$in/<generator>/<file>` is how a generator reads another one, so a
  # dependency that is not a declared generator is a file that never appears --
  # and the script fails at deploy time, on a router, with a shell error
  # instead of a Nix one.
  #
  # A cycle would leave the deploy tool with no order to run them in. Depth
  # first, carrying the path: a name already on it closes a loop.
  # A dependency that is not declared is reported by its own assertion below, so
  # the cycle walk steps over it instead of failing on a missing attribute: one
  # diagnostic, not a stack trace.
  depsAcyclic = generators:
    let
      visit = path: name:
        if !(generators ? ${name}) then
          true
        else if builtins.elem name path then
          false
        else
          builtins.all (dep: visit (path ++ [ name ]) dep) generators.${name}.dependencies;
    in
    builtins.all (name: visit [ ] name) (lib.attrNames generators);

  gens = config.clan.core.vars.generators;

  problemsFor =
    declared: r:
    let
      referenced = lib.unique (lib.concatMap secretRefs (lib.attrValues r.sections));
      undeclared = builtins.filter (n: !(declared ? ${n})) referenced;
      badPaths = builtins.filter (n: !(lib.hasPrefix "/" n)) (builtins.attrNames r.sections);
      badSecretNames = builtins.filter
        (n: builtins.match secretNameRe n == null)
        (lib.unique (referenced ++ builtins.attrNames declared));
    in
    {
      inherit undeclared badPaths badSecretNames;
      systemIdentity = r.sections ? "/system identity";
    };

  # One assertion set per router, so the message names the router that has the
  # problem instead of pointing at the fleet.
  routerAssertions =
    declared: label: r:
    let
      p = problemsFor declared r;
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
          a secret placeholder has no matching file: no
          `clan.core.vars.generators.<generator>.files.<file>` declaration on
          this router produces it (offending: ${toString p.undeclared})
        '';
      }
      {
        assertion = p.badSecretNames == [ ];
        message = ''
          these secret names are not usable as file names, and a secret name is
          also the name of the file the deploy tool reads the value from:
          letters, digits, dot, dash and underscore only, starting with a letter
          or a digit, with at most one `/` between a generator and its file
          (offending: ${toString p.badSecretNames})
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
        `mikrotik.ip.address`, `clan.core.vars.generators` -- because a router
        is a configuration of its own, not a slice of this one: it is evaluated
        on its own, so two routers cannot collide and each one's assertions run
        against that router alone. Its `clan.core.vars.generators` are filed
        under its key, so two routers never share a var directory by accident.

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

  # clan.core.vars.generators, in clan's shape, so a generator definition
  # moves between a clan machine and a router unchanged -- and so a router's
  # var store is the same store: `vars/per-machine/<router>/<generator>/<file>`
  # and `vars/shared/<generator>/<file>`.
  #
  # The interface follows clan's `nixosModules/clanCore/vars/interface.nix` and
  # `modules/clan/export-modules/generic-generator.nix`. Three differences,
  # each because the deploy target is RouterOS and not a NixOS machine:
  #
  #   * no var store is read while evaluating, so `path`, `value` and `exists`
  #     throw with an explanation instead of resolving to a file. Use
  #     `placeholder` and let the deploy tool substitute the value.
  #   * `owner`, `group`, `neededFor` and `restartUnits` are accepted and
  #     ignored: RouterOS has no users, no systemd, no activation.
  #   * `finalScript` is text rather than a store path, because this class may
  #     be evaluated without `pkgs`.
  options.clan.core.vars = mkOption {
    description = ''
      Generated values -- the same generator interface clan uses, so a
      generator written for a clan machine works here unchanged.

      A generator is a shell script plus the files it declares. It runs once
      on the deploying machine, never in the store: the values it mints are
      exactly what the store must not hold. `nix-mikrotik generate` runs it and
      keeps the values in a state directory; `nix-mikrotik deploy` substitutes
      them wherever a menu cell holds `files.<file>.placeholder`.
    '';
    type = types.submodule ({ config, ... }:
      let
        machineName = config.machineName;
      in
      {
        options = {
          machineName = mkOption {
            type = types.str;
            default = cfg.routerName;
            defaultText = literalExpression "config.mikrotik.routerName";
            internal = true;
            visible = false;
            description = ''
              The machine whose `per-machine` var directory this is: the
              router's name, so a fleet files each router's vars under its own
              key.
            '';
          };

          generators = mkOption {
            default = { };
            description = ''
              A set of generators keyed by name. Each one is a script and the
              files it produces.

              Declare a file with `files.<file>`; the generator is expected to
              write exactly those files under `$out`. `$in` holds the files of
              the generators named in `dependencies`, `$prompts` holds the
              prompted values -- both as files, both read by the script.
            '';
            type = types.attrsOf (types.submodule ({ name, config, ... }:
              let
                genName = name;
                share = config.share;

                # A prompt asked for once and kept is a file: clan makes the
                # same move (`files = genAttrs filePromptNames (_: {})`), and
                # the `$prompts/<name>` -> `$out/<name>` copy it implies is in
                # `finalScript` below.
                promptFileNames = lib.attrNames (lib.filterAttrs (_: p: p.persist) config.prompts);

                promptCopy = p: ''
                  if [[ -f "$prompts/${p}" ]]; then
                    cat "$prompts/${p}" > "$out/${p}"
                  else
                    echo "generator ${genName}: prompt ${p} was not answered" >&2
                    exit 1
                  fi
                '';

                scriptText =
                  if builtins.isPath config.script then
                    "source ${toString config.script}"
                  else
                    config.script;

                pathPrefix = lib.makeBinPath (config.runtimeInputs ++ [ pkgs.coreutils ]);
              in
              {
                options = {
                  name = mkOption {
                    type = types.str;
                    readOnly = true;
                    default = genName;
                    description = "The generator's name: its attribute key.";
                  };

                  files = mkOption {
                    type = types.attrsOf (types.submodule ({ name, config, ... }: {
                      options = {
                        name = mkOption {
                          type = types.str;
                          readOnly = true;
                          default = name;
                          description = "The file's name under `$out`.";
                        };

                        secret = mkOption {
                          type = types.bool;
                          default = true;
                          description = ''
                            Whether the file holds a secret. A secret value is
                            substituted into the script on the deploying
                            machine and never leaves its state directory; a
                            non-secret one (`secret = false`, a WireGuard
                            public key) is a *published* value: generated on
                            the deploying machine too, but readable by the
                            machines that peer with this router.
                          '';
                        };

                        mode = mkOption {
                          type = types.strMatching "^[0-7]{4}$";
                          default = "0400";
                          description = ''
                            Unix mode of a secret file in the state directory.
                            A non-secret file is published, so it is written
                            0644 whatever this says.
                          '';
                        };

                        description = mkOption {
                          type = types.str;
                          default = "";
                          description = "What this file is; documentation only.";
                        };

                        deploy = mkOption {
                          type = types.bool;
                          default = true;
                          description = ''
                            Whether this file is a value the router needs, as
                            opposed to an intermediate only other generators
                            read. An intermediate is still generated, but it is
                            not published when it is not a secret and it is not
                            part of the substituted set.
                          '';
                        };

                        share = mkOption {
                          type = types.bool;
                          readOnly = true;
                          internal = true;
                          default = share;
                          defaultText = literalExpression "the generator's share flag";
                          description = "Mirror of the generator's `share`.";
                        };

                        relDir = mkOption {
                          type = types.str;
                          readOnly = true;
                          internal = true;
                          default =
                            if share then
                              "shared/${genName}"
                            else
                              "per-machine/${machineName}/${genName}";
                          defaultText = literalExpression ''"per-machine/<machine>/<generator>"'';
                          description = ''
                            This file's directory in the var store, relative to
                            its root. The same string clan uses, so
                            `--vars-dir` reads a clan repository's vars
                            directly.
                          '';
                        };

                        placeholder = mkOption {
                          type = types.anything;
                          readOnly = true;
                          default =
                            if config.secret then
                              { __mikrotikSecret = "${genName}/${name}"; }
                            else
                              throw ''
                                clan.core.vars.generators.${genName}.files.${name}:
                                this file is not a secret (`secret = false`), so it
                                has no placeholder to put in a menu body -- it is
                                generated on the deploying machine and published for
                                the other participants to read.
                              '';
                          description = ''
                            What to write where this secret belongs in a menu
                            body:
                            `private-key = config.clan.core.vars.generators.<generator>.files.<file>.placeholder;`

                            It renders as `__MIKROTIK_SECRET_<generator>/<file>__`,
                            which the deploy tool substitutes; the value itself
                            is never in the store.
                          '';
                        };

                        # clan resolves these against the var store at
                        # evaluation time. There is no var store here: values
                        # are minted on the deploying machine, so a config that
                        # reads them gets an explanation rather than a lie.
                        path = mkOption {
                          type = types.str;
                          default = throw ''
                            clan.core.vars.generators.${genName}.files.${name}.path:
                            this class has no var store to point into. Values are
                            generated on the deploying machine, not in the store;
                            use `placeholder` in a menu body and deploy with
                            `nix-mikrotik deploy --generators`.
                          '';
                          description = "Not available: use `placeholder`.";
                        };

                        value = mkOption {
                          type = types.str;
                          default = throw ''
                            clan.core.vars.generators.${genName}.files.${name}.value:
                            this class does not read generated values while
                            evaluating. Use `placeholder` in a menu body and let
                            the deploy tool substitute the value.
                          '';
                          description = "Not available: use `placeholder`.";
                        };

                        exists = mkOption {
                          type = types.bool;
                          default = throw ''
                            clan.core.vars.generators.${genName}.files.${name}.exists:
                            this class does not read the var store while
                            evaluating, so it cannot say whether a value has been
                            generated. Run `nix-mikrotik generate` and then
                            `nix-mikrotik deploy`.
                          '';
                          description = "Not available: see `nix-mikrotik generate`.";
                        };

                        # Accepted so a clan generator evaluates here; RouterOS
                        # has nothing to apply them to.
                        owner = mkOption {
                          type = types.str;
                          default = "root";
                          internal = true;
                          visible = false;
                          description = "Ignored: RouterOS has no users.";
                        };

                        group = mkOption {
                          type = types.str;
                          default = "root";
                          internal = true;
                          visible = false;
                          description = "Ignored: RouterOS has no groups.";
                        };

                        neededFor = mkOption {
                          type = types.enum [ "partitioning" "activation" "users" "services" ];
                          default = "services";
                          internal = true;
                          visible = false;
                          description = "Ignored: RouterOS has no activation.";
                        };

                        restartUnits = mkOption {
                          type = types.listOf types.str;
                          default = [ ];
                          internal = true;
                          visible = false;
                          description = "Ignored: RouterOS has no systemd units.";
                        };
                      };
                    }));
                    default = { };
                    description = "The files this generator writes, by name.";
                  };

                  prompts = mkOption {
                    type = types.attrsOf (types.submodule ({ name, ... }: {
                      options = {
                        name = mkOption {
                          type = types.str;
                          default = name;
                          description = "The prompt's name: the file under `$prompts`.";
                        };

                        persist = mkOption {
                          type = types.bool;
                          default = false;
                          description = ''
                            Whether the prompted value is also a file of this
                            generator, equivalent to
                            `files.<name>.secret = true;` plus
                            `script = "cp $prompts/<name> $out/<name>";`. It is
                            answered once and kept, so a passphrase is not asked
                            for again on the next deploy.
                          '';
                        };

                        description = mkOption {
                          type = types.str;
                          default = name;
                          description = "What the value is; shown when asking.";
                        };

                        type = mkOption {
                          type = types.enum [ "hidden" "line" "multiline" "multiline-hidden" ];
                          default = "line";
                          description = ''
                            How the value is read: `line` echoes, `hidden` does
                            not, `multiline` and `multiline-hidden` read until
                            EOF instead of one line.
                          '';
                        };
                      };
                    }));
                    default = { };
                    description = ''
                      Values asked of whoever runs the generator, available to
                      the script as `$prompts/<name>`.
                    '';
                  };

                  dependencies = mkOption {
                    type = types.listOf types.str;
                    default = [ ];
                    description = ''
                      Other generators this one reads. Their files are
                      materialized under `$in/<generator>/<file>` before this
                      generator runs, so the deploy tool runs them first (`nix-mikrotik`
                      sorts by this list and refuses a cycle).
                    '';
                    example = [ "wg-key" ];
                  };

                  validation = mkOption {
                    type = types.nullOr (types.oneOf [
                      types.bool
                      types.int
                      types.str
                      (types.attrsOf (types.oneOf [
                        types.bool
                        types.int
                        types.str
                        (types.attrsOf (types.oneOf [
                          types.bool
                          types.int
                          types.str
                        ]))
                      ]))
                    ]);
                    default = null;
                    description = ''
                      Values that invalidate what was generated: if the hash
                      below changes, the generator runs again and replaces its
                      files. Lists are not allowed, as in clan, because their
                      order would make the hash unstable.
                    '';
                    example = { endpoints = 2; };
                  };

                  validationHash = mkOption {
                    type = types.nullOr types.str;
                    readOnly = true;
                    internal = true;
                    default =
                      if config.validation == null then
                        null
                      else
                        builtins.hashString "sha256" (builtins.toJSON config.validation);
                    defaultText = literalExpression ''hashString "sha256" (toJSON config.validation)'';
                    description = ''
                      The validation interface to the outside world: stored next
                      to the generated files, and compared on the next run.
                    '';
                  };

                  runtimeInputs = mkOption {
                    type = types.listOf types.package;
                    default = [ ];
                    description = "Packages put first on the generator's `PATH`.";
                  };

                  script = mkOption {
                    type = types.either types.str types.path;
                    default = "";
                    description = ''
                      Shell script that writes every declared file under `$out`.
                      It runs on the deploying machine, with

                        $in       the files of the generators in `dependencies`
                        $out      the directory the declared files go in
                        $prompts  the prompted values, as files

                      and with `runtimeInputs` on `PATH`.
                    '';
                    example = "wg genkey | tee $out/privkey | wg pubkey > $out/pubkey";
                  };

                  finalScript = mkOption {
                    type = types.lines;
                    readOnly = true;
                    internal = true;
                    description = ''
                      `script` as the deploy tool runs it: `PATH` set from
                      `runtimeInputs`, every persisted prompt copied from
                      `$prompts` into `$out`, then the script itself. clan makes
                      the same three moves in `generic-generator.nix`.
                    '';
                  };

                  share = mkOption {
                    type = types.bool;
                    default = false;
                    description = ''
                      Whether the values belong to the fleet rather than to this
                      router: a shared generator is stored once under
                      `vars/shared/<generator>` and reused by every router that
                      declares it, instead of once per router.
                    '';
                  };
                };

                config = {
                  files = lib.genAttrs promptFileNames (_: { });

                  finalScript = ''
                    set -euo pipefail

                    export PATH=${pathPrefix}:$PATH

                    mkdir -p "$out"
                    ${lib.concatMapStrings promptCopy promptFileNames}
                    ${scriptText}
                  '';
                };
              }));
          };
        };
      });
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
      {
          # A generator with no files would run a script whose output nobody
          # reads, and produce a manifest entry the tool cannot match to
          # anything.
          assertion = lib.all (g: g.files != { }) (lib.attrValues gens);
          message = ''
            every `clan.core.vars.generators.<generator>` must declare at least one file
            under `files`, or the generator produces nothing the deploy tool can use
          '';
        }
        {
          # `$in/<generator>/<file>` is how a generator reads another one, so a
          # dependency that is not a declared generator is a file that never
          # appears -- and the script fails at deploy time, on a router, with a
          # shell error instead of a Nix one.
          assertion = lib.all (g: builtins.all (d: gens ? ${d}) g.dependencies) (lib.attrValues gens);
          message = ''
            a `clan.core.vars.generators.<generator>.dependencies` entry names a generator
            this router does not declare (offending:
            ${toString (lib.unique (lib.concatMap (g: builtins.filter (d: !(gens ? ${d})) g.dependencies) (lib.attrValues gens)))})
          '';
        }
        {
          # A dependency cycle has no order to run the generators in, so the
          # deploy tool would refuse it anyway. Better to refuse it here, where
          # the message names the generators.
          assertion = depsAcyclic gens;
          message = ''
            clan.core.vars.generators has a dependency cycle:
            ${toString (lib.attrNames gens)}
          '';
        }
        {
          # A persisted prompt becomes a file of the same name, so the name has
          # to be a file name the deploy tool can see.
          assertion = lib.all
            (g: builtins.all (p: builtins.match secretPartRe p != null) (lib.attrNames g.prompts))
            (lib.attrValues gens);
          message = ''
            a prompt name is not usable as a file name: letters, digits, dot,
            dash and underscore only, starting with a letter or a digit
          '';
        }
        {
          # `varFiles` is clan's description of a generated file, so it has to
          # resolve to one: a generator, a file inside it, and a machine unless
          # the generator is shared. A path with `..`, an absolute path or an
          # empty segment is either a value nothing will find or a read outside
          # the vars directory the deploy was pointed at.
          assertion = badVarFiles == [ ];
          message = ''
            these mikrotik.varFiles entries do not resolve to `<rel_dir>/<file>`
            under the vars directory -- name them `<generator>/<file>` (the
            placeholder), or set `generator` and `file` explicitly, and leave
            `machine`/`share` to place the generator:
            ${toString badVarFiles}
          '';
        }
      ]
      ++ routerAssertions
        (generatorFiles // lib.genAttrs (lib.attrNames cfg.varFiles) (_: null))
        "mikrotik" cfg;
  };
}
