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
  init_script_timer

  # 📊 Track revision cleanup status for end-of-process reporting
  local revision_cleanup_declined=false
  local revisions_remain_after_cleanup=false

  # Determine absolute path to WP-CLI for robust execution in subshells
  WP_COMMAND=$(command -v wp)

  if [[ -z "$WP_COMMAND" ]]; then
    printf "${RED}❌ WP-CLI not found in PATH. Exiting.${RESET}\n"
    return 1
  fi

  # Export WP_COMMAND for use in utility functions
  export WP_COMMAND

  # 🧹 Define and set up cleanup for temporary log and data files
  # Logs live in a private (mode 700) temp directory, not in world-readable /tmp paths
  local WPDB_TMP_DIR
  if ! WPDB_TMP_DIR=$(secure_tmpdir); then
    printf "${RED}❌ Could not create a private temporary directory.${RESET}\n"
    return 1
  fi
  local DB_LOG="$WPDB_TMP_DIR/db_import.log"
  local SR_LOG_SINGLE="$WPDB_TMP_DIR/replace_single.log"
  local REVISION_LOG="$WPDB_TMP_DIR/revision_delete.log"
  local SUBSITE_DATA="$WPDB_TMP_DIR/subsite_data.csv" # Temporary file to store subsite CSV data from WP-CLI

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

      if declare -F ensure_socket_config_settings >/dev/null 2>&1; then
        ensure_socket_config_settings "$config_path" >/dev/null 2>&1 || true
        if [[ "$CONFIG_SOCKET_SETTINGS_MIGRATED" == "true" ]]; then
          printf "${GREEN}✅ Updated existing config with import settings:${RESET} use_socket, mysql_socket, import_optimizations, parallel_import, backup_before_import, backup_dir, backup_keep\n\n"
        fi
      fi

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
    wpdb_read_required sql_file "The SQL file name (sql_file)" || return 1
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
  get_domains "$config_path"

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

  printf "🧾 ${BOLD}Summary:${RESET}\n"
  printf "    🔍 Search for:   ${YELLOW}%s${RESET}\n" "$search_domain"
  printf "    🔄 Replace with: ${GREEN}%s${RESET}\n" "$replace_domain"
  printf "\n"

  # 🧪 Dry run is decided BEFORE anything is imported: a dry run previews the whole import in a
  # temporary database and never changes the real one (no backup, no import, no replacement).
  decide_dry_run_mode "$config_path"
  if [[ "$WPDB_DRY_RUN_ACTIVE" == "true" ]]; then
    dry_run_preview "$sql_file" "$search_domain" "$replace_domain" "$wp_root" "$config_path"
    return $?
  fi

  # Auto-proceed or prompt for confirmation
  local auto_reason
  if auto_reason=$(wpdb_auto_proceed_reason); then
    printf "${GREEN}✅ Auto-proceeding with database import (%s)${RESET}\n" "$auto_reason"
    local confirm="y"
  else
    pause_script_timer
    printf "Proceed with database import? (Y/n): "
    wpdb_read confirm
    resume_script_timer
    confirm="${confirm:-y}"
    [[ "$confirm" != [Yy]* ]] && { printf "${YELLOW}⚠️  Operation cancelled.${RESET}\n"; return 0; }
  fi

  # 💾 Back up the current database before it is replaced (cancels the import on failure)
  # Uses db_backup.sh
  if ! backup_database_before_import "$wp_root" "$config_path"; then
      return 1
  fi

  # 📥 Import the database using WP-CLI (with a spinner)
  # Uses db_import.sh
  if ! perform_db_import "$sql_file" "$DB_LOG"; then
      return 1
  fi

  # 🔍 Domain validation against database (if config exists)
  # Uses domain_manager.sh
  if ! validate_domains "$wp_root" "$config_path"; then
      return 1
  fi

  # 🧩 Enhanced multisite detection logic.
  printf "\n${CYAN}🔍 Checking WordPress installation type...${RESET}\n"

  # Use the centralized detection function
  local wp_detect_output
  wp_detect_output=$(detect_wordpress_installation_type)
  IFS='|' read -r installation_type multisite_type network_flag blog_count site_count detection_method <<< "$wp_detect_output"
  # Detection reports "NA" for single sites; only a real "--network" may reach WP-CLI
  [[ "$network_flag" == "--network" ]] || network_flag=""

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
      wpdb_read revision_override
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
      wpdb_read revision_override
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
    wpdb_read cleanup_revisions
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
    wpdb_read include_all
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

  # Live mode only: a dry run returned earlier. The flag is kept for the search-replace code.
  local dry_run_flag=""

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
      if auto_reason=$(wpdb_auto_proceed_reason); then
        printf "${GREEN}✅ Auto-proceeding with search-replace for all sites (%s)${RESET}\n" "$auto_reason"
        local confirm_replace="y"
      else
        pause_script_timer
        printf "Proceed with search-replace for all sites? (Y/n): "
        wpdb_read confirm_replace
        resume_script_timer
        confirm_replace="${confirm_replace:-y}"
        [[ "$confirm_replace" != [Yy]* ]] && { printf "${YELLOW}⚠️  Operation cancelled.${RESET}\n"; return 0; }
      fi

      # 🔧 Update wp_blogs and wp_site tables BEFORE search-replace operations
      if update_multisite_tables "$main_site_id" "$multisite_type" "$search_domain"; then
          local auto_updates_successful="yes"
      else
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
    if auto_reason=$(wpdb_auto_proceed_reason); then
      printf "${GREEN}✅ Auto-proceeding with search-replace (%s)${RESET}\n" "$auto_reason"
      local confirm_replace="y"
    else
      pause_script_timer
      printf "Proceed with search-replace now? (Y/n): "
      wpdb_read confirm_replace
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

  # 2. Flush rewrite rules (soft flush: updates the DB option only, never writes .htaccess/web.config)
  # Use execute_wp_cli for reliable command execution
  # `wp rewrite flush` has no --network option (it fails with "unknown --network parameter"),
  # and rewrite rules are stored per site: on a network, flush every site by its URL.
  local rewrite_ok=true
  if [[ -n "$network_flag" ]]; then
    local site_url_list site_url_item
    site_url_list=$(execute_wp_cli site list --field=url 2>/dev/null)
    if [[ -z "$site_url_list" ]]; then
      rewrite_ok=false
    else
      while IFS= read -r site_url_item; do
        [[ -n "$site_url_item" ]] || continue
        execute_wp_cli rewrite flush --url="$site_url_item" &>/dev/null || rewrite_ok=false
      done <<< "$site_url_list"
    fi
  else
    execute_wp_cli rewrite flush &>/dev/null || rewrite_ok=false
  fi
  if [[ "$rewrite_ok" == "true" ]]; then
      printf "${GREEN}  ✅ Rewrite rule flushed.${RESET}\n"
  else
      printf "${YELLOW}  ⚠️  Failed to flush rewrite rule (Not always necessary/available).${RESET}\n"
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
    if ! wpdb_read_required sql_executed "Confirmation that the MySQL commands above were executed"; then
      printf "${YELLOW}⚠️  Run the MySQL commands shown above, then re-run the tool.${RESET}\n"
      return 1
    fi
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
      wpdb_read setup_stage_proxy
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
  local start_time_val=$(get_total_start_time)
  local total_elapsed=$((total_end_time - start_time_val))

  # Format total elapsed time
  local total_minutes=$((total_elapsed / 60))
  local total_seconds=$((total_elapsed % 60))

  # Format script execution time
  local execution_duration=$(get_execution_duration)
  local script_minutes=$((execution_duration / 60))
  local script_seconds=$((execution_duration % 60))

  printf "\n${BOLD}⏱️  ${CYAN}Execution${RESET} ${GREEN}%02d:%02d${RESET}${RESET}" "$script_minutes" "$script_seconds"
  printf "${CYAN}${BOLD} | Total${RESET} ${GREEN}%02d:%02d${RESET}${RESET}\n\n" "$total_minutes" "$total_seconds"

  printf "\n"

  # Remove the temporary logs and private temp directory now, then clear the EXIT trap.
  # (Clearing the trap alone would skip cleanup on success and leave the files behind.)
  cleanup
  trap - EXIT
}

# Check if sourced or executed
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # Options: --yes / -y / --non-interactive (unattended mode, same as WPDB_ASSUME_YES=1)
    for _wpdb_arg in "$@"; do
        case "$_wpdb_arg" in
            --yes|-y|--non-interactive) export WPDB_ASSUME_YES=1 ;;
            --dry-run) export WPDB_DRY_RUN=1 ;;
            *)
                printf "${RED}❌ Unknown option: %s${RESET}\n" "$_wpdb_arg" >&2
                printf "Usage: import_wp_db.sh [--yes | -y | --non-interactive] [--dry-run]\n" >&2
                exit 2
                ;;
        esac
    done
    # Unattended: nothing may wait for input (not even a child process)
    wpdb_assume_yes && exec </dev/null
    import_wp_db
fi
