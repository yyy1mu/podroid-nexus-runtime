#!/usr/bin/env bash
set -euo pipefail

image="${1:?rootfs squashfs path is required}"
test -s "$image"

verify_dir="$(mktemp -d)"
trap 'rm -rf "$verify_dir"' EXIT
rootfs="$verify_dir/rootfs"
unsquashfs -d "$rootfs" "$image" >/dev/null

opencode="$rootfs/usr/local/bin/opencode"
test -x "$opencode"
for library in libgcc_s.so.1 libstdc++.so.6; do
    resolved="$(find "$rootfs/lib" "$rootfs/usr/lib" -name "$library" -print -quit)"
    test -n "$resolved"
    test -e "$resolved"
done

aarch64-linux-gnu-readelf -h "$opencode" | grep -q 'Machine:.*AArch64'
aarch64-linux-gnu-readelf -l "$opencode" | grep -q 'ld-musl-aarch64.so.1'
while IFS= read -r library; do
    find "$rootfs/lib" "$rootfs/usr/lib" -name "$library" -print -quit | grep -q . || {
        echo "Missing OpenCode runtime dependency: $library" >&2
        exit 1
    }
done < <(aarch64-linux-gnu-readelf -d "$opencode" | \
    sed -n 's/.*Shared library: \[\([^]]*\)\].*/\1/p')

version="$(timeout 180 qemu-aarch64-static -L "$rootfs" "$opencode" --version)"
test -n "$version"
echo "Verified OpenCode $version"

opencode_service="$rootfs/etc/init.d/podroid-opencode"
ready_service="$rootfs/etc/init.d/podroid-ready"
bootstrap_service="$rootfs/etc/init.d/podroid-bootstrap"
network_service="$rootfs/etc/init.d/podroid-network"
grep -Fq 'need podroid-network podroid-opencode' "$ready_service"
grep -Fq 'while [ "$_i" -lt 240 ]' "$ready_service"
grep -Fq 'ss -ltn' "$ready_service"
grep -Fq 'start-stop-daemon --start --background' "$opencode_service"
if grep -Fq '/usr/local/bin/opencode --version' "$opencode_service"; then
    echo "OpenCode boot service still performs the expensive version preflight" >&2
    exit 1
fi
if grep -Fq 'while [ "$_i"' "$opencode_service"; then
    echo "OpenCode boot service must not block OpenRC dependency startup" >&2
    exit 1
fi

sh -n "$opencode_service"
sh -n "$ready_service"
sh -n "$bootstrap_service"
sh -n "$network_service"

for package in iptables ip6tables nftables bridge-utils kmod; do
    if grep -Eq "^${package}([=<>~]|$)" "$rootfs/etc/apk/world"; then
        echo "Unused package remains in rootfs: $package" >&2
        exit 1
    fi
done
if grep -Eq '(^|[[:space:]])(depmod|modprobe)([[:space:]]|$)|mount -t 9p|mount -t cgroup2' \
    "$bootstrap_service"; then
    echo "Legacy module, 9P, or cgroup bootstrap logic remains" >&2
    exit 1
fi
grep -Fq 'tc qdisc replace' "$network_service"
if grep -F 'tc qdisc replace' "$network_service" | grep -Fq '|| true'; then
    echo "TBF setup still hides kernel/configuration failures" >&2
    exit 1
fi
if find "$rootfs/lib/modules" -name '*.ko' -print -quit 2>/dev/null | grep -q .; then
    echo "Rootfs unexpectedly contains loadable kernel modules" >&2
    exit 1
fi

if find "$rootfs" \( -type f -o -type l \) | \
    grep -Eqi 'tigervnc|Xvnc|pulseaudio|podroid-vsock|podroid-hostd|libusb'; then
    echo "Forbidden desktop, AVF, host-bridge, or libusb content found" >&2
    exit 1
fi
