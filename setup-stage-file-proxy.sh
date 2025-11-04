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
            echo "Skipping configuration for this site (empty input)"
            VALIDATED_DOMAIN=""
            return 1  # Return 1 to indicate skip
        fi

        # Check input length
        if [[ ${#domain} -gt 2048 ]]; then
            echo "Error: Domain too long (max 2048 characters)"
            continue
        fi

        # Check for dangerous characters
        if [[ "$domain" =~ [\;\|\&\$\`\(\)\<\>\"\'] ]]; then
            echo "Error: Domain contains invalid characters (; | & $ \` ( ) < > \" ')"
            continue
        fi

        # Check for control characters
        if [[ "$domain" =~ [[:cntrl:]] ]]; then
            echo "Error: Domain contains control characters"
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
                printf "⚠️  Warning: Localhost pattern detected. Continue? (y/n): "
                read -r continue_localhost < /dev/tty
                if [[ ! "$continue_localhost" =~ ^[Yy] ]]; then
                    continue
                fi
            fi

            # Set global variable instead of echo
            VALIDATED_DOMAIN="$clean_domain"
            return 0
        else
            echo "❌ Error: Invalid domain format. Please try again."
            continue
        fi
    done
}

# Function to configure Stage File Proxy with new plugin structure
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
        echo "❌ Failed to set sfp_url"
        return 1
    fi

    # Configure sfp_mode (replaces old method)
    if ! wp option update sfp_mode "$mode" $url_flag --quiet 2>/dev/null; then
        echo "❌ Failed to set sfp_mode"
        return 1
    fi

    echo "✅ Configuration successful (URL: $domain, Mode: $mode)"
    return 0
}

setup_stage_file_proxy() {
    echo "=== Stage File Proxy Setup ==="
    echo ""

    # Check if WP CLI is available
    if ! command -v wp &> /dev/null; then
        echo "Error: WP CLI is not installed or not in PATH"
        echo "Please install WP CLI first: https://wp-cli.org/"
        return 1
    fi

    # Check if we're in a WordPress directory
    if ! wp core is-installed --quiet 2>/dev/null; then
        echo "Error: Not in a WordPress directory or WordPress is not installed"
        return 1
    fi

    # Check if the plugin exists, if not install it with enhanced error handling
    if ! wp plugin is-installed stage-file-proxy --quiet 2>/dev/null; then
        echo "📦 Stage File Proxy plugin not found. Installing..."

        # Create a temporary log for installation debugging
        local install_log="/tmp/wp_plugin_install_setup_$$.log"
        local install_success=false

        # Method 1: Try installing from GitHub release
        echo "    Attempting installation from GitHub release..."
        if wp plugin install https://github.com/manishsongirkar/stage-file-proxy/releases/download/101/stage-file-proxy.zip --quiet > "$install_log" 2>&1; then
            echo "✅ Plugin installed successfully from GitHub"
            install_success=true
        else
            echo "⚠️ GitHub installation failed, trying direct download method..."

            # Method 2: Try direct download and install
            echo "    Attempting direct download method..."
            local temp_plugin_file="/tmp/stage-file-proxy-setup-$$.zip"

            # Try downloading with curl first, then wget as fallback
            if command -v curl &>/dev/null; then
                if curl -L -o "$temp_plugin_file" "https://github.com/manishsongirkar/stage-file-proxy/releases/download/101/stage-file-proxy.zip" >> "$install_log" 2>&1; then
                    if wp plugin install "$temp_plugin_file" --quiet >> "$install_log" 2>&1; then
                        echo "✅ Plugin installed successfully via direct download"
                        install_success=true
                    fi
                    rm -f "$temp_plugin_file" 2>/dev/null
                fi
            elif command -v wget &>/dev/null; then
                if wget -O "$temp_plugin_file" "https://github.com/manishsongirkar/stage-file-proxy/releases/download/101/stage-file-proxy.zip" >> "$install_log" 2>&1; then
                    if wp plugin install "$temp_plugin_file" --quiet >> "$install_log" 2>&1; then
                        echo "✅ Plugin installed successfully via direct download"
                        install_success=true
                    fi
                    rm -f "$temp_plugin_file" 2>/dev/null
                fi
            fi
        fi        # Handle installation result
        if [[ "$install_success" == true ]]; then
            # Verify installation was actually successful
            if wp plugin is-installed stage-file-proxy --quiet 2>/dev/null; then
                echo "✅ Plugin installation verified"
            else
                echo "❌ Plugin installation verification failed"
                install_success=false
            fi
        fi

        if [[ "$install_success" == false ]]; then
            echo "❌ Failed to install plugin using all methods"
            echo "💡 Installation error details:"
            if [[ -f "$install_log" ]]; then
                # Use built-in bash features instead of external commands
                echo "   Last few lines from installation log:"
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
            echo "🔧 Manual installation options:"
            echo "   1. Download manually: https://github.com/manishsongirkar/stage-file-proxy/releases/download/101/stage-file-proxy.zip"
            echo "   2. Install via WP Admin: Plugins → Add New → Upload Plugin"
            echo "   3. Check internet connection and try again"
            echo "Please install the plugin manually and run this script again"
            return 1
        fi

        # Clean up installation log
        rm -f "$install_log" 2>/dev/null
    else
        echo "✅ Stage File Proxy plugin already installed"
    fi

    # Detect if this is a multisite installation
    local is_multisite
    local subdomain_install
    is_multisite=$(wp config get MULTISITE --quiet 2>/dev/null || echo "false")
    subdomain_install=$(wp config get SUBDOMAIN_INSTALL --quiet 2>/dev/null || echo "false")

    echo "WordPress Installation Type:"
    if [[ "$is_multisite" == "1" || "$is_multisite" == "true" ]]; then
        if [[ "$subdomain_install" == "1" || "$subdomain_install" == "true" ]]; then
            echo "✓ Multisite detected (subdomain configuration)"
        else
            echo "✓ Multisite detected (subdirectory configuration)"
        fi
        setup_multisite
    else
        echo "✓ Single site detected"
        setup_single_site
    fi
}

setup_single_site() {
    echo ""
    echo "=== Setting up for Single Site ==="

    # Check if plugin is already active, activate if needed
    if wp plugin is-active stage-file-proxy --quiet 2>/dev/null; then
        echo "✓ Plugin already active"
    else
        echo "📦 Activating Stage File Proxy plugin..."
        if wp plugin activate stage-file-proxy --quiet 2>/dev/null; then
            echo "✓ Plugin activated successfully"
        else
            echo "✗ Failed to activate plugin"
            return 1
        fi
    fi

    # Get source domain from user with sanitization
    echo ""
    echo "ℹ️  Note: Using new plugin structure with separate sfp_url and sfp_mode options."
    if get_validated_domain "Enter the production domain (e.g., example.com or https://example.com): "; then
        local source_domain="$VALIDATED_DOMAIN"

        # Configure the plugin with new structure
        echo ""
        echo "Configuring Stage File Proxy..."
        if configure_stage_file_proxy "$source_domain" "header"; then
            echo "✅ Plugin configured successfully"
        else
            echo "❌ Failed to configure plugin"
            return 1
        fi
    else
        echo "⚠️  Skipping Stage File Proxy configuration for this site"
    fi

    echo ""
    echo "=== Setup Complete ==="
    echo "Stage File Proxy is now active and configured!"
}

setup_multisite() {
    echo ""
    echo "=== Setting up for Multisite ==="

    # Activate the plugin network-wide
    echo "Activating Stage File Proxy plugin network-wide..."
    if wp plugin activate stage-file-proxy --network --quiet; then
        echo "✓ Plugin activated network-wide successfully"
    else
        echo "✗ Failed to activate plugin network-wide"
        return 1
    fi

    # Get list of all sites
    echo ""
    echo "Getting list of all sites in the network..."
    local sites
    sites=$(wp site list --field=url --quiet)

    if [[ -z "$sites" ]]; then
        echo "✗ No sites found in the network"
        return 1
    fi

    echo "Sites found:"
    echo "$sites" | nl -w2 -s'. '

    echo ""
    echo "ℹ️  Note: Using new plugin structure with separate sfp_url and sfp_mode options."
    echo "Now configuring each site..."
    echo ""

    # Configure each site
    local site_count=0
    while IFS= read -r site_url; do
        site_count=$((site_count + 1))
        echo "--- Configuring Site $site_count: $site_url ---"

        if get_validated_domain "Enter production domain for $site_url (press Enter to skip): "; then
            local source_domain="$VALIDATED_DOMAIN"

            if configure_stage_file_proxy "$source_domain" "header" "$site_url"; then
                echo "✅ $site_url configured"
            else
                echo "❌ Failed to configure site: $site_url"
            fi
        else
            echo "⚠️  Skipping $site_url"
        fi
    done <<< "$sites"

    echo "=== Multisite Setup Complete ==="
    echo "Stage File Proxy is now active and configured for all sites!"
}

# Function to display current configuration
show_stage_file_proxy_config() {
    echo "=== Current Stage File Proxy Configuration ==="

    local is_multisite
    is_multisite=$(wp config get MULTISITE --quiet 2>/dev/null || echo "false")

    if [[ "$is_multisite" == "1" || "$is_multisite" == "true" ]]; then
        echo "Multisite Configuration:"
        local sites
        sites=$(wp site list --field=url --quiet)
        while IFS= read -r site_url; do
            echo ""
            echo "Site: $site_url"

            # Get sfp_url and sfp_mode separately (new plugin structure)
            local sfp_url sfp_mode
            sfp_url=$(wp --url="$site_url" option get sfp_url --quiet 2>/dev/null || echo "Not set")
            sfp_mode=$(wp --url="$site_url" option get sfp_mode --quiet 2>/dev/null || echo "Not set")

            echo "  sfp_url: $sfp_url"
            echo "  sfp_mode: $sfp_mode"
        done <<< "$sites"
    else
        echo "Single Site Configuration:"

        # Get sfp_url and sfp_mode separately (new plugin structure)
        local sfp_url sfp_mode
        sfp_url=$(wp option get sfp_url --quiet 2>/dev/null || echo "Not set")
        sfp_mode=$(wp option get sfp_mode --quiet 2>/dev/null || echo "Not set")

        echo "sfp_url: $sfp_url"
        echo "sfp_mode: $sfp_mode"
    fi
}

# Function to quickly set all sites to the same domain (for multisite)
bulk_configure_multisite() {
    local is_multisite
    is_multisite=$(wp config get MULTISITE --quiet 2>/dev/null || echo "false")

    if [[ "$is_multisite" != "1" && "$is_multisite" != "true" ]]; then
        echo "This function is only for multisite installations"
        return 1
    fi

    echo "=== Bulk Configure All Sites ==="
    echo "ℹ️  Note: Using new plugin structure with separate sfp_url and sfp_mode options."
    if get_validated_domain "Enter the production domain to use for ALL sites (e.g., example.com): "; then
        local source_domain="$VALIDATED_DOMAIN"

        echo ""
        echo "Applying configuration to all sites..."
        echo ""

        local sites
        sites=$(wp site list --field=url --quiet)

        while IFS= read -r site_url; do
            echo "Configuring: $site_url"
            if configure_stage_file_proxy "$source_domain" "header" "$site_url"; then
                echo "✅ $site_url configured"
            else
                echo "❌ Failed to configure $site_url"
            fi
        done <<< "$sites"

        echo ""
        echo "✅ Bulk configuration complete!"
    else
        echo "⚠️  Configuration cancelled."
    fi
}

# Help function
show_help() {
    echo "Stage File Proxy Setup Functions (Compatible with new plugin v101+):"
    echo ""
    echo "setup_stage_file_proxy        - Main setup function (interactive)"
    echo "show_stage_file_proxy_config  - Display current configuration"
    echo "bulk_configure_multisite      - Set same domain for all sites (multisite only)"
    echo ""
    echo "Plugin Structure Changes:"
    echo "• OLD: JSON format with 'stage-file-proxy-settings' option"
    echo "• NEW: Separate 'sfp_url' and 'sfp_mode' options"
    echo "• 'source_domain' → 'sfp_url'"
    echo "• 'method' → 'sfp_mode' (default: 'header')"
    echo ""
    echo "Available Proxy Modes:"
    echo "• header     - HTTP redirect to remote files (fastest, default)"
    echo "• download   - Download and save files locally"
    echo "• photon     - Use Photon/Jetpack for image processing"
    echo "• local      - Use local fallback images if remote fails"
    echo "• lorempixel - Use placeholder service for missing images"
    echo ""
    echo "Usage Examples:"
    echo "  setup_stage_file_proxy"
    echo "  show_stage_file_proxy_config"
    echo "  bulk_configure_multisite"
}

# If script is run directly (not sourced), show help
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "This script contains functions for setting up Stage File Proxy."
    echo "Source this script to use the functions:"
    echo ""
    echo "  source setup-stage-file-proxy.sh"
    echo "  setup_stage_file_proxy"
    echo ""
    show_help
fi
