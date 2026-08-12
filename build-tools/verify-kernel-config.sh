#!/bin/sh
set -eu

config_file="${1:-.config}"

require_builtin() {
    option="$1"
    if ! grep -q "^CONFIG_${option}=y$" "$config_file"; then
        echo "FATAL: CONFIG_${option} is not built in" >&2
        grep "CONFIG_${option}" "$config_file" >&2 || true
        exit 1
    fi
}

require_disabled() {
    option="$1"
    # A dependency-pruned boolean may be omitted from .config completely.
    # Both omission and the normal "is not set" form mean disabled; reject
    # only values that actually compile or enable the feature.
    if grep -Eq "^CONFIG_${option}=(y|m)$" "$config_file"; then
        echo "FATAL: CONFIG_${option} is enabled" >&2
        grep "CONFIG_${option}" "$config_file" >&2 || true
        exit 1
    fi
}

require_value() {
    option="$1"
    expected="$2"
    if ! grep -q "^CONFIG_${option}=${expected}$" "$config_file"; then
        echo "FATAL: CONFIG_${option} must be ${expected}" >&2
        grep "CONFIG_${option}" "$config_file" >&2 || true
        exit 1
    fi
}

if grep -q '^CONFIG_[A-Z0-9_]*=m$' "$config_file"; then
    echo "FATAL: the monolithic Nexus kernel still contains module options" >&2
    grep '^CONFIG_[A-Z0-9_]*=m$' "$config_file" | head -n 40 >&2
    exit 1
fi

for option in \
    EXPERT OF ARM_PSCI_FW ARM_GIC ARM_GIC_V3 ARM_ARCH_TIMER PCI PCI_MSI PCI_HOST_GENERIC \
    SERIAL_AMBA_PL011 SERIAL_AMBA_PL011_CONSOLE RTC_DRV_PL031 \
    VIRTIO VIRTIO_PCI VIRTIO_BLK VIRTIO_NET VIRTIO_CONSOLE \
    BLK_DEV_INITRD RD_GZIP DEVTMPFS DEVTMPFS_MOUNT \
    EXT4_FS EXT4_FS_SECURITY OVERLAY_FS SQUASHFS SQUASHFS_XATTR \
    SQUASHFS_ZSTD DECOMPRESS_ZSTD ZSTD_DECOMPRESS TMPFS TMPFS_XATTR \
    PROC_FS SYSFS POSIX_MQUEUE SWAP ZSMALLOC ZRAM ZRAM_BACKEND_LZ4 \
    NET PACKET UNIX INET IPV6 TUN NET_SCHED NET_SCH_TBF \
    NAMESPACES UTS_NS IPC_NS USER_NS PID_NS NET_NS \
    SECCOMP SECCOMP_FILTER BPF_SYSCALL BPF_JIT \
    IKCONFIG IKCONFIG_PROC BINFMT_ELF BINFMT_SCRIPT \
    RANDOMIZE_BASE RELOCATABLE ARM64_4K_PAGES STRICT_KERNEL_RWX; do
    require_builtin "$option"
done

for option in \
    MODULES ACPI EFI KVM XEN SUSPEND HIBERNATION PM CPU_FREQ CPU_IDLE NUMA \
    NUMA_BALANCING HOTPLUG_CPU MEMORY_HOTPLUG COMPAT CGROUPS SCHED_AUTOGROUP \
    VIRTIO_PCI_LEGACY VT AUDIT STACKPROTECTOR FORTIFY_SOURCE \
    HARDENED_USERCOPY PCIEPORTBUS HOTPLUG_PCI PCI_IOV PCI_ATS PCI_PRI \
    PCI_PASID ARM_SCMI_PROTOCOL ARM_SCPI_PROTOCOL \
    USB_SUPPORT SCSI ATA MMC MEMSTICK INPUT HID SOUND MEDIA_SUPPORT \
    BT RFKILL WIRELESS WLAN NEW_LEDS VETH BRIDGE VLAN_8021Q DUMMY \
    NETFILTER NET_9P 9P_FS FUSE_FS BTRFS_FS DRM FB THERMAL \
    WATCHDOG IOMMU_SUPPORT CAN NFC INFINIBAND MTD KPROBES FTRACE \
    ZRAM_BACKEND_LZ4HC ZRAM_BACKEND_ZSTD ZRAM_BACKEND_DEFLATE \
    ZRAM_BACKEND_842 ZRAM_BACKEND_LZO ZRAM_WRITEBACK ZRAM_MULTI_COMP \
    NET_SCH_FQ_CODEL \
    FUNCTION_TRACER LOCKUP_DETECTOR SOFTLOCKUP_DETECTOR; do
    require_disabled "$option"
done

require_value NR_CPUS 4

printf 'Verified monolithic QEMU-virt kernel: 0 modules, TUN/TAP and TBF built in.\n'
