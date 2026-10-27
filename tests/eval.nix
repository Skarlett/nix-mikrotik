{ pkgs, evalMikrotik, evalMikrotikRaw, mkSecret }:

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

  control = { mkSecret, ... }: {
    mikrotik = {
      hostname = "router1";
      secrets.wg-private-key.file = "wg-private-key";
      sections = {
        "/interface bridge" = [ { name = "bridge"; } ];
        "/interface wireguard" = [
          { name = "wg0"; private-key = mkSecret "wg-private-key"; }
        ];
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
      name = "a mkSecret with no declaration";
      module = { mkSecret, ... }: {
        mikrotik.sections."/interface wireguard" = [
          { name = "wg0"; private-key = mkSecret "wg-typo"; }
        ];
      };
      expect = "no matching mikrotik.secrets.<name> entry";
    }
    {
      name = "a secret name that is not a file name";
      module = { mkSecret, ... }: {
        mikrotik.secrets."wg+key".file = "wg+key";
        mikrotik.sections."/interface wireguard" = [
          { name = "wg0"; private-key = mkSecret "wg+key"; }
        ];
      };
      expect = "not usable as file names";
    }
    {
      name = "a secret name that walks out of --secrets-dir";
      module = { mkSecret, ... }: {
        mikrotik.secrets."../outside".file = "../outside";
        mikrotik.sections."/interface wireguard" = [
          { name = "wg0"; private-key = mkSecret "../outside"; }
        ];
      };
      expect = "not usable as file names";
    }
  ];

  # "does the evaluator refuse this", asked the way a user asks it
  refused = modules: !(builtins.tryEval (evalMikrotik { inherit modules; })).success;
  # ... and the diagnostic they would be shown
  messages = modules:
    lib.concatStringsSep " | " (map (a: a.message) (evalMikrotikRaw { inherit modules; }).failed);

  case = { module, ... }: {
    verdict = refused [ module ];
    diagnostic = messages [ module ];
  };
  results = map (r: r // case r) refusals;

  # The control leg: without this, a check that refuses everything passes.
  controlRefused = refused [ control ];
  controlDiagnostic = messages [ control ];
  controlHostname = (evalMikrotik { modules = [ control ]; }).mikrotik.hostname;
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