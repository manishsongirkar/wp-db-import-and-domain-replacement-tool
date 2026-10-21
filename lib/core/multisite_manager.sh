#!/usr/bin/env bash

# ================================================================
# Multisite Manager Module
# ================================================================
#
# Description:
#   Handles complex multisite operations, specifically updating
#   wp_blogs and wp_site tables during domain replacement.
#
# ================================================================

# ===============================================
# Update Multisite Tables
# ===============================================
#
# Description: Updates wp_blogs and wp_site tables with new domain mappings.
#              Uses global arrays for domain mapping data.
#
# Parameters:
#   - $1: Main Site ID
#   - $2: Multisite Type ("subdomain" or "subdirectory")
#   - $3: Search Domain (for WP-CLI --url context)
#
# Globals Used:
#   - domain_keys (array)
#   - domain_values (array)
#   - domain_blog_ids (array)
#
# Returns:
#   - 0 on success, 1 on failure.
#
update_multisite_tables() {
    local main_site_id="$1"
    local multisite_type="$2"
    local search_domain="$3"

    # The PHP code below is built with php_sq_escape (utils.sh). Without it a value could not be
    # escaped, so stop instead of writing anything.
    if ! declare -F php_sq_escape >/dev/null 2>&1; then
        printf "${RED}❌ Internal error: php_sq_escape is not loaded; the network tables were not updated.${RESET}\n"
        return 1
    fi

    # Table names shown in the messages follow the site's own prefix (wp-config.php)
    local tbl_prefix
    tbl_prefix=$(get_safe_table_prefix)

    printf "\n${CYAN}${BOLD}🔧 Updating %sblogs and %ssite tables (before search-replace)...${RESET}\n" "$tbl_prefix" "$tbl_prefix"
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

    if [[ -z "$base_domain" ]]; then
        printf "${YELLOW}⚠️  Could not determine base domain - skipping automatic table updates${RESET}\n"
        return 1
    fi

    printf "${CYAN}🔄 Executing %sblogs and %ssite table updates via wp eval...${RESET}\n\n" "$tbl_prefix" "$tbl_prefix"

    printf "${CYAN}⚡ Updating %sblogs and %ssite tables...${RESET}\n" "$tbl_prefix" "$tbl_prefix"

    # Explicitly disable shell debugging to prevent variable assignment echoes
    set +x +v

    local total_commands_executed=0
    local failed_commands=0
    local failed_details=""

    # Try a simpler approach: Test WP-CLI connection first
    local connection_test
    connection_test=$(execute_wp_cli eval "echo 'Connection OK';" --url="$search_domain" 2>&1)
    local connection_exit_code=$?

    if [[ $connection_exit_code -ne 0 ]]; then
        printf "${RED}Connection failed: %s${RESET}\n" "$connection_test"
        return 1
    fi

    # Execute wp_site update FIRST (before wp_blogs updates change domain references)
    # Domains and paths are placed between PHP single quotes: escape \ and ' so a value is always data.
    # The tables are named with the site's own prefix ($wpdb->base_prefix), not a fixed "wp_".
    local q_base_domain
    q_base_domain=$(php_sq_escape "$base_domain")
    local site_command="global \$wpdb; \$result = \$wpdb->update(\$wpdb->base_prefix . 'site', array('domain' => '${q_base_domain}'), array('id' => 1)); echo (\$result !== false ? 'SUCCESS' : 'FAILED');"

    # Execute command and check result using bash pattern matching (no grep dependency)
    local site_output
    {
        site_output=$(set +x; execute_wp_cli eval "$site_command" --url="$search_domain" 2>&1)
    } 2>/dev/null

    if [[ "$site_output" == *"SUCCESS"* ]]; then
        ((total_commands_executed++))
        printf "  → Site ID 1: Network domain → %s ${GREEN}✅${RESET}\n" "$base_domain"
    else
        ((failed_commands++))
        failed_details="${failed_details}Updating Network Site... Failed ❌\n"
        printf "  → Site ID 1: Network domain → %s ${RED}❌${RESET}\n" "$base_domain"
    fi

    # Execute subsite updates
    printf "\n"
    printf "${YELLOW}📝 Updating %sblogs for subsites...${RESET}\n" "$tbl_prefix"
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

        # Execute individual wp eval command for this subsite
        # blog_id goes into PHP unquoted: it must be a plain number
        if [[ ! "$blog_id" =~ ^[0-9]+$ ]]; then
            ((failed_commands++))
            failed_details="${failed_details}Updating Blog ID '${blog_id}'... Failed (not a number) ❌\n"
            printf "  → Blog ID %s: ${RED}❌ not a valid blog ID, skipped${RESET}\n" "$blog_id"
            continue
        fi
        local q_target_domain q_site_path
        q_target_domain=$(php_sq_escape "$target_domain")
        q_site_path=$(php_sq_escape "$site_path")
        local individual_command="global \$wpdb; \$result = \$wpdb->update(\$wpdb->base_prefix . 'blogs', array('domain' => '${q_target_domain}', 'path' => '${q_site_path}'), array('blog_id' => ${blog_id})); echo (\$result !== false ? 'SUCCESS' : 'FAILED');"

        # Execute command and check result
        local blog_output
        {
            blog_output=$(set +x; execute_wp_cli eval "$individual_command" --url="$search_domain" 2>&1)
        } 2>/dev/null

        if [[ "$blog_output" == *"SUCCESS"* ]]; then
            ((total_commands_executed++))
            printf "  → Blog ID %s: %s → %s%s ${GREEN}✅${RESET}\n" "$blog_id" "$old_domain" "$target_domain" "$site_path"
        else
            ((failed_commands++))
            failed_details="${failed_details}Updating Blog ID ${blog_id}... Failed ❌\n"
            printf "  → Blog ID %s: %s → %s%s ${RED}❌${RESET}\n" "$blog_id" "$old_domain" "$target_domain" "$site_path"
        fi
    done

    # Execute main site update
    if [[ -n "$main_site_new_domain" ]]; then
        printf "\n"
        printf "${YELLOW}📝 Updating %sblogs for main site (ID: %s)...${RESET}\n" "$tbl_prefix" "$main_site_id"
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
        local main_output=""
        if [[ "$main_site_id" =~ ^[0-9]+$ ]]; then
            local q_main_target_domain q_main_site_path
            q_main_target_domain=$(php_sq_escape "$target_domain")
            q_main_site_path=$(php_sq_escape "$main_site_path")
            local main_command="global \$wpdb; \$result = \$wpdb->update(\$wpdb->base_prefix . 'blogs', array('domain' => '${q_main_target_domain}', 'path' => '${q_main_site_path}'), array('blog_id' => ${main_site_id})); echo (\$result !== false ? 'SUCCESS' : 'FAILED');"
            {
                main_output=$(set +x; execute_wp_cli eval "$main_command" --url="$search_domain" 2>&1)
            } 2>/dev/null
        fi

        if [[ "$main_output" == *"SUCCESS"* ]]; then
            ((total_commands_executed++))
            printf "  → Blog ID %s: %s → %s%s ${GREEN}✅${RESET}\n" "$main_site_id" "$main_site_old_domain" "$target_domain" "$main_site_path"
        else
            ((failed_commands++))
            failed_details="${failed_details}Updating Main Site (Blog ID ${main_site_id})... Failed ❌\n"
            printf "  → Blog ID %s: %s → %s%s ${RED}❌${RESET}\n" "$main_site_id" "$main_site_old_domain" "$target_domain" "$main_site_path"
        fi
    fi

    # Determine overall success and show clean output
    if [[ $failed_commands -eq 0 ]]; then
        printf "\n"
        printf "${GREEN}✅ Database tables %sblogs & %ssite updated successfully!${RESET}\n" "$tbl_prefix" "$tbl_prefix"
        return 0
    else
        printf "\n"
        printf "${RED}❌ Database tables %sblogs & %ssite update failed!${RESET}\n" "$tbl_prefix" "$tbl_prefix"
        echo -e "$failed_details"
        return 1
    fi
}

# Export function
export -f update_multisite_tables
