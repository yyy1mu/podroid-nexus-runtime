#!/bin/sh
set -eu
WORK_DIR="${WORK_DIR:-/work}"
ROOTFS="${ROOTFS:-$WORK_DIR/rootfs}"
APK_BIN="${APK_BIN:-apk}"
ALPINE_MIRROR="${ALPINE_MIRROR:-https://mirrors.ustc.edu.cn/alpine}"

# ALPINE_VERSION is pinned by the release workflow (full release like 3.24.1).
# Strip the patch component to get the major branch (e.g. 3.24) used in repo URLs.
: "${ALPINE_VERSION:?ALPINE_VERSION must be set (e.g. 3.24.1)}"
ALPINE_BRANCH="${ALPINE_VERSION%.*}"

mkdir -p "$ROOTFS/etc/apk"
cat > "$ROOTFS/etc/apk/repositories" <<EOF
${ALPINE_MIRROR}/v${ALPINE_BRANCH}/main
${ALPINE_MIRROR}/v${ALPINE_BRANCH}/community
EOF

"$APK_BIN" -X "${ALPINE_MIRROR}/v${ALPINE_BRANCH}/main" \
    -X "${ALPINE_MIRROR}/v${ALPINE_BRANCH}/community" \
    -U --allow-untrusted --root "$ROOTFS" --initdb add \
    alpine-base \
    openrc \
    busybox-openrc \
    bash \
    iptables \
    ip6tables \
    nftables \
    bridge-utils \
    iproute2 \
    dropbear dropbear-openrc \
    openssh-sftp-server \
    curl \
    ca-certificates \
    shadow \
    doas sudo \
    gcompat \
    libgcc \
    libstdc++ \
    gzip \
    xz

# Ensure doas and sudo are setuid-root. apk usually does this, but on
# overlay-mounted build hosts it can silently fail.
chmod u+s "$ROOTFS/usr/bin/doas"  2>/dev/null || true
chmod u+s "$ROOTFS/usr/bin/sudo"  2>/dev/null || true

# doas: members of the `wheel` group can become root after entering their
# password (cached for ~5 min). Standard *BSD/Alpine convention.
mkdir -p "$ROOTFS/etc/doas.d"
echo "permit persist :wheel" > "$ROOTFS/etc/doas.d/doas.conf"
chmod 0400 "$ROOTFS/etc/doas.d/doas.conf"

# sudo: equivalent rule for users who prefer sudo over doas.
mkdir -p "$ROOTFS/etc/sudoers.d"
echo "%wheel ALL=(ALL) ALL" > "$ROOTFS/etc/sudoers.d/wheel"
chmod 0440 "$ROOTFS/etc/sudoers.d/wheel"

# Set root password to "podroid" (pre-hashed with openssl).
# We can't run chpasswd inside the aarch64 rootfs from an x86_64 host,
# so write the SHA-512 hash directly into /etc/shadow.
# No fixed -salt: openssl generates a random salt so the stored hash differs
# per build (the password stays the documented default "podroid").
ROOT_HASH=$(openssl passwd -6 podroid)
sed -i "s|^root:[^:]*:|root:${ROOT_HASH}:|" "$ROOTFS/etc/shadow"

# Strip docs/man/locale to shrink squashfs
rm -rf "$ROOTFS/usr/share/man" "$ROOTFS/usr/share/doc" \
       "$ROOTFS/usr/share/locale" "$ROOTFS/usr/share/info"

# Copy custom service files into the rootfs
cp "$WORK_DIR/files/etc/init.d/podroid-bootstrap" "$ROOTFS/etc/init.d/"
cp "$WORK_DIR/files/etc/init.d/podroid-network"   "$ROOTFS/etc/init.d/"
cp "$WORK_DIR/files/etc/init.d/podroid-ready"     "$ROOTFS/etc/init.d/"
cp "$WORK_DIR/files/etc/init.d/podroid-migrate"   "$ROOTFS/etc/init.d/"
cp "$WORK_DIR/files/etc/init.d/podroid-opencode"  "$ROOTFS/etc/init.d/"
chmod +x "$ROOTFS/etc/init.d/podroid-"*

# opencode — AI coding assistant (musl aarch64, runs natively on Alpine).
# Baked into the immutable squashfs lower; bump OPENCODE_VERSION to update.
: "${OPENCODE_VERSION:?OPENCODE_VERSION must be set}"
mkdir -p "$ROOTFS/usr/local/bin"
curl --fail --location --retry 8 --retry-all-errors --retry-delay 5 \
    --output /tmp/opencode.tar.gz \
    "https://github.com/anomalyco/opencode/releases/download/${OPENCODE_VERSION}/opencode-linux-arm64-musl.tar.gz"
tar xzf /tmp/opencode.tar.gz -C /tmp
cp /tmp/opencode "$ROOTFS/usr/local/bin/opencode"
chmod 0755 "$ROOTFS/usr/local/bin/opencode"
rm -f /tmp/opencode.tar.gz /tmp/opencode

mkdir -p "$ROOTFS/etc/conf.d"
cp "$WORK_DIR/files/etc/conf.d/podroid" "$ROOTFS/etc/conf.d/"
mkdir -p "$ROOTFS/etc/podroid"
# Migration scripts dir (seeded with its README; per-version <v>.sh added over time).
mkdir -p "$ROOTFS/etc/podroid/migrations"
cp "$WORK_DIR/files/etc/podroid/migrations/README" "$ROOTFS/etc/podroid/migrations/README"
# System-version stamp: the migration anchor. Baked from the app versionCode at
# build time; compared against /mnt/persist/.podroid/applied-version at boot.
printf '%s\n' "${SYSTEM_VERSION:-0}" > "$ROOTFS/etc/podroid/system-version"
chmod 0644 "$ROOTFS/etc/podroid/system-version"
cp "$WORK_DIR/files/etc/inittab" "$ROOTFS/etc/inittab"
cp "$WORK_DIR/files/etc/rc.conf" "$ROOTFS/etc/rc.conf"

# /etc/profile.d/*.sh — sourced by Alpine's /etc/profile in login shells.
mkdir -p "$ROOTFS/etc/profile.d"
cp "$WORK_DIR/files/etc/profile.d/podroid-color.sh" "$ROOTFS/etc/profile.d/"
chmod 0644 "$ROOTFS/etc/profile.d/podroid-color.sh"

# Hostname (read by podroid-bootstrap via `hostname -F /etc/hostname`)
echo "nexus-runtime" > "$ROOTFS/etc/hostname"
echo "127.0.0.1 localhost nexus-runtime" > "$ROOTFS/etc/hosts"
echo "::1 localhost ip6-localhost" >> "$ROOTFS/etc/hosts"

# Login banner shown by getty before the login prompt.
# \S=Alpine release, \r=kernel, \m=arch, \l=tty
cat > "$ROOTFS/etc/issue" <<'EOF'
Welcome to Nexus Runtime (Alpine \S)
Kernel \r on \m (\l)

  Default login:  root  /  podroid
  Change root password:    passwd
  Create a regular user:   adduser -G wheel <name>
                           (wheel group → can run doas/sudo)

EOF

# Set runlevels via direct symlinks (host is x86_64, can't chroot into aarch64 rootfs to run rc-update).
# rc-update is just `ln -s /etc/init.d/X /etc/runlevels/<level>/X` under the hood.
mkdir -p "$ROOTFS/etc/runlevels/default" "$ROOTFS/etc/runlevels/boot"
# Guard each link so a missing script cannot create a dangling runlevel entry.
for svc in podroid-migrate podroid-bootstrap podroid-network dropbear podroid-opencode podroid-ready; do
    if [ -e "$ROOTFS/etc/init.d/$svc" ]; then
        ln -sf "/etc/init.d/$svc" "$ROOTFS/etc/runlevels/default/$svc"
    else
        echo "WARN: init script /etc/init.d/$svc missing, skipping runlevel symlink"
    fi
done

# Disable services we don't need (initramfs already handles them, or they're noise in the VM)
for svc in hwclock swclock urandom networking sysctl bootmisc syslog; do
    rm -f "$ROOTFS/etc/runlevels/boot/$svc" "$ROOTFS/etc/runlevels/default/$svc"
done
