#!/usr/bin/env python3
"""Ask a real RouterOS which menu arguments take a list, and dump the answers.

Why this exists: `/console/inspect` reports a menu's argument *names* and
nothing about their values. This fork's typed menu options want to write a
multi-value argument as a Nix list (`interfaces = [ "ether1" "ether2" ]`)
instead of the comma-joined string RouterOS itself prints, so the library has
to know which arguments are multi-value -- and the only place that knows is the
device.

How the device is asked. Three probes, cheapest first, each of which can only
fail towards "unknown", never towards a wrong "list":

 1. `:typeof` of the property. A list-valued property is `array`; a string is
    `str`, a number `num`, a boolean `bool`, an unset property `nil`. This
    settles every property that has a value or a default -- `/ip dns servers`
    and `/ip vrf interfaces` are `array` even when they are empty.

 2. The garbage test. An unset property says nothing, so set it to a value no
    typed property can accept (`nix-mikrotik-probe`). A property that *accepts*
    it takes a free string: `/ip firewall filter comment=a,b` is one string,
    not two values, and is never a list. A property that refuses it is typed,
    which is what probe 3 needs to know.

 3. A pair of typed values. A typed property accepts the comma form only when it
    is multi-value: `connection-state=established,related` applies,
    `frame-types=admit-all,admit-only-untagged-and-priority-tagged` is refused.
    This is the probe that catches the flag-set properties, which read back as
    `str` and would otherwise look scalar.

Three details of the device that shape the code:

* **A comma in a value must be quoted, or RouterOS refuses the whole line with
  `syntax error`** -- and a parse error is not caught by `:do {…} on-error={…}`,
  because the block never runs. An unquoted pair therefore makes every list
  probe fail in a way that looks exactly like "not a list". Hence `q()` and the
  `END` sentinel: a probe whose sentinel never arrives is `?`, not `no`.

* **A flag set reads back as `str`.** `typeof` alone would call
  `connection-state` a string, so a `str` result still goes through probe 3.

* **Probes 2 and 3 write to the device.** They run only against an object this
  script created and removes afterwards, never against the router's live
  configuration: a lab device is disposable, a fleet router is not.

A property that refuses garbage and refuses every candidate pair stays
`unknown`. This file reports what the device proved; `lib/menus.overlay.nix`
carries the rest with a reason, like everything else a virtual router cannot be
asked.

    scripts/probe-menu-lists.py menus.json -o lists-<version>.json
    scripts/probe-menu-lists.py menus.json --only "/ip firewall filter" -v

`menus.json` is either the walk's `tree-<version>.json` or the table as JSON:
`nix eval --impure --json --expr '(import ./lib/menus.nix)'`.

Transport is ssh with one ControlMaster connection for the whole run: a fresh
ssh connection per probe draws "Connection timed out during banner exchange" on
this device, while a reused one is both faster and quieter.
"""
import argparse
import json
import os
import re
import subprocess
import sys
import tempfile
import time

# Values a typed property can be set to, in the order they are tried: a pair, and
# the same pair plus a third. The pair proves the property takes *a* comma; the
# triple proves the comma separates independent values rather than belonging to
# one value's syntax. Both halves are needed:
#
#   `/ip firewall filter connection-state=established,related`   a list
#   `/ip firewall filter connection-limit=10,5`                  one value: a
#                                                                count and a time
#
# `connection-limit` and `limit` take the pair and refuse the triple, which is
# exactly the fixed-arity syntax a pair alone would have mis-reported as a list.
# The interface family has no third name on a lab CHR (it has only `ether1` and
# `lo`), so it is proven by the pair alone.
PAIRS = [
    ("ip", "1.1.1.1,1.1.1.2", "1.1.1.1,1.1.1.2,1.1.1.3"),
    ("prefix", "10.10.10.1/32,10.10.10.2/32", "10.10.10.1/32,10.10.10.2/32,10.10.10.3/32"),
    ("interface", "ether1,lo", None),
    ("mac", "00:11:22:33:44:55,00:11:22:33:44:66",
     "00:11:22:33:44:55,00:11:22:33:44:66,00:11:22:33:44:77"),
    ("number", "1,2", "1,2,3"),
    ("time", "1s,2s", "1s,2s,3s"),
]

GARBAGE = "nix-mikrotik-probe"

# A property cannot be created with `name=` alone in every menu, and a menu with
# no object at all cannot be read. These are the minimal objects for the menus
# the fleet, the examples and the CRS226's own export use; a menu that is absent
# is still probed, it just may not get an object and therefore stays unknown.
MINIMAL_ADD = {
    "/interface bridge port": "bridge=__probe_bridge__ interface=ether1",
    "/interface vlan": "name=__probe__ interface=lo vlan-id=99",
    "/interface wireguard peers": 'interface=__probe_wg__ public-key="l0VH8y3T0nKzZ9Qq2m4Xo8b1y6wR5cJ7dE3fG9hI2kA=" allowed-address=10.99.99.0/24',
    "/interface list member": "list=__probe_list__ interface=lo",
    "/ip address": "address=10.99.99.1/32 interface=lo",
    "/ip arp": "address=10.99.99.99 interface=lo",
    "/ip dhcp-server": "name=__probe__ interface=ether1 address-pool=__probe_pool__",
    "/ip dhcp-server network": "address=10.99.99.0/24",
    "/ip dns static": "name=__probe__ address=10.99.99.99",
    "/ip firewall address-list": "list=__probe__ address=10.99.99.99",
    "/ip firewall filter": "chain=forward",
    "/ip firewall mangle": "chain=prerouting",
    "/ip firewall nat": "chain=srcnat",
    "/ip pool": "name=__probe__ ranges=10.99.99.10-10.99.99.20",
    "/ip route": "dst-address=10.99.99.0/24 gateway=lo",
    "/ipv6 address": "address=fd00:99::1/64 interface=lo",
    "/queue simple": "name=__probe__ target=10.99.99.0/24",
    "/system scheduler": 'name=__probe__ on-event="/system identity print"',
    "/system script": 'name=__probe__ source="/system identity print"',
    "/tool netwatch": "host=10.99.99.99",
}

# Objects that have to exist before the menu's own object can be created (a
# bridge port needs a bridge, a WireGuard peer needs an interface). They are
# removed again after the menu is probed.
PRELUDE = {
    "/interface bridge port": ["/interface bridge add name=__probe_bridge__"],
    "/interface wireguard peers": ["/interface wireguard add name=__probe_wg__"],
    "/ip dhcp-server": ["/ip pool add name=__probe_pool__ ranges=10.99.99.10-10.99.99.20"],
}

CLEANUP = {
    "/interface bridge port": ["/interface bridge remove [find name=__probe_bridge__]"],
    "/interface wireguard peers": ["/interface wireguard remove [find name=__probe_wg__]"],
    "/ip dhcp-server": ["/ip pool remove [find name=__probe_pool__]"],
}

# Menus whose keys are *names*, not arguments: `/ip service set ssh …`. Reading
# `[/ip service get ssh]` returns the service's whole property bag, which
# `:typeof` calls an array -- the one shape that would be mistaken for a list.
NAME_KEYED = {"/ip service"}

# Singletons whose properties are not written to even for a moment: `/ip ssh`
# is the one where a restore that fails could take away the control channel the
# probe itself runs on. Its `ciphers` list is carried by the overlay instead.
DANGER = {"/ip ssh"}

TYPEOF = ':do {{:put ("{i}%{a}=" . [:typeof [{ref} {a}]])}} on-error={{:put "{i}%{a}=?"}}'
TYPE_RE = re.compile(r"^(\d+)%([a-z0-9.\-\[\]]+)=(\w+)$", re.M)


def q(v):
    """Quote a RouterOS value. A bare comma is a parse error for the whole line."""
    return '"' + v.replace("\\", "\\\\").replace('"', '\\"').replace("$", "\\$") + '"'


def set_probe(menu, numbers, attr, value, mark):
    """A `set` that says whether the device took the value, and that it ran."""
    target = ("%s " % numbers) if numbers else ""
    return (':do {/%s set %s%s=%s; :put "OK%s"} on-error={:put "NO%s"}; :put "END%s"'
            % (menu, target, attr, q(value), mark, mark, mark))


def verdict(out, mark):
    """yes = taken, no = refused, ? = the line never ran (parse error / no ssh)."""
    if out is None or ("END" + mark) not in out:
        return "?"
    return "no" if ("NO" + mark) in out else "yes"


# Rows the completion list carries that are not values: `<value>` is the marker
# for "anything goes", and the rest are syntax the CLI offers at that position.
COMPLETION_META = {"<value>", "*", "!", "[", "(", "$", '"', ".."}


def enum_values(ssh, path, verb, attr):
    """The values the CLI itself offers for one argument, in its own order."""
    out = ssh.run('/console/inspect request=completion input="/%s/%s %s="'
                  % (path.replace(" ", "/"), verb, attr)) or ""
    vals = []
    for line in out.splitlines():
        parts = line.split()
        if len(parts) < 3 or parts[0] != "completion" or parts[-1] != "yes":
            continue
        if parts[2] == "syntax-meta" or parts[1] in COMPLETION_META:
            continue
        vals.append(parts[1])
    return vals


def comma_takes(ssh, path, numbers, attr, value, mark):
    """Does the device take this value for this argument? yes / no / ?"""
    return verdict(ssh.run(set_probe(path, numbers, attr, value, mark)), mark)


def temp_probe(menu, where, get, attr, value, mark):
    """Set, measure, restore -- one line, so the device is never left changed.

    `where` is the object selector for a list menu, empty for a singleton. The
    measure is `:len`, and it is the evidence: an array holding three values has
    length 3, while a string that merely contains a comma has the length of the
    whole string (`/ip firewall filter limit="10,5"` is 4, and is one value, not
    two).
    """
    target = ("%s " % where) if where else ""
    return ";".join([
        ':local old [%s %s]' % (get, attr),
        ':do {/%s set %s%s=%s; :put "OK%s"} on-error={:put "NO%s"}'
        % (menu, target, attr, q(value), mark, mark),
        ':put ("LEN%s=" . [:len [%s %s]])' % (mark, get, attr),
        ':do {/%s set %s%s=$old} on-error={:put "RESTORE-FAILED%s"}'
        % (menu, target, attr, mark),
        ':put "END%s"' % mark,
    ])


LEN_RE = re.compile(r"^LEN(\w+)=(\d+)$", re.M)


class Ssh:
    """One ssh connection, reused: `-o ControlMaster` with an askpass helper."""

    def __init__(self, port, password="", user="admin"):
        self.port = str(port)
        self.dir = tempfile.mkdtemp(prefix="menuprobe-")
        self.ctl = os.path.join(self.dir, "cm")
        askpass = os.path.join(self.dir, "askpass.sh")
        with open(askpass, "w") as fh:
            fh.write("#!/bin/sh\nprintf '%%s' '%s'\n" % password.replace("'", "'\\''"))
        os.chmod(askpass, 0o700)
        self.env = dict(os.environ)
        self.env.update({"SSH_ASKPASS": askpass, "SSH_ASKPASS_REQUIRE": "force",
                         "DISPLAY": ":0"})
        self.user = user
        self.calls = 0

    def base(self):
        return ["ssh", "-F", "/dev/null", "-p", self.port,
                "-o", "StrictHostKeyChecking=no",
                "-o", "UserKnownHostsFile=/dev/null",
                "-o", "PreferredAuthentications=password",
                "-o", "PubkeyAuthentication=no",
                "-o", "LogLevel=ERROR",
                "-o", "ConnectTimeout=15",
                "-o", "ControlMaster=auto",
                "-o", "ControlPath=" + self.ctl,
                "-o", "ControlPersist=600",
                "%s@127.0.0.1" % self.user]

    def run(self, cmd, attempts=3):
        """One RouterOS command; its stdout, or None if ssh itself failed."""
        delay = 1
        for attempt in range(attempts):
            try:
                p = subprocess.run(self.base() + [cmd], env=self.env,
                                   capture_output=True, text=True, timeout=120)
            except subprocess.TimeoutExpired:
                p = None
            self.calls += 1
            if p is not None and p.returncode in (0, 1):
                return p.stdout.replace("\r", "").strip()
            if attempt == attempts - 1:
                return None
            time.sleep(delay)
            delay *= 2
        return None


def load_menus(path):
    """Accept the walk's tree json, or the table as json."""
    data = json.load(open(path))
    if isinstance(data, dict) and "tree" in data:
        version = data.get("routeros", "?")
        menus = []
        for p, node in data["tree"].items():
            if node.get("add"):
                menus.append({"path": "/" + p, "kind": "list", "attrs": node["add"]})
            elif node.get("set"):
                menus.append({"path": "/" + p, "kind": "object", "attrs": node["set"]})
        return version, sorted(menus, key=lambda m: m["path"])
    if isinstance(data, list):
        return "?", data
    raise SystemExit("unrecognised menu table: %s" % path)


def probe(ssh, menus, verbose=False):
    results = {}
    for n, m in enumerate(menus):
        path, kind, attrs = m["path"], m["kind"], m["attrs"]
        p = path.lstrip("/")
        if path in NAME_KEYED:
            results[path] = {"skipped": "keys are names, not arguments"}
            continue

        created = False
        if kind == "object":
            ref = "/%s get" % p                       # a singleton: `get <attr>`
            numbers = None
        else:
            have = (ssh.run(':put [:len [/%s find]]' % p) or "").strip()
            if have.isdigit() and int(have) > 0:
                ref, numbers = "/%s get 0" % p, None
            else:
                args = MINIMAL_ADD.get(path)
                if args is None and "name" in attrs:
                    args = "name=__probe__"
                if args is None:
                    results[path] = {"skipped": "no object to read, and no way to make one"}
                    if verbose:
                        print("%-44s skipped" % path, file=sys.stderr)
                    continue
                for setup in PRELUDE.get(path, []):
                    ssh.run(':do {%s} on-error={:put ""}' % setup)
                ssh.run(':do {/%s add %s} on-error={:put ""}' % (p, args))
                have = (ssh.run(':put [:len [/%s find]]' % p) or "").strip()
                if not (have.isdigit() and int(have) > 0):
                    results[path] = {"skipped": "add %s was refused" % args}
                    if verbose:
                        print("%-44s add refused" % path, file=sys.stderr)
                    continue
                created = True
                numbers = "[:pick [/%s find] ([:len [/%s find]] - 1)]" % (p, p)
                ref = "/%s get %s" % (p, numbers)

        # --- probe 1: what does the device call the value it already has?
        line = ";".join(TYPEOF.format(i=n, a=a, ref=ref) for a in attrs)
        types = {mm.group(2): mm.group(3) for mm in TYPE_RE.finditer(ssh.run(line) or "")}

        # What may be written to while asking. For a menu this script created an
        # object in, everything -- the object is thrown away. For a singleton
        # (`/ip dns`) only a set that is restored in the same line, and not on
        # the one menu where a bad restore would take away the control channel.
        writable = created and numbers is not None
        singleton = kind == "object" and path not in DANGER

        for k, a in enumerate(attrs):
            t = types.get(a)
            mark = "m%d_%d" % (n, k)
            if not (writable or singleton):
                types[a] = "array-unproven" if t == "array" else t
                continue

            # probe 2: a value no typed property can accept. Taken means a free
            # string, where a comma is content -- but an *unvalidated* array of
            # names takes it too, so that case is measured rather than assumed.
            # Singleton menus go through this as well: `/system note note` is a
            # free string, and the value probe below would otherwise take its
            # acceptance of three comma-separated names for list-ness.
            get = ref if singleton else "/%s get %s" % (p, numbers)
            where = "" if singleton else numbers
            took = comma_takes(ssh, p, where, a, GARBAGE, mark)
            if took == "?":
                types[a] = "?"
                continue
            if took == "yes":
                # An unvalidated value: could be a free string, could be an
                # array of names. Three comma-separated names measure as 3
                # elements and as 20 characters, and that is the difference.
                names = "probe-a,probe-b,probe-c"
                out = ssh.run(temp_probe(p, where, get, a, names, mark)) or ""
                lens = dict((mm.group(1), int(mm.group(2))) for mm in LEN_RE.finditer(out))
                types[a] = "list" if lens.get(mark) == 3 else "str"
                continue

            # probe 3: candidates. An enum's own values first -- nothing else
            # will be taken -- then the typed families.
            vals = enum_values(ssh, p, "add" if kind == "list" else "set", a)
            families = []
            if len(vals) >= 2:
                families.append((vals[0] + "," + vals[1],
                                 (vals[0] + "," + vals[1] + "," + vals[2])
                                 if len(vals) >= 3 else None))
            families += [(pair, triple) for _, pair, triple in PAIRS]

            types[a] = "nil" if t in (None, "array") else t
            for pair, triple in families:
                out = ssh.run(temp_probe(p, where, get, a, pair, mark)) or ""
                if ("RESTORE-FAILED" + mark) in out and singleton:
                    # On a disposable object the failed restore costs nothing:
                    # the object is removed below. On a singleton it means the
                    # device was left holding the probe value.
                    print("WARNING: %s %s could not be restored" % (path, a), file=sys.stderr)
                if ("NO" + mark) in out or ("END" + mark) not in out:
                    if ("END" + mark) not in out:
                        break
                    continue
                lens = dict((mm.group(1), int(mm.group(2))) for mm in LEN_RE.finditer(out))
                if lens.get(mark) == 2:
                    types[a] = "list"
                    break
                if triple is None:
                    continue
                out = ssh.run(temp_probe(p, where, get, a, triple, mark)) or ""
                if ("RESTORE-FAILED" + mark) in out and singleton:
                    print("WARNING: %s %s could not be restored" % (path, a), file=sys.stderr)
                # A comma that separates independent values takes a third; one
                # that belongs to a value's syntax (`limit=10,5`) does not, and
                # would otherwise be misreported as a list.
                if ("OK" + mark) in out:
                    types[a] = "list"
                    break

        results[path] = types
        if verbose:
            lists = [a for a, t in types.items() if t == "list"]
            print("%-44s %2d attrs, %2d list" % (path, len(attrs), len(lists)),
                  file=sys.stderr)
        if created:
            ssh.run('/%s remove %s' % (p, numbers))
        # The prelude objects go even when the add was refused, or a menu that
        # cannot be probed leaves a bridge or a WireGuard interface behind and
        # the next run is refused for a reason that has nothing to do with it.
        for undo in CLEANUP.get(path, []):
            ssh.run(':do {%s} on-error={:put ""}' % undo)
    return results


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("menus",
                    help="tree-<version>.json from walk-menus.py, or lib/menus.nix as json")
    ap.add_argument("--port", default=os.environ.get("CHR_SSH_PORT", "2325"))
    ap.add_argument("--only", action="append", default=[], help="probe just this menu")
    ap.add_argument("--limit", type=int, default=0, help="first N menus (for a quick run)")
    ap.add_argument("--verbose", "-v", action="store_true")
    ap.add_argument("--out", "-o", help="write the json here instead of stdout")
    args = ap.parse_args()

    version, menus = load_menus(args.menus)
    if args.only:
        wanted = set(args.only)
        menus = [m for m in menus if m["path"] in wanted]
    if args.limit:
        menus = menus[:args.limit]

    ssh = Ssh(args.port)
    started = time.time()
    results = probe(ssh, menus, args.verbose)
    elapsed = time.time() - started

    typed = {p: v for p, v in results.items()
             if isinstance(v, dict) and "skipped" not in v}
    lists = {p: sorted(a for a, t in v.items() if t == "list") for p, v in typed.items()}
    weak = {p: sorted(a for a, t in v.items() if t == "array-unproven")
            for p, v in typed.items()}
    unknown = {p: sorted(a for a, t in v.items() if t in ("nil", "?", "unknown"))
               for p, v in typed.items()}
    doc = {
        "routeros": version,
        "probed": len(results),
        "ssh_calls": ssh.calls,
        "seconds": round(elapsed, 1),
        "lists": {p: v for p, v in lists.items() if v},
        "weak": {p: v for p, v in weak.items() if v},
        "unknown": {p: v for p, v in unknown.items() if v},
        "types": results,
    }
    text = json.dumps(doc, indent=1, sort_keys=True)
    if args.out:
        with open(args.out, "w") as fh:
            fh.write(text + "\n")
    else:
        print(text)
    print("probed %d menus, %d with a list argument, %d ssh calls, %.0fs"
          % (len(results), len([p for p, v in lists.items() if v]), ssh.calls, elapsed),
          file=sys.stderr)


if __name__ == "__main__":
    main()