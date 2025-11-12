#!/bin/bash

# ===============================================
# Module Loader for WordPress Import Tool
# ===============================================
#
# Description:
#   Central module loading system that provides core utilities.
#
# Usage:
#   source lib/module_loader.sh
#   load_modules
#

# Get the library directory
# If SCRIPT_DIR is already set by parent script, use it; otherwise calculate from this script's location
if [[ -z "${SCRIPT_DIR:-}" ]]; then
    # Use bash built-in parameter expansion instead of dirname for Flywheel compatibility
    SCRIPT_DIR="${BASH_SOURCE[0]%/*}"
    if [[ "$SCRIPT_DIR" == "${BASH_SOURCE[0]}" ]]; then
        SCRIPT_DIR="."
    fi
    SCRIPT_DIR="$(cd "$SCRIPT_DIR" && pwd)"
    # This script is in lib/, so the main directory is the parent
    LIB_DIR="$SCRIPT_DIR"
    SCRIPT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
else
    # SCRIPT_DIR is set by parent script, use it directly
    LIB_DIR="$SCRIPT_DIR/lib"
fi

# Load core modules
load_core_modules() {
    local core_dir="$LIB_DIR/core"

    # Load utilities
    if [[ -f "$core_dir/utils.sh" ]]; then
        source "$core_dir/utils.sh" 2>/dev/null
    fi
}

# Load utilities modules
load_utilities_modules() {
    local utilities_dir="$LIB_DIR/utilities"

    # Load stage file proxy utilities
    if [[ -f "$utilities_dir/stage_file_proxy.sh" ]]; then
        source "$utilities_dir/stage_file_proxy.sh" 2>/dev/null
    fi

    # Load site links utilities
    if [[ -f "$utilities_dir/site_links.sh" ]]; then
        source "$utilities_dir/site_links.sh" 2>/dev/null
    fi

    # Load revision cleanup utilities
    if [[ -f "$utilities_dir/revision_cleanup.sh" ]]; then
        source "$utilities_dir/revision_cleanup.sh" 2>/dev/null
    fi
}

# Main function to load all modules
load_modules() {
    # Load core modules (includes utils)
    load_core_modules

    # Load utilities modules
    load_utilities_modules

    return 0
}

# Check if modules are already loaded (prevent double loading)
if [[ -z "$WP_IMPORT_MODULES_LOADED" ]]; then
    export WP_IMPORT_MODULES_LOADED="true"

    # Auto-load modules when this script is sourced (only if explicitly requested)
    # This prevents hanging in shell compatibility tests
    if [[ "${BASH_SOURCE[0]}" != "${0}" && "$WP_IMPORT_AUTO_LOAD" == "true" ]]; then
        load_modules
    fi
fi

# Export the loader functions silently
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    {
        export -f load_modules
        export -f load_core_modules
        export -f load_utilities_modules
    } >/dev/null 2>&1
fi
