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

Only tags matching `v*` start a build. Components are independently versioned:

- `v*-rootfs` publishes Alpine and OpenCode;
- `v*-boot` publishes the matching kernel and initramfs;
- `v*-qemu` publishes Android QEMU, slirp, firmware, and the launcher;
- `v*-bundle` reads `runtime.lock` and assembles those immutable releases
  without compiling native code again.

Every component archive has both an archive checksum and an internal manifest.
The assembled runtime records all three component tags in `runtime.properties`,
so an APK is reproducible without relying on short-lived Actions caches. Heavy
native builds are never required by the Nexus app repository.

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
