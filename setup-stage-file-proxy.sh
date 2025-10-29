#!/bin/bash

# Stage File Proxy Setup Function
# This function activates and configures the Stage File Proxy plugin for WordPress
# Supports both single site and multisite installations

# Function to sanitize and validate domain input
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

    # Remove leading/trailing whitespace
    clean_domain=$(echo "$input" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

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

    # Validate URL format more thoroughly
    if ! [[ "$clean_domain" =~ ^https?://[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?)*([:]([0-9]{1,5}))?(/.*)?$ ]]; then
        return 1
    fi

    # Additional security check: ensure no multiple protocols
    if [[ $(echo "$clean_domain" | grep -o "://" | wc -l) -gt 1 ]]; then
        return 1
    fi

    # Return the sanitized domain
    echo "$clean_domain"
    return 0
}

# Function to get and validate domain input interactively
get_validated_domain() {
    local prompt="$1"
    local domain
    local clean_domain

    while true; do
        printf "%s" "$prompt"
        read -r domain < /dev/tty

        # Remove leading/trailing whitespace first
        domain=$(echo "$domain" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

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

        # Auto-add https:// protocol if missing (no user prompt)
        if [[ ! "$domain" =~ ^https?:// ]]; then
            echo "Auto-adding https:// protocol..."
            domain="https://$domain"
        fi

        # Use sanitize function for final validation (without interactive parts)
        clean_domain=$(sanitize_domain "$domain")
        if [[ $? -eq 0 ]]; then
            # Check for localhost patterns
            if [[ "$clean_domain" =~ (localhost|127\.0\.0\.1|0\.0\.0\.0) ]]; then
                echo "Warning: Detected localhost pattern. Are you sure this is correct for production?"
                printf "Continue with this domain? (y/n): "
                read -r continue_localhost < /dev/tty
                if [[ ! "$continue_localhost" =~ ^[Yy] ]]; then
                    continue
                fi
            fi

            # Set global variable instead of echo
            VALIDATED_DOMAIN="$clean_domain"
            return 0
        else
            echo "Error: Invalid URL format. Please enter a valid domain like https://example.com"
            continue
        fi
    done
}

# Function to safely escape JSON values
escape_json() {
    local input="$1"
    # Escape backslashes, quotes, and control characters for JSON
    echo "$input" | sed 's/\\/\\\\/g; s/"/\\"/g; s/\t/\\t/g; s/\n/\\n/g; s/\r/\\r/g'
}

# Function to create safe JSON settings
create_safe_json_settings() {
    local domain="$1"
    local method="$2"

    # Escape the domain for JSON
    local escaped_domain
    local escaped_method
    escaped_domain=$(escape_json "$domain")
    escaped_method=$(escape_json "$method")

    # Create JSON with proper escaping
    echo "{\"source_domain\":\"$escaped_domain\",\"method\":\"$escaped_method\"}"
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

    # Check if the plugin exists
    if ! wp plugin is-installed stage-file-proxy --quiet 2>/dev/null; then
        echo "Error: Stage File Proxy plugin is not installed"
        echo "Please install the plugin first"
        return 1
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

    # Activate the plugin
    echo "Activating Stage File Proxy plugin..."
    if wp plugin activate stage-file-proxy --quiet; then
        echo "✓ Plugin activated successfully"
    else
        echo "✗ Failed to activate plugin"
        return 1
    fi

    # Get source domain from user with sanitization
    echo ""
    if get_validated_domain "Enter the production domain: "; then
        local source_domain="$VALIDATED_DOMAIN"

        # Configure the plugin
        echo "Configuring Stage File Proxy..."
        local settings
        settings=$(create_safe_json_settings "$source_domain" "redirect")

        if wp option update stage-file-proxy-settings "$settings" --format=json --quiet; then
            echo "✓ Plugin configured successfully"
            echo "  Source Domain: $source_domain"
            echo "  Method: redirect"
        else
            echo "✗ Failed to configure plugin"
            return 1
        fi
    else
        echo "⚠ Skipping Stage File Proxy configuration for this site"
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
    echo "Now we'll configure each site individually..."
    echo ""

    # Configure each site
    local site_count=0
    while IFS= read -r site_url; do
        site_count=$((site_count + 1))
        echo "--- Configuring Site $site_count: $site_url ---"

        if get_validated_domain "Enter production domain for $site_url (press Enter to skip): "; then
            local source_domain="$VALIDATED_DOMAIN"
            local settings
            settings=$(create_safe_json_settings "$source_domain" "redirect")

            if wp --url="$site_url" option update stage-file-proxy-settings "$settings" --format=json --quiet; then
                echo "✓ Site configured successfully"
                echo "  URL: $site_url"
                echo "  Source Domain: $source_domain"
                echo "  Method: redirect"
            else
                echo "✗ Failed to configure site: $site_url"
            fi
        else
            echo "⚠ Skipping configuration for $site_url"
        fi
        echo ""
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
            local config
            config=$(wp --url="$site_url" option get stage-file-proxy-settings --format=json --quiet 2>/dev/null)
            if [[ -n "$config" && "$config" != "false" ]]; then
                echo "  Settings: $config"
            else
                echo "  Settings: Not configured"
            fi
        done <<< "$sites"
    else
        echo "Single Site Configuration:"
        local config
        config=$(wp option get stage-file-proxy-settings --format=json --quiet 2>/dev/null)
        if [[ -n "$config" && "$config" != "false" ]]; then
            echo "Settings: $config"
        else
            echo "Settings: Not configured"
        fi
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
    if get_validated_domain "Enter the production domain to use for ALL sites: "; then
        local source_domain="$VALIDATED_DOMAIN"
        local settings
        settings=$(create_safe_json_settings "$source_domain" "redirect")

        echo "Applying configuration to all sites..."
        local sites
        sites=$(wp site list --field=url --quiet)

        while IFS= read -r site_url; do
            echo "Configuring: $site_url"
            if wp --url="$site_url" option update stage-file-proxy-settings "$settings" --format=json --quiet; then
                echo "✓ $site_url configured"
            else
                echo "✗ Failed to configure $site_url"
            fi
        done <<< "$sites"

        echo "Bulk configuration complete!"
    else
        echo "⚠ Bulk configuration cancelled (no domain provided)"
    fi
}

# Help function
show_help() {
    echo "Stage File Proxy Setup Functions:"
    echo ""
    echo "setup_stage_file_proxy        - Main setup function (interactive)"
    echo "show_stage_file_proxy_config  - Display current configuration"
    echo "bulk_configure_multisite      - Set same domain for all sites (multisite only)"
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
