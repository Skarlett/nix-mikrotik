# Patched MikroTik CHR images, so a generated configuration can be tested
# against a real RouterOS before it reaches a real router.
#
# The images come from elseif/MikroTikPatch, which republishes RouterOS with a
# licence that lifts CHR's 1 Mbit/s free-tier cap -- the cap makes any
# throughput test meaningless otherwise. That repository's release assets are
# the only artifacts it publishes: a mirror of its *source* has no image behind
# it, and old release tags are pruned, so the pin below is to a tag that exists
# (7.15.2, the version originally referenced, no longer has a release).
#
# Licensing note: this is a licensing-patched build. The legitimate alternative
# for a lab is a CHR trial licence (1 Gbit/s, MikroTik account). Both are
# fetched the same way; swap the url/hash below if that is what you want.
{ lib, stdenv, fetchurl, unzip, qemu, runCommand, makeWrapper, writeShellApplication }:

let
  version = "7.15.3";
  base = "https://github.com/elseif/MikroTikPatch/releases/download/${version}";

  labScript = writeShellApplication {
    name = "chr-lab";
    runtimeInputs = [ qemu ];
    text = builtins.readFile ./lab.sh;
  };
in
rec {
  inherit version;

  # The disk image the lab boots. Kept as a fixed-output fetch: 23 MB, and the
  # only artifact in this repository that is not source.
  image = stdenv.mkDerivation {
    pname = "mikrotik-chr";
    inherit version;

    src = fetchurl {
      url = "${base}/chr-${version}.qcow2.zip";
      hash = "sha256-+W15/hQ+FkwX9hzHAsd8dbRxJKAsgKiM/2S26aq/qsY=";
    };

    nativeBuildInputs = [ unzip ];

    unpackPhase = "unzip -q $src";
    installPhase = ''
      runHook preInstall
      install -Dm444 "chr-${version}.qcow2" "$out/mikrotik-chr-${version}.qcow2"
      runHook postInstall
    '';

    meta.description = "Patched MikroTik RouterOS CHR ${version} disk image";
  };

  imageFile = "${image}/mikrotik-chr-${version}.qcow2";

  # The `option` package carries the devel shell and `keygen`; a freshly booted
  # CHR is licensed `free` (1 Mbit/s) until keygen has run *and* the device has
  # rebooted.
  optionPackage = stdenv.mkDerivation {
    pname = "mikrotik-option";
    inherit version;
    src = fetchurl {
      url = "${base}/option-${version}.npk";
      hash = "sha256-PtnuwcfbXzid65XZNeSbKmize/c2/Ivzwgwkm9EkYDA=";
    };
    dontUnpack = true;
    installPhase = ''
      install -Dm444 $src $out/option-${version}.npk
    '';
  };

  # Two CHRs on a point-to-point link, with a management NIC each.
  #
  # The link is QEMU's tcp socket netdev, not a tap: a tap needs
  # CAP_NET_ADMIN, and this has to run as an ordinary user. UDP (`dgram`) is the
  # obvious-looking alternative and the wrong one -- it has no flow control and
  # collapses to ~50-130 Mbit/s under load, where the socket backend sustains
  # 1.5-2 Gbit/s between two CHRs.
  lab = runCommand "chr-lab" {
    nativeBuildInputs = [ makeWrapper ];
    meta.mainProgram = "chr-lab";
  } ''
    makeWrapper ${lib.getExe labScript} $out/bin/chr-lab \
      --prefix PATH : ${lib.makeBinPath [ qemu ]} \
      --set CHR_IMAGE ${image}/mikrotik-chr-${version}.qcow2
  '';
}
