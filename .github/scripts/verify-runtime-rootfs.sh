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

grep -Fq 'need podroid-network podroid-opencode' \
    "$rootfs/etc/init.d/podroid-ready"
grep -Fq '/usr/local/bin/opencode --version' \
    "$rootfs/etc/init.d/podroid-opencode"
grep -Fq 'while [ "$_i" -lt 180 ]' \
    "$rootfs/etc/init.d/podroid-opencode"

if find "$rootfs" \( -type f -o -type l \) | \
    grep -Eqi 'tigervnc|Xvnc|pulseaudio|podroid-vsock|podroid-hostd|libusb'; then
    echo "Forbidden desktop, AVF, host-bridge, or libusb content found" >&2
    exit 1
fi
