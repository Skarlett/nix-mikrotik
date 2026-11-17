#!/usr/bin/env bash
# Regenerate `lib/menus.generated.nix` from a real RouterOS.
#
# The table is 346 menus and every argument each one takes, read out of the
# router's own CLI with `/console/inspect`. It is generated rather than curated
# because RouterOS documents no schema, and the hand-written table it replaced
# was a guess assembled from three documents.
#
#   scripts/regenerate-menus.sh [--skip-boot]
#
# `--skip-boot` walks and probes a device that is already answering on
# `CHR_SSH_PORT` (2325 by default) instead of fetching an image and starting a
# VM: the second run of the day, or a hand-started lab, does not need another
# 23 MB download and another boot. Only ssh and python3 are needed then.
#
# Needs: qemu, ssh, curl, python3, nix (for the SRI hash check), and KVM for a
# usable speed (falls back to TCG, which is slow but works).
#
# The image is the *legacy-bios* qcow2. The plain `chr-<v>.qcow2` in the same
# release is UEFI and boots to nothing under `-machine q35` with no firmware: the
# VM runs, the console stays empty, SSH never answers, and the failure looks like
# a network problem rather than a firmware one.
#
# After it runs, review `git diff lib/menus.generated.nix` before committing. A
# shrink in menu count is not automatically fine: it can mean the walk lost a
# subtree, which is why walk.py treats a failed inspect as fatal instead of as
# "no children".
set -euo pipefail

VERSION=${VERSION:-7.25}
VARIANT=${VARIANT:-legacy-bios}
PORT=${CHR_SSH_PORT:-2325}
STATE=${CHR_STATE:-$HOME/.hermes/cache/scratch/chrgen-$VERSION}

repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

SKIP_BOOT=
for arg in "$@"; do
  case $arg in
    --skip-boot) SKIP_BOOT=1 ;;
    *) echo "unknown argument: $arg" >&2; exit 2 ;;
  esac
done

if [[ -n $SKIP_BOOT ]]; then
  tools="ssh python3"
else
  tools="qemu-system-x86_64 ssh curl python3 unzip"
fi
for tool in $tools; do
  command -v "$tool" >/dev/null || { echo "missing $tool" >&2; exit 1; }
done

mkdir -p "$STATE"

# 1. The image, checked against the release's published sha256 rather than
#    trusted. A wrong hash here means a wrong table, silently.
img="$STATE/chr-$VERSION-$VARIANT.qcow2"
if [[ -n $SKIP_BOOT ]]; then
  echo "skipping the image and the boot: expecting a device on port $PORT"
elif [[ ! -f $img ]]; then
  url="https://github.com/elseif/MikroTikPatch/releases/download/$VERSION/chr-$VERSION-$VARIANT.qcow2.zip"
  echo "fetching $url"
  curl -sL --max-time 600 -o "$STATE/img.zip" "$url"
  published=$(curl -sL --max-time 60 "$url.sha256" | awk '{print $1}')
  actual=$(sha256sum "$STATE/img.zip" | cut -d' ' -f1)
  if [[ -n $published && $published != "$actual" ]]; then
    echo "sha256 mismatch: published $published, got $actual" >&2
    exit 1
  fi
  echo "sha256 ok: $actual"
  unzip -q -o "$STATE/img.zip" -d "$STATE/unpack"
  cp "$(find "$STATE/unpack" -name '*.qcow2' -print -quit)" "$img"
  rm -rf "$STATE/unpack" "$STATE/img.zip"
fi

# 2. Boot it, once. The disk keeps its licence and host keys between runs.
if [[ -n $SKIP_BOOT ]]; then
  :
elif [[ ! -f $STATE/chr.pid ]] || ! kill -0 "$(cat "$STATE/chr.pid")" 2>/dev/null; then
  if [[ ! -f $STATE/disk.qcow2 ]]; then cp "$img" "$STATE/disk.qcow2"; fi
  qemu-system-x86_64 \
    -name chrgen \
    -machine q35,accel=kvm:tcg -cpu max -smp 2 -m 1024 \
    -drive file="$STATE/disk.qcow2",if=virtio,format=qcow2 \
    -netdev user,id=mgmt,hostfwd=tcp:127.0.0.1:"$PORT"-:22 \
    -device virtio-net-pci,netdev=mgmt,mac=52:54:00:00:0c:25 \
    -display none -serial "file:$STATE/console.log" \
    -daemonize -pidfile "$STATE/chr.pid"
  echo "booted pid $(cat "$STATE/chr.pid"); waiting for ssh on $PORT"
fi

# 3. Wait for the router to answer. A CHR generates its host keys on first boot.
cat > "$STATE/askpass.sh" <<'EOF'
#!/bin/sh
echo ""
EOF
chmod +x "$STATE/askpass.sh"

# `-F /dev/null` because this device has an empty admin password and no key:
# whatever the operator's ~/.ssh/config says (a ProxyJump, an IdentityFile, a
# permission error on a home-managed file) is not part of this question.
attempts=40
[[ -n $SKIP_BOOT ]] && attempts=3
ready=
for _ in $(seq 1 "$attempts"); do
  if CHR_SSH_PORT=$PORT SSH_ASKPASS="$STATE/askpass.sh" SSH_ASKPASS_REQUIRE=force \
     DISPLAY=:0 ssh -F /dev/null -p "$PORT" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
       -o PreferredAuthentications=password -o PubkeyAuthentication=no \
       -o LogLevel=ERROR -o ConnectTimeout=10 admin@127.0.0.1 \
       '/system resource print' 2>/dev/null | grep -q 'version:'; then
    ready=1; break
  fi
  sleep 15
done
[[ -n $ready ]] || {
  echo "router never answered on port $PORT" >&2
  if [[ -n $SKIP_BOOT ]]; then
    echo "--skip-boot: nothing is listening there; start a lab device or drop the flag" >&2
  fi
  exit 1
}

# 4. Walk it. Retries are mandatory: a timed-out inspect and an empty child list
#    are indistinguishable from outside, and a walk that treats the first as the
#    second returns a narrower tree that still looks complete.
CHR_SSH_PORT=$PORT python3 "$repo/scripts/walk-menus.py" > "$STATE/tree-$VERSION.json"

# 5. Ask what each argument does with a comma-separated value. The walk reports
#    names; only the device knows which of them are several values. This step
#    writes to the device (it creates and removes one object per menu), so it is
#    a lab-only step -- never point it at a router that matters.
CHR_SSH_PORT=$PORT python3 "$repo/scripts/probe-menu-lists.py" \
  "$STATE/tree-$VERSION.json" -o "$STATE/lists-$VERSION.json"

python3 "$repo/scripts/gen-menus.py" "$STATE/tree-$VERSION.json" "$repo" \
  "$STATE/lists-$VERSION.json"

echo
echo "regenerated. Review the diff before committing:"
echo "  git diff lib/menus.generated.nix"
echo
echo "A menu count that *falls* is the thing to look at -- it can mean the walk"
echo "lost a subtree, not that RouterOS removed a menu."