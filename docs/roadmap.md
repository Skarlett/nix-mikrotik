# Not done yet

The gaps that are deliberate, what would close each, and the two that are
measured on a device rather than assumed.

* **a real diff/reconcile**: upstream's stated goal of a structural diff needs
  a parser for `.rsc`, which does not exist here. `diff` is textual.
* **idempotent import**: without reconciliation, `--reset` is the only
  convergent mode, and it is destructive.
* **`/export`-based import of existing routers**: the migration path is still
  "read the export, write the module by hand".
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
