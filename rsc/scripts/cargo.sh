#!/bin/sh
# Build/test the rsc crate with a Rust toolchain and a C linker from nixpkgs.
# Usage: ./scripts/cargo.sh test --lib
exec nix shell nixpkgs#cargo nixpkgs#rustc nixpkgs#gcc nixpkgs#gnumake \
  -c cargo "$@"
