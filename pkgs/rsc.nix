{ lib, rustPlatform }:

# The `.rsc` parser, differ and patch generator (`rsc/README.md`).
#
# The crate has no dependencies, so this is one derivation and the test suite is
# the check phase: `nix build .#rsc` is also the proof that the tests pass.
#
# The tests read the repository's own golden scripts (`../tests/golden`), which
# is why the build source is the repository root and cargo runs in `rsc/`.
rustPlatform.buildRustPackage {
  pname = "rsc";
  version = "0.1.0";

  src = lib.cleanSource ./..;
  # `cargoRoot` is where the vendor step looks for Cargo.toml/Cargo.lock;
  # `buildAndTestSubdir` is where the build and check phases run. Both are needed
  # when the crate is not at the source root.
  cargoRoot = "rsc";
  buildAndTestSubdir = "rsc";
  cargoLock.lockFile = ../rsc/Cargo.lock;

  meta = {
    description = "Parse, diff and patch MikroTik RouterOS .rsc configuration scripts";
    homepage = "https://codex.unallocatedspace.luni/ComputerClub/nix-mikrotik";
    license = lib.licenses.mit;
    mainProgram = "rsc";
  };
}
