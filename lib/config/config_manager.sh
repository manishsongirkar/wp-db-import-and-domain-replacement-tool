#!/usr/bin/env bash

# ===============================================
# Configuration Manager for WordPress Import Tool
# ===============================================
#
# Description:
#   This module handles all aspects of the tool's INI-style configuration file,
#   including location finding, creation, parsing, validation, and updating
#   for both general settings and multisite mappings.
#
# Config File Location:
#   - Searches for 'wpdb-import.conf' in the WordPress root directory
#     (same directory as wp-config.php)
#
# Config File Format:
#   [general]
#   sql_file=vip-db.sql
#   old_domain=mobility-admin.coxautoinc.com
#   new_domain=coxautoinc-mobility.test
#   all_tables=true
#   dry_run=false
#
#   [site_mappings]
#   # Format: blog_id:old_domain:new_domain
#   1:blog.example.com:example.test/blog
#   2:news.example.com:example.test/news
#   3:news.example.com:example.test/news
#
# ===============================================

# Global config file name (constant)
readonly CONFIG_FILE_NAME="wpdb-import.conf"

# ===============================================
# Find WP Root
# ===============================================
#
# Description: Searches up the directory tree to find the WordPress root directory.
#
# Parameters:
#	- None
#
# Returns:
#	- WordPress root path (echoed) on success
#	- Returns 1 if wp-config.php not found
#
# Behavior:
#	- Starts from current directory and moves up
#	- Looks for wp-config.php file
#	- Returns the directory containing wp-config.php
#
find_wp_root() {
    local current_dir="$(pwd)"
    local wp_root="$current_dir"

    # Search for wp-config.php up the directory tree
    while [[ "$wp_root" != "/" && ! -f "$wp_root/wp-config.php" ]]; do
        wp_root=$(dirname "$wp_root")
    done

    if [[ -f "$wp_root/wp-config.php" ]]; then
        echo "$wp_root"
        return 0
    else
        return 1
    fi
}

# ===============================================
# Get Config File Path
# ===============================================
#
# Description: Determines the full, expected path of the configuration file.
#
# Parameters:
#	- None
#
# Returns:
#	- Full config file path (echoed) on success
#	- Returns 1 if the WordPress root directory cannot be found
#
get_config_file_path() {
    local wp_root
    if wp_root=$(find_wp_root); then
        echo "$wp_root/$CONFIG_FILE_NAME"
        return 0
    else
        return 1
    fi
}

# ===============================================
# Config File Exists
# ===============================================
#
# Description: Checks if the configuration file is present at its expected location.
#
# Parameters:
#	- None
#
# Returns:
#	- 0 (Success) if the file exists
#	- 1 (Failure) if the file does not exist or WP root is not found
#
config_file_exists() {
    local config_path
    if config_path=$(get_config_file_path); then
        [[ -f "$config_path" ]]
    else
        return 1
    fi
}

# ===============================================
# Create Config File
# ===============================================
#
# Description: Creates a new configuration file with a basic structure and default settings.
#
# Parameters:
#	- $1: Path where the config file should be created.
#	- $2: Optional. Default SQL file name.
#	- $3: Optional. Default old domain.
#	- $4: Optional. Default new domain.
#
# Returns:
#	- 0 (Success) on successful creation
#	- 1 (Failure) on error
#
create_config_file() {
    local config_path="$1"
    local sql_file="${2:-vip-db.sql}"
    local old_domain="${3:-}"
    local new_domain="${4:-}"

    cat > "$config_path" << EOF
# ===============================================
# WordPress Database Import Configuration
# ===============================================
# This file stores your import settings to avoid re-entering them each time.
# Edit this file to customize your import settings.

[general]
sql_file=$sql_file
old_domain=$old_domain
new_domain=$new_domain
all_tables=true
dry_run=false
clear_revisions=true
setup_stage_proxy=true
auto_proceed=false

[site_mappings]
# Format:
# blog_id:old_domain:new_domain

# Example:
# 1:production-site.com:local-site.test

# Add your multisite mappings below:

EOF

    if [[ $? -eq 0 ]]; then
        printf "${GREEN}✅ Configuration file created: ${CYAN}%s${RESET}\n" "$config_path"
        return 0
    else
        printf "${RED}❌ Failed to create configuration file: %s${RESET}\n" "$config_path"
        return 1
    fi
}

# ===============================================
# Parse Config Section
# ===============================================
#
# Description: Extracts the value of a specific key within a specific INI section.
#
# Parameters:
#	- $1: Path to the config file.
#	- $2: The INI section name (e.g., "general"). Case-insensitive.
#	- $3: The key name (e.g., "sql_file"). Case-insensitive.
#
# Returns:
#	- The value of the key (echoed)
#	- Returns 1 if the config file does not exist
#
parse_config_section() {
    local config_path="$1"
    local section="$2"
    local key="$3"

    if [[ ! -f "$config_path" ]]; then
        return 1
    fi

    # Use awk to parse INI-style config
    awk -v section="$section" -v key="$key" '
        BEGIN {
            in_section = 0
            IGNORECASE = 1
        }
        /^\[.*\]/ {
            if ($0 ~ "\\[" section "\\]") {
                in_section = 1
            } else {
                in_section = 0
            }
            next
        }
        in_section && $0 ~ "^" key "=" {
            sub("^" key "=", "")
            sub(/^[ \t]+/, "")  # Remove leading whitespace
            sub(/[ \t]+$/, "")  # Remove trailing whitespace
            print $0
            exit
        }
    ' "$config_path"
}

# ===============================================
# Get Site Mappings
# ===============================================
#
# Description: Extracts all valid site mapping entries from the [site_mappings] section.
#
# Parameters:
#	- $1: Path to the config file.
#
# Returns:
#	- A list of all site mapping lines (e.g., "1:old.com:new.test"), one per line (echoed)
#	- Returns 1 if the config file does not exist
#
get_site_mappings() {
    local config_path="$1"

    if [[ ! -f "$config_path" ]]; then
        return 1
    fi

    # Parse site_mappings section
    awk '
        BEGIN {
            in_section = 0
            IGNORECASE = 1
        }
        /^\[.*\]/ {
            if ($0 ~ "\\[site_mappings\\]") {
                in_section = 1
            } else {
                in_section = 0
            }
            next
        }
        in_section && /^[0-9]+:/ && !/^#/ {
            sub(/^[ \t]+/, "")  # Remove leading whitespace
            sub(/[ \t]+$/, "")  # Remove trailing whitespace
            print $0
        }
    ' "$config_path"
}

# ===============================================
# Get Site Mapping
# ===============================================
#
# Description: Retrieves the new domain for a specific blog ID from site mappings.
#
# Parameters:
#	- $1: Path to the config file.
#	- $2: The Blog ID (e.g., "1").
#
# Returns:
#	- The new domain string (echoed)
#	- Returns 1 if the mapping or config file is not found
#
get_site_mapping() {
    local config_path="$1"
    local blog_id="$2"

    if [[ ! -f "$config_path" ]]; then
        return 1
    fi

    # Get all mappings and filter for specific blog_id
    get_site_mappings "$config_path" | while IFS=':' read -r map_blog_id old_domain new_domain; do
        if [[ "$map_blog_id" == "$blog_id" ]]; then
            echo "$new_domain"
            return 0
        fi
    done

    return 1
}

# ===============================================
# Update Site Mapping
# ===============================================
#
# Description: Adds a new site mapping or updates an existing one for a given blog ID.
#
# Parameters:
#	- $1: Path to the config file.
#	- $2: The Blog ID (key for the mapping).
#	- $3: The old domain.
#	- $4: The new domain.
#
# Returns:
#	- 0 (Success) on successful update/add
#	- 1 (Failure) on error or if the config file is not found
#
update_site_mapping() {
    local config_path="$1"
    local blog_id="$2"
    local old_domain="$3"
    local new_domain="$4"

    if [[ ! -f "$config_path" ]]; then
        return 1
    fi

    local mapping_line="${blog_id}:${old_domain}:${new_domain}"
    local temp_file="$config_path.tmp"

    # Check if the mapping already exists
    if grep -q "^${blog_id}:" "$config_path" 2>/dev/null; then
        # Update existing mapping
        awk -v blog_id="$blog_id" -v new_mapping="$mapping_line" '
            BEGIN {
                in_section = 0
                updated = 0
                IGNORECASE = 1
            }
            /^\[.*\]/ {
                if ($0 ~ "\\[site_mappings\\]") {
                    in_section = 1
                } else {
                    in_section = 0
                }
                print $0
                next
            }
            in_section && $0 ~ "^" blog_id ":" {
                print new_mapping
                updated = 1
                next
            }
            { print $0 }
        ' "$config_path" > "$temp_file"
    else
        # Add new mapping
        awk -v blog_id="$blog_id" -v new_mapping="$mapping_line" '
            BEGIN {
                in_section = 0
                added = 0
                IGNORECASE = 1
            }
            /^\[.*\]/ {
                if ($0 ~ "\\[site_mappings\\]") {
                    in_section = 1
                    print $0
                    next
                } else if (in_section && !added) {
                    print new_mapping
                    added = 1
                    in_section = 0
                }
                print $0
                next
            }
            { print $0 }
            END {
                if (!added && in_section) {
                    print new_mapping
                }
            }
        ' "$config_path" > "$temp_file"
    fi

    if [[ -f "$temp_file" ]]; then
        mv "$temp_file" "$config_path"
        return 0
    else
        return 1
    fi
}

# ===============================================
# Update Config General
# ===============================================
#
# Description: Updates a single key-value pair within the [general] section.
#
# Parameters:
#	- $1: Path to the config file.
#	- $2: The key name to update.
#	- $3: The new value for the key.
#
# Returns:
#	- 0 (Success) on successful update/add
#	- 1 (Failure) on error or if the config file is not found
#
update_config_general() {
    local config_path="$1"
    local key="$2"
    local value="$3"

    if [[ ! -f "$config_path" ]]; then
        return 1
    fi

    local temp_file="$config_path.tmp"

    awk -v key="$key" -v value="$value" '
        BEGIN {
            in_section = 0
            updated = 0
            IGNORECASE = 1
        }
        /^\[.*\]/ {
            if ($0 ~ "\\[general\\]") {
                in_section = 1
            } else {
                if (in_section && !updated) {
                    print key "=" value
                    updated = 1
                }
                in_section = 0
            }
            print $0
            next
        }
        in_section && $0 ~ "^" key "=" {
            print key "=" value
            updated = 1
            next
        }
        { print $0 }
        END {
            if (!updated && in_section) {
                print key "=" value
            }
        }
    ' "$config_path" > "$temp_file"

    if [[ -f "$temp_file" ]]; then
        mv "$temp_file" "$config_path"
        return 0
    else
        return 1
    fi
}

# ===============================================
# Validate Config File
# ===============================================
#
# Description: Checks the config file for the presence of required sections and general settings.
#
# Parameters:
#	- $1: Path to the config file.
#
# Returns:
#	- 0 (Success) if the config is valid
#	- 1 (Failure) if validation fails (prints specific errors)
#
validate_config_file() {
    local config_path="$1"
    local errors=()

    if [[ ! -f "$config_path" ]]; then
        echo "Config file does not exist: $config_path"
        return 1
    fi

    # Check for required sections
    if ! grep -q '^\[general\]' "$config_path" 2>/dev/null; then
        errors+=("Missing [general] section")
    fi

    if ! grep -q '^\[site_mappings\]' "$config_path" 2>/dev/null; then
        errors+=("Missing [site_mappings] section")
    fi

    # Check for required general settings
    local sql_file old_domain new_domain all_tables dry_run clear_revisions setup_stage_proxy auto_proceed
    sql_file=$(parse_config_section "$config_path" "general" "sql_file")
    old_domain=$(parse_config_section "$config_path" "general" "old_domain")
    new_domain=$(parse_config_section "$config_path" "general" "new_domain")
    all_tables=$(parse_config_section "$config_path" "general" "all_tables")
    dry_run=$(parse_config_section "$config_path" "general" "dry_run")
    clear_revisions=$(parse_config_section "$config_path" "general" "clear_revisions")
    setup_stage_proxy=$(parse_config_section "$config_path" "general" "setup_stage_proxy")
    auto_proceed=$(parse_config_section "$config_path" "general" "auto_proceed")

    [[ -z "$sql_file" ]] && errors+=("Missing or empty sql_file setting")
    [[ -z "$old_domain" ]] && errors+=("Missing or empty old_domain setting")
    [[ -z "$new_domain" ]] && errors+=("Missing or empty new_domain setting")

    # Output errors if any
    if [[ ${#errors[@]} -gt 0 ]]; then
        printf "${RED}❌ Configuration validation failed:${RESET}\n"
        for error in "${errors[@]}"; do
            printf "   - %s\n" "$error"
        done
        return 1
    fi

    printf "${GREEN}✅ Configuration file is valid${RESET}\n"
    return 0
}

# ===============================================
# Show Config
# ===============================================
#
# Description: Displays the config file contents in a colorized, user-friendly format.
#
# Parameters:
#	- $1: Path to the config file.
#
# Returns:
#	- 0 (Success) on successful display
#	- 1 (Failure) if the config file is not found
#
show_config() {
    local config_path="$1"

    if [[ ! -f "$config_path" ]]; then
        printf "${RED}❌ Config file not found: %s${RESET}\n" "$config_path"
        return 1
    fi

    printf "${CYAN}${BOLD}📋 Current Configuration${RESET}\n"
    printf "==========================\n"
    printf "Config file: ${YELLOW}%s${RESET}\n\n" "$config_path"

    # Display general settings
    printf "${BOLD}General Settings:${RESET}\n"
    local sql_file old_domain new_domain all_tables dry_run clear_revisions setup_stage_proxy auto_proceed
    sql_file=$(parse_config_section "$config_path" "general" "sql_file")
    old_domain=$(parse_config_section "$config_path" "general" "old_domain")
    new_domain=$(parse_config_section "$config_path" "general" "new_domain")
    all_tables=$(parse_config_section "$config_path" "general" "all_tables")
    dry_run=$(parse_config_section "$config_path" "general" "dry_run")
    clear_revisions=$(parse_config_section "$config_path" "general" "clear_revisions")
    setup_stage_proxy=$(parse_config_section "$config_path" "general" "setup_stage_proxy")
    auto_proceed=$(parse_config_section "$config_path" "general" "auto_proceed")

    printf "  SQL File:          ${GREEN}%s${RESET}\n" "${sql_file:-not set}"
    printf "  Old Domain:        ${YELLOW}%s${RESET}\n" "${old_domain:-not set}"
    printf "  New Domain:        ${GREEN}%s${RESET}\n" "${new_domain:-not set}"
    printf "  All Tables:        ${CYAN}%s${RESET}\n" "${all_tables:-false}"
    printf "  Dry Run:           ${CYAN}%s${RESET}\n" "${dry_run:-false}"
    printf "  Clear Revisions:   ${CYAN}%s${RESET}\n" "${clear_revisions:-true}"
    printf "  Setup Stage Proxy: ${CYAN}%s${RESET}\n" "${setup_stage_proxy:-true}"
    printf "  Auto Proceed:      ${CYAN}%s${RESET}\n" "${auto_proceed:-false}"

    # Display site mappings
    printf "\n${BOLD}Site Mappings:${RESET}\n"
    local mappings
    mappings=$(get_site_mappings "$config_path")

    if [[ -n "$mappings" ]]; then
        printf "  %-8s %-30s → %s\n" "Blog ID" "Old Domain" "New Domain"
        printf "  %-8s %-30s   %s\n" "-------" "-----------" "-----------"
        while IFS=':' read -r blog_id old_dom new_dom; do
            printf "  %-8s %-30s → ${GREEN}%s${RESET}\n" "$blog_id" "$old_dom" "$new_dom"
        done <<< "$mappings"
    else
        printf "  ${YELLOW}No site mappings configured${RESET}\n"
    fi

    printf "\n"
}

# ===============================================
# Get Config Value
# ===============================================
#
# Description: Retrieves a config value, falling back to a default value if not found.
#
# Parameters:
#	- $1: Path to the config file.
#	- $2: The section name.
#	- $3: The key name.
#	- $4: Optional. The default value to use if the key is missing or empty.
#
# Returns:
#	- The config value or the default value (echoed)
#
get_config_value() {
    local config_path="$1"
    local section="$2"
    local key="$3"
    local default_value="${4:-}"

    local value
    if [[ -f "$config_path" ]]; then
        value=$(parse_config_section "$config_path" "$section" "$key")
    fi

    echo "${value:-$default_value}"
}

# ===============================================
# Prompt and Save Config
# ===============================================
#
# Description: Prompts the user for missing required configuration values and saves them.
#
# Parameters:
#	- $1: Path to the config file.
#	- $2: The WordPress root directory path.
#
# Returns:
#	- 0 (Success) on successful configuration
#	- 1 (Failure) on error creating/updating the config file
#
prompt_and_save_config() {
    local config_path="$1"
    local wp_root="$2"

    printf "${CYAN}${BOLD}🔧 Configuration Setup${RESET}\n"
    printf "======================\n\n"

    # Create config file if it doesn't exist
    if [[ ! -f "$config_path" ]]; then
        printf "${YELLOW}📝 Config file not found. Creating new configuration...${RESET}\n\n"

        # Prompt for basic settings
        local sql_file old_domain new_domain all_tables dry_run clear_revisions setup_stage_proxy auto_proceed

        printf "📦 Enter SQL file name (default: vip-db.sql): "
        read -r sql_file
        sql_file=${sql_file:-vip-db.sql}

        printf "🌍 Enter the OLD (production) domain to search for: "
        read -r old_domain

        printf "🏠 Enter the NEW (local) domain/base URL to replace with: "
        read -r new_domain

        printf "Include --all-tables? (Y/n): "
        read -r all_tables
        all_tables=${all_tables:-y}
        [[ "$all_tables" == [Yy]* ]] && all_tables="true" || all_tables="false"

        printf "Run in dry-run mode by default? (y/N): "
        read -r dry_run
        dry_run=${dry_run:-n}
        [[ "$dry_run" == [Yy]* ]] && dry_run="true" || dry_run="false"

        printf "Clear post revisions by default? (Y/n): "
        read -r clear_revisions
        clear_revisions=${clear_revisions:-y}
        [[ "$clear_revisions" == [Yy]* ]] && clear_revisions="true" || clear_revisions="false"

        printf "Setup stage file proxy by default? (Y/n): "
        read -r setup_stage_proxy
        setup_stage_proxy=${setup_stage_proxy:-y}
        [[ "$setup_stage_proxy" == [Yy]* ]] && setup_stage_proxy="true" || setup_stage_proxy="false"

        printf "Auto-proceed without confirmations? (y/N): "
        read -r auto_proceed
        auto_proceed=${auto_proceed:-n}
        [[ "$auto_proceed" == [Yy]* ]] && auto_proceed="true" || auto_proceed="false"        # Create the config file
        if ! create_config_file "$config_path" "$sql_file" "$old_domain" "$new_domain"; then
            return 1
        fi

        # Update all general settings
        update_config_general "$config_path" "sql_file" "$sql_file"
        update_config_general "$config_path" "old_domain" "$old_domain"
        update_config_general "$config_path" "new_domain" "$new_domain"
        update_config_general "$config_path" "all_tables" "$all_tables"
        update_config_general "$config_path" "dry_run" "$dry_run"
        update_config_general "$config_path" "clear_revisions" "$clear_revisions"
        update_config_general "$config_path" "setup_stage_proxy" "$setup_stage_proxy"
        update_config_general "$config_path" "auto_proceed" "$auto_proceed"

        printf "\n${GREEN}✅ Basic configuration saved!${RESET}\n"
        printf "${YELLOW}💡 You can edit ${config_path} to add site mappings and customize options.${RESET}\n\n"
    fi

    return 0
}

# ===============================================
# Is Config True
# ===============================================
#
# Description: Checks if a configuration value represents a boolean 'true' state.
#
# Parameters:
#	- $1: The value to check (case-insensitive: 'true', 'yes', '1', 'on').
#
# Returns:
#	- 0 (Success) if the value is true
#	- 1 (Failure) if the value is false
#
is_config_true() {
    local value="$1"
    # Convert to lowercase using tr for compatibility
    local lower_value
    lower_value=$(echo "$value" | tr '[:upper:]' '[:lower:]')
    [[ "$lower_value" =~ ^(true|yes|1|on)$ ]]
}

# Export functions for use in other modules
export -f find_wp_root
export -f get_config_file_path
export -f config_file_exists
export -f create_config_file
export -f parse_config_section
export -f get_site_mappings
export -f get_site_mapping
export -f update_site_mapping
export -f update_config_general
export -f validate_config_file
export -f show_config
export -f get_config_value
export -f prompt_and_save_config
export -f is_config_true
