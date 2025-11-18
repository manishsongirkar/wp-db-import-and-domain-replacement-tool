#!/bin/bash

# ================================================================
# WordPress Installation Type Detection Module
# ================================================================
#
# This module provides comprehensive WordPress installation type detection
# functionality, supporting both single-site and multisite installations.
#
# Features:
#   - Multi-method detection approach for maximum reliability
#   - Automatic WordPress root discovery from any subdirectory
#   - Database analysis (wp_blogs, wp_site tables)
#   - wp-config.php constant parsing
#   - WP-CLI evaluation with fallback mechanisms
#   - Multisite type detection (subdomain vs subdirectory)
#   - Robust error handling and validation
#   - Silent and verbose operation modes
#
# Functions provided:
# - detect_wordpress_installation_type  Comprehensive WordPress type detection
# - detect_multisite_type              Determine subdomain vs subdirectory
# - validate_wordpress_detection       Validate detection results
#
# Dependencies:
# - execute_wp_cli function (from core/utils.sh)
# - Color variables (RED, GREEN, CYAN, YELLOW, RESET)
#
# ================================================================

# -----------------------------------------------
# Detect WordPress Installation Type
# -----------------------------------------------
# Comprehensive function to detect WordPress installation type using multiple methods
#
# Usage:
#   result=$(detect_wordpress_installation_type [wp_root_path] [verbose])
#
# Arguments:
#   starting_dir  (optional): Starting directory to search from (default: current directory)
#                             The function will automatically find WordPress root from this location
#   verbose       (optional): Enable verbose output ("true"/"false", default: "false")
#
# Returns:
#   String in format: "installation_type|multisite_type|network_flag|blog_count|site_count|detection_method"
#
#   installation_type: "single" or "multisite"
#   multisite_type:    "subdomain", "subdirectory", or "unknown" (only for multisite)
#   network_flag:      "--network" or "" (for WP-CLI commands)
#   blog_count:        Number of blogs (from get_blog_count() via WP-CLI)
#   site_count:        Always 1 for main site (multisite), 0 for single site
#   detection_method:  "wp-cli" (primary), "wp-config" (fallback), or "filesystem"
#
# Examples:
#   result=$(detect_wordpress_installation_type "/var/www/wordpress/wp-content" "true")
#   # Searches up from wp-content and returns: "multisite|subdomain|--network|3|1|wp-cli"
#
#   result=$(detect_wordpress_installation_type)
#   # Searches from current directory and returns: "single|NA|NA|0|0|wp-cli"
#
detect_wordpress_installation_type() {
    local starting_dir="${1:-$(pwd)}"
    # Verbose functionality removed
    local wp_root=""

    # Store original directory for restoration
    local original_dir=$(pwd)

    # If a specific path was provided, change to it first
    if [[ "$starting_dir" != "$(pwd)" ]]; then
        if [[ ! -d "$starting_dir" ]] || ! cd "$starting_dir" 2>/dev/null; then
            echo "error|invalid_path|||0|0|validation_failed"
            return 1
        fi
    fi
    # Only print detection start if not already printed by wrapper
    # (Assume wrapper prints its own detection start message)

    wp_root=$(find_wordpress_root)
    if [[ $? -ne 0 ]] || [[ -z "$wp_root" ]]; then
        cd "$original_dir"
        echo "error|no_wordpress|||0|0|validation_failed"
        return 1
    fi
    if ! cd "$wp_root" 2>/dev/null; then
        cd "$original_dir"
        echo "error|access_denied|||0|0|validation_failed"
        return 1
    fi

    # Initialize variables
    local installation_type="single"
    local multisite_type=""
    local network_flag=""
    local blog_count="0"
    local site_count="0"
    local detection_method="fallback"

    # ===== WP-CLI Evaluation (Primary Detection Method) =====

    # Use WordPress's own functions via WP-CLI eval
    local is_multisite_wp is_subdomain_install site_count_wp
    is_multisite_wp=$(execute_wp_cli eval 'echo is_multisite() ? "yes" : "no";' 2>/dev/null || echo "unknown")

    if [[ "$is_multisite_wp" == "yes" ]]; then
        installation_type="multisite"
        network_flag="--network"
        detection_method="wp-cli"

        # Determine multisite type using WordPress function
        is_subdomain_install=$(execute_wp_cli eval 'echo is_subdomain_install() ? "subdomain" : "subdirectory";' 2>/dev/null || echo "unknown")
        if [[ "$is_subdomain_install" == "subdomain" ]]; then
            multisite_type="subdomain"
        elif [[ "$is_subdomain_install" == "subdirectory" ]]; then
            multisite_type="subdirectory"
        fi

        # Get blog count using WordPress API
        blog_count_wp=$(execute_wp_cli eval 'echo get_blog_count();' 2>/dev/null || echo "N/A")
        if [[ "$blog_count_wp" =~ ^[0-9]+$ ]]; then
            blog_count="$blog_count_wp"
        else
            # Fallback: Try wp-config.php method
            local wp_config_count=""
            if grep -q "define.*MULTISITE.*true" wp-config.php 2>/dev/null; then
                # Try to get site count using WP-CLI site list.
                wp_config_count=$(execute_wp_cli site list --format=count 2>&1)
                if [[ "$wp_config_count" =~ ^[0-9]+$ ]]; then
                    blog_count="$wp_config_count"
                else
                    blog_count="1" # Default fallback
                fi
            else
                blog_count="1" # Default fallback
            fi
        fi
        # Site count is always at least 1 (main site)
        site_count="1"

    elif [[ "$is_multisite_wp" == "no" ]]; then
        installation_type="single"
        multisite_type="NA"
        network_flag="NA"
        blog_count="0"
        site_count="1"
        detection_method="wp-cli"
        # For single site, skip all multisite and filesystem fallback logic
        cd "$original_dir"
        echo "${installation_type}|${multisite_type}|${network_flag}|${blog_count}|${site_count}|${detection_method}"
        return 0
    fi

    # ===== METHOD 3: wp-config.php Constants Analysis (Fallback) =====
    if [[ "$installation_type" == "single" && "$is_multisite_wp" == "unknown" ]]; then
        if [[ $(check_wp_config_constant "MULTISITE" "true" "$wp_root/wp-config.php") == "true" ]]; then
            installation_type="multisite"
            network_flag="--network"
            detection_method="wp-config"

            # Try to get site count using WP-CLI site list.
            if [[ "$blog_count" == "0" || ! "$blog_count" =~ ^[0-9]+$ ]]; then
                local wp_site_list_count wp_cli_output
                wp_cli_output=$(execute_wp_cli site list --format=count 2>&1)
                wp_cli_exit_code=$?

                if [[ $wp_cli_exit_code -eq 0 ]] && [[ "$wp_cli_output" =~ ^[0-9]+$ ]]; then
                    blog_count="$wp_cli_output"
                else
                    blog_count="1" # Default fallback
                fi
                if [[ ! "$site_count" =~ ^[0-9]+$ ]]; then
                    site_count="1"
                fi
            fi
        fi
    fi

    # ===== METHOD 4: Filesystem Structure Analysis =====
    if [[ "$installation_type" == "single" ]]; then
        local fs_indicators
        fs_indicators=$(detect_multisite_filesystem_indicators "$wp_root")
        if [[ -n "$fs_indicators" ]]; then
            installation_type="multisite"
            network_flag="--network"
            detection_method="filesystem"
        fi
    fi

    # Multisite type detection (only if multisite)
    if [[ "$installation_type" == "multisite" ]]; then
        multisite_type=$(detect_multisite_type "$wp_root")
    fi

    # Return to original directory
    cd "$original_dir"

    # Ensure blog_count and site_count are always numeric before returning
    if [[ ! "$blog_count" =~ ^[0-9]+$ ]]; then
        blog_count="1"
    fi
    if [[ ! "$site_count" =~ ^[0-9]+$ ]]; then
        site_count="1"
    fi

    # Return formatted result
    echo "${installation_type}|${multisite_type}|${network_flag}|${blog_count}|${site_count}|${detection_method}"
    return 0
}

# -----------------------------------------------
# Detect Multisite Type (Subdomain vs Subdirectory)
# -----------------------------------------------
# Determines if a multisite installation uses subdomain or subdirectory configuration
#
# Usage:
#   type=$(detect_multisite_type [wp_root_path] [verbose])
#
# Arguments:
#   starting_dir  (optional): Starting directory to search from (default: current directory)
#                             The function will automatically find WordPress root from this location
#   verbose       (optional): Enable verbose output ("true"/"false", default: "false")
#
# Returns:
#   "subdomain", "subdirectory", or "unknown"
#
detect_multisite_type() {
    local starting_dir="${1:-$(pwd)}"
    # Verbose functionality removed
    local wp_root=""

    # Store original directory for restoration
    local original_dir=$(pwd)
    if [[ "$starting_dir" != "$(pwd)" ]]; then
        if [[ ! -d "$starting_dir" ]] || ! cd "$starting_dir" 2>/dev/null; then
            echo "unknown"
            return 1
        fi
    fi
    wp_root=$(find_wordpress_root)
    if [[ $? -ne 0 ]] || [[ -z "$wp_root" ]]; then
        cd "$original_dir"
        echo "unknown"
        return 1
    fi

    # Check wp-config.php for SUBDOMAIN_INSTALL constant using utility
    local subdomain_install=""
    if [[ $(check_wp_config_constant "SUBDOMAIN_INSTALL" "true" "$wp_root/wp-config.php") == "true" ]]; then
        subdomain_install="true"
    elif [[ $(check_wp_config_constant "SUBDOMAIN_INSTALL" "false" "$wp_root/wp-config.php") == "true" ]]; then
        subdomain_install="false"
    fi

    # Determine type based on SUBDOMAIN_INSTALL value
    if [[ "$subdomain_install" == "true" ]]; then
        cd "$original_dir"
        echo "subdomain"
    elif [[ "$subdomain_install" == "false" ]]; then
        cd "$original_dir"
        echo "subdirectory"
    else
        # Fallback: Try WP-CLI method
        if cd "$wp_root" 2>/dev/null; then
            local wp_subdomain_check=""
            wp_subdomain_check=$(execute_wp_cli eval 'echo is_subdomain_install() ? "true" : "false";' 2>/dev/null || echo "unknown")
            if [[ "$wp_subdomain_check" == "true" ]]; then
                cd "$original_dir"
                echo "subdomain"
            elif [[ "$wp_subdomain_check" == "false" ]]; then
                cd "$original_dir"
                echo "subdirectory"
            else
                cd "$original_dir"
                echo "unknown"
            fi
        else
            echo "unknown"
        fi
    fi
}

# -----------------------------------------------
# Validate WordPress Detection Results
# -----------------------------------------------
# Validates detection results and ensures consistency
#
# Usage:
#   validate_wordpress_detection "detection_result_string" [verbose]
#
# Arguments:
#   detection_result  Detection result string from detect_wordpress_installation_type
#   verbose          (optional): Enable verbose output ("true"/"false", default: "false")
#
# Returns:
#   0 if validation passes, 1 if validation fails
#
validate_wordpress_detection() {
    local detection_result="$1"
    local verbose="${2:-false}"

    if [[ -z "$detection_result" ]]; then
        if [[ "$verbose" == "true" ]]; then
            printf "${RED}❌ Empty detection result${RESET}\n" >&2
        fi
        return 1
    fi

    # Parse detection result
    IFS='|' read -r installation_type multisite_type network_flag blog_count site_count detection_method <<< "$detection_result"

    # Validate installation type
    if [[ "$installation_type" != "single" && "$installation_type" != "multisite" && "$installation_type" != "error" ]]; then
        if [[ "$verbose" == "true" ]]; then
            printf "${RED}❌ Invalid installation type: %s${RESET}\n" "$installation_type" >&2
        fi
        return 1
    fi

    # Validate multisite-specific fields
    if [[ "$installation_type" == "multisite" ]]; then
        # Check multisite type
        if [[ "$multisite_type" != "subdomain" && "$multisite_type" != "subdirectory" && "$multisite_type" != "unknown" ]]; then
            if [[ "$verbose" == "true" ]]; then
                printf "${RED}❌ Invalid multisite type: %s${RESET}\n" "$multisite_type" >&2
            fi
            return 1
        fi

        # Check network flag
        if [[ "$network_flag" != "--network" ]]; then
            if [[ "$verbose" == "true" ]]; then
                printf "${YELLOW}⚠️  Expected --network flag for multisite, got: %s${RESET}\n" "$network_flag" >&2
            fi
        fi
    fi

    # Validate numeric fields
    if [[ ! "$blog_count" =~ ^[0-9]+$ ]]; then
        if [[ "$verbose" == "true" ]]; then
            printf "${RED}❌ Invalid blog count: %s${RESET}\n" "$blog_count" >&2
        fi
        return 1
    fi

    if [[ ! "$site_count" =~ ^[0-9]+$ ]]; then
        if [[ "$verbose" == "true" ]]; then
            printf "${RED}❌ Invalid site count: %s${RESET}\n" "$site_count" >&2
        fi
        return 1
    fi

    # Validate detection method
    local valid_methods=("database" "wp-config" "wp-cli" "fallback" "validation_failed")
    local method_valid=false
    for method in "${valid_methods[@]}"; do
        if [[ "$detection_method" == "$method" ]]; then
            method_valid=true
            break
        fi
    done

    if [[ "$method_valid" == "false" ]]; then
        if [[ "$verbose" == "true" ]]; then
            printf "${RED}❌ Invalid detection method: %s${RESET}\n" "$detection_method" >&2
        fi
        return 1
    fi

    if [[ "$verbose" == "true" ]]; then
        printf "${GREEN}✅ Detection result validation passed${RESET}\n" >&2
    fi

    return 0
}
