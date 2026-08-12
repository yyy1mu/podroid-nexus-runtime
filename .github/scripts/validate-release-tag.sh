#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
component="${1:?component name is required}"
actual_tag="${2:-${GITHUB_REF_NAME:-}}"
release_version="$(sed -n 's/^nexusReleaseVersion=//p' "$repo_root/release.properties")"

test -n "$release_version"
test -n "$actual_tag"
expected_tag="v${release_version}-${component}"
if [ "$actual_tag" != "$expected_tag" ]; then
    echo "Release tag mismatch: expected $expected_tag, got $actual_tag" >&2
    exit 1
fi

printf '%s\n' "$release_version"
