# Not done yet

The gaps that are deliberate, what would close each, and the two that are
measured on a device rather than assumed.

The procedure for working on these, and the ordered backlog with a "done when"
for each, is in [The hardening campaigns](hardening-campaigns.md).

* **one RouterOS version, not two**: the menu table is walked from 7.25, while
  `chr/default.nix` pins 7.15.3 for the lab and `checks.chr-deploy`. A menu the
  fleet uses can therefore be in the table and absent from the device the
  checks deploy to, or the other way round. Bumping the pin to the version the
  table is walked from closes it; the licence and the deploy fixture need the
  same pass ([Maintaining the menu table](maintaining-the-menu-table.md)).
* **a real diff/reconcile**: the parser and the differ exist
  ([the `.rsc` parser](rsc-parser.md)) and `deploy` now applies the *difference*
  between the device's `/export` and the script, so a second deploy converges
  instead of duplicating ([Deploying](deploying.md)). What is still missing is
  the **ownership predicate**: the patch knows what the device holds and what the
  script declares, but not which of the device's objects this repository owns,
  so deletions are withheld unless `--prune` says otherwise.
* **idempotent import**: closed for the default path — `deploy` computes a patch
  and a repeat is a plan of `set`s (measured: a second deploy of the CHR fixture
  is `0 add, 2 set, 0 remove`, and the object handles do not change). The
  whole-script path (`--import-whole`, and `--reset`) is still a one-shot.
* **`/export`-based import of existing routers**: the migration path is still
  "read the export, write the module by hand". The differ reads an export, which
  makes a *converge* of an existing router possible; it does not write the module.
* **the examples on a CHR**: they describe a router with `ether2` … `ether5` and
  `sfp1`, and a stock CHR has one ethernet port, so an `/ip address …
  interface=ether2` line is refused at runtime (`script error: input does not
  match any value of interface`, measured on 7.15.3 — with the identity and the
  lines above it already applied). Given the ports (six virtio NICs, management
  moved off `ether1`) the measurement is: `examples/routers/example` and
  `examples/routers/legacy` apply cleanly, 12/12 assertions;
  `module-configuration` and its typed twin are refused at `/ip dhcp-client add
  interface=ether1` (`dhcp-client on that interface already exists` — a
  default-configured CHR has one); `legacy-wrapper` is refused at `/ip firewall
  address-list` because upstream's own data says `10.10.10.10-10.10.10.10.254`
  for a range (`examples/configuration.nix:123`, and the typo is in
  `tests/golden/legacy*.rsc` too, which is why a golden comparison cannot see it).
  `checks.chr-deploy` applies `tests/fixtures/chr-configuration.nix`, which is
  written for a CHR.
  `--key`, but not a known-hosts file, so a rebuilt lab device is refused at the
  same `host:port` until the stale key is removed by hand (`ssh-keygen -R`).
