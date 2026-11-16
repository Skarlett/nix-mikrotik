# Secrets

RouterOS cannot activate a secret the way a NixOS host does, so a value is
generated on the deploying machine and **delivered**. A menu cell holds a
reference that renders to a placeholder; the value never enters the store.

RouterOS cannot run sops-nix, so a secret cannot be *activated* onto a router
the way it is onto a NixOS host. It is **generated** on the deploying machine and
**delivered**:

1. the configuration declares a generator under `clan.core.vars.generators.<name>`
   — clan's own interface, not a spelling of it. A generator is a shell script
   plus the files it declares, and each file says whether it is a secret;
2. a menu cell takes `config.clan.core.vars.generators.<g>.files.<f>.placeholder`,
   which renders as `__MIKROTIK_SECRET_<g>/<f>__` — the value is never in the
   store, and the script is safe to build on any machine;
3. `nix-mikrotik generate <manifest>` runs the generators that script needs, once
   each, in dependency order, and keeps the values in a state directory laid out
   the way clan lays out its var store (`per-machine/<router>/<generator>/<file>`,
   or `shared/<generator>/<file>` for a `share = true` generator), because the
   manifest carries that `relDir` per file and the tool writes nowhere else. A
   file is written `0400`; a file declared `secret = false` is written `0444` and
   printed, because it is not a secret (a public key) and another machine has to
   read it;
4. `nix-mikrotik deploy` substitutes the real value into the script, quoting and
   escaping it the way RouterOS needs it, into a `0600` file under a `0700`
   temporary directory, uploads, imports, and **removes the uploaded copy from
   the router**, because that file holds the plaintext;
5. it refuses to deploy at all if any placeholder is unresolved — and it refuses
   a placeholder *name* whose parts are not usable as file names
   (`[A-Za-z0-9][A-Za-z0-9._-]*`, one `/` between generator and file), because
   that name is also the path the value is read from;
6. an unquoted base64 key — every WireGuard private key — makes the device end
   the command early, abort the whole script and still exit 0, which is why
   (4) quotes and escapes `"`, `\` and `$` rather than trusting the value;
7. a script the device did not finish running is a **failure, not a silent
   no-op**: `deploy` appends a one-line sentinel to the uploaded copy and reads
   the device's log back, so it cannot print `verified` for an import that
   stopped early. What stopped it is not recoverable — a parse abort applies
   nothing, a runtime abort has already applied a prefix — so the failure says
   exactly that rather than claiming the device is unchanged, and warns that a
   re-run can duplicate what the first attempt managed to apply.

```nix
clan.core.vars.generators.wg-chr1 = {
  files.private-key.secret = true;
  files.public-key.secret = false;        # published: the peers need it
  runtimeInputs = [ pkgs.wireguard-tools ];
  script = ''
    wg genkey | tee $out/private-key | wg pubkey > $out/public-key
  '';
};
```

The interface is clan's, with three deviations, each because the target is
RouterOS rather than a NixOS machine (`modules/base.nix` says so where the
options are declared):

* **no var store is read while evaluating.** `path`, `value` and `exists` throw
  with an explanation instead of resolving to a file: a router script is rendered
  on a machine that does not hold the values. Use `placeholder`.
* **`owner`, `group`, `neededFor` and `restartUnits` are accepted and ignored.**
  RouterOS has no users, no systemd and no activation step to restart.
* **`finalScript` is text, not a store path**, so a class can be evaluated
  without building anything.

Everything else is the real thing: `files`, `prompts` (a persisted prompt *is* a
file of the generator, so such a generator writes no script), `dependencies`
(`$in/<generator>/<file>`), `share`, `validation`, `runtimeInputs`. The
configuration asserts what it can: a generator with no files, a dependency on a
generator this router does not declare, a dependency cycle, and a placeholder no
declaration produces all fail the evaluation with a message that names the fix.

```sh
nix eval --impure --raw .#mikrotikConfigurations.r1.manifest \
  | jq . > manifest.json            # or: nix build .#...-generators

nix-mikrotik generate manifest.json --state-dir ./vars
nix-mikrotik deploy router.rsc --host 10.0.0.1 \
  --generators manifest.json --generator-state-dir ./vars \
  --verify --expect-hostname router1
```

The document is `{ generators }`: what the tool can mint, and where each file
goes. `generate` runs them, `deploy` reads what a previous run wrote.

`--state-dir` is outside the repository on purpose: the values are the one thing
that must not be committed, and the layout is clan's so that the same directory
can be the one clan deploys into.
