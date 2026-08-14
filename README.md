# Nexus Runtime

Nexus Runtime is the independently versioned, QEMU-only virtual-machine
runtime used by the Nexus Android app. It is derived from Podroid and keeps
the original GPL-2.0 history and attribution.

The repository publishes immutable runtime bundles containing:

- an AArch64 Linux kernel and initramfs;
- a minimal Alpine Linux squashfs;
- the musl AArch64 OpenCode server and all of its runtime libraries;
- Android ARM64 QEMU TCG, slirp, firmware/keymaps, and the launcher.

It intentionally excludes AVF, VNC, libusb, the Android host bridge, desktop
audio, and the Podroid Android application. The published runtime contract is:

```text
nexus-runtime/
├── assets/vm/
│   ├── vmlinuz-virt
│   ├── initrd.img
│   ├── alpine-rootfs.squashfs
│   └── qemu/
├── jniLibs/arm64-v8a/
│   ├── libqemu-system-aarch64.so
│   ├── libslirp.so
│   └── libpodroid-launcher.so
├── runtime.properties
└── SHA256SUMS
```

## Releases

Only tags matching `v*` start a build. `release.properties` is the single
public version source. All artifacts in one release share that version:

- `vX.Y.Z-rootfs` publishes Alpine and OpenCode;
- `vX.Y.Z-boot` publishes the matching kernel and initramfs;
- `vX.Y.Z-qemu` publishes Android QEMU, slirp, firmware, and the launcher;
- `vX.Y.Z-bundle` reads `runtime.lock` and assembles those immutable releases
  without compiling native code again.

An unchanged component may be promoted from its previous verified release by
setting its `*SourceTag` in `runtime.lock`; its binaries are copied and checked,
not rebuilt. Clear that source tag only when the component itself changes.

Component releases are private drafts used only by the bundle workflow, keeping
the public Releases page limited to complete, directly consumable runtime
bundles. The drafts are removed after a successful bundle; a later release can
promote unchanged components directly from the previous complete bundle. Every
component archive has both an archive checksum and an internal
manifest. The assembled runtime records all three component tags in
`runtime.properties`, so an APK is reproducible without relying on short-lived
Actions caches. Heavy native builds are never required by the Nexus app
repository.

## Kernel contract

The guest kernel is a monolithic QEMU `virt` build (`CONFIG_MODULES=n`). The
workflow starts from the upstream Arm64 virtualization config, disables every
inherited module, and compiles only `Image.gz`; the initramfs contains no
`/lib/modules`. USB, Wi-Fi, Bluetooth, sound, display, physical Arm SoCs,
KVM/Xen, container networking, and unused power-management stacks are excluded.
Virtio block/network/console/9P, overlay/ext4/squashfs, zram, TUN/TAP, and
`tc tbf` remain built in. When the Android app presents the optional
`downloads` 9P mount tag, the rootfs mounts it at `/mnt/downloads`; otherwise
the boot path is unchanged.

KASLR and low-cost userspace hardening remain enabled. The Android QEMU command
line uses `mitigations=off` for the performance-first TCG runtime. Before a
bundle is published, CI boots the exact kernel, initramfs and rootfs with QEMU,
waits for OpenCode health, and exercises both TUN/TAP creation and the TBF
queueing discipline inside the guest.

## Rootfs readiness contract

The guest is not marked ready until:

1. CI has executed and validated the musl OpenCode binary;
2. `libstdc++.so.6`, `libgcc_s.so.1`, and every ELF dependency are present;
3. the boot service starts OpenCode without blocking OpenRC's dependency
   timeout;
4. the ready service confirms that OpenCode remains alive and listens on guest
   TCP port 4096.

The Android host maps guest port 4096 to loopback port 14096.

## License

GPL-2.0-only. See [LICENSE](LICENSE) and [CREDITS.md](CREDITS.md).
