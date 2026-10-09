#!/usr/bin/env bash
# Fails if VERSION differs from the newest released CHANGELOG entry,
# or (when a tag is given) if the tag differs from VERSION.
# Usage: lib/tests/check_version.sh [tag]     e.g. v1.2.0
set -u
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
version="$(tr -d '[:space:]' < "$root/VERSION")"
changelog="$(sed -n 's/^## \[\([0-9][0-9.]*\)\].*/\1/p' "$root/CHANGELOG.md" | head -n 1)"
status=0
if [[ "$version" != "$changelog" ]]; then
    printf "VERSION is %s but the newest CHANGELOG release is %s\n" "$version" "$changelog" >&2
    status=1
fi
if [[ -n "${1:-}" && "${1#v}" != "$version" ]]; then
    printf "Tag %s does not match VERSION %s\n" "$1" "$version" >&2
    status=1
fi
[[ $status -eq 0 ]] && printf "Version OK: %s\n" "$version"
exit $status
