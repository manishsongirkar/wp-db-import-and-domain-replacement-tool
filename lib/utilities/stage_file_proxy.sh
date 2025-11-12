#!/bin/bash

# ================================================================
# Stage File Proxy Utilities Module
# ================================================================
#
# This module provides functions for setting up and configuring
# the Stage File Proxy plugin for WordPress installations.
#
# Compatible with Stage File Proxy plugin v101+
# - Uses separate 'sfp_url' and 'sfp_mode' options instead of JSON format
# - 'source_domain' → 'sfp_url'
# - 'method' → 'sfp_mode' with default value 'header'
# - All domains are stored with https:// protocol in the database for security
# - Improved user input validation and sanitization
# - Better user feedback about what gets stored in the database
# - Automatic protocol conversion (http:// → https://, missing protocol → https://)
#
# Functions provided:
# - setup_stage_file_proxy          Main setup function (interactive)
# - show_stage_file_proxy_config    Display current configuration
# - bulk_configure_multisite        Set same domain for all sites (multisite only)
# - configure_stage_file_proxy      Internal configuration function
# - sanitize_domain                 Domain validation and sanitization
# - get_validated_domain            Interactive domain input with validation
#

# Function to sanitize and validate domain input (Updated for new plugin structure)
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

# Function to get and validate domain input interactively
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

# Function to configure Stage File Proxy plugin settings
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

    printf "${GREEN}✅ Configuration successful (URL: $domain, Mode: $mode)${RESET}\n"
}

# Main setup function for Stage File Proxy
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

    # Detect if this is a multisite installation
    local is_multisite
    local subdomain_install
    is_multisite=$(wp config get MULTISITE --quiet 2>/dev/null || echo "false")
    subdomain_install=$(wp config get SUBDOMAIN_INSTALL --quiet 2>/dev/null || echo "false")

    printf "${CYAN}WordPress Installation Type:${RESET}\n"
    if [[ "$is_multisite" == "1" || "$is_multisite" == "true" ]]; then
        if [[ "$subdomain_install" == "1" || "$subdomain_install" == "true" ]]; then
            printf "${GREEN}✓ Multisite detected (subdomain configuration)${RESET}\n"
        else
            printf "${GREEN}✓ Multisite detected (subdirectory configuration)${RESET}\n"
        fi
        setup_multisite_stage_file_proxy
    else
        printf "${GREEN}✓ Single site detected${RESET}\n"
        setup_single_site_stage_file_proxy
    fi
}

# Single site setup function
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

# Multisite setup function
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
    local sites
    sites=$(wp site list --field=url --quiet)

    if [[ -z "$sites" ]]; then
        printf "${RED}✗ No sites found in the network${RESET}\n"
        return 1
    fi

    printf "${YELLOW}Sites found:${RESET}\n"
    echo "$sites" | nl -w2 -s'. '

    printf "\n"
    printf "${BLUE}Now configuring each site...${RESET}\n"
    printf "\n"

    # Configure each site
    local site_count=0
    while IFS= read -r site_url; do
        site_count=$((site_count + 1))
        printf "${CYAN}--- Configuring Site $site_count: $site_url ---${RESET}\n"

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
    done <<< "$sites"

    printf "${GREEN}=== Multisite Setup Complete ===${RESET}\n"
    printf "${GREEN}Stage File Proxy is now active and configured for all sites!${RESET}\n"
}

# Function to display current configuration
show_stage_file_proxy_config() {
    printf "${CYAN}=== Current Stage File Proxy Configuration ===${RESET}\n"

    local is_multisite
    is_multisite=$(wp config get MULTISITE --quiet 2>/dev/null || echo "false")

    if [[ "$is_multisite" == "1" || "$is_multisite" == "true" ]]; then
        printf "${YELLOW}Multisite Configuration:${RESET}\n"
        local sites
        sites=$(wp site list --field=url --quiet)
        while IFS= read -r site_url; do
            printf "\n"
            printf "${BLUE}Site: $site_url${RESET}\n"

            # Get sfp_url and sfp_mode separately (new plugin structure)
            local sfp_url sfp_mode
            sfp_url=$(wp --url="$site_url" option get sfp_url --quiet 2>/dev/null || echo "Not set")
            sfp_mode=$(wp --url="$site_url" option get sfp_mode --quiet 2>/dev/null || echo "Not set")

            printf "  ${GREEN}sfp_url:${RESET} $sfp_url\n"
            printf "  ${GREEN}sfp_mode:${RESET} $sfp_mode\n"
        done <<< "$sites"
    else
        printf "${YELLOW}Single Site Configuration:${RESET}\n"

        # Get sfp_url and sfp_mode separately (new plugin structure)
        local sfp_url sfp_mode
        sfp_url=$(wp option get sfp_url --quiet 2>/dev/null || echo "Not set")
        sfp_mode=$(wp option get sfp_mode --quiet 2>/dev/null || echo "Not set")

        printf "${GREEN}sfp_url:${RESET} $sfp_url\n"
        printf "${GREEN}sfp_mode:${RESET} $sfp_mode\n"
    fi
}

# Function to quickly set all sites to the same domain (for multisite)
bulk_configure_multisite() {
    local is_multisite
    is_multisite=$(wp config get MULTISITE --quiet 2>/dev/null || echo "false")

    if [[ "$is_multisite" != "1" && "$is_multisite" != "true" ]]; then
        printf "${RED}This function is only for multisite installations${RESET}\n"
        return 1
    fi

    printf "${CYAN}=== Bulk Configure All Sites ===${RESET}\n"
    if get_validated_domain "Enter the production domain to use for ALL sites (e.g., example.com): "; then
        local source_domain="$VALIDATED_DOMAIN"

        printf "\n"
        printf "${BLUE}Applying configuration to all sites...${RESET}\n"
        printf "\n"

        local sites
        sites=$(wp site list --field=url --quiet)

        while IFS= read -r site_url; do
            printf "${CYAN}Configuring: $site_url${RESET}\n"
            if configure_stage_file_proxy "$source_domain" "header" "$site_url"; then
                printf "${GREEN}✅ $site_url configured${RESET}\n"
            else
                printf "${RED}❌ Failed to configure $site_url${RESET}\n"
            fi
        done <<< "$sites"

        printf "\n"
        printf "${GREEN}✅ Bulk configuration complete!${RESET}\n"
    else
        printf "${YELLOW}⚠️  Configuration cancelled.${RESET}\n"
    fi
}

# Export functions for external use
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    {
        export -f setup_stage_file_proxy
        export -f show_stage_file_proxy_config
        export -f bulk_configure_multisite
        export -f configure_stage_file_proxy
        export -f sanitize_stage_proxy_domain
        export -f get_validated_domain
        export -f setup_single_site_stage_file_proxy
        export -f setup_multisite_stage_file_proxy
    } >/dev/null 2>&1
fi
