# Differences from upstream

Upstream is a single-file generator; this is a module class, a CLI and a test
rig around the same renderer. These are the deliberate deviations, and the one
upstream defect that is kept on purpose.

* the configuration is a module, not a bare attribute set — and the bare
  attribute set still works (`mikrotik.nix`, `examples/legacy-wrapper.nix`);
* `/system identity` is an option, so the deploy tool can verify a device;
* secrets are references, not strings;
* booleans and integers are typed rather than written as `"yes"`/`"no"`;
* every menu is a typed option as well as a `sections` key
  (`mikrotik.ip."dhcp-server".network`), with the attribute names it knows, so a
  misspelt menu or attribute fails evaluation instead of a router import;
* section order can be pinned;
* upstream's example puts two `action=`/`chain=` entries under
  `/ip firewall address-list`, where RouterOS will reject them;
  `examples/module-configuration.nix` has them under `/ip firewall filter`
  where they belong. The golden test keeps upstream's version as-is.

## The render check

Upstream's example still renders, and `nix-build mikrotik.nix` still works. It is
not byte-identical any more, and the render check no longer pretends it is: every
`add`/`set` line comes out the same, in upstream's order, plus four deliberate
deviations (a generated header, `/system identity` first with a quoted value, a
final newline, and pinned section order). `tests/golden/legacy-upstream.rsc` is
upstream's own generator's output for that fixture, committed as it came out; the
check asserts the deviations by name and diffs everything else against it.
`tests/golden/README.md` lists them and says how to regenerate the file.
