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
grep -q '^runtimeRootfsTag=v.*-rootfs$' "$runtime/runtime.properties"
grep -q '^runtimeBootTag=v.*-boot$' "$runtime/runtime.properties"
grep -q '^runtimeQemuTag=v.*-qemu$' "$runtime/runtime.properties"
(
    cd "$runtime"
    sha256sum --check SHA256SUMS
)

if find "$runtime" \( -type f -o -type l \) | \
    grep -Eqi 'tigervnc|Xvnc|pulseaudio|podroid-vsock|podroid-hostd|libusb'; then
    echo "Forbidden desktop, AVF, host-bridge, or libusb content found" >&2
    exit 1
fi
