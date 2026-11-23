#!/usr/bin/env python3
"""Apply a rendered RouterOS configuration to a CHR and assert the device holds it.

This is the half `checks.render` cannot be. A rendered script is only correct if
a RouterOS *accepts* it and ends up in the state the configuration described,
and the device cannot be asked through an exit status: a script it refuses to
parse applies nothing and `/import` still exits 0. So "the build succeeded" and
"the router is configured" are different claims, and only a device settles the
second one.

The device is a CHR (see `chr/`), never a real router. What this does:

  bootstrap   wait for the device's REST API, generate an ssh key here, serve
              the public half to the guest over the slirp alias (10.0.2.2), and
              have the device import it -- `POST /tool/fetch` then
              `POST /user/ssh-keys/import`, both over REST, so no serial
              console is needed -- and `nix-mikrotik deploy` can then reach the
              device without a password.
  baseline    read the device *before* the deploy, so the assertions after it
              are assertions and not coincidence.
  mint        `nix-mikrotik generate <manifest> --state-dir DIR`, so the values
              are produced by the generators the configuration declares rather
              than made up by this check -- a persisted prompt is answered the
              way an operator answers one.
  deploy      `nix-mikrotik deploy <script> --generators <manifest>
              --generator-state-dir DIR --verify --expect-hostname`, exactly as
              an operator runs it. `--secret NAME=VALUE` remains for a device
              whose values this check does have to invent.
  assert      read the device's state back over REST and compare it with what
              the configuration said: the identity, a bridge with an address on
              it, a dhcp-server that draws from a pool created above it, a
              firewall comment containing `$` read back byte for byte, an
              interface whose line carries a secret, a *secret* delivered into a
              comment and read back byte for byte, and -- the one only a minted
              key can support -- a public key on the device that is the one the
              minted private key derives.
  refusals    deploy a deliberately broken script and require the deploy to
              *fail*, with the device's own log entry as evidence -- otherwise
              the passing case above is indistinguishable from a check that
              cannot fail.
  cleanup     remove the imported key again, so the device is left as found.

It runs inside the nixos test VM (`tests/chr-deploy.nix`) and just as well
against a CHR from `nix run .#chr-lab -- start` on the host, which is how it was
written and where every assertion below was first measured:

`--config` points the same harness at any other configuration: it asserts only
what holds for every script -- the device accepts it, the identity it sets, and no
`script error:` in the device's log -- and reports the assertions about this
fixture's own menus as skipped. That is how the examples are run against a CHR.

  tests/chr-deploy.py --host 127.0.0.1 --ssh-port 2201 --rest-port 8081 \\
      --script <chr-fixture>/router-config.rsc --expect-hostname chr-deploy \\
      --generators <chr-fixture-generators.json> --prompt comment=<value> \\
      --broken-script tests/fixtures/refused.rsc --cli <nix-mikrotik>
"""

from __future__ import annotations

import argparse
import base64
import http.server
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import threading
import time
import urllib.error
import urllib.request

# What `deploy` must say when the sentinel line it appended was never logged,
# and what it must not say. See `import_failed` in pkgs/nix_mikrotik.py.
PREFIX_WARNING = "may already have been applied"
VERIFIED_PREFIX = "verified: identity is"
# The differ's own count line for a plan with nothing to create: the shape a
# second deploy of the same script has to produce.
ADD_NONE = "0 add"


class Failure(Exception):
    """A step that could not be taken any further (as opposed to one that ran
    and did not hold): reported without a traceback."""


# ---------------------------------------------------------------------------
# the device
# ---------------------------------------------------------------------------

class Rest:
    """The device's REST API. `admin:` -- a fresh CHR has no password."""

    def __init__(self, host: str, port: int, user: str = "admin") -> None:
        self.base = f"http://{host}:{port}/rest"
        self.auth = base64.b64encode(f"{user}:".encode()).decode()

    def call(self, method: str, path: str, body=None, timeout: int = 15):
        data = json.dumps(body).encode() if body is not None else None
        request = urllib.request.Request(self.base + path, data=data, method=method)
        request.add_header("Authorization", "Basic " + self.auth)
        request.add_header("Content-Type", "application/json")
        try:
            with urllib.request.urlopen(request, timeout=timeout) as response:
                raw = response.read()
                return response.status, (json.loads(raw) if raw else None)
        except urllib.error.HTTPError as exc:
            # The device answers a refused command with a readable body; a
            # traceback from urllib is not a report.
            detail = exc.read().decode(errors="replace").strip()
            raise Failure(f"{method} {path} -> HTTP {exc.code} {detail}") from None
        except (urllib.error.URLError, OSError) as exc:
            # Not listening yet, or it did not answer in time. Both are states
            # the waits below poll on, so they are reported as one thing.
            raise Failure(f"{method} {path} -> {exc}") from None

    def get(self, path: str, timeout: int = 15):
        return self.call("GET", path, timeout=timeout)

    def menu(self, path: str, key: str = "name") -> dict:
        """A menu as a dict keyed by `key`, which is how the checks read it."""
        _, rows = self.get(path)
        return {row.get(key): row for row in rows}

    def wait(self, timeout: int) -> None:
        deadline = time.time() + timeout
        last: object = None
        while time.time() < deadline:
            try:
                status, _ = self.get("/system/resource", timeout=5)
                if status == 200:
                    return
            except Failure as exc:
                last = exc
            time.sleep(2)
        raise Failure(f"the device's REST API did not answer within {timeout}s ({last})")

    def wait_for_address(self, timeout: int) -> None:
        """Wait until the guest has an address of its own.

        The REST API answers as soon as the device's www service is up, which
        can be before its dhcp client has taken the slirp lease. Fetching the
        check's key needs the *guest's* side of the network -- it is the guest
        that connects to 10.0.2.2 -- so this waits for it rather than racing it
        (observed under TCG, where the boot is slow enough for the two to
        separate).
        """
        deadline = time.time() + timeout
        while time.time() < deadline:
            try:
                _, addresses = self.get("/ip/address")
            except Failure:
                addresses = []
            if addresses:
                return
            time.sleep(2)
        raise Failure(f"the device never took an address within {timeout}s, so it "
                      "cannot reach the host to fetch the check's key")

    def recent_log(self, topics: str = "", count: int = 4) -> str:
        _, entries = self.get("/log")
        if topics:
            entries = [e for e in entries if topics in str(e.get("topics"))]
        return " | ".join(str(e.get("message")) for e in entries[-count:]) or "(empty)"


class Ssh:
    """Only here to prove the imported key works before the deploy relies on it."""

    def __init__(self, host: str, port: int, key: str, user: str = "admin") -> None:
        self.host, self.port, self.key, self.user = host, port, key, user

    def run(self, command: str, timeout: int = 30):
        argv = [
            "ssh", "-o", "BatchMode=yes",
            "-o", "StrictHostKeyChecking=accept-new",
            "-o", "UserKnownHostsFile=/dev/null",
            "-o", "ConnectTimeout=15",
            "-o", "LogLevel=ERROR",
            "-i", self.key, "-p", str(self.port),
            f"{self.user}@{self.host}", command,
        ]
        proc = subprocess.run(argv, capture_output=True, text=True, timeout=timeout)
        return proc.returncode, (proc.stdout or "") + (proc.stderr or "")

    def wait(self, timeout: int = 120) -> None:
        deadline = time.time() + timeout
        while time.time() < deadline:
            rc, _ = self.run("/system identity print")
            if rc == 0:
                return
            time.sleep(2)
        raise Failure("ssh with the imported key never worked")


# ---------------------------------------------------------------------------
# the report
# ---------------------------------------------------------------------------

class Run:
    def __init__(self, fixture: bool = True) -> None:
        self.checks: list[tuple[str, bool, str]] = []
        # `fixture` is the default shape: this check's own router, whose menu
        # contents it knows. Pointed at somebody else's configuration
        # (`--config`) only the assertions that hold for any script are made,
        # and the rest are reported as skipped rather than quietly dropped.
        self.fixture = fixture

    def check(self, description: str, ok: bool, evidence: str = "") -> bool:
        ok = bool(ok)
        self.checks.append((description, ok, evidence))
        print(("  ok   " if ok else "  FAIL ") + description +
              (f"  [{evidence}]" if evidence else ""))
        return ok

    def fixture_check(self, description: str, ok: bool, evidence: str = "") -> bool:
        """An assertion about *this* fixture; skipped when running any config."""
        if not self.fixture:
            print("  skip " + description + "  [this check's own router, not asserted]")
            return True
        return self.check(description, ok, evidence)

    def contains(self, description: str, haystack: str, needle: str) -> bool:
        return self.check(description, needle in haystack,
                          f"{needle!r} {'found' if needle in haystack else 'NOT found'}")

    def report(self) -> int:
        failed = [c for c in self.checks if not c[1]]
        print(f"\n{len(self.checks) - len(failed)}/{len(self.checks)} assertions held")
        if failed:
            print("failed assertions:")
            for description, _, evidence in failed:
                print(f"  - {description}" + (f"  [{evidence}]" if evidence else ""))
            return 1
        return 0


# ---------------------------------------------------------------------------
# steps
# ---------------------------------------------------------------------------

def serve_file(directory: str):
    """Serve a directory on a free loopback port.

    The guest reaches this host's loopback as 10.0.2.2 (slirp), which is what
    lets `/tool fetch` pull the key with no shared filesystem and no console.
    """

    class Handler(http.server.SimpleHTTPRequestHandler):
        def __init__(self, *args, **kwargs):
            super().__init__(*args, directory=directory, **kwargs)

        def log_message(self, *_args, **_kwargs):
            pass  # the assertion report is the log; request lines are noise

    server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    return server, server.server_address[1]


def bootstrap(rest: Rest, host: str, ssh_port: int, slirp_host: str,
              workdir: str, run: Run) -> Ssh:
    """Give `nix-mikrotik deploy` an authenticated ssh path to the device."""
    key = os.path.join(workdir, "key")
    subprocess.run(["ssh-keygen", "-t", "ed25519", "-N", "", "-q",
                    "-C", "chr-deploy-check", "-f", key], check=True)

    server, http_port = serve_file(workdir)
    remote = "chr-deploy-check.pub"
    url = f"http://{slirp_host}:{http_port}/{os.path.basename(key)}.pub"
    print(f"  serving the public key to the guest at {url}")

    # The guest fetches the key from the host, so it needs its own address
    # first; a fetch issued before the dhcp lease lands leaves the file missing
    # and the import below answers 400 "no such file".
    rest.wait_for_address(timeout=180)

    def fetched() -> bool:
        _, files = rest.get("/file")
        return any(f.get("name") == remote for f in files)

    for attempt in range(5):
        rest.call("POST", "/tool/fetch", {"url": url, "dst-path": remote})
        if fetched():
            break
        if attempt == 4:
            raise Failure(
                f"the device did not fetch {url}: no {remote} in /file and its "
                f"fetch log reads {rest.recent_log(topics='fetch')!r}")
        time.sleep(3)

    rest.call("POST", "/user/ssh-keys/import",
              {"public-key-file": remote, "user": "admin"})

    _, keys = rest.get("/user/ssh-keys")
    run.check("the device imported this check's public key (REST)",
              any(k.get("key-owner") == "chr-deploy-check" for k in keys),
              f"{len(keys)} key(s) on the device")
    run.check("the device fetched the key file from the slirp host", True, remote)

    ssh = Ssh(host, ssh_port, key)
    ssh.wait()
    run.check("the imported key logs in", True, "ssh /system identity print")

    # The fetched copy has done its job; the key it carried is imported.
    rest.call("DELETE", f"/file/{remote}")
    server.shutdown()
    return ssh


def deploy(cli: str, script: str, host: str, ssh_port: int, key: str,
           secrets: list[str], workdir: str, generators: str | None = None,
           state_dir: str | None = None,
           extra: list[str] | None = None) -> subprocess.CompletedProcess:
    """Run the deploy tool the way an operator does, secrets and all.

    With `--generators`, the values come from the state directory the manifest
    points into -- the path a consumer takes, where nothing on the command line
    is a secret. Without it, `--secret` takes NAME=VALUE and the values are
    staged as files in this check's private directory: the tool is meant to read
    them off the deploying machine and never off a command line, and a base64
    key or a value carrying `$` is a poor thing to put in argv anyway.
    """
    argv = [cli, "deploy", script, "--host", host, "--port", str(ssh_port),
            "--key", key, "--verify"]
    if generators:
        argv += ["--generators", generators, "--generator-state-dir", state_dir]
    if extra:
        argv += extra
    for item in secrets:
        name, value = item.split("=", 1)
        # A secret name is `<generator>/<file>`, which is a path, not a file
        # name: flatten it before staging it.
        path = os.path.join(workdir, "secret-" + name.replace("/", "-"))
        fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            handle.write(value)
        argv += ["--secret", f"{name}={path}"]

    proc = subprocess.run(argv, capture_output=True, text=True, timeout=300)
    print(f"  $ nix-mikrotik deploy {os.path.basename(script)}  -> rc {proc.returncode}")
    for line in (proc.stdout + proc.stderr).strip().splitlines():
        print(f"      | {line}")

    # The tool's ssh uses `StrictHostKeyChecking=accept-new` against the
    # operator's own known_hosts (OpenSSH takes that path from the password
    # database, not from $HOME, and the tool passes no -o to redirect it). A CHR
    # rebuilt at a host:port deployed to before comes back with a new host key,
    # and the client then refuses -- a fact about the machine this runs on, not
    # about the configuration under test. Name the fix rather than letting it
    # read as a broken deploy. In `tests/chr-deploy.nix` it cannot arise: the
    # test VM starts with an empty /root.
    if "REMOTE HOST IDENTIFICATION HAS CHANGED" in proc.stderr:
        raise Failure(
            f"the deploy's ssh refused the host key of {host}:{ssh_port}: that "
            "port has been deployed to before with a different key (a rebuilt "
            "CHR generates a new one). Clear the stale entry with\n"
            f"  ssh-keygen -R '[{host}]:{ssh_port}'\n"
            "or run this against a port you have not deployed to before.")
    return proc


def load_manifest(path: str) -> list[dict]:
    """The generators a configuration declares, in the order they must run."""
    with open(path, "r", encoding="utf-8") as handle:
        document = json.load(handle)
    return document.get("generators") or []


def generated_file(state_dir: str, gen: dict, entry: dict) -> str:
    """Where a generated value lives: `<state-dir>/<relDir>/<file>`.

    The manifest carries each file's `relDir` -- clan's own layout,
    `per-machine/<router>/<generator>/` or `shared/<generator>/` -- so this
    reads the state directory the way clan would, and a translation table
    between the two never has to exist.
    """
    return os.path.join(state_dir, entry["relDir"], entry["name"])


def mint(cli: str, manifest: str, state_dir: str, prompts: dict[str, str],
         run: Run) -> str:
    """Run the configuration's generators, the way an operator's first deploy does.

    This is the half `--secret` cannot be: the key is minted here, by the
    generator that declares it, and only its path in the state directory reaches
    the deploy. A check that is handed a value instead never runs the code that
    makes one. Returns what the tool printed -- the names it minted.
    """
    argv = [cli, "generate", manifest, "--state-dir", state_dir]
    for name, value in prompts.items():
        argv += ["--prompt", f"{name}={value}"]
    proc = subprocess.run(argv, capture_output=True, text=True, timeout=300)
    print(f"  $ nix-mikrotik generate <manifest> --state-dir {state_dir}  -> "
          f"rc {proc.returncode}")
    for line in (proc.stdout + proc.stderr).strip().splitlines():
        print(f"      | {line}")
    if proc.returncode != 0:
        raise Failure(
            f"the configuration's generators did not run (rc {proc.returncode}): "
            f"{(proc.stderr or proc.stdout).strip().splitlines()[:1]}")
    return proc.stdout


def generated_values(gens: list[dict], state_dir: str) -> dict[str, str]:
    """The substituted set, keyed `<generator>/<file>` -- what a deploy will use.

    `deploy = false` files are intermediates another generator reads, so they are
    not part of it; a value is read the way the tool reads it, stripped of the
    newline a file carries.
    """
    values: dict[str, str] = {}
    for gen in gens:
        for entry in gen["files"]:
            if not entry.get("secret", True) or not entry.get("deploy", True):
                continue
            path = generated_file(state_dir, gen, entry)
            with open(path, "r", encoding="utf-8") as handle:
                values[f"{gen['name']}/{entry['name']}"] = handle.read().strip()
    return values


def derive_public_key(private_key: str) -> str:
    """The public half of a WireGuard private key, the way `wg` computes it."""
    proc = subprocess.run(["wg", "pubkey"], input=private_key, capture_output=True,
                          text=True, timeout=60)
    if proc.returncode != 0:
        raise Failure(
            f"`wg pubkey` could not derive the public key (rc {proc.returncode}): "
            f"{proc.stderr.strip()}")
    return proc.stdout.strip()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--ssh-port", type=int, default=2201)
    parser.add_argument("--rest-port", type=int, default=8081)
    parser.add_argument("--slirp-host", default="10.0.2.2",
                        help="how the guest reaches this host (slirp alias)")
    parser.add_argument("--script", required=True, help="the rendered .rsc to apply")
    parser.add_argument("--expect-hostname", required=True,
                        help="the identity that script sets")
    parser.add_argument("--secret", action="append", default=[],
                        metavar="NAME=VALUE",
                        help="a placeholder's value; fakes are fine, none of "
                             "these reaches a store or a repository")
    parser.add_argument("--generators", metavar="PATH",
                        help="the configuration's generator manifest: the check "
                             "mints the values with `generate` and deploys with "
                             "`--generators` instead of being handed them")
    parser.add_argument("--generator-state-dir", metavar="DIR",
                        help="where the minted values are kept (default: a "
                             "directory inside this check's workdir)")
    parser.add_argument("--prompt", action="append", default=[],
                        metavar="NAME=VALUE",
                        help="answer a generator prompt (repeatable)")
    parser.add_argument("--broken-script",
                        help="a script the device must refuse; without one this "
                             "check has no way to be wrong")
    parser.add_argument("--config", action="store_true",
                        help="run any configuration, not this check's own: assert "
                             "only what holds for every script (the device accepts "
                             "it, the identity it sets, and no refused line in the "
                             "device's log) and skip the fixture's menu contents")
    parser.add_argument("--cli", default="nix-mikrotik",
                        help="the nix-mikrotik binary to deploy with")
    parser.add_argument("--rest-wait", type=int, default=300,
                        help="seconds to wait for the device's REST API")
    args = parser.parse_args()

    secrets = {}
    for item in args.secret:
        name, value = item.split("=", 1)
        secrets[name] = value
    prompts = {}
    for item in args.prompt:
        name, value = item.split("=", 1)
        prompts[name] = value

    run = Run(fixture=not args.config)
    if args.config:
        print("--config: asserting what holds for any configuration -- the device "
              "accepts the script, the identity it sets, and no `script error:` in "
              "the device's log. This check's own menu contents are not asserted.")
    workdir = tempfile.mkdtemp(prefix="chr-deploy-")
    os.chmod(workdir, 0o700)
    state_dir = None
    gens: list[dict] = []
    values: dict[str, str] = {}
    try:
        rest = Rest(args.host, args.rest_port)
        print("waiting for the device's REST API")
        rest.wait(args.rest_wait)

        print("bootstrapping ssh access")
        bootstrap(rest, args.host, args.ssh_port, args.slirp_host, workdir, run)

        # ---------------------------------------------------------- baseline --
        # The state the deploy is about to change. Without this, "the identity
        # is chr-deploy afterwards" reads the same on a device that ignored the
        # script and happened to be called that already.
        print("reading the device before the deploy")
        _, identity = rest.get("/system/identity")
        run.fixture_check("before the deploy the identity is the device's own default",
                  identity.get("name") == "MikroTik", identity.get("name", "?"))
        bridges_before = rest.menu("/interface/bridge")
        run.fixture_check("before the deploy no bridge exists", not bridges_before,
                  f"{len(bridges_before)} bridge(s)")
        wireguard_before = rest.menu("/interface/wireguard")
        run.fixture_check("before the deploy no wireguard interface exists",
                  not wireguard_before, f"{len(wireguard_before)} interface(s)")

        # ------------------------------------------------------------- mint --
        # The values the configuration's menu cells reference are minted here,
        # by the generators the configuration declares -- not handed in. This
        # runs before the deploy and after the device is up, which is the order
        # an operator's first deploy has.
        if args.generators:
            print("minting the configuration's secret values")
            state_dir = args.generator_state_dir or os.path.join(workdir, "vars")
            os.makedirs(state_dir, mode=0o700, exist_ok=True)
            gens = load_manifest(args.generators)
            run.check("the manifest declares the configuration's generators",
                      bool(gens), ", ".join(g["name"] for g in gens) or "none")
            printed = mint(args.cli, args.generators, state_dir, prompts, run)
            values = generated_values(gens, state_dir)
            run.check("`generate` reported every value it minted",
                      bool(values) and all(
                          f"{gen['name']}/{entry['name']}" in printed
                          for gen in gens for entry in gen["files"]
                          if entry.get("secret", True) and entry.get("deploy", True)),
                      ", ".join(sorted(values)) or "none")
            # clan's layout, because it is the layout the manifest carries:
            # `per-machine/<router>/<generator>/<file>` (or `shared/<generator>`
            # for a generator every machine reads), at the mode the manifest
            # declares. A value filed anywhere else, or readable, is not a value
            # a clan repository could hold.
            wrong: list[str] = []
            for gen in gens:
                want_dir = (f"shared/{gen['name']}" if gen.get("share")
                            else f"per-machine/{args.expect_hostname}/{gen['name']}")
                for entry in gen["files"]:
                    label = f"{gen['name']}/{entry['name']}"
                    if entry["relDir"] != want_dir:
                        wrong.append(f"{label} is under {entry['relDir']}, not {want_dir}")
                        continue
                    path = generated_file(state_dir, gen, entry)
                    if not os.path.isfile(path):
                        wrong.append(f"{label} missing")
                        continue
                    want = entry.get("mode") or ("0400" if entry.get("secret", True) else "0444")
                    got = format(os.stat(path).st_mode & 0o777, "04o")
                    if got != want:
                        wrong.append(f"{label} is {got}, declared {want}")
            run.check("every minted value is in clan's layout, at the mode the manifest declares",
                      not wrong, " | ".join(wrong) or
                      ", ".join(os.path.relpath(generated_file(state_dir, g, e), state_dir)
                                for g in gens for e in g["files"]))

        # ------------------------------------------------------------ deploy --
        print("deploying the rendered configuration")
        proc = deploy(args.cli, args.script, args.host, args.ssh_port,
                      os.path.join(workdir, "key"), args.secret, workdir,
                      generators=args.generators, state_dir=state_dir)
        output = proc.stdout + proc.stderr
        run.check("the device accepted the rendered script (rc 0)",
                  proc.returncode == 0, f"rc {proc.returncode}")
        run.contains("deploy verified the identity the script sets",
                     output, f"{VERIFIED_PREFIX} '{args.expect_hostname}'")

        # ------------------------------------------------------- device state --
        # The device's own answer, over REST: a transport that shares nothing
        # with the deploy tool's ssh, so a deploy that lied about itself cannot
        # make these hold.
        print("reading the device back")
        identity_name = rest.get("/system/identity")[1].get("name")
        run.check("the identity is what the configuration said",
                  identity_name == args.expect_hostname, identity_name or "?")

        bridges = rest.menu("/interface/bridge")
        run.fixture_check("the bridge the configuration creates exists", "lan" in bridges,
                  ", ".join(bridges) or "none")
        run.fixture_check("... with the comment the configuration gave it",
                  bridges.get("lan", {}).get("comment") == "chr-deploy-check",
                  repr(bridges.get("lan", {}).get("comment", "none")))

        _, addresses = rest.get("/ip/address")
        on_lan = [a.get("address") for a in addresses if a.get("interface") == "lan"]
        run.fixture_check("the address the configuration puts on that bridge exists",
                  "192.168.88.1/24" in on_lan, ", ".join(on_lan) or "none")

        dhcp = rest.menu("/ip/dhcp-server")
        run.fixture_check("the dhcp-server that draws from the pool above it exists",
                  dhcp.get("lan-dhcp", {}).get("interface") == "lan",
                  ", ".join(dhcp) or "none")

        dns = rest.menu("/ip/dns/static")
        entry = dns.get("chr-deploy.lan", {})
        run.fixture_check("the static dns entry exists, pointing where the script said",
                  entry.get("address") == "192.168.88.1", entry.get("address", "none"))
        # A value substituted into a comment and read back byte for byte: the
        # value the deploy tool had to quote and escape on its way in. With
        # `--generators` it is the one the prompt produced, not one this check
        # made up.
        delivered = dict(secrets)
        delivered.update(values)
        run.fixture_check("a secret delivered into a comment reads back byte for byte",
                  "dns/comment" in delivered
                  and entry.get("comment") == delivered["dns/comment"],
                  repr(entry.get("comment", "none")))

        nat = rest.menu("/ip/firewall/nat")
        run.fixture_check("a comment containing '$' reads back byte for byte",
                  any(n.get("comment") == "masquerade (cost $5/GB)"
                      for n in nat.values()),
                  " | ".join(n.get("comment", "") for n in nat.values()) or "none")

        wireguard = rest.menu("/interface/wireguard")
        wg = wireguard.get("wg.check", {})
        # The interface exists at all only if the *whole* script ran: the secret
        # on its line is 32 bytes of base64, and unquoted that trailing `=` ends
        # the command early and the device refuses the script from the top.
        run.fixture_check("the interface whose line carries a secret was created",
                  bool(wg), ", ".join(wireguard) or "none")
        run.fixture_check("... with the rest of its line applied",
                  wg.get("listen-port") == "51820" and wg.get("mtu") == "1420",
                  f"listen-port={wg.get('listen-port')} mtu={wg.get('mtu')}")

        # The cross-check that makes the two above mean something: the key on the
        # device has to be the public half of the key this run minted. A deploy
        # that substituted some other value -- a stale state directory, another
        # router's key, a placeholder substituted from the wrong generator --
        # would still create the interface and still set the port.
        if args.generators and "wg/private-key" in values:
            derived = derive_public_key(values["wg/private-key"])
            run.fixture_check("the device's wireguard public key is the one the minted private key derives",
                      wg.get("public-key") == derived,
                      f"device={wg.get('public-key') or 'none'} derived={derived}")

        _, files = rest.get("/file")
        left = [f.get("name") for f in files
                if str(f.get("name", "")).endswith(".rsc")]
        run.check("the uploaded copy was removed from the device", not left,
                  ", ".join(left) or "no .rsc files")

        _, log = rest.get("/log")
        # RouterOS logs `script,error executing script from sshd failed` for any
        # command a client runs over ssh that exits non-zero -- measured: a
        # `/file remove` of a file that is not there does exactly that, and the
        # deploy tool retries that removal on purpose because it races the
        # import. So the diagnostic worth asserting on is the device's own
        # `script error: …` line, which is what a refused import leaves.
        diagnostics = [e.get("message") for e in log
                       if "script,error" in str(e.get("topics"))
                       and "script error:" in str(e.get("message"))]
        run.check("the device's log holds no `script error:` from this deploy",
                  not diagnostics, " | ".join(diagnostics[-2:]) or "no script error line")
        incidental = [e for e in log
                      if "executing script from sshd failed" in str(e.get("message"))]
        if incidental:
            print(f"  note: {len(incidental)} `executing script from sshd failed` "
                  "line(s) -- RouterOS logs one for any ssh command that exits "
                  "non-zero, which the deploy's retried file removal does")

        # ------------------------------------------------------------ upsert --
        # `deploy` applies the difference between the device's own `/export` and
        # the script, not the script itself. What that buys is only visible on a
        # *second* run: `/import` of `add` lines is not idempotent, so the old
        # path could not be run twice against a device that already held the
        # configuration. These are the assertions that separate the two.
        print("deploying the same script again (upsert)")
        before_counts = {
            "bridge": len(rest.menu("/interface/bridge")),
            "pool": len(rest.menu("/ip/pool")),
            "wireguard": len(rest.menu("/interface/wireguard")),
            "address": len(rest.get("/ip/address")[1]),
            "dhcp-server": len(rest.menu("/ip/dhcp-server")),
            "dns-static": len(rest.menu("/ip/dns/static")),
        }
        wg_id = rest.menu("/interface/wireguard").get("wg.check", {}).get(".id")
        proc = deploy(args.cli, args.script, args.host, args.ssh_port,
                      os.path.join(workdir, "key"), args.secret, workdir,
                      generators=args.generators, state_dir=state_dir)
        output = proc.stdout + proc.stderr
        run.check("a second deploy of the same script succeeds (rc 0)",
                  proc.returncode == 0, f"rc {proc.returncode}")
        # Either shape is the upsert working: a plan of sets only, or nothing at
        # all. What must not appear is an `add`, which is what re-importing the
        # script would emit for every object it already made.
        run.check("... and it computes no adds",
                  "no changes" in output or ADD_NONE in output,
                  " | ".join(l.strip() for l in output.splitlines()
                             if "operations:" in l or "no changes" in l) or "no summary")
        after_counts = {
            "bridge": len(rest.menu("/interface/bridge")),
            "pool": len(rest.menu("/ip/pool")),
            "wireguard": len(rest.menu("/interface/wireguard")),
            "address": len(rest.get("/ip/address")[1]),
            "dhcp-server": len(rest.menu("/ip/dhcp-server")),
            "dns-static": len(rest.menu("/ip/dns/static")),
        }
        run.check("... and nothing was duplicated on the device",
                  after_counts == before_counts,
                  f"{before_counts} -> {after_counts}")

        # A one-property change, which is the other half of "upsert": the object
        # is *set*, not re-created, so its handle on the device survives.
        print("deploying a one-property change")
        changed = os.path.join(workdir, "changed.rsc")
        with open(args.script, "r", encoding="utf-8") as handle:
            original = handle.read()
        if "listen-port=51820" not in original:
            raise Failure("this check's fixture no longer carries listen-port=51820, "
                          "so the one-property change below would test nothing")
        with open(changed, "w", encoding="utf-8") as handle:
            handle.write(original.replace("listen-port=51820", "listen-port=51821"))
        proc = deploy(args.cli, changed, args.host, args.ssh_port,
                      os.path.join(workdir, "key"), args.secret, workdir,
                      generators=args.generators, state_dir=state_dir)
        output = proc.stdout + proc.stderr
        run.check("a changed property deploys (rc 0)", proc.returncode == 0,
                  f"rc {proc.returncode}")
        wg_after = rest.menu("/interface/wireguard").get("wg.check", {})
        run.check("the device holds the changed value",
                  wg_after.get("listen-port") == "51821",
                  f"listen-port={wg_after.get('listen-port')}")
        # The interface is not removed and re-added: same handle, and the peers
        # and routes pointing at it are not disturbed.
        run.check("... on the object that was already there, not a re-created one",
                  bool(wg_id) and wg_after.get(".id") == wg_id,
                  f"{wg_id} -> {wg_after.get('.id')}")
        run.check("... applied as a `set`: the plan has no add and no remove",
                  bool(re.search(r"\b0 add\b", output)) and bool(re.search(r"\b0 remove\b", output)),
                  " | ".join(l.strip() for l in output.splitlines()
                             if "operations:" in l) or "no summary")

        # And the contrast, which is what makes the two above a check: the path
        # this replaces, re-importing the whole script, fails on a device that
        # already holds it.
        print("re-importing the whole script (the path the patch replaces)")
        proc = deploy(args.cli, args.script, args.host, args.ssh_port,
                      os.path.join(workdir, "key"), args.secret, workdir,
                      generators=args.generators, state_dir=state_dir,
                      extra=["--import-whole"])
        output = proc.stdout + proc.stderr
        run.check("re-importing the same script fails instead of duplicating it",
                  proc.returncode != 0, f"rc {proc.returncode}")
        run.contains("... and the failure says a prefix may have been applied",
                     output, PREFIX_WARNING)

        # --------------------------------------------------------- refusals --
        if args.broken_script:
            print("deploying a script the device must refuse")
            proc = deploy(args.cli, args.broken_script, args.host, args.ssh_port,
                          os.path.join(workdir, "key"), args.secret, workdir,
                          generators=args.generators, state_dir=state_dir)
            output = proc.stdout + proc.stderr
            run.check("a broken script fails the deploy instead of passing it",
                      proc.returncode != 0, f"rc {proc.returncode}")
            run.contains("the failure warns that a prefix may have been applied",
                         output, PREFIX_WARNING)
            run.check("the failure prints no verified line",
                      VERIFIED_PREFIX not in output, "no 'verified:' line")

            # The device's own account of the refusal: a parse error, which is
            # the case `deploy` can only *warn* about.
            _, log = rest.get("/log")
            parse_errors = [e.get("message") for e in log
                            if "script,error" in str(e.get("topics"))
                            and "expected end of command" in str(e.get("message"))]
            run.check("the device's log names the parse error it refused",
                      bool(parse_errors), parse_errors[-1] if parse_errors else "none")

            # A parse error is refused before anything runs, so nothing at all
            # from that script applies -- not even the identity line above the
            # bad one. (The runtime-error shape is the other way round and does
            # apply a prefix: that is what the warning above is for.)
            after = rest.get("/system/identity")[1].get("name")
            run.check("... and the refused script changed nothing on the device",
                      after == args.expect_hostname, after or "?")
            run.check("... and no object from the refused script exists",
                      "broken-wg" not in rest.menu("/interface/wireguard"),
                      ", ".join(rest.menu("/interface/wireguard")) or "none")

        # ----------------------------------------------------------- cleanup --
        print("removing this check's key from the device")
        _, keys = rest.get("/user/ssh-keys")
        for entry in keys:
            if entry.get("key-owner") == "chr-deploy-check":
                rest.call("DELETE", f"/user/ssh-keys/{entry['.id']}")
        _, keys = rest.get("/user/ssh-keys")
        run.check("the key this check added was removed again",
                  all(k.get("key-owner") != "chr-deploy-check" for k in keys),
                  f"{len(keys)} key(s) left")

        return run.report()
    except Failure as exc:
        print(f"\nFAILED: {exc}", file=sys.stderr)
        try:
            print(f"the device's last log lines: {rest.recent_log(count=6)}",
                  file=sys.stderr)
        except Exception:  # noqa: BLE001 -- the device may be gone entirely
            pass
        run.report()
        return 1
    finally:
        shutil.rmtree(workdir, ignore_errors=True)


if __name__ == "__main__":
    sys.exit(main())