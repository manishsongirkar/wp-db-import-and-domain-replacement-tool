# ===============================================
# import_wp_db() function definition
# Author: Manish Songirkar (@manishsongirkar)
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

  # 🌀 Spinner function
  show_spinner() {
    local pid=$1
    local message=$2
    local delay=0.15
    local spin='|/-\'
    printf "  %s " "$message"
    while ps -p "$pid" > /dev/null 2>&1; do
      for i in $(seq 0 3); do
        printf "\r  %s ${CYAN}%s${RESET}" "$message" "${spin:$i:1}"
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
  if ! "$WP_COMMAND" core is-installed &>/dev/null; then
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
    # Remove http:// and https:// protocols
    domain="${domain#http://}"
    domain="${domain#https://}"
    # Remove trailing slash
    domain="${domain%/}"
    # Remove any leading/trailing whitespace
    domain=$(echo "$domain" | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//')
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
  /bin/sh -c "\"$WP_COMMAND\" db import \"$sql_file\" &> \"$DB_LOG\"" &
  local spinner_pid=$!
  show_spinner $spinner_pid "Importing"
  wait $spinner_pid

  if [[ $? -ne 0 ]]; then
    printf "${RED}❌ Database import failed. Check %s for details.${RESET}\n" "$DB_LOG"
    return 1
  fi
  printf "${GREEN}✅ Database import successful!${RESET}\n\n"

  # 🧩 Check for multisite
  printf "${CYAN}🔍 Checking WordPress installation type...${RESET}\n"
  local is_multisite
  is_multisite=$("$WP_COMMAND" eval 'echo is_multisite() ? "yes" : "no";' --url="$search_domain" 2>/dev/null)

  local network_flag=""
  if [[ "$is_multisite" == "yes" ]]; then
    local sub_dir_option multisite_type
    sub_dir_option=$("$WP_COMMAND" option get subdirectory_install --url="$search_domain" 2>/dev/null)
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
    local get_ids_cmd
    if [[ -n "$url_param" ]]; then
      get_ids_cmd="$WP_COMMAND post list --post_type=revision --format=ids --url=\"$url_param\""
    else
      get_ids_cmd="$WP_COMMAND post list --post_type=revision --format=ids $network_flag"
    fi

    # Execute the bulk deletion
    local revision_ids_output
    revision_ids_output=$(eval "$get_ids_cmd" 2>/dev/null)
    if [[ -n "$revision_ids_output" && "$revision_ids_output" =~ [0-9] ]]; then
      if [[ -n "$url_param" ]]; then
        if eval "$WP_COMMAND post delete $revision_ids_output --force --url=\"$url_param\"" &>/dev/null; then
          printf "${GREEN}✅ Revisions deleted${RESET}\n"
        else
          printf "${RED}❌ Failed to delete revisions${RESET}\n"
        fi
      else
        if eval "$WP_COMMAND post delete $revision_ids_output --force $network_flag" &>/dev/null; then
          printf "${GREEN}✅ Revisions deleted${RESET}\n"
        else
          printf "${RED}❌ Failed to delete revisions${RESET}\n"
        fi
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
    local site_urls
    site_urls=$("$WP_COMMAND" site list --field=url --url="$search_domain" 2>/dev/null)

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
    printf "${YELLOW}⏭️ Skipping revision cleanup as requested.${RESET}\n\n"
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

      # Set PATH and run WP-CLI command
      if ! (export PATH="/opt/homebrew/bin:$PATH"; "$WP_COMMAND" "${cmd_args[@]}") &> "$log_file"; then
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

      # Set PATH and run WP-CLI command
      if ! (export PATH="/opt/homebrew/bin:$PATH"; "$WP_COMMAND" "${cmd_args[@]}") &>> "$log_file"; then
          return 1
      fi

      return 0
  }

  # 🌐 Handle Multisite (Single logic for all types, enabling per-site mapping)
  if [[ "$is_multisite" == "yes" ]]; then

      local confirm_replace
      printf "${CYAN}🌐 Multisite (%s) detected — gathering subsites for mapping...${RESET}\n\n" "$multisite_type"

      # --- Data Retrieval ---
      "$WP_COMMAND" site list --fields=blog_id,domain,path --format=csv --url="$search_domain" 2>"$REVISION_LOG" > "$SUBSITE_DATA"

      # Read the CSV data using a simple and reliable method
      local subsite_lines=()

      while IFS= read -r line; do
          # Skip header line exactly
          if [[ "$line" == "blog_id,domain,path" ]]; then
              continue
          fi

          # Skip completely empty lines
          if [[ -z "$line" ]]; then
              continue
          fi

          # Clean the line of any carriage returns or other whitespace
          line=$(echo "$line" | tr -d '\r' | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//')

          # Skip if line becomes empty after cleaning
          if [[ -z "$line" ]]; then
              continue
          fi

          # Add valid lines
          subsite_lines+=("$line")
      done < "$SUBSITE_DATA"

      # Filter out any empty elements (safety measure)
      local filtered_lines=()
      for line in "${subsite_lines[@]}"; do

          if [[ -n "$line" ]]; then
              if [[ "$line" != "blog_id,domain,path" ]]; then
                  filtered_lines+=("$line")
              fi
          fi
      done
      subsite_lines=("${filtered_lines[@]}")

      # REMOVE PREVIOUS FIX: We only need to ensure the final subsite_lines array is clean.
      # The previous logic failed to remove the empty element at index 0, causing index misalignment.
      # The simple filtering above should be sufficient if WP-CLI is not outputting true empty elements.
      # If the empty line still exists at index 0 after the filtering loop, it needs to be removed.
      # If [[ "${subsite_lines[0]}" == "" ]]; then
      #     subsite_lines=("${subsite_lines[@]:1}")
      # fi
      # NOTE: Reverting the previous fix as it caused the regression.
      # The issue is the combination of the filtering logic and the previous fix.
      # Since the filtering loop above is redundant with the `while read` loop's checks, we'll
      # make the final filtering array assignment definitive to remove any empty elements.

      # NEW FIX: The initial filtering loop inside the `while read` is not appending empty lines.
      # The second filtering loop is what preserves the empty line if it was introduced.
      # The final `subsite_lines=("${filtered_lines[@]}")` already represents the clean array.
      # The regression was caused by the manual array shift. We must ensure the filtering array is built correctly.

      # We will modify the cleanup loop to ensure no empty element makes it into the final array.
      local final_subsite_lines=()
      for line in "${subsite_lines[@]}"; do
          # Check for non-zero length AND that the first character is not a comma (to exclude weird empty lines)
          if [[ -n "$line" && "$line" != ","* ]]; then
              final_subsite_lines+=("$line")
          fi
      done
      subsite_lines=("${final_subsite_lines[@]}")


      local site_list
      site_list=$("$WP_COMMAND" site list --fields=blog_id,domain,path --format=table --url="$search_domain" 2>/dev/null)

      # Count sites from the array length
      local site_count=${#subsite_lines[@]}

      printf "${GREEN}✅ Found %s subsites:${RESET}\n" "$site_count" "$site_count"
      printf "%s\n" "$site_list"
      printf "\n"

      # Use parallel arrays instead of associative arrays (more compatible)
      local domain_keys=()
      local domain_values=()

      printf "${BOLD}Enter the NEW URL/Domain for each site:${RESET}\n"
      printf "(Example: Map 'sub1.example.com' to 'example.local/sub1')\n\n"

      local blog_id domain path local_domain mapped cleaned_domain

      # --- Interactive Mapping Loop ---
      for subsite_line in "${subsite_lines[@]}"; do

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

        # Skip if domain is empty after cleaning
        if [[ -z "$cleaned_domain" ]]; then
            continue
        fi

        # For the main site (ID 1), default to the global replace_domain
        if [[ "$blog_id" == "1" ]]; then
            printf "→ Local URL for '%s' (Blog ID 1): (%s) " "$cleaned_domain" "$replace_domain"
            read -r local_domain
            # Use default if empty
            local_domain="${local_domain:-$replace_domain}"
        else
            # For subsites, prompt the user clearly
            printf "→ Local URL for '%s' (Blog ID %s): " "$cleaned_domain" "$blog_id"
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
            domain_keys+=("$cleaned_domain")
            domain_values+=("$local_domain")
        fi
      done

      printf "\n🧾 ${BOLD}Domain mapping summary:${RESET}\n"

      # --- Summary Loop using parallel arrays (more compatible) ---
      local array_length=${#domain_keys[@]}

      for ((i=1; i<=array_length; i++)); do

        local key="${domain_keys[i]}"
        local value="${domain_values[i]}"

        # 1. Trim leading whitespace from 'key'
        key="${key#"${key%%[![:space:]]*}"}"

        # 2. Trim trailing whitespace from 'key'
        key="${key%"${key##*[![:space:]]}"}"

        # 3. Trim leading whitespace from 'value'
        value="${value#"${value%%[![:space:]]*}"}"

        # 4. Trim trailing whitespace from 'value'
        value="${value%"${value##*[![:space:]]}"}"

        if [[ -z "$value" ]]; then
          printf "    ❌ %s → (no mapping found)\n" "$key"
        elif [[ "$key" == "$value" ]]; then
          printf "    ⏭️  %s → (unchanged)\n" "$key"
        else
          printf "    🔁 %s → ${GREEN}%s${RESET}\n" "$key" "$value"
        fi
      done

      printf "\n"
      printf "Proceed with search-replace for all subsites? (Y/n): "
      read -r confirm_replace
      confirm_replace="${confirm_replace:-y}"
      [[ "$confirm_replace" != [Yy]* ]] && { printf "${YELLOW}⚠️ Operation cancelled.${RESET}\n"; return 0; }

      printf "\n${CYAN}🔄 Starting search-replace (per subsite, sequential)...${RESET}\n"
      local new_domain SR_LOG_MULTI

      # --- Execution Loop using parallel arrays ---
      local array_length=${#domain_keys[@]}
      for ((i=1; i<=array_length; i++)); do
        local cleaned_domain="${domain_keys[i]}"
        local new_domain="${domain_values[i]}"

        if [[ -z "$new_domain" || "$cleaned_domain" == "$new_domain" ]]; then
          printf "${YELLOW}⏭️  Skipping '%s' (no change).${RESET}\n" "$cleaned_domain"
          continue
        fi

        # Get the blog_id from the original data by matching the domain
        local blog_id=""
        for subsite_line in "${subsite_lines[@]}"; do
          IFS=, read -r temp_blog_id temp_domain temp_path <<< "$subsite_line"
          local temp_cleaned_domain=$(clean_string "$temp_domain")
          if [[ "$temp_cleaned_domain" == "$cleaned_domain" ]]; then
            blog_id="$temp_blog_id"
            break
          fi
        done

        SR_LOG_MULTI="/tmp/wp_replace_${blog_id}_$$.log"

        printf "\n➡️  ${BOLD}Replacing for Site ID %s:${RESET} ${YELLOW}%s${RESET} → ${GREEN}%s${RESET}\n" "$blog_id" "$cleaned_domain" "$new_domain"

        if run_search_replace "$cleaned_domain" "$new_domain" "$SR_LOG_MULTI" "--url=$cleaned_domain"; then
          printf "${GREEN}✅ Completed for %s.${RESET}\n" "$cleaned_domain"
        else
          printf "${RED}❌ Failed on %s. Check %s for details.${RESET}\n" "$cleaned_domain" "$SR_LOG_MULTI"
        fi
      done

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
  if ! "$WP_COMMAND" cache flush $network_flag &>/dev/null; then
      printf "${YELLOW}  ⚠️ Failed to flush object cache (Not always necessary/available).${RESET}\n"
  else
      printf "${GREEN}  ✅ Object cache flushed.${RESET}\n"
  fi

  if ! "$WP_COMMAND" rewrite flush --hard $network_flag &>/dev/null; then
      printf "${YELLOW}  ⚠️ Failed to flush rewrite rule (Not always necessary/available).${RESET}\n"
  else
      printf "${GREEN}  ✅ Rewrite rule flushed.${RESET}\n"
  fi

  # 2. Delete transients
  if ! "$WP_COMMAND" transient delete --all $network_flag &>/dev/null; then
      printf "${YELLOW}  ⚠️ Transient deletion finished (No transients found or minor error).${RESET}\n"
  else
      printf "${GREEN}  ✅ All transients deleted.${RESET}\n"
  fi

  printf "\n${GREEN}${BOLD}🎉 All done!${RESET} Database import and replacements completed successfully.\n\n\n\n"

  # 📋 Generate and display MySQL commands for manual execution in phpMyAdmin
  if [[ "$is_multisite" == "yes" && ${#domain_keys[@]} -gt 0 ]]; then
    printf "\n================================================================\n"
    printf "\n${CYAN}${BOLD}📋 MySQL Commands for Manual Execution in phpMyAdmin:${RESET}\n"
    printf "\n================================================================\n\n"

    # Extract the base domain from the first mapped domain (main site)
    local base_domain=""
    if [[ ${#domain_values[@]} -gt 0 ]]; then
      base_domain="${domain_values[1]}"
      # Remove protocol if present
      base_domain="${base_domain#http://}"
      base_domain="${base_domain#https://}"
      # Remove trailing slash
      base_domain="${base_domain%/}"
      # Remove path if it's a subdirectory setup
      base_domain="${base_domain%%/*}"
    fi

    if [[ -n "$base_domain" ]]; then
      printf "-- Update the main site domain\n"
      printf "UPDATE wp_site SET domain = '%s' WHERE id = 1;\n\n" "$base_domain"

      printf "-- Update blog domains and paths based on domain mapping\n"

      # Generate commands for each mapped domain
      local array_length=${#domain_keys[@]}
      for ((i=1; i<=array_length; i++)); do
        local old_domain="${domain_keys[i]}"
        local new_domain="${domain_values[i]}"

        # Skip if empty or unchanged
        if [[ -z "$new_domain" || "$old_domain" == "$new_domain" ]]; then
          continue
        fi

        # Find the corresponding blog_id from subsite data
        local blog_id=""
        local site_path="/"

        for subsite_line in "${subsite_lines[@]}"; do
          if [[ "$subsite_line" == "blog_id,domain,path" || -z "$subsite_line" ]]; then
            continue
          fi

          IFS=, read -r temp_blog_id temp_domain temp_path <<< "$subsite_line"
          local temp_cleaned_domain=$(clean_string "$temp_domain")

          if [[ "$temp_cleaned_domain" == "$old_domain" ]]; then
            blog_id="$temp_blog_id"

            # Determine the path based on the new domain mapping
            if [[ "$new_domain" == *"/"* ]]; then
              # Extract path from new_domain if it contains a path
              local domain_part="${new_domain%%/*}"
              local path_part="${new_domain#*/}"
              if [[ "$path_part" != "$new_domain" ]]; then
                site_path="/${path_part}/"
              fi
            elif [[ "$blog_id" != "1" ]]; then
              # For non-main sites, create path from old domain
              if [[ "$old_domain" == *"."* ]]; then
                # Extract subdomain or create path from domain
                local subdomain="${old_domain%%.*}"
                site_path="/${subdomain}/"
              fi
            fi
            break
          fi
        done

        if [[ -n "$blog_id" ]]; then
          printf "UPDATE wp_blogs SET domain = \"%s\", path = \"%s\" WHERE blog_id = %s;\n" "$base_domain" "$site_path" "$blog_id"
        fi
      done

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

  printf "\n"

  # Ensure cleanup is run on successful exit
  trap - EXIT
}
