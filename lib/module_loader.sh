#!/bin/bash

# ===============================================
# Module Loader for WordPress Import Tool
# ===============================================
#
# Description:
#   Central module loading system that provides core utilities.
#   Enhanced with bash version compatibility for 3.2, 4.x, and 5.x.
#
# Usage:
#   source lib/module_loader.sh
#   load_modules
#

# Initialize bash compatibility detection early
BASH_COMPAT_INITIALIZED=""

# Get the library directory
# Enhanced cross-shell compatibility with robust fallback support
# If SCRIPT_DIR is already set by parent script, use it; otherwise detect automatically
if [[ -z "${SCRIPT_DIR:-}" ]]; then
    # Try multiple detection methods in order of reliability
    source_file=""
    detection_method=""

    # Method 1: Bash BASH_SOURCE (most reliable for bash)
    if [[ -n "${BASH_SOURCE:-}" ]] && [[ -n "${BASH_SOURCE[0]:-}" ]]; then
        source_file="${BASH_SOURCE[0]}"
        detection_method="bash_source"
    # Method 2: Check if we're in the right directory structure
    elif [[ -f "./lib/module_loader.sh" ]]; then
        source_file="./lib/module_loader.sh"
        detection_method="cwd_relative"
    # Method 3: Check if we're in lib directory
    elif [[ -f "./module_loader.sh" ]]; then
        source_file="./module_loader.sh"
        detection_method="cwd_direct"
    # Method 4: Use $PWD as base and try common patterns
    elif [[ -f "$PWD/lib/module_loader.sh" ]]; then
        source_file="$PWD/lib/module_loader.sh"
        detection_method="pwd_lib"
    # Method 5: Last resort - assume current location
    else
        source_file="lib/module_loader.sh"
        detection_method="fallback"
    fi

    # Extract directory from source file
    SCRIPT_DIR="${source_file%/*}"
    if [[ "$SCRIPT_DIR" == "$source_file" ]]; then
        SCRIPT_DIR="."
    fi

    # Convert to absolute path safely
    if [[ -d "$SCRIPT_DIR" ]]; then
        SCRIPT_DIR="$(cd "$SCRIPT_DIR" 2>/dev/null && pwd)"
    else
        # If directory doesn't exist, try PWD/lib
        SCRIPT_DIR="$PWD/lib"
    fi

    # Determine LIB_DIR based on where we think we are
    if [[ "$detection_method" == "cwd_direct" ]] || [[ "$SCRIPT_DIR" == *"/lib" ]]; then
        # We're in the lib directory
        LIB_DIR="$SCRIPT_DIR"
        SCRIPT_DIR="$(cd "$SCRIPT_DIR/.." 2>/dev/null && pwd)" || SCRIPT_DIR="${LIB_DIR%/lib}"
    else
        # We're in the project root
        LIB_DIR="$SCRIPT_DIR/lib"
    fi
else
    # SCRIPT_DIR is set by parent script, use it directly
    LIB_DIR="$SCRIPT_DIR/lib"
fi

# Final validation and emergency fallback
if [[ ! -d "$LIB_DIR" ]] || [[ ! -f "$LIB_DIR/module_loader.sh" ]]; then
    # Try various emergency fallback strategies
    fallback_found=false

    # Strategy 1: We're in project root
    if [[ -f "$PWD/lib/module_loader.sh" ]]; then
        SCRIPT_DIR="$PWD"
        LIB_DIR="$PWD/lib"
        fallback_found=true
    # Strategy 2: We're in lib directory
    elif [[ -f "$PWD/module_loader.sh" ]]; then
        LIB_DIR="$PWD"
        SCRIPT_DIR="$(cd "$PWD/.." 2>/dev/null && pwd)" || SCRIPT_DIR="$PWD/.."
        fallback_found=true
    # Strategy 3: Check parent directories for lib/module_loader.sh
    elif [[ -f "../lib/module_loader.sh" ]]; then
        SCRIPT_DIR="$(cd ".." 2>/dev/null && pwd)" || SCRIPT_DIR="$PWD/.."
        LIB_DIR="$SCRIPT_DIR/lib"
        fallback_found=true
    fi

    # If all fallbacks failed, show error but don't exit (to avoid breaking existing setups)
    if [[ "$fallback_found" != true ]]; then
        echo "⚠️  Warning: Cannot auto-detect module directory. Some features may not work." >&2
        echo "   Expected to find lib/module_loader.sh" >&2
        echo "   Current working directory: $PWD" >&2
        echo "   Detected SCRIPT_DIR: ${SCRIPT_DIR:-'unset'}" >&2
        echo "   Detected LIB_DIR: ${LIB_DIR:-'unset'}" >&2
        # Set reasonable defaults to prevent complete failure
        SCRIPT_DIR="${SCRIPT_DIR:-$PWD}"
        LIB_DIR="${LIB_DIR:-$PWD/lib}"
    fi
fi

# Load core modules with bash compatibility
load_core_modules() {
    local core_dir="$LIB_DIR/core"

    # Load utilities first (contains bash compatibility functions)
    if [[ -f "$core_dir/utils.sh" ]]; then
        source "$core_dir/utils.sh" 2>/dev/null

        # Initialize bash compatibility after utils is loaded
        if [[ -z "$BASH_COMPAT_INITIALIZED" ]]; then
            detect_bash_version 2>/dev/null || true
            BASH_COMPAT_INITIALIZED="true"

            # Optional: Show version info for debugging
            if [[ "${BASH_DEBUG_MODULES:-}" == "true" ]]; then
                printf "🔧 Bash compatibility initialized: %s.%s\n" \
                    "${BASH_VERSION_MAJOR:-3}" "${BASH_VERSION_MINOR:-2}" >&2
            fi
        fi
    fi

    # Load validation module (for testing purposes)
    if [[ -f "$core_dir/validation.sh" ]]; then
        source "$core_dir/validation.sh" 2>/dev/null
    fi
    
    # Load WordPress detection module
    if [[ -f "$core_dir/wp_detection.sh" ]]; then
        source "$core_dir/wp_detection.sh" 2>/dev/null
    fi
}

# Load configuration modules
load_config_modules() {
    local config_dir="$LIB_DIR/config"

    # Load configuration manager
    if [[ -f "$config_dir/config_manager.sh" ]]; then
        source "$config_dir/config_manager.sh" 2>/dev/null
    fi

    # Load config integration utilities
    if [[ -f "$config_dir/integration.sh" ]]; then
        source "$config_dir/integration.sh" 2>/dev/null
    fi
}

# Load database modules
load_database_modules() {
    local database_dir="$LIB_DIR/database"

    # Load search and replace utilities
    if [[ -f "$database_dir/search_replace.sh" ]]; then
        source "$database_dir/search_replace.sh" 2>/dev/null
    fi
}

# Load utilities modules
load_utilities_modules() {
    local utilities_dir="$LIB_DIR/utilities"

    # Load gitignore manager utilities (load first as dependency for stage_file_proxy)
    if [[ -f "$utilities_dir/gitignore_manager.sh" ]]; then
        source "$utilities_dir/gitignore_manager.sh" 2>/dev/null
    fi

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

    # Load configuration modules
    load_config_modules

    # Load database modules
    load_database_modules

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

# Export the loader functions silently (cross-shell compatible)
# Only export if this script is being sourced (not executed directly)
# Use a more portable check that works across different shells
if [[ "$0" != *"module_loader.sh" ]] || [[ -n "${ZSH_VERSION:-}" ]] || [[ -n "${BASH_SOURCE:-}" ]]; then
    {
        export -f load_modules 2>/dev/null || true
        export -f load_core_modules 2>/dev/null || true
        export -f load_config_modules 2>/dev/null || true
        export -f load_database_modules 2>/dev/null || true
        export -f load_utilities_modules 2>/dev/null || true
    } >/dev/null 2>&1
fi
