#!/usr/bin/env bash
set -euo pipefail

component="${1:?component name is required}"
tag="${2:?component tag is required}"
destination="${3:?destination directory is required}"
archive="nexus-${component}-${tag}.tar.zst"
repository="${NEXUS_RUNTIME_REPOSITORY:-${GITHUB_REPOSITORY:-}}"
work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"' EXIT

command -v gh >/dev/null
command -v zstd >/dev/null
command -v jq >/dev/null

gh_retry() {
    local attempt=1
    local delay_seconds=2
    while ! gh "$@"; do
        if [ "$attempt" -ge 5 ]; then
            return 1
        fi
        echo "GitHub request failed; retrying in ${delay_seconds}s (${attempt}/5)" >&2
        sleep "$delay_seconds"
        attempt=$((attempt + 1))
        delay_seconds=$((delay_seconds * 2))
    done
}

gh_api_retry() {
    local response_file
    local attempt=1
    local delay_seconds=2
    response_file="$(mktemp "$work_dir/gh-api.XXXXXX")"
    while ! gh api "$@" > "$response_file"; do
        if [ "$attempt" -ge 5 ]; then
            return 1
        fi
        echo "GitHub API request failed; retrying in ${delay_seconds}s (${attempt}/5)" >&2
        sleep "$delay_seconds"
        attempt=$((attempt + 1))
        delay_seconds=$((delay_seconds * 2))
    done
    command cat "$response_file"
}

gh_asset_retry() {
    local asset_id="$1"
    local destination_file="$2"
    local attempt=1
    local delay_seconds=2
    while ! gh api \
        -H 'Accept: application/octet-stream' \
        "repos/$repository/releases/assets/$asset_id" \
        > "$destination_file"; do
        if [ "$attempt" -ge 5 ]; then
            return 1
        fi
        echo "GitHub asset download failed; retrying in ${delay_seconds}s (${attempt}/5)" >&2
        sleep "$delay_seconds"
        attempt=$((attempt + 1))
        delay_seconds=$((delay_seconds * 2))
    done
}

if [ -z "$repository" ]; then
    repository="$(gh_retry repo view --json nameWithOwner --jq .nameWithOwner)"
fi

if [[ "$tag" == *-bundle ]]; then
    bundle_archive="nexus-runtime-${tag}.tar.zst"
    gh_retry release download "$tag" \
        --repo "$repository" \
        --pattern "${bundle_archive}*" \
        --clobber \
        --dir "$work_dir"
    (
        cd "$work_dir"
        sha256sum --check "$bundle_archive.sha256"
    )
    mkdir -p "$work_dir/runtime"
    tar --zstd -xf "$work_dir/$bundle_archive" -C "$work_dir/runtime"
    runtime="$work_dir/runtime/nexus-runtime"
    (
        cd "$runtime"
        sha256sum --check SHA256SUMS
    )
    component_dir="$destination/nexus-$component"
    mkdir -p "$component_dir"
    case "$component" in
        rootfs)
            install -m 0644 "$runtime/assets/vm/alpine-rootfs.squashfs" "$component_dir/"
            version_key=runtimeSystemVersion
            extra_properties="$(
                sed -n \
                    -e 's/^runtimeOpenCodeVersion=/runtimeOpenCodeVersion=/p' \
                    -e 's/^runtimeAlpineVersion=/runtimeAlpineVersion=/p' \
                    "$runtime/runtime.properties"
            )"
            ;;
        boot)
            install -m 0644 \
                "$runtime/assets/vm/vmlinuz-virt" \
                "$runtime/assets/vm/initrd.img" \
                "$component_dir/"
            version_key=runtimeKernelVersion
            extra_properties=""
            ;;
        qemu)
            install -m 0755 \
                "$runtime/jniLibs/arm64-v8a/libqemu-system-aarch64.so" \
                "$runtime/jniLibs/arm64-v8a/libslirp.so" \
                "$runtime/jniLibs/arm64-v8a/libpodroid-launcher.so" \
                "$component_dir/"
            cp -R "$runtime/assets/vm/qemu" "$component_dir/"
            version_key=runtimeQemuVersion
            extra_properties=""
            ;;
        *)
            echo "Unknown runtime component: $component" >&2
            exit 1
            ;;
    esac
    commit="$(sed -n 's/^commit=//p' "$runtime/runtime.properties")"
    version="$(sed -n "s/^${version_key}=//p" "$runtime/runtime.properties")"
    printf '%s\n' \
        "component=$component" \
        "tag=$tag" \
        "commit=$commit" \
        "$version_key=$version" \
        "$extra_properties" \
        > "$component_dir/component.properties"
    (
        cd "$component_dir"
        find . -type f ! -name SHA256SUMS -print0 | sort -z | \
            xargs -0 sha256sum > SHA256SUMS
    )
    exit 0
fi

# Component releases are drafts so the public Releases page only shows the
# complete runtime bundle. Resolve the authenticated release and assets via
# the API because the tag endpoint intentionally hides draft releases.
release_id="$(
    gh_api_retry --paginate "repos/$repository/releases?per_page=100" \
        | jq -r --arg tag "$tag" '.[] | select(.tag_name == $tag) | .id' \
        | head -n 1
)"
test -n "$release_id"

for asset_name in "$archive" "$archive.sha256"; do
    asset_id="$(
        gh_api_retry "repos/$repository/releases/$release_id" \
            | jq -r --arg name "$asset_name" \
                '.assets[] | select(.name == $name) | .id' \
            | head -n 1
    )"
    test -n "$asset_id"
    gh_asset_retry "$asset_id" "$work_dir/$asset_name"
done

(
    cd "$work_dir"
    sha256sum --check "$archive.sha256"
)

mkdir -p "$destination"
tar --zstd -xf "$work_dir/$archive" -C "$destination"
component_dir="$destination/nexus-$component"
test -d "$component_dir"
grep -Fxq "component=$component" "$component_dir/component.properties"
grep -Fxq "tag=$tag" "$component_dir/component.properties"
(
    cd "$component_dir"
    sha256sum --check SHA256SUMS
)
