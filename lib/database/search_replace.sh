#!/usr/bin/env bash

# ================================================================
# Search and Replace Module
# ================================================================
#
# Description:
#   Provides advanced and robust search and replace functionality specifically
#   designed for use with WP-CLI during WordPress database import and migration
#   processes. It meticulously handles multiple replacement passes to correctly
#   update standard URL strings, serialized data, and automatically accounts
#   for WWW and non-WWW variants. This module supports both single-site and
#   complex multisite domain mappings and path adjustments.
#
# Key Features:
# - Executes four distinct search-replace passes (non-escaped and escaped, www and non-www).
# - Handles multisite subsite domain and path configurations.
# - Provides visual progress indicators for each site and step.
#
# Functions provided:
# - run_search_replace           Core search-replace with enhanced www handling
# - process_multisite_mappings   Handle multisite domain mapping operations
# - start_site_processing        Visual feedback for multisite operations
# - update_step_status           Progress indicators for search-replace steps
#
# Dependencies:
#   - detect_bash_version (from core/utils.sh)
#   - execute_wp_cli (from core/utils.sh)
#   - Global flag variables (all_tables_flag, dry_run_flag)
#   - Global array variables (domain_keys, domain_values, domain_blog_ids, domain_paths)
#   - Color constants (e.g., ${CYAN}, ${YELLOW}, ${RED}, ${BOLD}, ${RESET})
#
# ================================================================

# Ensure bash version compatibility is detected
detect_bash_version 2>/dev/null || true

# ===============================================
# Enhanced Search-Replace Function
# ===============================================
#
# Description: Executes the core WP-CLI search-replace command, automatically handling four critical passes:
#              1. Non-WWW standard string replacement.
#              2. WWW standard string replacement (if applicable).
#              3. Non-WWW escaped string replacement (for serialized data).
#              4. WWW escaped string replacement (for serialized data, if applicable).
#
# Parameters:
#   - $1: old_domain (source domain, e.g., example.com)
#   - $2: new_domain (destination domain, e.g., local.test)
#   - $3: log_file (full path to the log file)
#   - $4: url_flag (--url=... or --network or empty)
#   - $5: old_path (optional path component, e.g., /subsite/)
#   - $6: new_path (optional new path component, currently unused in logic, retained for signature)
#
# Returns:
#   - 0 on success (all passes completed).
#   - 1 on failure (if any WP-CLI command fails).
#
# Behavior:
#   - Constructs search and replace strings carefully, including path components for multisite subsites.
#   - Automatically handles `http://` vs `https://` by searching/replacing the protocol-relative form `//domain`.
#   - Skips the `guid` column and non-essential tables/plugins/themes to speed up execution.
#   - Requires `execute_wp_cli`.
#
run_search_replace() {
    local old_domain="$1"
    local new_domain="$2"
    local log_file="$3"
    local url_flag="$4"
    local old_path="${5:-}"
    local new_path="${6:-}"

    # Validate inputs
    if [[ -z "$old_domain" || -z "$new_domain" ]]; then
        printf "Error: Missing domain parameters\n" >&2
        return 1
    fi

    # Parse url_flag to determine execution context
    local actual_url_flag=""
    local network_flag_arg=""

    if [[ "$url_flag" == "--network" ]]; then
        network_flag_arg="--network"
    elif [[ "$url_flag" == *"--url="* ]]; then
        actual_url_flag="$url_flag"
    fi

    # Enhanced domain+path construction with intelligent slash handling
    local search_domain_with_path="$old_domain"
    local replace_domain_with_path="$new_domain"

    # Apply path handling only in multisite context with meaningful paths
    local is_multisite_context=false
    if [[ "$actual_url_flag" == *"--url="* ]] || [[ -n "$network_flag_arg" ]]; then
        is_multisite_context=true
    fi

    # Construct domain+path combinations for multisite subsites
    if [[ -n "$old_path" && "$old_path" != "/" && "$is_multisite_context" == true ]]; then
        # Remove leading/trailing slashes for clean handling
        local clean_old_path="${old_path#/}"
        clean_old_path="${clean_old_path%/}"
        local clean_new_path="${new_path#/}"
        clean_new_path="${clean_new_path%/}"

        # Clean destination domain
        local clean_new_domain="${new_domain%/}"

        # Determine slash handling based on destination format
        local dest_has_trailing_slash=false
        if [[ "$new_domain" =~ /$ ]]; then
            dest_has_trailing_slash=true
        fi

        # Construct source domain+path
        if [[ "$dest_has_trailing_slash" == true ]]; then
            search_domain_with_path="${old_domain}/${clean_old_path}/"
        else
            search_domain_with_path="${old_domain}/${clean_old_path}"
        fi

        # Construct replace domain+path
        if [[ -n "$clean_new_path" ]]; then
            if [[ "$dest_has_trailing_slash" == true ]]; then
                replace_domain_with_path="${clean_new_domain}/${clean_new_path}/"
            else
                replace_domain_with_path="${clean_new_domain}/${clean_new_path}"
            fi
        else
            if [[ "$dest_has_trailing_slash" == true ]]; then
                replace_domain_with_path="${clean_new_domain}/"
            else
                replace_domain_with_path="$clean_new_domain"
            fi
        fi
    else
        # Handle main sites or single sites with proper slash logic
        local clean_old_domain="${old_domain%/}"
        local dest_has_trailing_slash=false
        if [[ "$new_domain" =~ /$ ]]; then
            dest_has_trailing_slash=true
        fi

        if [[ "$dest_has_trailing_slash" == true ]]; then
            search_domain_with_path="${clean_old_domain}/"
            replace_domain_with_path="${new_domain}"
        else
            search_domain_with_path="$clean_old_domain"
            replace_domain_with_path="$new_domain"
        fi
    fi

    # Enhanced www/non-www detection and handling
    local base_domain_with_path="$search_domain_with_path"
    local www_domain_with_path
    local non_www_domain_with_path
    local has_www=false

    # Check if source domain starts with www
    if [[ "$search_domain_with_path" =~ ^www\. ]]; then
        www_domain_with_path="$search_domain_with_path"
        non_www_domain_with_path="${search_domain_with_path#www.}"
        has_www=true
    else
        non_www_domain_with_path="$search_domain_with_path"
        www_domain_with_path="www.${search_domain_with_path}"
        has_www=false
    fi

    # Define search-replace patterns
    local sr1_old_non_www="//${non_www_domain_with_path}"
    local sr2_old_non_www="\\\\//${non_www_domain_with_path}"
    local sr_new="//${replace_domain_with_path}"
    local sr_new_escaped="\\\\//${replace_domain_with_path}"

    # Define www patterns if source has www
    local sr1_old_www
    local sr2_old_www
    if [[ "$has_www" == true ]]; then
        sr1_old_www="//${www_domain_with_path}"
        sr2_old_www="\\\\//${www_domain_with_path}"
    fi

    # Execute Pass 1: Standard replacement for non-www variant
    local cmd_args=("search-replace" "$sr1_old_non_www" "$sr_new")

    if [[ -n "$actual_url_flag" ]]; then
        cmd_args+=("$actual_url_flag")
    fi

    cmd_args+=("--skip-columns=guid" "--report-changed-only" "--skip-plugins" "--skip-themes" "--skip-packages")

    if [[ -n "$all_tables_flag" ]]; then
        cmd_args+=("$all_tables_flag")
    fi

    if [[ -n "$network_flag_arg" ]]; then
        cmd_args+=("$network_flag_arg")
    fi

    if [[ -n "$dry_run_flag" ]]; then
        cmd_args+=("$dry_run_flag")
    fi

    if ! execute_wp_cli "${cmd_args[@]}" &> "$log_file"; then
        return 1
    fi

    # Execute Pass 2: Standard replacement for www variant (if source has www)
    if [[ "$has_www" == true ]]; then
        cmd_args=("search-replace" "$sr1_old_www" "$sr_new")

        if [[ -n "$actual_url_flag" ]]; then
            cmd_args+=("$actual_url_flag")
        fi

        cmd_args+=("--skip-columns=guid" "--report-changed-only" "--skip-plugins" "--skip-themes" "--skip-packages")

        if [[ -n "$all_tables_flag" ]]; then
            cmd_args+=("$all_tables_flag")
        fi

        if [[ -n "$network_flag_arg" ]]; then
            cmd_args+=("$network_flag_arg")
        fi

        if [[ -n "$dry_run_flag" ]]; then
            cmd_args+=("$dry_run_flag")
        fi

        if ! execute_wp_cli "${cmd_args[@]}" >> "$log_file" 2>&1; then
            return 1
        fi
    fi

    # Execute Serialized Pass: Non-www variant
    cmd_args=("search-replace" "$sr2_old_non_www" "$sr_new_escaped")

    if [[ -n "$actual_url_flag" ]]; then
        cmd_args+=("$actual_url_flag")
    fi

    cmd_args+=("--skip-columns=guid" "--report-changed-only" "--skip-plugins" "--skip-themes" "--skip-packages")

    if [[ -n "$all_tables_flag" ]]; then
        cmd_args+=("$all_tables_flag")
    fi

    if [[ -n "$network_flag_arg" ]]; then
        cmd_args+=("$network_flag_arg")
    fi

    if [[ -n "$dry_run_flag" ]]; then
        cmd_args+=("$dry_run_flag")
    fi

    if ! execute_wp_cli "${cmd_args[@]}" >> "$log_file" 2>&1; then
        return 1
    fi

    # Execute Final Pass: Serialized replacement for www variant (if source has www)
    if [[ "$has_www" == true ]]; then
        cmd_args=("search-replace" "$sr2_old_www" "$sr_new_escaped")

        if [[ -n "$actual_url_flag" ]]; then
            cmd_args+=("$actual_url_flag")
        fi

        cmd_args+=("--skip-columns=guid" "--report-changed-only" "--skip-plugins" "--skip-themes" "--skip-packages")

        if [[ -n "$all_tables_flag" ]]; then
            cmd_args+=("$all_tables_flag")
        fi

        if [[ -n "$network_flag_arg" ]]; then
            cmd_args+=("$network_flag_arg")
        fi

        if [[ -n "$dry_run_flag" ]]; then
            cmd_args+=("$dry_run_flag")
        fi

        if ! execute_wp_cli "${cmd_args[@]}" >> "$log_file" 2>&1; then
            return 1
        fi
    fi

    return 0
}

# ===============================================
# Process Multisite Mappings
# ===============================================
#
# Description: Iterates through configured multisite mappings (subsites and main site) and executes the search-replace operation for each one.
#
# Parameters:
#   - $1: main_site_id (Blog ID of the primary network site, usually '1').
#   - $2-$5: Array names (Signature includes placeholders, but arrays are accessed globally).
#
# Returns:
#   - Implicitly calls `run_search_replace` for each mapped site.
#   - Prints status and verbose output.
#
# Global Arrays Used:
#   - domain_keys[]: Source domains/paths.
#   - domain_values[]: Target domains/paths.
#   - domain_blog_ids[]: Blog IDs.
#   - domain_paths[]: Site path components.
#
# Behavior:
#   - Skips the main site (ID $1) on the first pass, processing subsites first.
#   - Processes the main site last using its special mapping.
#   - Requires `detect_bash_version`, `start_site_processing`, and `update_step_status`.
#
process_multisite_mappings() {
    local main_site_id="$1"
    # Enhanced bash compatibility - works with 3.2, 4.x, and 5.x

    # Ensure bash features are detected
    detect_bash_version 2>/dev/null || true

    local array_length=${#domain_keys[@]}
    local main_site_key=""
    local main_site_value=""
    local main_site_path=""

    # Display header with enhanced compatibility
    printf "\n${CYAN}${BOLD}🔄 SEARCH-REPLACE OPERATIONS${RESET}\n"
    printf "${CYAN}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}\n"

    # Debug info for bash version (if enabled)
    if [[ "${BASH_DEBUG_VERSION:-}" == "true" ]]; then
        printf "${YELLOW}🔧 Running on Bash %s.%s with array processing compatibility${RESET}\n" \
            "${BASH_VERSION_MAJOR:-3}" "${BASH_VERSION_MINOR:-2}"
    fi

    # Process subsites first (skip main site)
    for ((i=0; i<array_length; i++)); do
        local cleaned_domain="${domain_keys[i]}"
        local new_domain="${domain_values[i]}"
        local blog_id="${domain_blog_ids[i]}"
        local site_path_var="${domain_paths[i]}"

        # Store main site data for later processing
        if [[ "$blog_id" == "$main_site_id" ]]; then
            main_site_key="$cleaned_domain"
            main_site_value="$new_domain"
            main_site_path="$site_path_var"
            continue
        fi

        # Skip unchanged or empty mappings
        if [[ -z "$new_domain" || "$cleaned_domain" == "$new_domain" ]]; then
            continue
        fi

        local SR_LOG_MULTI="/tmp/wp_replace_${blog_id}_$$.log"

        # Parse domain and path components
        local actual_domain="$cleaned_domain"
        local actual_path="$site_path_var"
        local display_from_domain="$cleaned_domain"

        # Handle domains that already contain path components
        if [[ "$cleaned_domain" == *"/"* && "$site_path_var" != "/" ]]; then
            actual_domain="${cleaned_domain%%/*}"
            display_from_domain="$cleaned_domain"
        elif [[ -n "$site_path_var" && "$site_path_var" != "/" ]]; then
            local clean_display_path="${site_path_var%/}"
            display_from_domain="${cleaned_domain}${clean_display_path}"
        fi

        # Start site processing
        start_site_processing "$blog_id" "$display_from_domain" "$new_domain" "false"

        # Execute search-replace
        if run_search_replace "$actual_domain" "$new_domain" "$SR_LOG_MULTI" "--url=$actual_domain" "$actual_path" ""; then
            update_step_status "1" "Standard URL replacement complete" "complete"
            update_step_status "2" "Serialized data replacement complete" "complete"
        else
            update_step_status "1" "Standard URL replacement failed" "failed"
            update_step_status "2" "Serialized data replacement failed" "failed"
        fi
    done

    # Process main site last
    if [[ -n "$main_site_key" && "$main_site_key" != "$main_site_value" ]]; then
        local main_site_log="/tmp/wp_replace_${main_site_id}_$$.log"

        # Construct display domain including path when meaningful
        local main_display_old="$main_site_key"
        if [[ -n "$main_site_path" && "$main_site_path" != "/" ]]; then
            local clean_main_path="${main_site_path%/}"
            main_display_old="${main_site_key}${clean_main_path}"
        fi

        # Start main site processing
        start_site_processing "$main_site_id" "$main_display_old" "$main_site_value" "true"

        # Execute main site search-replace
        if run_search_replace "$main_site_key" "$main_site_value" "$main_site_log" "--url=$main_site_key" "$main_site_path" ""; then
            update_step_status "1" "Standard URL replacement complete" "complete"
            update_step_status "2" "Serialized data replacement complete" "complete"
        else
            update_step_status "1" "Standard URL replacement failed" "failed"
            update_step_status "2" "Serialized data replacement failed" "failed"
        fi
    elif [[ -n "$main_site_key" ]]; then
        printf "\n${YELLOW}⏭️  Main Site (ID %s) - No changes needed${RESET}\n" "$main_site_id"
    else
        printf "\n${RED}❌ Could not find Main Site mapping (ID %s) to process.${RESET}\n" "$main_site_id"
    fi
}

# ===============================================
# Start Site Processing
# ===============================================
#
# Description: Prints a clear header indicating the start of search-replace for a specific site, showing the old and new domains.
#
# Parameters:
#   - $1: site_id (Blog ID).
#   - $2: from_domain (Source domain/path for display).
#   - $3: to_domain (Target domain/path for display).
#   - $4: is_main ("true" if this is the main network site, "false" otherwise).
#
# Returns:
#   - Prints formatted output to stdout.
#
# Behavior:
#   - Uses different visual cues (🏠 vs 🌍) for the main site and subsites.
#
start_site_processing() {
    local site_id="$1"
    local from_domain="$2"
    local to_domain="$3"
    local is_main="$4"

    if [[ "$is_main" == "true" ]]; then
        printf "\n🏠 Main Site Processing:\n"
    else
        printf "\n🌍 Site %s Processing:\n" "$site_id"
    fi

    printf "   From: %s\n" "$from_domain"
    printf "   To:   %s\n" "$to_domain"
    printf "\n"
}

# ===============================================
# Update Step Status
# ===============================================
#
# Description: Prints a single step's status (e.g., replacement pass) with a color-coded indicator.
#
# Parameters:
#   - $1: step_num (Step number, e.g., '1').
#   - $2: description (Description of the step).
#   - $3: status ("complete", "processing", or "failed").
#
# Returns:
#   - Prints color-coded status line to stdout.
#
# Behavior:
#   - Uses specific emojis (✅, 🔄, ❌) for visual feedback.
#
update_step_status() {
    local step_num="$1"
    local description="$2"
    local status="$3"

    case "$status" in
        "complete")
            printf "   Step %s: ✅ %s\n" "$step_num" "$description"
            ;;
        "processing")
            printf "   Step %s: 🔄 %s\n" "$step_num" "$description"
            ;;
        "failed")
            printf "   Step %s: ❌ %s\n" "$step_num" "$description"
            ;;
    esac
}

# -----------------------------------------------
# Export functions for external use
# -----------------------------------------------
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    {
        export -f run_search_replace
        export -f process_multisite_mappings
        export -f start_site_processing
        export -f update_step_status
    } >/dev/null 2>&1
fi
