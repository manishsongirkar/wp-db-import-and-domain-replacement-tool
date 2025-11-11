#!/bin/bash

# ===============================================
# WordPress Local Site Links Display Function
# ===============================================
#
# Description:
#   A standalone function to display clickable terminal links for WordPress sites.
#   Automatically detects single site vs multisite installations and shows appropriate links.
#   This function can be used independently or sourced by other scripts.
#
# Features:
#   - Automatic WordPress installation detection (single-site or multisite)
#   - Intelligent WordPress root directory detection via wp-config.php
#   - WP-CLI integration with robust error handling
#   - Colored terminal output with clickable links
#   - Support for subdomain and subdirectory multisite configurations
#   - Network admin link generation for multisite installations
#
# Requirements:
#   - WP-CLI installed and accessible in PATH
#   - WordPress installation (wp-config.php present)
#   - Bash shell (minimum 4.0 recommended)
#   - Must be run from within a WordPress directory or subdirectory
#
# Usage:
#   1. As a standalone script:
#      bash show_local_site_links.sh
#
#   2. Source and call from another script:
#      source show_local_site_links.sh
#      show_local_site_links
#
#   3. Direct function call after sourcing:
#      show_local_site_links

# Get the directory where the script is located
# Handle both direct execution and sourcing scenarios
if [[ -n "${BASH_SOURCE[0]}" ]]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
else
    # Fallback for edge cases
    SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
fi

# ================================================================
# Load Module System (if not already loaded)
# ================================================================
# Check if modules are already loaded by parent script
if [[ -z "${WP_IMPORT_MODULES_LOADED:-}" ]]; then
    MODULE_LOADER="$SCRIPT_DIR/lib/module_loader.sh"
    if [[ ! -f "$MODULE_LOADER" ]]; then
        echo "❌ Error: Module loader not found at:"
        echo "   $MODULE_LOADER"
        echo "💡 Please ensure 'lib/module_loader.sh' exists and is readable."
        exit 1
    fi

    # Load module loader safely and silently
    if ! source "$MODULE_LOADER" >/dev/null 2>&1; then
        echo "❌ Failed to load module system."
        echo "Check: $MODULE_LOADER"
        echo "Error log saved to /tmp/wp_import_errors.log"
        exit 1
    fi

    # Load all modules silently
    if ! load_modules >/dev/null 2>&1; then
        echo "❌ Error: Failed to load core modules."
        exit 1
    fi
else
    # Modules already loaded by parent script, just ensure colors are available
    # Colors are automatically initialized by utils module
    :  # No-op command
fi

#
# Supported WordPress Types:
#   - Single-site installations
#   - Multisite subdomain networks
#   - Multisite subdirectory networks
#
# Output:
#   Displays formatted terminal output with clickable links to:
#   - WordPress frontend URLs
#   - WordPress admin areas
#   - Network admin (for multisite)
#
# Author: Manish Songirkar (@manishsongirkar)
# Repository: https://github.com/manishsongirkar/wp-db-import-and-domain-replacement-tool
#
# ===============================================

# 🌐 Function to display local site access links
# This function displays clickable terminal links for WordPress sites
# It automatically detects single site vs multisite and shows appropriate links
show_local_site_links() {
  # 🔍 Locate WordPress root by searching for wp-config.php
  local wp_root
  wp_root=$(pwd)
  while [[ "$wp_root" != "/" && ! -f "$wp_root/wp-config.php" ]]; do
    # Use bash built-in parameter expansion instead of dirname command
    wp_root="${wp_root%/*}"
    # Handle edge case where wp_root becomes empty (would happen at filesystem root)
    if [[ -z "$wp_root" ]]; then
      wp_root="/"
    fi
  done

  if [[ ! -f "$wp_root/wp-config.php" ]]; then
    printf "${RED}❌ WordPress root not found (wp-config.php missing).${RESET}\n"
    printf "${YELLOW}💡 Please run this from within a WordPress directory.${RESET}\n"
    return 1
  fi

  if ! cd "$wp_root"; then
    printf "${RED}❌ Failed to change directory to ${wp_root}.${RESET}\n"
    return 1
  fi

  # 🧠 Check WP-CLI availability with enhanced PATH
  # Use global WP_COMMAND if available, otherwise detect it
  if [[ -z "${WP_COMMAND:-}" ]]; then
    # Ensure we have a robust PATH that includes common WP-CLI installation locations
    export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:$PATH"
    WP_COMMAND=$(command -v wp)
    if [[ -z "$WP_COMMAND" ]]; then
      printf "${RED}❌ WP-CLI not found in PATH.${RESET}\n"
      printf "${YELLOW}💡 Please install WP-CLI to use this function.${RESET}\n"
      return 1
    fi
    # Export for use in execute_wp_cli (needed because execute_wp_cli runs in a subshell)
    export WP_COMMAND
  fi

  # 🧱 Verify WordPress installation integrity
  if ! execute_wp_cli core is-installed &>/dev/null; then
    printf "${RED}❌ No WordPress installation detected in this directory.${RESET}\n"
    return 1
  fi

  # 🧩 Detect WordPress installation type (single site vs multisite)
  local is_multisite="no"
  local blog_count site_count

  # Check if wp_blogs table exists and has multiple entries
  blog_count=$(execute_wp_cli db query "SELECT COUNT(*) FROM wp_blogs;" --skip-column-names --silent 2>/dev/null || echo "0")
  site_count=$(execute_wp_cli db query "SELECT COUNT(*) FROM wp_site;" --skip-column-names --silent 2>/dev/null || echo "0")

  # Check wp-config.php constants as fallback
  local multisite_config=""
  if [[ -f "wp-config.php" ]]; then
    if grep -q "define.*MULTISITE.*true" wp-config.php 2>/dev/null; then
      multisite_config="yes"
    elif grep -q "define.*('MULTISITE'.*true" wp-config.php 2>/dev/null; then
      multisite_config="yes"
    elif grep -q 'define.*("MULTISITE".*true' wp-config.php 2>/dev/null; then
      multisite_config="yes"
    fi
  fi

  # WP-CLI eval check
  local is_multisite_wp=""
  is_multisite_wp=$(execute_wp_cli eval 'echo is_multisite() ? "yes" : "no";' 2>/dev/null || echo "unknown")

  # Decision logic
  if [[ "$blog_count" -gt 1 ]] || [[ "$site_count" -gt 0 ]]; then
    is_multisite="yes"
  elif [[ "$multisite_config" == "yes" ]]; then
    is_multisite="yes"
  elif [[ "$is_multisite_wp" == "yes" ]]; then
    is_multisite="yes"
  fi

  # 🌐 Display the local site access links
  printf "\n"
  printf "================================================================\n"
  printf "${CYAN}${BOLD}🌐 LOCAL SITE ACCESS LINKS${RESET}\n"
  printf "================================================================\n\n"

  if [[ "$is_multisite" == "yes" ]]; then
    # Store current shell options
    local shell_options="$-"

    set +x +v

    printf "${GREEN}✅ Your WordPress Multisite is ready:${RESET}\n\n"

    # Get the current site URL to determine the local domain pattern
    local current_site_url
    current_site_url=$(execute_wp_cli option get siteurl 2>/dev/null || echo "")

    if [[ -n "$current_site_url" ]]; then
      # Extract base domain from current site URL
      local base_domain="$current_site_url"
      base_domain="${base_domain#http://}"
      base_domain="${base_domain#https://}"
      base_domain="${base_domain%/}"
      base_domain="${base_domain%%/*}"

      # Get all sites in the network
      local sites_data
      sites_data=$(execute_wp_cli site list --fields=blog_id,url --format=csv 2>/dev/null)

      if [[ -n "$sites_data" ]]; then
        # Detect main site using WordPress database structure
        local main_site_info main_site_id main_site_detected_url
        main_site_info=$(detect_main_site "yes" "$current_site_url")
        IFS='|' read -r main_site_id main_site_detected_url <<< "$main_site_info"

        # Process each site
        while IFS=, read -r blog_id site_url; do
          # Skip header line
          if [[ "$blog_id" == "blog_id" ]]; then
            continue
          fi

          # Skip empty lines
          if [[ -z "$blog_id" || -z "$site_url" ]]; then
            continue
          fi

          local protocol=""
          protocol=$(detect_protocol "$site_url")

          # Clean the site URL but preserve protocol preference
          local clean_site_url="$site_url"
          clean_site_url="${clean_site_url#http://}"
          clean_site_url="${clean_site_url#https://}"
          clean_site_url="${clean_site_url%/}"

          local clickable_url="${protocol}${clean_site_url}"

          # Mark main site
          if [[ "$blog_id" == "$main_site_id" ]]; then
            printf "  🏠 ${BOLD}Main Site (ID: %s):${RESET} \033]8;;%s\033\\%s\033]8;;\033\\" "$blog_id" "$clickable_url" "$clickable_url"
            printf "\n"
          else
            printf "  🌍 ${BOLD}Subsite   (ID: %s):${RESET} \033]8;;%s\033\\%s\033]8;;\033\\" "$blog_id" "$clickable_url" "$clickable_url"
            printf "\n"
          fi
        done <<< "$sites_data"
      else
        # Fallback if site list fails
        local fallback_url="$current_site_url"
        printf "  🏠 ${BOLD}Main Site:${RESET} \033]8;;%s\033\\%s\033]8;;\033\\\n" "$fallback_url" "$fallback_url"
      fi

      printf "\n${CYAN}💡 Network Admin:${RESET} Add ${YELLOW}/wp-admin/network/${RESET} to any of the above URLs\n"
    else
      printf "${YELLOW}⚠️ Could not detect site URLs. Please check your WordPress configuration.${RESET}\n"
    fi

    if [[ "$shell_options" == *x* ]]; then set -x; fi
    if [[ "$shell_options" == *v* ]]; then set -v; fi

  else
    printf "${GREEN}✅ Your WordPress Single Site is ready:${RESET}\n\n"

    # Get current site URL
    local site_url
    site_url=$(execute_wp_cli option get siteurl 2>/dev/null || echo "")

    if [[ -n "$site_url" ]]; then
      local protocol=""
      protocol=$(detect_protocol "$site_url")

      # Clean the domain but preserve protocol preference
      local clean_site_url="$site_url"
      clean_site_url="${clean_site_url#http://}"
      clean_site_url="${clean_site_url#https://}"
      clean_site_url="${clean_site_url%/}"

      local frontend_url="${protocol}${clean_site_url}"
      local admin_url="${protocol}${clean_site_url}/wp-admin"

      printf "  🏠 ${BOLD}Frontend:${RESET} \033]8;;%s\033\\%s\033]8;;\033\\" "$frontend_url" "$frontend_url"
      printf "\n"
      printf "  ⚙️  ${BOLD}Admin:${RESET}    \033]8;;%s\033\\%s\033]8;;\033\\" "$admin_url" "$admin_url"
      printf "\n"
    else
      printf "${YELLOW}⚠️ Could not detect site URL. Please check your WordPress configuration.${RESET}\n"
    fi
  fi

  printf "\n================================================================\n"
}

# Allow the script to be called directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    show_local_site_links "$@"
fi
