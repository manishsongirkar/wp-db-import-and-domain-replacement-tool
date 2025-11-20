#!/usr/bin/env bash

# ================================================================
# WordPress Site Links Utilities Module
# ================================================================
#
# Description:
#   This module provides functions for displaying clickable terminal links
#   for WordPress sites, supporting both single-site and multisite installations.
#   It enhances user experience by providing quick access to the frontend and admin interfaces.
#
# Features:
#   - Automatic WordPress installation detection (single-site or multisite)
#   - Intelligent WordPress root directory detection via wp-config.php
#   - WP-CLI integration for robust site discovery
#   - Colored terminal output with clickable links (using ANSI escape codes for linking)
#
# Functions provided:
# - show_local_site_links    Display clickable terminal links for WordPress sites
#
# Dependencies:
# - find_wordpress_root (from core/utils.sh)
# - check_wpcli_availability (from core/utils.sh)
# - validate_wordpress_installation (from core/utils.sh)
# - detect_wordpress_installation_type (from core/detection.sh)
# - detect_main_site (from core/utils.sh)
# - detect_protocol (from core/utils.sh)
# - execute_wp_cli (from core/utils.sh)
# - Color variables (RED, GREEN, CYAN, YELLOW, BOLD, RESET)
#
# ================================================================

# ===============================================
# Show Local Site Links
# ===============================================
#
# Description: Displays clickable terminal links for the WordPress installation.
#
# Parameters:
#	- None (relies on current directory being within the WordPress installation).
#
# Returns:
#	- Prints formatted, clickable URLs for the frontend and admin interfaces (or all subsites for multisite).
#	- Returns 1 if WordPress root is not found or WP-CLI checks fail.
#
# Behavior:
#	- Detects installation type (single vs multisite).
#	- For single sites, provides Frontend and Admin links.
#	- For multisite, iterates over all sites discovered via `wp site list`, providing links for each subsite and the main site.
#	- Uses ANSI OSC 8 escape codes (\033]8;;) for clickable links.
#
show_local_site_links() {
  # 🔍 Locate WordPress root by searching for wp-config.php
  local wp_root
  wp_root=$(find_wordpress_root)
  if [[ $? -ne 0 ]]; then
    printf "${RED}❌ WordPress root not found (wp-config.php missing).${RESET}\n"
    printf "${YELLOW}💡 Please run this from within a WordPress directory.${RESET}\n"
    return 1
  fi

  if ! cd "$wp_root"; then
    printf "${RED}❌ Failed to change directory to ${wp_root}.${RESET}\n"
    return 1
  fi

  # 🧠 Check WP-CLI availability with enhanced PATH
  if ! check_wpcli_availability; then
    return 1
  fi

  # 🧱 Verify WordPress installation integrity
  if ! validate_wordpress_installation; then
    return 1
  fi

  # 🧩 Detect WordPress installation type using centralized function
  local wp_detect_output
  wp_detect_output=$(detect_wordpress_installation_type "$wp_root" "false")
  IFS='|' read -r installation_type multisite_type network_flag blog_count site_count detection_method <<< "$wp_detect_output"
  local is_multisite="no"
  if [[ "$installation_type" == "multisite" ]]; then
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

    # Disable command tracing temporarily to prevent cluttering output with WP-CLI calls
    # Note: Using explicit set +x +v requires careful restoration below
    set +x +v

    printf "${GREEN}✅ Your WordPress Multisite is ready (${blog_count} sites):${RESET}\n\n"

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

          # Use ANSI OSC 8 escape codes for clickable links
          local link_start='\033]8;;'
          local link_end='\033\\'

          # Mark main site
          if [[ "$blog_id" == "$main_site_id" ]]; then
            printf "  🏠 ${BOLD}Main Site (ID: %s):${RESET} ${link_start}%s${link_end}%s${link_start}${link_end}" "$blog_id" "$clickable_url" "$clickable_url"
            printf "\n"
          else
            printf "  🌍 ${BOLD}Subsite   (ID: %s):${RESET} ${link_start}%s${link_end}%s${link_start}${link_end}" "$blog_id" "$clickable_url" "$clickable_url"
            printf "\n"
          fi
        done <<< "$sites_data"
      else
        # Fallback if site list fails
        local fallback_url="$current_site_url"
        local link_start='\033]8;;'
        local link_end='\033\\'
        printf "  🏠 ${BOLD}Main Site:${RESET} ${link_start}%s${link_end}%s${link_start}${link_end}\n" "$fallback_url" "$fallback_url"
      fi

      printf "\n${CYAN}💡 Network Admin:${RESET} Add ${YELLOW}/wp-admin/network/${RESET} to any of the above URLs\n"
    else
      printf "${YELLOW}⚠️  Could not detect site URLs. Please check your WordPress configuration.${RESET}\n"
    fi

    # Restore shell options if they were originally set
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

      local link_start='\033]8;;'
      local link_end='\033\\'

      printf "  🏠 ${BOLD}Frontend:${RESET} ${link_start}%s${link_end}%s${link_start}${link_end}\n" "$frontend_url" "$frontend_url"
      printf "  ⚙️  ${BOLD}Admin:${RESET}    ${link_start}%s${link_end}%s${link_start}${link_end}\n" "$admin_url" "$admin_url"
      printf "\n"
    else
      printf "${YELLOW}⚠️  Could not detect site URL. Please check your WordPress configuration.${RESET}\n"
    fi
  fi

  printf "\n================================================================\n"
}

# Export functions for external use
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    {
        export -f show_local_site_links
    } >/dev/null 2>&1
fi
