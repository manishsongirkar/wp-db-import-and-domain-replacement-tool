#!/bin/bash

# ===============================================
# Unified Configuration Reader for WordPress Import Tool
# ===============================================
#
# Description:
#   Unified module that consolidates all configuration reading, writing, and validation
#   functionality for wpdb-import.conf. This module eliminates code duplication and
#   provides a single interface for all config operations.
#
# Features:
#   - Auto-detects WordPress root directory
#   - Reads/writes wpdb-import.conf file
#   - Handles [general] and [site_mappings] sections
#   - Validates configuration data
#   - Provides fallback mechanisms
#   - Bash 3.2+ compatible (macOS default shell support)
#
# Config File Location:
#   - WordPress root directory (same as wp-config.php)
#   - Filename: wpdb-import.conf
#
# Dependencies:
#   - config_manager.sh (leverages existing functions)
#   - Works standalone when config_manager is not available
#
# ===============================================

# Source config_manager if available (for compatibility)
if [[ -f "$(dirname "${BASH_SOURCE[0]}")/config_manager.sh" ]]; then
    source "$(dirname "${BASH_SOURCE[0]}")/config_manager.sh"
fi

# Constants
readonly WPDB_CONFIG_FILE_NAME="wpdb-import.conf"

# ===============================================
# Core Configuration Detection Functions
# ===============================================

# Check if wpdb-import.conf exists in WordPress root
wpdb_config_exists() {
    local config_path
    config_path=$(get_wpdb_config_path)
    [[ -f "$config_path" ]]
}

# Get full path to wpdb-import.conf
get_wpdb_config_path() {
    if command -v get_config_file_path >/dev/null 2>&1; then
        # Use config_manager function if available
        get_config_file_path
    else
        # Standalone implementation
        local wp_root
        wp_root=$(find_wordpress_root)
        if [[ $? -eq 0 && -n "$wp_root" ]]; then
            echo "$wp_root/$WPDB_CONFIG_FILE_NAME"
        else
            echo "./$WPDB_CONFIG_FILE_NAME"  # Fallback to current directory
        fi
    fi
}

# Find WordPress root directory (standalone version)
find_wordpress_root() {
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
# Configuration Reading Functions
# ===============================================

# Read value from [general] section
read_general_config() {
    local key="$1"
    local config_path="$2"

    # Use provided path or auto-detect
    if [[ -z "$config_path" ]]; then
        config_path=$(get_wpdb_config_path)
    fi

    if [[ ! -f "$config_path" ]]; then
        return 1
    fi

    # Try config_manager function first
    if command -v parse_config_section >/dev/null 2>&1; then
        parse_config_section "$config_path" "general" "$key"
    else
        # Standalone implementation
        awk -v key="$key" '
            /^\[general\]/ { in_section=1; next }
            /^\[/ && in_section { in_section=0 }
            in_section && $0 ~ "^" key "=" {
                gsub(/^[[:space:]]+|[[:space:]]+$/, "")
                sub("^" key "=", "")
                print
                exit
            }
        ' "$config_path" 2>/dev/null
    fi
}

# Read all site mappings
read_site_mappings() {
    local config_path="$1"

    # Use provided path or auto-detect
    if [[ -z "$config_path" ]]; then
        config_path=$(get_wpdb_config_path)
    fi

    if [[ ! -f "$config_path" ]]; then
        return 1
    fi

    # Try config_manager function first
    if command -v get_site_mappings >/dev/null 2>&1; then
        get_site_mappings "$config_path"
    else
        # Standalone implementation
        awk '
            /^\[site_mappings\]/ { in_section=1; next }
            /^\[/ && in_section { in_section=0 }
            in_section && NF > 0 && !/^#/ && !/^;/ {
                gsub(/^[[:space:]]+|[[:space:]]+$/, "")
                if (NF > 0) print
            }
        ' "$config_path" 2>/dev/null
    fi
}

# Read specific site mapping by blog_id
read_site_mapping() {
    local blog_id="$1"
    local config_path="$2"

    # Use provided path or auto-detect
    if [[ -z "$config_path" ]]; then
        config_path=$(get_wpdb_config_path)
    fi

    # Try config_manager function first
    if command -v get_site_mapping >/dev/null 2>&1; then
        get_site_mapping "$blog_id" "$config_path"
    else
        # Standalone implementation
        local mappings
        mappings=$(read_site_mappings "$config_path")
        while IFS=':' read -r mapped_blog_id old_domain new_domain; do
            if [[ "$mapped_blog_id" == "$blog_id" ]]; then
                echo "$old_domain:$new_domain"
                return 0
            fi
        done <<< "$mappings"
        return 1
    fi
}

# Extract production domains for Stage File Proxy (blog_id:old_domain pairs)
read_stage_proxy_mappings() {
    local config_path="$1"

    # Use provided path or auto-detect
    if [[ -z "$config_path" ]]; then
        config_path=$(get_wpdb_config_path)
    fi

    if [[ ! -f "$config_path" ]]; then
        return 1
    fi

    # Extract blog_id:old_domain from site_mappings (format: blog_id:old_domain:new_domain)
    awk '
        /^\[site_mappings\]/ { in_section=1; next }
        /^\[/ && in_section { in_section=0 }
        in_section && NF > 0 && !/^#/ && !/^;/ {
            # Remove leading/trailing whitespace
            gsub(/^[[:space:]]+|[[:space:]]+$/, "")
            split($0, parts, ":")
            if (length(parts) >= 3 && parts[1] != "" && parts[2] != "") {
                print parts[1] ":" parts[2]
            }
        }
    ' "$config_path" 2>/dev/null
}

# Get production domain for specific blog_id (for Stage File Proxy)
read_production_domain() {
    local blog_id="$1"
    local config_path="$2"
    local fallback_domain="$3"

    # Use provided path or auto-detect
    if [[ -z "$config_path" ]]; then
        config_path=$(get_wpdb_config_path)
    fi

    local mappings
    mappings=$(read_stage_proxy_mappings "$config_path")
    while IFS=':' read -r mapped_blog_id mapped_domain; do
        if [[ "$mapped_blog_id" == "$blog_id" ]]; then
            echo "$mapped_domain"
            return 0
        fi
    done <<< "$mappings"

    # Return fallback domain if provided
    if [[ -n "$fallback_domain" ]]; then
        echo "$fallback_domain"
        return 0
    fi

    return 1
}

# ===============================================
# Configuration Writing Functions
# ===============================================

# Write/update value in [general] section
write_general_config() {
    local key="$1"
    local value="$2"
    local config_path="$3"

    # Use provided path or auto-detect
    if [[ -z "$config_path" ]]; then
        config_path=$(get_wpdb_config_path)
    fi

    # Try config_manager function first
    if command -v update_config_general >/dev/null 2>&1; then
        update_config_general "$config_path" "$key" "$value"
    else
        # Standalone implementation
        if [[ ! -f "$config_path" ]]; then
            # Create new config file
            cat > "$config_path" << EOF
[general]
$key=$value
EOF
            return 0
        fi

        # Update existing file
        local temp_file
        temp_file=$(mktemp)
        awk -v key="$key" -v value="$value" '
            /^\[general\]/ { in_section=1; print; next }
            /^\[/ && in_section {
                if (!found) print key "=" value
                in_section=0; found=0; print; next
            }
            in_section && $0 ~ "^" key "=" {
                print key "=" value; found=1; next
            }
            { print }
            END {
                if (in_section && !found) print key "=" value
            }
        ' "$config_path" > "$temp_file" && mv "$temp_file" "$config_path"
    fi
}

# Add/update site mapping
write_site_mapping() {
    local blog_id="$1"
    local old_domain="$2"
    local new_domain="$3"
    local config_path="$4"

    # Use provided path or auto-detect
    if [[ -z "$config_path" ]]; then
        config_path=$(get_wpdb_config_path)
    fi

    # Try config_manager function first
    if command -v update_site_mapping >/dev/null 2>&1; then
        update_site_mapping "$config_path" "$blog_id" "$old_domain" "$new_domain"
    else
        # Standalone implementation
        if [[ ! -f "$config_path" ]]; then
            # Create new config file
            cat > "$config_path" << EOF
[general]

[site_mappings]
$blog_id:$old_domain:$new_domain
EOF
            return 0
        fi

        # Update existing file
        local temp_file
        temp_file=$(mktemp)
        local mapping_found=false
        local in_site_section=false

        while IFS= read -r line; do
            if [[ "$line" =~ ^\[site_mappings\] ]]; then
                in_site_section=true
                echo "$line"
            elif [[ "$line" =~ ^\[ ]] && [[ "$in_site_section" == true ]]; then
                # End of site_mappings section
                if [[ "$mapping_found" == false ]]; then
                    echo "$blog_id:$old_domain:$new_domain"
                fi
                in_site_section=false
                echo "$line"
            elif [[ "$in_site_section" == true ]]; then
                # Check if this is the mapping we want to update
                if [[ "$line" =~ ^$blog_id: ]]; then
                    echo "$blog_id:$old_domain:$new_domain"
                    mapping_found=true
                else
                    echo "$line"
                fi
            else
                echo "$line"
            fi
        done < "$config_path" > "$temp_file"

        # If we're still in site_mappings section and didn't find the mapping, add it
        if [[ "$in_site_section" == true ]] && [[ "$mapping_found" == false ]]; then
            echo "$blog_id:$old_domain:$new_domain" >> "$temp_file"
        fi

        mv "$temp_file" "$config_path"
    fi
}

# Create a new config file with template
create_wpdb_config() {
    local config_path="$1"
    local sql_file="$2"
    local old_domain="$3"
    local new_domain="$4"

    # Use provided path or auto-detect
    if [[ -z "$config_path" ]]; then
        config_path=$(get_wpdb_config_path)
    fi

    # Try config_manager function first
    if command -v create_config_file >/dev/null 2>&1; then
        create_config_file "$sql_file" "$old_domain" "$new_domain"
    else
        # Standalone implementation
        cat > "$config_path" << EOF
# WordPress Database Import Configuration
# Auto-generated by wp-db-import tool

[general]
sql_file=${sql_file:-}
old_domain=${old_domain:-}
new_domain=${new_domain:-}
all_tables=true
dry_run=false
clear_revisions=true
setup_stage_proxy=true
auto_proceed=false

[site_mappings]
# Format: blog_id:old_domain:new_domain
# Example: 1:example.com:local.test
EOF
        echo "Configuration file created: $config_path"
    fi
}

# ===============================================
# Configuration Validation Functions
# ===============================================

# Validate config file structure and required fields
validate_wpdb_config() {
    local config_path="$1"

    # Use provided path or auto-detect
    if [[ -z "$config_path" ]]; then
        config_path=$(get_wpdb_config_path)
    fi

    if [[ ! -f "$config_path" ]]; then
        echo "Config file not found: $config_path"
        return 1
    fi

    # Try config_manager function first
    if command -v validate_config_file >/dev/null 2>&1; then
        validate_config_file "$config_path"
    else
        # Standalone validation
        local has_general=false
        local has_site_mappings=false

        while IFS= read -r line; do
            if [[ "$line" =~ ^\[general\] ]]; then
                has_general=true
            elif [[ "$line" =~ ^\[site_mappings\] ]]; then
                has_site_mappings=true
            fi
        done < "$config_path"

        if [[ "$has_general" == false ]]; then
            echo "Missing [general] section"
            return 1
        fi

        return 0
    fi
}

# Check if a config value is 'true'
is_config_enabled() {
    local value="$1"

    # Try config_manager function first
    if command -v is_config_true >/dev/null 2>&1; then
        is_config_true "$value"
    else
        # Standalone implementation
        case "${value,,}" in
            true|yes|1|on|enable|enabled) return 0 ;;
            *) return 1 ;;
        esac
    fi
}

# ===============================================
# Convenience Functions
# ===============================================

# Get all general config as associative array (if supported) or key=value pairs
get_all_general_config() {
    local config_path="$1"

    # Use provided path or auto-detect
    if [[ -z "$config_path" ]]; then
        config_path=$(get_wpdb_config_path)
    fi

    if [[ ! -f "$config_path" ]]; then
        return 1
    fi

    # Output key=value pairs
    awk '
        /^\[general\]/ { in_section=1; next }
        /^\[/ && in_section { in_section=0 }
        in_section && NF > 0 && !/^#/ && !/^;/ && /=/ {
            gsub(/^[[:space:]]+|[[:space:]]+$/, "")
            print
        }
    ' "$config_path" 2>/dev/null
}

# Check if config has any site mappings
has_site_mappings() {
    local config_path="$1"

    # Use provided path or auto-detect
    if [[ -z "$config_path" ]]; then
        config_path=$(get_wpdb_config_path)
    fi

    local mappings
    mappings=$(read_site_mappings "$config_path")
    [[ -n "$mappings" ]]
}

# Export functions for external use
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    {
        export -f wpdb_config_exists
        export -f get_wpdb_config_path
        export -f find_wordpress_root
        export -f read_general_config
        export -f read_site_mappings
        export -f read_site_mapping
        export -f read_stage_proxy_mappings
        export -f read_production_domain
        export -f write_general_config
        export -f write_site_mapping
        export -f create_wpdb_config
        export -f validate_wpdb_config
        export -f is_config_enabled
        export -f get_all_general_config
        export -f has_site_mappings
    } >/dev/null 2>&1
fi
