#!/usr/bin/env bash

# Shared helpers for assembling an Alpine aarch64 root directly on the runner.

ALPINE_RELEASE="${ALPINE_RELEASE:-3.24.1}"
ALPINE_BRANCH="${ALPINE_RELEASE%.*}"
ALPINE_MIRROR="${ALPINE_MIRROR:-https://dl-cdn.alpinelinux.org/alpine}"

alpine_prepare_apk() {
    local tools_dir="$1"
    local repository="${ALPINE_MIRROR}/v${ALPINE_BRANCH}/main"
    local index_file="${tools_dir}/APKINDEX.tar.gz"
    local index_contents="${tools_dir}/APKINDEX"
    local package_version

    mkdir -p "$tools_dir"
    curl --fail --location --retry 3 --output "$index_file" \
        "${repository}/x86_64/APKINDEX.tar.gz"
    tar -xOzf "$index_file" APKINDEX > "$index_contents"
    package_version="$(
        awk '
            /^P:apk-tools-static$/ { found = 1; next }
            found && /^V:/ { version = substr($0, 3); found = 0 }
            /^$/ { found = 0 }
            END { print version }
        ' "$index_contents"
    )"
    test -n "$package_version"

    curl --fail --location --retry 3 --output "${tools_dir}/apk-tools-static.apk" \
        "${repository}/x86_64/apk-tools-static-${package_version}.apk"
    tar --ignore-zeros --warning=no-unknown-keyword \
        -xzf "${tools_dir}/apk-tools-static.apk" \
        -C "$tools_dir" sbin/apk.static
    chmod +x "${tools_dir}/sbin/apk.static"
    ALPINE_APK="${tools_dir}/sbin/apk.static"
}

alpine_extract_aarch64_root() {
    local rootfs="$1"
    local archive="${rootfs}.tar.gz"

    mkdir -p "$rootfs"
    curl --fail --location --retry 3 --output "$archive" \
        "${ALPINE_MIRROR}/v${ALPINE_BRANCH}/releases/aarch64/alpine-minirootfs-${ALPINE_RELEASE}-aarch64.tar.gz"
    sudo tar -xzf "$archive" -C "$rootfs"
    rm -f "$archive"
    sudo mkdir -p "$rootfs/etc/apk"
    printf '%s\n' aarch64 | sudo tee "$rootfs/etc/apk/arch" >/dev/null
    printf '%s\n' \
        "${ALPINE_MIRROR}/v${ALPINE_BRANCH}/main" \
        "${ALPINE_MIRROR}/v${ALPINE_BRANCH}/community" \
        | sudo tee "$rootfs/etc/apk/repositories" >/dev/null
}

alpine_apk_add() {
    local rootfs="$1"
    shift
    sudo "$ALPINE_APK" \
        --arch aarch64 \
        --root "$rootfs" \
        --initdb \
        --allow-untrusted \
        --repositories-file "$rootfs/etc/apk/repositories" \
        --update-cache \
        add "$@"
}
