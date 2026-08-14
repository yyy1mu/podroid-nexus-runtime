#!/usr/bin/env bash
set -euo pipefail

runtime="${1:?runtime directory is required}"

for file in vmlinuz-virt initrd.img alpine-rootfs.squashfs; do
    test -s "$runtime/assets/vm/$file"
done
for file in libqemu-system-aarch64.so libslirp.so libpodroid-launcher.so; do
    test -s "$runtime/jniLibs/arm64-v8a/$file"
done
test ! -e "$runtime/jniLibs/arm64-v8a/libpodroid-bridge.so"
test -s "$runtime/assets/vm/qemu/efi-virtio.rom"
if [ -e "$runtime/assets/vm/kernel-metrics.properties" ]; then
    grep -Fxq 'kernelModules=0' "$runtime/assets/vm/kernel-metrics.properties"
fi
release="$(sed -n 's/^nexusReleaseVersion=//p' "$runtime/runtime.properties")"
test -n "$release"
grep -Eq '^runtimeIwanVersion=v[0-9]+\.[0-9]+\.[0-9]+$' "$runtime/runtime.properties"
grep -Eq '^runtimeIwanSha256=[0-9a-f]{64}$' "$runtime/runtime.properties"
grep -Fxq "tag=v${release}-bundle" "$runtime/runtime.properties"
grep -Fxq "runtimeRootfsTag=v${release}-rootfs" "$runtime/runtime.properties"
grep -Fxq "runtimeBootTag=v${release}-boot" "$runtime/runtime.properties"
grep -Fxq "runtimeQemuTag=v${release}-qemu" "$runtime/runtime.properties"
(
    cd "$runtime"
    sha256sum --check SHA256SUMS
)

if find "$runtime" \( -type f -o -type l \) | \
    grep -Eqi 'tigervnc|Xvnc|pulseaudio|podroid-vsock|podroid-hostd|libusb'; then
    echo "Forbidden desktop, AVF, host-bridge, or libusb content found" >&2
    exit 1
fi
