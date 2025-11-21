#!/usr/bin/env bash

# ===============================================
# Config Integration for WordPress Import Tool
# ===============================================
#
# Description:
#   Integrates the configuration system with the main import flow,
#   handles multisite mapping, and manages config updates.
#
# Dependencies (Assumed to be sourced externally):
#   - parse_config_section
#   - get_site_mappings
#   - get_site_mapping
#   - update_site_mapping
#   - update_config_general
#   - is_config_true
#
# ===============================================

# ===============================================
# Load Import Config
# ===============================================
#
# Description: Loads primary [general] config settings into global environment variables.
#
# Parameters:
#	- $1: Path to the configuration file (wpdb-import.conf).
#
# Returns:
#	- 0 (Success) if the config file is read and variables are populated.
#	- 1 (Failure) if the config file is not found.
#
# Behavior:
#	- Exports settings to global variables (CONFIG_SQL_FILE, CONFIG_OLD_DOMAIN, etc.).
#	- Requires `parse_config_section` function to be available.
#
load_import_config() {
    local config_path="$1"

    # Initialize global config variables
    export CONFIG_SQL_FILE=""
    export CONFIG_OLD_DOMAIN=""
    export CONFIG_NEW_DOMAIN=""
    export CONFIG_ALL_TABLES=""
    export CONFIG_DRY_RUN=""
    export CONFIG_CLEAR_REVISIONS=""
    export CONFIG_SETUP_STAGE_PROXY=""
    export CONFIG_AUTO_PROCEED=""

    if [[ ! -f "$config_path" ]]; then
        return 1
    fi

    # Load general settings
    CONFIG_SQL_FILE=$(parse_config_section "$config_path" "general" "sql_file")
    CONFIG_OLD_DOMAIN=$(parse_config_section "$config_path" "general" "old_domain")
    CONFIG_NEW_DOMAIN=$(parse_config_section "$config_path" "general" "new_domain")
    CONFIG_ALL_TABLES=$(parse_config_section "$config_path" "general" "all_tables")
    CONFIG_DRY_RUN=$(parse_config_section "$config_path" "general" "dry_run")
    CONFIG_CLEAR_REVISIONS=$(parse_config_section "$config_path" "general" "clear_revisions")
    CONFIG_SETUP_STAGE_PROXY=$(parse_config_section "$config_path" "general" "setup_stage_proxy")
    CONFIG_AUTO_PROCEED=$(parse_config_section "$config_path" "general" "auto_proceed")

    return 0
}

# ===============================================
# Load Site Mappings
# ===============================================
#
# Description: Loads all multisite mappings from config into associative arrays.
#
# Parameters:
#	- $1: Path to the configuration file (wpdb-import.conf).
#
# Returns:
#	- Implicitly populates global associative arrays (BLOG_ID_MAP, OLD_DOMAIN_MAP, NEW_DOMAIN_MAP).
#
# Behavior:
#	- Attempts to use native Bash/Zsh associative arrays (Bash 4.0+ required).
#	- Falls back to compatibility functions if available.
#	- Requires `get_site_mappings` function to be available.
#
load_site_mappings() {
    local config_path="$1"

    # Clear any existing arrays
    unset BLOG_ID_MAP OLD_DOMAIN_MAP NEW_DOMAIN_MAP

    # Create associative arrays with enhanced shell compatibility
    local use_arrays=false

    # Check if associative arrays are available using compatibility system
    if has_bash_feature "associative_arrays" 2>/dev/null; then
        # Bash 4.0+: Use native associative arrays
        if declare -A BLOG_ID_MAP OLD_DOMAIN_MAP NEW_DOMAIN_MAP 2>/dev/null; then
            use_arrays=true
        else
            # Fallback to compatibility functions
            init_associative_array "BLOG_ID_MAP"
            init_associative_array "OLD_DOMAIN_MAP"
            init_associative_array "NEW_DOMAIN_MAP"
            use_arrays=true
        fi
    elif [[ -n "${ZSH_VERSION:-}" ]]; then
        # Running in zsh - use typeset for associative arrays
        if typeset -A BLOG_ID_MAP OLD_DOMAIN_MAP NEW_DOMAIN_MAP 2>/dev/null; then
            use_arrays=true
        else
            # Fallback to compatibility functions
            init_associative_array "BLOG_ID_MAP"
            init_associative_array "OLD_DOMAIN_MAP"
            init_associative_array "NEW_DOMAIN_MAP"
            use_arrays=true
        fi
    else
        # Use compatibility functions for other shells
        init_associative_array "BLOG_ID_MAP"
        init_associative_array "OLD_DOMAIN_MAP"
        init_associative_array "NEW_DOMAIN_MAP"
        use_arrays=true
    fi

    # Fallback if all methods fail
    if [[ "$use_arrays" != "true" ]]; then
        BLOG_ID_MAP=""
        OLD_DOMAIN_MAP=""
        NEW_DOMAIN_MAP=""
    fi

    local mappings
    mappings=$(get_site_mappings "$config_path")

    if [[ -n "$mappings" && "$use_arrays" == true ]]; then
        while IFS=':' read -r blog_id old_domain new_domain; do
            BLOG_ID_MAP["$blog_id"]="$new_domain"
            OLD_DOMAIN_MAP["$blog_id"]="$old_domain"
            NEW_DOMAIN_MAP["$blog_id"]="$new_domain"  # Use blog_id instead of old_domain
        done <<< "$mappings"
    fi
}

# ===============================================
# Has Site Mapping
# ===============================================
#
# Description: Checks if a site mapping exists for a given blog ID in the config file.
#
# Parameters:
#	- $1: The Blog ID to check.
#	- $2: Optional. Path to the configuration file.
#
# Returns:
#	- 0 (Success) if a non-empty mapping is found.
#	- 1 (Failure) otherwise.
#
# Behavior:
#	- Requires `get_site_mapping` function to be available.
#
has_site_mapping() {
    local blog_id="$1"
    local config_path="${2:-}"

    # Ensure config_path is provided
    [[ -z "$config_path" ]] && return 1

    # Direct approach: check if get_site_mapping returns a non-empty result
    local mapping_result
    mapping_result=$(get_site_mapping "$config_path" "$blog_id" 2>/dev/null)

    # Return success if mapping exists and is non-empty
    [[ -n "$mapping_result" ]]
}

# ===============================================
# Get Mapped Domain
# ===============================================
#
# Description: Retrieves the new (local) domain for a given blog ID.
#
# Parameters:
#	- $1: The Blog ID.
#	- $2: Optional. Path to the configuration file.
#
# Returns:
#	- The new domain string (echoed) if found.
#	- Empty string (echoed) if not found.
#
# Behavior:
#	- Prefers reading from the loaded global associative arrays (if available).
#	- Falls back to reading directly from the config file via `get_site_mapping`.
#
get_mapped_domain() {
    local blog_id="$1"
    local config_path="${2:-}"

    # Check if we have associative arrays available
    if [[ -n "${BASH_VERSION:-}" && ${BASH_VERSION%%.*} -ge 4 ]] || [[ -n "${ZSH_VERSION:-}" ]]; then
        if [[ "${#BLOG_ID_MAP[@]}" -gt 0 ]] 2>/dev/null; then
            echo "${BLOG_ID_MAP[$blog_id]:-}" 2>/dev/null || echo ""
        else
            # Fallback: read from config file directly
            [[ -n "$config_path" ]] && get_site_mapping "$config_path" "$blog_id" 2>/dev/null || echo ""
        fi
    else
        # Fallback: read from config file directly
        [[ -n "$config_path" ]] && get_site_mapping "$config_path" "$blog_id" 2>/dev/null || echo ""
    fi
}

# ===============================================
# Handle Missing Mappings
# ===============================================
#
# Description: Prompts the user to configure missing site mappings and updates the config file.
#
# Parameters:
#	- $1: Path to the configuration file.
#	- $2: CSV string of detected sites (format: blog_id,domain,path).
#	- $3: Optional. The new base domain provided by the user (to suggest defaults).
#
# Returns:
#	- 0 (Success) after attempting to update mappings.
#	- Prints status updates to the user.
#
# Behavior:
#	- Determines a default local URL based on the main site's new domain and the site's path/subdomain.
#	- Requires `update_site_mapping` and `get_site_mappings` to be available.
#
handle_missing_mappings() {
    local config_path="$1"
    local detected_sites="$2"  # CSV format: blog_id,domain,path
    local new_base_domain="${3:-}"  # NEW domain from user input

    # Load existing mappings first
    load_site_mappings "$config_path"

    # Count total sites and existing mappings
    local total_sites=0
    local mapped_sites=0
    local missing_sites=()
    local temp_file=$(mktemp)

    # Create temporary file to avoid stdin conflicts with user input
    echo "$detected_sites" > "$temp_file"

    # First pass: count and identify missing mappings
    while IFS=',' read -r blog_id domain path; do
        # Skip empty lines and header
        [[ -z "$blog_id" || "$blog_id" == "blog_id" ]] && continue

        total_sites=$((total_sites + 1))

        if has_site_mapping "$blog_id" "$config_path"; then
            mapped_sites=$((mapped_sites + 1))
        else
            missing_sites+=("$blog_id,$domain,$path")
        fi
    done < "$temp_file"

    printf "\n${CYAN}${BOLD}🗺️  Site Mapping Configuration${RESET}\n"
    printf "===============================\n\n"

    # Show existing mappings summary
    if [[ $mapped_sites -gt 0 ]]; then
        printf "${GREEN}✅ Found existing mappings for %d/%d sites:${RESET}\n\n" "$mapped_sites" "$total_sites"

        # Display existing mappings in a compact format
        local mappings
        mappings=$(get_site_mappings "$config_path")

        if [[ -n "$mappings" ]]; then
            printf "  %-8s %-35s → %s\n" "Blog ID" "Production Domain" "Local Domain"
            printf "  %-8s %-35s   %s\n" "-------" "-----------------" "------------"

            while IFS=':' read -r blog_id old_domain new_domain; do
                printf "  %-8s %-35s → ${GREEN}%s${RESET}\n" "$blog_id" "$old_domain" "$new_domain"
            done <<< "$mappings"
            printf "\n"
        fi
    fi

    # If all sites are mapped, skip prompting
    if [[ ${#missing_sites[@]} -eq 0 ]]; then
        printf "${GREEN}🎉 All sites are already mapped! Proceeding with existing configuration.${RESET}\n\n"
        rm -f "$temp_file"
        return 0
    fi

    # Show missing sites that need mapping
    printf "${YELLOW}⚠️  Missing mappings for %d sites:${RESET}\n\n" "${#missing_sites[@]}"

    local updated=false

    # Second pass: only process missing mappings
    for missing_site in "${missing_sites[@]}"; do
        IFS=',' read -r blog_id domain path <<< "$missing_site"

        printf "  ${CYAN}📍 Site %s${RESET} \n" "$blog_id"
        printf "     🌐 Domain: %s\n" "$domain"
        printf "     📁 Path:   %s\n" "$path"

        local default_url=""
        # Use the NEW domain from user input, fall back to config, then local.test
        local base_domain="${new_base_domain:-${CONFIG_NEW_DOMAIN:-local.test}}"

        if [[ "$blog_id" == "1" ]]; then
            echo ""
            printf "     💡 Suggested URL: %s \n" "$base_domain"
            printf "     🔗 Local URL: "
            default_url="$base_domain"
        else
            # Remove protocol if present from base domain
            base_domain="${base_domain#http://}"
            base_domain="${base_domain#https://}"

            # Prioritize existing path over subdomain extraction when path is not just "/"
            if [[ -n "$path" && "$path" != "/" ]]; then
                # Use the existing path (remove leading/trailing slashes for clean concatenation)
                local clean_path="${path#/}"
                clean_path="${clean_path%/}"
                default_url="${base_domain}/${clean_path}"
            else
                # Fallback to subdomain extraction for default suggestion
                local subdomain=$(echo "$domain" | cut -d'.' -f1)
                default_url="${base_domain}/${subdomain}"
            fi
            echo ""
            printf "     💡 Suggested URL: %s \n" "$default_url"
            printf "     🔗 Local URL: "
        fi

        local new_domain_input
        # Pause timer for user input
        pause_script_timer
        # Read from stdin (terminal) explicitly to avoid CSV input conflicts
        read -r new_domain_input < /dev/tty
        # Resume timer after user input
        resume_script_timer
        new_domain_input="${new_domain_input:-$default_url}"

        # Clean the URL (remove protocols and trailing slashes)
        if [[ "$new_domain_input" =~ ^https?:// ]]; then
            printf "     🧹 Cleaned: '%s' → '%s'\n" "$new_domain_input" "${new_domain_input#http*://}"
            new_domain_input="${new_domain_input#http*://}"
        fi
        new_domain_input="${new_domain_input%/}"

        local local_site_path="$path"
        if [[ "$installation_type" == "multisite" ]]; then
            if [[ "$multisite_type" == "subdirectory" ]]; then
                if [[ "$blog_id" != "1" ]]; then
                    if [[ -n "$path" && "$path" != "/" ]]; then
                        local local_clean_path="${path#/}"
                        local_site_path="/${local_clean_path%/}"
                    else
                        local local_subdomain=$(echo "$domain" | cut -d'.' -f1)
                        local_site_path="/${local_subdomain}"
                    fi

                    # Override path if user specified a path in the new domain.
                    if [[ -n $new_domain_input ]]; then
                        local new_domain_path=$(echo "$new_domain_input" | cut -d'/' -f2)
                        local_site_path="/${new_domain_path}"
                    fi
                fi # ! Blog ID 1
            fi # if Subdirectory
        fi # if Multisite

        echo ""
        # printf "  └──────────────────────────────────────────────────────────\n"
        printf "   ${GREEN}✔ Mapping confirmed:${RESET}\n"
        printf "     ${YELLOW}%s${RESET} → ${GREEN}%s${RESET}\n" "$domain" "$new_domain_input"
        printf "     (Blog ID: %s, Path: %s)\n\n" "$blog_id" "$local_site_path"
        echo ""

        # Construct old domain with path for config storage when path is meaningful
        local config_old_domain="$domain"
        if [[ -n "$path" && "$path" != "/" ]]; then
            # Remove trailing slash from path for clean concatenation
            local clean_path="${path%/}"
            config_old_domain="${domain}${clean_path}"
        fi

        # Save mapping to config
        if update_site_mapping "$config_path" "$blog_id" "$config_old_domain" "$new_domain_input"; then
            # Update CONFIG_NEW_DOMAIN for main site to use for subsequent defaults
            if [[ "$blog_id" == "1" ]]; then
                CONFIG_NEW_DOMAIN="$new_domain_input"
                export CONFIG_NEW_DOMAIN
            fi

            updated=true
        else
            printf "${RED}❌ Failed to save mapping for Blog ID %s${RESET}\n" "$blog_id"
        fi
    done

    rm -f "$temp_file"

    if [[ "$updated" == true ]]; then
        printf "${GREEN}✅ Configuration updated with new site mappings${RESET}\n\n"
    fi

    return 0
}

# ===============================================
# Show Configured Mappings
# ===============================================
#
# Description: Displays all currently configured site mappings in a clean, tabular format.
#
# Parameters:
#	- None (relies on loaded global arrays or config file path via dependency).
#
# Returns:
#	- Prints the formatted table of mappings to stdout.
#	- 0 (Success) always.
#
# Behavior:
#	- Prefers global arrays if loaded.
#	- Falls back to reading directly from the config file via `get_site_mappings`.
#
show_configured_mappings() {
    printf "\n${CYAN}${BOLD}🗺️ Configured Site Mappings${RESET}\n"
    printf "============================\n"

    if [[ "$use_arrays" == true ]]; then
        if [[ ${#BLOG_ID_MAP[@]} -eq 0 ]]; then
            printf "${YELLOW}No site mappings configured${RESET}\n\n"
            return 0
        fi

        printf "%-8s %-35s → %s\n" "Blog ID" "Old Domain" "New Domain"
        printf "%-8s %-35s   %s\n" "-------" "----------" "----------"

        for blog_id in $(printf '%s\n' "${!BLOG_ID_MAP[@]}" | sort -n); do
            local old_domain="${OLD_DOMAIN_MAP[$blog_id]}"
            local new_domain="${BLOG_ID_MAP[$blog_id]}"
            printf "%-8s %-35s → ${GREEN}%s${RESET}\n" "$blog_id" "$old_domain" "$new_domain"
        done
    else
        # Fallback: read mappings from config file
        local mappings
        mappings=$(get_site_mappings "$config_path")

        if [[ -z "$mappings" ]]; then
            printf "${YELLOW}No site mappings configured${RESET}\n\n"
            return 0
        fi

        printf "%-8s %-35s → %s\n" "Blog ID" "Old Domain" "New Domain"
        printf "%-8s %-35s   %s\n" "-------" "----------" "----------"

        while IFS=':' read -r blog_id old_domain new_domain; do
            printf "%-8s %-35s → ${GREEN}%s${RESET}\n" "$blog_id" "$old_domain" "$new_domain"
        done <<< "$mappings"
    fi

    printf "\n"
}

# ===============================================
# Get Config Prompt Value
# ===============================================
#
# Description: Displays a prompt, auto-populating the answer from global config variables if available.
#
# Parameters:
#	- $1: The prompt text to display.
#	- $2: The config key name (e.g., "sql_file").
#	- $3: The default value to use if the user enters nothing and config is empty.
#
# Returns:
#	- The final determined value (config value, user input, or default) (echoed).
#
# Behavior:
#	- Automatically uses global CONFIG_* variables.
#	- If config value is present, displays it and uses it without prompting for input.
#
get_config_prompt_value() {
    local prompt_text="$1"
    local config_key="$2"
    local default_value="$3"

    local config_value=""
    case "$config_key" in
        "sql_file")
            config_value="$CONFIG_SQL_FILE"
            ;;
        "old_domain")
            config_value="$CONFIG_OLD_DOMAIN"
            ;;
        "new_domain")
            config_value="$CONFIG_NEW_DOMAIN"
            ;;
    esac

    # If we have a config value, auto-populate and show it
    if [[ -n "$config_value" ]]; then
        printf "%s ${GREEN}%s${RESET} (from config)\n" "$prompt_text" "$config_value"
        echo "$config_value"
    else
        # No config value, prompt user
        printf "%s" "$prompt_text"
        local user_input
        read -r user_input
        echo "${user_input:-$default_value}"
    fi
}

# ===============================================
# Build WP-CLI Flags
# ===============================================
#
# Description: Constructs a string of WP-CLI flags (e.g., --all-tables) based on config settings.
#
# Parameters:
#	- None (relies on global CONFIG_* variables).
#
# Returns:
#	- A space-separated string of active WP-CLI flags (echoed).
#
# Behavior:
#	- Requires `is_config_true` function to be available.
#
build_wp_cli_flags() {
    local flags=()

    # Add --all-tables flag if configured
    if is_config_true "$CONFIG_ALL_TABLES"; then
        flags+=("--all-tables")
    fi

    # Add --dry-run flag if configured
    if is_config_true "$CONFIG_DRY_RUN"; then
        flags+=("--dry-run")
    fi

    # Return flags as a string
    printf '%s ' "${flags[@]}"
}

# ===============================================
# Save Import Values To Config
# ===============================================
#
# Description: Updates general config settings with values provided during the import run if they differ from existing config.
#
# Parameters:
#	- $1: Path to the config file.
#	- $2: SQL file name.
#	- $3: Old domain.
#	- $4: New domain.
#	- $5-9: Optional. Boolean flags (all_tables, dry_run, clear_revisions, setup_stage_proxy, auto_proceed).
#
# Returns:
#	- Implicitly updates the config file.
#	- 0 (Success) always.
#
# Behavior:
#	- Requires `update_config_general` to be available.
#	- Only updates if the provided value is non-empty AND differs from the global CONFIG_* variable.
#
save_import_values_to_config() {
    local config_path="$1"
    local sql_file="$2"
    local old_domain="$3"
    local new_domain="$4"
    local all_tables="${5:-}"
    local dry_run="${6:-}"
    local clear_revisions="${7:-}"
    local setup_stage_proxy="${8:-}"
    local auto_proceed="${9:-}"

    # Update general settings if they were provided by user and differ from config
    if [[ -n "$sql_file" && "$sql_file" != "$CONFIG_SQL_FILE" ]]; then
        update_config_general "$config_path" "sql_file" "$sql_file"
    fi

    if [[ -n "$old_domain" && "$old_domain" != "$CONFIG_OLD_DOMAIN" ]]; then
        update_config_general "$config_path" "old_domain" "$old_domain"
    fi

    if [[ -n "$new_domain" && "$new_domain" != "$CONFIG_NEW_DOMAIN" ]]; then
        update_config_general "$config_path" "new_domain" "$new_domain"
    fi

    if [[ -n "$all_tables" && "$all_tables" != "$CONFIG_ALL_TABLES" ]]; then
        update_config_general "$config_path" "all_tables" "$all_tables"
    fi

    if [[ -n "$dry_run" && "$dry_run" != "$CONFIG_DRY_RUN" ]]; then
        update_config_general "$config_path" "dry_run" "$dry_run"
    fi

    if [[ -n "$clear_revisions" && "$clear_revisions" != "$CONFIG_CLEAR_REVISIONS" ]]; then
        update_config_general "$config_path" "clear_revisions" "$clear_revisions"
    fi

    if [[ -n "$setup_stage_proxy" && "$setup_stage_proxy" != "$CONFIG_SETUP_STAGE_PROXY" ]]; then
        update_config_general "$config_path" "setup_stage_proxy" "$setup_stage_proxy"
    fi

    if [[ -n "$auto_proceed" && "$auto_proceed" != "$CONFIG_AUTO_PROCEED" ]]; then
        update_config_general "$config_path" "auto_proceed" "$auto_proceed"
    fi
}

# ===============================================
# Validate Config Domains
# ===============================================
#
# Description: Compares the old domain in the config file against the domain detected in the database/SQL file.
#
# Parameters:
#	- $1: Path to the config file.
#	- $2: The 'old_domain' detected in the SQL file.
#
# Returns:
#	- 0 (Success) if domains match or if the user chooses to update/keep the config domain.
#	- The domain to use (echoed) if the user chooses option 2 (use config domain).
#	- 1 (Failure) if the user cancels or editing fails.
#
# Behavior:
#	- Prompts the user for action if a mismatch is detected.
#	- Requires `parse_config_section`, `update_config_general`, and `sanitize_domain` (not defined here, assumed external) to be available.
#
validate_config_domains() {
    local config_path="$1"
    local old_domain="$2"

    if [[ ! -f "$config_path" || -z "$old_domain" ]]; then
        return 0  # Skip validation if no config or domain
    fi

    # Get the configured old domain
    local config_old_domain
    config_old_domain=$(parse_config_section "$config_path" "general" "old_domain")

    if [[ -z "$config_old_domain" ]]; then
        return 0  # No configured domain to validate
    fi

    # Clean both domains for comparison
    local cleaned_config_domain=$(sanitize_domain "$config_old_domain")
    local cleaned_input_domain=$(sanitize_domain "$old_domain")

    # Check if domains match
    if [[ "$cleaned_config_domain" != "$cleaned_input_domain" ]]; then
        printf "\n${RED}❌ Domain Mismatch Detected!${RESET}\n"
        printf "================================================================\n"
        printf "Config file domain: ${YELLOW}%s${RESET}\n" "$config_old_domain"
        printf "Database domain:    ${YELLOW}%s${RESET}\n" "$old_domain"
        printf "================================================================\n\n"
        printf "${YELLOW}The domain in your config file doesn't match the domain detected in the database.${RESET}\n"
        printf "This could happen if:\n"
        printf "  • You're using the wrong SQL file\n"
        printf "  • The config file is from a different project\n"
        printf "  • The production domain has changed\n\n"

        printf "Would you like to:\n"
        printf "  ${GREEN}1${RESET}) Update config file with new domain (${CYAN}%s${RESET})\n" "$old_domain"
        printf "  ${GREEN}2${RESET}) Keep config domain and use it instead (${CYAN}%s${RESET})\n" "$config_old_domain"
        printf "  ${GREEN}3${RESET}) Edit config file manually\n"
        printf "  ${RED}4${RESET}) Cancel import\n\n"

        local choice
        printf "Enter your choice (1-4): "
        read -r choice

        case "$choice" in
            1)
                # Update config with new domain
                update_config_general "$config_path" "old_domain" "$old_domain"
                printf "\n${GREEN}✅ Config updated with new domain: %s${RESET}\n\n" "$old_domain"
                return 0
                ;;
            2)
                # Use config domain - update the input variable reference
                printf "\n${GREEN}✅ Using config domain: %s${RESET}\n\n" "$config_old_domain"
                # Return the config domain to be used
                echo "$config_old_domain"
                return 0
                ;;
            3)
                # Edit config manually
                local editor="${EDITOR:-nano}"
                if command -v "$editor" >/dev/null 2>&1; then
                    printf "\n${CYAN}Opening config file for editing...${RESET}\n"
                    "$editor" "$config_path"
                    printf "\n${GREEN}Please run the import again after editing the config.${RESET}\n"
                else
                    printf "\n${RED}❌ Editor not found: $editor${RESET}\n"
                    printf "Set EDITOR environment variable or edit manually: %s\n" "$config_path"
                fi
                return 1
                ;;
            4|*)
                # Cancel import
                printf "\n${YELLOW}⚠️  Import cancelled. Please resolve the domain mismatch.${RESET}\n"
                return 1
                ;;
        esac
    fi

    return 0  # Domains match, continue
}

# ===============================================
# Detect Database Domain
# ===============================================
#
# Description: Attempts to detect the primary domain from the database using WP-CLI after an import.
#
# Parameters:
#	- $1: WordPress root path.
#
# Returns:
#	- The detected domain (e.g., "example.com") (echoed) if successful.
#	- Returns 1 (Failure) if WP-CLI is not available or domain cannot be read.
#
# Behavior:
#	- Relies on external functions like `execute_wp_cli` (not defined here, assumed external).
#	- Tries to read 'siteurl' first, then 'home'.
#
detect_database_domain() {
    local wp_root="$1"

    if [[ -z "$WP_COMMAND" ]]; then
        return 1
    fi

    # Try to get the site URL from the database
    local site_url
    if site_url=$(execute_wp_cli option get siteurl 2>/dev/null); then
        # Extract domain from URL
        local domain=$(echo "$site_url" | sed -E 's|^https?://([^/]+).*|\1|')
        if [[ -n "$domain" ]]; then
            echo "$domain"
            return 0
        fi
    fi

    # Fallback: try to get home URL
    if site_url=$(execute_wp_cli option get home 2>/dev/null); then
        local domain=$(echo "$site_url" | sed -E 's|^https?://([^/]+).*|\1|')
        if [[ -n "$domain" ]]; then
            echo "$domain"
            return 0
        fi
    fi

    return 1
}

# Export functions for use in main script
export -f load_import_config
export -f load_site_mappings
export -f has_site_mapping
export -f get_mapped_domain
export -f handle_missing_mappings
export -f show_configured_mappings
export -f get_config_prompt_value
export -f build_wp_cli_flags
export -f save_import_values_to_config
export -f validate_config_domains
export -f detect_database_domain
