# Credits and third-party components

Nexus Runtime is derived from [Podroid](https://github.com/ExTV/Podroid),
created by ExTV and its contributors. The Git history is retained so the
origin of inherited code remains auditable.

The release bundle is assembled from these upstream projects. Each component
remains under its own license:

- [Linux](https://kernel.org/) — AArch64 guest kernel, GPL-2.0.
- [Alpine Linux](https://alpinelinux.org/) — guest userspace, per-package
  licenses.
- [OpenCode](https://github.com/anomalyco/opencode) — AI coding server.
- [QEMU](https://www.qemu.org/) — Android ARM64 machine emulator, GPL-2.0 and
  other licenses documented upstream.
- [libslirp](https://gitlab.freedesktop.org/slirp/libslirp) — QEMU user-mode
  networking, BSD-3-Clause.
- [libucontext](https://github.com/kaniini/libucontext) — QEMU coroutine
  support on Android Bionic, ISC.
- [PCRE2](https://github.com/PCRE2Project/pcre2),
  [libffi](https://github.com/libffi/libffi),
  [GLib](https://gitlab.gnome.org/GNOME/glib),
  [Pixman](https://gitlab.freedesktop.org/pixman/pixman), and
  [attr](https://savannah.nongnu.org/projects/attr/) — QEMU build
  dependencies.
- Android SDK and NDK — Android cross-compilation toolchain.

The runtime deliberately does not ship the Podroid Android UI, AVF backend,
VNC desktop, audio stack, USB passthrough, or host bridge. See each upstream
project for its complete copyright and license notices.
