# The menu options

Every menu in `lib/menus.nix` is also an option path, so a configuration can
be written against the RouterOS menu rather than against a string key. The
two spellings compile to the same value.

Every menu in `lib/menus.nix` is also an option, at the path `/export` gives it
with the slashes dropped and the spaces turned into dots:

```nix
mikrotik.ip."dhcp-server".network = [
  { address = "172.29.82.0/24"; gateway = "172.29.82.1"; dns-server = "1.1.1.1,8.8.8.8"; }
];
```

rather than

```nix
mikrotik.sections."/ip dhcp-server network" = [
  { address = "172.29.82.0/24"; gateway = "172.29.82.1"; dns-server = "1.1.1.1,8.8.8.8"; }
];
```

The two are the same value: the typed layer is a front end that compiles into
`mikrotik.sections`, so the renderer never learns which spelling produced a
script. `checks.menus` renders `examples/module-configuration.nix` and
`examples/typed-module-configuration.nix` and requires the bytes to match, and
the fleet's homelab router, transliterated into the typed options, renders the
same 62-statement script (same `sha256`) as the module it ships today.

What the spelling buys:

* **a menu typo is an evaluation error**, not a `script error` on a live router
  at import time — `mikrotik.ip."dhcp-servr"` does not exist, and the module
  system says so and suggests `dhcp-server`;
* **an attribute typo is an evaluation error too**, because each menu lists the
  attribute names it knows (also from `lib/menus.nix`). Misspell `address` and
  evaluation stops with the menu, the name and the alternatives;
* the menu path is an attribute path, so it is discoverable — `nix repl`, an
  editor's completion and `nixos-option`-style inspection all work on it.

### Arguments that hold several values

Some arguments are one value and some are several. `/ip vrf interfaces` holds
interfaces, `/ip pool ranges` holds ranges, `/ip firewall filter
connection-state` holds flags — RouterOS spells all of them comma-joined in
`/export` and stores them as separate values. In the typed menus those
arguments take a Nix list:

```nix
mikrotik.ip.vrf = [ { name = "vrf.mgmt"; interfaces = [ "ether1" "ether2" ]; } ];
mikrotik.ip.pool.items = [ { name = "dhcp"; ranges = [ "10.0.0.10-10.0.0.200" ]; } ];
```

A single value is still a list (`interfaces = [ "ether1" ]`), because the shape
is a property of the argument, not of this particular router. Writing the
comma-joined string instead is an evaluation error that names the argument and
the list spelling.

The table behind this is `lists` in `lib/menus.nix`, and it comes from the
device: `scripts/probe-menu-lists.py` asks a CHR what each argument does with a
comma-separated value, and records only what the device *took*. Two things
follow from that, and both are deliberate:

* **an argument absent from `lists` is not claimed to be scalar** — it was not
  proven to be a list. Menus the probe cannot write to keep what the device
  reports as `array` and are marked as such in the generated table;
* **the check is an assertion, not a type** — `mikrotik.sections."/ip vrf"`
  still takes `interfaces = "ether1,ether2"`, and `mikrotik.checkMenuLists =
  false` turns the check off for one router that has to write a menu the table
  has not been probed for.

### Menus with submenus: `items`

`/interface wireguard` is a list of interfaces and `/interface wireguard peers`
is a list of peers, so `interface.wireguard` would have to be both a list and an
attrset of children. A menu that has submenus carries its own body under
`items`; every other menu is written directly:

```nix
mikrotik.interface.wireguard.items = [
  { name = "wg0"; listen-port = 51820; private-key = config.clan.core.vars.generators.wg0.files.private-key.placeholder; }
];
mikrotik.interface.wireguard.peers = [ { interface = "wg0"; name = "peer1"; public-key = "…"; } ];

mikrotik.ip.address = [ { address = "10.0.0.3/24"; interface = "vlan10"; network = "10.0.0.0"; } ];
```

`items` is one rule for every such menu (`/interface bridge` +
`/interface bridge port`, `/ip dhcp-server` + `/ip dhcp-server network`,
`/interface list` + `/interface list member`, `/ip dns` + `/ip dns static`,
`/tool mac-server` + its two children), rather than a per-menu name to remember.
The alternative — always writing a wrapper, so the collision case is uniform —
was rejected: it taxes every menu for the shape of five.

### Dashes in menu names

`dhcp-server` is not a Nix identifier, so the attribute path needs a quoting
step: `mikrotik.ip."dhcp-server".network`. That is accepted as the ergonomics
rather than papered over with a mapping table (a table would need a name per
menu, two spellings to keep in step, and would break the property that the
option path *is* the RouterOS path). Twelve of the thirty-six menus need it;
the quoting is standard Nix and survives `nix fmt` untouched.

### Mixing the two, and the order of `add` lines

A path written both ways merges, exactly as two `sections` definitions always
have — so a menu can move over one at a time, and a module still written against
`sections` (this repository's `hardening.nix`, the fleet's fabric) keeps
composing with one written against the menu options. Definitions merge in
reverse module order and the menus module is part of the class, so a typed menu's
lines come **after** the `sections` lines for the same path; `checks.menus`
pins that order rather than leaving it to be discovered.

`mikrotik.sectionOrder` keeps taking section paths (`"/ip dhcp-server"`): a menu
path is the same string with `.` for ` ` and a leading `/`.

Anything `lib/menus.nix` does not list is still expressible through
`mikrotik.sections` and `mikrotik.extraScript`. The table is not a RouterOS
schema (RouterOS ships none); it is what the fleet, the examples and the CRS226's
own `/export` use, and adding a menu or an attribute is one line in that file.
