#!/usr/bin/env bash

# ================================================================
# Stage File Proxy Utilities Module (Unified)
# ================================================================
#
# Description:
#   This module provides a unified and robust set of functions for
#   installing, activating, and configuring the Stage File Proxy
#   WordPress plugin (v101+). It supports both single-site and
#   multisite installations, automatically choosing between:
#   1. Automatic configuration (using existing production domain mappings from a config file).
#   2. Manual configuration (interactive prompting, saving new mappings to the config file).
#
# Key Features:
# - Unified setup function (`setup_stage_file_proxy_unified`) supporting automatic/manual modes.
# - Plugin installation and activation with enhanced failure handling.
# - Secure handling of domains, ensuring `https://` protocol is stored.
# - Integration with external site mapping tools for persistent configuration.
# - Utilities for checking current configuration and bulk setup for multisite.
#
# Functions provided:
# - get_stage_proxy_mappings                   Extracts mappings from [site_mappings].
# - save_stage_proxy_mapping                   Placeholder/Info function.
# - get_domain_mapping_for_site                Retrieves production domain for a blog ID.
# - sanitize_stage_proxy_domain                Validates and standardizes domain input.
# - get_validated_domain                       Interactive domain input validation.
# - configure_stage_file_proxy                 Sets `sfp_url` and `sfp_mode` via WP-CLI.
# - setup_stage_file_proxy                     Legacy interactive setup function.
# - setup_single_site_stage_file_proxy         Legacy single site handler.
# - setup_stage_file_proxy_unified             Main unified setup entry point.
# - setup_multisite_stage_file_proxy           Legacy multisite handler.
# - show_stage_file_proxy_config               Displays current plugin settings.
# - bulk_configure_multisite                   Sets one domain for all subsites.
# - setup_single_site_stage_file_proxy_automatic Single site setup using config mappings.
# - setup_multisite_stage_file_proxy_automatic Multisite setup using config mappings.
# - setup_multisite_from_config_mappings       Fallback multisite setup when WP-CLI fails.
# - setup_single_site_stage_file_proxy_manual  Single site interactive setup (saves mapping).
# - setup_multisite_stage_file_proxy_manual    Multisite interactive setup (saves mappings).
# - get_validated_domain_with_input            Non-interactive domain validation helper.
# - install_stage_file_proxy_plugin            Handles installation of the plugin.
#
# Dependencies:
# - WP-CLI (`wp` command)
# - External site mapping/detection utilities (e.g., `sanitize_domain`, `find_wordpress_root`, `detect_wordpress_installation_type`, `write_site_mapping`).
# - Color constants (e.g., ${CYAN}, ${RED}, ${GREEN}).
#
# ================================================================

# ===============================================
# Function to get stage proxy mappings from existing site_mappings
# ===============================================
#
# Description: Extracts production domain mappings from the `[site_mappings]` section
#              of a configuration file.
#
# Parameters:
#   - $1: Path to the configuration file (e.g., `config/site-mappings.conf`).
#
# Returns:
#   - Output (echoed) in the format `blog_id:old_domain` (production domain) for each mapping.
#   - Returns 1 (Failure) if the config file does not exist.
#   - Returns 0 (Success) otherwise (even if no mappings are found).
#
# Behavior:
#   - Uses `awk` to parse the specified section and format the output.
#   - Assumes mapping format is `blog_id:old_domain:new_domain`.
#
get_stage_proxy_mappings() {
    local config_path="$1"

    if [[ ! -f "$config_path" ]]; then
        return 1
    fi

    # Extract blog_id:old_domain from site_mappings (format: blog_id:old_domain:new_domain)
    # Handle potential trailing spaces in section headers
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

# ===============================================
# Function to save stage proxy mapping
# ===============================================
#
# Description: Placeholder function to indicate that site mappings are saved
#              via the existing site mapping infrastructure (e.g., by calling
#              `write_site_mapping` or similar external functions).
#
# Parameters:
#   - None (The actual saving is handled by other functions like `setup_multisite_stage_file_proxy_manual`).
#
# Returns:
#   - 0 (Success) always.
#
# Behavior:
#   - Prints a message to inform the user where mappings are stored.
#
save_stage_proxy_mapping() {
    echo "Mappings are automatically saved in [site_mappings] section"
    return 0
}

# ===============================================
# Function to get domain mapping for a specific site
# ===============================================
#
# Description: Retrieves the production domain (old_domain) associated with a
#              specific blog ID from the configuration file site mappings.
#
# Parameters:
#   - $1: Path to the configuration file.
#   - $2: The blog ID (e.g., '1' for the main site).
#   - $3: (Optional) A fallback domain to return if no mapping is found.
#
# Returns:
#   - The mapped production domain (echoed) on success.
#   - The optional fallback domain (echoed) if no mapping is found but a fallback is provided.
#   - Returns 0 (Success) if a domain is echoed.
#   - Returns 1 (Failure) if no mapping is found and no fallback is provided.
#
# Behavior:
#   - Prioritizes using the external function `read_production_domain` if available.
#   - Falls back to using `get_stage_proxy_mappings` to manually search.
#
get_domain_mapping_for_site() {
    local config_path="$1"
    local blog_id="$2"
    local fallback_domain="$3"  # Optional fallback domain

    # Use unified config reader if available
    if command -v read_production_domain >/dev/null 2>&1; then
        read_production_domain "$blog_id" "$config_path" "$fallback_domain"
    else
        # Fallback implementation
        local mappings
        mappings=$(get_stage_proxy_mappings "$config_path")
        while IFS=':' read -r mapped_blog_id mapped_domain; do
            if [[ "$mapped_blog_id" == "$blog_id" ]]; then
                echo "$mapped_domain"
                return 0
            fi
        done <<< "$mappings"

        # If no mapping found, return fallback domain if provided
        if [[ -n "$fallback_domain" ]]; then
            echo "$fallback_domain"
            return 0
        fi

        return 1
    fi
}

# ===============================================
# Function to sanitize and validate domain input
# ===============================================
#
# Description: Standardizes and validates a domain input string for use as the
#              Stage File Proxy source URL (`sfp_url`).
#
# Parameters:
#   - $1: The input domain string (may contain protocol, slashes, or nothing).
#
# Returns:
#   - The sanitized, valid domain string (echoed) on success (guaranteed to start with `https://`).
#   - Returns 1 (Failure) if the domain is invalid or empty after processing.
#
# Behavior:
#   - Relies on the external function `sanitize_domain` with "strict" mode for core validation.
#   - Handles protocol conversion to ensure `https://` is used for security.
#
sanitize_stage_proxy_domain() {
    local input="$1"

    # Use the centralized sanitize_domain function with strict mode
    local clean_domain
    clean_domain=$(sanitize_domain "$input" "strict")
    local exit_code=$?

    if [[ $exit_code -eq 0 && -n "$clean_domain" ]]; then
        echo "$clean_domain"
        return 0
    else
        return 1
    fi
}

# ===============================================
# Function to get and validate domain input interactively
# ===============================================
#
# Description: Prompts the user for a domain, performs basic validation,
#              and uses `sanitize_stage_proxy_domain` for final processing.
#
# Parameters:
#   - $1: The prompt string to display to the user.
#
# Returns:
#   - 0 (Success) if a valid domain is entered and the global variable `VALIDATED_DOMAIN` is set.
#   - 1 (Failure) if input is empty (user chose to skip), invalid, or the user cancels a warning.
#
# Behavior:
#   - Reads input from `/dev/tty`.
#   - Performs checks for length, dangerous characters, and control characters.
#   - Automatically converts `http://` to `https://` and adds `https://` if missing.
#   - Warns the user if localhost patterns are detected.
#   - Sets the global variable `VALIDATED_DOMAIN` to the final, sanitized domain.
#
get_validated_domain() {
    local prompt="$1"
    local domain
    local clean_domain
    local original_input

    while true; do
        printf "%s" "$prompt"
        read -r domain < /dev/tty

        # Store original input for user feedback
        original_input="$domain"

        # Remove leading/trailing whitespace first using bash built-ins
        # Remove leading whitespace
        while [[ "$domain" =~ ^[[:space:]] ]]; do
          domain="${domain#[[:space:]]}"
        done
        # Remove trailing whitespace
        while [[ "$domain" =~ [[:space:]]$ ]]; do
          domain="${domain%[[:space:]]}"
        done

        # Check if input is empty (allow skipping)
        if [[ -z "$domain" ]]; then
            printf "${YELLOW}⚠️  Skipping configuration for this site (empty input)${RESET}\n"
            VALIDATED_DOMAIN=""
            return 1  # Return 1 to indicate skip
        fi

        # Check input length
        if [[ ${#domain} -gt 2048 ]]; then
            printf "${RED}❌ Error: Domain too long (max 2048 characters)${RESET}\n"
            continue
        fi

        # Check for dangerous characters
        if [[ "$domain" =~ [\;\|\&\$\`\(\)\<\>\"\'] ]]; then
            printf "${RED}❌ Error: Domain contains invalid characters (; | & \$ \` ( ) < > \" ')${RESET}\n"
            continue
        fi

        # Check for control characters
        if [[ "$domain" =~ [[:cntrl:]] ]]; then
            printf "${RED}❌ Error: Domain contains control characters${RESET}\n"
            continue
        fi

        # UPDATED: Show user what will be stored in database for new plugin structure
        local display_domain="$domain"

        # Auto-add https:// protocol if missing (required for database storage)
        if [[ ! "$domain" =~ ^https?:// ]]; then
            domain="https://$domain"
        elif [[ "$domain" =~ ^http:// ]]; then
            # Convert http to https for security
            domain="${domain#http://}"
            domain="https://$domain"
        fi

        # Use sanitize function for final validation
        clean_domain=$(sanitize_stage_proxy_domain "$domain")
        if [[ $? -eq 0 ]]; then
            # Check for localhost patterns
            if [[ "$clean_domain" =~ (localhost|127\.0\.0\.1|0\.0\.0\.0) ]]; then
                printf "${YELLOW}⚠️  Warning: Localhost pattern detected. Continue? (y/n): ${RESET}"
                read -r continue_localhost < /dev/tty
                if [[ ! "$continue_localhost" =~ ^[Yy] ]]; then
                    continue
                fi
            fi

            # Set global variable instead of echo
            VALIDATED_DOMAIN="$clean_domain"
            return 0
        else
            printf "${RED}❌ Error: Invalid domain format. Please try again.${RESET}\n"
            continue
        fi
    done
}

# ===============================================
# Function to configure Stage File Proxy plugin settings
# ===============================================
#
# Description: Configures the Stage File Proxy WP-CLI options (`sfp_url` and `sfp_mode`)
#              for a single site or a specific site in a multisite network.
#
# Parameters:
#   - $1: The sanitized production domain (sfp_url). Must include protocol (https://).
#   - $2: The Stage File Proxy mode (sfp_mode). Defaults to 'header'.
#   - $3: (Optional) The site URL for multisite context (used with `--url=$3`).
#
# Returns:
#   - 0 (Success) if both options are updated successfully via WP-CLI.
#   - 1 (Failure) otherwise.
#
# Behavior:
#   - Uses `wp option update` to set `sfp_url` and `sfp_mode`.
#
configure_stage_file_proxy() {
    local domain="$1"
    local mode="${2:-header}"  # Default mode is 'header' as per new plugin
    local site_url="$3"  # Optional site URL for multisite
    local url_flag=""

    if [[ -n "$site_url" ]]; then
        url_flag="--url=$site_url"
    fi

    # Configure sfp_url (replaces old source_domain)
    if ! wp option update sfp_url "$domain" $url_flag --quiet 2>/dev/null; then
        printf "${RED}❌ Failed to set sfp_url${RESET}\n"
        return 1
    fi

    # Configure sfp_mode (replaces old method)
    if ! wp option update sfp_mode "$mode" $url_flag --quiet 2>/dev/null; then
        printf "${RED}❌ Failed to set sfp_mode${RESET}\n"
        return 1
    fi

    printf " ${GREEN}✅ Configuration successful${RESET}\n"
}

# ===============================================
# Main setup function for Stage File Proxy
# ===============================================
#
# Description: Legacy, interactive setup function for Stage File Proxy. It installs
#              and activates the plugin, and then prompts the user for the production
#              domain(s) based on whether it detects a single site or multisite.
#
# Parameters:
#   - None.
#
# Returns:
#   - 0 (Success) if setup completes for the detected installation type.
#   - 1 (Failure) if WP-CLI is unavailable, WordPress is not installed, or plugin installation/activation fails.
#
# Behavior:
#   - Installs the plugin if missing (via GitHub release or direct download).
#   - Calls `add_stage_file_proxy_to_gitignore` if available.
#   - Detects installation type using external functions.
#   - Delegates to `setup_single_site_stage_file_proxy` or `setup_multisite_stage_file_proxy`.
#
setup_stage_file_proxy() {
    printf "${CYAN}${BOLD}=== Stage File Proxy Setup ===${RESET}\n"
    echo ""

    # Check if WP CLI is available
    if ! command -v wp &> /dev/null; then
        printf "${RED}❌ Error: WP CLI is not installed or not in PATH${RESET}\n"
        printf "${YELLOW}💡 Please install WP CLI first: https://wp-cli.org/${RESET}\n"
        return 1
    fi

    # Check if we're in a WordPress directory
    if ! wp core is-installed --quiet 2>/dev/null; then
        printf "${RED}❌ Error: Not in a WordPress directory or WordPress is not installed${RESET}\n"
        return 1
    fi

    # Check if the plugin exists, if not install it with enhanced error handling
    if ! wp plugin is-installed stage-file-proxy --quiet 2>/dev/null; then
        printf "${CYAN}📦 Stage File Proxy plugin not found. Installing...${RESET}\n"

        # Create a temporary log for installation debugging
        local install_log="/tmp/wp_plugin_install_setup_$$.log"
        local install_success=false

        # Method 1: Try installing from GitHub release
        printf "${YELLOW}    Attempting installation from GitHub release...${RESET}\n"
        if wp plugin install https://github.com/manishsongirkar/stage-file-proxy/releases/download/101/stage-file-proxy.zip --quiet > "$install_log" 2>&1; then
            printf "${GREEN}✅ Plugin installed successfully from GitHub${RESET}\n"
            install_success=true
        else
            printf "${YELLOW}⚠️  GitHub installation failed, trying direct download method...${RESET}\n"

            # Method 2: Try direct download and install
            printf "${YELLOW}    Attempting direct download method...${RESET}\n"
            local temp_plugin_file="/tmp/stage-file-proxy-setup-$$.zip"

            # Try downloading with curl first, then wget as fallback
            if command -v curl &>/dev/null; then
                if curl -L -o "$temp_plugin_file" "https://github.com/manishsongirkar/stage-file-proxy/releases/download/101/stage-file-proxy.zip" >> "$install_log" 2>&1; then
                    if wp plugin install "$temp_plugin_file" --quiet >> "$install_log" 2>&1; then
                        printf "${GREEN}✅ Plugin installed successfully via direct download${RESET}\n"
                        install_success=true
                    fi
                    rm -f "$temp_plugin_file" 2>/dev/null
                fi
            elif command -v wget &>/dev/null; then
                if wget -O "$temp_plugin_file" "https://github.com/manishsongirkar/stage-file-proxy/releases/download/101/stage-file-proxy.zip" >> "$install_log" 2>&1; then
                    if wp plugin install "$temp_plugin_file" --quiet >> "$install_log" 2>&1; then
                        printf "${GREEN}✅ Plugin installed successfully via direct download${RESET}\n"
                        install_success=true
                    fi
                    rm -f "$temp_plugin_file" 2>/dev/null
                fi
            fi
        fi

        # Handle installation result
        if [[ "$install_success" == true ]]; then
            # Verify installation was actually successful
            if wp plugin is-installed stage-file-proxy --quiet 2>/dev/null; then
                printf "${GREEN}✅ Plugin installation verified${RESET}\n"
            else
                printf "${RED}❌ Plugin installation verification failed${RESET}\n"
                install_success=false
            fi
        fi

        if [[ "$install_success" == false ]]; then
            printf "${RED}❌ Failed to install plugin using all methods${RESET}\n"
            printf "${YELLOW}💡 Installation error details:${RESET}\n"
            if [[ -f "$install_log" ]]; then
                # Use built-in bash features instead of external commands
                printf "${YELLOW}   Last few lines from installation log:${RESET}\n"
                local line_count=0
                local lines=()
                while IFS= read -r line; do
                    lines+=("$line")
                    ((line_count++))
                done < "$install_log"

                # Display last 5 lines or all lines if less than 5
                local start_index=$((line_count > 5 ? line_count - 5 : 0))
                for ((i=start_index; i<line_count; i++)); do
                    echo "   ${lines[i]}"
                done
            fi
            printf "${CYAN}🔧 Manual installation options:${RESET}\n"
            printf "${YELLOW}   1. Download manually: https://github.com/manishsongirkar/stage-file-proxy/releases/download/101/stage-file-proxy.zip${RESET}\n"
            printf "${YELLOW}   2. Install via WP Admin: Plugins → Add New → Upload Plugin${RESET}\n"
            printf "${YELLOW}   3. Check internet connection and try again${RESET}\n"
            printf "${RED}Please install the plugin manually and run this script again${RESET}\n"
            return 1
        fi

        # Clean up installation log
        rm -f "$install_log" 2>/dev/null
    else
        printf "${GREEN}✅ Stage File Proxy plugin already installed${RESET}\n"
    fi

    # Automatically add plugin to .gitignore to prevent accidental commits
    printf "\n${CYAN}🔒 Securing plugin from accidental repository commits...${RESET}\n"
    if command -v add_stage_file_proxy_to_gitignore >/dev/null 2>&1; then
        if add_stage_file_proxy_to_gitignore; then
            printf "${GREEN}✅ Plugin successfully added to .gitignore${RESET}\n"
        else
            printf "${YELLOW}⚠️  Could not automatically add to .gitignore${RESET}\n"
            printf "${YELLOW}💡 Consider adding '/plugins/stage-file-proxy/' to wp-content/.gitignore manually${RESET}\n"
        fi
    else
        printf "${YELLOW}⚠️  GitIgnore manager not available${RESET}\n"
        printf "${YELLOW}💡 Ensure gitignore_manager.sh is loaded or add manually to wp-content/.gitignore${RESET}\n"
    fi

    # Detect WordPress installation type using centralized function
    local wp_root
    wp_root=$(find_wordpress_root)
    local wp_detect_output
    wp_detect_output=$(detect_wordpress_installation_type "$wp_root" "false")
    IFS='|' read -r installation_type multisite_type network_flag blog_count site_count detection_method <<< "$wp_detect_output"

    printf "${CYAN}WordPress Installation Type:${RESET}\n"
    if [[ "$installation_type" == "multisite" ]]; then
        if [[ "$multisite_type" == "subdomain" ]]; then
            printf "${GREEN}✓ Multisite detected (subdomain configuration)${RESET}\n"
        elif [[ "$multisite_type" == "subdirectory" ]]; then
            printf "${GREEN}✓ Multisite detected (subdirectory configuration)${RESET}\n"
        else
            printf "${GREEN}✓ Multisite detected${RESET}\n"
        fi
        setup_multisite_stage_file_proxy
    elif [[ "$installation_type" == "single" ]]; then
        printf "${GREEN}✓ Single site detected${RESET}\n"
        setup_single_site_stage_file_proxy
    else
        printf "${RED}❌ Could not detect WordPress installation type${RESET}\n"
        return 1
    fi
}

# ===============================================
# Single site setup function
# ===============================================
#
# Description: Handles the interactive setup for a WordPress single site installation.
#
# Parameters:
#   - None.
#
# Returns:
#   - 0 (Success) if the plugin is activated and configured.
#   - 1 (Failure) if plugin activation fails or configuration is unsuccessful.
#
# Behavior:
#   - Activates the Stage File Proxy plugin.
#   - Prompts the user for the production domain via `get_validated_domain`.
#   - Configures the site using `configure_stage_file_proxy` with 'header' mode.
#
setup_single_site_stage_file_proxy() {
    echo ""
    printf "${CYAN}${BOLD}=== Setting up for Single Site ===${RESET}\n"

    # Check if plugin is already active, activate if needed
    if wp plugin is-active stage-file-proxy --quiet 2>/dev/null; then
        printf "${GREEN}✓ Plugin already active${RESET}\n"
    else
        printf "${CYAN}📦 Activating Stage File Proxy plugin...${RESET}\n"
        if wp plugin activate stage-file-proxy --quiet 2>/dev/null; then
            printf "${GREEN}✓ Plugin activated successfully${RESET}\n"
        else
            printf "${RED}✗ Failed to activate plugin${RESET}\n"
            return 1
        fi
    fi

    # Get source domain from user with sanitization
    echo ""
    if get_validated_domain "Enter the production domain (e.g., example.com or https://example.com): "; then
        local source_domain="$VALIDATED_DOMAIN"

        # Configure the plugin with new structure
        printf "\n"
        printf "${BLUE}Configuring Stage File Proxy...${RESET}\n"
        if configure_stage_file_proxy "$source_domain" "header"; then
            printf "${GREEN}✅ Plugin configured successfully${RESET}\n"
        else
            printf "${RED}❌ Failed to configure plugin${RESET}\n"
            return 1
        fi
    else
        printf "${YELLOW}⚠️  Skipping Stage File Proxy configuration for this site${RESET}\n"
    fi

    printf "\n"
    printf "${GREEN}=== Setup Complete ===${RESET}\n"
    printf "${GREEN}Stage File Proxy is now active and configured!${RESET}\n"
}

# ===============================================
# Unified Stage File Proxy Setup Function
# ===============================================
#
# Description: The main, robust setup function that automatically selects between
#              automatic (using config mappings) and manual (interactive) modes
#              based on the availability of configuration data and the WordPress
#              installation type (single/multisite).
#
# Parameters:
#   - $1: Path to the configuration file containing site mappings.
#
# Returns:
#   - 0 (Success) if setup completes (either successfully configured or skipped).
#   - 1 (Failure) if WP-CLI is unavailable, plugin installation fails, or installation type cannot be detected.
#
# Behavior:
#   - Handles cases where WordPress is inaccessible (attempting config-based setup).
#   - Calls `install_stage_file_proxy_plugin`.
#   - Detects installation type and checks for existing site mappings.
#   - Delegates to: `setup_multisite_stage_file_proxy_automatic`,
#     `setup_multisite_stage_file_proxy_manual`,
#     `setup_single_site_stage_file_proxy_automatic`, or
#     `setup_single_site_stage_file_proxy_manual`.
#
setup_stage_file_proxy_unified() {
    local config_path="$1"

    printf "${CYAN}${BOLD}=== Unified Stage File Proxy Setup ===${RESET}\n"
    echo ""

    # Check if WP CLI is available
    if ! command -v wp &> /dev/null; then
        printf "${RED}❌ Error: WP CLI is not installed or not in PATH${RESET}\n"
        printf "${YELLOW}💡 Please install WP CLI first: https://wp-cli.org/${RESET}\n"
        return 1
    fi

    # Check if we're in a WordPress directory
    if ! wp core is-installed --quiet 2>/dev/null; then
        printf "${YELLOW}⚠️  WordPress not accessible or database connection issue${RESET}\n"
        printf "${BLUE}💡 Will attempt configuration using config file mappings...${RESET}\n"

        # Try to configure directly from mappings if available
        if [[ -n "$config_path" && -f "$config_path" ]]; then
            local mappings
            mappings=$(get_stage_proxy_mappings "$config_path")
            if [[ -n "$mappings" ]]; then
                # Detect multisite from config if possible
                local is_multisite_from_config=false
                local mapping_count
                mapping_count=$(echo "$mappings" | wc -l | tr -d ' ')
                if [[ $mapping_count -gt 1 ]]; then
                    is_multisite_from_config=true
                fi

                if [[ "$is_multisite_from_config" == "true" ]]; then
                    setup_multisite_from_config_mappings "$config_path" "$mappings"
                    return $?
                else
                    # For single site, extract the first mapping
                    local production_domain
                    production_domain=$(echo "$mappings" | head -n1 | cut -d: -f2)
                    if [[ -n "$production_domain" ]]; then
                        printf "${GREEN}✓ Found production domain in config: $production_domain${RESET}\n"
                        printf "${YELLOW}💡 Manual plugin activation and configuration needed when WordPress is accessible${RESET}\n"
                        printf "${CYAN}Commands to run when WordPress is available:${RESET}\n"
                        printf "  wp plugin activate stage-file-proxy\n"
                        printf "  wp option update sfp_url '$production_domain'\n"
                        printf "  wp option update sfp_mode 'header'\n"
                        return 0
                    fi
                fi
            fi
        fi

        printf "${RED}❌ Error: WordPress not accessible and no config mappings found${RESET}\n"
        printf "${YELLOW}💡 Please ensure WordPress is running or run 'wp-db-import config-create' first${RESET}\n"
        return 1
    fi

    # Install plugin if needed
    if ! install_stage_file_proxy_plugin; then
        printf "${RED}❌ Failed to install Stage File Proxy plugin${RESET}\n"
        return 1
    fi

    # Detect WordPress installation type using centralized function
    local wp_root
    wp_root=$(find_wordpress_root)
    local wp_detect_output
    wp_detect_output=$(detect_wordpress_installation_type "$wp_root" "false")
    IFS='|' read -r installation_type multisite_type network_flag blog_count site_count detection_method <<< "$wp_detect_output"

    # Check if we have config file and domain mappings available
    local has_mappings=false
    if [[ -n "$config_path" && -f "$config_path" ]]; then
        if command -v has_site_mappings >/dev/null 2>&1; then
            has_site_mappings "$config_path" && has_mappings=true
        else
            local mappings
            mappings=$(get_stage_proxy_mappings "$config_path")
            if [[ -n "$mappings" ]]; then
                has_mappings=true
            fi
        fi
    fi

    if [[ "$installation_type" == "multisite" ]]; then
        if [[ "$has_mappings" == "true" ]]; then
            printf "${GREEN}✓ Domain mappings found - using automatic mode${RESET}\n"
            setup_multisite_stage_file_proxy_automatic "$config_path"
        else
            printf "${YELLOW}⚠ No domain mappings found - using manual mode${RESET}\n"
            setup_multisite_stage_file_proxy_manual "$config_path"
        fi
    elif [[ "$installation_type" == "single" ]]; then
        if [[ "$has_mappings" == "true" ]]; then
            printf "${GREEN}✓ Domain mappings found - using automatic mode${RESET}\n"
            setup_single_site_stage_file_proxy_automatic "$config_path"
        else
            printf "${YELLOW}⚠ No domain mappings found - using manual mode${RESET}\n"
            setup_single_site_stage_file_proxy_manual "$config_path"
        fi
    else
        printf "${RED}❌ Could not detect WordPress installation type${RESET}\n"
        return 1
    fi
}

# ===============================================
# Multisite setup function
# ===============================================
#
# Description: Handles the interactive setup for a WordPress multisite installation.
#              It prompts the user for the production domain for each site in the network.
#
# Parameters:
#   - None.
#
# Returns:
#   - 0 (Success) if the plugin is activated network-wide and all sites are processed.
#   - 1 (Failure) if plugin activation fails or no sites are found in the network.
#
# Behavior:
#   - Activates the Stage File Proxy plugin network-wide.
#   - Uses `wp site list` to get all site IDs and URLs.
#   - Iterates through each site, prompting for the production domain via `get_validated_domain`.
#   - Configures each site using `configure_stage_file_proxy` with the site's URL flag.
#
setup_multisite_stage_file_proxy() {
    printf "\n"
    printf "${CYAN}=== Setting up for Multisite ===${RESET}\n"

    # Activate the plugin network-wide
    printf "${BLUE}Activating Stage File Proxy plugin network-wide...${RESET}\n"
    if wp plugin activate stage-file-proxy --network --quiet; then
        printf "${GREEN}✓ Plugin activated network-wide successfully${RESET}\n"
    else
        printf "${RED}✗ Failed to activate plugin network-wide${RESET}\n"
        return 1
    fi

    # Get list of all sites
    printf "\n"
    printf "${BLUE}Getting list of all sites in the network...${RESET}\n"
    local sites_data
    sites_data=$(wp site list --format=csv --fields=blog_id,url --quiet)

    if [[ -z "$sites_data" ]]; then
        printf "${RED}✗ No sites found in the network${RESET}\n"
        return 1
    fi

    printf "${YELLOW}Sites found:${RESET}\n"
    # Display sites in a readable format (skip CSV header)
    local site_count=0
    echo "$sites_data" | tail -n +2 | while IFS=',' read -r blog_id site_url; do
        site_count=$((site_count + 1))
        printf "  %d. Site %s: %s\n" "$site_count" "$blog_id" "$site_url"
    done

    printf "\n"
    printf "${BLUE}Now configuring each site...${RESET}\n"
    printf "\n"

    # Configure each site using CSV data
    local site_count=0
    local sites_without_header
    sites_without_header=$(echo "$sites_data" | tail -n +2)

    while IFS=',' read -r blog_id site_url; do
        [[ -z "$blog_id" || -z "$site_url" ]] && continue
        site_count=$((site_count + 1))
        printf "${CYAN}--- Configuring Site $site_count (ID: $blog_id): $site_url ---${RESET}\n"

        if get_validated_domain "Enter production domain for $site_url (press Enter to skip): "; then
            local source_domain="$VALIDATED_DOMAIN"

            if configure_stage_file_proxy "$source_domain" "header" "$site_url"; then
                printf "${GREEN}✅ $site_url configured${RESET}\n"
            else
                printf "${RED}❌ Failed to configure site: $site_url${RESET}\n"
            fi
        else
            printf "${YELLOW}⚠️  Skipping $site_url${RESET}\n"
        fi
    done <<< "$sites_without_header"

    printf "${GREEN}=== Multisite Setup Complete ===${RESET}\n"
    printf "${GREEN}Stage File Proxy is now active and configured for all sites!${RESET}\n"
}

# ===============================================
# Function to display current configuration
# ===============================================
#
# Description: Outputs the current `sfp_url` and `sfp_mode` settings for the
#              WordPress installation. For multisite, it shows the configuration
#              for every site in the network.
#
# Parameters:
#   - None.
#
# Returns:
#   - 0 (Success) always.
#
# Behavior:
#   - Detects installation type.
#   - Uses `wp option get` to retrieve the current settings.
#
show_stage_file_proxy_config() {
    printf "${CYAN}=== Current Stage File Proxy Configuration ===${RESET}\n"

    # Detect WordPress installation type using centralized function
    local wp_root
    wp_root=$(find_wordpress_root)
    local wp_detect_output
    wp_detect_output=$(detect_wordpress_installation_type "$wp_root" "false")
    IFS='|' read -r installation_type multisite_type network_flag blog_count site_count detection_method <<< "$wp_detect_output"

    if [[ "$installation_type" == "multisite" ]]; then
        printf "${YELLOW}Multisite Configuration:${RESET}\n"
        local sites_data
        sites_data=$(wp site list --format=csv --fields=blog_id,url --quiet)

        if [[ -n "$sites_data" ]]; then
            local sites_without_header
            sites_without_header=$(echo "$sites_data" | tail -n +2)

            while IFS=',' read -r blog_id site_url; do
                [[ -z "$blog_id" || -z "$site_url" ]] && continue
                printf "\n"
                printf "${BLUE}Site $blog_id: $site_url${RESET}\n"

                # Get sfp_url and sfp_mode separately (new plugin structure)
                local sfp_url sfp_mode
                sfp_url=$(wp --url="$site_url" option get sfp_url --quiet 2>/dev/null || echo "Not set")
                sfp_mode=$(wp --url="$site_url" option get sfp_mode --quiet 2>/dev/null || echo "Not set")

                printf "  ${GREEN}sfp_url:${RESET} $sfp_url\n"
                printf "  ${GREEN}sfp_mode:${RESET} $sfp_mode\n"
            done <<< "$sites_without_header"
        else
            printf "${YELLOW}⚠️  Could not retrieve sites list${RESET}\n"
        fi
    elif [[ "$installation_type" == "single" ]]; then
        printf "${YELLOW}Single Site Configuration:${RESET}\n"

        # Get sfp_url and sfp_mode separately (new plugin structure)
        local sfp_url sfp_mode
        sfp_url=$(wp option get sfp_url --quiet 2>/dev/null || echo "Not set")
        sfp_mode=$(wp option get sfp_mode --quiet 2>/dev/null || echo "Not set")

        printf "${GREEN}sfp_url:${RESET} $sfp_url\n"
        printf "${GREEN}sfp_mode:${RESET} $sfp_mode\n"
    else
        printf "${RED}❌ Could not detect WordPress installation type${RESET}\n"
    fi
}

# ===============================================
# Function to quickly set all sites to the same domain (for multisite)
# ===============================================
#
# Description: Prompts the user for a single production domain and applies it
#              as the `sfp_url` for *all* sites in a WordPress multisite network.
#
# Parameters:
#   - None.
#
# Returns:
#   - 0 (Success) if the configuration is applied successfully or cancelled.
#   - 1 (Failure) if the installation is not multisite.
#
# Behavior:
#   - Checks for multisite installation type.
#   - Uses `get_validated_domain` to get a single source domain.
#   - Iterates through all sites and calls `configure_stage_file_proxy`.
#
bulk_configure_multisite() {
    # Detect WordPress installation type using centralized function
    local wp_root
    wp_root=$(find_wordpress_root)
    local wp_detect_output
    wp_detect_output=$(detect_wordpress_installation_type "$wp_root" "false")
    IFS='|' read -r installation_type multisite_type network_flag blog_count site_count detection_method <<< "$wp_detect_output"

    if [[ "$installation_type" != "multisite" ]]; then
        printf "${RED}This function is only for multisite installations${RESET}\n"
        return 1
    fi

    printf "${CYAN}=== Bulk Configure All Sites ===${RESET}\n"
    if get_validated_domain "Enter the production domain to use for ALL sites (e.g., example.com): "; then
        local source_domain="$VALIDATED_DOMAIN"

        printf "\n"
        printf "${BLUE}Applying configuration to all sites...${RESET}\n"
        printf "\n"

        local sites_data
        sites_data=$(wp site list --format=csv --fields=blog_id,url --quiet)

        if [[ -n "$sites_data" ]]; then
            local sites_without_header
            sites_without_header=$(echo "$sites_data" | tail -n +2)

            while IFS=',' read -r blog_id site_url; do
                [[ -z "$blog_id" || -z "$site_url" ]] && continue
                printf "${CYAN}Configuring Site $blog_id: $site_url${RESET}\n"
                if configure_stage_file_proxy "$source_domain" "header" "$site_url"; then
                    printf "${GREEN}✅ $site_url configured${RESET}\n"
                else
                    printf "${RED}❌ Failed to configure $site_url${RESET}\n"
                fi
            done <<< "$sites_without_header"
        else
            printf "${YELLOW}⚠️  Could not retrieve sites list${RESET}\n"
        fi

        printf "\n"
        printf "${GREEN}✅ Bulk configuration complete!${RESET}\n"
    else
        printf "${YELLOW}⚠️  Configuration cancelled.${RESET}\n"
    fi
}

# ===============================================
# Single site automatic setup using site_mappings
# ===============================================
#
# Description: Configures Stage File Proxy for a single site using an existing
#              production domain mapping from the configuration file.
#
# Parameters:
#   - $1: Path to the configuration file containing site mappings.
#
# Returns:
#   - 0 (Success) if the site is configured automatically.
#   - 1 (Failure) if no mapping is found, the domain is invalid, or configuration fails.
#
# Behavior:
#   - Retrieves the production domain for blog ID 1 using `get_domain_mapping_for_site`.
#   - Activates the plugin.
#   - Sanitizes the domain with `sanitize_stage_proxy_domain`.
#   - Configures the site using `configure_stage_file_proxy`.
#
setup_single_site_stage_file_proxy_automatic() {
    local config_path="$1"

    printf "\n"
    printf "${CYAN}=== Automatic Setup for Single Site ===${RESET}\n"

    # Get the mapping for blog_id 1 (main site)
    local production_domain
    production_domain=$(get_domain_mapping_for_site "$config_path" "1")

    if [[ -z "$production_domain" ]]; then
        printf "${YELLOW}⚠️  No domain mapping found for main site${RESET}\n"
        return 1
    fi

    # Activate the plugin
    if wp plugin activate stage-file-proxy --quiet 2>/dev/null; then
        printf "${GREEN}✓ Plugin activated successfully${RESET}\n"
    else
        printf "${YELLOW}⚠️  Could not activate plugin - may need manual activation${RESET}\n"
    fi

    # Sanitize domain for Stage File Proxy (ensure https:// protocol)
    local sanitized_domain
    sanitized_domain=$(sanitize_stage_proxy_domain "$production_domain")
    if [[ $? -ne 0 || -z "$sanitized_domain" ]]; then
        printf "${RED}❌ Invalid production domain format: $production_domain${RESET}\n"
        return 1
    fi

    printf "\n"
    printf "${CYAN} Site Configuration ${RESET}\n"
    printf " Source:      %s\n" "$(wp option get siteurl --quiet 2>/dev/null)"
    printf " Destination: %s\n" "$sanitized_domain"
    printf " Mode:        header\n"
    printf "\n"

    # Configure using the sanitized domain
    if configure_stage_file_proxy "$sanitized_domain" "header"; then
        return 0
    else
        printf "${RED}❌ Failed to configure single site${RESET}\n"
        return 1
    fi
}

# ===============================================
# Multisite automatic setup using site_mappings
# ===============================================
#
# Description: Configures Stage File Proxy for all sites in a multisite network
#              using production domain mappings from the configuration file.
#
# Parameters:
#   - $1: Path to the configuration file containing site mappings.
#
# Returns:
#   - 0 (Success) always, even if some sites fail to configure.
#   - 1 (Failure) if network activation fails.
#
# Behavior:
#   - Activates the plugin network-wide.
#   - Uses `wp site list` to get all sites.
#   - For each site, finds the corresponding mapping using `get_stage_proxy_mappings`.
#   - Sanitizes the domain and calls `configure_stage_file_proxy`.
#   - Falls back to `setup_multisite_from_config_mappings` if WP-CLI site list fails.
#
setup_multisite_stage_file_proxy_automatic() {
    local config_path="$1"

    printf "\n"
    printf "${CYAN}=== Automatic Setup for Multisite ===${RESET}\n"

    # Activate the plugin network-wide
    printf "${BLUE}Activating Stage File Proxy plugin network-wide...${RESET}\n"
    if wp plugin activate stage-file-proxy --network --quiet; then
        printf "${GREEN}✓ Plugin activated network-wide successfully${RESET}\n"
    else
        printf "${RED}❌ Failed to activate plugin network-wide${RESET}\n"
        return 1
    fi

    # Get all sites and their mappings
    local sites_data mappings
    sites_data=$(wp site list --format=csv --fields=blog_id,url --quiet 2>/dev/null)
    mappings=$(get_stage_proxy_mappings "$config_path")

    # Check if wp site list command succeeded
    if [[ $? -ne 0 || -z "$sites_data" ]]; then
        printf "${YELLOW}⚠️  Could not retrieve site list from WordPress. Using config mappings instead...${RESET}\n"
        # Fallback: Use mappings directly when WP-CLI fails
        setup_multisite_from_config_mappings "$config_path" "$mappings"
        return $?
    fi

    printf "\n"
    printf "${BLUE}Configuring sites automatically using existing mappings...${RESET}\n"
    printf "\n"

    local configured_count=0
    local total_count=0

    # Skip the CSV header line and process each site
    local sites_without_header
    sites_without_header=$(echo "$sites_data" | tail -n +2)

    while IFS=',' read -r blog_id site_url; do
        [[ -z "$blog_id" || -z "$site_url" ]] && continue
        total_count=$((total_count + 1))

        # Find mapping for this blog_id
        local production_domain=""
        while IFS=':' read -r mapped_blog_id mapped_domain; do
            [[ -z "$mapped_blog_id" || -z "$mapped_domain" ]] && continue
            if [[ "$mapped_blog_id" == "$blog_id" ]]; then
                production_domain="$mapped_domain"
                break
            fi
        done <<< "$mappings"

        if [[ -n "$production_domain" ]]; then
            # Sanitize domain for Stage File Proxy (ensure https:// protocol)
            local sanitized_domain
            sanitized_domain=$(sanitize_stage_proxy_domain "$production_domain")
            if [[ $? -eq 0 && -n "$sanitized_domain" ]]; then
                printf "${CYAN} Site Configuration (ID: $blog_id)${RESET}\n"
                printf " Source:      %s\n" "${site_url%/}"
                printf " Destination: %s\n" "$sanitized_domain"
                printf " Mode:        header\n"
                printf "\n"
                if configure_stage_file_proxy "$sanitized_domain" "header" "$site_url"; then
                    configured_count=$((configured_count + 1))
                else
                    printf "${RED}❌ Failed to configure $site_url${RESET}\n"
                fi
                printf "\n\n"
            else
                printf "${RED}❌ Invalid domain format for site $blog_id: $production_domain${RESET}\n"
            fi
        else
            printf "${YELLOW}⚠️  No mapping found for site $blog_id ($site_url) - skipping${RESET}\n"
        fi
    done <<< "$sites_without_header"

    printf "\n"
    printf "${GREEN}=== Automatic Multisite Setup Complete ===${RESET}\n"
    printf "${GREEN}Configured $configured_count out of $total_count sites${RESET}\n"
    return 0
}

# ===============================================
# Fallback function when WP-CLI site list fails - works directly from config
# ===============================================
#
# Description: A configuration fallback mechanism for multisite. When WP-CLI fails
#              to list the sites (e.g., due to database issues), this function
#              attempts to configure Stage File Proxy for sites based only on the
#              mappings found in the configuration file.
#
# Parameters:
#   - $1: Path to the configuration file.
#   - $2: A string containing the site mappings in `blog_id:old_domain` format.
#
# Returns:
#   - 0 (Success) always.
#
# Behavior:
#   - Activates the plugin network-wide (with suppressed errors).
#   - Iterates through the provided mappings.
#   - Attempts to determine the local site URL (using `read_local_domain` or simple fallback).
#   - Configures the site options using the URL flag inferred from config.
#
setup_multisite_from_config_mappings() {
    local config_path="$1"
    local mappings="$2"

    printf "\n"
    printf "${BLUE}Configuring sites directly from config mappings...${RESET}\n"
    printf "\n"

    # Activate the plugin network-wide
    printf "${BLUE}Activating Stage File Proxy plugin network-wide...${RESET}\n"
    if wp plugin activate stage-file-proxy --network --quiet 2>/dev/null; then
        printf "${GREEN}✓ Plugin activated network-wide successfully${RESET}\n"
    else
        printf "${YELLOW}⚠️  Could not activate plugin - may need manual activation${RESET}\n"
    fi

    local configured_count=0
    local total_count=0

    # Process each mapping directly
    while IFS=':' read -r blog_id production_domain; do
        [[ -z "$blog_id" || -z "$production_domain" ]] && continue
        total_count=$((total_count + 1))

        # Construct site URL from config mapping
        local site_url
        if command -v read_local_domain >/dev/null 2>&1; then
            site_url=$(read_local_domain "$blog_id" "$config_path")
        else
            # Simple fallback - try to get from general config
            local new_domain
            new_domain=$(read_general_config "new_domain" "$config_path" | sed 's|https\?://||; s|/$||')
            if [[ "$blog_id" == "1" ]]; then
                site_url="https://$new_domain"
            else
                # For subsites, we'd need more logic, but this is a basic fallback
                site_url="https://$new_domain"
            fi
        fi

        # Sanitize domain for Stage File Proxy (ensure https:// protocol)
        local sanitized_domain
        sanitized_domain=$(sanitize_stage_proxy_domain "$production_domain")
        if [[ $? -eq 0 && -n "$sanitized_domain" ]]; then
            printf "${CYAN}Configuring site $blog_id (from mapping) → $sanitized_domain${RESET}\n"

            # Configure using the blog ID approach
            if wp option update sfp_url "$sanitized_domain" --url="$site_url" --quiet 2>/dev/null && \
               wp option update sfp_mode "header" --url="$site_url" --quiet 2>/dev/null; then
                printf "${GREEN}✅ Site $blog_id configured successfully${RESET}\n"
                configured_count=$((configured_count + 1))
            else
                printf "${YELLOW}⚠️  Site $blog_id configuration may need manual setup${RESET}\n"
            fi
        else
            printf "${RED}❌ Invalid domain format for site $blog_id: $production_domain${RESET}\n"
        fi
    done <<< "$mappings"

    printf "\n"
    printf "${GREEN}=== Config-Based Multisite Setup Complete ===${RESET}\n"
    printf "${GREEN}Attempted configuration for $configured_count out of $total_count sites${RESET}\n"

    if [[ $configured_count -lt $total_count ]]; then
        printf "${YELLOW}💡 Some sites may need manual configuration when database is available${RESET}\n"
    fi

    return 0
}

# ===============================================
# Single site manual setup
# ===============================================
#
# Description: Handles the interactive, manual setup for a WordPress single site
#              when no site mappings are found, including saving the new mapping.
#
# Parameters:
#   - $1: Path to the configuration file (where the new mapping will be saved).
#
# Returns:
#   - 0 (Success) if the site is configured and the mapping is saved.
#   - 1 (Failure) otherwise.
#
# Behavior:
#   - Activates the plugin.
#   - Uses `get_validated_domain` to prompt for the source domain.
#   - Calls `write_site_mapping` or `update_site_mapping` (if available) to save the mapping for blog ID 1.
#   - Configures the site using `configure_stage_file_proxy`.
#
setup_single_site_stage_file_proxy_manual() {
    local config_path="$1"

    printf "\n"
    printf "${CYAN}=== Manual Setup for Single Site ===${RESET}\n"

    # Activate the plugin
    if wp plugin activate stage-file-proxy --quiet; then
        printf "${GREEN}✓ Plugin activated successfully${RESET}\n"
    else
        printf "${RED}❌ Failed to activate plugin${RESET}\n"
        return 1
    fi

    # Get production domain interactively
    if get_validated_domain "Enter the production domain (e.g., example.com): "; then
        local source_domain="$VALIDATED_DOMAIN"

        # Save mapping if config path provided
        if [[ -n "$config_path" ]]; then
            # Use unified config reader if available
            if command -v write_site_mapping >/dev/null 2>&1; then
                local current_url
                current_url=$(wp option get siteurl --quiet 2>/dev/null | sed 's|https\?://||')
                write_site_mapping "1" "$source_domain" "$current_url" "$config_path"
            elif command -v update_site_mapping >/dev/null 2>&1; then
                local current_url
                current_url=$(wp option get siteurl --quiet 2>/dev/null | sed 's|https\?://||')
                update_site_mapping "$config_path" "1" "$source_domain" "$current_url"
            fi
        fi

        # Configure the site (source_domain is already sanitized from get_validated_domain)
        if configure_stage_file_proxy "$source_domain" "header"; then
            printf "${GREEN}✅ Single site configured manually${RESET}\n"
            return 0
        else
            printf "${RED}❌ Failed to configure single site${RESET}\n"
            return 1
        fi
    else
        printf "${YELLOW}⚠️  Setup cancelled${RESET}\n"
        return 1
    fi
}

# ===============================================
# Multisite manual setup with config integration
# ===============================================
#
# Description: Handles the interactive, manual setup for a WordPress multisite
#              when no site mappings are found, integrating the configuration
#              by saving new or updating existing site mappings in the config file.
#
# Parameters:
#   - $1: Path to the configuration file (where the new mappings will be saved/updated).
#
# Returns:
#   - 0 (Success) if the plugin is activated and all sites are processed.
#   - 1 (Failure) if plugin activation fails.
#
# Behavior:
#   - Activates the plugin network-wide.
#   - Iterates through all sites retrieved via `wp site list`.
#   - Checks for existing mappings and prompts the user to use the existing domain or provide a new one.
#   - Calls `write_site_mapping` or `update_site_mapping` to save the production domain.
#   - Configures the site using `configure_stage_file_proxy`.
#
setup_multisite_stage_file_proxy_manual() {
    local config_path="$1"

    printf "\n"
    printf "${CYAN}=== Manual Setup for Multisite ===${RESET}\n"

    # Activate the plugin network-wide
    printf "${BLUE}Activating Stage File Proxy plugin network-wide...${RESET}\n"
    if wp plugin activate stage-file-proxy --network --quiet; then
        printf "${GREEN}✓ Plugin activated network-wide successfully${RESET}\n"
    else
        printf "${RED}❌ Failed to activate plugin network-wide${RESET}\n"
        return 1
    fi

    # Get list of all sites
    printf "\n"
    printf "${BLUE}Getting list of all sites in the network...${RESET}\n"
    local sites_data
    sites_data=$(wp site list --format=csv --fields=blog_id,url --quiet)

    printf "\n"
    printf "${BLUE}Now configuring each site manually...${RESET}\n"
    printf "\n"

    # Configure each site using CSV data
    local site_count=0
    local sites_without_header
    sites_without_header=$(echo "$sites_data" | tail -n +2)

    while IFS=',' read -r blog_id site_url; do
        [[ -z "$blog_id" || -z "$site_url" ]] && continue
        site_count=$((site_count + 1))

        printf "${CYAN}--- Configuring Site $site_count (ID: $blog_id): $site_url ---${RESET}\n"

        # Check if we already have a site mapping for this blog_id
        local existing_domain=""
        if [[ -n "$config_path" ]]; then
            # Use unified config reader if available
            if command -v read_site_mapping >/dev/null 2>&1; then
                local mapping_result
                if mapping_result=$(read_site_mapping "$blog_id" "$config_path" 2>/dev/null); then
                    # Extract old_domain from old_domain:new_domain format
                    existing_domain="${mapping_result%%:*}"
                fi
            elif command -v get_site_mappings >/dev/null 2>&1; then
                local site_mappings
                if site_mappings=$(get_site_mappings "$config_path" 2>/dev/null); then
                    while IFS=':' read -r config_blog_id config_old_domain config_new_domain; do
                        if [[ "$config_blog_id" == "$blog_id" && -n "$config_old_domain" ]]; then
                            existing_domain="$config_old_domain"
                            break
                        fi
                    done <<< "$site_mappings"
                fi
            fi
        fi

        if [[ -n "$existing_domain" ]]; then
            printf "${GREEN}✓ Found existing mapping: %s${RESET}\n" "$existing_domain"
            printf "${CYAN}Press Enter to use this domain, or type a new domain to override: ${RESET}"
            read -r domain_override < /dev/tty

            if [[ -n "$domain_override" ]]; then
                if get_validated_domain_with_input "$domain_override"; then
                    local source_domain="$VALIDATED_DOMAIN"
                    # Use existing update_site_mapping function or unified config reader
                    if [[ -n "$config_path" ]]; then
                        if command -v write_site_mapping >/dev/null 2>&1; then
                            write_site_mapping "$blog_id" "$source_domain" "$site_url" "$config_path"
                        elif command -v update_site_mapping >/dev/null 2>&1; then
                            update_site_mapping "$config_path" "$blog_id" "$source_domain" "$site_url"
                        fi
                    fi
                else
                    printf "${RED}❌ Invalid domain format, keeping existing mapping${RESET}\n"
                    local source_domain="$existing_domain"
                fi
            else
                local source_domain="$existing_domain"
            fi
        else
            if get_validated_domain "Enter production domain for $site_url (press Enter to skip): "; then
                local source_domain="$VALIDATED_DOMAIN"

                # Save new mapping using existing infrastructure or unified config reader
                if [[ -n "$config_path" ]]; then
                    if command -v write_site_mapping >/dev/null 2>&1; then
                        write_site_mapping "$blog_id" "$source_domain" "$site_url" "$config_path"
                    elif command -v update_site_mapping >/dev/null 2>&1; then
                        update_site_mapping "$config_path" "$blog_id" "$source_domain" "$site_url"
                    fi
                fi
            else
                printf "${YELLOW}⚠️  Skipping $site_url${RESET}\n"
                continue
            fi
        fi

        # Sanitize domain for Stage File Proxy (ensure https:// protocol)
        # This is especially important for existing domains from config that may lack protocol
        local sanitized_domain
        sanitized_domain=$(sanitize_stage_proxy_domain "$source_domain")
        if [[ $? -eq 0 && -n "$sanitized_domain" ]]; then
            if configure_stage_file_proxy "$sanitized_domain" "header" "$site_url"; then
                printf "${GREEN}✅ $site_url configured${RESET}\n"
            else
                printf "${RED}❌ Failed to configure site: $site_url${RESET}\n"
            fi
        else
            printf "${RED}❌ Invalid domain format for site: $source_domain${RESET}\n"
        fi
    done <<< "$sites_without_header"

    # Mappings are saved automatically using existing site mapping infrastructure

    printf "${GREEN}=== Manual Multisite Setup Complete ===${RESET}\n"
    printf "${GREEN}Stage File Proxy is now active and configured for all sites!${RESET}\n"
}

# ===============================================
# Helper function to validate domain from direct input
# ===============================================
#
# Description: Validates a domain string provided directly as an argument, bypassing
#              the interactive prompt of `get_validated_domain`.
#
# Parameters:
#   - $1: The input domain string to validate and sanitize.
#
# Returns:
#   - 0 (Success) if the domain is valid, and the global variable `VALIDATED_DOMAIN` is set.
#   - 1 (Failure) otherwise.
#
# Behavior:
#   - Calls `sanitize_stage_proxy_domain` for validation and standardization.
#   - Sets the global variable `VALIDATED_DOMAIN`.
#
get_validated_domain_with_input() {
    local input="$1"
    local clean_domain

    clean_domain=$(sanitize_stage_proxy_domain "$input")
    if [[ $? -eq 0 && -n "$clean_domain" ]]; then
        export VALIDATED_DOMAIN="$clean_domain"
        return 0
    else
        return 1
    fi
}

# ===============================================
# Install Stage File Proxy plugin
# ===============================================
#
# Description: Installs the Stage File Proxy plugin from a GitHub release
#              using WP-CLI, falling back to direct download via curl/wget
#              if WP-CLI installation fails.
#
# Parameters:
#   - None.
#
# Returns:
#   - 0 (Success) if the plugin is already installed or installed successfully.
#   - 1 (Failure) if all installation attempts fail.
#
# Behavior:
#   - Checks for existing installation first.
#   - Attempts download/install using `curl` or `wget` as fallback mechanisms.
#
install_stage_file_proxy_plugin() {
    local install_success=false
    local install_log="/tmp/sfp_install.log"

    # Check if plugin is already installed
    if wp plugin is-installed stage-file-proxy --quiet 2>/dev/null; then
        printf "${GREEN}✓ Stage File Proxy plugin already installed${RESET}\n"
        return 0
    fi

    printf "${BLUE}Installing Stage File Proxy plugin...${RESET}\n"

    # Download Plugin
    local temp_plugin_file="/tmp/stage-file-proxy.zip"
    if command -v curl >/dev/null 2>&1; then
        if curl -sL "https://github.com/manishsongirkar/stage-file-proxy/releases/download/101/stage-file-proxy.zip" -o "$temp_plugin_file" >> "$install_log" 2>&1; then
            if wp plugin install "$temp_plugin_file" --quiet >> "$install_log" 2>&1; then
                printf "${GREEN}✅ Plugin installed successfully via direct download${RESET}\n"
                install_success=true
            fi
            rm -f "$temp_plugin_file" 2>/dev/null
        fi
    elif command -v wget >/dev/null 2>&1; then
        if wget -O "$temp_plugin_file" "https://github.com/manishsongirkar/stage-file-proxy/releases/download/101/stage-file-proxy.zip" >> "$install_log" 2>&1; then
            if wp plugin install "$temp_plugin_file" --quiet >> "$install_log" 2>&1; then
                printf "${GREEN}✅ Plugin installed successfully via direct download${RESET}\n"
                install_success=true
            fi
            rm -f "$temp_plugin_file" 2>/dev/null
        fi
    fi

    # Handle installation result
    if [[ "$install_success" == true ]]; then
        # Verify installation was actually successful
        if wp plugin is-installed stage-file-proxy --quiet 2>/dev/null; then
            printf "${GREEN}✅ Plugin installation verified${RESET}\n"
            return 0
        else
            printf "${RED}❌ Plugin installation verification failed${RESET}\n"
            return 1
        fi
    else
        printf "${RED}❌ All plugin installation methods failed${RESET}\n"
        printf "${YELLOW}💡 You may need to install manually or check network connectivity${RESET}\n"
        return 1
    fi
}

# Export functions for external use
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    {
        export -f setup_stage_file_proxy
        export -f setup_stage_file_proxy_unified
        export -f show_stage_file_proxy_config
        export -f bulk_configure_multisite
        export -f configure_stage_file_proxy
        export -f sanitize_stage_proxy_domain
        export -f get_validated_domain
        export -f get_validated_domain_with_input
        export -f setup_single_site_stage_file_proxy
        export -f setup_multisite_stage_file_proxy
        export -f setup_single_site_stage_file_proxy_automatic
        export -f setup_multisite_stage_file_proxy_automatic
        export -f setup_single_site_stage_file_proxy_manual
        export -f setup_multisite_stage_file_proxy_manual
        export -f install_stage_file_proxy_plugin
        export -f get_stage_proxy_mappings
        export -f save_stage_proxy_mapping
        export -f get_domain_mapping_for_site
    } >/dev/null 2>&1
fi
