#!/usr/bin/env bash

# ================================================================
# Version Control Script
# ================================================================
#
# Description:
#   A simple utility script for managing the project version number,
#   which is stored in a separate `VERSION` file relative to the script's
#   location. It allows users to easily display the current version or
#   set a new version number.
#
# Key Features:
# - Read/display the current version from the VERSION file.
# - Validate new version format against semantic versioning (X.Y.Z).
# - Update the VERSION file with a new version number.
#
# Usage:
#   ./version.sh              # Show current version
#   ./version.sh 1.2.0        # Set version to 1.2.0
#
# Dependencies:
# - None (uses only standard bash commands).
#
# ================================================================

# ===============================================
# Main version handling logic
# ===============================================
#
# Description: Executes the primary logic of the script based on the number
#              of command-line arguments provided.
#
# Parameters:
#   - $1 (Optional): The new version string to set (e.g., '1.2.0').
#
# Returns:
#   - 0 (Success) if the version is shown or successfully updated.
#   - 1 (Failure) if the VERSION file is not found, the new version format is invalid, or incorrect usage is detected.
#
# Behavior:
#   - If zero arguments are provided, it attempts to display the content of the $VERSION_FILE.
#   - If one argument is provided, it validates the argument against the semantic version format (X.Y.Z) and overwrites the $VERSION_FILE.
#   - If any other number of arguments is provided, it prints the usage instructions.
#
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
