#!/usr/bin/env bash

# ===============================================
# Core Utilities Library
# ===============================================
#
# Description:
#   Essential utility functions for the WordPress database import tool.
#   Contains core functions for terminal output, execution, file handling,
#   WordPress detection, and robust Bash version compatibility.
#
# Features:
#   - Dynamic color initialization.
#   - Cross-platform execution helpers (spinner, timeout, timing).
#   - Bash version detection and feature compatibility fallbacks (associative arrays, case conversion).
#   - WordPress environment detection (root, multisite, table prefix).
#
# ===============================================

# ===============================================
# Init Colors
# ===============================================
#
# Description: Initializes global variables with ANSI color codes if the terminal supports them.
#
# Parameters:
#	- None
#
# Returns:
#	- Implicitly exports global color variables (RED, GREEN, RESET, etc.).
#	- Returns 0 (Success) always.
#
# Behavior:
#	- Checks TERM variable and redirection status to intelligently decide whether to use colors.
#	- Sets all color variables to empty strings if colors are disabled.
#
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

# ===============================================
# Clean String
# ===============================================
#
# Description: Removes carriage returns and newlines, and trims leading/trailing whitespace from a string.
#
# Parameters:
#	- $1: The input string.
#
# Returns:
#	- The cleaned string (echoed).
#
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

# ===============================================
# Show Spinner
# ===============================================
#
# Description: Displays a running terminal spinner with elapsed time next to a message until the given PID terminates.
#
# Parameters:
#	- $1: The Process ID (PID) of the background task to monitor.
#	- $2: The message to display alongside the spinner.
#
# Returns:
#	- Prints the spinner and elapsed time directly to the terminal.
#
# Behavior:
#	- Uses `ps -p` to monitor the PID.
#	- Works on both Linux and BSD-based systems (like macOS).
#
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

# ===============================================
# Execute With Timeout
# ===============================================
#
# Description: Executes a command, applying a timeout if the 'timeout' utility is available.
#
# Parameters:
#	- $1: Timeout duration (e.g., "10s").
#	- $@: The command and its arguments to execute.
#
# Returns:
#	- The exit code and output of the executed command.
#
# Behavior:
#	- Gracefully falls back to running the command directly if `timeout` is not found.
#
execute_with_timeout() {
    local timeout_duration="$1"
    shift
    if command -v timeout >/dev/null 2>&1; then
        timeout "$timeout_duration" "$@"
    else
        "$@"
    fi
}

# ===============================================
# Calculate Elapsed Time
# ===============================================
#
# Description: Calculates the difference between two Unix timestamps and formats it as MM:SS.
#
# Parameters:
#	- $1: The start time (Unix timestamp).
#	- $2: Optional. The end time (Unix timestamp). Defaults to current time.
#
# Returns:
#	- The elapsed time formatted as MM:SS (echoed).
#
calculate_elapsed_time() {
    local start_time="$1"
    local end_time="${2:-$(date +%s)}"
    local elapsed=$((end_time - start_time))
    local minutes=$((elapsed / 60))
    local seconds=$((elapsed % 60))
    printf "%02d:%02d" "$minutes" "$seconds"
}

# ===============================================
# Timer Management
# ===============================================
# Global variables for timer state
_TIMER_TOTAL_START=0
_TIMER_SEGMENT_START=0
_TIMER_EXECUTION_DURATION=0

init_script_timer() {
    _TIMER_TOTAL_START=$(date +%s)
    _TIMER_SEGMENT_START=$(date +%s)
    _TIMER_EXECUTION_DURATION=0
}

pause_script_timer() {
    local now=$(date +%s)
    local segment_duration=$((now - _TIMER_SEGMENT_START))
    _TIMER_EXECUTION_DURATION=$((_TIMER_EXECUTION_DURATION + segment_duration))
}

resume_script_timer() {
    _TIMER_SEGMENT_START=$(date +%s)
}

get_execution_duration() {
    echo "$_TIMER_EXECUTION_DURATION"
}

get_total_start_time() {
    echo "$_TIMER_TOTAL_START"
}

# ===============================================
# Display Execution Time
# ===============================================
#
# Description: Calculates and displays the total execution time since a specified start time.
#
# Parameters:
#	- $1: Optional. The start time (Unix timestamp). Uses global `_TIMER_TOTAL_START` if omitted.
#
# Returns:
#	- Prints the formatted execution time (MM:SS) to stdout.
#	- Returns 1 if no start time is provided.
#
display_execution_time() {
    local start_time_param="$1"
    # If parameter provided, use it; otherwise use global variable
    local start_time_value="${start_time_param:-${_TIMER_TOTAL_START:-}}"

    if [[ -z "$start_time_value" || "$start_time_value" -eq 0 ]]; then
        # Try to use date if not initialized
        start_time_value=$(date +%s)
    fi

    local end_time=$(date +%s)
    local total_elapsed=$((end_time - start_time_value))
    local total_minutes=$((total_elapsed / 60))
    local total_seconds=$((total_elapsed % 60))
    printf "\n${CYAN}${BOLD}⏱️ Execution Time:${RESET} ${GREEN}%02d:%02d${RESET} (mm:ss)\n" "$total_minutes" "$total_seconds"
}

# ===============================================
# Show File Size
# ===============================================
#
# Description: Calculates the size of a file and prints it in human-readable format (e.g., 1.5 GB).
#
# Parameters:
#	- $1: The path to the file.
#
# Returns:
#	- Prints the formatted file size to stdout.
#	- Returns 1 on error (file not found/unreadable).
#
# Behavior:
#	- Prefers the `numfmt` utility if available for accurate IEC (1024-based) conversion.
#	- Falls back to `awk` and `stat` for cross-platform support.
#
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
        printf "${YELLOW}⚠️  Could not determine file size${RESET}\n"
    fi
}

# ===============================================
# Detect Main Site
# ===============================================
#
# Description: Detects the blog ID and URL of the primary site (Blog ID 1 or the root site) in a WordPress installation.
#
# Parameters:
#	- $1: Is it multisite? ("yes" or "no").
#	- $2: A fallback domain/URL to use for WP-CLI commands and final URL fallback.
#
# Returns:
#	- Primary site info in the format: "blog_id|site_url" (echoed).
#	- Prints debug and status messages to stderr.
#
# Behavior:
#	- For single sites, simply returns blog ID 1 and the site URL.
#	- For multisite, attempts multiple detection methods (database query, WP-CLI site list, network admin URL, WordPress functions) with timeouts.
#	- Requires `execute_wp_cli` and `execute_with_timeout` to be available.
#
detect_main_site() {
    local is_multisite="$1"
    local fallback_domain="$2"  # Used for WP-CLI --url parameter

    # For single site, always return site URL from wp_options
    if [[ "$is_multisite" != "yes" ]]; then
        local site_url
        # Add timeout protection for WP-CLI commands using the existing utility
        site_url=$(execute_with_timeout 10 execute_wp_cli option get siteurl 2>/dev/null || echo "")
        echo "1|$site_url"  # Format: blog_id|site_url
        return 0
    fi

    # For multisite, try multiple detection methods with timeouts
    local main_site_blog_id=""
    local main_site_url=""
    local detection_method=""

    # Quick check if WP-CLI is working at all
    if ! execute_with_timeout 5 execute_wp_cli core version --url="$fallback_domain" >/dev/null 2>&1; then
        printf "${YELLOW}⚠️  WP-CLI not responding or no WordPress installation, using defaults${RESET}\n" >&2
        echo "1|$fallback_domain"
        return 0
    fi

    # Check if this is actually a multisite installation
    local is_multisite_check
    is_multisite_check=$(execute_with_timeout 5 execute_wp_cli eval 'echo is_multisite() ? "yes" : "no";' --url="$fallback_domain" 2>/dev/null || echo "no")
    if [[ "$is_multisite_check" != "yes" ]]; then
        printf "${YELLOW}⚠️  Not actually a multisite installation, treating as single site${RESET}\n" >&2
        local site_url
        site_url=$(execute_with_timeout 10 execute_wp_cli option get siteurl --url="$fallback_domain" 2>/dev/null || echo "$fallback_domain")
        echo "1|$site_url"
        return 0
    fi

    # === METHOD 1: Direct database queries (works on most environments) ===
    main_site_blog_id=$(execute_with_timeout 10 execute_wp_cli db query "SELECT blog_id FROM wp_site WHERE id = 1 LIMIT 1;" --skip-column-names --silent --url="$fallback_domain" 2>/dev/null || echo "")

    if [[ -n "$main_site_blog_id" && "$main_site_blog_id" != "0" ]]; then
        detection_method="database-wp_site"
        printf "${GREEN}✅ Found main site via wp_site table${RESET}\n" >&2
    else
        # Try wp_blogs table fallback
        main_site_blog_id=$(execute_with_timeout 10 execute_wp_cli db query "SELECT blog_id FROM wp_blogs WHERE path = '/' ORDER BY blog_id ASC LIMIT 1;" --skip-column-names --silent --url="$fallback_domain" 2>/dev/null || echo "")
        if [[ -n "$main_site_blog_id" && "$main_site_blog_id" != "0" ]]; then
            detection_method="database-wp_blogs"
            printf "${GREEN}✅ Found main site via wp_blogs table${RESET}\n" >&2
        fi
    fi

    # === METHOD 2: WP-CLI site list (Flywheel-friendly) ===
    if [[ -z "$main_site_blog_id" ]]; then

        # Get site list and find main site by path
        local site_data
        site_data=$(execute_with_timeout 10 execute_wp_cli site list --fields=blog_id,path --format=csv --url="$fallback_domain" 2>/dev/null || echo "")

        if [[ -n "$site_data" ]]; then
            # Parse CSV to find site with path='/'
            while IFS=, read -r blog_id site_path; do
                if [[ "$blog_id" == "blog_id" ]]; then continue; fi  # Skip header
                if [[ -n "$blog_id" && -n "$site_path" ]]; then
                    site_path=$(clean_string "$site_path")
                    if [[ "$site_path" == "/" ]]; then
                        main_site_blog_id=$(clean_string "$blog_id")
                        detection_method="wp-cli-site-list"
                        printf "${GREEN}✅ Found main site via WP-CLI site list${RESET}\n" >&2
                        break
                    fi
                fi
            done <<< "$site_data"
        fi
    fi

    # === METHOD 3: Network admin URL detection (Flywheel-friendly) ===
    if [[ -z "$main_site_blog_id" ]]; then
        printf "${YELLOW}⚠️  Site list failed, trying network admin detection...${RESET}\n" >&2

        # Try to get network admin URL which typically points to main site
        local network_admin_url
        network_admin_url=$(execute_with_timeout 10 execute_wp_cli eval "echo network_admin_url();" --url="$fallback_domain" 2>/dev/null || echo "")

        if [[ -n "$network_admin_url" ]]; then
            # Extract domain from network admin URL for main site detection
            local network_domain
            network_domain="${network_admin_url#http://}"
            network_domain="${network_domain#https://}"
            network_domain="${network_domain%%/*}"

            if [[ -n "$network_domain" ]]; then
                # Try to find blog_id by matching domain
                local site_data
                site_data=$(execute_with_timeout 10 execute_wp_cli site list --fields=blog_id,url --format=csv --url="$fallback_domain" 2>/dev/null || echo "")

                while IFS=, read -r blog_id site_url; do
                    if [[ "$blog_id" == "blog_id" ]]; then continue; fi  # Skip header
                    if [[ -n "$blog_id" && -n "$site_url" ]]; then
                        local site_domain
                        site_domain="${site_url#http://}"
                        site_domain="${site_domain#https://}"
                        site_domain="${site_domain%%/*}"

                        if [[ "$site_domain" == "$network_domain" ]]; then
                            main_site_blog_id=$(clean_string "$blog_id")
                            detection_method="wp-cli-network-admin"
                            printf "${GREEN}✅ Found main site via network admin URL${RESET}\n" >&2
                            break
                        fi
                    fi
                done <<< "$site_data"
            fi
        fi
    fi

    # === METHOD 4: WordPress constants/eval (Universal fallback) ===
    if [[ -z "$main_site_blog_id" ]]; then
        printf "${YELLOW}⚠️  Advanced detection failed, using WordPress constants...${RESET}\n" >&2

        # Try to get main site ID using WordPress constants/functions
        main_site_blog_id=$(execute_with_timeout 10 execute_wp_cli eval "echo get_main_site_id();" --url="$fallback_domain" 2>/dev/null || echo "")

        if [[ -n "$main_site_blog_id" && "$main_site_blog_id" != "0" ]]; then
            detection_method="wp-eval-get_main_site_id"
            printf "${GREEN}✅ Found main site via get_main_site_id()${RESET}\n" >&2
        else
            # Try legacy approach
            main_site_blog_id=$(execute_with_timeout 10 execute_wp_cli eval "echo get_current_site()->blog_id;" --url="$fallback_domain" 2>/dev/null || echo "")
            if [[ -n "$main_site_blog_id" && "$main_site_blog_id" != "0" ]]; then
                detection_method="wp-eval-current-site"
                printf "${GREEN}✅ Found main site via get_current_site()${RESET}\n" >&2
            fi
        fi
    fi

    # === METHOD 5: Smart fallback (lowest numbered site with reasonable path) ===
    if [[ -z "$main_site_blog_id" ]]; then
        printf "${YELLOW}⚠️  All advanced methods failed, using intelligent fallback...${RESET}\n" >&2

        local site_data
        site_data=$(execute_with_timeout 10 execute_wp_cli site list --fields=blog_id,path --format=csv --url="$fallback_domain" 2>/dev/null || echo "")

        if [[ -n "$site_data" ]]; then
            local lowest_id=999999
            local fallback_id=""

            while IFS=, read -r blog_id site_path; do
                if [[ "$blog_id" == "blog_id" ]]; then continue; fi  # Skip header
                if [[ -n "$blog_id" ]]; then
                    local clean_blog_id=$(clean_string "$blog_id")
                    local clean_path=$(clean_string "$site_path")

                    # Prefer root path, but accept any if no root found
                    if [[ "$clean_path" == "/" ]]; then
                        main_site_blog_id="$clean_blog_id"
                        detection_method="fallback-root-path"
                        break
                    elif [[ "$clean_blog_id" -lt "$lowest_id" ]]; then
                        lowest_id="$clean_blog_id"
                        fallback_id="$clean_blog_id"
                    fi
                fi
            done <<< "$site_data"

            # Use lowest ID if no root path found
            if [[ -z "$main_site_blog_id" && -n "$fallback_id" ]]; then
                main_site_blog_id="$fallback_id"
                detection_method="fallback-lowest-id"
                printf "${YELLOW}⚠️  Using lowest blog ID as fallback${RESET}\n" >&2
            fi
        fi
    fi

    # === Final fallback ===
    if [[ -z "$main_site_blog_id" ]]; then
        main_site_blog_id="1"
        detection_method="hardcoded-fallback"
        printf "${YELLOW}⚠️  Using hardcoded blog ID 1 as final fallback${RESET}\n" >&2
    fi

    # Try multiple methods to get the URL
    if [[ -n "$main_site_blog_id" && "$main_site_blog_id" != "0" ]]; then
        # Method 1: Direct option get with blog ID switching
        if [[ "$main_site_blog_id" == "1" ]]; then
            main_site_url=$(execute_with_timeout 10 execute_wp_cli option get siteurl --url="$fallback_domain" 2>/dev/null || echo "")
        else
            main_site_url=$(execute_with_timeout 10 execute_wp_cli option get siteurl --url="$fallback_domain" --blog="$main_site_blog_id" 2>/dev/null || echo "")
        fi

        # Method 2: Database query for URL (if not restricted)
        if [[ -z "$main_site_url" ]]; then
            local main_options_table="wp_options"
            if [[ "$main_site_blog_id" != "1" ]]; then
                main_options_table="wp_${main_site_blog_id}_options"
            fi
            main_site_url=$(execute_with_timeout 10 execute_wp_cli db query "SELECT option_value FROM ${main_options_table} WHERE option_name = 'siteurl' LIMIT 1;" --skip-column-names --silent --url="$fallback_domain" 2>/dev/null || echo "")
        fi

        # Method 3: Construct from site list
        if [[ -z "$main_site_url" ]]; then
            local site_data
            site_data=$(execute_with_timeout 10 execute_wp_cli site list --field=url --url="$fallback_domain" 2>/dev/null | head -1 || echo "")
            if [[ -n "$site_data" ]]; then
                main_site_url="$site_data"
            fi
        fi

        # Method 4: Construct from wp_blogs table
        if [[ -z "$main_site_url" ]]; then
            local main_domain main_path
            read -r main_domain main_path <<< "$(execute_with_timeout 10 execute_wp_cli db query "SELECT domain, path FROM wp_blogs WHERE blog_id = ${main_site_blog_id} LIMIT 1;" --skip-column-names --silent --url="$fallback_domain" 2>/dev/null || echo "")"

            if [[ -n "$main_domain" ]]; then
                # Determine protocol (default to https for modern setups)
                local protocol="https://"
                if [[ "$fallback_domain" =~ ^http:// ]]; then
                    protocol="http://"
                fi

                # Clean up path
                main_path="${main_path%/}"
                if [[ "$main_path" == "/" || -z "$main_path" ]]; then
                    main_site_url="${protocol}${main_domain}"
                else
                    main_site_url="${protocol}${main_domain}${main_path}"
                fi
            fi
        fi
    fi

    # Final fallback for URL
    if [[ -z "$main_site_url" ]]; then
        main_site_url="$fallback_domain"
        printf "${YELLOW}⚠️  Using fallback domain for main site URL${RESET}\n" >&2
    fi

    printf "${GREEN}✅ Main site detection complete:${RESET} Blog ID $main_site_blog_id via $detection_method\n" >&2
    printf "\n" >&2
    echo "${main_site_blog_id}|${main_site_url}"
    echo
}

# ===============================================
# Detect Protocol
# ===============================================
#
# Description: Detects the protocol (http:// or https://) used in a URL, or defaults to https:// if none is present.
#
# Parameters:
#	- $1: The URL string.
#
# Returns:
#	- The detected or default protocol string (echoed).
#
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

# ===============================================
# Execute WP-CLI
# ===============================================
#
# Description: Executes a WP-CLI command within a safe, enhanced environment.
#
# Parameters:
#	- $@: The WP-CLI command and its arguments (e.g., "option get siteurl").
#
# Returns:
#	- The output and exit code of the WP-CLI command.
#	- Prints an error and returns 1 if WP-CLI is not found.
#
# Behavior:
#	- Checks for and exports the WP_COMMAND binary path.
#	- Executes the command in a subshell with an enhanced PATH to find WP-CLI (Homebrew, /usr/local).
#
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
        # Suppress PHP startup errors to prevent pollution of output parsing
        export WP_CLI_PHP_ARGS="${WP_CLI_PHP_ARGS:-} -d display_startup_errors=0"
        # Execute the command passed as arguments
        "$WP_COMMAND" "$@"
    )
}

# ===============================================
# Get Tool Version
# ===============================================
#
# Description: Reads the version string from the project's 'VERSION' file.
#
# Parameters:
#	- None (relies on SCRIPT_DIR to locate the file).
#
# Returns:
#	- The version string (echoed).
#	- Echoes "unknown" if the file is not found or empty.
#
get_tool_version() {
    local script_dir="${SCRIPT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
    local version="unknown"

    if [[ -f "$script_dir/VERSION" ]]; then
        version=$(cat "$script_dir/VERSION" 2>/dev/null | tr -d '\n\r' | head -1)
        # Fallback if VERSION file is empty or unreadable
        if [[ -z "$version" ]]; then
            version="unknown"
        fi
    fi

    echo "$version"
}

# ===============================================
# Is Sourced
# ===============================================
#
# Description: Checks if the current script file was sourced (loaded) or executed directly.
#
# Parameters:
#	- None
#
# Returns:
#	- 0 (Success) if sourced.
#	- 1 (Failure) if executed directly.
#
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
        export -f init_script_timer
        export -f pause_script_timer
        export -f resume_script_timer
        export -f get_execution_duration
        export -f get_total_start_time
        export -f show_file_size
        export -f detect_main_site
        export -f detect_protocol
        export -f execute_wp_cli
        export -f get_tool_version
        export -f is_sourced
        export -f find_wordpress_root
        export -f get_wp_table_prefix
        export -f sanitize_domain
        export -f validate_file_exists
        export -f validate_wordpress_installation
        export -f check_wpcli_availability
        export -f create_temp_file
        export -f check_wp_config_constant
        export -f detect_multisite_filesystem_indicators
    } 2>/dev/null
fi

# ===============================================
# Find WordPress Root
# ===============================================
#
# Description: Searches up the directory tree to find the WordPress root directory.
#
# Parameters:
#	- None
#
# Returns:
#	- WordPress root path (echoed) on success.
#	- Returns 1 if wp-config.php not found.
#
# Behavior:
#	- Starts from current directory and moves up, looking for `wp-config.php`.
#
find_wordpress_root() {
    local wp_root
    wp_root=$(pwd)
    while [[ "$wp_root" != "/" && ! -f "$wp_root/wp-config.php" ]]; do
        # Use bash built-in parameter expansion instead of dirname command
        wp_root="${wp_root%/*}"
        # Handle edge case where wp_root becomes empty (would happen at filesystem root)
        if [[ -z "$wp_root" ]]; then
            wp_root="/"
        fi
    done

    if [[ ! -f "$wp_root/wp-config.php" ]]; then
        return 1
    fi

    echo "$wp_root"
    return 0
}

# ===============================================
# Check WP Config Constant
# ===============================================
#
# Description: Checks if a `define()` constant in `wp-config.php` matches a specific value.
#
# Parameters:
#	- $1: CONSTANT_NAME (e.g., "WP_DEBUG").
#	- $2: EXPECTED_VALUE (e.g., "true" or "false").
#	- $3: Optional. Path to `wp-config.php`. Defaults to `wp-config.php` in current dir.
#
# Returns:
#	- "true" or "false" (echoed).
#	- Returns 1 if the config file is not found.
#
check_wp_config_constant() {
    local constant="$1"
    local expected="$2"
    local config_path="${3:-wp-config.php}"

    if [[ ! -f "$config_path" ]]; then
        echo "false"
        return 1
    fi

    if grep -q "define.*${constant}.*${expected}" "$config_path" 2>/dev/null || \
       grep -q "define('${constant}', ${expected})" "$config_path" 2>/dev/null || \
       grep -q "define(\"${constant}\", ${expected})" "$config_path" 2>/dev/null; then
        echo "true"
    else
        echo "false"
    fi
}

# ===============================================
# Detect Multisite Filesystem Indicators
# ===============================================
#
# Description: Checks for common files/directories that indicate a WordPress multisite installation.
#
# Parameters:
#	- $1: WordPress root path.
#
# Returns:
#	- Comma-separated list of indicators found (e.g., "blogs.dir,uploads/sites,mu-plugins") (echoed).
#	- Echoes an empty string if none are found.
#
detect_multisite_filesystem_indicators() {
    local wp_root="$1"
    local indicators=()

    [[ -d "$wp_root/wp-content/blogs.dir" ]] && indicators+=("blogs.dir")
    [[ -d "$wp_root/wp-content/uploads/sites" ]] && indicators+=("uploads/sites")
    [[ -d "$wp_root/wp-content/mu-plugins" ]] && [[ -n "$(ls -A "$wp_root/wp-content/mu-plugins" 2>/dev/null)" ]] && indicators+=("mu-plugins")
    [[ -f "$wp_root/.htaccess" ]] && grep -q "RewriteRule.*wp-includes/ms-files.php" "$wp_root/.htaccess" 2>/dev/null && indicators+=("htaccess-rules")

    ((${#indicators[@]})) && echo "${indicators[*]}" || echo ""
}

# ===============================================
# Get WP Table Prefix
# ===============================================
#
# Description: Extracts the database table prefix (`$table_prefix`) from `wp-config.php`.
#
# Parameters:
#	- $1: Optional. Path to `wp-config.php`. Defaults to `wp-config.php` in current dir.
#
# Returns:
#	- The detected table prefix (e.g., "wp_", "my_") (echoed).
#	- Echoes "wp_" and returns 1 if the file/prefix is not found.
#
get_wp_table_prefix() {
    local wp_config_path="${1:-wp-config.php}"

    if [[ ! -f "$wp_config_path" ]]; then
        echo "wp_"
        return 1
    fi

    local table_prefix
    table_prefix=$(grep -E "^\\\$table_prefix\s*=" "$wp_config_path" | cut -d"'" -f2 2>/dev/null)

    if [[ -z "$table_prefix" ]]; then
        table_prefix="wp_"
    fi

    echo "$table_prefix"
}

# ===============================================
# Sanitize Domain
# ===============================================
#
# Description: Cleans a domain string by removing protocols, trailing slashes, and optional whitespace.
#
# Parameters:
#	- $1: The input domain/URL string.
#	- $2: Optional. Mode ("basic" or "strict"). Strict mode performs extensive validation for security.
#
# Returns:
#	- The sanitized domain (echoed).
#	- Returns 1 if validation fails in "strict" mode.
#
sanitize_domain() {
    local domain="$1"
    local mode="${2:-basic}"  # basic (default) or strict (for stage-file-proxy)

    # Handle empty input
    if [[ -z "$domain" ]]; then
        echo ""
        return 0
    fi

    # Remove any leading/trailing whitespace using bash built-ins
    while [[ "$domain" =~ ^[[:space:]] ]]; do
        domain="${domain#[[:space:]]}"
    done
    while [[ "$domain" =~ [[:space:]]$ ]]; do
        domain="${domain%[[:space:]]}"
    done

    # Remove http:// and https:// protocols (do this AFTER whitespace removal)
    domain="${domain#http://}"
    domain="${domain#https://}"

    # Remove trailing slash(es)
    while [[ "$domain" =~ /$ ]]; do
        domain="${domain%/}"
    done

    # For strict mode (stage-file-proxy), do additional validation
    if [[ "$mode" == "strict" ]]; then
        # Check input length (reasonable URL length limit)
        if [[ ${#domain} -gt 2048 ]]; then
            return 1
        fi

        # Check for dangerous characters that could cause injection
        if [[ "$domain" =~ [\;\|\&\$\`\(\)\<\>\"\'] ]]; then
            return 1
        fi

        # Check for control characters and non-printable characters
        if [[ "$domain" =~ [[:cntrl:]] ]]; then
            return 1
        fi

        # Add https:// protocol (required for database storage in strict mode)
        domain="https://$domain"

        # Validate URL format more thoroughly
        if [[ "$domain" =~ ^https://localhost([:]([0-9]{1,5}))?(/.*)?$ ]]; then
            # Allow localhost with optional port and path
            :
        elif [[ "$domain" =~ ^https://([0-9]{1,3}\.){3}[0-9]{1,3}([:]([0-9]{1,5}))?(/.*)?$ ]]; then
            # Allow IP addresses with optional port and path
            :
        elif ! [[ "$domain" =~ ^https://[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?)+([:]([0-9]{1,5}))?(/.*)?$ ]]; then
            return 1
        fi

        # Additional security check: ensure no multiple protocols
        local protocol_count=0
        local temp_domain="$domain"
        while [[ "$temp_domain" == *"://"* ]]; do
            protocol_count=$((protocol_count + 1))
            temp_domain="${temp_domain#*://}"
        done

        if [[ "$protocol_count" -gt 1 ]]; then
            return 1
        fi
    fi

    echo "$domain"
}

# ===============================================
# Validate File Exists
# ===============================================
#
# Description: Checks if a file exists and is readable.
#
# Parameters:
#	- $1: The path to the file.
#	- $2: Optional. Custom error message prefix.
#
# Returns:
#	- 0 (Success) if file exists and is readable.
#	- 1 (Failure) otherwise (prints specific error message).
#
validate_file_exists() {
    local file_path="$1"
    local error_message="${2:-File not found}"

    if [[ ! -f "$file_path" ]]; then
        printf "${RED}❌ %s: %s${RESET}\n" "$error_message" "$file_path"
        return 1
    fi

    if [[ ! -r "$file_path" ]]; then
        printf "${RED}❌ File not readable: %s${RESET}\n" "$file_path"
        return 1
    fi

    return 0
}

# ===============================================
# Validate WordPress Installation
# ===============================================
#
# Description: Checks if a valid WordPress installation exists in the current directory using WP-CLI.
#
# Parameters:
#	- None
#
# Returns:
#	- 0 (Success) if WordPress is installed.
#	- 1 (Failure) otherwise (prints error).
#
# Behavior:
#	- Relies on `execute_wp_cli` to run `core is-installed`.
#
validate_wordpress_installation() {
    if ! execute_wp_cli core is-installed &>/dev/null; then
        printf "${RED}❌ No WordPress installation detected in this directory.${RESET}\n"
        return 1
    fi
    return 0
}

# ===============================================
# Check WP-CLI Availability
# ===============================================
#
# Description: Checks if the `wp` command is available and sets the global WP_COMMAND variable.
#
# Parameters:
#	- None
#
# Returns:
#	- 0 (Success) if WP-CLI is found.
#	- 1 (Failure) otherwise (prints error).
#
# Behavior:
#	- Searches common paths (Homebrew, /usr/local) if not found in default PATH.
#
check_wpcli_availability() {
    # Use global WP_COMMAND if available, otherwise detect it
    if [[ -z "${WP_COMMAND:-}" ]]; then
        local enhanced_path="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:$PATH"
        WP_COMMAND=$(PATH="$enhanced_path" command -v wp)
        if [[ -z "$WP_COMMAND" ]]; then
            printf "${RED}❌ WP-CLI not found in PATH.${RESET}\n"
            printf "${YELLOW}💡 Please install WP-CLI to use this function.${RESET}\n"
            return 1
        fi
        export WP_COMMAND
    fi
    return 0
}

# ===============================================
# Create Temp File
# ===============================================
#
# Description: Creates a secure temporary file with restricted permissions (600).
#
# Parameters:
#	- $1: Optional. Prefix for the filename (default: `wp_import`).
#	- $2: Optional. Extension for the filename (default: `log`).
#
# Returns:
#	- The full path to the created temporary file (echoed).
#
create_temp_file() {
    local prefix="${1:-wp_import}"
    local extension="${2:-log}"
    local temp_file="/tmp/${prefix}_$$.${extension}"

    # Create file with restricted permissions
    touch "$temp_file"
    chmod 600 "$temp_file"

    echo "$temp_file"
}

# Global bash version variables (set once, used throughout)
# Using compatible syntax for Bash 3.2+ (no -g flag)
BASH_VERSION_MAJOR=""
BASH_VERSION_MINOR=""
BASH_FEATURE_ASSOCIATIVE_ARRAYS=""
BASH_FEATURE_NAMEREF=""
BASH_FEATURE_LOWERCASE=""
BASH_FEATURE_MAPFILE=""
BASH_VERSION_DETECTED=""

# ===============================================
# Detect Bash Version
# ===============================================
#
# Description: Detects the major/minor Bash version and sets flags for available features (AA, NR, LC, MF).
#
# Parameters:
#	- None
#
# Returns:
#	- Implicitly sets global BASH_VERSION_* and BASH_FEATURE_* variables.
#	- Returns 0 (Success) always.
#
# Behavior:
#	- Caches detection result in BASH_VERSION_DETECTED.
#
detect_bash_version() {
    # Skip if already detected
    [[ -n "$BASH_VERSION_DETECTED" ]] && return 0

    # Extract major and minor version numbers
    if [[ -n "${BASH_VERSION:-}" ]]; then
        BASH_VERSION_MAJOR="${BASH_VERSION%%.*}"
        local version_remainder="${BASH_VERSION#*.}"
        BASH_VERSION_MINOR="${version_remainder%%.*}"
    else
        # Fallback for very old systems
        BASH_VERSION_MAJOR="3"
        BASH_VERSION_MINOR="0"
    fi

    # Feature detection based on version
    # Bash 4.0+ features
    if [[ "$BASH_VERSION_MAJOR" -gt 4 ]] || [[ "$BASH_VERSION_MAJOR" -eq 4 && "$BASH_VERSION_MINOR" -ge 0 ]]; then
        BASH_FEATURE_ASSOCIATIVE_ARRAYS="true"
        BASH_FEATURE_LOWERCASE="true"
        BASH_FEATURE_MAPFILE="true"
    else
        BASH_FEATURE_ASSOCIATIVE_ARRAYS="false"
        BASH_FEATURE_LOWERCASE="false"
        BASH_FEATURE_MAPFILE="false"
    fi

    # Bash 4.3+ features
    if [[ "$BASH_VERSION_MAJOR" -gt 4 ]] || [[ "$BASH_VERSION_MAJOR" -eq 4 && "$BASH_VERSION_MINOR" -ge 3 ]]; then
        BASH_FEATURE_NAMEREF="true"
    else
        BASH_FEATURE_NAMEREF="false"
    fi

    BASH_VERSION_DETECTED="true"

    # Debug info (optional)
    if [[ "${BASH_DEBUG_VERSION:-}" == "true" ]]; then
        printf "🔍 Bash Version: %s.%s\n" "$BASH_VERSION_MAJOR" "$BASH_VERSION_MINOR" >&2
        printf "📋 Features: AA=%s, NR=%s, LC=%s, MF=%s\n" \
            "$BASH_FEATURE_ASSOCIATIVE_ARRAYS" "$BASH_FEATURE_NAMEREF" \
            "$BASH_FEATURE_LOWERCASE" "$BASH_FEATURE_MAPFILE" >&2
    fi
}

# ===============================================
# Init Associative Array
# ===============================================
#
# Description: Initializes a structure to simulate an associative array (AA) compatible across Bash versions.
#
# Parameters:
#	- $1: The name of the array/structure (e.g., "MY_MAP").
#
# Returns:
#	- Implicitly creates the necessary global variables (native AA for Bash 4.0+, or parallel arrays for Bash 3.2).
#
# Behavior:
#	- Requires `detect_bash_version` to run first.
#
init_associative_array() {
    local array_name="$1"

    detect_bash_version

    if [[ "$BASH_FEATURE_ASSOCIATIVE_ARRAYS" == "true" ]]; then
        # Bash 4.0+: Use native associative arrays
        # Use eval to avoid syntax errors in older bash
        eval "declare -A $array_name" 2>/dev/null || {
            # Fallback if declare -A fails
            eval "declare -a ${array_name}_KEYS"
            eval "declare -a ${array_name}_VALUES"
            eval "${array_name}_INITIALIZED=true"
        }
    else
        # Bash 3.2: Use regular array with key encoding
        eval "declare -a ${array_name}_KEYS"
        eval "declare -a ${array_name}_VALUES"
        eval "${array_name}_INITIALIZED=true"
    fi
}

# ===============================================
# Set Associative Value
# ===============================================
#
# Description: Sets a key-value pair in the version-compatible associative array structure.
#
# Parameters:
#	- $1: The name of the array/structure.
#	- $2: The key.
#	- $3: The value.
#
# Returns:
#	- Implicitly updates the global array/structure.
#
# Behavior:
#	- Requires `detect_bash_version` to run first.
#
set_associative_value() {
    local array_name="$1"
    local key="$2"
    local value="$3"

    detect_bash_version

    if [[ "$BASH_FEATURE_ASSOCIATIVE_ARRAYS" == "true" ]]; then
        # Bash 4.0+: Direct assignment
        eval "${array_name}['$key']='$value'"
    else
        # Bash 3.2: Parallel arrays
        eval "local keys_array_name=\"${array_name}_KEYS\""
        eval "local values_array_name=\"${array_name}_VALUES\""

        # Check if key exists
        eval "local -a existing_keys=(\"\${${array_name}_KEYS[@]}\")"
        local index=-1
        local i=0

        for existing_key in "${existing_keys[@]}"; do
            if [[ "$existing_key" == "$key" ]]; then
                index=$i
                break
            fi
            ((i++))
        done

        if [[ $index -ge 0 ]]; then
            # Update existing value
            eval "${values_array_name}[$index]='$value'"
        else
            # Add new key-value pair
            eval "${keys_array_name}+=('$key')"
            eval "${values_array_name}+=('$value')"
        fi
    fi
}

# ===============================================
# Get Associative Value
# ===============================================
#
# Description: Retrieves the value for a given key from the version-compatible associative array structure.
#
# Parameters:
#	- $1: The name of the array/structure.
#	- $2: The key.
#
# Returns:
#	- The value (echoed), or an empty string if the key is not found.
#
# Behavior:
#	- Requires `detect_bash_version` to run first.
#
get_associative_value() {
    local array_name="$1"
    local key="$2"

    detect_bash_version

    if [[ "$BASH_FEATURE_ASSOCIATIVE_ARRAYS" == "true" ]]; then
        # Bash 4.0+: Direct access
        eval "echo \"\${${array_name}['$key']:-}\""
    else
        # Bash 3.2: Search parallel arrays
        eval "local -a existing_keys=(\"\${${array_name}_KEYS[@]}\")"
        eval "local -a existing_values=(\"\${${array_name}_VALUES[@]}\")"

        local i=0
        for existing_key in "${existing_keys[@]}"; do
            if [[ "$existing_key" == "$key" ]]; then
                echo "${existing_values[$i]}"
                return 0
            fi
            ((i++))
        done

        # Key not found
        echo ""
    fi
}

# ===============================================
# Get Associative Keys
# ===============================================
#
# Description: Lists all keys stored in the version-compatible associative array structure.
#
# Parameters:
#	- $1: The name of the array/structure.
#
# Returns:
#	- Keys, one per line (echoed).
#
# Behavior:
#	- Requires `detect_bash_version` to run first.
#
get_associative_keys() {
    local array_name="$1"

    detect_bash_version

    if [[ "$BASH_FEATURE_ASSOCIATIVE_ARRAYS" == "true" ]]; then
        # Bash 4.0+: Get keys directly
        eval "local -a keys=(\"\${!${array_name}[@]}\")"
        printf '%s\n' "${keys[@]}"
    else
        # Bash 3.2: Return keys array
        eval "local -a keys=(\"\${${array_name}_KEYS[@]}\")"
        printf '%s\n' "${keys[@]}"
    fi
}

# ===============================================
# To Lowercase
# ===============================================
#
# Description: Converts a string to lowercase using the best available method.
#
# Parameters:
#	- $1: The input string.
#
# Returns:
#	- The lowercase string (echoed).
#
# Behavior:
#	- Uses Bash 4.0+ parameter expansion (`${input,,}`).
#	- Falls back to the `tr` command for Bash 3.2.
#
to_lowercase() {
    local input="$1"

    detect_bash_version

    if [[ "$BASH_FEATURE_LOWERCASE" == "true" ]]; then
        # Bash 4.0+: Built-in parameter expansion
        echo "${input,,}"
    else
        # Bash 3.2: Use tr command
        echo "$input" | tr '[:upper:]' '[:lower:]'
    fi
}

# ===============================================
# To Uppercase
# ===============================================
#
# Description: Converts a string to uppercase using the best available method.
#
# Parameters:
#	- $1: The input string.
#
# Returns:
#	- The uppercase string (echoed).
#
# Behavior:
#	- Uses Bash 4.0+ parameter expansion (`${input^^}`).
#	- Falls back to the `tr` command for Bash 3.2.
#
to_uppercase() {
    local input="$1"

    detect_bash_version

    if [[ "$BASH_FEATURE_LOWERCASE" == "true" ]]; then
        # Bash 4.0+: Built-in parameter expansion
        echo "${input^^}"
    else
        # Bash 3.2: Use tr command
        echo "$input" | tr '[:lower:]' '[:upper:]'
    fi
}

# ===============================================
# Read Lines Into Array
# ===============================================
#
# Description: Reads stdin (lines) into a named array, compatible across Bash versions.
#
# Parameters:
#	- $1: The name of the destination array variable.
#
# Returns:
#	- Implicitly populates the named array.
#
# Behavior:
#	- Uses Bash 4.0+ `mapfile -t`.
#	- Falls back to manual `while IFS= read -r line` loop for Bash 3.2.
#
read_lines_into_array() {
    local array_name="$1"

    detect_bash_version

    if [[ "$BASH_FEATURE_MAPFILE" == "true" ]]; then
        # Bash 4.0+: Use mapfile
        eval "mapfile -t $array_name"
    else
        # Bash 3.2: Manual line reading
        eval "$array_name=()"
        local line
        while IFS= read -r line; do
            eval "$array_name+=(\"\$line\")"
        done
    fi
}

# ===============================================
# Process Array By Name
# ===============================================
#
# Description: Copies the contents of a source array (passed by name) into a global array named `ARRAY_ELEMENTS`.
#
# Parameters:
#	- $1: The name of the source array variable.
#
# Returns:
#	- Implicitly populates the global `ARRAY_ELEMENTS` array.
#
# Behavior:
#	- Required for Bash 3.2 which lacks nameref. Global name must be used carefully.
#
process_array_by_name() {
    local array_name="$1"

    # Copy array to global ARRAY_ELEMENTS for processing
    eval "ARRAY_ELEMENTS=(\"\${${array_name}[@]}\")"
}

# ===============================================
# Copy Array To Local
# ===============================================
#
# Description: Copies the contents of one array to a local array within the calling function's scope.
#
# Parameters:
#	- $1: The name of the source array variable.
#	- $2: The name of the destination array variable (which is declared locally).
#
# Returns:
#	- Implicitly populates the local destination array.
#
copy_array_to_local() {
    local source_name="$1"
    local dest_name="$2"

    eval "local -a temp_array=(\"\${${source_name}[@]}\")"
    eval "$dest_name=(\"\${temp_array[@]}\")"
}

# ===============================================
# Has Bash Feature
# ===============================================
#
# Description: Checks if a specific advanced Bash feature is available in the current shell version.
#
# Parameters:
#	- $1: Feature name (e.g., "associative_arrays", "nameref", "lowercase", "mapfile").
#
# Returns:
#	- 0 (Success) if the feature is available.
#	- 1 (Failure) otherwise.
#
has_bash_feature() {
    local feature="$1"

    detect_bash_version

    case "$feature" in
        "associative_arrays"|"aa")
            [[ "$BASH_FEATURE_ASSOCIATIVE_ARRAYS" == "true" ]]
            ;;
        "nameref"|"nr")
            [[ "$BASH_FEATURE_NAMEREF" == "true" ]]
            ;;
        "lowercase"|"lc")
            [[ "$BASH_FEATURE_LOWERCASE" == "true" ]]
            ;;
        "mapfile"|"mf")
            [[ "$BASH_FEATURE_MAPFILE" == "true" ]]
            ;;
        *)
            echo "Unknown feature: $feature" >&2
            return 1
            ;;
    esac
}

# ===============================================
# Get Bash Version Info
# ===============================================
#
# Description: Prints diagnostic information about the current Bash version and detected features.
#
# Parameters:
#	- None
#
# Returns:
#	- Prints formatted version and feature information to stdout.
#
get_bash_version_info() {
    detect_bash_version

    printf "Bash Version: %s.%s (%s)\n" \
        "$BASH_VERSION_MAJOR" "$BASH_VERSION_MINOR" "${BASH_VERSION:-unknown}"
    printf "Features Available:\n"
    printf "  - Associative Arrays: %s\n" "$BASH_FEATURE_ASSOCIATIVE_ARRAYS"
    printf "  - Nameref Variables: %s\n" "$BASH_FEATURE_NAMEREF"
    printf "  - Case Conversion: %s\n" "$BASH_FEATURE_LOWERCASE"
    printf "  - Mapfile/Readarray: %s\n" "$BASH_FEATURE_MAPFILE"
}

# ===============================================
# Enhanced Configuration Compatibility
# ===============================================

# ===============================================
# Init Config Storage
# ===============================================
#
# Description: Initializes the global configuration storage structure (`WP_IMPORT_CONFIG`) using the best version-compatible method.
#
# Parameters:
#	- None
#
# Returns:
#	- Implicitly sets the global `CONFIG_STORAGE_METHOD` variable.
#
# Behavior:
#	- Prefers native associative arrays (`associative`).
#	- Falls back to parallel arrays (`arrays`) via `init_associative_array`.
#
init_config_storage() {
    detect_bash_version

    if [[ "$BASH_FEATURE_ASSOCIATIVE_ARRAYS" == "true" ]]; then
        # Try to declare associative array
        eval "declare -A WP_IMPORT_CONFIG" 2>/dev/null || {
            # Fallback if declare fails
            CONFIG_STORAGE_METHOD="arrays"
            init_associative_array "WP_IMPORT_CONFIG"
        }
        if [[ -z "$CONFIG_STORAGE_METHOD" ]]; then
            CONFIG_STORAGE_METHOD="associative"
        fi
    else
        CONFIG_STORAGE_METHOD="arrays"
        init_associative_array "WP_IMPORT_CONFIG"
    fi
}

# ===============================================
# Set Config Value
# ===============================================
#
# Description: Sets a key-value pair in the global configuration storage.
#
# Parameters:
#	- $1: The key.
#	- $2: The value.
#
# Returns:
#	- Implicitly updates the global `WP_IMPORT_CONFIG` storage.
#
# Behavior:
#	- Automatically calls `init_config_storage` if needed.
#	- Uses native array assignment or `set_associative_value` based on detected method.
#
set_config_value() {
    local key="$1"
    local value="$2"

    [[ -z "$CONFIG_STORAGE_METHOD" ]] && init_config_storage

    if [[ "$CONFIG_STORAGE_METHOD" == "associative" ]]; then
        WP_IMPORT_CONFIG["$key"]="$value"
    else
        set_associative_value "WP_IMPORT_CONFIG" "$key" "$value"
    fi
}

# ===============================================
# Get Config Value
# ===============================================
#
# Description: Retrieves the value for a given key from the global configuration storage.
#
# Parameters:
#	- $1: The key.
#
# Returns:
#	- The value (echoed), or an empty string if the key is not found.
#
# Behavior:
#	- Automatically calls `init_config_storage` if needed.
#	- Uses native array access or `get_associative_value` based on detected method.
#
get_config_value() {
    local key="$1"

    [[ -z "$CONFIG_STORAGE_METHOD" ]] && init_config_storage

    if [[ "$CONFIG_STORAGE_METHOD" == "associative" ]]; then
        echo "${WP_IMPORT_CONFIG[$key]:-}"
    else
        get_associative_value "WP_IMPORT_CONFIG" "$key"
    fi
}
