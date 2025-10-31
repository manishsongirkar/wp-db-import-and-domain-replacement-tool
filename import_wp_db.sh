#!/bin/bash

# ===============================================
# WordPress Database Import & Domain Replacement Tool
# ===============================================
#
# Description:
#   A comprehensive bash script for importing WordPress databases and performing
#   domain/URL replacements with full support for both single-site and multisite
#   WordPress installations. This tool automates the complex process of migrating
#   WordPress databases from production to local/staging environments.
#
# Features:
#   - Automatic WordPress installation detection (single-site or multisite)
#   - Intelligent domain sanitization (removes protocols, trailing slashes)
#   - Interactive domain mapping for multisite installations
#   - Two-pass search-replace (standard + serialized data)
#   - Post revision cleanup for improved performance
#   - Cache and transient clearing
#   - Dry-run mode for testing
#   - MySQL command generation for phpMyAdmin
#   - Comprehensive error handling and logging
#   - Colored terminal output with progress indicators
#
# Requirements:
#   - WP-CLI installed and accessible in PATH
#   - WordPress installation (wp-config.php present)
#   - MySQL/MariaDB database
#   - Bash shell
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
#   - Multisite subdirectory networks
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

  # 🌐 Ask for main domain mapping
  local search_domain replace_domain confirm
  printf "🌍 Enter the OLD (production) domain to search for: "
  read -r search_domain
  printf "🏠 Enter the NEW (local) domain/base URL to replace with: "
  read -r replace_domain
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

  # 🧩 Check for multisite
  printf "${CYAN}🔍 Checking WordPress installation type...${RESET}\n"
  local is_multisite
  # FIXED: Use execute_wp_cli for WP-CLI calls
  is_multisite=$(execute_wp_cli eval 'echo is_multisite() ? "yes" : "no";' --url="$search_domain" 2>/dev/null)

  local network_flag=""
  if [[ "$is_multisite" == "yes" ]]; then
    local sub_dir_option multisite_type
    # FIXED: Use execute_wp_cli
    sub_dir_option=$(execute_wp_cli option get subdirectory_install --url="$search_domain" 2>/dev/null)
    if [[ "$sub_dir_option" == "1" ]]; then
      multisite_type="subdirectory"
    else
      multisite_type="subdomain"
    fi
    printf "${GREEN}✅ Multisite status:${RESET} %s\n\n" "$multisite_type"
    network_flag="--network"
  else
    printf "${GREEN}✅ Multisite status:${RESET} no\n\n"
  fi

  # 🗑️ Ask for revision cleanup
  local cleanup_revisions
  printf "Clear ALL post revisions? (improves search-replace speed) (Y/n): "
  read -r cleanup_revisions
  cleanup_revisions="${cleanup_revisions:-y}"

  if [[ "$cleanup_revisions" =~ ^[Yy]$ ]]; then
    printf "${CYAN}🗑️ Clearing ALL Post Revisions (improves search-replace speed)...${RESET}\n"

  # Clean revision cleanup function - minimal output
  clean_revisions_silent() {
    local url_param="$1"

    # Get revision IDs and execute deletion
    local get_ids_cmd_parts=()
    if [[ -n "$url_param" ]]; then
      get_ids_cmd_parts=("post" "list" "--post_type=revision" "--format=ids" "--url=$url_param")
    else
      get_ids_cmd_parts=("post" "list" "--post_type=revision" "--format=ids" "$network_flag")
    fi

    # Execute the bulk deletion
    local revision_ids_output
    # FIXED: Use execute_wp_cli
    revision_ids_output=$(execute_wp_cli "${get_ids_cmd_parts[@]}" 2>/dev/null)

    if [[ -n "$revision_ids_output" && "$revision_ids_output" =~ [0-9] ]]; then
        local delete_cmd_parts=("post" "delete" $revision_ids_output "--force")

        if [[ -n "$url_param" ]]; then
            delete_cmd_parts+=("--url=$url_param")
        else
            delete_cmd_parts+=("$network_flag")
        fi

        # FIXED: Use execute_wp_cli
        if execute_wp_cli "${delete_cmd_parts[@]}" &>/dev/null; then
          printf "${GREEN}✅ Revisions deleted${RESET}\n"
        else
          printf "${RED}❌ Failed to delete revisions${RESET}\n"
        fi
    else
      printf "${YELLOW}ℹ️ No revisions found${RESET}\n"
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

  # --- Search-Replace Execution Function (Handles Double Pass) ---

  # Arguments: $1=old_domain $2=new_domain $3=log_file $4=url_flag
  run_search_replace() {
      local old_domain="$1"
      local new_domain="$2"
      local log_file="$3"
      local url_flag="$4" # --url=... or empty

      # Validate inputs
      if [[ -z "$old_domain" || -z "$new_domain" ]]; then
          printf "Error: Missing domain parameters\n" >&2
          return 1
      fi

      local sr1_old="//${old_domain}"
      local sr1_new="//${new_domain}"
      local sr2_old="\\\\//${old_domain}"
      local sr2_new="\\\\//${new_domain}"

      # --- Pass 1 Execution (Blocking/Sequential) ---
      printf "  [Pass 1] Simple replacement: ${YELLOW}%s${RESET} → ${GREEN}%s${RESET}\n" "$sr1_old" "$sr1_new"

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
              IFS=, read -r blog_id domain path <<< "$line"
              local clean_blog_id=$(clean_string "$blog_id")
              local clean_path=$(clean_string "$path")

              # Condition 1: Find the lowest blog ID
              if [[ "$clean_blog_id" -lt "$temp_min_blog_id" ]]; then
                  temp_min_blog_id="$clean_blog_id"
              fi

              # Condition 2: Find the site with path ONLY "/"
              if [[ "$clean_path" == "/" ]]; then
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
          printf "${GREEN}✅ Main Site ID detected by path ('/'):${RESET} %s\n" "$main_site_id"
      elif [[ "$temp_min_blog_id" -ne 999999 ]]; then
          main_site_id="$temp_min_blog_id"
          printf "${YELLOW}⚠️ Main Site ID detected by lowest ID (fallback):${RESET} %s\n" "$main_site_id"
      else
          printf "${RED}❌ Could not detect Main Site ID. Defaulting to 1 (Network Admin Site).${RESET}\n"
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
        printf "%s\n" "$site_list"
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
            IFS=, read -r blog_id domain path <<< "$subsite_line"

            cleaned_domain=$(clean_string "$domain")
            local clean_blog_id=$(clean_string "$blog_id")

            # Skip if domain is empty after cleaning
            if [[ -z "$cleaned_domain" ]]; then
                continue
            fi

            # Debug output for domain processing
            printf "\n"
            printf "  ${CYAN}Processing:${RESET} Blog ID %s, Domain: '%s', Path: '%s'\n" "$clean_blog_id" "$cleaned_domain" "$path"

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
                printf "    ${GREEN}✅ Added mapping:${RESET} '%s' → '%s' (ID: %s)\n" "$cleaned_domain" "$local_domain" "$clean_blog_id"
            else
                printf "    ${RED}❌ Skipped invalid mapping:${RESET} domain='%s', local='%s'\n" "$cleaned_domain" "$local_domain"
            fi

          done

          # Clean up arrays - remove any empty elements using a more robust approach
          local clean_domain_keys=()
          local clean_domain_values=()
          local clean_domain_blog_ids=()
          local original_length=${#domain_keys[@]}

          for ((i=1; i<=original_length; i++)); do
            local key="${domain_keys[i]}"
            local value="${domain_values[i]}"
            local id="${domain_blog_ids[i]}" # Get blog ID

            if [[ -n "$key" && -n "$value" && -n "$id" ]]; then
              clean_domain_keys+=("$key")
              clean_domain_values+=("$value")
              clean_domain_blog_ids+=("$id") # Store clean blog ID
            fi
          done

          # Replace the original arrays
          unset domain_keys domain_values domain_blog_ids
          domain_keys=("${clean_domain_keys[@]}")
          domain_values=("${clean_domain_values[@]}")
          domain_blog_ids=("${clean_domain_blog_ids[@]}") # Use clean blog ID array

          printf "\n🧾 ${BOLD}Domain mapping summary:${RESET}\n"

          # --- Summary Loop using parallel arrays (more compatible) ---
          local array_length=${#domain_keys[@]}

          for ((i=1; i<=array_length; i++)); do

            local key="${domain_keys[i]}"
            local value="${domain_values[i]}"
            local id="${domain_blog_ids[i]}"

            # Use simple and reliable trimming - just check the raw values
            if [[ -z "$value" ]]; then
              printf "    ❌ [ID: %s] %s → (no mapping found)\n" "$id" "$key"
            elif [[ "$key" == "$value" ]]; then
              printf "    ⏭️  [ID: %s] %s → (unchanged)\n" "$id" "$key"
            else
              printf "    🔁 [ID: %s] %s → ${GREEN}%s${RESET}\n" "$id" "$key" "$value"
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

          # --- Execution Loop 1: Subsites (ID != main_site_id) ---
          printf "\n${CYAN}  SUB-SITES REPLACEMENT (ID != %s)${RESET}\n" "$main_site_id"
          local array_length=${#domain_keys[@]}
          for ((i=1; i<=array_length; i++)); do
            local cleaned_domain="${domain_keys[i]}"
            local new_domain="${domain_values[i]}"
            local blog_id="${domain_blog_ids[i]}"

            # Skip main site for now
            if [[ "$blog_id" == "$main_site_id" ]]; then
                main_site_key="$cleaned_domain"
                main_site_value="$new_domain"
                printf "${YELLOW}  ⏸️  Skipping Main Site (ID %s) - will process last.${RESET}\n" "$main_site_id"
                continue
            fi

            if [[ -z "$new_domain" || "$cleaned_domain" == "$new_domain" ]]; then
              printf "${YELLOW}⏭️  Skipping '%s' (ID %s, no change).${RESET}\n" "$cleaned_domain" "$blog_id"
              continue
            fi

            SR_LOG_MULTI="/tmp/wp_replace_${blog_id}_$$.log"

            printf "\n➡️  ${BOLD}Replacing for Site ID %s:${RESET} ${YELLOW}%s${RESET} → ${GREEN}%s${RESET}\n" "$blog_id" "$cleaned_domain" "$new_domain"

            # Use the old domain in the --url parameter because WP-CLI needs to find the table prefix.
            # The old domain should still exist in the wp_blogs table until the MySQL update.
            if run_search_replace "$cleaned_domain" "$new_domain" "$SR_LOG_MULTI" "--url=$cleaned_domain"; then
              printf "${GREEN}✅ Completed for %s (ID %s).${RESET}\n" "$cleaned_domain" "$blog_id"
            else
              printf "${RED}❌ Failed on %s (ID %s). Check %s for details.${RESET}\n" "$cleaned_domain" "$blog_id" "$SR_LOG_MULTI"
            fi
          done

          # --- Execution Loop 2: Main Site (ID = main_site_id) ---
          printf "\n${CYAN}  MAIN SITE REPLACEMENT (ID = %s)${RESET}\n" "$main_site_id"
          if [[ -n "$main_site_key" && "$main_site_key" != "$main_site_value" ]]; then
              local main_site_log="/tmp/wp_replace_${main_site_id}_$$.log"
              printf "\n➡️  ${BOLD}Replacing for Main Site ID %s:${RESET} ${YELLOW}%s${RESET} → ${GREEN}%s${RESET}\n" "$main_site_id" "$main_site_key" "$main_site_value"

              # Run main site search-replace (using the main site's old domain in --url for safety)
              if run_search_replace "$main_site_key" "$main_site_value" "$main_site_log" "--url=$main_site_key"; then
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
      printf "${CYAN}ℹ️  Note: All domains will be stored with https:// protocol for security.${RESET}\n"

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
    fi    # Function to sanitize and validate domain input (Enhanced version)
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

        # FIXED: Ensure https:// protocol for database storage
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

    # Function to escape JSON values safely (Enhanced version)
    escape_json_value() {
      local input="$1"
      # Use printf and parameter expansion for reliable escaping
      local escaped="$input"
      escaped="${escaped//\\/\\\\}"    # Escape backslashes first
      escaped="${escaped//\"/\\\"}"    # Escape quotes
      escaped="${escaped//$'\t'/\\t}"  # Escape tabs
      escaped="${escaped//$'\r'/\\r}"  # Escape carriage returns
      escaped="${escaped//$'\n'/\\n}"  # Escape newlines
      printf '%s' "$escaped"
    }

    # Function to create JSON settings for stage-file-proxy (Enhanced version)
    create_stage_proxy_settings() {
      local source_domain="$1"
      local method="${2:-redirect}"

      # FIXED: Use enhanced domain sanitization instead of basic protocol check
      local sanitized_domain
      sanitized_domain=$(sanitize_stage_proxy_domain "$source_domain")
      if [[ $? -ne 0 ]]; then
        printf "${RED}❌ Invalid domain format for stage-file-proxy: '%s'${RESET}\n" "$source_domain" >&2
        return 1
      fi

      local escaped_domain escaped_method
      escaped_domain=$(escape_json_value "$sanitized_domain")
      escaped_method=$(escape_json_value "$method")

      echo "{\"source_domain\":\"$escaped_domain\",\"method\":\"$escaped_method\"}"
      return 0
    }

    # Function to configure site-specific stage-file-proxy settings (Enhanced version)
    configure_site_proxy() {
      local source_domain="$1"
      local target_site="$2"
      local wp_url_flag=""

      if [[ "$is_multisite" == "yes" ]]; then
        wp_url_flag="--url=$target_site"
      fi

      # FIXED: Enhanced settings creation with validation and user feedback
      local settings
      settings=$(create_stage_proxy_settings "$source_domain" "redirect")
      if [[ $? -ne 0 ]]; then
        printf "${RED}  ❌ Configuration failed for %s (invalid domain)${RESET}\n" "$target_site"
        return 1
      fi

      # Execute WP-CLI command
      local wp_command=("option" "update" "stage-file-proxy-settings" "$settings" "--format=json" "$wp_url_flag")

      # Execute with error capture
      local wp_output
      local wp_exit_code
      # FIXED: Use execute_wp_cli
      wp_output=$(execute_wp_cli "${wp_command[@]}" 2>&1)
      wp_exit_code=$?

      if [[ $wp_exit_code -eq 0 ]]; then
        printf "${GREEN}  ✅ Configured successfully: %s${RESET}\n" "$target_site"
      else
        printf "${RED}  ❌ Configuration failed for %s${RESET}\n" "$target_site"
        printf "${RED}     WP-CLI Error: %s${RESET}\n" "$wp_output"
        return 1
      fi
      return 0
    }

    # Configure based on installation type
    if [[ "$is_multisite" == "yes" ]]; then
      printf "${CYAN}🌐 Configuring multisite stage-file-proxy...${RESET}\n"

      # Use existing domain mappings
      local array_length=${#domain_keys[@]}

      if [[ $array_length -eq 0 ]]; then
        printf "${YELLOW}⚠️ No domain mappings found. Using fallback configuration.${RESET}\n"
        configure_site_proxy "$search_domain" "$search_domain"
      else
        printf "${GREEN}✅ Configuring %d sites with stage-file-proxy${RESET}\n" "$array_length"

        for ((i=1; i<=array_length; i++)); do
          local old_domain="${domain_keys[i]}"
          local new_domain="${domain_values[i]}"

          # Skip if empty or unchanged
          if [[ -z "$old_domain" || -z "$new_domain" || "$old_domain" == "$new_domain" ]]; then
            continue
          fi

          # Configure stage-file-proxy: source_domain (production) → target_site (local)
          configure_site_proxy "$old_domain" "$new_domain"
        done
      fi

    else
      printf "${CYAN}🧩 Configuring single site stage-file-proxy...${RESET}\n"
      configure_site_proxy "$search_domain" "$replace_domain"
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
