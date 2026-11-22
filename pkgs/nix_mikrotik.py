#!/usr/bin/env python3
"""nix-mikrotik -- build, secret-deliver and deploy RouterOS scripts.

The nix side owns rendering (lib/render.nix): a configuration is evaluated to a
`.rsc` file in the store, with `__MIKROTIK_SECRET_<name>__` placeholders where a
secret value belongs. This tool owns everything that must happen *off* the
store:

  render      build a configuration's script through nix and copy it out
  list-secrets  list the placeholders a script still contains
  secretize   substitute real values into a private temporary copy
  deploy      secretize, diff against the device, import the difference, verify
  diff        export the device's live config and diff it textually against the script

`deploy` applies the *difference* between the device's own `/export` and the
script, computed by `rsc` (the crate in `rsc/`), rather than re-importing every
line. That is what makes a second deploy safe: `/import` of `add` lines is not
idempotent -- a repeated `add` makes a second object, and the device refuses the
script from that point on -- while a patch that says `set [find name=…]` for an
object that already exists converges. Deletions are withheld by default
(`--prune` applies them): an `/export` carries the whole configuration, so
"not in the target" includes the address the deploy itself is talking over.
`--import-whole` keeps the old path, and `--check` prints the plan and stops.

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
import getpass
import json
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
#
# A *generated* file is named `<generator>/<file>`: one slash, no more, because
# the name doubles as the path below the state directory the value is kept at
# and the tool only ever creates one level there.
SECRET_PART_RE = re.compile(r"[A-Za-z0-9][A-Za-z0-9._-]*")
SECRET_NAME_RE = re.compile(r"[A-Za-z0-9][A-Za-z0-9._-]*(?:/[A-Za-z0-9][A-Za-z0-9._-]*)?")

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
            "match [A-Za-z0-9][A-Za-z0-9._-]* -- letters, digits, dot, dash and "
            "underscore -- with at most one '/' naming a generator's file "
            f"('{SECRET_PART_RE.pattern}' on each side of it)")
    return name


def check_var_path(path: str) -> str:
    """A `varFiles` path: where a generated file sits under the vars directory.

    Clan's own spelling -- `per-machine/<machine>/<generator>/<file>`,
    `shared/<generator>/<file>`, `per-export/<export>/<generator>/<file>` -- so
    this is several segments, not the one slash a placeholder name has. It is
    still a *relative* path joined to `--secrets-dir`, so `..`, `.` and an
    absolute path are refused: they are how a manifest would read a file outside
    the directory the operator pointed at.
    """
    segments = path.split("/")
    if (
        path.startswith("/")
        or not path
        or any(segment in ("", ".", "..") for segment in segments)
        or any(SECRET_PART_RE.fullmatch(segment) is None for segment in segments)
    ):
        raise ToolError(
            f"varFiles path '{path}' is not a path under the vars directory: "
            "expected clan's layout, `per-machine/<machine>/<generator>/<file>` "
            "or `shared/<generator>/<file>` -- relative, no '..', no absolute "
            f"path, each segment matching {SECRET_PART_RE.pattern}")
    return path


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


def read_secret_files(
    directory: str,
    names: list[str],
    files: dict[str, str] | None = None,
) -> dict[str, str]:
    """Values read out of `--secrets-dir`, keyed by placeholder name.

    `files` maps a placeholder name to the path its value actually sits at: the
    manifest's `varFiles` carries clan's own layout for a generated file
    (`per-machine/<machine>/<generator>/<file>`, `shared/<generator>/<file>`),
    relative to the vars directory. Without an entry the name is the path, which
    is the flatter convention a configuration of its own generators wants.
    """
    files = files or {}
    values: dict[str, str] = {}
    root = os.path.realpath(directory) if directory else ""
    for name in names:
        # Belt and braces: the name is a path component, and every caller has
        # already validated it, but this is the line that would read a file
        # outside the directory if one ever did not.
        check_secret_name(name)
        rel = check_var_path(files.get(name, name))
        path = os.path.join(directory, rel)
        # `..` is refused above, and this is the second lock on the same door:
        # a path that resolves outside the directory is not read at all.
        if root and not os.path.realpath(path).startswith(root + os.sep):
            raise ToolError(
                f"varFiles path '{rel}' resolves outside --secrets-dir {directory}")
        if not os.path.isfile(path):
            # clan's own store: a var is a *directory* that holds `secret` for a
            # secret and `value` for a published one
            # (`vars/per-machine/<machine>/<generator>/<file>/secret`). Point
            # `--secrets-dir` at the tree and the placeholder name is the path.
            for leaf in ("secret", "value"):
                candidate = os.path.join(path, leaf)
                if os.path.isfile(candidate):
                    path = candidate
                    break
        if not os.path.isfile(path):
            continue
        with open(path, "r", encoding="utf-8") as handle:
            values[name] = handle.read().strip()
    return values


def read_sops_secrets(path: str, names: list[str], key_file: str | None) -> dict[str, str]:
    """Decrypt this router's secrets out of a sops file, at deploy time.

    The deploying host never holds the plaintext: the file is encrypted in the
    store, and `sops -d --extract` is what turns one entry into one value, in
    memory, in the deploy process. The key is the *host's own* sops key, so no
    activation step is needed on the machine and nothing is staged to disk.

    `key_file` sets `SOPS_AGE_KEY_FILE` for the subprocess; left unset, sops
    finds its key the way it already does (that environment variable, or
    `~/.config/sops/age/keys.txt`).
    """
    env = dict(os.environ)
    if key_file is None and "SOPS_AGE_KEY_FILE" not in env:
        # The host's own key if it has one -- sops-nix puts it here -- and
        # otherwise nothing: sops falls back to the user's key
        # (~/.config/sops/age/keys.txt), which is what an operator running this
        # by hand has. Either way no activation step is needed on the machine.
        host_key = "/var/lib/sops-nix/key.txt"
        if os.path.exists(host_key):
            key_file = host_key
    if key_file is not None:
        env["SOPS_AGE_KEY_FILE"] = key_file
    values: dict[str, str] = {}
    for name in names:
        check_secret_name(name)
        try:
            proc = subprocess.run(
                ["sops", "-d", path, "--extract", f'["{name}"]'],
                capture_output=True, text=True, env=env)
        except FileNotFoundError as exc:
            raise ToolError(
                "--sops-file needs sops on PATH (add pkgs.sops to the unit's path)") from exc
        if proc.returncode != 0:
            detail = (proc.stderr or proc.stdout).strip().splitlines()
            raise ToolError(
                f"sops could not read '{name}' from {path} (exit {proc.returncode})"
                + ("\n" + detail[0] if detail else ""))
        value = proc.stdout.rstrip("\n")
        if value == "":
            raise ToolError(f"sops returned no value for '{name}' in {path}")
        values[name] = value
    return values


def generate_secrets(template: str, names: list[str], state_dir: str | None) -> dict[str, str]:
    """Mint values for secrets that do not exist yet, and keep them.

    This is the "run the var generators" path: a host with no clan can ask for a
    key to be created rather than read. `{name}` is substituted, stdout is the
    value, and with `--generator-state-dir` the value is written there (0600) so
    the *next* deploy reads it instead of minting a second key for the same
    tunnel -- a generator that runs on every deploy would renumber every tunnel
    it touches.

    Anything already present in the state directory is read, not regenerated:
    that is what makes the mint a one-time act.
    """
    values: dict[str, str] = {}
    if state_dir is not None:
        values.update(read_secret_files(state_dir, names))
    for name in names:
        if name in values:
            continue
        check_secret_name(name)
        proc = subprocess.run(
            ["sh", "-c", template.replace("{name}", name)],
            capture_output=True, text=True)
        if proc.returncode != 0:
            detail = (proc.stderr or proc.stdout).strip().splitlines()
            raise ToolError(
                f"--secret-generator failed for '{name}' (exit {proc.returncode})"
                + ("\n" + detail[0] if detail else ""))
        value = proc.stdout.rstrip("\n")
        if value == "":
            raise ToolError(f"--secret-generator produced no value for '{name}'")
        values[name] = value
        if state_dir is not None:
            os.makedirs(state_dir, exist_ok=True)
            path = os.path.join(state_dir, name)
            fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
            with os.fdopen(fd, "w", encoding="utf-8") as handle:
                handle.write(value + "\n")
    return values


def load_manifest(path: str) -> tuple[list[dict], dict[str, str]]:
    """Read the manifest `lib.manifest` renders, or a flake's `<name>-generators`.

    Two documents in one file, because a placeholder is either minted here or
    read from `--secrets-dir`, never both:

        { "generators": [ …the list load_generator_manifest validates… ]
        , "varFiles": { "mesh-chr1-private-key": { "path": "per-machine/flagship/mikrotik-lab-peers/chr1"
                                                , "description": "…" } } }

    `varFiles` maps a *placeholder name* to the path under `--secrets-dir`, and
    the path is clan's own layout for a generated file -- the directory clan
    files the generator in (`per-machine/<machine>/<generator>`, or
    `shared/<generator>`) plus the file name. The path is optional in the
    manifest: a bare list of generators -- the older shape, which fixtures and
    hand-written manifests still use -- reads as "the placeholder name is the
    file name", and `file` is accepted as the older spelling of `path`.
    """
    try:
        with open(path, "r", encoding="utf-8") as handle:
            data = json.load(handle)
    except OSError as exc:
        raise ToolError(f"cannot read the generator manifest {path}: {exc}") from exc
    except json.JSONDecodeError as exc:
        raise ToolError(f"{path} is not a generator manifest: {exc}") from exc

    if isinstance(data, list):
        return validate_generators(path, data), {}

    if not isinstance(data, dict):
        raise ToolError(
            f"{path} is not a generator manifest: expected a list of generators "
            f"or an object with a 'generators' key, got {type(data).__name__}")

    if "generators" not in data:
        raise ToolError(f"{path} is not a generator manifest: it has no 'generators' key")
    generators = validate_generators(path, data["generators"])

    declared = data.get("varFiles") or {}
    if not isinstance(declared, dict):
        raise ToolError(
            f"{path}: 'varFiles' must be an object keyed by placeholder name, "
            f"got {type(declared).__name__}")
    var_files: dict[str, str] = {}
    for name, entry in declared.items():
        check_secret_name(name)
        if entry is None:
            entry = {}
        if not isinstance(entry, dict):
            raise ToolError(f"{path}: varFiles entry '{name}' must be an object")
        file = entry.get("path", entry.get("file"))
        if file is None:
            file = name
        elif not isinstance(file, str) or not file:
            raise ToolError(f"{path}: varFiles entry '{name}' has a path that is not a string")
        var_files[name] = check_var_path(file)
    return generators, var_files


def load_generator_manifest(path: str) -> list[dict]:
    """The generators alone, for callers that do not resolve `varFiles`."""
    return load_manifest(path)[0]


def validate_generators(path: str, data: list) -> list[dict]:
    """Check a generator list from the manifest `lib.generators` renders.

    The shape is the one `secrets.<name>` has in nix, minus everything the tool
    has no use for:

        [ { "name": "wg-9600-baud-net-key"
          , "files": [ { "name": "privkey", "secret": true }
                     , { "name": "pubkey",  "secret": false } ]
          , "runtimeInputs": [ "/nix/store/…-wireguard-tools" ]
          , "script": "wg genkey | tee $out/privkey | wg pubkey > $out/pubkey" } ]

    A list, not an attrset: the order is the order the generators were declared
    in, and one generator's script may read what an earlier one published.
    """
    if not isinstance(data, list):
        raise ToolError(
            f"{path} is not a generator manifest: expected a list of generators, "
            f"got {type(data).__name__}")
    for gen in data:
        if not isinstance(gen, dict):
            raise ToolError(f"{path}: every generator must be an object, got {type(gen).__name__}")
        name = gen.get("name")
        if not isinstance(name, str) or not name:
            raise ToolError(f"{path}: a generator has no name")
        check_secret_name(name)
        if "/" in name:
            raise ToolError(f"{path}: generator name '{name}' must not contain '/'")
        if not isinstance(gen.get("script"), str) or not gen["script"].strip():
            raise ToolError(f"generator '{name}' has no script")
        files = gen.get("files")
        if not isinstance(files, list) or not files:
            raise ToolError(f"generator '{name}' declares no files")
        for entry in files:
            if not isinstance(entry, dict) or not isinstance(entry.get("name"), str):
                raise ToolError(f"generator '{name}' has a file with no name")
            check_secret_name(f"{name}/{entry['name']}")
            mode = entry.get("mode")
            if mode is not None and not re.fullmatch(r"[0-7]{4}", str(mode)):
                raise ToolError(
                    f"generator '{name}' file '{entry['name']}' has a mode that is "
                    f"not a 4-digit octal number: {mode!r}")
        inputs = gen.get("runtimeInputs") or []
        if not isinstance(inputs, list) or not all(isinstance(i, str) for i in inputs):
            raise ToolError(f"generator '{name}' has runtimeInputs that are not paths")
        dependencies = gen.get("dependencies") or []
        if not isinstance(dependencies, list) or not all(isinstance(d, str) for d in dependencies):
            raise ToolError(f"generator '{name}' has dependencies that are not names")
        prompts = gen.get("prompts") or []
        if not isinstance(prompts, list):
            raise ToolError(f"generator '{name}' has prompts that are not a list")
        for prompt in prompts:
            if not isinstance(prompt, dict) or not isinstance(prompt.get("name"), str):
                raise ToolError(f"generator '{name}' has a prompt with no name")
            check_secret_name(prompt["name"])
            if "/" in prompt["name"]:
                raise ToolError(
                    f"generator '{name}' prompt '{prompt['name']}' must not contain '/'")
    return data


def generator_file(state_dir: str, gen: dict, entry: dict) -> str:
    """Where a generated file lives: `state_dir` + the `relDir` the manifest gave.

    The layout is clan's, not this tool's: `per-machine/<machine>/<generator>/`
    for a router's own values and `shared/<generator>/` for one declared
    `share = true`. A manifest carries each file's `relDir` so this function
    does not have to know which case it is in, and so a state directory that
    clan owns can be read as-is -- the same files `clan vars get` would print,
    at the same paths, without a translation table.

    `relDir` is required rather than defaulted. A default would be a second
    spelling of the layout, and the two would drift: the deploy tool would read
    a value from one path while clan wrote it to another, which looks exactly
    like a value that was never generated.
    """
    rel = entry.get("relDir")
    if not isinstance(rel, str) or not rel:
        raise ToolError(
            f"generator '{gen.get('name')}' file '{entry.get('name')}' has no relDir: "
            "the manifest has to say where the value belongs in the state directory")
    if os.path.isabs(rel) or ".." in rel.split("/"):
        raise ToolError(
            f"generator '{gen.get('name')}' file '{entry.get('name')}' has a relDir "
            f"that is not inside the state directory: {rel!r}")
    return os.path.join(state_dir, rel, entry["name"])


def generator_dir(state_dir: str, gen: dict, entry: dict) -> str:
    """The directory a generator's files share, for removing a complete set."""
    return os.path.dirname(generator_file(state_dir, gen, entry))


def generator_paths(state_dir: str, gen: dict) -> dict[str, str]:
    """Every file of a generator, by name, whether or not it exists yet."""
    return {
        entry["name"]: generator_file(state_dir, gen, entry)
        for entry in gen["files"]
    }


# clan keeps each generator's invalidation hash in a dot-file inside the
# generator's own directory (`VALIDATION_HASH_NAME` in
# `clan_lib/vars/_types.py`), so a state directory can be read by clan and by
# this tool without a translation table. The hash is what makes `validation`
# mean anything: a file on disk is not enough if the *definition* of the
# generator changed.
VALIDATION_HASH_NAME = ".validation-hash"


def validation_hash_file(state_dir: str, gen: dict) -> str:
    return os.path.join(generator_dir(state_dir, gen, gen["files"][0]), VALIDATION_HASH_NAME)


def stored_validation(state_dir: str, gen: dict) -> str | None:
    path = validation_hash_file(state_dir, gen)
    if not os.path.isfile(path):
        return None
    with open(path, "r", encoding="utf-8") as handle:
        return handle.read().strip()


def validation_is_valid(state_dir: str, gen: dict) -> bool:
    """clan's rule: unset on both sides is valid, otherwise they must match."""
    target = gen.get("validationHash")
    stored = stored_validation(state_dir, gen)
    if target is None and stored is None:
        return True
    return stored == target


def write_validation(state_dir: str, gen: dict) -> None:
    path = validation_hash_file(state_dir, gen)
    target = gen.get("validationHash")
    if target is None:
        if os.path.exists(path):
            os.remove(path)
        return
    os.makedirs(os.path.dirname(path), mode=0o700, exist_ok=True)
    with open(path, "w", encoding="utf-8") as handle:
        handle.write(target + "\n")


def read_generated(state_dir: str, gen: dict) -> dict[str, str]:
    """The secret half of an already-generated generator, keyed `<name>/<file>`.

    A file declared `deploy = false` is an intermediate that only another
    generator reads, so it is not part of the set a menu cell may substitute.
    """
    values: dict[str, str] = {}
    for entry in gen["files"]:
        if not entry.get("secret", True) or not entry.get("deploy", True):
            continue
        path = generator_file(state_dir, gen, entry)
        if not os.path.isfile(path):
            continue
        with open(path, "r", encoding="utf-8") as handle:
            values[f"{gen['name']}/{entry['name']}"] = handle.read().strip()
    return values


def read_prompt_previous(state_dir: str, gen: dict, prompt: dict) -> str | None:
    """A persisted prompt's previous value, read from the file it becomes.

    `prompts.<name>.persist = true` makes the prompt a file of the generator --
    the Nix module does the same -- so the first run's answer is what a later
    run reads instead of asking again.
    """
    if not prompt.get("persist"):
        return None
    for entry in gen["files"]:
        if entry["name"] == prompt["name"]:
            path = generator_file(state_dir, gen, entry)
            if os.path.isfile(path):
                with open(path, "r", encoding="utf-8") as handle:
                    return handle.read()
    return None


def ask_prompt(prompt: dict) -> str:
    """Ask for a prompt on the terminal. Only called when stdin is a TTY."""
    label = prompt.get("description") or prompt["name"]
    kind = prompt.get("type") or "line"
    if kind == "hidden":
        return getpass.getpass(f"{label}: ")
    sys.stderr.write(f"{label}: ")
    sys.stderr.flush()
    if kind in ("multiline", "multiline-hidden"):
        return sys.stdin.read().rstrip("\n")
    return sys.stdin.readline().rstrip("\n")


def resolve_prompts(
    state_dir: str,
    gen: dict,
    supplied: dict[str, str],
    interactive: bool = True,
) -> dict[str, str]:
    """Every prompt's value: supplied, remembered, or asked on a terminal."""
    resolved: dict[str, str] = {}
    unanswered: list[str] = []
    for prompt in gen.get("prompts") or []:
        name = prompt["name"]
        if name in supplied:
            resolved[name] = supplied[name]
            continue
        previous = read_prompt_previous(state_dir, gen, prompt)
        if previous is not None:
            resolved[name] = previous
            continue
        if interactive and sys.stdin.isatty():
            resolved[name] = ask_prompt(prompt)
            continue
        unanswered.append(name)
    if unanswered:
        raise ToolError(
            f"generator '{gen['name']}' needs a value for prompt "
            f"{', '.join(repr(n) for n in unanswered)}: pass "
            "--prompt NAME=VALUE, put the name in --prompts-dir, or run it on a "
            "terminal")
    return resolved


def run_generators(
    manifest: str | list[dict],
    state_dir: str | None,
    prompts: dict[str, str] | None = None,
    dry_run: bool = False,
) -> tuple[dict[str, str], list[str]]:
    """Run the generators that have not run yet: secret values, published paths.

    This is the declarative half of `--secret-generator`: instead of one command
    per secret name, the configuration says which script produces which files,
    and this runs it once. A generator whose files all exist *and* whose
    validation hash still matches is *read*, never re-run -- running a key
    generator on every deploy would renumber every tunnel it touches, and the
    peer that already has the old key would go on using it.

    A generator whose `validation` changed is re-run, the way clan re-runs one:
    the hash is the definition's fingerprint, and a file that exists is not
    evidence that it is still the right file.

    A generator with only some of its files present is a hard error rather than
    a re-run, for the same reason: the files it did write are the half that
    something else already depends on.

    `dry_run` reports what would be minted without minting it, and never deletes
    anything: `deploy --dry-run` must not hand out keys or destroy the ones a
    half-finished state directory still holds.
    """
    gens = load_generator_manifest(manifest) if isinstance(manifest, str) else manifest
    if not gens:
        # A manifest that declares no generators -- a router whose values are all
        # hand-offs, or a flake publishing an empty list -- has nothing to mint
        # and so needs nowhere to keep it.
        return {}, []
    if not state_dir:
        raise ToolError(
            "--generators needs --generator-state-dir: generated values have to "
            "be kept somewhere, or the next deploy mints a second key for the "
            "same tunnel")
    supplied = prompts or {}
    values: dict[str, str] = {}
    published: list[str] = []
    # What every generator so far wrote: the `$in` tree of the next one is built
    # from it, which is why the manifest has to arrive in dependency order.
    produced: dict[str, dict[str, str]] = {}
    for gen in gens:
        name = gen["name"]
        paths = generator_paths(state_dir, gen)
        declared = list(paths)
        present = [file for file in declared if os.path.isfile(paths[file])]
        complete = len(present) == len(declared)
        if complete and validation_is_valid(state_dir, gen):
            values.update(read_generated(state_dir, gen))
            published.extend(
                paths[entry["name"]] for entry in gen["files"]
                if not entry.get("secret", True) and entry.get("deploy", True)
            )
            produced[name] = paths
            continue
        if present and not complete:
            missing = sorted(set(declared) - set(present))
            # The whole set goes, not the missing half: a generator's files are
            # one value in several spellings (a private key and its public key),
            # so keeping the survivors would keep peers pointed at a key whose
            # private half is about to be replaced.
            if not dry_run:
                for directory in {os.path.dirname(path) for path in paths.values()}:
                    shutil.rmtree(directory, ignore_errors=True)
            raise ToolError(
                f"generator '{name}' is half-generated under {state_dir} (missing: "
                f"{', '.join(missing)}); its remaining files were removed so the "
                "next run starts a complete set -- the peers using the old ones "
                "need the new public key")
        if dry_run:
            # Report the names that a real run would mint, and nothing else: a
            # dry run that ran the generator would be a dry run with a side
            # effect, which is the one thing it must not have.
            for entry in gen["files"]:
                if entry.get("secret", True) and entry.get("deploy", True):
                    values[f"{name}/{entry['name']}"] = ""
            produced[name] = paths
            continue
        unknown = [d for d in gen.get("dependencies") or [] if d not in produced]
        if unknown:
            raise ToolError(
                f"generator '{name}' depends on {', '.join(unknown)}, which this "
                "manifest does not declare before it")
        inputs = {d: produced[d] for d in gen.get("dependencies") or []}
        resolved = resolve_prompts(state_dir, gen, supplied)
        fresh, fresh_published = run_generator(state_dir, gen, prompts=resolved, inputs=inputs)
        write_validation(state_dir, gen)
        values.update(fresh)
        published.extend(fresh_published)
        produced[name] = paths
    return values, published


def run_generator(
    state_dir: str,
    gen: dict,
    prompts: dict[str, str] | None = None,
    inputs: dict[str, dict[str, str]] | None = None,
) -> tuple[dict[str, str], list[str]]:
    """Run one generator's script and keep what it wrote under `$out`."""
    name = gen["name"]
    workdir = tempfile.mkdtemp(prefix=f"nix-mikrotik-{name}-")
    try:
        out = os.path.join(workdir, "out")
        os.makedirs(out, mode=0o700)
        env = dict(os.environ)
        env["out"] = out

        # `$in/<generator>/<file>` is how one generator reads another's output
        # (clan's own contract). The tree is a copy inside the work directory, so
        # a script cannot write back into the state directory through it.
        indir = os.path.join(workdir, "in")
        os.makedirs(indir, mode=0o700)
        env["in"] = indir
        for dep, files in (inputs or {}).items():
            depdir = os.path.join(indir, dep)
            os.makedirs(depdir, mode=0o700)
            for filename, source in files.items():
                if not os.path.isfile(source):
                    raise ToolError(
                        f"generator '{name}' depends on {dep}/{filename}, which is "
                        "not in the state directory")
                destination = os.path.join(depdir, filename)
                shutil.copyfile(source, destination)
                os.chmod(destination, 0o400)

        # `$prompts/<name>` is a file per prompt, not an environment variable:
        # a value may contain a newline or a quote, and both belong in a file.
        if gen.get("prompts"):
            promptsdir = os.path.join(workdir, "prompts")
            os.makedirs(promptsdir, mode=0o700)
            env["prompts"] = promptsdir
            given = prompts or {}
            for prompt in gen["prompts"]:
                path = os.path.join(promptsdir, prompt["name"])
                fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o400)
                with os.fdopen(fd, "w", encoding="utf-8") as handle:
                    handle.write(given[prompt["name"]])

        # The tool's own PATH is not the generator's: `runtimeInputs` is what the
        # configuration says the script needs, and it comes first so a package
        # named there wins over whatever the deploying host happens to have.
        runtime_inputs = gen.get("runtimeInputs") or []
        if runtime_inputs:
            env["PATH"] = ":".join(os.path.join(p, "bin") for p in runtime_inputs) + ":" + env.get("PATH", "")
        proc = subprocess.run(
            ["bash", "-euo", "pipefail", "-c", gen["script"]],
            capture_output=True, text=True, env=env)
        if proc.returncode != 0:
            detail = (proc.stderr or proc.stdout).strip().splitlines()
            raise ToolError(
                f"generator '{name}' failed (exit {proc.returncode})"
                + ("\n" + detail[0] if detail else ""))
        missing = [
            entry["name"] for entry in gen["files"]
            if not os.path.isfile(os.path.join(out, entry["name"]))
        ]
        if missing:
            raise ToolError(
                f"generator '{name}' declares {', '.join(missing)} but its script "
                f"did not write {'them' if len(missing) > 1 else 'it'} under $out")
        values: dict[str, str] = {}
        published: list[str] = []
        for entry in gen["files"]:
            secret = entry.get("secret", True)
            deploy = entry.get("deploy", True)
            destination = generator_file(state_dir, gen, entry)
            os.makedirs(os.path.dirname(destination), mode=0o700, exist_ok=True)
            # A re-run replaces files that are 0400/0444 -- copyfile would fail
            # to open one for writing, and a generated file is replaced, never
            # edited in place.
            if os.path.lexists(destination):
                os.remove(destination)
            shutil.copyfile(os.path.join(out, entry["name"]), destination)
            if secret:
                # A generated secret is as sensitive as one read from a clan
                # var. Its mode comes from the manifest (default 0400), because
                # a generator that has to hand a key to a service on the
                # deploying machine is a real case clan supports.
                os.chmod(destination, int(str(entry.get("mode") or "0400"), 8))
                if deploy:
                    with open(destination, "r", encoding="utf-8") as handle:
                        values[f"{name}/{entry['name']}"] = handle.read().strip()
            elif deploy:
                # Published: another machine has to read it. Never writable, so
                # a peer cannot be handed a copy that later disagrees with the
                # generator's own.
                os.chmod(destination, 0o444)
                published.append(destination)
            else:
                # An intermediate: another generator reads it, nothing else.
                os.chmod(destination, 0o400)
        return values, published
    finally:
        shutil.rmtree(workdir, ignore_errors=True)


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
                 timeout: int = 20, command_timeout: int = 120) -> None:
        self.host = host
        self.user = user
        self.port = port
        self.key = key
        self.known_hosts = check_known_hosts(known_hosts) if known_hosts else None
        self.timeout = timeout
        # A device that answers the TCP connection and then stops talking -- a
        # wedged sshd, a script that blocks the console, a reboot in the middle
        # of an import -- otherwise holds the caller open forever. A deploy that
        # is a systemd unit has no terminal to interrupt it with, so the only
        # way out is a timeout of our own; `ConnectTimeout` does not cover it
        # because the connection is already established.
        self.command_timeout = command_timeout

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

    def run(self, command: str, timeout: int | None = None) -> str:
        argv = ["ssh", *self._common(), "-p", str(self.port),
                f"{self.user}@{self.host}", command]
        try:
            proc = subprocess.run(argv, capture_output=True, text=True,
                                  timeout=timeout or self.command_timeout)
        except subprocess.TimeoutExpired:
            raise ToolError(
                f"the device did not answer within "
                f"{timeout or self.command_timeout}s: {command}\n"
                "the connection is open, so this is the device not finishing the "
                "command (a script that blocks, a reboot, a wedged sshd), not a "
                "refused connection -- check it on the console before re-running") from None
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
        try:
            proc = subprocess.run(argv, capture_output=True, text=True,
                                  timeout=max(self.command_timeout, 300))
        except subprocess.TimeoutExpired:
            raise ToolError(
                f"scp of {local} did not finish within "
                f"{max(self.command_timeout, 300)}s -- the device's storage may be "
                "full, or its sshd has stopped reading") from None
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
    sops_file: str | None = None,
    sops_key_file: str | None = None,
    secret_generator: str | None = None,
    generator_state_dir: str | None = None,
    generators: str | None = None,
    prompts: dict[str, str] | None = None,
    dry_run: bool = False,
) -> tuple[str, list[str]]:
    with open(script, "r", encoding="utf-8") as handle:
        text = handle.read()
    names = find_placeholders(text)
    values: dict[str, str] = {}
    # Read before anything else: the manifest says where a hand-off value sits
    # under --secrets-dir, and reading the directory without it would only find
    # the values whose placeholder happens to be the file name.
    generator_list, var_files = load_manifest(generators) if generators else ([], {})
    if secrets_dir:
        values.update(read_secret_files(secrets_dir, names, var_files))
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
    if missing and sops_file:
        values.update(read_sops_secrets(sops_file, missing, sops_key_file))
        missing = []
    if missing and generators:
        # Before the per-name generator: the manifest says which script mints
        # which files, so it is the one that can mint a value *and* the public
        # key that has to be handed to the peer.
        values.update(run_generators(
            generator_list, generator_state_dir,
            prompts=prompts, dry_run=dry_run)[0])
        missing = [n for n in names if n not in values]
    if missing and secret_generator:
        values.update(generate_secrets(secret_generator, missing, generator_state_dir))
        missing = []
    if missing and secret_command:
        # Only what is still unresolved: an explicit --secret or a file in
        # --secrets-dir wins over asking the command.
        values.update(read_secret_command(secret_command, missing))
        missing = []
    if missing:
        lines = ["unresolved secret placeholders: " + ", ".join(missing)]
        for name in missing:
            if name in var_files:
                where = os.path.join(secrets_dir, var_files[name]) if secrets_dir else var_files[name]
                lines.append(
                    f"  '{name}' is declared under mikrotik.varFiles: it is minted "
                    f"elsewhere, so it has to be found at {where}")
        if not all(name in var_files for name in missing):
            lines.append(
                "pass them with --secret NAME=PATH, --secrets-dir, --sops-file, "
                "--generators, --secret-generator or --secret-command")
        raise ToolError("\n".join(lines))
    return substitute(text, values), names


def prompt_values(args: argparse.Namespace) -> dict[str, str]:
    """Prompt values from the command line: a directory of files, then `--prompt`.

    A directory is the shape a deploy unit can be handed (one file per prompt,
    named after it), and `--prompt` is what a person types. The flag wins over
    the directory, so an operator can override one value without rewriting it.
    """
    values: dict[str, str] = {}
    directory = getattr(args, "prompts_dir", None)
    if directory:
        if not os.path.isdir(directory):
            raise ToolError(f"--prompts-dir: {directory} is not a directory")
        for entry in sorted(os.listdir(directory)):
            path = os.path.join(directory, entry)
            if not os.path.isfile(path):
                continue
            check_secret_name(entry)
            with open(path, "r", encoding="utf-8") as handle:
                values[entry] = handle.read().rstrip("\n")
    for item in getattr(args, "prompt", None) or []:
        name, sep, value = item.partition("=")
        if not sep or not name:
            raise ToolError(f"--prompt wants NAME=VALUE, got {item!r}")
        check_secret_name(name)
        values[name] = value
    return values


def cmd_generate(args: argparse.Namespace) -> int:
    values: dict[str, str] = {}
    published: list[str] = []
    prompts = prompt_values(args)
    # One manifest per router, and a router's values are keyed
    # `<generator>/<file>` -- so two routers that each declare `wg/privkey` are
    # two state-directory paths but one key here. Generating them in one call is
    # therefore fine (the values are written, not substituted); a deploy still
    # takes its own router's manifest alone.
    for manifest in args.manifests:
        fresh, fresh_published = run_generators(manifest, args.state_dir, prompts=prompts)
        values.update(fresh)
        published.extend(fresh_published)
    for name in sorted(values):
        print(name)
    for path in published:
        # Printed so the caller can hand the public half over (or commit it)
        # without having to know where a state directory keeps it.
        print(f"published {path}")
    if not values and not published:
        print("(the generators had nothing to produce)", file=sys.stderr)
    return 0


def cmd_secretize(args: argparse.Namespace) -> int:
    text, names = _secretize(args.script, args.secret, args.secrets_dir, args.secret_command, args.sops_file, args.sops_key_file, args.secret_generator, args.generator_state_dir, args.generators, prompt_values(args))
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


# --------------------------------------------------------------------------
# the differ
# --------------------------------------------------------------------------

def rsc_binary() -> str:
    """The `rsc` differ this tool drives.

    It ships beside `nix-mikrotik` in the same package (the flake wraps both into
    one PATH), so the plain name is the normal case. `NIX_MIKROTIK_RSC` is for
    the test harness, which runs the tool from a worktree against a binary it
    just built rather than through the wrapper.
    """
    return os.environ.get("NIX_MIKROTIK_RSC") or "rsc"


def run_rsc(argv: list[str], what: str) -> str:
    """Run the differ, and turn its failures into this tool's own.

    Exit 2 is a parse error on one of the two files: the device's `/export` is
    the one that surprises a parser (a script block, a menu the model does not
    know), and it is the file the operator cannot edit -- so the message names
    the escape hatch instead of leaving a Rust diagnostic to read.
    """
    try:
        proc = subprocess.run([rsc_binary(), *argv], capture_output=True, text=True)
    except FileNotFoundError:
        raise ToolError(
            f"`{rsc_binary()}` is not on PATH: it is the differ this deploy "
            "computes its patch with, and it ships with nix-mikrotik -- run the "
            "packaged tool rather than the script") from None
    if proc.returncode == 2:
        raise ToolError(
            f"rsc could not parse a file while computing {what}:\n"
            f"{proc.stderr.strip()}\n"
            "if it is the device's /export, pass --import-whole: importing the "
            "script is the path that does not read the device's configuration")
    if proc.returncode != 0:
        raise ToolError(f"rsc {argv[0]} failed ({proc.returncode}):\n{proc.stderr.strip()}")
    return proc.stdout


def patch_commands(text: str) -> list[str]:
    """The lines of a patch a device would actually run.

    A patch is mostly comments -- the header, the notes, and every operation
    that was withheld -- and a file with none of them left is a deploy with
    nothing to do. Counting them is also what keeps an empty patch off the
    device: uploading and importing it would only prove the sentinel works.
    """
    commands = []
    for line in text.splitlines():
        stripped = line.strip()
        if not stripped or stripped.startswith("#") or stripped.startswith("/"):
            continue
        if stripped.startswith(":"):
            # `:log info "<sentinel>"` is a command, but it is this tool's own
            # proof-of-run, not a change: a patch made only of one is empty.
            continue
        commands.append(stripped)
    return commands


def render_patch(router: "Router", text: str, workdir: str, prune: bool,
                 marker: str) -> tuple[str, str]:
    """Diff the device against `text` and return (patch, report).

    The device is the source of "what is there now": a fresh `/export`, which is
    the only statement about the device that does not go through this tool's own
    record of what it thinks it deployed. The script is the target. The differ
    turns the two into the console commands in between, and the sentinel it
    appends is the same proof-of-run the whole-script path uses -- RouterOS
    exits 0 for an import it refused, so the log line is the only positive
    evidence that the patch ran to the end.

    `prune` decides what happens to the operations that delete. Without it the
    patch is an *upsert*: adds and sets only. That is not caution for its own
    sake -- an `/export` carries the device's whole configuration, so "not in
    the target" includes the address this deploy is talking to the device over,
    the ethernet interfaces, and anything somebody added by hand. Deleting those
    is what "exact" means, and it is not this tool's decision to make.
    """
    live_path = os.path.join(workdir, "live.rsc")
    target_path = os.path.join(workdir, "target.rsc")
    for path, content in ((live_path, router.export()), (target_path, text)):
        fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            handle.write(content)

    mode = [] if prune else ["--upsert"]
    report = run_rsc(["diff", live_path, target_path, *mode], "the difference")
    patch = run_rsc(["patch", live_path, target_path, *mode, "--sentinel", marker],
                    "the patch")
    return patch, report


def patch_summary(report: str) -> str:
    """The one line of `rsc diff`'s report that says how much work there is."""
    for line in report.splitlines():
        if "operations:" in line:
            return line.strip()
    return "the differ reported no operations"


def unapplied(report: str) -> list[str]:
    """What the plan says it cannot apply, in the differ's own words.

    `rsc` marks a section it could not express with `UNAPPLIED:` rather than
    leaving a note among the others: a deploy that reports success while part of
    the target was never applied is the one failure an operator cannot see, so
    the line is greppable and this tool refuses on it by default.

    Three shapes reach here, all measured: a target line the differ cannot model
    (a block script, `extraScript`), a menu with no stable handle that would have
    to be rebuilt (which is a removal), and an object whose re-creation needs a
    property to disappear (RouterOS has no unset).
    """
    marker = "UNAPPLIED:"
    found = []
    for line in report.splitlines():
        if marker in line:
            found.append(line.split(marker, 1)[1].strip())
    return found


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

    router = Router(args.host, args.user, args.port, args.key, args.known_hosts,
                    command_timeout=args.command_timeout)
    text, names = _secretize(args.script, args.secret, args.secrets_dir, args.secret_command, args.sops_file, args.sops_key_file, args.secret_generator, args.generator_state_dir, args.generators, prompt_values(args), args.dry_run)

    # An empty script is not a request to empty the device. A render that
    # produced nothing is a broken configuration -- a module that evaluated to
    # no sections, a flake output that changed shape -- and deploying it would
    # either do nothing (with deletions withheld, which reads as success) or, on
    # a device this tool owns, delete everything. Refuse, and say which.
    if not [line for line in text.splitlines()
            if line.strip() and not line.strip().startswith("#")]:
        raise ToolError(
            "the script contains no commands: an empty render is a broken "
            "configuration, not a request to empty the device. Check what "
            "produced it before deploying")

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
        # Which script the device is given is the whole of this change. By
        # default it is the *difference* between the device's own /export and
        # the target, computed here and applied as a patch; `--import-whole`
        # keeps the old path, which re-imports every line and is only correct on
        # a device that is empty or already in that exact state.
        whole = args.reset or args.import_whole
        if whole:
            body = text
            summary = f"{len(text)} bytes, imported whole"
        else:
            patch, report = render_patch(router, text, workdir, args.prune, marker)
            if args.check:
                print(report, end="" if report.endswith("\n") else "\n")
                print("check: nothing was sent to the device", file=sys.stderr)
                return 1 if patch_commands(patch) else 0
            gaps = unapplied(report)
            if gaps and not args.allow_partial:
                raise ToolError(
                    "the plan cannot reach this configuration, and applying it "
                    "anyway would report success for a device that is only "
                    "partly configured:\n  "
                    + "\n  ".join(gaps)
                    + "\npass --allow-partial to apply what the differ can express "
                      "and leave the rest as it is, or --prune where a deletion is "
                      "what is missing, or --import-whole for lines the differ "
                      "cannot model")
            if gaps:
                print("warning: applying a partial configuration; the differ cannot "
                      "express:", file=sys.stderr)
                for gap in gaps:
                    print(f"  {gap}", file=sys.stderr)
            commands = patch_commands(patch)
            if not commands:
                print("no changes: the device already holds this configuration",
                      file=sys.stderr)
                print(report, end="" if report.endswith("\n") else "\n",
                      file=sys.stderr)
                if args.verify:
                    _verify_identity(router, args)
                return 0
            body = patch
            summary = patch_summary(report)
            print(f"{summary}", file=sys.stderr)
            if not args.prune:
                print("removals are withheld (upsert): pass --prune to apply "
                      "the operations that delete", file=sys.stderr)

        if args.check:
            # Only the diff path can check without sending anything; the
            # whole-script path has no plan to show.
            raise ToolError("--check needs the diff path: do not combine it with "
                            "--import-whole or --reset")

        staged = os.path.join(workdir, DEFAULT_SCRIPT_NAME)
        fd = os.open(staged, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            # The differ already appended the sentinel to a patch; the
            # whole-script path has to add its own.
            handle.write(body if whole is False else body + sentinel_line(marker))

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
        _verify_identity(router, args)
    return 0


def _verify_identity(router: Router, args: argparse.Namespace) -> None:
    identity = router.identity()
    if identity is None:
        raise ToolError("could not read /system identity after deploy")
    if args.expect_hostname and identity != args.expect_hostname:
        raise ToolError(
            f"identity is '{identity}', expected '{args.expect_hostname}'")
    print(f"verified: identity is '{identity}'")


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

    router = Router(args.host, args.user, args.port, args.key, args.known_hosts,
                    command_timeout=args.command_timeout)
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

def add_prompt_arguments(parser: argparse.ArgumentParser) -> None:
    """The two ways a prompt's value gets in without a terminal.

    `--prompt` is what a person types; `--prompts-dir` is the shape a deploy
    unit can be handed (one file per prompt, named after it, so the value never
    appears in a process list). With neither, a run that still needs an answer
    asks on the terminal -- and a run that is not on a terminal fails, rather
    than writing an empty value into a key.
    """
    parser.add_argument("--prompt", action="append", default=[], metavar="NAME=VALUE",
                        help="answer a generator prompt (repeatable)")
    parser.add_argument("--prompts-dir", metavar="DIR",
                        help="directory of files named after prompts, one value each")
    return None


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

    p = sub.add_parser("generate", help="run a configuration's secret generators")
    p.add_argument("manifests", nargs="+", metavar="MANIFEST",
                   help="generator manifest JSON (a flake's mikrotik-<name>-generators); "
                        "one per router, so `nix-mikrotik generate $(nix build "
                        "--print-out-paths .#mikrotik-*-generators)` generates the vars "
                        "of every router in a routers/ directory")
    p.add_argument("--state-dir", required=True, metavar="DIR",
                   help="where generated values are kept, in clan's layout: each "
                        "file goes to the relDir the manifest gives it "
                        "(per-machine/<router>/<generator>/, shared/<generator>/), "
                        "at the mode the manifest declares (0400 for a secret, "
                        "0444 for a published value)")
    add_prompt_arguments(p)
    p.set_defaults(func=cmd_generate)

    p = sub.add_parser("secretize", help="substitute secret values into a copy")
    p.add_argument("script")
    p.add_argument("-o", "--output", required=True)
    p.add_argument("--secret", action="append", default=[], metavar="NAME=PATH")
    p.add_argument("--secrets-dir", help="directory of files named after secrets")
    p.add_argument("--secret-generator", metavar="CMD",
                   help="mint a value per missing secret ({name} substituted) -- "
                        "run the generator, rather than read it")
    p.add_argument("--generator-state-dir", metavar="DIR",
                   help="where minted values are kept (0600), so the next deploy "
                        "reads the key instead of minting a second one")
    p.add_argument("--sops-file", metavar="PATH",
                   help="decrypt the secrets out of this sops file, with the host's "
                        "own sops key -- nothing has to be staged on the deploying machine")
    p.add_argument("--sops-key-file", metavar="PATH",
                   help="sops key to decrypt with (sets SOPS_AGE_KEY_FILE); default: "
                        "sops' own discovery")
    p.add_argument("--generators", metavar="PATH",
                   help="generator manifest JSON (a flake's mikrotik-<name>-generators): "
                        "run the generators that have not run yet, then substitute "
                        "their files; values declared under varFiles are read from "
                        "--secrets-dir instead")
    p.add_argument("--secret-command", metavar="CMD",
                   help="run CMD per unresolved secret ({name} substituted), "
                        "using its stdout instead of reading files")
    add_prompt_arguments(p)
    p.set_defaults(func=cmd_secretize)

    p = sub.add_parser("deploy", help="secretize, diff, import and verify")
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
    p.add_argument("--secret-generator", metavar="CMD",
                   help="mint a value per missing secret ({name} substituted) -- "
                        "run the generator, rather than read it")
    p.add_argument("--generator-state-dir", metavar="DIR",
                   help="where minted values are kept (0600), so the next deploy "
                        "reads the key instead of minting a second one")
    p.add_argument("--sops-file", metavar="PATH",
                   help="decrypt the secrets out of this sops file, with the host's "
                        "own sops key -- nothing has to be staged on the deploying machine")
    p.add_argument("--sops-key-file", metavar="PATH",
                   help="sops key to decrypt with (sets SOPS_AGE_KEY_FILE); default: "
                        "sops' own discovery")
    p.add_argument("--generators", metavar="PATH",
                   help="generator manifest JSON (a flake's mikrotik-<name>-generators): "
                        "run the generators that have not run yet, then substitute "
                        "their files; values declared under varFiles are read from "
                        "--secrets-dir instead")
    p.add_argument("--secret-command", metavar="CMD",
                   help="run CMD per unresolved secret ({name} substituted), "
                        "using its stdout instead of reading files")
    p.add_argument("--reset", action="store_true",
                   help="reset-configuration with the script (destructive)")
    p.add_argument("--yes", action="store_true", help="confirm --reset")
    p.add_argument("--prune", action="store_true",
                   help="apply the operations that delete as well: the patch "
                        "then takes the device to exactly the script, including "
                        "removing what the script does not declare (the "
                        "management address and the ethernet interfaces are "
                        "declared by /export and not by most scripts)")
    p.add_argument("--import-whole", action="store_true",
                   help="import the whole script instead of its difference: the "
                        "path for a device whose /export the differ cannot read, "
                        "and the one that is not idempotent")
    p.add_argument("--check", action="store_true",
                   help="print the difference and exit (1 if there is one, 0 if "
                        "the device already holds the configuration); nothing is "
                        "uploaded -- the first run against a live router")
    p.add_argument("--allow-partial", action="store_true",
                   help="apply the part of the target the differ can express even "
                        "though the rest cannot be reached (a menu with no stable "
                        "handle, a property RouterOS cannot unset, a line it cannot "
                        "model); without it such a plan is refused, because the "
                        "deploy would report success for a partly-configured device")
    p.add_argument("--command-timeout", type=int, default=120, metavar="SECONDS",
                   help="how long one command may run before the device is called "
                        "wedged (default: 120); an export of a large configuration "
                        "is the command that needs more")
    p.add_argument("--wait", type=int, default=180,
                   help="seconds to wait for a reset device (default: 180)")
    p.add_argument("--verify", action="store_true",
                   help="read the identity back after deploying")
    p.add_argument("--expect-hostname", help="fail if the identity differs")
    p.add_argument("--dry-run", action="store_true")
    add_prompt_arguments(p)
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
    p.add_argument("--command-timeout", type=int, default=120, metavar="SECONDS",
                   help="how long one command may run before the device is called "
                        "wedged (default: 120)")
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
