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
(
    cd "$kernel_dir"
    ./scripts/kconfig/merge_config.sh -m .config "$repo_root/podroid_kernel.config"
    ./scripts/kconfig/merge_config.sh -m .config "$repo_root/build-tools/forced_builtin.config"
)
make -C "$kernel_dir" ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- olddefconfig
sh "$repo_root/build-tools/verify-kernel-config.sh" "$kernel_dir/.config"
make -C "$kernel_dir" ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- \
    -j"$(nproc)" Image.gz modules

modules_dir="$work_dir/modules"
make -C "$kernel_dir" ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- \
    INSTALL_MOD_PATH="$modules_dir" INSTALL_MOD_STRIP=1 modules_install
rm -f "$modules_dir"/lib/modules/*/build "$modules_dir"/lib/modules/*/source

modules_kernel_dir="$(find "$modules_dir/lib/modules" -mindepth 2 -maxdepth 2 -type d -name kernel -print -quit)"
test -n "$modules_kernel_dir"
find "$modules_kernel_dir" -name '*.ko' | \
    grep -vE '(/net/(bridge|netfilter|9p|ipv4/netfilter|ipv6/netfilter)/|/fs/(9p|fuse|overlayfs)/|/drivers/net/(tun|veth|virtio_net)\.ko$|/drivers/block/virtio_blk\.ko$|/drivers/char/hw_random/virtio-rng\.ko$|/drivers/virtio/)' | \
    xargs -r rm -f || true
find "$modules_kernel_dir" -type d -empty -delete

initroot="$work_dir/initroot"
alpine_prepare_apk "$work_dir/alpine-tools"
alpine_extract_aarch64_root "$initroot"
alpine_apk_add "$initroot" \
    busybox e2fsprogs util-linux kmod

sudo install -m 0755 "$repo_root/init-podroid" "$initroot/init"
sudo mkdir -p "$initroot/lib/modules"
sudo cp -a "$modules_dir/lib/modules/." "$initroot/lib/modules/"
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
