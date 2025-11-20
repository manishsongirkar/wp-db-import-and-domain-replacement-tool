#!/usr/bin/env bash

# ================================================================
# WordPress Revision Cleanup Utilities Module
# ================================================================
#
# Description:
#   This module provides functions for generating MySQL commands to clean up
#   WordPress post revisions from both single-site and multisite installations.
#   It helps reduce database size by targeting the 'revision' post type in
#   _posts and _postmeta tables.
#
# Features:
#   - Automatic detection of single-site vs multisite installations using WP-CLI
#   - Dynamic table prefix detection from wp-config.php
#   - Accurate command generation for multisite subsites when site list is available
#
# Functions provided:
# - show_revision_cleanup_commands        Generate MySQL cleanup commands
# - show_utilities_revision_cleanup_if_needed Conditional cleanup command display
#
# Dependencies:
# - find_wordpress_root (from core/utils.sh)
# - get_wp_table_prefix (from core/utils.sh)
# - execute_wp_cli (from core/utils.sh)
# - Color variables (CYAN, RED, YELLOW, GREEN, BOLD, RESET)
#
# ================================================================

# ===============================================
# Show Revision Cleanup Commands
# ===============================================
#
# Description: Generates and displays the necessary MySQL DELETE commands to remove all WordPress post revisions.
#
# Parameters:
#	- None (relies on current directory being within the WordPress installation).
#
# Returns:
#	- Prints formatted MySQL commands and instructions to stdout.
#	- Returns 1 if wp-config.php is not found.
#
# Behavior:
#	- Detects table prefix.
#	- Uses WP-CLI's `wp site list` and `wp eval 'is_multisite()'` for robust multisite detection.
#	- Generates separate DELETE commands for each detected subsite's posts and postmeta tables.
#
show_revision_cleanup_commands() {
  printf "\n"
  printf "================================================================\n"
  printf "${CYAN}${BOLD}🧹 MYSQL COMMANDS FOR REVISION CLEANUP${RESET}\n"
  printf "================================================================\n\n"

  # Check if we're in a WordPress directory using centralized validation
  local wp_root
  wp_root=$(find_wordpress_root)
  if [[ $? -ne 0 ]]; then
    printf "${RED}❌ Error: wp-config.php not found in current directory${RESET}\n"
    printf "${YELLOW}💡 Please navigate to your WordPress root directory and run this script${RESET}\n"
    return 1
  fi

  # Get table prefix from wp-config.php using centralized function
  local table_prefix
  table_prefix=$(get_wp_table_prefix)
  if [[ $? -ne 0 ]]; then
    table_prefix="wp_"
  fi

  printf "${YELLOW}💡 These commands will permanently delete ALL post revisions from your database.${RESET}\n"
  printf "${YELLOW}💡 Copy and paste these commands into phpMyAdmin → SQL tab or MySQL console.${RESET}\n\n"

  # Try to detect multisite using multiple methods
  if command -v wp >/dev/null 2>&1; then
    # Method 1: Try to get site list first (most reliable for existing multisites)
    local blog_ids
    blog_ids=$(wp site list --field=blog_id 2>/dev/null)

    if [ $? -eq 0 ] && [ -n "$blog_ids" ]; then
      local site_count
      site_count=$(echo "$blog_ids" | wc -l | tr -d ' ')

      if [ "$site_count" -gt 1 ] || [ "$blog_ids" != "1" ]; then
        # Multiple sites detected OR site list contains non-1 blog IDs
        printf "${GREEN}✅ WordPress Multisite detected (${site_count} sites)${RESET}\n\n"
        printf "${YELLOW}🗂️  MySQL Commands for Multisite:${RESET}\n\n"

        while IFS= read -r blog_id; do
          if [ -z "$blog_id" ]; then continue; fi

          if [ "$blog_id" = "1" ]; then
            site_prefix="${table_prefix}"
            printf "${CYAN}-- Blog ID %s (Main Site) - Tables: %sposts, %spostmeta${RESET}\n" "$blog_id" "$site_prefix" "$site_prefix"
          else
            site_prefix="${table_prefix}${blog_id}_"
            printf "${CYAN}-- Blog ID %s (Subsite) - Tables: %sposts, %spostmeta${RESET}\n" "$blog_id" "$site_prefix" "$site_prefix"
          fi

          # Use backticks for table names for compatibility
          echo "DELETE FROM \`${site_prefix}postmeta\` WHERE \`post_id\` in (SELECT ID FROM \`${site_prefix}posts\` WHERE \`post_type\` = 'revision');"
          echo "DELETE FROM \`${site_prefix}posts\` WHERE \`post_type\` = 'revision';"

          echo
        done <<< "$blog_ids"

        printf "\n================================================================\n"
        echo

        return
      fi
    fi

    # Method 2: Check WordPress multisite function (Fallback for incomplete site list)
    local is_multisite_check
    is_multisite_check=$(wp eval "echo is_multisite() ? 'yes' : 'no';" 2>/dev/null)

    if [ "$is_multisite_check" = "yes" ]; then
      printf "${GREEN}✅ WordPress Multisite detected (function fallback)${RESET}\n\n"
      printf "${YELLOW}⚠️  Could not get complete site list via WP-CLI${RESET}\n"
      printf "${YELLOW}💡 Generating basic multisite commands${RESET}\n\n"

      printf "${YELLOW}🗂️  MySQL Commands for Multisite (Main Site):${RESET}\n\n"
      echo "DELETE FROM \`${table_prefix}postmeta\` WHERE \`post_id\` in (SELECT ID FROM \`${table_prefix}posts\` WHERE \`post_type\` = 'revision');"
      echo "DELETE FROM \`${table_prefix}posts\` WHERE \`post_type\` = 'revision';"

      printf "${YELLOW}💡 For subsites, manually replace table prefix with ${table_prefix}N_ (where N is blog_id)${RESET}\n"
      printf "${YELLOW}💡 Example for blog_id 2: ${table_prefix}2_posts, ${table_prefix}2_postmeta${RESET}\n\n"

      echo

      printf "\n================================================================\n"
      echo
      return
    fi

    # Method 3: Fallback to single site
    printf "${GREEN}✅ WordPress Single Site detected${RESET}\n\n"
    printf "${CYAN}📊 Site Information:${RESET}\n"
    printf "   Blog ID: 1 (Main Site) - Tables: %sposts, %spostmeta\n\n" "$table_prefix" "$table_prefix"
    printf "${YELLOW}🗂️  MySQL Commands for Single Site:${RESET}\n\n"
    echo "DELETE FROM \`${table_prefix}postmeta\` WHERE \`post_id\` in (SELECT ID FROM \`${table_prefix}posts\` WHERE \`post_type\` = 'revision');"
    echo "DELETE FROM \`${table_prefix}posts\` WHERE \`post_type\` = 'revision';"

  else
    # No WP-CLI fallback (Hard fallback to single site assumption)
    printf "${YELLOW}⚠️  WP-CLI not available, generating basic commands${RESET}\n\n"
    printf "${CYAN}📊 Assuming Single Site Configuration:${RESET}\n"
    printf "   Blog ID: 1 (Main Site) - Tables: %sposts, %spostmeta\n\n" "$table_prefix" "$table_prefix"
    printf "${YELLOW}🗂️  MySQL Commands:${RESET}\n\n"
    echo "DELETE FROM \`${table_prefix}postmeta\` WHERE \`post_id\` in (SELECT ID FROM \`${table_prefix}posts\` WHERE \`post_type\` = 'revision');"
    echo "DELETE FROM \`${table_prefix}posts\` WHERE \`post_type\` = 'revision';"
    printf "\n${YELLOW}💡 If this is a multisite, manually adjust table prefixes${RESET}\n"
  fi

  printf "\n================================================================\n"
  echo
}

# ===============================================
# Show Utilities Revision Cleanup If Needed
# ===============================================
#
# Description: Checks for `wp-config.php` and conditionally calls the main command generator.
#
# Parameters:
#	- $1: Optional. Path to the WordPress root directory.
#
# Returns:
#	- Prints generated commands or an error message.
#	- Returns 1 if `wp-config.php` is not found in the target directory.
#
# Behavior:
#	- Temporarily changes directory if a path is provided.
#	- This function serves as the primary entry point for displaying cleanup commands externally.
#
show_utilities_revision_cleanup_if_needed() {
  local wp_path="${1:-.}"

  if [ "$wp_path" != "." ]; then
    if [ ! -d "$wp_path" ]; then
      printf "${RED}❌ Error: Directory '$wp_path' not found${RESET}\n"
      return 1
    fi
    local original_dir=$(pwd)
    cd "$wp_path" || return 1
  fi

  if [ ! -f "wp-config.php" ]; then
    printf "${RED}❌ Error: wp-config.php not found${RESET}\n"
    if [ "$wp_path" != "." ]; then
      cd "$original_dir"
    fi
    return 1
  fi

  show_revision_cleanup_commands

  if [ "$wp_path" != "." ]; then
    cd "$original_dir"
  fi
}

# Export functions for external use
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    {
        export -f show_revision_cleanup_commands
        export -f show_utilities_revision_cleanup_if_needed
    } >/dev/null 2>&1
fi
