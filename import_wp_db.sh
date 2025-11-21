#!/usr/bin/env bash

# ================================================================
# WordPress Database Import & Domain Replacement Tool
# ================================================================
#
# Version: See VERSION file
#
# Description:
#   A robust bash utility for performing WordPress database imports and domain/URL
#   replacements, commonly needed for migrating environments (e.g., production to local/staging).
#   It efficiently handles single-site and multi-domain WordPress Multisite setups.
#
# Features:
#   - Automatic WordPress installation detection (single-site or multisite)
#   - **High-Speed Bulk Post Revision Cleanup (via xargs)**
#   - **MySQL Commands for Manual Revision Cleanup (when automatic cleanup is skipped)**
#   - Intelligent domain sanitization (removes protocols, trailing slashes)
#   - **Robust Multi-Domain/Per-Site Mapping for Multisite**
#   - Two-pass search-replace (standard + serialized data)
#   - Cache and transient clearing via WP-CLI
#   - Dry-run mode for testing replacements
#   - MySQL command generation for network domain tables (critical for multisite completion)
#   - Comprehensive error handling and logging
#   - Colored terminal output with clear progress indicators
#
# Requirements:
#   - WP-CLI installed and accessible in PATH
#   - WordPress installation (wp-config.php present)
#   - MySQL/MariaDB database
#   - Bash shell (minimum 4.0 recommended for best performance)
#   - macOS/Linux environment
#
# Usage:
#   1. Place SQL file in the same directory as this script.
#   2. Navigate to WordPress root directory or subdirectory.
#   3. Source this script: source import_wp_db.sh
#   4. Run the function: import_wp_db
#   5. Follow the interactive prompts.
#
# Additional Functions (loaded via lib/utilities/ modules):
#   show_local_site_links - Display clickable links to local WordPress sites
#     Usage: show_local_site_links
#     Requirements: Must be run from within a WordPress directory with WP-CLI installed
#     Note: Function is now loaded from lib/utilities/site_links.sh via module loader
#
#   show_revision_cleanup_commands - Generate MySQL commands for manual revision cleanup
#     Usage: show_revision_cleanup_commands [single|multisite|test|test-multisite|test-subdirectory]
#     Requirements: Must be run from within a WordPress directory with WP-CLI installed
#     Note: Function is now loaded from lib/utilities/revision_cleanup.sh via module loader
#
#   setup_stage_file_proxy - Interactive setup for Stage File Proxy plugin
#     Usage: setup_stage_file_proxy
#     Requirements: Must be run from within a WordPress directory with WP-CLI installed
#     Note: Function is now loaded from lib/utilities/stage_file_proxy.sh via module loader
#
#   show_revision_cleanup_if_needed - Helper function that conditionally shows revision cleanup commands
#     Usage: show_revision_cleanup_if_needed (called automatically during import)
#     Requirements: Variables cleanup_revisions and is_multisite should be set
#     Note: Available globally after sourcing this script
#
# Supported WordPress Types:
#   - Single-site installations
#   - Multisite subdomain networks
#   - Multisite subdirectory networks (including multi-domain to single-domain migrations)
#
# File Structure:
#   - Creates temporary log files in /tmp/ for debugging (uses PID to prevent collision)
#   - Automatically cleans up temporary files on exit
#   - Logs all WP-CLI operations for troubleshooting
#
# Security:
#   - Uses absolute paths to prevent directory traversal
#   - Validates all user inputs
#   - Sanitizes domain inputs
#   - Uses temporary files with process-specific names
#
# Author: Manish Songirkar (@manishsongirkar)
# Repository: https://github.com/manishsongirkar/wp-db-import-and-domain-replacement-tool
#
# ================================================================

# Get the directory where the script is located
# Handle both direct execution and sourcing scenarios
if [[ -n "${BASH_SOURCE[0]}" ]]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
else
    # Fallback for edge cases
    SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
fi

# ================================================================
# Load Module System
# ================================================================
MODULE_LOADER="$SCRIPT_DIR/lib/module_loader.sh"
if [[ ! -f "$MODULE_LOADER" ]]; then
    echo "${RED}❌ Error: Module loader not found at:$RESET"
    echo "   $MODULE_LOADER"
    echo "💡 Please ensure 'lib/module_loader.sh' exists and is readable."
    exit 1
fi

# Load module loader safely and silently
if ! source "$MODULE_LOADER" >/dev/null 2>&1; then
    echo "${RED}❌ Failed to load module system.${RESET}"
    echo "Check: $MODULE_LOADER"
    echo "Error log saved to /tmp/wp_import_errors.log"
    exit 1
fi

# Load all modules silently
if ! load_modules >/dev/null 2>&1; then
    echo "${RED}❌ Error: Failed to load core modules.${RESET}"
    exit 1
fi

# ===============================================
# Functions now loaded via module system
# ===============================================
# All utility functions (show_local_site_links, show_revision_cleanup_commands,
# and stage file proxy functions) are now loaded automatically through
# the module loader system in lib/

# ===============================================
# Define helper function for conditional revision cleanup during import
# ===============================================
#
# Description: Helper function that conditionally calls `show_revision_cleanup_commands`
#              (which generates manual MySQL commands) only if the user opted to
#              skip the automatic revision cleanup step (`cleanup_revisions` is not 'Y'/'y').
#
# Parameters:
#   - None (Relies on the global variable `cleanup_revisions`).
#
# Returns:
#   - Prints manual MySQL commands to stdout if the condition is met.
#
# Behavior:
#   - Calls `show_revision_cleanup_commands` (from `revision_cleanup.sh`)
#     which must be loaded via the module system.
#
show_revision_cleanup_if_needed() {
    # Check if cleanup_revisions variable exists and is not Y/y
    if [[ "${cleanup_revisions:-}" != [Yy]* ]]; then
        # Call the revision cleanup function (now loaded via module system)
        show_revision_cleanup_commands
        printf "\n"
    fi
}

# ===============================================
# Define function to show revision cleanup commands at the end of the process
# ===============================================
#
# Description: Conditionally displays manual MySQL commands for revision cleanup
#              at the very end of the import process. This acts as a final fallback
#              and reminder.
#
# Parameters:
#   - None (Relies on global flags `revision_cleanup_declined` and `revisions_remain_after_cleanup`).
#
# Returns:
#   - Prints manual MySQL commands and status messages to stdout if needed.
#
# Behavior:
#   - Displays commands if the user declined cleanup explicitly (`revision_cleanup_declined=true`).
#   - Displays commands if the automatic cleanup attempt failed to clear all revisions (`revisions_remain_after_cleanup=true`).
#
show_revision_cleanup_at_end() {
    local should_show_commands=false

    # Check if we should show revision cleanup commands
    if [[ "$revision_cleanup_declined" == true ]]; then
        should_show_commands=true
        printf "\n${CYAN}${BOLD}🗑️ Revision Cleanup Commands${RESET}\n"
        printf "${YELLOW}Since you declined automatic revision cleanup, here are the MySQL commands to clean up revisions manually:${RESET}\n\n"
    elif [[ "$revisions_remain_after_cleanup" == true ]]; then
        should_show_commands=true
        printf "\n${CYAN}${BOLD}🗑️ Revision Cleanup Commands${RESET}\n"
        printf "${YELLOW}Some revisions could not be automatically removed. Here are the MySQL commands to complete the cleanup:${RESET}\n\n"
    fi

    if [[ "$should_show_commands" == true ]]; then
        # Call the revision cleanup function (now loaded via module system)
        show_revision_cleanup_commands
        printf "\n"
    fi
}

# ===============================================
# import_wp_db() function definition
# ===============================================
#
# Description: The main function of the tool. It orchestrates the entire database
#              import, domain replacement, configuration management, multisite handling,
#              and post-import cleanup process.
#
# Parameters:
#   - None (Takes inputs interactively or from config files).
#
# Returns:
#   - 0 (Success) on completion.
#   - 1 (Failure) if critical steps (WP-CLI check, WP root detection, DB import, domain validation) fail.
#
# Behavior:
#   - Manages a comprehensive cleanup trap (`trap cleanup EXIT`) for temporary files.
#   - Auto-detects WP root, loads config, prompts for SQL file and domain mappings.
#   - Executes database import (`wp db import`).
#   - Handles single-site or multisite specific search-replace logic.
#   - Performs multisite network table updates (`wp_blogs`, `wp_site`) either automatically (via `wp eval`) or manually (generates MySQL commands).
#   - Flushes caches, optionally sets up Stage File Proxy, and shows site links.
#
import_wp_db() {

  # ⏱️ Initialize timers
  local total_start_time=$(date +%s)
  local script_execution_duration=0
  local segment_start_time=$(date +%s)

  # 📊 Track revision cleanup status for end-of-process reporting
  local revision_cleanup_declined=false
  local revisions_remain_after_cleanup=false

  # ===============================================
  # Timer Control Functions
  # ===============================================
  # Pauses the script execution timer before waiting for user input
  pause_script_timer() {
    local now
    now=$(date +%s)
    local segment_duration=$((now - segment_start_time))
    script_execution_duration=$((script_execution_duration + segment_duration))
  }

  # Resumes the script execution timer after user input is received
  resume_script_timer() {
    segment_start_time=$(date +%s)
  }

  # Determine absolute path to WP-CLI for robust execution in subshells
  WP_COMMAND=$(command -v wp)

  if [[ -z "$WP_COMMAND" ]]; then
    printf "${RED}❌ WP-CLI not found in PATH. Exiting.${RESET}\n"
    return 1
  fi

  # Export WP_COMMAND for use in utility functions
  export WP_COMMAND

  # 🧹 Define and set up cleanup for temporary log and data files
  local DB_LOG="/tmp/wp_db_import_$$.log"
  local SR_LOG_SINGLE="/tmp/wp_replace_single_$$.log"
  local REVISION_LOG="/tmp/wp_revision_delete_$$.log"
  local SUBSITE_DATA="/tmp/wp_subsite_data_$$.csv" # Temporary file to store subsite CSV data from WP-CLI

  # ===============================================
  # Comprehensive Cleanup Function
  # ===============================================
  #
  # Description: This function executes a comprehensive cleanup routine designed to safely
  #              remove all temporary files generated during the script's execution.
  #              It is primarily intended to be executed via a Bash `trap cleanup EXIT`
  #              command to ensure cleanup happens even if the script is interrupted or fails.
  #
  # Parameters:
  #   - None (Operates on globally defined variables).
  #
  # Returns:
  #   - 0 (Success) always.
  #
  # Behavior:
  #   - Explicitly removes defined temporary files ($DB_LOG, $SR_LOG_SINGLE, etc.) using their PID ($$) in the filename for uniqueness.
  #   - Uses `find` with the `delete` action to locate and remove any remaining temporary files or logs associated with the script's PID in `/tmp`.
  #   - Safely cleans up stale WP-CLI cache files (older than 1 day) to maintain system hygiene.
  #   - Uses `2>/dev/null` throughout to suppress errors for files that may already be gone or permissions issues.
  #
  cleanup() {
    # 🧹 Comprehensive cleanup of all temporary files created by this script (using PID $$)
    local files_to_remove=(
      "$DB_LOG"
      "$SR_LOG_SINGLE"
      "$REVISION_LOG"
      "$SUBSITE_DATA"
    )

    # Remove explicitly defined log files
    for file in "${files_to_remove[@]}"; do
      if [[ -n "$file" && -f "$file" ]]; then
        rm -f "$file" 2>/dev/null
      fi
    done

    # Clean up multisite logs (any log files starting with /tmp/wp_replace_ that contain the script's PID)
    find /tmp -type f -name "wp_replace_*_$$.log" -delete 2>/dev/null

    # Additional safety: Remove any other temp files that might have been created with this script's PID
    find /tmp -type f -name "*_$$.log" -delete 2>/dev/null
    find /tmp -type f -name "*_$$.csv" -delete 2>/dev/null
    find /tmp -type f -name "*_$$.tmp" -delete 2>/dev/null

    # Clean up any WordPress CLI cache files older than 1 day
    find /tmp -type f -name "wp-cli-*" -mtime +1 -delete 2>/dev/null
  }
  trap cleanup EXIT

  printf "\n${CYAN}${BOLD}🔧 WordPress Database Import & Domain Replace Tool${RESET}\n"
  printf "====================================================\n\n"

  # 🔍 Locate WordPress root by searching for wp-config.php
  local wp_root
  wp_root=$(pwd)
  while [[ "$wp_root" != "/" && ! -f "$wp_root/wp-config.php" ]]; do
    wp_root=$(dirname "$wp_root")
  done

  if [[ ! -f "$wp_root/wp-config.php" ]]; then
    printf "${RED}❌ WordPress root not found (wp-config.php missing).${RESET}\n"
    return 1
  fi

  if ! cd "$wp_root"; then
    printf "${RED}❌ Failed to change directory to ${wp_root}.${RESET}\n"
    return 1
  fi
  printf "${GREEN}✅ WordPress root found:${RESET} %s\n" "$wp_root"

  # 🛠️ Configuration Management
  local config_path
  if config_path=$(get_config_file_path); then
    if config_file_exists; then
      printf "${GREEN}✅ Configuration found:${RESET} %s\n\n" "$config_path"

      # Load existing config
      if load_import_config "$config_path"; then
        load_site_mappings "$config_path"
        printf "${CYAN}📋  Using configuration settings...${RESET}\n\n"
      else
        printf "${YELLOW}⚠️  Error loading config. Will prompt for values.${RESET}\n\n"
      fi
    else
      printf "${YELLOW}📝 No configuration file found.${RESET}\n"
      # Extract directory and filename separately for styling (with fallbacks)
      local config_dir config_file
      if command -v dirname >/dev/null 2>&1 && command -v basename >/dev/null 2>&1; then
        config_dir="$(dirname "$config_path")"
        config_file="$(basename "$config_path")"
      else
        # Fallback using parameter expansion for restricted environments
        config_dir="${config_path%/*}"
        config_file="${config_path##*/}"
        # Handle case where path has no directory separator
        [[ "$config_dir" == "$config_path" ]] && config_dir="."
      fi
      printf "💡 Creating new config: %s/${BOLD}%s${RESET}\n\n" "$config_dir" "$config_file"

      # Create empty config arrays (with enhanced shell compatibility)
      # Use the new bash compatibility system
      if has_bash_feature "associative_arrays" 2>/dev/null; then
        # Bash 4.0+: Use native associative arrays
        declare -A BLOG_ID_MAP OLD_DOMAIN_MAP NEW_DOMAIN_MAP 2>/dev/null || {
          # Initialize using compatibility functions if declare fails
          init_associative_array "BLOG_ID_MAP"
          init_associative_array "OLD_DOMAIN_MAP"
          init_associative_array "NEW_DOMAIN_MAP"
        }
      elif [[ -n "${ZSH_VERSION:-}" ]]; then
        # Running in zsh - use typeset for associative arrays
        typeset -A BLOG_ID_MAP OLD_DOMAIN_MAP NEW_DOMAIN_MAP 2>/dev/null || {
          # Fallback for restricted zsh
          init_associative_array "BLOG_ID_MAP"
          init_associative_array "OLD_DOMAIN_MAP"
          init_associative_array "NEW_DOMAIN_MAP"
        }
      else
        # Use compatibility functions for all other shells/versions
        init_associative_array "BLOG_ID_MAP"
        init_associative_array "OLD_DOMAIN_MAP"
        init_associative_array "NEW_DOMAIN_MAP"
      fi
    fi
  else
    printf "${RED}❌ Could not determine config file path${RESET}\n"
    return 1
  fi

  # 🧩 Get SQL file name (from config or prompt)
  local sql_file
  if [[ -n "$CONFIG_SQL_FILE" ]]; then
    sql_file="$CONFIG_SQL_FILE"
    printf "📦 SQL file: ${GREEN}%s${RESET} (from config)\n" "$sql_file"
  else
    pause_script_timer
    printf "📦 Enter SQL file name (default: vip-db.sql): "
    read -r sql_file
    resume_script_timer
    sql_file=${sql_file:-vip-db.sql}
  fi

  # 🧠 Verify WP-CLI availability
  if [[ -z "$WP_COMMAND" ]]; then
    printf "${RED}❌ WP-CLI not found. Please install WP-CLI first (or check your shell PATH).${RESET}\n"
    return 1
  fi

  # 🧱 Verify WordPress installation integrity
  if ! execute_wp_cli core is-installed &>/dev/null; then
    printf "${RED}❌ No WordPress installation detected in this directory.${RESET}\n"
    return 1
  fi

  # 🧾 Validate SQL file existence
  if [[ ! -f "$sql_file" ]]; then
    printf "${RED}❌ File '%s' not found.${RESET}\n" "$sql_file"
    printf "${YELLOW}💡 Hint:${RESET} Place the file in current directory or specify the full path.\n"
    return 1
  fi

  printf "${GREEN}✅ Found SQL file:${RESET} %s\n" "$sql_file"

  # 📊 Display file size information
  show_file_size "$sql_file"
  printf "\n"

  # 🌐 Get the main domain mapping (Source/Search and Destination/Replace)
  local search_domain replace_domain confirm

  # Get OLD (production/source) domain - from config or prompt with override option
  while true; do
    if [[ -n "$CONFIG_OLD_DOMAIN" ]]; then
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
    if [[ -n "$CONFIG_NEW_DOMAIN" ]]; then
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

  # Create config file if it doesn't exist, then save user-provided values
  if ! config_file_exists; then
    printf "${CYAN}📝 Creating configuration file...${RESET}\n"
    if create_config_file "$config_path" "$sql_file" "$search_domain" "$replace_domain"; then
      # Get filename with fallback for restricted environments
      local config_filename
      if command -v basename >/dev/null 2>&1; then
        config_filename="$(basename "$config_path")"
      else
        config_filename="${config_path##*/}"
      fi
      printf "${GREEN}✅ Configuration file created: %s${RESET}\n" "$config_filename"
    else
      printf "${YELLOW}⚠️  Could not create config file, but import will continue...${RESET}\n"
    fi
  fi

  # Save any user-provided values to config (with error handling)
  if ! save_import_values_to_config "$config_path" "$sql_file" "$search_domain" "$replace_domain" 2>/dev/null; then
    printf "${YELLOW}💡 Note: Could not save some settings to config (restricted environment)${RESET}\n"
  fi

  printf "\n"

  # 🧹 Sanitize domain inputs (remove protocols and trailing slashes)
  # Apply sanitization to both domains using centralized function
  local original_search_domain="$search_domain"
  local original_replace_domain="$replace_domain"
  search_domain=$(sanitize_domain "$search_domain")
  replace_domain=$(sanitize_domain "$replace_domain")

  # Show what was cleaned up if changes were made
  if [[ "$original_search_domain" != "$search_domain" ]]; then
    printf "${YELLOW}🧹 Cleaned search domain: '%s' → '%s'${RESET}\n" "$original_search_domain" "$search_domain"
  fi
  if [[ "$original_replace_domain" != "$replace_domain" ]]; then
    printf "${YELLOW}🧹 Cleaned replace domain: '%s' → '%s'${RESET}\n" "$original_replace_domain" "$replace_domain"
  fi

  printf "🧾 ${BOLD}Summary:${RESET}\n"
  printf "    🔍 Search for:   ${YELLOW}%s${RESET}\n" "$search_domain"
  printf "    🔄 Replace with: ${GREEN}%s${RESET}\n" "$replace_domain"
  printf "\n"

  # Auto-proceed or prompt for confirmation
  if [[ -n "$CONFIG_AUTO_PROCEED" ]] && is_config_true "$CONFIG_AUTO_PROCEED"; then
    printf "${GREEN}✅ Auto-proceeding with database import (from config)${RESET}\n"
    local confirm="y"
  else
    pause_script_timer
    printf "Proceed with database import? (Y/n): "
    read -r confirm
    resume_script_timer
    confirm="${confirm:-y}"
    [[ "$confirm" != [Yy]* ]] && { printf "${YELLOW}⚠️  Operation cancelled.${RESET}\n"; return 0; }
  fi

  # 📥 Import the database using WP-CLI (with a spinner)
  printf "\n${CYAN}⏳ Importing database...${RESET}\n"
  local import_start_time=$(date +%s)

  # Try robust command execution with fallbacks for restricted environments
  local import_success=false

  # Method 1: Try with enhanced PATH in subshell (most compatible)
  if command -v sh >/dev/null 2>&1; then
    if /bin/sh -c "(export PATH=\"/opt/homebrew/bin:/usr/local/bin:$PATH\"; \"$WP_COMMAND\" db import \"$sql_file\") &> \"$DB_LOG\"" & then
      local spinner_pid=$!
      show_spinner $spinner_pid "Importing"
      wait $spinner_pid && import_success=true
    fi
  fi

  # Method 2: Fallback for restricted environments - direct execution
  if [[ "$import_success" = false ]]; then
    printf "${YELLOW}Fallback: Direct WP-CLI execution...${RESET}\n"
    if execute_wp_cli db import "$sql_file" &> "$DB_LOG"; then
      import_success=true
    fi
  fi

  # Check if import was successful
  if [[ "$import_success" = false ]]; then
    printf "${RED}❌ Database import failed. Check %s for details.${RESET}\n" "$DB_LOG"
    return 1
  fi

  # Calculate elapsed time
  local import_end_time=$(date +%s)
  local import_elapsed=$((import_end_time - import_start_time))
  local import_minutes=$((import_elapsed / 60))
  local import_seconds=$((import_elapsed % 60))

  printf "${GREEN}✅ Database import successful! ${CYAN}[Completed in %02d:%02d]${RESET}\n\n" "$import_minutes" "$import_seconds"

  # 🔍 Domain validation against database (if config exists)
  printf "${CYAN}🔍 Validating domain configuration...${RESET}\n"
  local detected_domain
  if detected_domain=$(detect_database_domain "$wp_root"); then
    printf "${GREEN}✅ Detected domain in database: ${YELLOW}%s${RESET}\n" "$detected_domain"

    # Validate against config if it exists
    if config_file_exists; then
      local validated_domain
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

  # 🧩 Enhanced multisite detection logic.
  printf "\n${CYAN}🔍 Checking WordPress installation type...${RESET}\n"

  # Use the centralized detection function
  local wp_detect_output
  wp_detect_output=$(detect_wordpress_installation_type)
  IFS='|' read -r installation_type multisite_type network_flag blog_count site_count detection_method <<< "$wp_detect_output"

  # Set is_multisite variable for compatibility with rest of script
  local is_multisite="no"
  if [[ "$installation_type" == "multisite" ]]; then
    is_multisite="yes"
    printf "${GREEN}✅ Multisite detected (%s) via %s${RESET} (blogs: %s, sites: %s)\n" "$multisite_type" "$detection_method" "$blog_count" "$site_count"
  else
    is_multisite="no"
    printf "${GREEN}✅ Single site installation detected via %s${RESET}\n" "$detection_method"
  fi

  printf "\n"

  # 🗑️ Prompt for revision cleanup (from config with confirmation option)
  local cleanup_revisions
  if [[ -n "$CONFIG_CLEAR_REVISIONS" ]]; then
    if is_config_true "$CONFIG_CLEAR_REVISIONS"; then
      printf "Clear ALL post revisions: ${GREEN}enabled${RESET} (from config)\n"
      pause_script_timer
      printf "   ${CYAN}Press Enter to confirm, or 'n' to skip revision cleanup:${RESET} "
      read -r revision_override
      resume_script_timer

      if [[ "$revision_override" == [Nn]* ]]; then
        cleanup_revisions="n"
        printf "   ${YELLOW}⚠️  Skipping revision cleanup${RESET}\n"
        # Update config to remember this choice
        update_config_general "$config_path" "clear_revisions" "false" 2>/dev/null || true
      else
        cleanup_revisions="y"
        printf "   ${GREEN}✅ Proceeding with revision cleanup${RESET}\n"
      fi
    else
      printf "Clear ALL post revisions: ${YELLOW}disabled${RESET} (from config)\n"
      pause_script_timer
      printf "   ${CYAN}Press Enter to keep disabled, or 'y' to enable revision cleanup:${RESET} "
      read -r revision_override
      resume_script_timer

      if [[ "$revision_override" == [Yy]* ]]; then
        cleanup_revisions="y"
        printf "   ${GREEN}✅ Enabling revision cleanup${RESET}\n"
        # Update config to remember this choice
        update_config_general "$config_path" "clear_revisions" "true" 2>/dev/null || true
      else
        cleanup_revisions="n"
        printf "   ${YELLOW}⚠️  Keeping revision cleanup disabled${RESET}\n"
      fi
    fi
  else
    pause_script_timer
    printf "Clear ALL post revisions? (improves search-replace speed) (Y/n): "
    read -r cleanup_revisions
    resume_script_timer
    cleanup_revisions="${cleanup_revisions:-y}"

    # Save to config for future use
    if [[ "$cleanup_revisions" == [Yy]* ]]; then
      update_config_general "$config_path" "clear_revisions" "true"
    else
      update_config_general "$config_path" "clear_revisions" "false"
    fi
  fi

  # Track if user declined revision cleanup
  if [[ "$cleanup_revisions" != [Yy]* ]]; then
    revision_cleanup_declined=true
  fi

  if [[ "$cleanup_revisions" =~ ^[Yy]$ ]]; then
    printf "${CYAN}🗑️ Clearing ALL Post Revisions (improves search-replace speed)...${RESET}\n"

  # ===============================================
  # Function to perform revision cleanup silently and quickly
  # ===============================================
  #
  # Description: Deletes all WordPress post revisions for the current site or a specified subsite
  #              in a multisite network. It leverages the high-speed bulk operation capability
  #              of 'wp post list' piped to 'xargs wp post delete', which efficiently handles
  #              a large number of post IDs while bypassing Bash array splitting limits.
  #
  # Parameters:
  #   - $1 (optional, string): The `--url` parameter (e.g., `subsite.example.com`) to target a specific multisite subsite.
  #
  # Returns:
  #   - 0 (Success) if all revisions were successfully deleted or if no revisions were found initially.
  #   - 1 (Failure) if the bulk deletion fails or if revisions still remain in the database after the cleanup attempt.
  #
  # Behavior:
  #   - Step 1: Retrieves all post revision IDs (`post_type=revision`) using WP-CLI.
  #   - Step 2: Pipes the list of IDs to `xargs` to execute `wp post delete --force` in batches of 500.
  #   - Step 3: Verifies the remaining revision count after deletion.
  #   - Relies on the external functions `execute_wp_cli` and the global variable `$network_flag`.
  #
  clean_revisions_silent() {
    local url_param="$1"
    local wp_cli_args
    local revision_ids_output
    local revision_count_before
    local delete_success=0

    # 1. --- Revision ID Retrieval ---
    if [[ -n "$url_param" ]]; then
      wp_cli_args=("post" "list" "--post_type=revision" "--format=ids" "--url=$url_param")
    else
      wp_cli_args=("post" "list" "--post_type=revision" "--format=ids")
    fi

    # Execute the command and capture IDs.
    revision_ids_output=$(execute_wp_cli "${wp_cli_args[@]}" 2>/dev/null)
    local trimmed_output
    # Remove all carriage returns and newlines to get a single space-separated string of IDs.
    trimmed_output=$(echo "$revision_ids_output" | tr -d '\r\n')

    if [[ -z "$trimmed_output" ]]; then
        printf "${YELLOW}ℹ️  No revisions found for site: %s${RESET}\n" "${url_param:-main site}"
        return 0
    fi

    # Count IDs for verification and logging.
    revision_count_before=$(echo "$trimmed_output" | wc -w | tr -d ' ')

    printf "${CYAN}   Revisions found: %s${RESET}\n" "$revision_count_before"

    local wp_args=("--force")
    if [[ -n "$url_param" ]]; then
        wp_args+=("--url=$url_param")
    fi

    # Use xargs to pipeline the list of IDs, calling 'wp post delete' in batches of 500.
    xargs_command_output=$(echo "$trimmed_output" | xargs -r -n 500 "$WP_COMMAND" post delete "${wp_args[@]}" 2>&1)
    xargs_exit_code=$?

    # Check for execution success. WP-CLI may report success even if not all rows were deleted,
    # so we rely on the verification step.
    if [[ $xargs_exit_code -eq 0 ]]; then
        printf "  ${GREEN}✅ Revisions deleted (WP-CLI reported success)${RESET}\n"
        delete_success=1
    else
        printf "  ${RED}❌ Failed to execute BULK deletion (xargs Exit Code %s)${RESET}\n" "$xargs_exit_code"
        printf "  ${RED}WP-CLI output:${RESET}\n%s\n" "$xargs_command_output"
        return 1
    fi

    # 3. --- Verification Step ---
    local revisions_after
    local verify_wp_cli_args
    if [[ -n "$url_param" ]]; then
      verify_wp_cli_args=("post" "list" "--post_type=revision" "--format=ids" "--url=$url_param")
    else
      verify_wp_cli_args=("post" "list" "--post_type=revision" "--format=ids")
    fi

    local verify_output
    verify_output=$(execute_wp_cli "${verify_wp_cli_args[@]}" 2>/dev/null)
    revisions_after=$(echo "$verify_output" | wc -w | tr -d ' ')
    revisions_after="${revisions_after:-0}"

    # Final check for total success
    if [[ "$revisions_after" -eq 0 ]]; then
        return 0
    else
        printf "${RED}⚠️  WARNING: %s revisions remain in the database after bulk attempt.${RESET}\n" "$revisions_after"
        printf "${RED}WP-CLI output after deletion:${RESET}\n%s\n" "$verify_output"
        return 1
    fi
  }

  # Clear revisions based on site type (Multisite or Single-site)
  printf "${CYAN}🗑️ REVISION CLEANUP - STEP BY STEP${RESET}\n"
  printf "=====================================================\n\n"

  if [[ "$is_multisite" == "yes" ]]; then
    printf "${CYAN}🌐 MULTISITE DETECTED - Processing all subsites...${RESET}\n"
    printf "  ${YELLOW}Step A:${RESET} Getting list of all sites in the network\n"

    # Get all site URLs for multisite
    # Ensure WP-CLI execution environment is used
    local site_urls
    site_urls=$(execute_wp_cli site list --field=url --url="$search_domain" 2>/dev/null)

    # Count and display sites
    local site_count=$(echo "$site_urls" | wc -l | tr -d ' ')
    printf "  ${GREEN}Found %d sites to process:${RESET}\n" "$site_count"
    local site_counter=1
    while IFS= read -r site_url; do
      if [[ -n "$site_url" ]]; then
        printf "    %d. %s\n" "$site_counter" "$site_url"
        ((site_counter++))
      fi
    done <<< "$site_urls"

    printf "\n  ${YELLOW}Step B:${RESET} Processing revisions for each site individually\n\n"

    # Process each site with counter
    site_counter=1
    while IFS= read -r site_url; do
      if [[ -n "$site_url" ]]; then
        printf "  ${CYAN}🌍 Site %d/%d: %s${RESET}\n" "$site_counter" "$site_count" "$site_url"
        printf "  "
        if ! clean_revisions_silent "$site_url"; then
          revisions_remain_after_cleanup=true
        fi
        printf "\n"
        ((site_counter++))
      fi
    done <<< "$site_urls"
  else
    printf "${CYAN}🧩 SINGLE SITE DETECTED - Processing main site only...${RESET}\n"
    printf "  ${YELLOW}Step A:${RESET} Processing revisions for the main site\n\n"
    printf "  ${CYAN}🌍 Processing Main Site${RESET}\n"
    printf "  "
    if ! clean_revisions_silent ""; then
      revisions_remain_after_cleanup=true
    fi
    printf "\n"
  fi

  printf "\n"
  else
    printf "${YELLOW}⏭️  Skipping revision cleanup as requested.${RESET}\n\n"
  fi

  # ⚙️ Configure --all-tables flag (from config or prompt)
  local include_all all_tables_flag
  if [[ -n "$CONFIG_ALL_TABLES" ]]; then
    if is_config_true "$CONFIG_ALL_TABLES"; then
      all_tables_flag="--all-tables"
      printf "Include ${BOLD}--all-tables${RESET}: ${GREEN}enabled${RESET} (from config)\n"
    else
      all_tables_flag=""
      printf "Include ${BOLD}--all-tables${RESET}: ${YELLOW}disabled${RESET} (from config)\n"
    fi
  else
    pause_script_timer
    printf "Include ${BOLD}--all-tables${RESET} (recommended for full DB imports)? (Y/n): "
    read -r include_all
    resume_script_timer
    include_all="${include_all:-y}"
    all_tables_flag=""
    if [[ "$include_all" =~ ^[Yy]$ ]]; then
      all_tables_flag="--all-tables"
      printf "${GREEN}✅ Will include all tables.${RESET}\n"
      # Save to config for future use
      update_config_general "$config_path" "all_tables" "true"
    else
      printf "${YELLOW}ℹ️ Limiting to WordPress tables only.${RESET}\n"
      # Save to config for future use
      update_config_general "$config_path" "all_tables" "false"
    fi
  fi

  # ⚙️ Configure dry-run mode (from config or prompt)
  local dry_run dry_run_flag
  printf "\n"
  if [[ -n "$CONFIG_DRY_RUN" ]]; then
    if is_config_true "$CONFIG_DRY_RUN"; then
      dry_run_flag="--dry-run"
      printf "Run in ${BOLD}dry-run mode${RESET}: ${YELLOW}enabled${RESET} (from config)\n\n"
    else
      dry_run_flag=""
      printf "Run in ${BOLD}dry-run mode${RESET}: ${GREEN}live mode${RESET} (from config)\n\n"
    fi
  else
    pause_script_timer
    printf "Run in ${BOLD}dry-run mode${RESET} (no data will be changed)? (y/N): "
    read -r dry_run
    resume_script_timer
    dry_run="${dry_run:-n}"
    dry_run_flag=""
    if [[ "$dry_run" =~ ^[Yy]$ ]]; then
      dry_run_flag="--dry-run"
      printf "${YELLOW}🧪 Running in dry-run mode (preview only).${RESET}\n\n"
      # Save to config for future use
      update_config_general "$config_path" "dry_run" "true"
    else
      printf "${GREEN}🚀 Running in live mode (changes will be applied).${RESET}\n\n"
      # Save to config for future use
      update_config_general "$config_path" "dry_run" "false"
    fi
  fi

  # 🌐 Handle Multisite (Logic for site list, mapping, and per-site replacement)
  if [[ "$is_multisite" == "yes" ]]; then

      local confirm_replace
      printf "${CYAN}🌐 Multisite (%s) detected — gathering subsites for mapping...${RESET}\n\n" "$multisite_type"

      # --- Data Retrieval ---
      # Retrieve site data (ID, domain, path) in CSV format for later parsing
      execute_wp_cli site list --fields=blog_id,domain,path --format=csv --url="$search_domain" 2>"$REVISION_LOG" > "$SUBSITE_DATA"

      # 🔍 Main Site ID Detection Block (Using WordPress database structure)
      local main_site_info main_site_id main_site_url
      printf "${CYAN}🔍 Detecting main site using WordPress database structure...${RESET}\n"

      # Use the robust main site detection function
      main_site_info=$(detect_main_site "$is_multisite" "$search_domain")

      # Parse the result (format: blog_id|site_url)
      IFS='|' read -r main_site_id main_site_url <<< "$main_site_info"

      printf "${GREEN}✅ Main site detected:${RESET} Blog ID %s, URL: %s\n" "$main_site_id" "$main_site_url"

      # Read the CSV data for subsite processing
      local subsite_lines=()

      # Ensure the CSV file ends with a newline to prevent missing the last line
      echo "" >> "$SUBSITE_DATA"

      local line_count=0
      while IFS= read -r line; do
          line_count=$((line_count + 1))

          # Skip header line exactly
          if [[ "$line" == "blog_id,domain,path" ]]; then
              continue
          fi

          # Skip completely empty lines
          if [[ -z "$line" ]]; then
              continue
          fi

          # Clean the line of any carriage returns
          line="${line//$'\r'/}"

          # Skip if line becomes empty after cleaning
          if [[ -z "$line" ]]; then
              continue
          fi

          # Add valid lines only if they contain actual data
          if [[ "$line" =~ ^[0-9]+, ]]; then
              subsite_lines+=("$line")
          fi
      done < "$SUBSITE_DATA"

      printf "\n"
      # 🧩 End of Main Site ID Detection Block

      local site_list
      site_list=$(execute_wp_cli site list --fields=blog_id,domain,path --format=table --url="$search_domain" 2>&1)
      local wp_exit_code=$?

      # Count sites from the array length
      local site_count=${#subsite_lines[@]}

      printf "${GREEN}✅ Found %s subsites:${RESET}\n" "$site_count"

      if [[ $wp_exit_code -ne 0 ]]; then
        printf "${RED}❌ WP-CLI command failed with exit code %s:${RESET}\n" "$wp_exit_code"
        printf "${RED}Error output: %s${RESET}\n" "$site_list"
        # Exit if the site list command failed.
        return 1
      elif [[ -z "$site_list" ]]; then
        printf "${YELLOW}⚠️  WP-CLI command succeeded but returned empty output${RESET}\n"
      else
        printf "%s\n" "$site_list" | column -t -s $'\t'
      fi
      printf "\n"

      # Determine if multisite is subdirectory or subdomain (affects search-replace logic)
      site_type_label=$(printf '%s' "$multisite_type" | awk '{print toupper(substr($0,1,1)) tolower(substr($0,2))}')
      printf "${CYAN}🌐 %s Multisite Detected${RESET}\n" "$site_type_label"
      printf "Using configuration-aware site mapping...\n\n"

      # Handle site mappings with config system
      local subsite_csv=""
      for subsite_line in "${subsite_lines[@]}"; do
        if [[ "$subsite_line" != "blog_id,domain,path" && -n "$subsite_line" ]]; then
          if [[ -n "$subsite_csv" ]]; then
            subsite_csv="${subsite_csv}
${subsite_line}"
          else
            subsite_csv="$subsite_line"
          fi
        fi
      done

      # Process missing mappings with config system
      handle_missing_mappings "$config_path" "$subsite_csv" "$replace_domain"

      # Reload site mapping arrays after saving new mappings
      load_site_mappings "$config_path"

      # Use config mappings to build domain arrays for existing logic
      local domain_keys=()
      local domain_values=()
      local domain_blog_ids=()
      local domain_paths=()

      # Build arrays directly from saved config mappings instead of original site data
      local saved_mappings
      saved_mappings=$(get_site_mappings "$config_path")

      if [[ -n "$saved_mappings" ]]; then
        while IFS=':' read -r blog_id old_domain new_domain; do
          if [[ -n "$blog_id" && -n "$old_domain" && -n "$new_domain" ]]; then
            # Find the corresponding path from original site data
            local site_path="/"
            for subsite_line in "${subsite_lines[@]}"; do
              if [[ "$subsite_line" == "blog_id,domain,path" || -z "$subsite_line" ]]; then
                continue
              fi
              IFS=, read -r orig_blog_id orig_domain orig_path <<< "$subsite_line"
              if [[ "$orig_blog_id" == "$blog_id" ]]; then
                site_path="$orig_path"
                break
              fi
            done

            # Add to arrays using the saved mappings
            domain_keys+=("$old_domain")
            domain_values+=("$new_domain")
            domain_blog_ids+=("$blog_id")
            domain_paths+=("$site_path")
          fi
        done <<< "$saved_mappings"
      else
        printf "${YELLOW}⚠️  No saved mappings found in config file${RESET}\n"
      fi

      printf "\n🧾 ${BOLD}Domain Mapping Summary:${RESET}\n\n"
      # printf "    ${CYAN}ℹ️  Main site detected:${RESET} Blog ID %s (via WordPress database)\n" "$main_site_id"

      # --- Summary Loop using parallel arrays ---
      local array_length=${#domain_keys[@]}

      printf "  %-9s %-35s → %s\n" "Blog ID" "Production Domain" "Local Domain"
      printf "  %-9s %-35s   %s\n" "-------" "-----------------" "------------"

      for ((i=0; i<array_length; i++)); do

        local key="${domain_keys[i]}"
        local value="${domain_values[i]}"
        local id="${domain_blog_ids[i]}"
        local site_path_var="${domain_paths[i]}"

        local display_key="$key"
        if [[ "$site_path_var" != "/" ]]; then
            local clean_path="${site_path_var%/}"
            if [[ -n "$clean_path" && "$key" != *"$clean_path" ]]; then
                display_key="${key}${clean_path}"
            fi
        fi

        local main_site_emoji="    "
        if [ "$id" = "$main_site_id" ]; then
            main_site_emoji="🏠  "
        fi

        if [[ -z "$value" ]]; then
          printf "  %-4s %s %-35s → %s\n" \
              "$id" "$main_site_emoji" "$display_key" "(no mapping found)"
        elif [[ "$key" == "$value" ]]; then
            printf "  %-4s %s %-35s → %s\n" \
                "$id" "$main_site_emoji" "$display_key" "(unchanged)"
        else
            printf "  %-4s %s %-35s → ${GREEN}%s${RESET}\n" \
                "$id" "$main_site_emoji" "$display_key" "$value"
        fi
      done

      printf "\n"
      # Auto-proceed or prompt for confirmation
      if [[ -n "$CONFIG_AUTO_PROCEED" ]] && is_config_true "$CONFIG_AUTO_PROCEED"; then
        printf "${GREEN}✅ Auto-proceeding with search-replace for all sites (from config)${RESET}\n"
        local confirm_replace="y"
      else
        pause_script_timer
        printf "Proceed with search-replace for all sites? (Y/n): "
        read -r confirm_replace
        resume_script_timer
        confirm_replace="${confirm_replace:-y}"
        [[ "$confirm_replace" != [Yy]* ]] && { printf "${YELLOW}⚠️  Operation cancelled.${RESET}\n"; return 0; }
      fi

      # 🔧 Update wp_blogs and wp_site tables BEFORE search-replace operations
      printf "\n${CYAN}${BOLD}🔧 Updating wp_blogs and wp_site tables (before search-replace)...${RESET}\n"
      printf "================================================================\n\n"

      # Extract the base domain from the main site mapping for wp_site update
      local base_domain=""
      local main_site_new_domain=""
      local main_site_old_domain=""

      # Find the main site mapping for base_domain calculation
      local array_length=${#domain_keys[@]}
      for ((i=0; i<array_length; i++)); do
          local blog_id="${domain_blog_ids[i]}"
          if [[ "$blog_id" == "$main_site_id" ]]; then
              main_site_new_domain="${domain_values[i]}"
              main_site_old_domain="${domain_keys[i]}"
              break
          fi
      done

      if [[ -n "$main_site_new_domain" ]]; then
        base_domain="$main_site_new_domain"
        # Remove protocol if present
        base_domain="${base_domain#http://}"
        base_domain="${base_domain#https://}"
        # Remove trailing slash
        base_domain="${base_domain%/}"
        # Remove path if it's a subdirectory setup (we only want the base domain)
        base_domain="${base_domain%%/*}"
      fi

      if [[ -n "$base_domain" ]]; then
        printf "${CYAN}🔄 Executing wp_blogs and wp_site table updates via wp eval...${RESET}\n\n"

        # Build the wp eval command with all necessary updates
        local wp_eval_commands="global \\\$wpdb;"
        local processed_blog_ids=()

        # Generate wp_blogs UPDATE commands for subsites (ID != main_site_id)
        printf "${YELLOW}📝 Preparing wp_blogs updates for subsites...${RESET}\n"
        for ((i=0; i<array_length; i++)); do
          local old_domain="${domain_keys[i]}"
          local new_domain="${domain_values[i]}"
          local blog_id="${domain_blog_ids[i]}"

          # Skip main site for now
          if [[ "$blog_id" == "$main_site_id" ]]; then
            continue
          fi

          # Skip if empty or unchanged
          if [[ -z "$new_domain" || "$old_domain" == "$new_domain" ]]; then
            continue
          fi

          # Check for duplicates
          local duplicate_blog_id=false
          for processed_id in "${processed_blog_ids[@]}"; do
            if [[ "$processed_id" == "$blog_id" ]]; then
              duplicate_blog_id=true
              break
            fi
          done

          if [[ "$duplicate_blog_id" == true ]]; then
            continue
          fi

          processed_blog_ids+=("$blog_id")

          # Calculate the target domain and path
          local target_domain="$base_domain"
          local site_path="/"
          local clean_new_domain="$new_domain"
          clean_new_domain="${clean_new_domain#http://}"
          clean_new_domain="${clean_new_domain#https://}"

          # Extract path component for subdirectory setups
          if [[ "$clean_new_domain" == *"/"* ]]; then
            local path_part="${clean_new_domain#*/}"
            if [[ -n "$path_part" ]]; then
              site_path="/${path_part}"
              if [[ ! "$site_path" =~ /$ ]]; then
                site_path="${site_path}/"
              fi
            fi
          fi

          # For subdomain setups, use the full domain
          if [[ "$multisite_type" != "subdirectory" ]]; then
            local domain_part="$clean_new_domain"
            domain_part="${domain_part%/}"
            domain_part="${domain_part%%/*}"
            target_domain="$domain_part"
          fi

          if [[ "$site_path" == "//" ]]; then
            site_path="/"
          fi

          # Add to wp eval commands
          wp_eval_commands="${wp_eval_commands} \\\$wpdb->query(\\\"UPDATE wp_blogs SET domain='${target_domain}', path='${site_path}' WHERE blog_id=${blog_id};\\\");"
          printf "  → Blog ID %s: %s → %s%s\n" "$blog_id" "$old_domain" "$target_domain" "$site_path"
        done

        # Generate wp_blogs UPDATE command for main site (ID = main_site_id)
        printf "\n${YELLOW}📝 Preparing wp_blogs update for main site (ID: %s)...${RESET}\n" "$main_site_id"
        if [[ -n "$main_site_new_domain" ]]; then
            local main_site_path="/"
            local target_domain="$base_domain"

            if [[ "$multisite_type" != "subdirectory" ]]; then
              local domain_part="$main_site_new_domain"
              domain_part="${domain_part#http://}"
              domain_part="${domain_part#https://}"
              domain_part="${domain_part%/}"
              domain_part="${domain_part%%/*}"
              target_domain="$domain_part"
            fi

            wp_eval_commands="${wp_eval_commands} \\\$wpdb->query(\\\"UPDATE wp_blogs SET domain='${target_domain}', path='${main_site_path}' WHERE blog_id=${main_site_id};\\\");"
            printf "  → Blog ID %s: %s → %s%s\n" "$main_site_id" "$main_site_old_domain" "$target_domain" "$main_site_path"
        fi

        # Generate wp_site UPDATE command
        printf "\n${YELLOW}📝 Preparing wp_site update for network (ID: 1)...${RESET}\n"
        wp_eval_commands="${wp_eval_commands} \\\$wpdb->query(\\\"UPDATE wp_site SET domain='${base_domain}' WHERE id=1;\\\");"
        printf "  → Site ID 1: Network domain → %s\n" "$base_domain"

        # Add success message
        wp_eval_commands="${wp_eval_commands} echo 'wp_blogs and wp_site updated successfully.';"

        printf "\n${CYAN}⚡ Updating wp_blogs and wp_site tables...${RESET}\n"

        # Explicitly disable shell debugging to prevent variable assignment echoes
        set +x +v

        # Execute the wp eval command using the original search domain for --url parameter
        local eval_output eval_exit_code
        local total_commands_executed=0
        local failed_commands=0
        local failed_details=""

        # Try a simpler approach: Test WP-CLI connection first
        local connection_test
        connection_test=$(execute_wp_cli eval "echo 'Connection OK';" --url="$search_domain" 2>&1)
        local connection_exit_code=$?

        if [[ $connection_exit_code -ne 0 ]]; then
            printf "${RED}Connection failed: %s${RESET}\n" "$connection_test"
            local auto_updates_successful="no"
        else
            # Execute wp_site update FIRST (before wp_blogs updates change domain references)
            local site_command="global \$wpdb; \$result = \$wpdb->update('wp_site', array('domain' => '${base_domain}'), array('id' => 1)); echo (\$result !== false ? 'SUCCESS' : 'FAILED');"

            # Execute command and check result using bash pattern matching (no grep dependency)
            local site_output
            {
              site_output=$(set +x; execute_wp_cli eval "$site_command" --url="$search_domain" 2>&1)
            } 2>/dev/null

            if [[ "$site_output" == "SUCCESS" ]]; then
              ((total_commands_executed++))
            else
              ((failed_commands++))
              failed_details="${failed_details}Updating Network Site... Failed ❌\n"
            fi

            # Execute subsite updates
            for ((i=0; i<array_length; i++)); do
              local old_domain="${domain_keys[i]}"
              local new_domain="${domain_values[i]}"
              local blog_id="${domain_blog_ids[i]}"

              # Skip main site for now
              if [[ "$blog_id" == "$main_site_id" ]]; then
                continue
              fi

              # Skip if empty or unchanged
              if [[ -z "$new_domain" || "$old_domain" == "$new_domain" ]]; then
                continue
              fi

              # Calculate the target domain and path (same logic as before)
              local target_domain="$base_domain"
              local site_path="/"
              local clean_new_domain="$new_domain"
              clean_new_domain="${clean_new_domain#http://}"
              clean_new_domain="${clean_new_domain#https://}"

              # Extract path component for subdirectory setups
              if [[ "$clean_new_domain" == *"/"* ]]; then
                local path_part="${clean_new_domain#*/}"
                if [[ -n "$path_part" ]]; then
                  site_path="/${path_part}"
                  if [[ ! "$site_path" =~ /$ ]]; then
                    site_path="${site_path}/"
                  fi
                fi
              fi

              # For subdomain setups, use the full domain
              if [[ "$multisite_type" != "subdirectory" ]]; then
                local domain_part="$clean_new_domain"
                domain_part="${domain_part%/}"
                domain_part="${domain_part%%/*}"
                target_domain="$domain_part"
              fi

              if [[ "$site_path" == "//" ]]; then
                site_path="/"
              fi

              # Execute individual wp eval command for this subsite
              # Use simpler PHP syntax that's more compatible with wp eval
              local individual_command="global \$wpdb; \$result = \$wpdb->update('wp_blogs', array('domain' => '${target_domain}', 'path' => '${site_path}'), array('blog_id' => ${blog_id})); echo (\$result !== false ? 'SUCCESS' : 'FAILED');"

              # Execute command and check result using bash pattern matching (no grep dependency)
              local blog_output
              {
                blog_output=$(set +x; execute_wp_cli eval "$individual_command" --url="$search_domain" 2>&1)
              } 2>/dev/null

              if [[ "$blog_output" == "SUCCESS" ]]; then
                ((total_commands_executed++))
              else
                ((failed_commands++))
                failed_details="${failed_details}Updating Blog ID ${blog_id}... Failed ❌\n"
              fi
            done

            # Execute main site update
            if [[ -n "$main_site_new_domain" ]]; then
                local main_site_path="/"
                local target_domain="$base_domain"

                if [[ "$multisite_type" != "subdirectory" ]]; then
                  local domain_part="$main_site_new_domain"
                  domain_part="${domain_part#http://}"
                  domain_part="${domain_part#https://}"
                  domain_part="${domain_part%/}"
                  domain_part="${domain_part%%/*}"
                  target_domain="$domain_part"
                fi

                # Execute main site wp_blogs update
                local main_command="global \$wpdb; \$result = \$wpdb->update('wp_blogs', array('domain' => '${target_domain}', 'path' => '${main_site_path}'), array('blog_id' => ${main_site_id})); echo (\$result !== false ? 'SUCCESS' : 'FAILED');"

                # Execute command and check result using bash pattern matching (no grep dependency)
                local main_output
                {
                  main_output=$(set +x; execute_wp_cli eval "$main_command" --url="$search_domain" 2>&1)
                } 2>/dev/null

                if [[ "$main_output" == "SUCCESS" ]]; then
                  ((total_commands_executed++))
                else
                  ((failed_commands++))
                  failed_details="${failed_details}Updating Main Site (Blog ID ${main_site_id})... Failed ❌\n"
                fi
            fi

            # Determine overall success and show clean output
            if [[ $failed_commands -eq 0 ]]; then
              printf "${GREEN}✅ Database tables wp_blogs & wp_site updated successfully!${RESET}\n"
              local auto_updates_successful="yes"
            else
              printf "${RED}❌ Database update failed!${RESET}\n"
              echo -e "$failed_details"
              local auto_updates_successful="no"
            fi
        fi

      else
        printf "${YELLOW}⚠️  Could not determine base domain - skipping automatic table updates${RESET}\n"
        local auto_updates_successful="no"
      fi

      local new_domain SR_LOG_MULTI
      local main_site_key=""
      local main_site_value=""
      local main_site_path=""

      # --- Use modular search-replace processing ---
      # Call the extracted multisite processing function from search_replace module
      process_multisite_mappings "$main_site_id" domain_keys domain_values domain_blog_ids domain_paths

  else
    # 🧩 Single site logic
    printf "${CYAN}🧩 Single site detected.${RESET}\n"
    # Auto-proceed or prompt for confirmation
    if [[ -n "$CONFIG_AUTO_PROCEED" ]] && is_config_true "$CONFIG_AUTO_PROCEED"; then
      printf "${GREEN}✅ Auto-proceeding with search-replace (from config)${RESET}\n"
      local confirm_replace="y"
    else
      pause_script_timer
      printf "Proceed with search-replace now? (Y/n): "
      read -r confirm_replace
      resume_script_timer
      confirm_replace="${confirm_replace:-y}"
      [[ "$confirm_replace" != [Yy]* ]] && { printf "${YELLOW}⚠️  Operation cancelled.${RESET}\n"; return 0; }
    fi

    printf "\n🔁 Running search-replace operations...\n"

    # Execute search-replace for single site (Pass search_domain and replace_domain, with no --url flag)
    if run_search_replace "$search_domain" "$replace_domain" "$SR_LOG_SINGLE" ""; then
      printf "\n${GREEN}✅ Search-replace completed successfully!${RESET}\n"

      # Save single site mapping to config for future Stage File Proxy usage
      if [[ -n "$config_path" ]]; then
        # Use unified config reader if available, otherwise fallback to existing config_manager
        if command -v write_site_mapping >/dev/null 2>&1; then
          write_site_mapping "1" "$search_domain" "$replace_domain" "$config_path"
          printf "${GREEN}💾 Saved domain mapping to config for future Stage File Proxy usage${RESET}\n"
        elif command -v update_site_mapping >/dev/null 2>&1; then
          update_site_mapping "$config_path" "1" "$search_domain" "$replace_domain"
          printf "${GREEN}💾 Saved domain mapping to config for future Stage File Proxy usage${RESET}\n"
        fi
      fi
    else
      printf "\n${RED}❌ Search-replace failed. See %s.${RESET}\n" "$SR_LOG_SINGLE"
      return 1
    fi
  fi

  # 🧹 Flush caches and transients (post-search-replace operations)
  printf "\n${CYAN}🧹 Flushing WordPress and WP-CLI caches & transients...${RESET}\n"

  # 1. Clear object cache (if persistent caching is used)
  # Use execute_wp_cli for reliable command execution
  if ! execute_wp_cli cache flush $network_flag &>/dev/null; then
      printf "${YELLOW}  ⚠️  Failed to flush object cache (Not always necessary/available).${RESET}\n"
  else
      printf "${GREEN}  ✅ Object cache flushed.${RESET}\n"
  fi

  # 2. Flush rewrite rules (hard flush for robust update)
  # Use execute_wp_cli for reliable command execution
  if ! execute_wp_cli rewrite flush --hard $network_flag &>/dev/null; then
      printf "${YELLOW}  ⚠️  Failed to flush rewrite rule (Not always necessary/available).${RESET}\n"
  else
      printf "${GREEN}  ✅ Rewrite rule flushed.${RESET}\n"
  fi

  # 3. Delete transients
  # Use execute_wp_cli for reliable command execution
  if ! execute_wp_cli transient delete --all $network_flag &>/dev/null; then
      printf "${YELLOW}  ⚠️  Transient deletion finished (No transients found or minor error).${RESET}\n"
  else
      printf "${GREEN}  ✅ All transients deleted.${RESET}\n"
  fi

  printf "\n${GREEN}${BOLD}🎉 All done!${RESET} Database import and replacements completed successfully.\n\n"

  # 📋 Generate and display MySQL commands for manual execution (fallback only if early auto-updates failed)
  if [[ "$is_multisite" == "yes" && ${#domain_keys[@]} -gt 0 && "${auto_updates_successful:-yes}" == "no" ]]; then
    printf "\n================================================================\n"
    printf "\n${CYAN}${BOLD}📋 MySQL Commands for Manual Execution in phpMyAdmin:${RESET}\n"
    printf "\n================================================================\n\n"

    # Extract the base domain from the main site mapping for wp_site update
    local base_domain=""
    local main_site_new_domain=""
    local main_site_old_domain=""

    # Find the main site mapping for base_domain calculation (using standard 0-based array iteration)
    local array_length=${#domain_keys[@]}
    for ((i=0; i<array_length; i++)); do
        local blog_id="${domain_blog_ids[i]}"
        if [[ "$blog_id" == "$main_site_id" ]]; then
            main_site_new_domain="${domain_values[i]}"
            main_site_old_domain="${domain_keys[i]}"
            break
        fi
    done

    if [[ -n "$main_site_new_domain" ]]; then
      base_domain="$main_site_new_domain"
      # Remove protocol if present
      base_domain="${base_domain#http://}"
      base_domain="${base_domain#https://}"
      # Remove trailing slash
      base_domain="${base_domain%/}"
      # Remove path if it's a subdirectory setup (we only want the base domain)
      base_domain="${base_domain%%/*}"
    fi

    if [[ -n "$base_domain" ]]; then
      printf "\n-- 1. Update wp_blogs table: blog domain and path for SUB-SITES (ID != %s)\n\n" "$main_site_id"

      # Generate commands for each mapped subsite domain
      local processed_blog_ids=() # Track processed blog_ids to prevent duplicates

      # --- Subsite Commands (ID != main_site_id) ---
      for ((i=0; i<array_length; i++)); do
        local old_domain="${domain_keys[i]}"
        local new_domain="${domain_values[i]}"
        local blog_id="${domain_blog_ids[i]}"

        # Skip main site for this section
        if [[ "$blog_id" == "$main_site_id" ]]; then
          continue
        fi

        # Skip if empty or unchanged
        if [[ -z "$new_domain" || "$old_domain" == "$new_domain" ]]; then
          continue
        fi

        # Find the path component from the new_domain mapping (for subdirectory migration)
        local site_path="/"
        local clean_new_domain="$new_domain"
        clean_new_domain="${clean_new_domain#http://}"
        clean_new_domain="${clean_new_domain#https://}"

        local path_part=""
        if [[ "$clean_new_domain" == *"/"* ]]; then
          path_part="${clean_new_domain#*/}"
          if [[ -n "$path_part" ]]; then
            site_path="/${path_part}"
            if [[ ! "$site_path" =~ /$ ]]; then
              site_path="${site_path}/"
            fi
          else
            site_path="/"
          fi
        else
          site_path="/"
        fi

        if [[ "$site_path" == "//" ]]; then
          site_path="/"
        fi

        # Skip if already processed (for safety)
        local duplicate_blog_id=false
        for processed_id in "${processed_blog_ids[@]}"; do
          if [[ "$processed_id" == "$blog_id" ]]; then
            duplicate_blog_id=true
            break
          fi
        done

        if [[ "$duplicate_blog_id" == true ]]; then
          printf "\n-- Skipping duplicate blog_id %s for domain %s\n" "$blog_id" "$old_domain"
          continue
        fi

        processed_blog_ids+=("$blog_id")

        # Determine the target domain
        local target_domain="$base_domain"
        if [[ "$multisite_type" != "subdirectory" ]]; then
          local domain_part="$new_domain"
          domain_part="${domain_part#http://}"
          domain_part="${domain_part#https://}"
          domain_part="${domain_part%/}"
          domain_part="${domain_part%%/*}"
          target_domain="$domain_part"
        fi

        printf "UPDATE wp_blogs SET domain = \"%s\", path = \"%s\" WHERE blog_id = %s; -- %s → %s (Subsite)\n" "$target_domain" "$site_path" "$blog_id" "$old_domain" "$new_domain"
      done

      printf "\n-- 2. Update wp_blogs table: blog domain and path for MAIN SITE (ID = %s)\n\n" "$main_site_id"

      # --- Main Site wp_blogs Command (ID = main_site_id) ---
      if [[ -n "$main_site_new_domain" ]]; then
          # For main site, the path is always '/'
          local main_site_path="/"

          # Determine the target domain for main_site_id
          local target_domain="$base_domain"
          if [[ "$multisite_type" != "subdirectory" ]]; then
            # Use the full domain part for subdomain setups
            local domain_part="$main_site_new_domain"
            domain_part="${domain_part#http://}"
            domain_part="${domain_part#https://}"
            domain_part="${domain_part%/}"
            domain_part="${domain_part%%/*}"
            target_domain="$domain_part"
          fi

          # Output the command for wp_blogs main_site_id
          printf "UPDATE wp_blogs SET domain = \"%s\", path = \"%s\" WHERE blog_id = %s; -- %s → %s (Main Site)\n" "$target_domain" "$main_site_path" "$main_site_id" "$main_site_old_domain" "$main_site_new_domain"
      else
          printf "\n-- WARNING: Main site mapping (ID %s) not found to generate wp_blogs command.\n" "$main_site_id"
      fi

      printf "\n-- 3. Update wp_site table: the main network site domain (ID = 1)\n"
      printf "UPDATE wp_site SET domain = '%s' WHERE id = 1;\n\n" "$base_domain"

      printf "\n================================================================\n"

      printf "\n${YELLOW}💡 Copy the above commands and paste them into phpMyAdmin → SQL command to execute.${RESET}\n"
    else
      printf "${YELLOW}⚠️  Could not generate MySQL commands - no base domain found.${RESET}\n"
    fi
  elif [[ "$is_multisite" != "yes" ]]; then
    printf "${GREEN}✅ Single site domain replacement completed via WP-CLI.${RESET}\n"
  fi

  printf "\n"

  # 🔍 Prompt for confirmation that MySQL commands have been executed (only if manual commands were shown)
  local sql_executed="y"
  if [[ "$is_multisite" == "yes" && ${#domain_keys[@]} -gt 0 && "${auto_updates_successful:-yes}" == "no" ]]; then
    printf "${CYAN}${BOLD}📋 MySQL Commands Confirmation${RESET}\n"
    pause_script_timer
    printf "Have you executed the above MySQL commands in phpMyAdmin/database? (Y/n): "
    read -r sql_executed
    resume_script_timer
    sql_executed="${sql_executed:-y}"

    if [[ "$sql_executed" != [Yy]* ]]; then
      printf "${YELLOW}⚠️  Please execute the MySQL commands first, to complete the setup.${RESET}\n"
      sql_executed="n"
    else
      printf "${GREEN}🚀 Database Migration Completed Successfully!${RESET}\n"
    fi
    printf "\n"
  elif [[ "$is_multisite" == "yes" && "${auto_updates_successful:-yes}" == "yes" ]]; then
    # Auto-updates were successful, no manual intervention needed
    printf "${GREEN}🚀 Database Migration Completed Successfully! (Tables updated automatically)${RESET}\n\n"
    sql_executed="y"
  fi

  # 🔍 Stage File Proxy Plugin Setup (only if SQL commands confirmed and proceeding)
  if [[ "$sql_executed" == [Yy]* ]]; then
    # Ask user if they want to setup stage file proxy for media management (from config or prompt)
    local setup_stage_proxy
    if [[ -n "$CONFIG_SETUP_STAGE_PROXY" ]]; then
      if is_config_true "$CONFIG_SETUP_STAGE_PROXY"; then
        setup_stage_proxy="y"
        printf "${CYAN}${BOLD}📸 Stage File Proxy Setup${RESET}\n"
        printf "Setup stage file proxy: ${GREEN}enabled${RESET} (from config)\n"
      else
        setup_stage_proxy="n"
        printf "${CYAN}${BOLD}📸 Stage File Proxy Setup${RESET}\n"
        printf "Setup stage file proxy: ${YELLOW}disabled${RESET} (from config)\n"
      fi
    else
      printf "${CYAN}${BOLD}📸 Stage File Proxy Setup${RESET}\n"
      pause_script_timer
      printf "Do you want to setup the stage file proxy plugin for media management? (Y/n): "
      read -r setup_stage_proxy
      resume_script_timer
      setup_stage_proxy="${setup_stage_proxy:-y}"

      # Save to config for future use
      if [[ "$setup_stage_proxy" == [Yy]* ]]; then
        update_config_general "$config_path" "setup_stage_proxy" "true"
      else
        update_config_general "$config_path" "setup_stage_proxy" "false"
      fi
    fi

    if [[ "$setup_stage_proxy" == [Yy]* ]]; then
      # Use the unified stage file proxy module
      # Automatically detects mode based on available configuration
      if command -v setup_stage_file_proxy_unified >/dev/null 2>&1; then
        printf "\n${CYAN}${BOLD}📸 Stage File Proxy Unified Setup${RESET}\n"

        # Call unified function with config path - it auto-detects automatic vs manual mode
        if setup_stage_file_proxy_unified "$config_path"; then
          printf " ${GREEN}🎉 Stage File Proxy setup completed successfully!${RESET}\n"
        else
          printf " ${YELLOW}⚠️  Stage File Proxy setup encountered some issues, but continuing...${RESET}\n"
        fi
      else
        printf "${RED}❌ Stage File Proxy unified module not found${RESET}\n"
        printf "${YELLOW}💡 Falling back to original setup process...${RESET}\n"

        # Fallback to original setup (legacy compatibility)
        if command -v setup_stage_file_proxy >/dev/null 2>&1; then
          setup_stage_file_proxy
        else
          printf "${RED}❌ Stage File Proxy module not available${RESET}\n"
        fi
      fi

      # Show revision cleanup commands at the end if needed
      show_revision_cleanup_at_end

      # Call the separate function to display local site access links
      show_local_site_links
    else
      printf "${YELLOW}ℹ️ Skipping stage-file-proxy setup as requested${RESET}\n"

      # Show revision cleanup commands at the end if needed
      show_revision_cleanup_at_end

      # Call the separate function to display local site access links
      show_local_site_links
    fi
  else
    printf "${YELLOW}ℹ️ Skipping stage-file-proxy configuration (SQL commands not confirmed or not applicable).${RESET}\n"

    # Show revision cleanup commands at the end if needed
    show_revision_cleanup_at_end

    # Call the separate function to display local site access links
    show_local_site_links
  fi

  # ⏱️ Calculate and display total execution time
  pause_script_timer # Final pause to capture the last segment
  local total_end_time=$(date +%s)
  local total_elapsed=$((total_end_time - total_start_time))

  # Format total elapsed time
  local total_minutes=$((total_elapsed / 60))
  local total_seconds=$((total_elapsed % 60))

  # Format script execution time
  local script_minutes=$((script_execution_duration / 60))
  local script_seconds=$((script_execution_duration % 60))

  printf "\n${BOLD}⏱️  ${CYAN}Execution${RESET} ${GREEN}%02d:%02d${RESET}${RESET}" "$script_minutes" "$script_seconds"
  printf "${CYAN}${BOLD} | Total${RESET} ${GREEN}%02d:%02d${RESET}${RESET}\n\n" "$total_minutes" "$total_seconds"

  printf "\n"

  # Ensure cleanup is run on successful exit
  trap - EXIT
}
