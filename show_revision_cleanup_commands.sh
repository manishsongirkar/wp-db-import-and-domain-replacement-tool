#!/bin/bash

# WordPress Database Revision Cleanup Commands Generator
# This script generates MySQL commands to remove post revisions

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
fi

show_revision_cleanup_commands() {
  printf "\n"
  printf "================================================================\n"
  printf "${CYAN}${BOLD}🧹 MYSQL COMMANDS FOR REVISION CLEANUP${RESET}\n"
  printf "================================================================\n\n"

  # Check if we're in a WordPress directory
  if [ ! -f "wp-config.php" ]; then
    printf "${RED}❌ Error: wp-config.php not found in current directory${RESET}\n"
    printf "${YELLOW}💡 Please navigate to your WordPress root directory and run this script${RESET}\n"
    return 1
  fi

  # Get table prefix from wp-config.php
  local table_prefix
  table_prefix=$(grep -E "^\\\$table_prefix\s*=" wp-config.php | cut -d"'" -f2 2>/dev/null)
  if [ -z "$table_prefix" ]; then
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

          echo "DELETE FROM \`${site_prefix}postmeta\` WHERE \`post_id\` in (SELECT ID FROM \`${site_prefix}posts\` WHERE \`post_type\` = 'revision');"
          echo "DELETE FROM \`${site_prefix}posts\` WHERE \`post_type\` = 'revision';"

          echo
        done <<< "$blog_ids"

        printf "\n================================================================\n"
        echo

        return
      fi
    fi

    # Method 2: Check WordPress multisite function
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
    # No WP-CLI fallback
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

# Function to check if revisions need cleanup and show commands conditionally
show_revision_cleanup_if_needed() {
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

# If script is run directly, show commands
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  show_revision_cleanup_commands
fi
