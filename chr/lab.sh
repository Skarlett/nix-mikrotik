#!/usr/bin/env bash
# chr-lab -- boot two MikroTik CHR VMs wired to each other, unprivileged.
#
#   chr-lab start     create overlays and start both VMs
#   chr-lab stop      stop both
#   chr-lab status    show pids and the management ports
#   chr-lab fresh     drop the overlays (licence and configuration go with them)
#
# Every host port is settable, because more than one lab runs on a host at a
# time -- a second checkout, another agent, a hand-started device. Each falls
# back to the port the docs use:
#
#   CHR_LAB_LINK_PORT  the inter-router link   (15501)
#   CHR_LAB_SSH_A/B    ssh to chr-a / chr-b    (2201 / 2202)
#   CHR_LAB_WWW_A/B    REST to chr-a / chr-b   (8081 / 8082)
#   CHR_LAB_STATE      where the overlays live ($PWD/chr-lab)
#
# CHR_IMAGE is set by the wrapper to the pinned image in the store.
set -euo pipefail

STATE="${CHR_LAB_STATE:-$PWD/chr-lab}"
IMAGE="${CHR_IMAGE:?CHR_IMAGE is not set; run this through the flake app}"

LINK_PORT="${CHR_LAB_LINK_PORT:-15501}"
SSH_A="${CHR_LAB_SSH_A:-2201}"
SSH_B="${CHR_LAB_SSH_B:-2202}"
WWW_A="${CHR_LAB_WWW_A:-8081}"
WWW_B="${CHR_LAB_WWW_B:-8082}"

start_vm() {
  local name="$1" link="$2" mac1="$3" mac2="$4" ssh="$5" www="$6"

  if [[ -f "$STATE/$name.pid" ]] && kill -0 "$(cat "$STATE/$name.pid")" 2>/dev/null; then
    echo "$name already running (pid $(cat "$STATE/$name.pid"))"
    return
  fi

  # An existing overlay holds the device's licence and configuration; only
  # create one when there is none. `chr-lab fresh` wipes both.
  if [[ ! -f "$STATE/$name.qcow2" ]]; then
    qemu-img create -q -f qcow2 -F qcow2 -b "$IMAGE" "$STATE/$name.qcow2"
  fi

  # The management NIC has to be the guest's **ether1**: a CHR's default
  # configuration runs its only dhcp-client there, and the host reaches the
  # guest through that lease (10.0.2.15, the address qemu's user-net hands out).
  # With the inter-router link first, ether1 was the link, nothing ever leased
  # an address on the management NIC, and `127.0.0.1:<ssh port>` forwarded into a
  # guest with no address -- the VMs booted and the console worked, but ssh and
  # REST never answered. The link is the second device, which is also what
  # `tests/fixtures/chr-configuration.nix` assumes: ether1 is the way in, and it
  # stays out of the bridge.
  #
  # The inter-router link is the tcp socket backend: no tap, so no
  # CAP_NET_ADMIN, and flow control that the UDP (dgram) backend lacks.
  qemu-system-x86_64 \
    -name "$name" \
    -machine q35,accel=kvm:tcg \
    -cpu max -smp 2 -m 1024 \
    -drive "file=$STATE/$name.qcow2,if=virtio,format=qcow2" \
    -netdev "user,id=mgmt,hostfwd=tcp:127.0.0.1:$ssh-:22,hostfwd=tcp:127.0.0.1:$www-:80" \
    -device "virtio-net-pci,netdev=mgmt,mac=$mac2" \
    -netdev "$link" \
    -device "virtio-net-pci,netdev=link0,mac=$mac1,host_mtu=9000" \
    -display none \
    -serial "unix:$STATE/$name.serial,server=on,wait=off" \
    -daemonize -pidfile "$STATE/$name.pid"

  echo "$name: pid $(cat "$STATE/$name.pid")  ssh 127.0.0.1:$ssh  rest http://127.0.0.1:$www"
}

stop_vm() {
  local name="$1"
  if [[ -f "$STATE/$name.pid" ]]; then
    kill "$(cat "$STATE/$name.pid")" 2>/dev/null || true
    rm -f "$STATE/$name.pid"
    echo "$name stopped"
  else
    echo "$name not running"
  fi
}

case "${1:-start}" in
  start)
    mkdir -p "$STATE"
    # One end listens, the other connects: two listeners are two unconnected
    # links. chr-a has to be up first.
    start_vm chr-a "socket,id=link0,listen=127.0.0.1:$LINK_PORT" \
      52:54:00:00:0a:01 52:54:00:00:0b:01 "$SSH_A" "$WWW_A"
    sleep 2
    start_vm chr-b "socket,id=link0,connect=127.0.0.1:$LINK_PORT" \
      52:54:00:00:0a:02 52:54:00:00:0b:02 "$SSH_B" "$WWW_B"
    cat <<'EOF'

Both routers boot unlicensed: CHR's free tier caps throughput at 1 Mbit/s.
To licence one, fetch the option package, reboot, log in as `devel` and run
`keygen`, then reboot again -- the packet path ignores the new licence until it
does. See README "Testing against a real RouterOS".
EOF
    ;;
  stop)
    stop_vm chr-b
    stop_vm chr-a
    ;;
  status)
    for name in chr-a chr-b; do
      case $name in
        chr-a) ssh=$SSH_A; www=$WWW_A ;;
        chr-b) ssh=$SSH_B; www=$WWW_B ;;
      esac
      if [[ -f "$STATE/$name.pid" ]] && kill -0 "$(cat "$STATE/$name.pid")" 2>/dev/null; then
        echo "$name: running (pid $(cat "$STATE/$name.pid"))  ssh 127.0.0.1:$ssh  rest http://127.0.0.1:$www"
      else
        echo "$name: stopped"
      fi
    done
    ;;
  fresh)
    stop_vm chr-b
    stop_vm chr-a
    rm -f "$STATE"/chr-?.qcow2
    echo "overlays removed; next start boots from the pristine image"
    ;;
  *)
    echo "usage: chr-lab {start|stop|status|fresh}" >&2
    echo "ports: CHR_LAB_LINK_PORT CHR_LAB_SSH_A CHR_LAB_SSH_B CHR_LAB_WWW_A CHR_LAB_WWW_B" >&2
    exit 2
    ;;
esac
