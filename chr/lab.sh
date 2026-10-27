#!/usr/bin/env bash
# chr-lab -- boot two MikroTik CHR VMs wired to each other, unprivileged.
#
#   chr-lab start     create overlays and start both VMs
#   chr-lab stop      stop both
#   chr-lab status    show pids and the management ports
#   chr-lab fresh     drop the overlays (licence and configuration go with them)
#
# CHR_IMAGE is set by the wrapper to the pinned image in the store.
set -euo pipefail

STATE="${CHR_LAB_STATE:-$PWD/chr-lab}"
IMAGE="${CHR_IMAGE:?CHR_IMAGE is not set; run this through the flake app}"

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

  # The inter-router link is the tcp socket backend: no tap, so no
  # CAP_NET_ADMIN, and flow control that the UDP (dgram) backend lacks.
  qemu-system-x86_64 \
    -name "$name" \
    -machine q35,accel=kvm:tcg \
    -cpu max -smp 2 -m 1024 \
    -drive "file=$STATE/$name.qcow2,if=virtio,format=qcow2" \
    -netdev "$link" \
    -device "virtio-net-pci,netdev=link0,mac=$mac1,host_mtu=9000" \
    -netdev "user,id=mgmt,hostfwd=tcp:127.0.0.1:$ssh-:22,hostfwd=tcp:127.0.0.1:$www-:80" \
    -device "virtio-net-pci,netdev=mgmt,mac=$mac2" \
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
    start_vm chr-a "socket,id=link0,listen=127.0.0.1:15501" \
      52:54:00:00:0a:01 52:54:00:00:0b:01 2201 8081
    sleep 2
    start_vm chr-b "socket,id=link0,connect=127.0.0.1:15501" \
      52:54:00:00:0a:02 52:54:00:00:0b:02 2202 8082
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
      if [[ -f "$STATE/$name.pid" ]] && kill -0 "$(cat "$STATE/$name.pid")" 2>/dev/null; then
        echo "$name: running (pid $(cat "$STATE/$name.pid"))"
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
    exit 2
    ;;
esac
