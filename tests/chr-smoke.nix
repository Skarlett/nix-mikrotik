{ pkgs, imageFile }:

# Boot the pinned CHR image under QEMU and wait for RouterOS' login prompt.
#
# This is the "does the image expression actually produce something bootable"
# check. It runs with TCG, not KVM: a nixos test VM has no nested
# virtualization, so the boot is slow (minutes, not seconds) and this check
# takes the timeout it needs rather than pretending to be fast.
pkgs.testers.nixosTest {
  name = "mikrotik-chr-smoke";

  nodes.machine = { config, pkgs, ... }: {
    virtualisation = {
      memorySize = 3072;
      cores = 2;
      diskSize = 4096;
    };
    environment.systemPackages = [ pkgs.qemu ];
    # The image is copied in, not referenced from the store: a CHR boot writes
    # to the disk, and the store is read-only.
  };

  testScript = ''
    machine.start()
    machine.wait_for_unit("multi-user.target")

    machine.succeed("qemu-img create -q -f qcow2 -F qcow2 -b ${imageFile} /tmp/chr.qcow2");
    machine.succeed(
        "qemu-system-x86_64"
        " -machine q35"
        " -accel tcg"
        " -cpu max"
        " -smp 2"
        " -m 1024"
        " -drive file=/tmp/chr.qcow2,if=virtio,format=qcow2"
        " -display none"
        " -serial file:/tmp/chr-console.log"
        " -daemonize -pidfile /tmp/chr.pid"
    )

    machine.wait_until_succeeds(
        "grep -q 'MikroTik Login:' /tmp/chr-console.log", timeout=900)
    print(machine.succeed("tail -n 3 /tmp/chr-console.log"))
  '';
}