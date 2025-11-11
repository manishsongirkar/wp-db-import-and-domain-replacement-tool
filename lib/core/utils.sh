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
# Detect main site ID and URL for WordPress multisite
# -----------------------------------------------
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
        printf "${YELLOW}⚠️ WP-CLI not responding or no WordPress installation, using defaults${RESET}\n" >&2
        echo "1|$fallback_domain"
        return 0
    fi

    # Check if this is actually a multisite installation
    local is_multisite_check
    is_multisite_check=$(execute_with_timeout 5 execute_wp_cli eval 'echo is_multisite() ? "yes" : "no";' --url="$fallback_domain" 2>/dev/null || echo "no")
    if [[ "$is_multisite_check" != "yes" ]]; then
        printf "${YELLOW}⚠️ Not actually a multisite installation, treating as single site${RESET}\n" >&2
        local site_url
        site_url=$(execute_with_timeout 10 execute_wp_cli option get siteurl --url="$fallback_domain" 2>/dev/null || echo "$fallback_domain")
        echo "1|$site_url"
        return 0
    fi

    # === METHOD 1: Direct database queries (works on most environments) ===
    printf "${CYAN}🔍 Trying database query method...${RESET}\n" >&2
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
        printf "${YELLOW}⚠️  Database queries blocked, trying WP-CLI site commands...${RESET}\n" >&2

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
        printf "${YELLOW}⚠️ Site list failed, trying network admin detection...${RESET}\n" >&2

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
        printf "${YELLOW}⚠️ Advanced detection failed, using WordPress constants...${RESET}\n" >&2

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
        printf "${YELLOW}⚠️ All advanced methods failed, using intelligent fallback...${RESET}\n" >&2

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
                printf "${YELLOW}⚠️ Using lowest blog ID as fallback${RESET}\n" >&2
            fi
        fi
    fi

    # === Final fallback ===
    if [[ -z "$main_site_blog_id" ]]; then
        main_site_blog_id="1"
        detection_method="hardcoded-fallback"
        printf "${YELLOW}⚠️ Using hardcoded blog ID 1 as final fallback${RESET}\n" >&2
    fi

    # === Get main site URL ===
    printf "${CYAN}🔍 Getting main site URL (Blog ID: $main_site_blog_id)...${RESET}\n" >&2

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
        printf "${YELLOW}⚠️ Using fallback domain for main site URL${RESET}\n" >&2
    fi

    printf "${GREEN}✅ Main site detection complete:${RESET} Blog ID $main_site_blog_id via $detection_method\n" >&2
    echo "${main_site_blog_id}|${main_site_url}"
    echo
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
        export -f detect_main_site
        export -f detect_protocol
        export -f execute_wp_cli
        export -f is_sourced
    } 2>/dev/null
fi
