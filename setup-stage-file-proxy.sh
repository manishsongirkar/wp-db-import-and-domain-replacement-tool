#!/bin/bash

# Stage File Proxy Setup Function
# This function activates and configures the Stage File Proxy plugin for WordPress
# Supports both single site and multisite installations
#
# UPDATED: Compatible with new Stage File Proxy plugin structure (v101+)
# - Uses separate 'sfp_url' and 'sfp_mode' options instead of JSON format
# - 'source_domain' → 'sfp_url'
# - 'method' → 'sfp_mode' with default value 'header'
# - All domains are stored with https:// protocol in the database for security
# - Improved user input validation and sanitization
# - Better user feedback about what gets stored in the database
# - Automatic protocol conversion (http:// → https://, missing protocol → https://)

# Get the directory where the script is located
# Handle both direct execution and sourcing scenarios
if [[ -n "${BASH_SOURCE[0]}" ]]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
else
    # Fallback for edge cases
    SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
fi

# Import centralized colors with error handling
if [[ -f "$SCRIPT_DIR/colors.sh" ]]; then
    source "$SCRIPT_DIR/colors.sh"
else
    # Fallback: define a minimal colors function if colors.sh is not found
    colors() {
        echo "Warning: colors.sh not found, using no colors" >&2
        return 0
    }
fi

# Function to sanitize and validate domain input (Updated for new plugin structure)
sanitize_domain() {
    local input="$1"
    local clean_domain

    # Check if input is empty
    if [[ -z "$input" ]]; then
        return 1
    fi

    # Check input length (reasonable URL length limit)
    if [[ ${#input} -gt 2048 ]]; then
        return 1
    fi

    # Remove leading/trailing whitespace using bash built-ins
    clean_domain="$input"
    # Remove leading whitespace
    while [[ "$clean_domain" =~ ^[[:space:]] ]]; do
      clean_domain="${clean_domain#[[:space:]]}"
    done
    # Remove trailing whitespace
    while [[ "$clean_domain" =~ [[:space:]]$ ]]; do
      clean_domain="${clean_domain%[[:space:]]}"
    done

    # Check for dangerous characters that could cause injection
    if [[ "$clean_domain" =~ [\;\|\&\$\`\(\)\<\>\"\'] ]]; then
        return 1
    fi

    # Check for control characters and non-printable characters
    if [[ "$clean_domain" =~ [[:cntrl:]] ]]; then
        return 1
    fi

    # Remove trailing slashes
    clean_domain=${clean_domain%/}

    # UPDATED: Ensure https:// protocol for database storage (new plugin expects full URL)
    # Remove any existing protocol first
    clean_domain="${clean_domain#http://}"
    clean_domain="${clean_domain#https://}"

    # Add https:// protocol (required for database storage)
    clean_domain="https://$clean_domain"

    # Validate URL format more thoroughly (with required https protocol)
    # Domain must have at least one dot (.) for a valid TLD, except for localhost and IP addresses
    if [[ "$clean_domain" =~ ^https://localhost([:]([0-9]{1,5}))?(/.*)?$ ]]; then
        # Allow localhost with optional port and path
        :
    elif [[ "$clean_domain" =~ ^https://([0-9]{1,3}\.){3}[0-9]{1,3}([:]([0-9]{1,5}))?(/.*)?$ ]]; then
        # Allow IP addresses with optional port and path
        :
    elif ! [[ "$clean_domain" =~ ^https://[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?)+([:]([0-9]{1,5}))?(/.*)?$ ]]; then
        return 1
    fi

    # Additional security check: ensure no multiple protocols using bash built-ins
    local protocol_count=0
    local temp_domain="$clean_domain"
    while [[ "$temp_domain" == *"://"* ]]; do
        protocol_count=$((protocol_count + 1))
        temp_domain="${temp_domain#*://}"
    done

    if [[ "$protocol_count" -gt 1 ]]; then
        return 1
    fi

    # Return the sanitized domain with https:// protocol
    echo "$clean_domain"
    return 0
}

# Function to get and validate domain input interactively
get_validated_domain() {
    # Load scoped colors
    eval "$(colors)"

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
            printf "${YELLOW}⚠️ Skipping configuration for this site (empty input)${RESET}\n"
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
        clean_domain=$(sanitize_domain "$domain")
        if [[ $? -eq 0 ]]; then
            # Check for localhost patterns
            if [[ "$clean_domain" =~ (localhost|127\.0\.0\.1|0\.0\.0\.0) ]]; then
                printf "${YELLOW}⚠️ Warning: Localhost pattern detected. Continue? (y/n): ${RESET}"
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
configure_sfp() {
    # Load scoped colors
    eval "$(colors)"

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

setup_stage_file_proxy() {
    # Load scoped colors
    eval "$(colors)"

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
            printf "${YELLOW}⚠️ GitHub installation failed, trying direct download method...${RESET}\n"

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
        setup_multisite
    else
        printf "${GREEN}✓ Single site detected${RESET}\n"
        setup_single_site
    fi
}

setup_single_site() {
    # Load scoped colors
    eval "$(colors)"

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
        printf "${BLUE}Configuring Stage File Proxy...$NC\n"
        if configure_stage_file_proxy "$source_domain" "header"; then
            printf "${GREEN}✅ Plugin configured successfully$NC\n"
        else
            printf "${RED}❌ Failed to configure plugin$NC\n"
            return 1
        fi
    else
        printf "${YELLOW}⚠️  Skipping Stage File Proxy configuration for this site$NC\n"
    fi

    printf "\n"
    printf "${GREEN}=== Setup Complete ===$NC\n"
    printf "${GREEN}Stage File Proxy is now active and configured!$NC\n"
}

setup_multisite() {
    eval "$(colors)"
    printf "\n"
    printf "${CYAN}=== Setting up for Multisite ===$NC\n"

    # Activate the plugin network-wide
    printf "${BLUE}Activating Stage File Proxy plugin network-wide...$NC\n"
    if wp plugin activate stage-file-proxy --network --quiet; then
        printf "${GREEN}✓ Plugin activated network-wide successfully$NC\n"
    else
        printf "${RED}✗ Failed to activate plugin network-wide$NC\n"
        return 1
    fi

    # Get list of all sites
    printf "\n"
    printf "${BLUE}Getting list of all sites in the network...$NC\n"
    local sites
    sites=$(wp site list --field=url --quiet)

    if [[ -z "$sites" ]]; then
        printf "${RED}✗ No sites found in the network$NC\n"
        return 1
    fi

    printf "${YELLOW}Sites found:$NC\n"
    echo "$sites" | nl -w2 -s'. '

    printf "\n"
    printf "${BLUE}Now configuring each site...$NC\n"
    printf "\n"

    # Configure each site
    local site_count=0
    while IFS= read -r site_url; do
        site_count=$((site_count + 1))
        printf "${CYAN}--- Configuring Site $site_count: $site_url ---$NC\n"

        if get_validated_domain "Enter production domain for $site_url (press Enter to skip): "; then
            local source_domain="$VALIDATED_DOMAIN"

            if configure_stage_file_proxy "$source_domain" "header" "$site_url"; then
                printf "${GREEN}✅ $site_url configured$NC\n"
            else
                printf "${RED}❌ Failed to configure site: $site_url$NC\n"
            fi
        else
            printf "${YELLOW}⚠️  Skipping $site_url$NC\n"
        fi
    done <<< "$sites"

    printf "${GREEN}=== Multisite Setup Complete ===$NC\n"
    printf "${GREEN}Stage File Proxy is now active and configured for all sites!$NC\n"
}

# Function to display current configuration
show_stage_file_proxy_config() {
    eval "$(colors)"
    printf "${CYAN}=== Current Stage File Proxy Configuration ===$NC\n"

    local is_multisite
    is_multisite=$(wp config get MULTISITE --quiet 2>/dev/null || echo "false")

    if [[ "$is_multisite" == "1" || "$is_multisite" == "true" ]]; then
        printf "${YELLOW}Multisite Configuration:$NC\n"
        local sites
        sites=$(wp site list --field=url --quiet)
        while IFS= read -r site_url; do
            printf "\n"
            printf "${BLUE}Site: $site_url$NC\n"

            # Get sfp_url and sfp_mode separately (new plugin structure)
            local sfp_url sfp_mode
            sfp_url=$(wp --url="$site_url" option get sfp_url --quiet 2>/dev/null || echo "Not set")
            sfp_mode=$(wp --url="$site_url" option get sfp_mode --quiet 2>/dev/null || echo "Not set")

            printf "  ${GREEN}sfp_url:$NC $sfp_url\n"
            printf "  ${GREEN}sfp_mode:$NC $sfp_mode\n"
        done <<< "$sites"
    else
        printf "${YELLOW}Single Site Configuration:$NC\n"

        # Get sfp_url and sfp_mode separately (new plugin structure)
        local sfp_url sfp_mode
        sfp_url=$(wp option get sfp_url --quiet 2>/dev/null || echo "Not set")
        sfp_mode=$(wp option get sfp_mode --quiet 2>/dev/null || echo "Not set")

        printf "${GREEN}sfp_url:$NC $sfp_url\n"
        printf "${GREEN}sfp_mode:$NC $sfp_mode\n"
    fi
}

# Function to quickly set all sites to the same domain (for multisite)
bulk_configure_multisite() {
    eval "$(colors)"
    local is_multisite
    is_multisite=$(wp config get MULTISITE --quiet 2>/dev/null || echo "false")

    if [[ "$is_multisite" != "1" && "$is_multisite" != "true" ]]; then
        printf "${RED}This function is only for multisite installations$NC\n"
        return 1
    fi

    printf "${CYAN}=== Bulk Configure All Sites ===$NC\n"
    if get_validated_domain "Enter the production domain to use for ALL sites (e.g., example.com): "; then
        local source_domain="$VALIDATED_DOMAIN"

        printf "\n"
        printf "${BLUE}Applying configuration to all sites...$NC\n"
        printf "\n"

        local sites
        sites=$(wp site list --field=url --quiet)

        while IFS= read -r site_url; do
            printf "${CYAN}Configuring: $site_url$NC\n"
            if configure_stage_file_proxy "$source_domain" "header" "$site_url"; then
                printf "${GREEN}✅ $site_url configured$NC\n"
            else
                printf "${RED}❌ Failed to configure $site_url$NC\n"
            fi
        done <<< "$sites"

        printf "\n"
        printf "${GREEN}✅ Bulk configuration complete!$NC\n"
    else
        printf "${YELLOW}⚠️  Configuration cancelled.$NC\n"
    fi
}

# Help function
show_help() {
    eval "$(colors)"
    printf "${CYAN}Stage File Proxy Setup Functions (Compatible with new plugin v101+):$NC\n"
    printf "\n"
    printf "${GREEN}setup_stage_file_proxy$NC        - Main setup function (interactive)\n"
    printf "${GREEN}show_stage_file_proxy_config$NC  - Display current configuration\n"
    printf "${GREEN}bulk_configure_multisite$NC      - Set same domain for all sites (multisite only)\n"
    printf "\n"
    printf "${YELLOW}Plugin Structure Changes:$NC\n"
    printf "• OLD: JSON format with 'stage-file-proxy-settings' option\n"
    printf "• NEW: Separate 'sfp_url' and 'sfp_mode' options\n"
    printf "• 'source_domain' → 'sfp_url'\n"
    printf "• 'method' → 'sfp_mode' (default: 'header')\n"
    printf "\n"
    printf "${YELLOW}Available Proxy Modes:$NC\n"
    printf "• header     - HTTP redirect to remote files (fastest, default)\n"
    printf "• download   - Download and save files locally\n"
    printf "• photon     - Use Photon/Jetpack for image processing\n"
    printf "• local      - Use local fallback images if remote fails\n"
    printf "• lorempixel - Use placeholder service for missing images\n"
    printf "\n"
    printf "${WHITE}Usage Examples:$NC\n"
    printf "  ${GREEN}setup_stage_file_proxy$NC\n"
    printf "  ${GREEN}show_stage_file_proxy_config$NC\n"
    printf "  ${GREEN}bulk_configure_multisite$NC\n"
}

# If script is run directly (not sourced), show help
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # Import colors for direct execution
    eval "$(colors)" 2>/dev/null || true

    printf "${CYAN}This script contains functions for setting up Stage File Proxy.$NC\n"
    printf "Source this script to use the functions:\n"
    printf "\n"
    printf "  ${YELLOW}source setup-stage-file-proxy.sh$NC\n"
    printf "  ${GREEN}setup_stage_file_proxy$NC\n"
    printf "\n"
    show_help
fi
