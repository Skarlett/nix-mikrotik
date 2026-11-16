# Testing against a real RouterOS

Building a script proves nothing about whether RouterOS accepts it: `/import`
exits 0 for a script the device refused to parse. These are the lab and the
checks that ask a device instead.

`chr/` pins the patched CHR images from
[elseif/MikroTikPatch](https://github.com/elseif/MikroTikPatch) and provides a
two-VM lab:

```sh
nix run .#chr-lab -- start     # two CHRs, wired to each other
nix run .#chr-lab -- status    # pids and management ports
nix run .#chr-lab -- stop
```

`chr-a` is reachable at `127.0.0.1:2201` (ssh) and `127.0.0.1:8081` (REST),
`chr-b` at `2202`/`8082`. Their link is QEMU's tcp socket backend, not a tap:
no root, and ~1.5-2 Gbit/s between the two, where UDP (`dgram`) collapses to
~50-130 Mbit/s.

Two things about CHR that cost time if you do not know them:

* a fresh CHR is licensed `free`, which caps throughput at **1 Mbit/s**;
* the patched images need `keygen` (in the `option` package) run on the device,
  **and then a reboot** — `/system license print` reports the new licence
  immediately, but the packet path keeps the old cap until the device restarts.

`checks.chr-smoke` boots the pinned image and waits for the RouterOS login
prompt, so a broken image pin fails the build rather than a lab session.

`checks.menus` is the one that guards the two spellings: it renders one
configuration written both ways, a typed/section hybrid (to pin the merge order),
and every menu in the table, and requires the typed render to be byte-identical
to the section render.

`checks.chr-deploy` goes further: it boots that image, applies a rendered
configuration to the device, and reads the device's state back. It is the only
check that can answer whether RouterOS *accepts* what the renderer produced —
`/import` exits 0 for a script the device refused to parse, so nothing about the
build itself can. What it asserts, all read over REST afterwards:

* the identity, a bridge with an address on it, and a dhcp-server drawing from a
  pool created earlier in the same script (section order is real);
* a firewall comment carrying `$`, and a *secret* substituted into a dns
  comment, both read back byte for byte;
* the interface whose line carries the substituted WireGuard key — it exists at
  all only if the whole script ran, because unquoted that base64 `=` padding
  makes the device refuse the script from its first line;
* the uploaded copy is gone from the device afterwards;
* and, the other way round, that a deliberately broken script **fails** the
  deploy, with the device's own `script error: expected end of command` in the
  log and nothing applied. A check whose subject always applies cannot be shown
  to fail, so the refusal is part of the check rather than a claim about it.

`tests/chr-deploy.py` is the whole of it and needs nothing from nix, so it also
runs against a CHR from the lab above — which is how its assertions were written:

```sh
nix run .#chr-lab -- start
script=$(nix build --no-link --print-out-paths .#mikrotik-chr-fixture-script)
generators=$(nix build --no-link --print-out-paths .#mikrotik-chr-fixture-generators)
cli=$(nix build --no-link --print-out-paths .#nix-mikrotik)
tests/chr-deploy.py --host 127.0.0.1 --ssh-port 2201 --rest-port 8081 \
  --script "$script/router-config.rsc" --expect-hostname chr-deploy \
  --generators "$generators" --generator-state-dir ./vars \
  --broken-script tests/fixtures/refused.rsc --cli "$cli/bin/nix-mikrotik"
```

It bootstraps its own ssh access rather than needing a console: it serves a
fresh public key to the guest at `http://10.0.2.2:<port>/` and has the device
import it over REST (`POST /tool/fetch`, then `POST /user/ssh-keys/import`), then
removes it again. `--generators` makes the check mint the fixture's key with the
generator that declares it, so the public key the device ends up with is an
assertion and not a restatement; `--secret NAME=VALUE` remains for a device whose
values you do have to invent.

`--config` points the same harness at *any* configuration: it then asserts only
what holds for every script — the device accepts it, the identity it sets, and no
`script error:` in the device's log — and reports the fixture's own menus as
skipped. That is how the examples are run against a router (see
[Not done yet](roadmap.md)).

Two lab notes this leaves behind: a CHR rebuilt at a host:port you have already
deployed to comes back with a **new ssh host key**, and the deploy tool's
`accept-new` then refuses it (OpenSSH reads `known_hosts` from the password
database, not from `$HOME`, so nothing redirects it) — clear it with
`ssh-keygen -R '[127.0.0.1]:2201'`, or use a port you have not deployed to.
Inside the nixos test that cannot arise. And RouterOS logs `script,error
executing script from sshd failed` for *any* command a client runs over ssh that
exits non-zero — including the deploy's own `/file remove`, which is retried
because it races the import — so that line is not evidence about a script; the
device's `script error: …` line is.
