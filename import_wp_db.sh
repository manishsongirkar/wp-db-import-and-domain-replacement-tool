#!/bin/bash

# ===============================================
# WordPress Database Import & Domain Replacement Tool
# ===============================================
#
# Description:
#   A comprehensive bash script for importing WordPress databases and performing
#   domain/URL replacements, crucial for migrating environments (e.g., prod to local/staging).
#   It handles complex domain mapping scenarios and is optimized for both single-site
#   and multi-domain WordPress Multisite installations.
#
# Features:
#   - Automatic WordPress installation detection (single-site or multisite)
#   - **High-Speed Bulk Post Revision Cleanup (via xargs)**
#   - Intelligent domain sanitization (removes protocols, trailing slashes)
#   - **Robust Multi-Domain/Per-Site Mapping for Multisite**
#   - Two-pass search-replace (standard + serialized data)
#   - Cache and transient clearing
#   - Dry-run mode for testing
#   - MySQL command generation for domain mapping tables (for multisite completion)
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
#   1. Place SQL file in the same directory as this script
#   2. Navigate to WordPress root directory or subdirectory
#   3. Source this script: source import_wp_db.sh
#   4. Run the function: import_wp_db
#   5. Follow the interactive prompts
#
# Supported WordPress Types:
#   - Single-site installations
#   - Multisite subdomain networks
#   - Multisite subdirectory networks (especially multi-domain to single-domain migrations)
#
# File Structure:
#   - Creates temporary log files in /tmp/ for debugging
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
# import_wp_db() function definition
# ===============================================
import_wp_db() {
  # 🎨 Define colors locally for use within the function (Self-contained scope)
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

  # ⚙️ NEW HELPER FUNCTION: Safely execute WP-CLI commands
  # This function ensures that common Homebrew paths (where php/wp-cli often reside)
  # are prepended to the PATH for reliable execution in subshells.
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

  # Utility function to clean strings (removes leading/trailing whitespace/CR)
  clean_string() {
      local s="$1"
      # Only remove carriage returns and newlines - keep it simple
      s="${s//$'\r'/}"
      s="${s//$'\n'/}"
      # Use printf to naturally trim and return
      printf "%s" "$s"
  }  # 🧹 Define and set up cleanup for temporary log files
  local DB_LOG="/tmp/wp_db_import_$$.log"
  local SR_LOG_SINGLE="/tmp/wp_replace_single_$$.log"
  local REVISION_LOG="/tmp/wp_revision_delete_$$.log"
  local SUBSITE_DATA="/tmp/wp_subsite_data_$$.csv" # File to store subsite CSV data

  cleanup() {
    # 🧹 Comprehensive cleanup of all temporary files created by this script
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

    # Clean up any WordPress CLI cache files that might have been created
    find /tmp -type f -name "wp-cli-*" -mtime +1 -delete 2>/dev/null
  }
  trap cleanup EXIT

  # 🌀 Spinner function with elapsed time
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
    printf "%s" "                                                                                                   "
    printf "\r"
  }

  printf "\n${CYAN}${BOLD}🔧 WordPress Database Import & Domain Replace Tool${RESET}\n"
  printf "---------------------------------------------------\n\n"

  # 🧩 Ask for SQL file name (with fallback)
  local sql_file
  printf "📦 Enter SQL file name (default: vip-db.sql): "
  read -r sql_file
  sql_file=${sql_file:-vip-db.sql}

  # 🔍 Locate WordPress root
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

  # 🧠 Check WP-CLI installation
  if [[ -z "$WP_COMMAND" ]]; then
    printf "${RED}❌ WP-CLI not found. Please install WP-CLI first (or check your shell PATH).${RESET}\n"
    return 1
  fi

  # 🧱 Verify WordPress installation
  if ! execute_wp_cli core is-installed &>/dev/null; then
    printf "${RED}❌ No WordPress installation detected in this directory.${RESET}\n"
    return 1
  fi

  # 🧾 Validate SQL file
  if [[ ! -f "$sql_file" ]]; then
    printf "${RED}❌ File '%s' not found.${RESET}\n" "$sql_file"
    printf "${YELLOW}💡 Hint:${RESET} Place the file in current directory or specify the full path.\n"
    return 1
  fi

  printf "${GREEN}✅ Found SQL file:${RESET} %s\n\n" "$sql_file"

  # 🌐 Ask for main domain mapping (MANDATORY - no defaults allowed)
  local search_domain replace_domain confirm

  # Get OLD (production) domain - mandatory input
  while true; do
    printf "🌍 Enter the OLD (production) domain to search for: "
    read -r search_domain

    if [[ -n "$search_domain" ]]; then
      break
    else
      printf "${YELLOW}⚠️  Production domain is required. Please enter a value.${RESET}\n"
    fi
  done

  # Get NEW (local) domain - mandatory input
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

  # 📥 Import database (with spinner)
  printf "\n${CYAN}⏳ Importing database...${RESET}\n"
  local import_start_time=$(date +%s)
  # FIXED: Ensure PATH is available for the db import subshell
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

  # 🧩 Enhanced multisite detection logic (Post-import database introspection)
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
    multisite_type="subdomain" && printf "\n"
  else
    printf "${GREEN}✅ Multisite status:${RESET} no\n"
  fi

  printf "\n"

  # 🗑️ Ask for revision cleanup
  local cleanup_revisions
  printf "Clear ALL post revisions? (improves search-replace speed) (Y/n): "
  read -r cleanup_revisions
  cleanup_revisions="${cleanup_revisions:-y}"

  if [[ "$cleanup_revisions" =~ ^[Yy]$ ]]; then
    printf "${CYAN}🗑️ Clearing ALL Post Revisions (improves search-replace speed)...${RESET}\n"

  # Clean revision cleanup function - minimal output
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
      wp_cli_args=("post" "list" "--post_type=revision" "--format=ids" "$network_flag")
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

    printf "${CYAN}    Revisions found: %s${RESET}\n" "$revision_count_before"

    local xargs_command_output
    local xargs_exit_code

    # 2. --- Bulk Deletion via xargs ---
    # Construct arguments specific to the delete command.
    local wp_args=("--force")
    if [[ -n "$url_param" ]]; then
        wp_args+=("--url=$url_param")
    else
        wp_args+=("$network_flag")
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
    revisions_after=$(execute_wp_cli post list --post_type=revision --format=ids "${url_param:+--url=$url_param}" "$network_flag" 2>/dev/null | wc -w | tr -d ' ')
    revisions_after="${revisions_after:-0}"

    # Final check for total success
    if [[ "$revisions_after" -eq 0 ]]; then
        return 0
    else
        printf "${RED}⚠️ WARNING: %s revisions remain in the database after bulk attempt.${RESET}\n" "$revisions_after"
        return 1
    fi
  }

  # Clear revisions based on site type
  printf "${CYAN}🗑️ REVISION CLEANUP - STEP BY STEP${RESET}\n"
  printf "=====================================================\n\n"

  if [[ "$is_multisite" == "yes" ]]; then
    printf "${CYAN}🌐 MULTISITE DETECTED - Processing all subsites...${RESET}\n"
    printf "  ${YELLOW}Step A:${RESET} Getting list of all sites in the network\n"

    # Get all site URLs for multisite
    # FIXED: Use execute_wp_cli
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

  # ⚙️ Ask for --all-tables
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

  # ⚙️ Ask for --dry-run
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
  # Enhanced to handle domain+path combinations from wp_blogs table with intelligent slash handling.
  #
  # Key Features:
  # - Searches for domain+path as per wp_blogs table structure
  # - Conditional slash handling: only adds trailing slash to source if destination has trailing slash
  # - Maintains backward compatibility for single-site and simple domain-only replacements
  # - Supports both subdomain and subdirectory multisite configurations
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

      # CRITICAL REGRESSION PROTECTION: Only use path logic for actual multisite contexts
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

      local sr1_old="//${search_domain_with_path}"
      local sr1_new="//${replace_domain_with_path}"
      local sr2_old="\\\\//${search_domain_with_path}"
      local sr2_new="\\\\//${replace_domain_with_path}"

      # --- Pass 1 Execution (Blocking/Sequential) ---
      if [[ -n "$old_path" && "$old_path" != "/" ]]; then
          printf "  [Pass 1] Domain+Path replacement: ${YELLOW}%s${RESET} → ${GREEN}%s${RESET}\n" "$sr1_old" "$sr1_new"
      else
          printf "  [Pass 1] Simple replacement: ${YELLOW}%s${RESET} → ${GREEN}%s${RESET}\n" "$sr1_old" "$sr1_new"
      fi

      # Build the command array to avoid word splitting issues
      local cmd_args=("search-replace" "$sr1_old" "$sr1_new")

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

      # FIXED: Use execute_wp_cli for reliable command execution
      if ! execute_wp_cli "${cmd_args[@]}" &> "$log_file"; then
          return 1
      fi

      # --- Pass 2 Execution (Blocking/Sequential) ---
      printf "  [Pass 2] Serialized replacement: ${YELLOW}%s${RESET} → ${GREEN}%s${RESET}\n" "$sr2_old" "$sr2_new"

      # Rebuild command args for pass 2
      cmd_args=("search-replace" "$sr2_old" "$sr2_new")

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

      # FIXED: Use execute_wp_cli for reliable command execution
      if ! execute_wp_cli "${cmd_args[@]}" >> "$log_file" 2>&1; then
          return 1
      fi

      return 0
  }

  # 🌐 Handle Multisite (Single logic for all types, enabling per-site mapping)
  if [[ "$is_multisite" == "yes" ]]; then

      local confirm_replace
      printf "${CYAN}🌐 Multisite (%s) detected — gathering subsites for mapping...${RESET}\n\n" "$multisite_type"

      # --- Data Retrieval ---
      # FIXED: Use execute_wp_cli
      execute_wp_cli site list --fields=blog_id,domain,path --format=csv --url="$search_domain" 2>"$REVISION_LOG" > "$SUBSITE_DATA"

      # 🔍 Main Site ID Detection Block (NEW LOGIC)
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

      # Assign the Main Site ID
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
        # Since this call failed, the CSV data might be missing, so we must exit here.
        return 1
      elif [[ -z "$site_list" ]]; then
        printf "${YELLOW}⚠️ WP-CLI command succeeded but returned empty output${RESET}\n"
      else
        printf "%s\n" "$site_list" | column -t -s $'\t'
      fi
      printf "\n"

      # FIXED: Handle subdirectory vs subdomain multisite differently for search-replace
      if [[ "$multisite_type" == "subdirectory" ]]; then
          # For subdirectory multisite: All sites share the same domain
          printf "${CYAN}🏠 Subdirectory Multisite Detected${RESET}\n"
          printf "All subsites share the same domain. Only one search-replace operation needed.\n\n"

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

          # For subdirectory multisite, use network flag and main domain
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
          # For subdomain multisite: Handle individual site mappings (original logic)
          printf "${CYAN}🌐 Subdomain Multisite Detected${RESET}\n"
          printf "Each subsite has its own domain. Individual mapping required.\n\n"

          # Use parallel arrays instead of associative arrays (more compatible)
          local domain_keys=()
          local domain_values=()
          local domain_blog_ids=() # Added array to track blog IDs
          local domain_paths=() # Added array to track paths from wp_blogs

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
                printf "    ${GREEN}✅ Added mapping:${RESET} '%s' → '%s' (ID: %s, Path: %s)\n" "$cleaned_domain" "$local_domain" "$clean_blog_id" "$clean_site_path"
            else
                printf "    ${RED}❌ Skipped invalid mapping:${RESET} domain='%s', local='%s'\n" "$cleaned_domain" "$local_domain"
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

          # --- Summary Loop using parallel arrays (more compatible) ---
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

          printf "\n${CYAN}🔄 Starting search-replace (per site, sequential) - Subsites first, then Main Site...${RESET}\n"
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
    # 🧩 Single site (Original logic)
    printf "${CYAN}🧩 Single site detected.${RESET}\n"
    printf "Proceed with search-replace now? (Y/n): "
    read -r confirm_replace
    confirm_replace="${confirm_replace:-y}"
    [[ "$confirm_replace" != [Yy]* ]] && { printf "${YELLOW}⚠️ Operation cancelled.${RESET}\n"; return 0; }

    printf "\n🔁 Running search-replace (Double Pass)...${RESET}\n"

    # Pass search_domain and replace_domain, with no --url flag
    if run_search_replace "$search_domain" "$replace_domain" "$SR_LOG_SINGLE" ""; then
      printf "\n${GREEN}✅ Search-replace completed successfully!${RESET}\n"
    else
      printf "\n${RED}❌ Search-replace failed. See %s.${RESET}\n" "$SR_LOG_SINGLE"
      return 1
    fi
  fi

  # 🧹 Flush caches and transients
  printf "\n${CYAN}🧹 Flushing WordPress and WP-CLI caches & transients...${RESET}\n"

  # 1. Clear object cache (if persistent caching is used)
  # FIXED: Use execute_wp_cli
  if ! execute_wp_cli cache flush $network_flag &>/dev/null; then
      printf "${YELLOW}  ⚠️ Failed to flush object cache (Not always necessary/available).${RESET}\n"
  else
      printf "${GREEN}  ✅ Object cache flushed.${RESET}\n"
  fi

  # FIXED: Use execute_wp_cli
  if ! execute_wp_cli rewrite flush --hard $network_flag &>/dev/null; then
      printf "${YELLOW}  ⚠️ Failed to flush rewrite rule (Not always necessary/available).${RESET}\n"
  else
      printf "${GREEN}  ✅ Rewrite rule flushed.${RESET}\n"
  fi

  # 2. Delete transients
  # FIXED: Use execute_wp_cli
  if ! execute_wp_cli transient delete --all $network_flag &>/dev/null; then
      printf "${YELLOW}  ⚠️ Transient deletion finished (No transients found or minor error).${RESET}\n"
  else
      printf "${GREEN}  ✅ All transients deleted.${RESET}\n"
  fi

  printf "\n${GREEN}${BOLD}🎉 All done!${RESET} Database import and replacements completed successfully.\n\n"

  # 📋 Generate and display MySQL commands for manual execution in phpMyAdmin
  if [[ "$is_multisite" == "yes" && ${#domain_keys[@]} -gt 0 ]]; then
    printf "\n================================================================\n"
    printf "\n${CYAN}${BOLD}📋 MySQL Commands for Manual Execution in phpMyAdmin:${RESET}\n"
    printf "\n================================================================\n\n"

    # Extract the base domain from the first mapped domain (main site)
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
      printf "-- 1. Update blog domains and paths for SUB-SITES (ID != %s)\n\n" "$main_site_id"

      # Generate commands for each mapped domain
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

      printf "\n-- 2. Update blog domain and path for MAIN SITE (ID = %s)\n\n" "$main_site_id"

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

      printf "\n-- 3. Update the main network site domain (ID = 1)\n"
      printf "UPDATE wp_site SET domain = '%s' WHERE id = 1;\n\n" "$base_domain"

      printf "\n${YELLOW}💡 Copy the above commands and paste them into phpMyAdmin → SQL command to execute.${RESET}\n"
    else
      printf "${YELLOW}⚠️ Could not generate MySQL commands - no base domain found.${RESET}\n"
    fi
  elif [[ "$is_multisite" != "yes" ]]; then
    printf "${CYAN}${BOLD}📋 MySQL Commands for Single Site:${RESET}\n"
    printf "================================================================\n\n"
    printf "-- Single site setup - domain updated via WP-CLI search-replace\n"
    printf "-- No additional MySQL commands needed for single site installations\n\n"
    printf "${GREEN}✅ Single site domain replacement completed via WP-CLI.${RESET}\n"
  else
    printf "${YELLOW}ℹ️ No domain mappings to generate MySQL commands for.${RESET}\n"
  fi

  printf "\n================================================================\n\n"

  # 🔍 Ask for confirmation that MySQL commands have been executed (for multisite)
  local sql_executed="y"
  if [[ "$is_multisite" == "yes" && ${#domain_keys[@]} -gt 0 ]]; then
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
  fi

  # 🔍 Check for stage-file-proxy plugin and configure if present (only if SQL commands confirmed)
  if [[ "$sql_executed" == [Yy]* ]]; then
    # FIXED: Use execute_wp_cli
    if execute_wp_cli plugin is-installed stage-file-proxy &>/dev/null; then
      printf "${CYAN}🔍 stage-file-proxy plugin found! Configuring...${RESET}\n"

    # Check if plugin is active and activate if needed
    # FIXED: Use execute_wp_cli
    if ! execute_wp_cli plugin is-active stage-file-proxy $network_flag &>/dev/null; then
      printf "${CYAN}📦 Activating stage-file-proxy plugin...${RESET}\n"
      # FIXED: Use execute_wp_cli
      if execute_wp_cli plugin activate stage-file-proxy $network_flag &>/dev/null; then
        printf "${GREEN}✅ Plugin activated successfully${RESET}\n"
      else
        printf "${RED}❌ Failed to activate plugin${RESET}\n"
      fi
    else
      printf "${GREEN}✅ Plugin already active${RESET}\n"
    fi

    # Function to sanitize and validate domain input (Enhanced version for new plugin structure)
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

    # Function to escape JSON values safely (Enhanced version) - REMOVED as no longer needed
    # The new plugin version uses separate options instead of JSON format

    # Function to configure site-specific stage-file-proxy settings (Updated for new plugin structure)
    configure_site_proxy() {
      local source_domain="$1"
      local target_site="$2"
      local mode="${3:-header}"  # Default mode is 'header'.
      local wp_url_flag=""

      if [[ "$is_multisite" == "yes" ]]; then
        wp_url_flag="--url=$target_site"
      fi

      # UPDATED: Enhanced settings configuration with validation and user feedback for new plugin structure
      local sanitized_domain
      sanitized_domain=$(sanitize_stage_proxy_domain "$source_domain")
      if [[ $? -ne 0 ]]; then
        printf "${RED}  ❌ Configuration failed for %s (invalid domain)${RESET}\n" "$target_site"
        return 1
      fi

      # UPDATED: Configure sfp_url (replaces old source_domain)
      local wp_url_output wp_url_exit_code
      wp_url_output=$(execute_wp_cli option update sfp_url "$sanitized_domain" $wp_url_flag 2>&1)
      wp_url_exit_code=$?

      if [[ $wp_url_exit_code -ne 0 ]]; then
        printf "${RED}  ❌ Failed to set sfp_url for %s${RESET}\n" "$target_site"
        printf "${RED}     WP-CLI Error: %s${RESET}\n" "$wp_url_output"
        return 1
      fi

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

          # UPDATED: Configure stage-file-proxy with new plugin structure
          # sfp_url (production source) → target_site (local site), default mode 'header'
          configure_site_proxy "$old_domain" "$new_domain" "header"
        done
      fi

    else
      printf "${CYAN}🧩 Configuring single site stage-file-proxy...${RESET}\n"
      configure_site_proxy "$search_domain" "$replace_domain" "header"
    fi

    printf "${GREEN}🎉 stage-file-proxy configuration complete!${RESET}\n"
    fi
  else
    printf "${YELLOW}ℹ️ Skipping stage-file-proxy configuration (SQL commands not confirmed or not applicable).${RESET}\n"
  fi

  printf "\n"

  # Ensure cleanup is run on successful exit
  trap - EXIT
}
