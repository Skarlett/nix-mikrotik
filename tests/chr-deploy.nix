{ lib, pkgs, imageFile, nix-mikrotik, harness, script, refusedScript }:

# Apply a rendered configuration to a real RouterOS, then read the device back.
#
# `checks.chr-smoke` proves the pinned image still boots. That is the image, not
# the tool: until this check nothing in the repository asked whether what the
# *renderer* produces is something a RouterOS accepts -- and a script the device
# refuses is silent, because `/import` exits 0 whether the configuration applied
# or the device refused to parse it. A renderer change that produces such a
# script reached a real router before anything noticed; that is the gap this
# closes.
#
# So: boot the pinned CHR (TCG -- a nixos test VM has no nested KVM, which is
# why this takes minutes rather than seconds), let `tests/chr-deploy.py` apply
# the configuration and read the device's state back over REST, then deploy a
# deliberately broken script and require *that* deploy to fail. The failing case
# is what makes the passing case a check: without it, a tool that reported
# success unconditionally would pass this too.
#
# The device is a CHR, never a real router. The configuration is
# `tests/fixtures/chr-configuration.nix`, rendered by the same
# `mt.mkRouterScript` the flake ships -- a CHR has one ethernet port, so it is
# written for that device rather than reusing the examples, which name ether2,
# ether3, ether5 and sfp1.
let
  # Obviously fake, and they stay in this file: one is 32 bytes of base64
  # (`=` padding is what has to be quoted) and one carries the three characters
  # RouterOS gives meaning to inside a quoted value.
  wgKey = "QUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUE=";
  dnsComment = "a\"b\\c$d";

  # The runner is a script of its own rather than a string spliced into the
  # test's Python: the arguments carry quotes and `$`, and a shell script is
  # where those belong.
  runner = pkgs.writeShellScript "chr-deploy-check-run" (lib.concatStringsSep " " [
    "${harness}/bin/chr-deploy-check"
    "--host 127.0.0.1"
    "--ssh-port 2201"
    "--rest-port 8081"
    "--script ${script}/router-config.rsc"
    "--expect-hostname chr-deploy"
    "--secret ${lib.escapeShellArg "wg/private-key=${wgKey}"}"
    "--secret ${lib.escapeShellArg "dns/comment=${dnsComment}"}"
    "--broken-script ${refusedScript}"
    "--cli ${nix-mikrotik}/bin/nix-mikrotik"
  ]);
in
pkgs.testers.nixosTest {
  name = "mikrotik-chr-deploy";

  nodes.machine = { pkgs, ... }: {
    virtualisation = {
      # The CHR takes 1 GiB of this (see the qemu command below); the rest is
      # the test VM, which is running qemu.
      memorySize = 3072;
      cores = 2;
      diskSize = 4096;
    };
    environment.systemPackages = [
      pkgs.qemu
      pkgs.openssh
      pkgs.python3
      nix-mikrotik
    ];
  };

  testScript = ''
    machine.start()
    machine.wait_for_unit("multi-user.target")

    # The image is copied into an overlay rather than used directly: a CHR boot
    # writes to its disk, and the store is read-only.
    machine.succeed(
        "qemu-img create -q -f qcow2 -F qcow2 -b ${imageFile} /tmp/chr.qcow2")
    machine.succeed(
        "qemu-system-x86_64"
        " -name chr-deploy"
        " -machine q35"
        " -accel tcg"
        " -cpu max"
        " -smp 2"
        " -m 1024"
        " -drive file=/tmp/chr.qcow2,if=virtio,format=qcow2"
        " -netdev user,id=mgmt,hostfwd=tcp:127.0.0.1:2201-:22,hostfwd=tcp:127.0.0.1:8081-:80"
        " -device virtio-net-pci,netdev=mgmt"
        " -display none"
        " -serial file:/tmp/chr-console.log"
        " -daemonize -pidfile /tmp/chr.pid"
    )

    # The harness waits for the device's REST API itself, so this covers the
    # boot; its output is the assertion report and is printed either way.
    (status, output) = machine.execute("${runner}", timeout=1200)
    print(output)
    if status != 0:
        # The CHR's own console is the only place the boot says anything when
        # the device never reaches a REST prompt.
        print(machine.execute("tail -n 40 /tmp/chr-console.log")[1])
        raise Exception("the deploy check failed (rc %d)" % status)
    print(machine.succeed("grep -m1 'MikroTik Login:' /tmp/chr-console.log"))
  '';
}