#!/bin/bash

# ================================================================
# Stage File Proxy Utilities Module (Unified)
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
# - UNIFIED: Automatic mode when domain mapping provided, manual when missing
# - REUSES: Existing [site_mappings] section for configuration
#
# Functions provided:
# - setup_stage_file_proxy_unified   Main unified setup function
# - setup_stage_file_proxy           Legacy setup function (interactive)
# - show_stage_file_proxy_config     Display current configuration
# - bulk_configure_multisite         Set same domain for all sites (multisite only)
# - configure_stage_file_proxy       Internal configuration function
# - sanitize_stage_proxy_domain      Domain validation and sanitization
# - get_validated_domain             Interactive domain input with validation
# - get_stage_proxy_mappings         Extract domains from site_mappings
#

# Function to get stage proxy mappings from existing site_mappings
# Returns in format: blog_id:old_domain (production domain for sfp_url)
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

# Function to save stage proxy mapping (reuses existing site mapping infrastructure)
save_stage_proxy_mapping() {
    echo "Mappings are automatically saved in [site_mappings] section"
    return 0
}

# Function to get domain mapping for a specific site (from site_mappings)
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

# Unified Stage File Proxy Setup Function
# Automatically detects mode based on available configuration
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

    # Detect multisite
    local is_multisite
    is_multisite=$(wp config get MULTISITE --quiet 2>/dev/null || echo "false")

    # Check if we have config file and domain mappings available
    local has_mappings=false
    if [[ -n "$config_path" && -f "$config_path" ]]; then
        # Use unified config reader if available
        if command -v has_site_mappings >/dev/null 2>&1; then
            has_site_mappings "$config_path" && has_mappings=true
        else
            # Fallback check
            local mappings
            mappings=$(get_stage_proxy_mappings "$config_path")
            if [[ -n "$mappings" ]]; then
                has_mappings=true
            fi
        fi
    fi

    if [[ "$is_multisite" == "1" || "$is_multisite" == "true" ]]; then
        if [[ "$has_mappings" == "true" ]]; then
            printf "${GREEN}✓ Domain mappings found - using automatic mode${RESET}\n"
            setup_multisite_stage_file_proxy_automatic "$config_path"
        else
            printf "${YELLOW}⚠ No domain mappings found - using manual mode${RESET}\n"
            setup_multisite_stage_file_proxy_manual "$config_path"
        fi
    else
        if [[ "$has_mappings" == "true" ]]; then
            printf "${GREEN}✓ Domain mappings found - using automatic mode${RESET}\n"
            setup_single_site_stage_file_proxy_automatic "$config_path"
        else
            printf "${YELLOW}⚠ No domain mappings found - using manual mode${RESET}\n"
            setup_single_site_stage_file_proxy_manual "$config_path"
        fi
    fi
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

# Function to display current configuration
show_stage_file_proxy_config() {
    printf "${CYAN}=== Current Stage File Proxy Configuration ===${RESET}\n"

    local is_multisite
    is_multisite=$(wp config get MULTISITE --quiet 2>/dev/null || echo "false")

    if [[ "$is_multisite" == "1" || "$is_multisite" == "true" ]]; then
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

# Single site automatic setup using site_mappings
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

    printf "${GREEN}✓ Using production domain: $production_domain${RESET}\n"

    # Activate the plugin
    if wp plugin activate stage-file-proxy --quiet 2>/dev/null; then
        printf "${GREEN}✓ Plugin activated successfully${RESET}\n"
    else
        printf "${YELLOW}⚠️  Could not activate plugin - may need manual activation${RESET}\n"
    fi

    # Configure using the mapped domain
    if configure_stage_file_proxy "$production_domain" "header"; then
        printf "${GREEN}✅ Single site configured automatically${RESET}\n"
        return 0
    else
        printf "${RED}❌ Failed to configure single site${RESET}\n"
        return 1
    fi
}

# Multisite automatic setup using site_mappings
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

    # Debug output (uncomment for troubleshooting)
    # printf "${YELLOW}DEBUG: Sites data received:${RESET}\n"
    # echo "$sites_data" | head -5
    # printf "${YELLOW}DEBUG: Mappings found:${RESET}\n"
    # echo "$mappings"

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
            printf "${CYAN}Configuring site $blog_id ($site_url) → $production_domain${RESET}\n"
            if configure_stage_file_proxy "$production_domain" "header" "$site_url"; then
                printf "${GREEN}✅ $site_url configured${RESET}\n"
                configured_count=$((configured_count + 1))
            else
                printf "${RED}❌ Failed to configure $site_url${RESET}\n"
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

# Fallback function when WP-CLI site list fails - works directly from config
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

        printf "${CYAN}Configuring site $blog_id (from mapping) → $production_domain${RESET}\n"

        # Configure using the blog ID approach
        if wp option update sfp_url "$production_domain" --url="$site_url" --quiet 2>/dev/null && \
           wp option update sfp_mode "header" --url="$site_url" --quiet 2>/dev/null; then
            printf "${GREEN}✅ Site $blog_id configured successfully${RESET}\n"
            configured_count=$((configured_count + 1))
        else
            printf "${YELLOW}⚠️  Site $blog_id configuration may need manual setup${RESET}\n"
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

# Single site manual setup
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

        # Configure the site
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

# Multisite manual setup with config integration
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

        if configure_stage_file_proxy "$source_domain" "header" "$site_url"; then
            printf "${GREEN}✅ $site_url configured${RESET}\n"
        else
            printf "${RED}❌ Failed to configure site: $site_url${RESET}\n"
        fi
    done <<< "$sites_without_header"

    # Mappings are saved automatically using existing site mapping infrastructure

    printf "${GREEN}=== Manual Multisite Setup Complete ===${RESET}\n"
    printf "${GREEN}Stage File Proxy is now active and configured for all sites!${RESET}\n"
}

# Helper function to validate domain from direct input
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

# Install Stage File Proxy plugin
install_stage_file_proxy_plugin() {
    local install_success=false
    local install_log="/tmp/sfp_install.log"

    # Check if plugin is already installed
    if wp plugin is-installed stage-file-proxy --quiet 2>/dev/null; then
        printf "${GREEN}✓ Stage File Proxy plugin already installed${RESET}\n"
        return 0
    fi

    printf "${BLUE}Installing Stage File Proxy plugin...${RESET}\n"

    # Try WordPress.org repository first
    if wp plugin install stage-file-proxy --quiet >> "$install_log" 2>&1; then
        printf "${GREEN}✅ Plugin installed from WordPress.org repository${RESET}\n"
        install_success=true
    else
        printf "${YELLOW}⚠️  WordPress.org installation failed, trying direct download...${RESET}\n"

        # Fallback: Direct download
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
