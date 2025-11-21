#!/usr/bin/env bash

# ================================================================
# Domain Manager Module
# ================================================================
#
# Description:
#   Handles domain input, configuration, and validation.
#
# ================================================================

# ===============================================
# Get Domains
# ===============================================
#
# Description: Prompts the user for old and new domains, or retrieves them from config.
#              Handles overrides and updates configuration.
#
# Parameters:
#   - $1: Path to the configuration file.
#
# Returns:
#   - Sets global variables `search_domain` and `replace_domain`.
#
get_domains() {
    local config_path="$1"
    local domain_override

    # Get OLD (production/source) domain - from config or prompt with override option
    while true; do
        if [[ -n "${CONFIG_OLD_DOMAIN:-}" ]]; then
            search_domain="$CONFIG_OLD_DOMAIN"
            printf "🌍 OLD (production) domain: ${GREEN}%s${RESET} (from config)\n" "$search_domain"
            pause_script_timer
            printf "   ${CYAN}Press Enter to use this domain, or type a new domain to override:${RESET} "
            read -r domain_override
            resume_script_timer

            if [[ -n "$domain_override" ]]; then
                search_domain="$domain_override"
                printf "   ${YELLOW}✏️  Using override domain: %s${RESET}\n" "$search_domain"
                # Update config with the new domain for future use
                update_config_general "$config_path" "old_domain" "$search_domain" 2>/dev/null || true
            fi
            break
        else
            pause_script_timer
            printf "🌍 Enter the OLD (production) domain to search for: "
            read -r search_domain
            resume_script_timer

            if [[ -n "$search_domain" ]]; then
                break
            else
                printf "${YELLOW}⚠️  Production domain is required. Please enter a value.${RESET}\n"
            fi
        fi
    done

    # Get NEW (local/destination) domain - from config or prompt with override option
    while true; do
        if [[ -n "${CONFIG_NEW_DOMAIN:-}" ]]; then
            replace_domain="$CONFIG_NEW_DOMAIN"
            printf "🏠 NEW (local) domain: ${GREEN}%s${RESET} (from config)\n" "$replace_domain"
            pause_script_timer
            printf "   ${CYAN}Press Enter to use this domain, or type a new domain to override:${RESET} "
            read -r domain_override
            resume_script_timer

            if [[ -n "$domain_override" ]]; then
                replace_domain="$domain_override"
                printf "   ${YELLOW}✏️  Using override domain: %s${RESET}\n" "$replace_domain"
                # Update config with the new domain for future use
                update_config_general "$config_path" "new_domain" "$replace_domain" 2>/dev/null || true
            fi
            break
        else
            pause_script_timer
            printf "🏠 Enter the NEW (local) domain/base URL to replace with: "
            read -r replace_domain
            resume_script_timer

            if [[ -n "$replace_domain" ]]; then
                break
            else
                printf "${YELLOW}⚠️  Local domain is required. Please enter a value.${RESET}\n"
            fi
        fi
    done

    # Sanitize domain inputs (remove protocols and trailing slashes)
    # Apply sanitization to both domains using centralized function
    local original_search_domain="$search_domain"
    local original_replace_domain="$replace_domain"

    # sanitize_domain is in utils.sh (must be loaded)
    search_domain=$(sanitize_domain "$search_domain")
    replace_domain=$(sanitize_domain "$replace_domain")

    # Show what was cleaned up if changes were made
    if [[ "$original_search_domain" != "$search_domain" ]]; then
        printf "${YELLOW}🧹 Cleaned search domain: '%s' → '%s'${RESET}\n" "$original_search_domain" "$search_domain"
    fi
    if [[ "$original_replace_domain" != "$replace_domain" ]]; then
        printf "${YELLOW}🧹 Cleaned replace domain: '%s' → '%s'${RESET}\n" "$original_replace_domain" "$replace_domain"
    fi

    # Export them to ensure they are available globally
    export search_domain
    export replace_domain
}

# ===============================================
# Validate Domains
# ===============================================
#
# Description: Validates the selected domains against the database and configuration.
#
# Parameters:
#   - $1: WordPress root directory.
#   - $2: Config path.
#
# Returns:
#   - 0 if valid, 1 if invalid/cancelled.
#   - Updates `search_domain` if validation suggests a change.
#
validate_domains() {
    local wp_root="$1"
    local config_path="$2"

    printf "${CYAN}🔍 Validating domain configuration...${RESET}\n"
    local detected_domain

    # Use detect_database_domain from integration.sh (must be loaded)
    if detected_domain=$(detect_database_domain "$wp_root"); then
        printf "${GREEN}✅ Detected domain in database: ${YELLOW}%s${RESET}\n" "$detected_domain"

        # Validate against config if it exists
        if [[ -f "$config_path" ]]; then
            local validated_domain
            # Use validate_config_domains from integration.sh
            if validated_domain=$(validate_config_domains "$config_path" "$detected_domain"); then
                if [[ -n "$validated_domain" && "$validated_domain" != "$detected_domain" ]]; then
                    # User chose to use config domain instead
                    search_domain="$validated_domain"
                    printf "${CYAN}🔄 Updated search domain to: ${YELLOW}%s${RESET}\n" "$search_domain"
                fi
            else
                # Validation failed, user cancelled or needs to fix config
                printf "${RED}❌ Domain validation failed. Please resolve the issue and try again.${RESET}\n"
                return 1
            fi
        fi
    else
        printf "${YELLOW}⚠️  Could not detect domain from database. Proceeding with provided domain.${RESET}\n"
    fi

    return 0
}

# Export functions
export -f get_domains
export -f validate_domains
