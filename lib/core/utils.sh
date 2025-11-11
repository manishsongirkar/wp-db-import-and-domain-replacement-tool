#!/usr/bin/env bash

# ===============================================
# Core Utilities Library
# ===============================================
#
# Description:
#   Essential utility functions for the WordPress database import tool.
#   Contains only the core functions needed for basic operation.
#

# -----------------------------------------------
# Initialize color constants for terminal output
# -----------------------------------------------
init_colors() {
    # Skip if colors already initialized
    [[ -n "${_COLORS_INITIALIZED:-}" ]] && return 0

    # Check if we should use colors
    # Use colors if:
    # 1. Original stdout/stderr are terminals (check /dev/tty if stdout is redirected)
    # 2. TERM is set and not 'dumb'
    # 3. NO_COLOR environment variable is not set
    local use_colors=false

    if [[ -z "${NO_COLOR:-}" && "${TERM:-}" != "dumb" ]]; then
        if [[ -t 1 ]]; then
            # stdout is a terminal
            use_colors=true
        elif [[ -t 2 ]]; then
            # stderr is a terminal (stdout might be redirected)
            use_colors=true
        elif [[ -e /dev/tty ]]; then
            # Check if we can access the controlling terminal
            if exec 3>/dev/tty 2>/dev/null; then
                use_colors=true
                exec 3>&-
            fi
        fi
    fi

    if [[ "$use_colors" == "true" ]]; then
        # Define ANSI color codes with real escape bytes
        RED=$'\033[0;31m'
        GREEN=$'\033[0;32m'
        YELLOW=$'\033[1;33m'
        BLUE=$'\033[0;34m'
        CYAN=$'\033[0;36m'
        WHITE=$'\033[1;37m'
        BOLD=$'\033[1m'
        RESET=$'\033[0m'
        NC=$'\033[0m'  # No Color alias

        # Additional color variations
        GRAY=$'\033[0;90m'
        LIGHT_RED=$'\033[1;31m'
        LIGHT_GREEN=$'\033[1;32m'
        LIGHT_BLUE=$'\033[1;34m'
        LIGHT_CYAN=$'\033[1;36m'
        LIGHT_GRAY=$'\033[0;37m'
    else
        # No color mode (e.g., when redirected or NO_COLOR is set)
        RED=""; GREEN=""; YELLOW=""; BLUE=""; CYAN=""; WHITE=""
        BOLD=""; RESET=""; NC=""
        GRAY=""; LIGHT_RED=""; LIGHT_GREEN=""
        LIGHT_BLUE=""; LIGHT_CYAN=""; LIGHT_GRAY=""
    fi

    export RED GREEN YELLOW BLUE CYAN WHITE BOLD RESET NC
    export GRAY LIGHT_RED LIGHT_GREEN LIGHT_BLUE LIGHT_CYAN LIGHT_GRAY
    _COLORS_INITIALIZED=true
}

# Automatically initialize colors when sourced
init_colors

# -----------------------------------------------
# Clean strings (remove CR/LF and trim whitespace)
# -----------------------------------------------
clean_string() {
    local s="$1"

    # Remove carriage returns and newlines
    s="${s//$'\r'/}"
    s="${s//$'\n'/}"

    # Trim leading whitespace
    s="${s#"${s%%[![:space:]]*}"}"
    # Trim trailing whitespace
    s="${s%"${s##*[![:space:]]}"}"

    # Use printf to return the cleaned string
    printf "%s" "$s"
}

# -----------------------------------------------
# Spinner with elapsed time (BSD-safe)
# -----------------------------------------------
show_spinner() {
    local pid=$1
    local message=$2
    local delay=0.15
    local spin='|/-\'
    local start_time=$(date +%s)

    printf "  %s " "$message"
    while ps -p "$pid" > /dev/null 2>&1; do
      for i in $(seq 0 3); do
        local current_time=$(date +%s)
        local elapsed=$((current_time - start_time))
        local minutes=$((elapsed / 60))
        local seconds=$((elapsed % 60))

        printf "\r  %s ${CYAN}%s${RESET} (%02d:%02d)" "$message" "${spin:$i:1}" "$minutes" "$seconds"
        sleep $delay
      done
    done
    printf "\r"
    printf "%s" "                                                                                                   " # Clear the line
    printf "\r"
}

# -----------------------------------------------
# Execute a command with optional timeout
# -----------------------------------------------
execute_with_timeout() {
    local timeout_duration="$1"
    shift
    if command -v timeout >/dev/null 2>&1; then
        timeout "$timeout_duration" "$@"
    else
        "$@"
    fi
}

# -----------------------------------------------
# Calculate elapsed time
# -----------------------------------------------
calculate_elapsed_time() {
    local start_time="$1"
    local end_time="${2:-$(date +%s)}"
    local elapsed=$((end_time - start_time))
    local minutes=$((elapsed / 60))
    local seconds=$((elapsed % 60))
    printf "%02d:%02d" "$minutes" "$seconds"
}

# -----------------------------------------------
# Display execution time (requires start_time variable or parameter)
# -----------------------------------------------
display_execution_time() {
    local start_time_param="$1"
    # If parameter provided, use it; otherwise use local/global start_time variable
    local start_time_value="${start_time_param:-${start_time:-}}"

    if [[ -z "$start_time_value" ]]; then
        printf "${YELLOW}⚠️ No start time available for execution time calculation${RESET}\n"
        return 1
    fi

    local end_time=$(date +%s)
    local total_elapsed=$((end_time - start_time_value))
    local total_minutes=$((total_elapsed / 60))
    local total_seconds=$((total_elapsed % 60))
    printf "\n${CYAN}${BOLD}⏱️ Execution Time:${RESET} ${GREEN}%02d:%02d${RESET} (mm:ss)\n" "$total_minutes" "$total_seconds"
}

# -----------------------------------------------
# 📊 Display file size in human-readable format (enhanced)
# Usage: show_file_size "/path/to/file"
# Returns: Prints formatted file size (TB, GB, MB, KB)
# -----------------------------------------------
show_file_size() {
    local file_path="$1"

    if [[ -z "$file_path" ]]; then
        printf "${RED}❌ Error: File path required${RESET}\n"
        return 1
    fi

    if [[ ! -f "$file_path" ]]; then
        printf "${RED}❌ Error: File not found${RESET}\n"
        return 1
    fi

    local file_size_bytes file_size_human
    file_size_bytes=$(stat -f%z "$file_path" 2>/dev/null || stat -c%s "$file_path" 2>/dev/null)

    if [[ -n "$file_size_bytes" ]]; then
        # Convert bytes to human-readable format (TB, GB, MB, KB only)
        if command -v numfmt >/dev/null 2>&1; then
            file_size_human=$(numfmt --to=iec-i --suffix=B "$file_size_bytes")
        elif [[ "$file_size_bytes" -gt 1099511627776 ]]; then
            file_size_human=$(awk "BEGIN {printf \"%.2f TB\", $file_size_bytes/1024/1024/1024/1024}")
        elif [[ "$file_size_bytes" -gt 1073741824 ]]; then
            file_size_human=$(awk "BEGIN {printf \"%.2f GB\", $file_size_bytes/1024/1024/1024}")
        elif [[ "$file_size_bytes" -gt 1048576 ]]; then
            file_size_human=$(awk "BEGIN {printf \"%.2f MB\", $file_size_bytes/1024/1024}")
        elif [[ "$file_size_bytes" -gt 1024 ]]; then
            file_size_human=$(awk "BEGIN {printf \"%.2f KB\", $file_size_bytes/1024}")
        else
            file_size_human=$(awk "BEGIN {printf \"%.2f KB\", $file_size_bytes/1024}")
        fi
        printf "${CYAN}📊 File size:${RESET} %s\n" "$file_size_human"
    else
        printf "${YELLOW}⚠️ Could not determine file size${RESET}\n"
    fi
}

# -----------------------------------------------
# Detect preferred protocol for a URL (http or https)
# -----------------------------------------------
detect_protocol() {
    local url="$1"

    # If URL already has a protocol, preserve it
    if [[ "$url" =~ ^https:// ]]; then
        echo "https://"
    elif [[ "$url" =~ ^http:// ]]; then
        echo "http://"
    else
        # Default to https for modern local development
        echo "https://"
    fi
}

# -----------------------------------------------
# Execute WP-CLI commands safely
# -----------------------------------------------
execute_wp_cli() {
    # Check if WP_COMMAND is set
    if [[ -z "${WP_COMMAND:-}" ]]; then
        local wp_path
        wp_path=$(command -v wp)
        if [[ -z "$wp_path" ]]; then
            printf "${RED}❌ WP-CLI not found in PATH. Please install WP-CLI or check your PATH.${RESET}\n" >&2
            return 1
        fi
        WP_COMMAND="$wp_path"
        export WP_COMMAND
    fi

    # Arguments: WP-CLI command parts (e.g., core is-installed)
    # Execution environment: Export a robust PATH and run the command
    (
        # Prepend common paths (Homebrew, /usr/local) to the current PATH
        export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
        # Disable OPcache warnings that can interfere with output parsing
        export PHP_INI_SCAN_DIR=""
        # Execute the command passed as arguments
        "$WP_COMMAND" "$@"
    )
}

# -----------------------------------------------
# Check if script is sourced
# -----------------------------------------------
is_sourced() {
    [[ "${BASH_SOURCE[0]}" != "${0}" ]]
}

# -----------------------------------------------
# Export functions for sourcing
# -----------------------------------------------
if is_sourced; then
    {
        export -f init_colors
        export -f clean_string
        export -f show_spinner
        export -f execute_with_timeout
        export -f calculate_elapsed_time
        export -f display_execution_time
        export -f show_file_size
        export -f detect_protocol
        export -f execute_wp_cli
        export -f is_sourced
    } 2>/dev/null
fi
