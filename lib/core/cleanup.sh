#!/usr/bin/env bash

# ================================================================
# Cleanup Utilities Module
# ================================================================
#
# Description:
#   This module provides utility functions for cleaning up temporary files
#   and logs created during the execution of the wp-db-import-and-domain-replacement-tool.
#
# Usage:
#   The `cleanup` function is designed to be used with a Bash `trap` command
#   to ensure that temporary files are removed even if the script exits
#   unexpectedly. It can also be invoked manually if needed.
#
# Dependencies:
#   - Requires Bash version 4.0 or higher for associative arrays and advanced
#     string manipulation.
#   - Relies on standard Unix utilities like `find` and `rm`.
#
# ================================================================

# ===============================================
# Comprehensive Cleanup Function
# ===============================================
#
# Description:
#   Executes a comprehensive cleanup routine designed to safely remove all
#   temporary files generated during the script's execution. This function
#   ensures that no leftover files remain in the `/tmp` directory or other
#   locations used by the tool.
#
# Parameters:
#   - None (Operates on globally defined variables).
#
# Returns:
#   - 0 (Success) always.
#
# Notes:
#   - This function is intended to be executed via a Bash `trap cleanup EXIT`
#     command to ensure cleanup happens even if the script is interrupted or fails.
#   - Temporary files are identified using the script's PID ($$) to avoid
#     accidentally deleting unrelated files.
#
# Example:
#   trap cleanup EXIT
#
cleanup() {
    # 🧹 Comprehensive cleanup of all temporary files created by this script (using PID $$)
    local files_to_remove=(
      "${DB_LOG:-}"
      "${SR_LOG_SINGLE:-}"
      "${REVISION_LOG:-}"
      "${SUBSITE_DATA:-}"
    )

    # Remove explicitly defined log files
    for file in "${files_to_remove[@]}"; do
      if [[ -n "$file" && -f "$file" ]]; then
        rm -f "$file" 2>/dev/null
      fi
    done

    # Clean up multisite logs (any log files starting with /tmp/wp_replace_ that contain the script's PID)
    find /tmp -type f -name "wp_replace_*_$$.log" -delete 2>/dev/null

    # Additional safety: Remove any other temp files that might have been created with this script's PID
    find /tmp -type f -name "*_$$.log" -delete 2>/dev/null
    find /tmp -type f -name "*_$$.csv" -delete 2>/dev/null
    find /tmp -type f -name "*_$$.tmp" -delete 2>/dev/null

    # Clean up any WordPress CLI cache files older than 1 day
    find /tmp -type f -name "wp-cli-*" -mtime +1 -delete 2>/dev/null
}

# Export the function so it can be used in traps
export -f cleanup
