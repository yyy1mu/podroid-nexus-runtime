#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
output_dir="${1:?output directory is required}"
system_version="${NEXUS_RUNTIME_SYSTEM_VERSION:?NEXUS_RUNTIME_SYSTEM_VERSION is required}"
opencode_version="${NEXUS_OPENCODE_VERSION:?NEXUS_OPENCODE_VERSION is required}"
iwan_version="${NEXUS_IWAN_VERSION:?NEXUS_IWAN_VERSION is required}"
iwan_sha256="${NEXUS_IWAN_SHA256:?NEXUS_IWAN_SHA256 is required}"
work_dir="$(mktemp -d)"
trap 'sudo rm -rf "$work_dir"' EXIT

source "$repo_root/.github/scripts/alpine-rootfs.sh"

rootfs="$work_dir/rootfs"
build_sysroot="$work_dir/build-sysroot"
mkdir -p "$output_dir"
alpine_prepare_apk "$work_dir/alpine-tools"
alpine_extract_aarch64_root "$build_sysroot"
alpine_apk_add "$build_sysroot" musl-dev linux-headers
alpine_extract_aarch64_root "$rootfs"

sudo mkdir -p "$rootfs/usr/local/bin"
guest_cflags=(
    -O2 -Wall -Wextra -Wno-unused-parameter -static
    -fstack-protector-strong -D_FORTIFY_SOURCE=2
)
aarch64-linux-gnu-gcc --sysroot="$build_sysroot" -B"$build_sysroot/usr/lib/" \
    "${guest_cflags[@]}" \
    "$repo_root/build-rootfs/overlay-normalize/podroid-overlay-normalize.c" \
    -o "$work_dir/podroid-overlay-normalize"
elf_header="$(aarch64-linux-gnu-readelf -h "$work_dir/podroid-overlay-normalize")"
elf_program_headers="$(aarch64-linux-gnu-readelf -l "$work_dir/podroid-overlay-normalize")"
grep -q 'Machine:.*AArch64' <<< "$elf_header"
if grep -q INTERP <<< "$elf_program_headers"; then
    echo "Guest helper is not statically linked" >&2
    exit 1
fi
sudo install -m 0755 \
    "$work_dir/podroid-overlay-normalize" \
    "$rootfs/usr/local/bin/"

sudo env \
    ALPINE_VERSION="$ALPINE_RELEASE" \
    SYSTEM_VERSION="$system_version" \
    OPENCODE_VERSION="$opencode_version" \
    IWAN_VERSION="$iwan_version" \
    IWAN_SHA256="$iwan_sha256" \
    ALPINE_MIRROR="$ALPINE_MIRROR" \
    GUEST_ALPINE_MIRROR="${NEXUS_GUEST_ALPINE_MIRROR:-https://mirrors.ustc.edu.cn/alpine}" \
    ROOTFS="$rootfs" \
    WORK_DIR="$repo_root/build-rootfs" \
    APK_BIN="$ALPINE_APK" \
    "$repo_root/build-rootfs/build-rootfs.sh"

sudo mksquashfs "$rootfs" "$output_dir/alpine-rootfs.squashfs" \
    -comp zstd -Xcompression-level 19 -all-root -noappend
sudo chown "$(id -u):$(id -g)" "$output_dir/alpine-rootfs.squashfs"
test -s "$output_dir/alpine-rootfs.squashfs"
