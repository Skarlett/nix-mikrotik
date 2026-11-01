#!/usr/bin/env python3
"""nix-mikrotik -- build, secret-deliver and deploy RouterOS scripts.

The nix side owns rendering (lib/render.nix): a configuration is evaluated to a
`.rsc` file in the store, with `__MIKROTIK_SECRET_<name>__` placeholders where a
secret value belongs. This tool owns everything that must happen *off* the
store:

  render      build a configuration's script through nix and copy it out
  list-secrets  list the placeholders a script still contains
  secretize   substitute real values into a private temporary copy
  deploy      secretize, upload, import, verify, and remove the file again
  diff        export the device's live config and diff it against the script

RouterOS cannot run sops-nix, so a secret cannot be "activated" onto the
device the way it is onto a NixOS host. It is delivered here instead: the value
is read on the deploying machine (from a clan var, a sops file, anywhere), put
into a 0600 file under a 0700 temporary directory, uploaded, imported, and the
uploaded copy is removed from the router afterwards.

Two things about a RouterOS value this tool has to get right, because the
device reports neither of them through ssh's exit status:

  * a value that is not quoted when RouterOS needs it to be (a base64 key ends
    in `=`) makes the device refuse the script at parse time -- nothing is
    applied -- and `/import` still exits 0. Values are quoted here when they
    need it.
  * a script the device did not finish running is indistinguishable, by status
    alone, from one it applied. `deploy` appends a one-line sentinel to the
    uploaded copy and reads the device's log back, so a deploy that did not run
    to the end fails instead of printing "verified" -- and its message says a
    prefix may have been applied, because a parse abort applies nothing while a
    runtime abort has already applied everything above the failing line.
"""

from __future__ import annotations

import argparse
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time

DEFAULT_SCRIPT_NAME = "router-config.rsc"

# The name between the markers is also a file name in a secrets directory (see
# README "Clan vars"), so it has to be one: a name carrying a path separator or
# a `..` would let read_secret_files read outside the directory, and a name
# outside this charset slips past an enumeration and gets uploaded as a literal
# placeholder. modules/base.nix asserts the same rule when the configuration is
# evaluated; this is the half that covers a script the tool was handed rather
# than one it rendered.
SECRET_NAME_RE = re.compile(r"[A-Za-z0-9][A-Za-z0-9._-]*")

# Deliberately wider than SECRET_NAME_RE, because a script has to be *found* to
# be refused. A matching pattern narrower than what a configuration can write
# answers "no secret placeholders" for a name it cannot see, which is exactly
# how a literal placeholder reaches a router.
PLACEHOLDER_RE = re.compile(r"__MIKROTIK_SECRET_(.+?)__")

# A substituted value is left bare only when it cannot be anything but one
# token. Anything else -- a space, `=`, `;`, `#`, a quote -- is quoted and
# escaped: RouterOS parses `key=value` with its own grammar and ends the
# command early on those, and a base64 WireGuard private key (32 bytes, so
# always a trailing `=`) is precisely the shape that aborts a whole import.
BARE_VALUE_RE = re.compile(r"[A-Za-z0-9._:/@,+-]+")

# The wording /import uses on a clean run. Only a fallback: the sentinel is the
# signal, this is what still works if a device's logging has been turned down.
IMPORT_OK_TEXT = "executed successfully"

SENTINEL_PREFIX = "nix-mikrotik-import"


class ToolError(Exception):
    """An expected failure, reported without a traceback."""


# --------------------------------------------------------------------------
# placeholders
# --------------------------------------------------------------------------

def check_secret_name(name: str) -> str:
    if not SECRET_NAME_RE.fullmatch(name):
        raise ToolError(
            f"secret name '{name}' is not usable as a file name: names must "
            "match [A-Za-z0-9][A-Za-z0-9._-]* (no '/', no space, no '..')")
    return name


def routeros_value(value: str) -> str:
    """A secret value, spelled the way RouterOS needs it in the slot it goes in.

    Quoting is not cosmetic here. An unquoted value containing `=` -- which
    every base64 private key is -- makes RouterOS end the command early, abort
    the *entire* script and still exit 0, so the device keeps its old
    configuration and the deploy looks like it worked. `"`, `\\` and `$` are
    escaped the way RouterOS writes and reads them back: verified on 7.15.3 by
    setting a value carrying all three and reading it back byte-identical,
    against the same value left bare, which the device refuses to parse at all.
    """
    if BARE_VALUE_RE.fullmatch(value):
        return value
    escaped = value.replace("\\", "\\\\").replace('"', '\\"').replace("$", "\\$")
    return f'"{escaped}"'


def find_placeholders(text: str) -> list[str]:
    seen: list[str] = []
    for name in PLACEHOLDER_RE.findall(text):
        check_secret_name(name)
        if name not in seen:
            seen.append(name)
    return seen


def substitute(text: str, values: dict[str, str]) -> str:
    def repl(match: re.Match[str]) -> str:
        name = check_secret_name(match.group(1))
        if name not in values:
            raise ToolError(f"no value supplied for secret '{name}'")
        value = values[name]
        # A RouterOS value that breaks the line it sits in is a silent config
        # corruption, not an error on the device. Refuse instead.
        if any(c in value for c in "\r\n"):
            raise ToolError(f"secret '{name}' contains a newline; refusing to render it")
        return routeros_value(value)

    return PLACEHOLDER_RE.sub(repl, text)


def read_secret_files(directory: str, names: list[str]) -> dict[str, str]:
    values: dict[str, str] = {}
    for name in names:
        # Belt and braces: the name is a path component, and every caller has
        # already validated it, but this is the line that would read a file
        # outside the directory if one ever did not.
        check_secret_name(name)
        path = os.path.join(directory, name)
        if not os.path.isfile(path):
            continue
        with open(path, "r", encoding="utf-8") as handle:
            values[name] = handle.read().strip()
    return values


def read_secret_command(template: str, names: list[str]) -> dict[str, str]:
    """Resolve secrets by running a command per name, instead of reading files.

    For a deploy host that must not *hold* the router's secrets: the values stay
    where they are (a sops file, a vault) and are fetched at deploy time,
    decrypted in memory, substituted, and gone when the process exits. `{name}`
    is replaced with the secret's name; stdout is the value.

    A command that fails, or prints nothing, is an error: a placeholder replaced
    with an empty string would deploy a router with an empty key.
    """
    values: dict[str, str] = {}
    for name in names:
        check_secret_name(name)
        proc = subprocess.run(
            ["sh", "-c", template.replace("{name}", name)],
            capture_output=True, text=True)
        if proc.returncode != 0:
            detail = (proc.stderr or proc.stdout).strip().splitlines()
            raise ToolError(
                f"--secret-command failed for '{name}' (exit {proc.returncode})"
                + ("\n" + detail[0] if detail else ""))
        value = proc.stdout.rstrip("\n")
        if value == "":
            raise ToolError(f"--secret-command produced no value for '{name}'")
        values[name] = value
    return values


# --------------------------------------------------------------------------
# transport
# --------------------------------------------------------------------------

def check_known_hosts(path: str) -> str:
    """A known_hosts path ssh can actually record a key in, or a refusal.

    `StrictHostKeyChecking=accept-new` learns a key by *appending* it to this
    file, and that append fails quietly: ssh prints one warning -- "Failed to
    add the host to the list of known hosts" -- to stderr and carries on, so a
    deploy that names a path it cannot write there looks pinned and is not. The
    case worth catching is a parent directory that does not exist (ssh creates
    the file itself, not the directory), and it is the only thing this option
    can be wrong about before a packet is sent.
    """
    expanded = os.path.expanduser(path)
    parent = os.path.dirname(expanded) or "."
    if not os.path.isdir(parent):
        raise ToolError(
            f"--known-hosts {path}: '{parent}' is not a directory, so ssh cannot "
            "record the host key it learns there: it would warn and continue, "
            "and the pin would be silently absent")
    return expanded


class Router:
    """ssh/scp against a RouterOS device.

    RouterOS' sshd accepts a command argument, so both halves are one-shot
    invocations of the system openssh. No library, no agent, no key handling of
    our own: whatever the operator's ssh already does for the fleet, it does
    here -- with one exception, `known_hosts`.

    `~/.ssh/known_hosts` is a `~` ssh resolves through the *passwd* entry, not
    through `$HOME`, so a caller with no operator home -- a systemd unit running
    as root under `ProtectHome = true`, ccpkgs' `services.mikrotik` -- has no
    such file and can learn nothing: under `accept-new` every deploy is then a
    first contact, and the secretized script goes to whoever answers the
    address. `known_hosts` names the file instead, so such a caller can hand in
    a path it can write (a unit's `StateDirectory`) and the pin is learned
    again. The *semantics* of `accept-new` are untouched: only the file is
    selectable, and the machine-wide `/etc/ssh/ssh_known_hosts` that a pinned
    host key lands in is still read.
    """

    def __init__(self, host: str, user: str = "admin", port: int = 22,
                 key: str | None = None, known_hosts: str | None = None,
                 timeout: int = 20) -> None:
        self.host = host
        self.user = user
        self.port = port
        self.key = key
        self.known_hosts = check_known_hosts(known_hosts) if known_hosts else None
        self.timeout = timeout

    def _common(self) -> list[str]:
        args = [
            "-o", "BatchMode=yes",
            "-o", "StrictHostKeyChecking=accept-new",
            "-o", f"ConnectTimeout={self.timeout}",
        ]
        if self.key:
            args += ["-i", os.path.expanduser(self.key)]
        if self.known_hosts:
            # `-o` rather than a config file: it applies to this invocation
            # only, which is what a tool that shells out twice per deploy wants.
            args += ["-o", f"UserKnownHostsFile={self.known_hosts}"]
        return args

    def run(self, command: str) -> str:
        argv = ["ssh", *self._common(), "-p", str(self.port),
                f"{self.user}@{self.host}", command]
        proc = subprocess.run(argv, capture_output=True, text=True)
        if proc.returncode != 0:
            raise ToolError(
                f"ssh command failed ({proc.returncode}): {command}\n"
                f"{proc.stderr.strip()}")
        return proc.stdout

    def upload(self, local: str) -> str:
        """Copy a file into the router's file store; returns the remote name."""
        remote = os.path.basename(local)
        # RouterOS speaks the legacy scp protocol only; current OpenSSH needs -O.
        argv = ["scp", "-O", *self._common(), "-P", str(self.port),
                local, f"{self.user}@{self.host}:{remote}"]
        proc = subprocess.run(argv, capture_output=True, text=True)
        if proc.returncode != 0:
            raise ToolError(f"scp failed ({proc.returncode}):\n{proc.stderr.strip()}")
        return remote

    def remove(self, remote: str) -> None:
        # Best effort: the uploaded script carries plaintext secrets and must
        # not stay on the device's flash. `/file remove <name>` rather than
        # `/file remove [find …]`: the find expression needs RouterOS' own
        # bracket syntax to survive the remote shell, and a name is a name.
        #
        # Retried, because it runs immediately after /import and the device is
        # often still applying the script: the first attempt fails with a bare
        # exit 1 and the same command succeeds a second later.
        last: ToolError | None = None
        for _attempt in range(5):
            try:
                self.run(f'/file remove "{remote}"')
                return
            except ToolError as exc:
                last = exc
                time.sleep(1)
        print(f"warning: could not remove {remote} from the device: {last}",
              file=sys.stderr)

    def identity(self) -> str | None:
        out = self.run("/system identity print")
        match = re.search(r"^\s*name:\s*(\S+)\s*$", out, re.M)
        return match.group(1) if match else None

    def sentinel_seen(self, marker: str) -> bool:
        """Did the sentinel line the tool appended actually run on the device?

        This is the only positive signal a failed import leaves behind: a
        script RouterOS refused to parse is logged and exits 0, exactly like
        one that applied. The marker is logged by the script's own last line,
        and only if the whole script ran.
        """
        out = self.run(f'/log print where message~"{marker}"')
        return marker in out

    def script_errors(self) -> list[str]:
        """The device's own account of a script it could not run."""
        out = self.run('/log print where topics~"script"')
        return [line.strip() for line in out.splitlines() if "script,error" in line]

    def export(self) -> str:
        return self.run("/export terse")


# --------------------------------------------------------------------------
# commands
# --------------------------------------------------------------------------

def cmd_render(args: argparse.Namespace) -> int:
    system = args.system or _current_system()
    attr = f"{args.flake}#packages.{system}.mikrotik-{args.name}-script"
    out = subprocess.run(
        ["nix", "build", "--no-link", "--print-out-paths", attr],
        capture_output=True, text=True)
    if out.returncode != 0:
        raise ToolError(f"nix build failed for {attr}:\n{out.stderr.strip()}")
    store_path = out.stdout.strip().splitlines()[-1]
    source = os.path.join(store_path, DEFAULT_SCRIPT_NAME)
    if not os.path.isfile(source):
        raise ToolError(f"{source} does not exist in the build output")
    destination = args.output or f"{args.name}.rsc"
    shutil.copyfile(source, destination)
    os.chmod(destination, 0o644)
    print(destination)
    return 0


def _current_system() -> str:
    """The flake's package path is per-system; ask nix rather than uname."""
    out = subprocess.run(
        ["nix", "eval", "--impure", "--raw", "--expr", "builtins.currentSystem"],
        capture_output=True, text=True)
    if out.returncode != 0 or not out.stdout.strip():
        raise ToolError("could not determine the current system; pass --system")
    return out.stdout.strip()


def cmd_list_secrets(args: argparse.Namespace) -> int:
    with open(args.script, "r", encoding="utf-8") as handle:
        names = find_placeholders(handle.read())
    if not names:
        print("(no secret placeholders)", file=sys.stderr)
        return 0
    for name in names:
        print(name)
    return 0


def _secretize(
    script: str,
    secret_args: list[str],
    secrets_dir: str | None,
    secret_command: str | None = None,
) -> tuple[str, list[str]]:
    with open(script, "r", encoding="utf-8") as handle:
        text = handle.read()
    names = find_placeholders(text)
    values: dict[str, str] = {}
    if secrets_dir:
        values.update(read_secret_files(secrets_dir, names))
    for item in secret_args:
        if "=" not in item:
            raise ToolError(f"--secret wants NAME=PATH, got '{item}'")
        name, path = item.split("=", 1)
        try:
            with open(os.path.expanduser(path), "r", encoding="utf-8") as handle:
                values[name] = handle.read().strip()
        except OSError as exc:
            raise ToolError(f"cannot read secret '{name}' from {path}: {exc}") from exc
    missing = [n for n in names if n not in values]
    if missing and secret_command:
        # Only what is still unresolved: an explicit --secret or a file in
        # --secrets-dir wins over asking the command.
        values.update(read_secret_command(secret_command, missing))
        missing = []
    if missing:
        raise ToolError(
            "unresolved secret placeholders: " + ", ".join(missing) +
            "\npass them with --secret NAME=PATH, --secrets-dir, or --secret-command")
    return substitute(text, values), names


def cmd_secretize(args: argparse.Namespace) -> int:
    text, names = _secretize(args.script, args.secret, args.secrets_dir, args.secret_command)
    destination = args.output
    # 0600 from creation *and* afterwards: the mode passed to os.open applies
    # only when the file is created, so secretizing into a destination that
    # already exists (a 0644 one, from an earlier run of anything) would
    # otherwise leave plaintext secrets world-readable.
    fd = os.open(destination, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w", encoding="utf-8") as handle:
        handle.write(text)
    os.chmod(destination, 0o600)
    print(f"{destination} ({len(names)} secret(s) substituted)", file=sys.stderr)
    return 0


def new_sentinel() -> str:
    """A per-deploy marker, so an old log entry cannot be mistaken for this one."""
    return f"{SENTINEL_PREFIX}-{os.urandom(8).hex()}"


def sentinel_line(marker: str) -> str:
    """The line appended to the uploaded copy, and why it is there.

    This line is logged only if the whole script ran. RouterOS exits 0 for an
    import it refused, so ssh's status cannot say whether anything happened; a
    script the device cannot *parse* applies nothing and never reaches this
    line, and one that fails *while running* stops before it. So the sentinel
    answers "did it run to the end", not "did every line apply". It is a log
    entry rather than a file so that nothing has to be cleaned up on the
    device, and the marker is unique per deploy.
    """
    return f'\n:log info "{marker}"\n'


def import_failed(detail: str) -> str:
    """What `deploy` says when the sentinel the script ends with was not logged.

    It deliberately makes no claim about what did or did not reach the device,
    because the tool cannot know: a script RouterOS could not parse applies
    nothing, while one that failed partway through has already applied every
    line above the failing one, and both leave the same evidence (no sentinel,
    a `script,error` line). Measured on 7.15.3 with this tool: a runtime abort
    after two `add`s left the identity set and one filter rule in place.

    That is why the wording warns instead of reassuring. An operator told "the
    device is unchanged" re-runs the corrected script, and RouterOS has no
    reconciliation -- a repeated `add` makes a second object, so the re-run
    duplicates whatever the first attempt managed to apply.
    """
    return (
        "the import did not run to the end, so this deploy did not complete: "
        "RouterOS exits 0 either way, and the sentinel line this tool appended "
        "to the uploaded copy was never logged.\n"
        "a prefix of the script may already have been applied. A script the "
        "device cannot parse applies nothing, but one that fails while running "
        "has applied every line before the failing one, and this tool cannot "
        "tell the two apart. Do not re-run it on that assumption: RouterOS has "
        "no reconciliation, so a repeated `add` makes a second object and a "
        "re-run duplicates what the first attempt applied. Check the device "
        "first -- `nix-mikrotik diff` shows what it holds now.\n"
        "the device's most recent script errors (its log holds earlier failures "
        f"too, so read these as context):\n{detail}")


def check_applied(router: Router, marker: str, output: str) -> None:
    """Refuse to call a deploy successful when the script did not run to the end.

    `/import` answers a script it cannot parse by logging the error and exiting
    **0**, so ssh's status says "fine" whether the configuration applied or the
    import was refused outright (verified on 7.15.3: an unquoted base64 key
    produced an empty stdout, an unchanged identity and rc=0). The positive
    signal is the sentinel line: a clean run logs it and prints "…executed
    successfully"; a parse error produces neither, and a runtime error stops
    before the sentinel does. Which of the two happened is not recoverable
    here, so the failure says so rather than guessing -- see `import_failed`.
    """
    if IMPORT_OK_TEXT in output:
        return
    for _attempt in range(3):
        if router.sentinel_seen(marker):
            return
        time.sleep(1)
    errors = router.script_errors()[-5:]
    detail = "\n".join(errors) if errors else "(no script error in the device log)"
    raise ToolError(import_failed(detail))


def cmd_deploy(args: argparse.Namespace) -> int:
    # The confirmation comes first, before anything that reaches the device or
    # reads a secret value: `--reset` without `--yes` is a refused invocation,
    # and it used to be refused only after `router.upload()` had put the
    # secretized script -- plaintext secrets, on the device's flash -- and after
    # `_secretize` had read every secret into memory. The `finally` below does
    # remove it again, so nothing leaked; but the refusal was not the guard it
    # reads as, and it has no business doing work it is about to undo.
    if args.reset and not args.yes:
        raise ToolError(
            "--reset wipes the device's configuration and reboots it; "
            "pass --yes to confirm")

    router = Router(args.host, args.user, args.port, args.key, args.known_hosts)
    text, names = _secretize(args.script, args.secret, args.secrets_dir, args.secret_command)

    if args.dry_run:
        print(f"would deploy {len(text)} bytes with {len(names)} secret(s) to "
              f"{args.user}@{args.host}:{args.port}")
        if args.reset:
            print("would reset the configuration with the uploaded script "
                  "(destructive)", file=sys.stderr)
        return 0

    workdir = tempfile.mkdtemp(prefix="nix-mikrotik-")
    os.chmod(workdir, 0o700)
    remote = None
    marker = new_sentinel()
    try:
        staged = os.path.join(workdir, DEFAULT_SCRIPT_NAME)
        fd = os.open(staged, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            handle.write(text + sentinel_line(marker))

        print(f"uploading to {args.user}@{args.host}:{args.port}", file=sys.stderr)
        remote = router.upload(staged)

        if args.reset:
            # The declarative path: the device reboots with the script applied
            # to an empty configuration. Destructive by definition, and confirmed
            # above.
            print("resetting configuration from the uploaded script",
                  file=sys.stderr)
            router.run(
                f"/system reset-configuration no-defaults=yes skip-backup=yes "
                f'run-after-reset="{remote}"')
            print("device is rebooting; waiting for it to come back",
                  file=sys.stderr)
            _wait_for_router(router, args.wait)
            check_applied(router, marker, "")
        else:
            print("importing", file=sys.stderr)
            output = router.run(f'/import file-name="{remote}"')
            check_applied(router, marker, output)
    finally:
        if remote:
            router.remove(remote)
        shutil.rmtree(workdir, ignore_errors=True)

    if args.verify:
        identity = router.identity()
        if identity is None:
            raise ToolError("could not read /system identity after deploy")
        if args.expect_hostname and identity != args.expect_hostname:
            raise ToolError(
                f"identity is '{identity}', expected '{args.expect_hostname}'")
        print(f"verified: identity is '{identity}'")
    return 0


def _wait_for_router(router: Router, timeout: int) -> None:
    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            router.run("/system identity print")
            return
        except ToolError:
            time.sleep(3)
    raise ToolError(f"device did not come back within {timeout}s")


def _normalise(text: str) -> list[str]:
    """Strip what legitimately differs between a rendered script and /export."""
    lines = []
    for line in text.splitlines():
        stripped = line.strip()
        if not stripped or stripped.startswith("#"):
            continue
        # /export appends "; created by ..." and similar markers.
        lines.append(stripped)
    return lines


def cmd_diff(args: argparse.Namespace) -> int:
    import difflib

    router = Router(args.host, args.user, args.port, args.key, args.known_hosts)
    live = _normalise(router.export())
    with open(args.script, "r", encoding="utf-8") as handle:
        wanted = _normalise(handle.read())
    diff = list(difflib.unified_diff(
        live, wanted, fromfile=f"{args.host}:/export", tofile=args.script,
        lineterm=""))
    if not diff:
        print("no differences")
        return 0
    print("\n".join(diff))
    # 1 = "differs", which is what a wrapper script wants to branch on.
    return 1


# --------------------------------------------------------------------------

def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="nix-mikrotik",
        description="Build, secret-deliver and deploy RouterOS scripts.")
    sub = parser.add_subparsers(dest="command", required=True)

    p = sub.add_parser("render", help="build a configuration's script through nix")
    p.add_argument("--flake", default=".", help="flake reference (default: .)")
    p.add_argument("--name", required=True, help="mikrotikConfigurations.<name>")
    p.add_argument("--system", help="target system (default: the current one)")
    p.add_argument("-o", "--output", help="output path (default: <name>.rsc)")
    p.set_defaults(func=cmd_render)

    p = sub.add_parser("list-secrets", help="list a script's secret placeholders")
    p.add_argument("script")
    p.set_defaults(func=cmd_list_secrets)

    p = sub.add_parser("secretize", help="substitute secret values into a copy")
    p.add_argument("script")
    p.add_argument("-o", "--output", required=True)
    p.add_argument("--secret", action="append", default=[], metavar="NAME=PATH")
    p.add_argument("--secrets-dir", help="directory of files named after secrets")
    p.add_argument("--secret-command", metavar="CMD",
                   help="run CMD per unresolved secret ({name} substituted), "
                        "using its stdout instead of reading files")
    p.set_defaults(func=cmd_secretize)

    p = sub.add_parser("deploy", help="secretize, upload, import and verify")
    p.add_argument("script")
    p.add_argument("--host", required=True)
    p.add_argument("--user", default="admin")
    p.add_argument("--port", type=int, default=22)
    p.add_argument("--key", help="ssh private key")
    p.add_argument("--known-hosts", metavar="PATH",
                   help="known_hosts file ssh records host keys in (default: "
                        "the operator's ~/.ssh/known_hosts; a unit with no home "
                        "needs this, or every deploy is a first contact)")
    p.add_argument("--secret", action="append", default=[], metavar="NAME=PATH")
    p.add_argument("--secrets-dir")
    p.add_argument("--secret-command", metavar="CMD",
                   help="run CMD per unresolved secret ({name} substituted), "
                        "using its stdout instead of reading files")
    p.add_argument("--reset", action="store_true",
                   help="reset-configuration with the script (destructive)")
    p.add_argument("--yes", action="store_true", help="confirm --reset")
    p.add_argument("--wait", type=int, default=180,
                   help="seconds to wait for a reset device (default: 180)")
    p.add_argument("--verify", action="store_true",
                   help="read the identity back after deploying")
    p.add_argument("--expect-hostname", help="fail if the identity differs")
    p.add_argument("--dry-run", action="store_true")
    p.set_defaults(func=cmd_deploy)

    p = sub.add_parser("diff", help="diff the live config against a script")
    p.add_argument("script")
    p.add_argument("--host", required=True)
    p.add_argument("--user", default="admin")
    p.add_argument("--port", type=int, default=22)
    p.add_argument("--key")
    p.add_argument("--known-hosts", metavar="PATH",
                   help="known_hosts file ssh records host keys in (default: "
                        "the operator's ~/.ssh/known_hosts)")
    p.set_defaults(func=cmd_diff)

    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    try:
        return args.func(args)
    except ToolError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
