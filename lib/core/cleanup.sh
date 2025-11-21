#!/usr/bin/env bash

# ================================================================
# Cleanup Utilities Module
# ================================================================
#
# Description:
#   Provides functions for cleaning up temporary files and logs created
#   during the execution of the tool.
#
# ================================================================

# ===============================================
# Comprehensive Cleanup Function
# ===============================================
#
# Description: This function executes a comprehensive cleanup routine designed to safely
#              remove all temporary files generated during the script's execution.
#              It is primarily intended to be executed via a Bash `trap cleanup EXIT`
#              command to ensure cleanup happens even if the script is interrupted or fails.
#
# Parameters:
#   - None (Operates on globally defined variables).
#
# Returns:
#   - 0 (Success) always.
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
