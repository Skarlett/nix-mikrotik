{ pkgs, evalMikrotik, evalMikrotikRaw, generators }:

# The class refuses what it says it refuses.
#
# A custom module class has no NixOS activation step behind it, so an assertion
# that is never forced is an assertion that does not exist. `evalMikrotik`
# forces them; this check proves each one fires, and that the message names the
# fix rather than a line number. The plan is read through `evalMikrotikRaw`
# because a `throw`'s text cannot be read back through `builtins.tryEval` --
# "something was refused" and "the right thing was said" are two claims.
let
  lib = pkgs.lib;

  # A router that does everything the class is for: a generator that mints a
  # key, a second generator that reads the first through `dependencies`, a
  # prompted file, and menu cells that hold the placeholders rather than values.
  control = { config, ... }: {
    mikrotik = {
      hostname = "router1";
      sections = {
        "/interface bridge" = [ { name = "bridge"; } ];
        "/interface wireguard" = [
          {
            name = "wg0";
            private-key = config.clan.core.vars.generators.wg-key.files.privkey.placeholder;
          }
        ];
      };
    };

    clan.core.vars.generators = {
      wg-key = {
        files.privkey = { };
        files.pubkey.secret = false;
        script = "wg genkey | tee $out/privkey | wg pubkey > $out/pubkey";
      };

      # The second generator reads the first's files, which is what
      # `dependencies` is for: `$in/wg-key/pubkey`.
      peer-key = {
        dependencies = [ "wg-key" ];
        files.preshared = { };
        prompts.passphrase = {
          description = "the mix-in for the preshared key";
          type = "hidden";
          persist = true;
        };
        script = "wg genpsk < $in/wg-key/pubkey > $out/preshared";
      };
    };
  };

  # Each of these must be refused, and the diagnostic must contain `expect`.
  refusals = [
    {
      name = "an empty hostname";
      module = _: { mikrotik.hostname = ""; };
      expect = "mikrotik.hostname must not be empty";
    }
    {
      name = "a /system identity section";
      module = _: { mikrotik.sections."/system identity" = { name = "router1"; }; };
      expect = "/system identity\" is not allowed";
    }
    {
      name = "a section path without a leading slash";
      module = _: { mikrotik.sections."ip dns" = { }; };
      expect = "must be RouterOS command paths beginning with";
    }
    {
      name = "a placeholder no generator declares";
      module = { mkSecret, ... }: {
        mikrotik.sections."/interface wireguard" = [
          { name = "wg0"; private-key = mkSecret "wg-typo/privkey"; }
        ];
      };
      expect = "has no matching file";
    }
    {
      name = "a placeholder that names a file the generator does not declare";
      module = { mkSecret, ... }: {
        mikrotik.sections."/interface wireguard" = [
          { name = "wg0"; private-key = mkSecret "wg-key/privkey.pem"; }
        ];
        clan.core.vars.generators.wg-key = {
          files.privkey = { };
          script = "wg genkey > $out/privkey";
        };
      };
      expect = "has no matching file";
    }
    {
      name = "a generator that declares no files";
      module = _: {
        clan.core.vars.generators.empty.script = "true";
      };
      expect = "must declare at least one file";
    }
    {
      name = "a dependency on a generator this router does not declare";
      module = _: {
        clan.core.vars.generators.peer-key = {
          dependencies = [ "wg-key" ];
          files.preshared = { };
          script = "cp $in/wg-key/privkey $out/preshared";
        };
      };
      expect = "names a generator this router does not declare";
    }
    {
      name = "a dependency cycle";
      module = _: {
        clan.core.vars.generators = {
          a = {
            dependencies = [ "b" ];
            files.f = { };
            script = "true";
          };
          b = {
            dependencies = [ "a" ];
            files.f = { };
            script = "true";
          };
        };
      };
      expect = "has a dependency cycle";
    }
    {
      name = "a prompt name that is not a file name";
      module = _: {
        clan.core.vars.generators.wg-key = {
          files.privkey = { };
          prompts."wg+key".persist = true;
          script = "wg genkey > $out/privkey";
        };
      };
      expect = "not usable as a file name";
    }
    {
      name = "a secret name that is not a file name";
      module = { mkSecret, ... }: {
        mikrotik.sections."/interface wireguard" = [
          { name = "wg0"; private-key = mkSecret "wg+key/privkey"; }
        ];
      };
      expect = "not usable as file names";
    }
    {
      name = "a secret name that walks out of the var store";
      module = { mkSecret, ... }: {
        mikrotik.sections."/interface wireguard" = [
          { name = "wg0"; private-key = mkSecret "../outside"; }
        ];
      };
      expect = "not usable as file names";
    }
  ];

  # "does the evaluator refuse this", asked the way a user asks it
  refused = modules: !(builtins.tryEval (evalMikrotik { inherit modules pkgs; })).success;
  # ... and the diagnostic they would be shown. Line wrapping in a message is
  # formatting, not wording: collapses runs of whitespace so an `expect` phrase
  # matches across a line break.
  flatten = lib.replaceStrings [ "\n" "\t" ] [ " " " " ];
  messages = modules:
    lib.concatStringsSep " | "
      (map (a: flatten a.message) (evalMikrotikRaw { inherit modules pkgs; }).failed);

  case = r:
    let
      modules = [ r.module ];
    in
    r // {
      verdict = refused modules;
      diagnostic = messages modules;
    };
  results = map case refusals;

  # The control leg: without this, a check that refuses everything passes.
  controlRefused = refused [ control ];
  controlDiagnostic = messages [ control ];
  controlConfig = evalMikrotik { inherit pkgs; modules = [ control ]; };
  controlHostname = controlConfig.mikrotik.hostname;

  # A value this router does not mint at all: a key its controller generated.
  # `varFiles` names it so the "is this placeholder declared?" assertion can
  # tell a real hand-off from a typo, and the value is read from `--secrets-dir`
  # at deploy time rather than from a generator manifest entry.
  varFileModule = { mkSecret, ... }: {
    mikrotik = {
      hostname = "router2";
      varFiles."mesh-chr1-private-key".description = "chr1's key, minted on its controller";
      sections."/interface wireguard" = [
        { name = "wg0"; private-key = mkSecret "mesh-chr1-private-key"; }
      ];
    };
  };
  varFileConfig = evalMikrotik { inherit pkgs; modules = [ varFileModule ]; };
  varFileDeclared = builtins.attrNames varFileConfig.mikrotik.varFiles;
  varFileGenerated = generators varFileConfig;
  # ... and it is still a placeholder a typo cannot slip past.
  varFileTypoRefused = refused [
    ({ mkSecret, ... }: {
      mikrotik = {
        hostname = "router2";
        varFiles."mesh-chr1-private-key".description = "chr1's key";
        sections."/interface wireguard" = [
          { name = "wg0"; private-key = mkSecret "mesh-chr1-rpivate-key"; }
        ];
      };
    })
  ];

  # The generator list is in dependency order and carries each file's place in
  # the var store, which is what the deploy tool runs on. `wg-key` is declared
  # first and `peer-key` depends on it, so the order is already right -- the
  # test is that it stays right when it is not.
  controlGenerators = generators controlConfig;
  controlOrder = map (g: g.name) controlGenerators;
  controlKeyFile = (builtins.head (lib.filter (f: f.name == "privkey") (builtins.head controlGenerators).files));

  # `pkgs` reaches a module through `specialArgs`, so a module may name it as an
  # argument rather than reach for `_module.args`; and a caller cannot shadow it,
  # because the set the generators were rendered against is the set the module
  # must see.
  pkgsSeen = (evalMikrotik {
    inherit pkgs;
    modules = [ ({ pkgs, ... }: { mikrotik.hostname = pkgs.stdenv.hostPlatform.system; }) ];
  }).mikrotik.hostname;
  pkgsSystem = pkgs.stdenv.hostPlatform.system;
  pkgsShadowed = (evalMikrotik {
    inherit pkgs;
    specialArgs = { pkgs = throw "specialArgs overrode pkgs"; };
    modules = [ ({ pkgs, ... }: { mikrotik.hostname = pkgs.stdenv.hostPlatform.system; }) ];
  }).mikrotik.hostname;
  pkgsExtended = (evalMikrotik {
    inherit pkgs;
    specialArgs = { site = "homelab"; };
    modules = [ ({ site, ... }: { mikrotik.hostname = "router.${site}"; }) ];
  }).mikrotik.hostname;
in
pkgs.runCommand "check-eval" { } ''
  mkdir -p $out

  # -- the control: evaluates, and has nothing to say ------------------------
  [ ${if controlRefused then "0" else "1"} -eq 1 ] || {
    echo "the control configuration was refused: $controlDiagnostic" >&2
    exit 1
  }
  [ ${lib.escapeShellArg controlHostname} = "router1" ]
  [ -z ${lib.escapeShellArg controlDiagnostic} ]
  printf 'control | evaluates | hostname %s, 0 failed assertions\n' ${lib.escapeShellArg controlHostname} > $out/refusals.txt

  # -- the generators reach the manifest in dependency order -----------------
  [ ${lib.escapeShellArg (lib.concatStringsSep "," controlOrder)} = 'wg-key,peer-key' ] || {
    echo "generators are not in dependency order: ${lib.concatStringsSep "," controlOrder}" >&2
    exit 1
  }
  # ... with the var-store path the tool writes to, and the mode it writes it
  [ ${lib.escapeShellArg controlKeyFile.relDir} = 'per-machine/router1/wg-key' ]
  [ ${lib.escapeShellArg controlKeyFile.mode} = "0400" ]
  # ... and a prompt that becomes a file is also a file of the generator
  grep -q 'passphrase' ${pkgs.writeText "prompts" (lib.concatStringsSep "," (map (p: p.name) (builtins.elemAt controlGenerators 1).prompts))}

  # -- pkgs is a module argument, and only the evaluator's set is visible -----
  [ ${lib.escapeShellArg pkgsSeen} = ${lib.escapeShellArg pkgsSystem} ] || {
    echo "a module did not see pkgs through specialArgs: ${pkgsSeen}" >&2
    exit 1
  }
  [ ${lib.escapeShellArg pkgsShadowed} = ${lib.escapeShellArg pkgsSystem} ] || {
    echo "specialArgs was allowed to override pkgs: ${pkgsShadowed}" >&2
    exit 1
  }
  [ ${lib.escapeShellArg pkgsExtended} = ${lib.escapeShellArg "router.homelab"} ] || {
    echo "specialArgs did not extend the argument set: ${pkgsExtended}" >&2
    exit 1
  }
  printf 'pkgs | argument | %s, specialArgs extends but cannot override\n' ${lib.escapeShellArg pkgsSystem} >> $out/refusals.txt

  # -- a value generated elsewhere is declared, not minted here --------------
  [ ${lib.escapeShellArg (lib.concatStringsSep "," varFileDeclared)} = 'mesh-chr1-private-key' ] || {
    echo "varFiles did not declare the hand-off: ${lib.concatStringsSep "," varFileDeclared}" >&2
    exit 1
  }
  [ -z ${lib.escapeShellArg (lib.concatStringsSep "," (map (g: g.name) varFileGenerated))} ] || {
    echo "a varFiles entry reached the generator manifest" >&2
    exit 1
  }
  [ ${if varFileTypoRefused then "0" else "1"} -eq 0 ] || {
    echo "a typo against varFiles was not refused" >&2
    exit 1
  }
  printf 'varFiles | declared | %s, no generator, typo refused\n' ${lib.escapeShellArg (lib.concatStringsSep "," varFileDeclared)} >> $out/refusals.txt

  # -- every assertion fires, with a diagnostic that names the fix ----------
  ${lib.concatMapStrings (r: ''
    [ ${if r.verdict then "0" else "1"} -eq 0 ] || {
      echo "not refused: ${r.name}" >&2
      exit 1
    }
    case ${lib.escapeShellArg r.diagnostic} in
      *${lib.escapeShellArg r.expect}*) ;;
      *) echo "diagnostic does not name the fix: ${r.name}" >&2
         printf '  wanted a mention of: %s\n' ${lib.escapeShellArg r.expect} >&2
         printf '  got: %s\n' ${lib.escapeShellArg r.diagnostic} >&2
         exit 1 ;;
    esac
    printf '%s | refused | %s\n' ${lib.escapeShellArg r.name} ${lib.escapeShellArg r.diagnostic} >> $out/refusals.txt
  '') results}

  cat $out/refusals.txt
  touch $out/pass
''