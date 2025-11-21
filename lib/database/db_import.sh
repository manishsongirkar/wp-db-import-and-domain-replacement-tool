#!/usr/bin/env bash

# ================================================================
# Database Import Module
# ================================================================
#
# Description:
#   Handles the core database import functionality using WP-CLI.
#   Includes robust execution methods and progress indication.
#
# ================================================================

# ===============================================
# Perform Database Import
# ===============================================
#
# Description: Imports a SQL file into the WordPress database.
#
# Parameters:
#   - $1: Path to the SQL file.
#   - $2: Path to the log file (optional, defaults to global DB_LOG or /tmp/wp_db_import.log).
#
# Returns:
#   - 0 (Success) if import succeeds.
#   - 1 (Failure) if import fails.
#
perform_db_import() {
    local sql_file="$1"
    local log_file="${2:-${DB_LOG:-/tmp/wp_db_import.log}}"

    if [[ -z "$sql_file" ]]; then
        printf "${RED}❌ Error: No SQL file specified for import.${RESET}\n"
        return 1
    fi

    printf "\n${CYAN}⏳ Importing database...${RESET}\n"
    local import_start_time=$(date +%s)

    # Try robust command execution with fallbacks for restricted environments
    local import_success=false

    # Ensure WP_COMMAND is available
    local wp_cmd="${WP_COMMAND:-wp}"

    # Method 1: Try with enhanced PATH in subshell (most compatible)
    if command -v sh >/dev/null 2>&1; then
        # We use a subshell to run the import in background and show a spinner
        # We need to export PATH inside the sh command string
        if /bin/sh -c "(export PATH=\"/opt/homebrew/bin:/usr/local/bin:$PATH\"; \"$wp_cmd\" db import \"$sql_file\") &> \"$log_file\"" & then
            local spinner_pid=$!
            show_spinner $spinner_pid "Importing"
            wait $spinner_pid && import_success=true
        fi
    fi

    # Method 2: Fallback for restricted environments - direct execution
    if [[ "$import_success" = false ]]; then
        printf "${YELLOW}Fallback: Direct WP-CLI execution...${RESET}\n"
        if execute_wp_cli db import "$sql_file" &> "$log_file"; then
            import_success=true
        fi
    fi

    # Check if import was successful
    if [[ "$import_success" = false ]]; then
        printf "${RED}❌ Database import failed. Check %s for details.${RESET}\n" "$log_file"
        return 1
    fi

    # Calculate elapsed time
    local import_end_time=$(date +%s)
    local import_elapsed=$((import_end_time - import_start_time))
    local import_minutes=$((import_elapsed / 60))
    local import_seconds=$((import_elapsed % 60))

    printf "${GREEN}✅ Database import successful! ${CYAN}[Completed in %02d:%02d]${RESET}\n\n" "$import_minutes" "$import_seconds"
    return 0
}

# Export function
export -f perform_db_import
