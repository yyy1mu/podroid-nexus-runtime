#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
output_dir="${1:?output directory is required}"
kernel_version="${NEXUS_KERNEL_VERSION:?NEXUS_KERNEL_VERSION is required}"
work_dir="$(mktemp -d)"
trap 'sudo rm -rf "$work_dir"' EXIT

source "$repo_root/.github/scripts/alpine-rootfs.sh"

mkdir -p "$output_dir"
curl --fail --location --retry 3 \
    --output "$work_dir/linux.tar.xz" \
    "https://cdn.kernel.org/pub/linux/kernel/v7.x/linux-${kernel_version}.tar.xz"
tar -xf "$work_dir/linux.tar.xz" -C "$work_dir"
kernel_dir="$work_dir/linux-${kernel_version}"

make -C "$kernel_dir" ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- defconfig
make -C "$kernel_dir" ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- virt.config

# The upstream defconfig intentionally offers broad hardware coverage through
# modules. Nexus is a fixed QEMU virt appliance: turn every inherited module
# off before CONFIG_MODULES=n is merged. Otherwise Kconfig promotes many of
# those '=m' entries to built-ins and wastes both build time and kernel space.
sed -E 's/^(CONFIG_[A-Z0-9_]+)=m$/# \1 is not set/' \
    "$kernel_dir/.config" > "$kernel_dir/.config.nexus"
mv "$kernel_dir/.config.nexus" "$kernel_dir/.config"
(
    cd "$kernel_dir"
    ./scripts/kconfig/merge_config.sh -m .config "$repo_root/podroid_kernel.config"
)
make -C "$kernel_dir" ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- olddefconfig
sh "$repo_root/build-tools/verify-kernel-config.sh" "$kernel_dir/.config"

kernel_build_started="$SECONDS"
make -C "$kernel_dir" ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- \
    -j"$(nproc)" Image.gz
kernel_build_seconds="$((SECONDS - kernel_build_started))"

initroot="$work_dir/initroot"
alpine_prepare_apk "$work_dir/alpine-tools"
alpine_extract_aarch64_root "$initroot"
alpine_apk_add "$initroot" \
    busybox e2fsprogs util-linux

sudo install -m 0755 "$repo_root/init-podroid" "$initroot/init"
sudo rm -rf \
    "$initroot/var/cache/apk"/* \
    "$initroot/tmp"/* \
    "$initroot/var/tmp"/* \
    "$initroot/usr/share/man" \
    "$initroot/usr/share/doc" \
    "$initroot/proc"/* \
    "$initroot/sys"/* \
    "$initroot/dev"/* \
    "$initroot/run"/* \
    "$initroot/boot"

cp "$kernel_dir/arch/arm64/boot/Image.gz" "$output_dir/vmlinuz-virt"
(
    cd "$initroot"
    sudo find . -print0 | sudo cpio --null -o -H newc 2>/dev/null
) | gzip -9 > "$output_dir/initrd.img"

test -s "$output_dir/vmlinuz-virt"
test -s "$output_dir/initrd.img"
if gzip -dc "$output_dir/initrd.img" | cpio -it 2>/dev/null | \
    grep '^\./lib/modules' >/dev/null; then
    echo "FATAL: monolithic initramfs unexpectedly contains /lib/modules" >&2
    exit 1
fi

printf '%s\n' \
    "kernelBuildSeconds=${kernel_build_seconds}" \
    "kernelBytes=$(stat -c '%s' "$output_dir/vmlinuz-virt")" \
    "initrdBytes=$(stat -c '%s' "$output_dir/initrd.img")" \
    'kernelModules=0' \
    > "$output_dir/kernel-metrics.properties"
