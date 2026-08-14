#!/usr/bin/env bash
set -euo pipefail

runtime="${1:?runtime directory is required}"
kernel="$runtime/assets/vm/vmlinuz-virt"
initrd="$runtime/assets/vm/initrd.img"
rootfs="$runtime/assets/vm/alpine-rootfs.squashfs"

for file in "$kernel" "$initrd" "$rootfs"; do
    test -s "$file"
done
command -v qemu-system-aarch64 >/dev/null
command -v sshpass >/dev/null

work_dir="$(mktemp -d)"
serial_log="$work_dir/serial.log"
qemu_log="$work_dir/qemu.log"
persist="$work_dir/persist.img"
downloads="$work_dir/downloads"
qemu_pid=""

show_diagnostics() {
    echo '--- Nexus runtime serial tail ---' >&2
    tail -n 160 "$serial_log" >&2 2>/dev/null || true
    echo '--- QEMU stderr tail ---' >&2
    tail -n 80 "$qemu_log" >&2 2>/dev/null || true
}

cleanup() {
    if [ -n "$qemu_pid" ] && kill -0 "$qemu_pid" 2>/dev/null; then
        kill "$qemu_pid" 2>/dev/null || true
        wait "$qemu_pid" 2>/dev/null || true
    fi
    rm -rf "$work_dir"
}
trap cleanup EXIT

truncate -s 1G "$persist"
mkfs.ext4 -q -F "$persist"
mkdir -p "$downloads"
printf 'host-to-guest\n' > "$downloads/from-android.txt"

qemu-system-aarch64 \
    -machine virt,gic-version=3 \
    -cpu max \
    -accel tcg,thread=multi \
    -smp 4 \
    -m 2048 \
    -kernel "$kernel" \
    -append 'console=ttyAMA0 mitigations=off podroid.bandwidth=10' \
    -initrd "$initrd" \
    -drive "file=${persist},if=none,id=drive1,format=raw,cache=writeback" \
    -device virtio-blk-pci,drive=drive1,romfile= \
    -drive "file=${rootfs},if=none,id=drive2,format=raw,readonly=on" \
    -device virtio-blk-pci,drive=drive2,romfile= \
    -fsdev "local,id=downloads_fs,path=${downloads},security_model=none" \
    -device virtio-9p-pci,fsdev=downloads_fs,mount_tag=downloads,romfile= \
    -netdev user,id=net0,ipv6=off,hostfwd=tcp:127.0.0.1:19922-:22,hostfwd=tcp:127.0.0.1:14096-:4096 \
    -device virtio-net-pci,netdev=net0,romfile= \
    -serial "file:${serial_log}" \
    -display none \
    -monitor none \
    -no-reboot \
    >"$qemu_log" 2>&1 &
qemu_pid="$!"

ready=false
for _attempt in $(seq 1 360); do
    if ! kill -0 "$qemu_pid" 2>/dev/null; then
        echo "QEMU exited before the runtime became ready" >&2
        show_diagnostics
        exit 1
    fi
    if curl --fail --silent --show-error \
        --user opencode:secret \
        --connect-timeout 2 --max-time 3 \
        http://127.0.0.1:14096/global/health >/dev/null 2>&1; then
        ready=true
        break
    fi
    sleep 1
done

if [ "$ready" != true ]; then
    echo "OpenCode health did not become ready within 360 seconds" >&2
    show_diagnostics
    exit 1
fi
serial_ready=false
for _attempt in $(seq 1 30); do
    if grep -Fq 'Ready!' "$serial_log"; then
        serial_ready=true
        break
    fi
    sleep 1
done
if [ "$serial_ready" != true ]; then
    echo "OpenCode health passed but the guest ready contract did not" >&2
    show_diagnostics
    exit 1
fi

ssh_options=(
    -p 19922
    -o BatchMode=no
    -o ConnectTimeout=5
    -o PreferredAuthentications=password
    -o PubkeyAuthentication=no
    -o StrictHostKeyChecking=no
    -o UserKnownHostsFile=/dev/null
)
ssh_ready=false
for _attempt in $(seq 1 60); do
    if sshpass -p podroid ssh "${ssh_options[@]}" \
        root@127.0.0.1 true >/dev/null 2>&1; then
        ssh_ready=true
        break
    fi
    sleep 1
done
if [ "$ssh_ready" != true ]; then
    echo "SSH did not become ready" >&2
    show_diagnostics
    exit 1
fi

sshpass -p podroid ssh "${ssh_options[@]}" root@127.0.0.1 'set -eu
    test -c /dev/net/tun
    ip tuntap add dev nexus-tun0 mode tun
    ip tuntap add dev nexus-tap0 mode tap
    ip link set nexus-tun0 up
    ip link set nexus-tap0 up
    ip -details tuntap show | grep -q nexus-tun0
    ip -details tuntap show | grep -q nexus-tap0
    netif=$(ip route show default | awk "NR == 1 { print \$5 }")
    test -n "$netif"
    tc qdisc show dev "$netif" | grep -q "qdisc tbf"
    zcat /proc/config.gz | grep -Fxq "CONFIG_TUN=y"
    zcat /proc/config.gz | grep -Fxq "CONFIG_NET_SCH_TBF=y"
    zcat /proc/config.gz | grep -Fxq "CONFIG_NET_9P=y"
    zcat /proc/config.gz | grep -Fxq "CONFIG_NET_9P_VIRTIO=y"
    zcat /proc/config.gz | grep -Fxq "CONFIG_9P_FS=y"
    zcat /proc/config.gz | grep -Fxq "# CONFIG_MODULES is not set"
    test "$(find /lib/modules -name "*.ko" -print 2>/dev/null | wc -l)" -eq 0
    mountpoint -q /mnt/downloads
    grep -Fxq "host-to-guest" /mnt/downloads/from-android.txt
    printf "guest-to-host\n" > /mnt/downloads/from-nexus.txt
    ip tuntap del dev nexus-tun0 mode tun
    ip tuntap del dev nexus-tap0 mode tap'

grep -Fxq 'guest-to-host' "$downloads/from-nexus.txt"

printf 'Boot smoke test passed: OpenCode healthy; Downloads 9P, TUN/TAP and TBF operational.\n'
