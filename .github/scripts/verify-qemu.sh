#!/usr/bin/env bash
set -euo pipefail

qemu_dir="${1:?QEMU output directory is required}"

for file in libqemu-system-aarch64.so libslirp.so libpodroid-launcher.so; do
    test -s "$qemu_dir/$file"
done
test ! -e "$qemu_dir/libpodroid-bridge.so"
test -s "$qemu_dir/qemu/efi-virtio.rom"
test -n "$(find "$qemu_dir/qemu/keymaps" -type f -print -quit)"

if strings "$qemu_dir/libqemu-system-aarch64.so" | grep -qi libusb; then
    echo "libusb content remains in QEMU" >&2
    exit 1
fi

python3 - "$qemu_dir/libqemu-system-aarch64.so" <<'PY'
import struct
import sys

path = sys.argv[1]
with open(path, "rb") as stream:
    data = stream.read()
phoff = struct.unpack_from("<Q", data, 32)[0]
phentsize = struct.unpack_from("<H", data, 54)[0]
phnum = struct.unpack_from("<H", data, 56)[0]
aligns = [
    struct.unpack_from("<Q", data, phoff + index * phentsize + 48)[0]
    for index in range(phnum)
    if struct.unpack_from("<I", data, phoff + index * phentsize)[0] == 1
]
if not aligns or any(alignment < 16384 for alignment in aligns):
    raise SystemExit(f"{path} is not 16 KB page aligned: {aligns}")
PY
