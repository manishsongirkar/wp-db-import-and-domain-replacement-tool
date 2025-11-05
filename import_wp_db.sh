#!/bin/bash

# ===============================================
# WordPress Database Import & Domain Replacement Tool
# ===============================================
#
# Description:
#   A robust bash utility for performing WordPress database imports and domain/URL
#   replacements, commonly needed for migrating environments (e.g., production to local/staging).
#   It efficiently handles single-site and multi-domain WordPress Multisite setups.
#
# Features:
#   - Automatic WordPress installation detection (single-site or multisite)
#   - **High-Speed Bulk Post Revision Cleanup (via xargs)**
#   - Intelligent domain sanitization (removes protocols, trailing slashes)
#   - **Robust Multi-Domain/Per-Site Mapping for Multisite**
#   - Two-pass search-replace (standard + serialized data)
#   - Cache and transient clearing via WP-CLI
#   - Dry-run mode for testing replacements
#   - MySQL command generation for network domain tables (critical for multisite completion)
#   - Comprehensive error handling and logging
#   - Colored terminal output with clear progress indicators
#
# Requirements:
#   - WP-CLI installed and accessible in PATH
#   - WordPress installation (wp-config.php present)
#   - MySQL/MariaDB database
#   - Bash shell (minimum 4.0 recommended for best performance)
#   - macOS/Linux environment
#
# Usage:
#   1. Place SQL file in the same directory as this script.
#   2. Navigate to WordPress root directory or subdirectory.
#   3. Source this script: source import_wp_db.sh
#   4. Run the function: import_wp_db
#   5. Follow the interactive prompts.
#
# Additional Functions:
#   show_local_site_links - Display clickable links to local WordPress sites (sourced from show_local_site_links.sh)
#     Usage: show_local_site_links
#     Requirements: Must be run from within a WordPress directory with WP-CLI installed
#     Note: Function is loaded from show_local_site_links.sh in the same directory
#
# Supported WordPress Types:
#   - Single-site installations
#   - Multisite subdomain networks
#   - Multisite subdirectory networks (including multi-domain to single-domain migrations)
#
# File Structure:
#   - Creates temporary log files in /tmp/ for debugging (uses PID to prevent collision)
#   - Automatically cleans up temporary files on exit
#   - Logs all WP-CLI operations for troubleshooting
#
# Security:
#   - Uses absolute paths to prevent directory traversal
#   - Validates all user inputs
#   - Sanitizes domain inputs
#   - Uses temporary files with process-specific names
#
# Author: Manish Songirkar (@manishsongirkar)
# Repository: https://github.com/manishsongirkar/wp-db-import-and-domain-replacement-tool
#
# ===============================================
# Source external function files
# ===============================================

# Define a lazy loading function for show_local_site_links
# This approach only loads the function when needed and handles missing files gracefully
show_local_site_links() {
    # Get the directory of the current script for relative path resolution
    # Use bash built-in parameter expansion instead of dirname command for better compatibility
    local SCRIPT_DIR="${BASH_SOURCE[0]%/*}"
    if [[ "$SCRIPT_DIR" == "${BASH_SOURCE[0]}" ]]; then
        SCRIPT_DIR="."
    fi
    SCRIPT_DIR="$(cd "$SCRIPT_DIR" && pwd)"
    local LINKS_SCRIPT="$SCRIPT_DIR/show_local_site_links.sh"

    # Try multiple possible locations for the show_local_site_links.sh file
    local possible_locations=(
        "$SCRIPT_DIR/show_local_site_links.sh"
        "$HOME/wp-db-import-and-domain-replacement-tool/show_local_site_links.sh"
        "${BASH_SOURCE[0]%/*}/show_local_site_links.sh"
    )

    local found_script=""
    for location in "${possible_locations[@]}"; do
        if [[ -f "$location" ]]; then
            found_script="$location"
            break
        fi
    done

    if [[ -n "$found_script" ]]; then
        # Source the actual function and replace this placeholder
        if source "$found_script" 2>/dev/null; then
            # Call the real function now that it's loaded
            show_local_site_links "$@"
        else
            # Fallback if sourcing fails
            printf "\033[1;33m⚠️ Could not load show_local_site_links.sh properly.\033[0m\n"
            printf "\033[1;33m💡 You can manually access your WordPress sites using the configured domains.\033[0m\n"
        fi
    else
        printf "\033[0;31m❌ Error: show_local_site_links.sh not found.\033[0m\n"
        printf "\033[1;33m💡 Tried locations:\033[0m\n"
        for location in "${possible_locations[@]}"; do
            printf "    - %s\n" "$location"
        done
        printf "\033[1;33m💡 Please ensure show_local_site_links.sh is available in one of these locations.\033[0m\n"
        return 1
    fi
}

# ===============================================
# import_wp_db() function definition
# ===============================================
import_wp_db() {
  # 🎨 Define colors locally for use within the function scope
  local GREEN="\033[0;32m"
  local YELLOW="\033[1;33m"
  local RED="\033[0;31m"
  local CYAN="\033[0;36m"
  local BOLD="\033[1m"
  local RESET="\033[0m"

  # Determine absolute path to WP-CLI for robust execution in subshells
  local WP_COMMAND
  WP_COMMAND=$(command -v wp)

  if [[ -z "$WP_COMMAND" ]]; then
    printf "${RED}❌ WP-CLI not found in PATH. Exiting.${RESET}\n"
    return 1
  fi

  # ⚙️ HELPER FUNCTION: Safely execute WP-CLI commands
  # Ensures common environment variables and paths are set for reliable execution.
  execute_wp_cli() {
      # Arguments: WP-CLI command parts (e.g., core is-installed)
      # Execution environment: Export a robust PATH and run the command
      (
          # Prepend common paths (Homebrew, /usr/local) to the current PATH
          export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
          # Disable OPcache warnings that can interfere with output parsing
          export PHP_INI_SCAN_DIR=""
          # Execute the command passed as arguments
          "$WP_COMMAND" "$@"
      )
  }

  # Utility function to clean strings (removes leading/trailing whitespace/CR/LF)
  clean_string() {
      local s="$1"
      # Only remove carriage returns and newlines - keep it simple
      s="${s//$'\r'/}"
      s="${s//$'\n'/}"
      # Use printf to naturally trim and return
      printf "%s" "$s"
  }
  # 🧹 Define and set up cleanup for temporary log and data files
  local DB_LOG="/tmp/wp_db_import_$$.log"
  local SR_LOG_SINGLE="/tmp/wp_replace_single_$$.log"
  local REVISION_LOG="/tmp/wp_revision_delete_$$.log"
  local SUBSITE_DATA="/tmp/wp_subsite_data_$$.csv" # Temporary file to store subsite CSV data from WP-CLI

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

  # 🌀 Spinner function with elapsed time for long operations
  show_spinner() {
    local pid=$1
    local message=$2
    local delay=0.15
    local spin='|/-\'
    local start_time=$(date +%s)

    printf "  %s " "$message"
    while ps -p "$pid" > /dev/null 2>&1; do
      for i in $(seq 0 3); do
        local current_time=$(date +%s)
        local elapsed=$((current_time - start_time))
        local minutes=$((elapsed / 60))
        local seconds=$((elapsed % 60))

        printf "\r  %s ${CYAN}%s${RESET} (%02d:%02d)" "$message" "${spin:$i:1}" "$minutes" "$seconds"
        sleep $delay
      done
    done
    printf "\r"
    printf "%s" "                                                                                                   " # Clear the line
    printf "\r"
  }

  printf "\n${CYAN}${BOLD}🔧 WordPress Database Import & Domain Replace Tool${RESET}\n"
  printf "---------------------------------------------------\n\n"

  # 🧩 Prompt for SQL file name
  local sql_file
  printf "📦 Enter SQL file name (default: vip-db.sql): "
  read -r sql_file
  sql_file=${sql_file:-vip-db.sql}

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
  printf "${GREEN}✅ WordPress root found:${RESET} %s\n\n" "$wp_root"

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

  printf "${GREEN}✅ Found SQL file:${RESET} %s\n\n" "$sql_file"

  # 🌐 Get the main domain mapping (Source/Search and Destination/Replace)
  local search_domain replace_domain confirm

  # Get OLD (production/source) domain - mandatory input
  while true; do
    printf "🌍 Enter the OLD (production) domain to search for: "
    read -r search_domain

    if [[ -n "$search_domain" ]]; then
      break
    else
      printf "${YELLOW}⚠️  Production domain is required. Please enter a value.${RESET}\n"
    fi
  done

  # Get NEW (local/destination) domain - mandatory input
  while true; do
    printf "🏠 Enter the NEW (local) domain/base URL to replace with: "
    read -r replace_domain

    if [[ -n "$replace_domain" ]]; then
      break
    else
      printf "${YELLOW}⚠️  Local domain is required. Please enter a value.${RESET}\n"
    fi
  done

  printf "\n"

  # 🧹 Sanitize domain inputs (remove protocols and trailing slashes)
  sanitize_domain() {
    local domain="$1"

    # Handle empty input
    if [[ -z "$domain" ]]; then
      echo ""
      return 0
    fi

    # Remove http:// and https:// protocols
    domain="${domain#http://}"
    domain="${domain#https://}"

    # Remove any leading/trailing whitespace using bash built-ins
    # This is more reliable than sed and doesn't depend on external commands
    while [[ "$domain" =~ ^[[:space:]] ]]; do
      domain="${domain#[[:space:]]}"
    done
    while [[ "$domain" =~ [[:space:]]$ ]]; do
      domain="${domain%[[:space:]]}"
    done

    # Remove trailing slash
    domain="${domain%/}"

    echo "$domain"
  }

  # Apply sanitization to both domains
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
  printf "Proceed with database import? (Y/n): "
  read -r confirm
  confirm="${confirm:-y}"
  [[ "$confirm" != [Yy]* ]] && { printf "${YELLOW}⚠️ Operation cancelled.${RESET}\n"; return 0; }

  # 📥 Import the database using WP-CLI (with a spinner)
  printf "\n${CYAN}⏳ Importing database...${RESET}\n"
  local import_start_time=$(date +%s)
  # Ensure the environment PATH is robust for the db import subshell
  /bin/sh -c "(export PATH=\"/opt/homebrew/bin:/usr/local/bin:$PATH\"; \"$WP_COMMAND\" db import \"$sql_file\") &> \"$DB_LOG\"" &
  local spinner_pid=$!
  show_spinner $spinner_pid "Importing"
  wait $spinner_pid

  if [[ $? -ne 0 ]]; then
    printf "${RED}❌ Database import failed. Check %s for details.${RESET}\n" "$DB_LOG"
    return 1
  fi

  # Calculate elapsed time
  local import_end_time=$(date +%s)
  local import_elapsed=$((import_end_time - import_start_time))
  local import_minutes=$((import_elapsed / 60))
  local import_seconds=$((import_elapsed % 60))

  printf "${GREEN}✅ Database import successful! ${CYAN}[Completed in %02d:%02d]${RESET}\n\n" "$import_minutes" "$import_seconds"

  # 🧩 Enhanced multisite detection logic (Post-import database introspection using multiple methods)
  printf "${CYAN}🔍 Checking WordPress installation type...${RESET}\n"

  # Method 1: Direct database queries (most reliable after import)
  local is_multisite_db table_count blog_count site_count
  local multisite_type=""
  local network_flag=""

  # Check if wp_blogs table exists and has multiple entries
  blog_count=$(execute_wp_cli db query "SELECT COUNT(*) FROM wp_blogs;" --skip-column-names --silent 2>/dev/null || echo "0")
  site_count=$(execute_wp_cli db query "SELECT COUNT(*) FROM wp_site;" --skip-column-names --silent 2>/dev/null || echo "0")

  # Method 2: Check wp-config.php constants (fallback for local environment)
  local multisite_config=""
  if [[ -f "wp-config.php" ]]; then
    # Check for MULTISITE constant in wp-config.php
    if grep -q "define.*MULTISITE.*true" wp-config.php 2>/dev/null; then
      multisite_config="yes"
    elif grep -q "define.*('MULTISITE'.*true" wp-config.php 2>/dev/null; then
      multisite_config="yes"
    elif grep -q 'define.*("MULTISITE".*true' wp-config.php 2>/dev/null; then
      multisite_config="yes"
    fi
  fi

  # Method 3: WP-CLI eval without URL constraint (most compatible)
  local is_multisite_wp=""
  is_multisite_wp=$(execute_wp_cli eval 'echo is_multisite() ? "yes" : "no";' 2>/dev/null || echo "unknown")

  # Decision logic: Combine all methods for accuracy
  local is_multisite="no"

  # If database has multisite tables with data, it's definitely multisite
  if [[ "$blog_count" -gt 1 ]] || [[ "$site_count" -gt 0 ]]; then
    is_multisite="yes"
    printf "${GREEN}✅ Multisite detected via database analysis${RESET} (blogs: %s, sites: %s)\n" "$blog_count" "$site_count"
  # If wp-config.php shows MULTISITE constant, trust it
  elif [[ "$multisite_config" == "yes" ]]; then
    is_multisite="yes"
    printf "${GREEN}✅ Multisite detected via wp-config.php constants${RESET}\n"
  # If WP-CLI can determine it, use that
  elif [[ "$is_multisite_wp" == "yes" ]]; then
    is_multisite="yes"
    printf "${GREEN}✅ Multisite detected via WP-CLI evaluation${RESET}\n"
  else
    is_multisite="no"
    printf "${GREEN}✅ Single site installation detected${RESET}\n"
  fi

  # Determine multisite type if it's multisite
  if [[ "$is_multisite" == "yes" ]]; then
    network_flag="--network"
    multisite_type="subdomain" && printf "\n" # Placeholder; further analysis needed for subdirectory, but subdomain is a common default
  else
    printf "${GREEN}✅ Multisite status:${RESET} no\n"
  fi

  printf "\n"

  # 🗑️ Prompt for revision cleanup
  local cleanup_revisions
  printf "Clear ALL post revisions? (improves search-replace speed) (Y/n): "
  read -r cleanup_revisions
  cleanup_revisions="${cleanup_revisions:-y}"

  if [[ "$cleanup_revisions" =~ ^[Yy]$ ]]; then
    printf "${CYAN}🗑️ Clearing ALL Post Revisions (improves search-replace speed)...${RESET}\n"

  # Function to perform revision cleanup silently and quickly
  clean_revisions_silent() {
    # Description: Deletes all post revisions for the current site or a specified subsite.
    # It uses 'wp post list' piped to 'xargs wp post delete' for high-speed, reliable bulk operation,
    # bypassing Bash's word-splitting limitations.
    # Arguments:
    #   $1 (optional, string): The --url parameter for a specific multisite subsite.
    # Returns:
    #   0 on successful deletion (or if no revisions found).
    #   1 on failure or if revisions remain after the operation.
    local url_param="$1"
    local wp_cli_args
    local revision_ids_output
    local revision_count_before
    local delete_success=0

    # 1. --- Revision ID Retrieval ---
    # Construct the base command to list all revision IDs.
    if [[ -n "$url_param" ]]; then
      wp_cli_args=("post" "list" "--post_type=revision" "--format=ids" "--url=$url_param")
    else
      wp_cli_args=("post" "list" "--post_type=revision" "--format=ids")
      # Only add network flag if it's not empty (i.e., for multisite)
      if [[ -n "$network_flag" ]]; then
        wp_cli_args+=("$network_flag")
      fi
    fi

    # Execute the command and capture IDs.
    revision_ids_output=$(execute_wp_cli "${wp_cli_args[@]}" 2>/dev/null)
    local trimmed_output
    # Remove all carriage returns and newlines to get a single space-separated string of IDs.
    trimmed_output=$(echo "$revision_ids_output" | tr -d '\r\n')

    if [[ -z "$trimmed_output" ]]; then
        printf "${YELLOW}ℹ️ No revisions found${RESET}\n"
        return 0
    fi

    # Count IDs for verification and logging.
    revision_count_before=$(echo "$trimmed_output" | wc -w | tr -d ' ')

    printf "${CYAN}   Revisions found: %s${RESET}\n" "$revision_count_before"

    local xargs_command_output
    local xargs_exit_code

    # 2. --- Bulk Deletion via xargs ---
    # Construct arguments specific to the delete command.
    local wp_args=("--force")
    if [[ -n "$url_param" ]]; then
        wp_args+=("--url=$url_param")
    else
        # Only add network flag if it's not empty (i.e., for multisite)
        if [[ -n "$network_flag" ]]; then
          wp_args+=("$network_flag")
        fi
    fi

    # Use xargs to pipeline the list of IDs, calling 'wp post delete' in batches of 500.
    # This bypasses Bash array splitting issues and is highly performant.
    xargs_command_output=$(
        echo "$trimmed_output" | xargs -r -n 500 "$WP_COMMAND" post delete "${wp_args[@]}" 2>&1
    )
    xargs_exit_code=$?

    # Check for execution success. WP-CLI may report success even if not all rows were deleted,
    # so we rely on the verification step.
    if [[ $xargs_exit_code -eq 0 ]]; then
        printf "  ${GREEN}✅ Revisions deleted (WP-CLI reported success)${RESET}\n"
        delete_success=1
    else
        printf "  ${RED}❌ Failed to execute BULK deletion (xargs Exit Code %s)${RESET}\n" "$xargs_exit_code"
        return 1
    fi

    # 3. --- Verification Step ---
    local revisions_after
    # Check the remaining revision count by executing wp post list again.
    # Use the same command structure as the initial revision retrieval for consistency
    local verify_wp_cli_args
    if [[ -n "$url_param" ]]; then
      verify_wp_cli_args=("post" "list" "--post_type=revision" "--format=ids" "--url=$url_param")
    else
      verify_wp_cli_args=("post" "list" "--post_type=revision" "--format=ids")
      # Only add network flag if it's not empty (i.e., for multisite)
      if [[ -n "$network_flag" ]]; then
        verify_wp_cli_args+=("$network_flag")
      fi
    fi

    local verify_output
    verify_output=$(execute_wp_cli "${verify_wp_cli_args[@]}" 2>/dev/null)
    revisions_after=$(echo "$verify_output" | wc -w | tr -d ' ')
    revisions_after="${revisions_after:-0}"

    # Final check for total success
    if [[ "$revisions_after" -eq 0 ]]; then
        return 0
    else
        printf "${RED}⚠️ WARNING: %s revisions remain in the database after bulk attempt.${RESET}\n" "$revisions_after"
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
        clean_revisions_silent "$site_url"
        printf "\n"
        ((site_counter++))
      fi
    done <<< "$site_urls"
  else
    printf "${CYAN}🧩 SINGLE SITE DETECTED - Processing main site only...${RESET}\n"
    printf "  ${YELLOW}Step A:${RESET} Processing revisions for the main site\n\n"
    printf "  ${CYAN}🌍 Processing Main Site${RESET}\n"
    printf "  "
    clean_revisions_silent ""
    printf "\n"
  fi

  printf "\n"
  else
    printf "${YELLOW}⏭️  Skipping revision cleanup as requested.${RESET}\n\n"
  fi

  # ⚙️ Prompt to include --all-tables flag
  local include_all all_tables_flag
  printf "Include ${BOLD}--all-tables${RESET} (recommended for full DB imports)? (Y/n): "
  read -r include_all
  include_all="${include_all:-y}"
  all_tables_flag=""
  if [[ "$include_all" =~ ^[Yy]$ ]]; then
    all_tables_flag="--all-tables"
    printf "${GREEN}✅ Will include all tables.${RESET}\n"
  else
    printf "${YELLOW}ℹ️ Limiting to WordPress tables only.${RESET}\n"
  fi

  # ⚙️ Prompt for dry-run mode
  local dry_run dry_run_flag
  printf "\n"
  printf "Run in ${BOLD}dry-run mode${RESET} (no data will be changed)? (y/N): "
  read -r dry_run
  dry_run="${dry_run:-n}"
  dry_run_flag=""
  if [[ "$dry_run" =~ ^[Yy]$ ]]; then
    dry_run_flag="--dry-run"
    printf "${YELLOW}🧪 Running in dry-run mode (preview only).${RESET}\n\n"
  else
    printf "${GREEN}🚀 Running in live mode (changes will be applied).${RESET}\n\n"
  fi

  # --- Search-Replace Execution Function (Handles Double Pass with Domain+Path Logic) ---
  #
  # This function executes the critical two-pass search-replace operation.
  # It intelligently handles domain+path combinations from the wp_blogs table,
  # ensuring correct slash handling for both source and destination URLs in serialized data.
  #
  # Key Features:
  # - Searches for domain+path as per wp_blogs table structure.
  # - Conditional slash handling: ensures consistency between source and destination formats.
  # - Maintains compatibility for single-site and simple domain-only replacements.
  # - Supports both subdomain and subdirectory multisite configurations.
  #
  # Arguments: $1=old_domain $2=new_domain $3=log_file $4=url_flag $5=old_path (optional) $6=new_path (optional)
  run_search_replace() {
      local old_domain="$1"
      local new_domain="$2"
      local log_file="$3"
      local url_flag="$4" # --url=... or empty
      local old_path="${5:-}"  # Optional path from wp_blogs table
      local new_path="${6:-}"  # Optional new path

      # Validate inputs
      if [[ -z "$old_domain" || -z "$new_domain" ]]; then
          printf "Error: Missing domain parameters\n" >&2
          return 1
      fi

      # Enhanced domain+path construction with intelligent slash handling
      local search_domain_with_path="$old_domain"
      local replace_domain_with_path="$new_domain"

      # CRITICAL LOGIC: Only apply path handling in a multisite context with non-root paths.
      # Path logic should only execute when:
      # 1. Paths are provided AND meaningful (not just "/")
      # 2. We're in a multisite context (indicated by --url flag)
      local is_multisite_context=false
      if [[ "$url_flag" == *"--url="* ]]; then
          is_multisite_context=true
      fi

      # If paths are provided, meaningful, AND we're in multisite context, construct domain+path combinations
      # Note: For multisite, main site path is "/" while subsites have paths like "/subsite/"
      if [[ -n "$old_path" && "$old_path" != "/" && "$is_multisite_context" == true ]]; then
          # Remove leading and trailing slashes from paths for clean handling
          local clean_old_path="${old_path#/}"
          clean_old_path="${clean_old_path%/}"
          local clean_new_path="${new_path#/}"
          clean_new_path="${clean_new_path%/}"

          # Clean destination domain of trailing slash for proper concatenation
          local clean_new_domain="${new_domain%/}"

          # Determine if destination should have trailing slash based on original new_domain format
          local dest_has_trailing_slash=false
          if [[ "$new_domain" =~ /$ ]]; then
              dest_has_trailing_slash=true
          fi

          # Construct source domain+path with conditional trailing slash
          if [[ "$dest_has_trailing_slash" == true ]]; then
              # If destination has slash, add slash to source
              search_domain_with_path="${old_domain}/${clean_old_path}/"
          else
              # If destination has no slash, don't add slash to source
              search_domain_with_path="${old_domain}/${clean_old_path}"
          fi

          # Construct replace domain+path - preserve destination format
          if [[ -n "$clean_new_path" ]]; then
              if [[ "$dest_has_trailing_slash" == true ]]; then
                  replace_domain_with_path="${clean_new_domain}/${clean_new_path}/"
              else
                  replace_domain_with_path="${clean_new_domain}/${clean_new_path}"
              fi
          else
              # If new_path is empty or just "/", use the new_domain with proper slash handling
              if [[ "$dest_has_trailing_slash" == true ]]; then
                  replace_domain_with_path="${clean_new_domain}/"
              else
                  replace_domain_with_path="$clean_new_domain"
              fi
          fi
      else
          # For main sites (path="/") or when no path info available, use domain-only replacement
          # Apply destination slash logic to domain-only replacements as well
          local clean_old_domain="${old_domain%/}"  # Remove any existing trailing slash
          local dest_has_trailing_slash=false
          if [[ "$new_domain" =~ /$ ]]; then
              dest_has_trailing_slash=true
          fi

          if [[ "$dest_has_trailing_slash" == true ]]; then
              # If destination domain has trailing slash, add to source for consistency
              search_domain_with_path="${clean_old_domain}/"
              replace_domain_with_path="${new_domain}"  # Use as-is since it already has the slash
          else
              # No trailing slash needed
              search_domain_with_path="$clean_old_domain"
              replace_domain_with_path="$new_domain"
          fi
      fi

      # Enhanced www/non-www handling - determine source domain variations
      local base_domain_with_path="$search_domain_with_path"
      local www_domain_with_path
      local non_www_domain_with_path
      local has_www=false

      # Check if the search domain starts with www
      if [[ "$search_domain_with_path" =~ ^www\. ]]; then
          # Source is www.domain - create non-www variant
          www_domain_with_path="$search_domain_with_path"
          non_www_domain_with_path="${search_domain_with_path#www.}"
          has_www=true
      else
          # Source is non-www domain - only handle non-www variant
          non_www_domain_with_path="$search_domain_with_path"
          www_domain_with_path="www.${search_domain_with_path}"
          has_www=false
      fi

      # Define search-replace patterns
      local sr1_old_non_www="//${non_www_domain_with_path}"
      local sr2_old_non_www="\\\\//${non_www_domain_with_path}"
      local sr_new="//${replace_domain_with_path}"
      local sr_new_escaped="\\\\//${replace_domain_with_path}"

      # Only define www patterns if source has www
      local sr1_old_www
      local sr2_old_www
      if [[ "$has_www" == true ]]; then
          sr1_old_www="//${www_domain_with_path}"
          sr2_old_www="\\\\//${www_domain_with_path}"
      fi

      # --- Pass 1 Execution (Standard replacement for non-www variant - always executed) ---
      printf "[Pass 1] Updating standard domain URLs: ${YELLOW}%s${RESET} → ${GREEN}%s${RESET}\n" "$sr1_old_non_www" "$sr_new"

      # Build the command array to avoid word splitting issues
      local cmd_args=("search-replace" "$sr1_old_non_www" "$sr_new")

      if [[ -n "$url_flag" ]]; then
          cmd_args+=("$url_flag")
      fi

      cmd_args+=("--skip-columns=guid" "--report-changed-only" "--skip-plugins" "--skip-themes" "--skip-packages")

      if [[ -n "$all_tables_flag" ]]; then
          cmd_args+=("$all_tables_flag")
      fi

      if [[ -n "$network_flag" ]]; then
          cmd_args+=("$network_flag")
      fi

      if [[ -n "$dry_run_flag" ]]; then
          cmd_args+=("$dry_run_flag")
      fi

      # Execute Pass 1 (non-www variant - always executed)
      if ! execute_wp_cli "${cmd_args[@]}" &> "$log_file"; then
          return 1
      fi

      # --- Pass 2 Execution (Standard replacement for www variant - only if source has www) ---
      if [[ "$has_www" == true ]]; then
          printf "[Pass 3] Updating standard domain URLs (www): ${YELLOW}%s${RESET} → ${GREEN}%s${RESET}\n" "$sr1_old_www" "$sr_new"

          # Rebuild command args for pass 2 (www variant)
          cmd_args=("search-replace" "$sr1_old_www" "$sr_new")

          if [[ -n "$url_flag" ]]; then
              cmd_args+=("$url_flag")
          fi

          cmd_args+=("--skip-columns=guid" "--report-changed-only" "--skip-plugins" "--skip-themes" "--skip-packages")

          if [[ -n "$all_tables_flag" ]]; then
              cmd_args+=("$all_tables_flag")
          fi

          if [[ -n "$network_flag" ]]; then
              cmd_args+=("$network_flag")
          fi

          if [[ -n "$dry_run_flag" ]]; then
              cmd_args+=("$dry_run_flag")
          fi

          # Execute Pass 2 (www variant)
          if ! execute_wp_cli "${cmd_args[@]}" >> "$log_file" 2>&1; then
              return 1
          fi
      fi

      # --- Serialized Data Pass Execution (Conditional numbering based on www presence) ---
      local serialized_pass_num
      if [[ "$has_www" == true ]]; then
          serialized_pass_num="2"
      else
          serialized_pass_num="2"
      fi

      # --- Serialized data repair for non-www variant (always executed) ---
      printf "[Pass %s] Updating serialized domain URLs: ${YELLOW}%s${RESET} → ${GREEN}%s${RESET}\n" "$serialized_pass_num" "$sr2_old_non_www" "$sr_new_escaped"

      # Rebuild command args for serialized non-www variant
      cmd_args=("search-replace" "$sr2_old_non_www" "$sr_new_escaped")

      if [[ -n "$url_flag" ]]; then
          cmd_args+=("$url_flag")
      fi

      cmd_args+=("--skip-columns=guid" "--report-changed-only" "--skip-plugins" "--skip-themes" "--skip-packages")

      if [[ -n "$all_tables_flag" ]]; then
          cmd_args+=("$all_tables_flag")
      fi

      if [[ -n "$network_flag" ]]; then
          cmd_args+=("$network_flag")
      fi

      if [[ -n "$dry_run_flag" ]]; then
          cmd_args+=("$dry_run_flag")
      fi

      # Execute serialized non-www variant
      if ! execute_wp_cli "${cmd_args[@]}" >> "$log_file" 2>&1; then
          return 1
      fi

      # --- Final Pass Execution (Serialized data repair for www variant - only if source has www) ---
      if [[ "$has_www" == true ]]; then
          printf "[Pass 4] Updating serialized domain URLs (www): ${YELLOW}%s${RESET} → ${GREEN}%s${RESET}\n" "$sr2_old_www" "$sr_new_escaped"

          # Rebuild command args for serialized www variant
          cmd_args=("search-replace" "$sr2_old_www" "$sr_new_escaped")

          if [[ -n "$url_flag" ]]; then
              cmd_args+=("$url_flag")
          fi

          cmd_args+=("--skip-columns=guid" "--report-changed-only" "--skip-plugins" "--skip-themes" "--skip-packages")

          if [[ -n "$all_tables_flag" ]]; then
              cmd_args+=("$all_tables_flag")
          fi

          if [[ -n "$network_flag" ]]; then
              cmd_args+=("$network_flag")
          fi

          if [[ -n "$dry_run_flag" ]]; then
              cmd_args+=("$dry_run_flag")
          fi

          # Execute serialized www variant
          if ! execute_wp_cli "${cmd_args[@]}" >> "$log_file" 2>&1; then
              return 1
          fi
      fi

      return 0
  }

  # 🌐 Handle Multisite (Logic for site list, mapping, and per-site replacement)
  if [[ "$is_multisite" == "yes" ]]; then

      local confirm_replace
      printf "${CYAN}🌐 Multisite (%s) detected — gathering subsites for mapping...${RESET}\n\n" "$multisite_type"

      # --- Data Retrieval ---
      # Retrieve site data (ID, domain, path) in CSV format for later parsing
      execute_wp_cli site list --fields=blog_id,domain,path --format=csv --url="$search_domain" 2>"$REVISION_LOG" > "$SUBSITE_DATA"

      # 🔍 Main Site ID Detection Block (Robustly determines the main site's Blog ID)
      local main_site_id
      local temp_min_blog_id=999999 # Initialize with a large number
      local found_main_by_path="" # ID of the site with path='/'

      # Read the CSV data using a simple and reliable method
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

              # Parse for ID and Path
              IFS=, read -r blog_id domain site_path <<< "$line"
              local clean_blog_id=$(clean_string "$blog_id")
              local clean_site_path=$(clean_string "$site_path")

              # Condition 1: Find the lowest blog ID
              if [[ "$clean_blog_id" -lt "$temp_min_blog_id" ]]; then
                  temp_min_blog_id="$clean_blog_id"
              fi

              # Condition 2: Find the site with path ONLY "/"
              if [[ "$clean_site_path" == "/" ]]; then
                  # We prefer the lowest ID with path '/' if multiple exist, though typically only one should.
                  if [[ -z "$found_main_by_path" || "$clean_blog_id" -lt "$found_main_by_path" ]]; then
                      found_main_by_path="$clean_blog_id"
                  fi
              fi
          fi
      done < "$SUBSITE_DATA"

      # Assign the Main Site ID (prefer path match, then lowest ID, then fallback to 1)
      if [[ -n "$found_main_by_path" ]]; then
          main_site_id="$found_main_by_path"
      elif [[ "$temp_min_blog_id" -ne 999999 ]]; then
          main_site_id="$temp_min_blog_id"
      else
          main_site_id="1" # Safest default
      fi
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
        printf "${YELLOW}⚠️ WP-CLI command succeeded but returned empty output${RESET}\n"
      else
        printf "%s\n" "$site_list" | column -t -s $'\t'
      fi
      printf "\n"

      # Determine if multisite is subdirectory or subdomain (affects search-replace logic)
      if [[ "$multisite_type" == "subdirectory" ]]; then
          # For subdirectory multisite: All sites share the same domain
          printf "${CYAN}🏠 Subdirectory Multisite Detected${RESET}\n"
          printf "All subsites share the same domain. Only one network-wide search-replace operation is required.\n\n"

          printf "🌍 Enter the NEW domain for all sites:\n"
          printf "→ Replace '%s' with: (%s) " "$search_domain" "$replace_domain"
          read -r network_domain
          network_domain="${network_domain:-$replace_domain}"

          # Sanitize the input
          local original_network_domain="$network_domain"
          network_domain=$(sanitize_domain "$network_domain")
          if [[ "$original_network_domain" != "$network_domain" ]]; then
              printf "    ${YELLOW}🧹 Cleaned: '%s' → '%s'${RESET}\n" "$original_network_domain" "$network_domain"
          fi

          printf "\n🧾 ${BOLD}Domain mapping summary:${RESET}\n"
          printf "    🔁 %s → ${GREEN}%s${RESET} (Network-wide)\n" "$search_domain" "$network_domain"

          printf "\nProceed with network-wide search-replace? (Y/n): "
          read -r confirm_replace
          confirm_replace="${confirm_replace:-y}"
          [[ "$confirm_replace" != [Yy]* ]] && { printf "${YELLOW}⚠️ Operation cancelled.${RESET}\n"; return 0; }

          printf "\n${CYAN}🔄 Starting network-wide search-replace...${RESET}\n"

          # For subdirectory multisite, run search-replace using the main domain/network-flag
          if run_search_replace "$search_domain" "$network_domain" "$SR_LOG_SINGLE" ""; then
              printf "\n${GREEN}✅ Network-wide search-replace completed successfully!${RESET}\n"
          else
              printf "\n${RED}❌ Network-wide search-replace failed. See %s.${RESET}\n" "$SR_LOG_SINGLE"
              return 1
          fi

          # Store network domain for MySQL command generation
          domain_keys=("$search_domain")
          domain_values=("$network_domain")

      else
          # For subdomain multisite: Handle individual site mappings (Interactive mapping logic)
          printf "${CYAN}🌐 Subdomain Multisite Detected${RESET}\n"
          printf "Each subsite has its own domain. Individual mapping input is required.\n\n"

          # Use parallel arrays to store mappings (more compatible than associative arrays)
          local domain_keys=()
          local domain_values=()
          local domain_blog_ids=() # Array to track blog IDs
          local domain_paths=() # Array to track paths from wp_blogs

          printf "${BOLD}Enter the NEW URL/Domain for each site:${RESET}\n"
          printf "(Example: Map 'sub1.example.com' to 'sub1.example.local')\n\n"

          local blog_id domain path local_domain mapped cleaned_domain
          local processed_count=0

          # --- Interactive Mapping Loop ---
          for subsite_line in "${subsite_lines[@]}"; do
            processed_count=$((processed_count + 1))

            if [[ "$subsite_line" == "blog_id,domain,path" ]]; then
                continue
            fi

            # Skip empty lines
            if [[ -z "$subsite_line" ]]; then
                continue
            fi

            # Read the CSV elements from the array element
            IFS=, read -r blog_id domain site_path <<< "$subsite_line"

            cleaned_domain=$(clean_string "$domain")
            local clean_blog_id=$(clean_string "$blog_id")
            local clean_site_path=$(clean_string "$site_path")

            # Skip if domain is empty after cleaning
            if [[ -z "$cleaned_domain" ]]; then
                continue
            fi

            # Debug output for domain processing
            printf "\n"
            printf "  ${CYAN}Processing:${RESET} Blog ID %s, Domain: '%s', Path: '%s'\n" "$clean_blog_id" "$cleaned_domain" "$clean_site_path"

            # For the main site (dynamic ID), default to the global replace_domain
            if [[ "$clean_blog_id" == "$main_site_id" ]]; then
                printf "→ Local URL for '%s' (Blog ID %s): (%s) " "$cleaned_domain" "$main_site_id" "$replace_domain"
                read -r local_domain
                # Use default if empty
                local_domain="${local_domain:-$replace_domain}"
            else
                # For subsites, prompt the user clearly
                printf "→ Local URL for '%s' (Blog ID %s): " "$cleaned_domain" "$clean_blog_id"
                read -r local_domain
                # Use default if empty
                local_domain="${local_domain:-$cleaned_domain}"
            fi

            # 🧹 Sanitize the local domain input (remove protocols, trailing slashes, whitespace)
            if [[ -n "$local_domain" ]]; then
                local original_local_domain="$local_domain"
                local_domain=$(sanitize_domain "$local_domain")

                # Show what was cleaned up if changes were made
                if [[ "$original_local_domain" != "$local_domain" ]]; then
                    printf "    ${YELLOW}🧹 Cleaned: '%s' → '%s'${RESET}\n" "$original_local_domain" "$local_domain"
                fi
            fi

            # Add to arrays with validation - SINGLE POINT OF ADDITION
            if [[ -n "$cleaned_domain" && -n "$local_domain" ]]; then
                # For multisite, multiple sites can have the same domain with different paths
                # This is normal behavior, so we don't need to prevent "duplicates" here
                domain_keys+=("$cleaned_domain")
                domain_values+=("$local_domain")
                domain_blog_ids+=("$clean_blog_id") # Store the blog ID
                domain_paths+=("$clean_site_path") # Store the path from wp_blogs
                printf "  ${GREEN}✅ Added mapping:${RESET} '%s' → '%s' (ID: %s, Path: %s)\n" "$cleaned_domain" "$local_domain" "$clean_blog_id" "$clean_site_path"
            else
                printf "  ${RED}❌ Skipped invalid mapping:${RESET} domain='%s', local='%s'\n" "$cleaned_domain" "$local_domain"
            fi

          done

          # Clean up arrays - remove any empty elements using a more robust approach
          local clean_domain_keys=()
          local clean_domain_values=()
          local clean_domain_blog_ids=()
          local clean_domain_paths=()
          local domain_display_names=()  # Store exact display names from summary
          local original_length=${#domain_keys[@]}

          for ((i=1; i<=original_length; i++)); do
            local key="${domain_keys[i]}"
            local value="${domain_values[i]}"
            local id="${domain_blog_ids[i]}" # Get blog ID
            local site_path_var="${domain_paths[i]}" # Get path

            if [[ -n "$key" && -n "$value" && -n "$id" ]]; then
              clean_domain_keys+=("$key")
              clean_domain_values+=("$value")
              clean_domain_blog_ids+=("$id") # Store clean blog ID
              clean_domain_paths+=("$site_path_var") # Store clean path
              domain_display_names+=("${key}${site_path_var}") # Store exact display name
            fi
          done

          # Replace the original arrays
          unset domain_keys domain_values domain_blog_ids domain_paths
          domain_keys=("${clean_domain_keys[@]}")
          domain_values=("${clean_domain_values[@]}")
          domain_blog_ids=("${clean_domain_blog_ids[@]}") # Use clean blog ID array
          domain_paths=("${clean_domain_paths[@]}") # Use clean path array

          printf "\n🧾 ${BOLD}Domain mapping summary:${RESET}\n"

          # --- Summary Loop using parallel arrays ---
          local array_length=${#domain_keys[@]}

          for ((i=1; i<=array_length; i++)); do

            local key="${domain_keys[i]}"
            local value="${domain_values[i]}"
            local id="${domain_blog_ids[i]}"
            local site_path_var="${domain_paths[i]}"

            # Use simple and reliable trimming - just check the raw values
            if [[ -z "$value" ]]; then
              printf "    ❌ [ID: %s] %s%s → (no mapping found)\n" "$id" "$key" "$site_path_var"
            elif [[ "$key" == "$value" ]]; then
              printf "    ⏭️  [ID: %s] %s%s → (unchanged)\n" "$id" "$key" "$site_path_var"
            else
              printf "    🔁 [ID: %s] %s%s → ${GREEN}%s${RESET}\n" "$id" "$key" "$site_path_var" "$value"
            fi
          done

          printf "\n"
          printf "Proceed with search-replace for all sites? (Y/n): "
          read -r confirm_replace
          confirm_replace="${confirm_replace:-y}"
          [[ "$confirm_replace" != [Yy]* ]] && { printf "${YELLOW}⚠️ Operation cancelled.${RESET}\n"; return 0; }

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
            for ((i=1; i<=array_length; i++)); do
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
                for ((i=1; i<=array_length; i++)); do
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
            printf "${YELLOW}⚠️ Could not determine base domain - skipping automatic table updates${RESET}\n"
            local auto_updates_successful="no"
          fi

          local new_domain SR_LOG_MULTI
          local main_site_key=""
          local main_site_value=""
          local main_site_path=""

          # --- Execution Loop 1: Subsites (ID != main_site_id) ---
          local array_length=${#domain_keys[@]}
          for ((i=1; i<=array_length; i++)); do
            local cleaned_domain="${domain_keys[i]}"
            local new_domain="${domain_values[i]}"
            local blog_id="${domain_blog_ids[i]}"
            local site_path_var="${domain_paths[i]}"

            # Skip main site for now - store its data for later processing
            if [[ "$blog_id" == "$main_site_id" ]]; then
                main_site_key="$cleaned_domain"
                main_site_value="$new_domain"
                main_site_path="$site_path_var"
                printf "${YELLOW}  ⏸️  Skipping Main Site (ID %s) - will process last.${RESET}\n" "$main_site_id"
                continue
            fi

            if [[ -z "$new_domain" || "$cleaned_domain" == "$new_domain" ]]; then
              printf "${YELLOW}⏭️  Skipping '%s' (ID %s, no change).${RESET}\n" "$cleaned_domain" "$blog_id"
              continue
            fi

            SR_LOG_MULTI="/tmp/wp_replace_${blog_id}_$$.log"

            # Use the exact display name from summary to ensure consistency
            local display_old="${domain_display_names[i]}"
            printf "\n➡️  ${BOLD}Replacing for Site ID %s:${RESET} ${YELLOW}%s${RESET} → ${GREEN}%s${RESET}\n" "$blog_id" "$display_old" "$new_domain"

            # Use enhanced run_search_replace with path information
            # Pass the path from wp_blogs to enable domain+path replacement
            if run_search_replace "$cleaned_domain" "$new_domain" "$SR_LOG_MULTI" "--url=$cleaned_domain" "$site_path_var" ""; then
              printf "${GREEN}✅ Completed for %s (ID %s).${RESET}\n" "$display_old" "$blog_id"
            else
              printf "${RED}❌ Failed on %s (ID %s). Check %s for details.${RESET}\n" "$display_old" "$blog_id" "$SR_LOG_MULTI"
            fi
          done

          # --- Execution Loop 2: Main Site (ID = main_site_id) ---
          printf "\n${CYAN}  MAIN SITE REPLACEMENT (ID = %s)${RESET}\n" "$main_site_id"
          if [[ -n "$main_site_key" && "$main_site_key" != "$main_site_value" ]]; then
              local main_site_log="/tmp/wp_replace_${main_site_id}_$$.log"
              local main_display_old="${main_site_key}${main_site_path}"
              printf "\n➡️  ${BOLD}Replacing for Main Site ID %s:${RESET} ${YELLOW}%s${RESET} → ${GREEN}%s${RESET}\n" "$main_site_id" "$main_display_old" "$main_site_value"

              # Run main site search-replace with path information (using the main site's old domain in --url for safety)
              if run_search_replace "$main_site_key" "$main_site_value" "$main_site_log" "--url=$main_site_key" "$main_site_path" ""; then
                printf "${GREEN}✅ Completed for Main Site (ID %s).${RESET}\n" "$main_site_id"
              else
                printf "${RED}❌ Failed on Main Site (ID %s). Check %s for details.${RESET}\n" "$main_site_id" "$main_site_log"
              fi
          elif [[ -n "$main_site_key" ]]; then
              printf "${YELLOW}⏭️  Skipping Main Site (ID %s, no change).${RESET}\n" "$main_site_id"
          else
              printf "${RED}❌ Could not find Main Site mapping (ID %s) to process.${RESET}\n" "$main_site_id"
          fi

      fi  # End of subdirectory vs subdomain multisite logic

  else
    # 🧩 Single site logic
    printf "${CYAN}🧩 Single site detected.${RESET}\n"
    printf "Proceed with search-replace now? (Y/n): "
    read -r confirm_replace
    confirm_replace="${confirm_replace:-y}"
    [[ "$confirm_replace" != [Yy]* ]] && { printf "${YELLOW}⚠️ Operation cancelled.${RESET}\n"; return 0; }

    printf "\n🔁 Running search-replace operations...\n"

    # Execute search-replace for single site (Pass search_domain and replace_domain, with no --url flag)
    if run_search_replace "$search_domain" "$replace_domain" "$SR_LOG_SINGLE" ""; then
      printf "\n${GREEN}✅ Search-replace completed successfully!${RESET}\n"
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
      printf "${YELLOW}  ⚠️ Failed to flush object cache (Not always necessary/available).${RESET}\n"
  else
      printf "${GREEN}  ✅ Object cache flushed.${RESET}\n"
  fi

  # 2. Flush rewrite rules (hard flush for robust update)
  # Use execute_wp_cli for reliable command execution
  if ! execute_wp_cli rewrite flush --hard $network_flag &>/dev/null; then
      printf "${YELLOW}  ⚠️ Failed to flush rewrite rule (Not always necessary/available).${RESET}\n"
  else
      printf "${GREEN}  ✅ Rewrite rule flushed.${RESET}\n"
  fi

  # 3. Delete transients
  # Use execute_wp_cli for reliable command execution
  if ! execute_wp_cli transient delete --all $network_flag &>/dev/null; then
      printf "${YELLOW}  ⚠️ Transient deletion finished (No transients found or minor error).${RESET}\n"
  else
      printf "${GREEN}  ✅ All transients deleted.${RESET}\n"
  fi

  printf "\n${GREEN}${BOLD}🎉 All done!${RESET} Database import and replacements completed successfully.\n\n"

  # ✅ wp_blogs/wp_site tables updated earlier (before search-replace) - OLD LOGIC DISABLED
  if [[ "1" == "0" && "$is_multisite" == "yes" && ${#domain_keys[@]} -gt 0 ]]; then
    printf "\n${CYAN}${BOLD}🔧 Updating wp_blogs and wp_site tables automatically...${RESET}\n"
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
      for ((i=1; i<=array_length; i++)); do
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
      wp_eval_commands="${wp_eval_commands} echo '✅ wp_blogs and wp_site updated successfully.';"

      printf "\n${CYAN}⚡ Executing database updates...${RESET}\n"

      # Execute the wp eval command using the original search domain for --url parameter
      # This ensures WP-CLI can connect to the site before we update the domain tables
      local eval_log="/tmp/wp_eval_updates_$$.log"
      local eval_output eval_exit_code

      # Use the original search_domain (before replacement) to execute wp eval
      # This is crucial because after search-replace, the URLs are mixed and WP-CLI needs a valid reference point
      if [[ -n "$main_site_old_domain" ]]; then
        printf "${CYAN}   Using original domain for WP-CLI connection: %s${RESET}\n" "$main_site_old_domain"
        eval_output=$(execute_wp_cli eval "$wp_eval_commands" --url="$main_site_old_domain" 2>&1)
      else
        printf "${CYAN}   Using fallback domain for WP-CLI connection: %s${RESET}\n" "$search_domain"
        eval_output=$(execute_wp_cli eval "$wp_eval_commands" --url="$search_domain" 2>&1)
      fi
      eval_exit_code=$?

      if [[ $eval_exit_code -eq 0 ]]; then
        printf "${GREEN}✅ Database tables updated successfully!${RESET}\n"
        printf "${GREEN}   %s${RESET}\n" "$eval_output"

        # Set flag to indicate automatic updates were successful
        local auto_updates_successful="yes"
      else
        printf "${RED}❌ Failed to update database tables automatically${RESET}\n"
        printf "${RED}   Error: %s${RESET}\n\n" "$eval_output"
        printf "${YELLOW}💡 Falling back to manual MySQL commands...${RESET}\n\n"

        # Set flag to show manual commands as fallback
        local auto_updates_successful="no"
      fi

      # Clean up eval log
      rm -f "$eval_log" 2>/dev/null

    else
      printf "${YELLOW}⚠️ Could not determine base domain - falling back to manual MySQL commands${RESET}\n"
      local auto_updates_successful="no"
    fi
  fi

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
      printf "-- 1. Update wp_blogs table: blog domain and path for SUB-SITES (ID != %s)\n\n" "$main_site_id"

      # Generate commands for each mapped subsite domain
      local processed_blog_ids=() # Track processed blog_ids to prevent duplicates

      # --- Subsite Commands (ID != main_site_id) ---
      for ((i=1; i<=array_length; i++)); do
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
          printf "-- Skipping duplicate blog_id %s for domain %s\n" "$blog_id" "$old_domain"
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
          printf "-- WARNING: Main site mapping (ID %s) not found to generate wp_blogs command.\n" "$main_site_id"
      fi

      printf "\n-- 3. Update wp_site table: the main network site domain (ID = 1)\n"
      printf "UPDATE wp_site SET domain = '%s' WHERE id = 1;\n\n" "$base_domain"

      printf "\n================================================================\n"

      printf "\n${YELLOW}💡 Copy the above commands and paste them into phpMyAdmin → SQL command to execute.${RESET}\n"
    else
      printf "${YELLOW}⚠️ Could not generate MySQL commands - no base domain found.${RESET}\n"
    fi
  elif [[ "$is_multisite" != "yes" ]]; then
    printf "${GREEN}✅ Single site domain replacement completed via WP-CLI.${RESET}\n"
  fi

  printf "\n"

  # 🔍 Prompt for confirmation that MySQL commands have been executed (only if manual commands were shown)
  local sql_executed="y"
  if [[ "$is_multisite" == "yes" && ${#domain_keys[@]} -gt 0 && "${auto_updates_successful:-yes}" == "no" ]]; then
    printf "${CYAN}${BOLD}📋 MySQL Commands Confirmation${RESET}\n"
    printf "Have you executed the above MySQL commands in phpMyAdmin/database? (Y/n): "
    read -r sql_executed
    sql_executed="${sql_executed:-y}"

    if [[ "$sql_executed" != [Yy]* ]]; then
      printf "${YELLOW}⚠️ Please execute the MySQL commands first, to complete the setup.${RESET}\n"
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
    # Ask user if they want to setup stage file proxy for media management
    local setup_stage_proxy
    printf "${CYAN}${BOLD}📸 Stage File Proxy Setup${RESET}\n"
    printf "Do you want to setup the stage file proxy plugin for media management? (Y/n): "
    read -r setup_stage_proxy
    setup_stage_proxy="${setup_stage_proxy:-y}"

    if [[ "$setup_stage_proxy" == [Yy]* ]]; then
      # Check if stage-file-proxy plugin is already installed
      # Use execute_wp_cli for reliable command execution
      if execute_wp_cli plugin is-installed stage-file-proxy &>/dev/null; then
        printf "${CYAN}🔍 stage-file-proxy plugin found! Configuring...${RESET}\n"
      else
        # Install the plugin with enhanced error handling
        printf "${CYAN}📦 Installing stage-file-proxy plugin...${RESET}\n"

        # Create a temporary log for installation debugging
        local install_log="/tmp/wp_plugin_install_$$.log"
        local install_success=false

        # Method 1: Try installing from GitHub release
        printf "${CYAN}    Attempting installation from GitHub release...${RESET}\n"
        if execute_wp_cli plugin install https://github.com/manishsongirkar/stage-file-proxy/releases/download/101/stage-file-proxy.zip > "$install_log" 2>&1; then
          printf "${GREEN}✅ Plugin installed successfully from GitHub${RESET}\n"
          install_success=true
        else
          printf "${YELLOW}⚠️ GitHub installation failed, trying direct download method...${RESET}\n"

          # Method 2: Try direct download and install
          printf "${CYAN}    Attempting direct download method...${RESET}\n"
          local temp_plugin_file="/tmp/stage-file-proxy-$$.zip"

          # Try downloading with curl first, then wget as fallback
          if command -v curl &>/dev/null; then
            if curl -L -o "$temp_plugin_file" "https://github.com/manishsongirkar/stage-file-proxy/releases/download/101/stage-file-proxy.zip" >> "$install_log" 2>&1; then
              if execute_wp_cli plugin install "$temp_plugin_file" >> "$install_log" 2>&1; then
                printf "${GREEN}✅ Plugin installed successfully via direct download${RESET}\n"
                install_success=true
              fi
              rm -f "$temp_plugin_file" 2>/dev/null
            fi
          elif command -v wget &>/dev/null; then
            if wget -O "$temp_plugin_file" "https://github.com/manishsongirkar/stage-file-proxy/releases/download/101/stage-file-proxy.zip" >> "$install_log" 2>&1; then
              if execute_wp_cli plugin install "$temp_plugin_file" >> "$install_log" 2>&1; then
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
          if execute_wp_cli plugin is-installed stage-file-proxy &>/dev/null; then
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
            printf "   Last few lines from installation log:\n"
            local line_count=0
            local lines=()
            while IFS= read -r line; do
              lines+=("$line")
              ((line_count++))
            done < "$install_log"

            # Display last 5 lines or all lines if less than 5
            local start_index=$((line_count > 5 ? line_count - 5 : 0))
            for ((i=start_index; i<line_count; i++)); do
              printf "   %s\n" "${lines[i]}"
            done
          fi
          printf "${YELLOW}⚠️ Skipping stage-file-proxy configuration${RESET}\n"
          printf "${CYAN}🔧 Manual installation options:${RESET}\n"
          printf "   1. Download manually: https://github.com/manishsongirkar/stage-file-proxy/releases/download/101/stage-file-proxy.zip\n"
          printf "   2. Install via WP Admin: Plugins → Add New → Upload Plugin\n"
          printf "   3. Check internet connection and try again\n"
          setup_stage_proxy="n"
        fi

        # Clean up installation log
        rm -f "$install_log" 2>/dev/null
      fi

      # Only proceed with configuration if plugin installation was successful or plugin was already installed
      if [[ "$setup_stage_proxy" == [Yy]* ]]; then

    # Check if plugin is active and activate if needed
    # Use execute_wp_cli for reliable command execution
    if ! execute_wp_cli plugin is-active stage-file-proxy $network_flag &>/dev/null; then
      printf "${CYAN}📦 Activating stage-file-proxy plugin...${RESET}\n"
      # Use execute_wp_cli for reliable command execution
      if execute_wp_cli plugin activate stage-file-proxy $network_flag &>/dev/null; then
        printf "${GREEN}✅ Plugin activated successfully${RESET}\n"
      else
        printf "${RED}❌ Failed to activate plugin${RESET}\n"
      fi
    else
      printf "${GREEN}✅ Plugin already active${RESET}\n"
    fi

    # Function to sanitize and validate domain input for Stage File Proxy (expects full URL)
    sanitize_stage_proxy_domain() {
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

        # Initialize clean_domain with input
        clean_domain="$input"

        # Remove leading/trailing whitespace using bash built-ins (more portable than sed)
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

        # Prepare for HTTPS: Remove any existing protocol first
        clean_domain="${clean_domain#http://}"
        clean_domain="${clean_domain#https://}"

        # Add https:// protocol (required for database storage by plugin)
        clean_domain="https://$clean_domain"

        # Validate URL format more thoroughly (with required https protocol)
        # Domain must have at least one dot (.), except for localhost and IP addresses
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

    # Function to configure site-specific stage-file-proxy settings (using sfp_url and sfp_mode options)
    configure_site_proxy() {
      local source_domain="$1"
      local target_site="$2"
      local mode="${3:-header}"  # Default mode is 'header'.
      local wp_url_flag=""

      if [[ "$is_multisite" == "yes" ]]; then
        wp_url_flag="--url=$target_site"
      fi

      # Configure sfp_url (production source)
      local sanitized_domain
      sanitized_domain=$(sanitize_stage_proxy_domain "$source_domain")
      if [[ $? -ne 0 ]]; then
        printf "${RED}  ❌ Configuration failed for %s (invalid domain)${RESET}\n" "$target_site"
        return 1
      fi

      # Configure sfp_url
      local wp_url_output wp_url_exit_code
      wp_url_output=$(execute_wp_cli option update sfp_url "$sanitized_domain" $wp_url_flag 2>&1)
      wp_url_exit_code=$?

      if [[ $wp_url_exit_code -ne 0 ]]; then
        printf "${RED}  ❌ Failed to set sfp_url for %s${RESET}\n" "$target_site"
        printf "${RED}     WP-CLI Error: %s${RESET}\n" "$wp_url_output"
        return 1
      fi

      # Configure sfp_mode
      local wp_mode_output wp_mode_exit_code
      wp_mode_output=$(execute_wp_cli option update sfp_mode "$mode" $wp_url_flag 2>&1)
      wp_mode_exit_code=$?

      if [[ $wp_mode_exit_code -ne 0 ]]; then
        printf "${RED}  ❌ Failed to set sfp_mode for %s${RESET}\n" "$target_site"
        printf "${RED}     WP-CLI Error: %s${RESET}\n" "$wp_mode_output"
        return 1
      fi

      printf "${GREEN}  ✅ Configured successfully: %s (URL: %s, Mode: %s)${RESET}\n" "$target_site" "$sanitized_domain" "$mode"
      return 0
    }

    # Configure based on installation type
    if [[ "$is_multisite" == "yes" ]]; then
      printf "${CYAN}🌐 Configuring multisite stage-file-proxy...${RESET}\n"

      # Use existing domain mappings
      local array_length=${#domain_keys[@]}

      if [[ $array_length -eq 0 ]]; then
        printf "${YELLOW}⚠️ No domain mappings found. Using fallback configuration.${RESET}\n"
        configure_site_proxy "$search_domain" "$search_domain" "header"
      else
        printf "${GREEN}✅ Configuring %d sites with stage-file-proxy${RESET}\n" "$array_length"

        for ((i=1; i<=array_length; i++)); do
          local old_domain="${domain_keys[i]}"
          local new_domain="${domain_values[i]}"

          # Skip if empty or unchanged
          if [[ -z "$old_domain" || -z "$new_domain" || "$old_domain" == "$new_domain" ]]; then
            continue
          fi

          # Configure stage-file-proxy: production source (old_domain) → target site (new_domain)
          configure_site_proxy "$old_domain" "$new_domain" "header"
        done
      fi

    else
      printf "${CYAN}🧩 Configuring single site stage-file-proxy...${RESET}\n"
      configure_site_proxy "$search_domain" "$replace_domain" "header"
    fi

    printf "${GREEN}🎉 stage-file-proxy configuration complete!${RESET}\n"

    # Call the separate function to display local site access links
    show_local_site_links

      fi
    else
      printf "${YELLOW}ℹ️ Skipping stage-file-proxy setup as requested${RESET}\n"

      # Call the separate function to display local site access links
      show_local_site_links
    fi
  else
    printf "${YELLOW}ℹ️ Skipping stage-file-proxy configuration (SQL commands not confirmed or not applicable).${RESET}\n"

    # Call the separate function to display local site access links
    show_local_site_links
  fi

  printf "\n"

  # Ensure cleanup is run on successful exit
  trap - EXIT
}
