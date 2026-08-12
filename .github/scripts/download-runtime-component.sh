#!/usr/bin/env bash
set -euo pipefail

component="${1:?component name is required}"
tag="${2:?component tag is required}"
destination="${3:?destination directory is required}"
archive="nexus-${component}-${tag}.tar.zst"
work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"' EXIT

command -v gh >/dev/null
command -v zstd >/dev/null

gh release download "$tag" \
    --pattern "${archive}*" \
    --dir "$work_dir"

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
