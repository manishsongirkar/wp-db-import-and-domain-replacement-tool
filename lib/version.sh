#!/bin/bash

# Simple script to get/set version
# Usage:
#   ./version.sh              # Show current version
#   ./version.sh 1.2.0         # Set version to 1.2.0

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VERSION_FILE="$SCRIPT_DIR/../VERSION"

if [[ $# -eq 0 ]]; then
    # Show current version
    if [[ -f "$VERSION_FILE" ]]; then
        cat "$VERSION_FILE"
    else
        echo "VERSION file not found"
        exit 1
    fi
elif [[ $# -eq 1 ]]; then
    # Set new version
    NEW_VERSION="$1"

    # Basic version format validation (semantic versioning: X.Y.Z)
    if [[ "$NEW_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        echo "$NEW_VERSION" > "$VERSION_FILE"
        echo "Version updated to: $NEW_VERSION"
    else
        echo "Error: Version must be in format X.Y.Z (e.g., 1.2.0)"
        exit 1
    fi
else
    echo "Usage: $0 [version]"
    echo "  $0           # Show current version"
    echo "  $0 1.2.0     # Set version to 1.2.0"
    exit 1
fi
