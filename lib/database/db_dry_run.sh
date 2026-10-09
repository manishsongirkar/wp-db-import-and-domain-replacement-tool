#!/usr/bin/env bash

# ================================================================
# Real Dry Run
# ================================================================
#
# Description:
#   `dry_run=true` in the config, `--dry-run` on the command line, or WPDB_DRY_RUN=1 previews
#   the whole import WITHOUT changing the real database:
#     1. the SQL source is verified (size, corrupt archives)
#     2. the dump is imported into a temporary scratch database (never the real one)
#        - if the server rejects it, the compatibility filter is tried and reported
#     3. tables and rows that would be created are counted
#     4. occurrences of the old domain (and of every site-mapping domain) are counted per
#        table, i.e. what search-replace would change
#     5. the scratch database is dropped, and a summary is printed
#   Nothing is backed up, imported or replaced in the real database.
#
# Needs: the mysql client and an account that may CREATE DATABASE (a clear message is
#   printed when either is missing).
#
# Safety: one-line statements such as USE `db`; and CREATE/DROP/ALTER DATABASE ...; (also in
#   /*!40000 ... */ form) are removed from the stream, so a dump made with --databases can
#   never reach another database. Only complete one-line statements are removed, so row data
#   (even a multi-line text value) is never touched.
#
# ================================================================

# ===============================================
# Is dry-run mode on? (--dry-run / WPDB_DRY_RUN=1)
# ===============================================
wpdb_dry_run_requested() {
    case "$(printf "%s" "${WPDB_DRY_RUN:-}" | tr '[:upper:]' '[:lower:]')" in
        1|true|yes|on) return 0 ;;
    esac
    return 1
}

# ===============================================
# Decide dry-run mode BEFORE anything is imported
# ===============================================
# Sets WPDB_DRY_RUN_ACTIVE to "true" or "false". Order: command line / environment,
# then dry_run from the config, then a question (default No; saved to the config).
# Parameters: $1 = config path
decide_dry_run_mode() {
    local config_path="${1:-}" answer=""
    WPDB_DRY_RUN_ACTIVE="false"
    printf "\n"
    if wpdb_dry_run_requested; then
        WPDB_DRY_RUN_ACTIVE="true"
        printf "Run in ${BOLD}dry-run mode${RESET}: ${YELLOW}enabled${RESET} (--dry-run)\n\n"
    elif [[ -n "${CONFIG_DRY_RUN:-}" ]]; then
        if is_config_true "$CONFIG_DRY_RUN"; then
            WPDB_DRY_RUN_ACTIVE="true"
            printf "Run in ${BOLD}dry-run mode${RESET}: ${YELLOW}enabled${RESET} (from config)\n\n"
        else
            printf "Run in ${BOLD}dry-run mode${RESET}: ${GREEN}live mode${RESET} (from config)\n\n"
        fi
    else
        pause_script_timer 2>/dev/null
        printf "Run in ${BOLD}dry-run mode${RESET} (preview only, nothing is changed)? (y/N): "
        wpdb_read answer
        resume_script_timer 2>/dev/null
        if [[ "${answer:-n}" =~ ^[Yy] ]]; then
            WPDB_DRY_RUN_ACTIVE="true"
            printf "${YELLOW}🧪 Dry run: preview only, nothing will be changed.${RESET}\n\n"
            [[ -n "$config_path" ]] && update_config_general "$config_path" "dry_run" "true" 2>/dev/null
        else
            printf "${GREEN}🚀 Running in live mode (changes will be applied).${RESET}\n\n"
            [[ -n "$config_path" ]] && update_config_general "$config_path" "dry_run" "false" 2>/dev/null
        fi
    fi
    export WPDB_DRY_RUN_ACTIVE
}

# ===============================================
# Domains to look for: old_domain plus the old side of every site mapping
# ===============================================
# Parameters: $1 = main old domain, $2 = config path. Prints "old<TAB>new" lines, longest
# old domain first (so a more specific site is reported before its parent domain).
dry_run_domains() {
    local old="$1" new="$2" config="${3:-}"
    {
        printf '%s\t%s\n' "$old" "$new"
        if [[ -n "$config" && -f "$config" ]]; then
            awk -F: '
                /^\[/ { insec = ($0 == "[site_mappings]"); next }
                insec && $1 ~ /^[0-9]+$/ && NF >= 3 { gsub(/[[:space:]]/, "", $2); gsub(/[[:space:]]/, "", $3); if ($2 != "") printf "%s\t%s\n", $2, $3 }
            ' "$config"
        fi
    } | awk -F'\t' '!seen[$1]++ { print length($1) "\t" $0 }' | sort -rn | cut -f2-
}

# SQL string literal: backslashes and single quotes escaped
_dry_run_sql_str() {
    local v
    # sed, not ${var//}: the quoting rules for backslash and quote differ between Bash 3.2 and 5
    v=$(printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e "s/'/''/g")
    printf "'%s'" "$v"
}

# ===============================================
# The stream that goes into the scratch database
# ===============================================
# Parameters: $1 = file, $2 = apply compatibility filter (true/false)
# Database-switching statements are removed so the dump can only land in the scratch database.
_dry_run_stream() {
    _emit_import_stream "$1" false "${2:-false}" \
        | LC_ALL=C sed -E -e '/^(USE|CREATE DATABASE|DROP DATABASE|ALTER DATABASE)[[:space:]].*;[[:space:]]*$/Id' \
                          -e '/^\/\*![0-9]+[[:space:]]+(CREATE|DROP|ALTER)[[:space:]]+DATABASE[[:space:]].*\*\/;[[:space:]]*$/Id'
}

# ===============================================
# Run the preview
# ===============================================
# Parameters: $1 sql file, $2 old domain, $3 new domain, $4 WordPress root, $5 config path
# Returns 0 on success, 1 if the preview could not be done (nothing was changed either way).
dry_run_preview() {
    local sql_file="$1" old_domain="$2" new_domain="$3" wp_root="${4:-${WP_ROOT:-$(pwd)}}" config_path="${5:-}"

    printf "${CYAN}${BOLD}🧪 Dry run${RESET} ${DIM}(your database is not changed)${RESET}\n"

    # 1) source
    local verify_error
    if ! verify_error=$(sql_verify_source "$sql_file" 2>&1); then
        printf "${RED}❌ %s${RESET}\n" "$verify_error"
        return 1
    fi
    local size_b; size_b=$(sql_uncompressed_size_bytes "$sql_file")
    printf "   SQL file: %s ${DIM}(%d MB)${RESET}\n" "$sql_file" "$((size_b / 1048576))"

    # 2) client and credentials
    local mysql_bin
    if ! mysql_bin=$(_find_mysql_bin); then
        printf "${RED}❌ Dry run needs the mysql client (it imports into a temporary database), but none was found.${RESET}\n"
        printf "${YELLOW}💡 Install a mysql client, or set WPDB_MYSQL_BIN=/path/to/mysql. Nothing was changed.${RESET}\n"
        return 1
    fi
    if ! declare -F get_wp_db_credentials >/dev/null 2>&1 || ! get_wp_db_credentials "$wp_root" >/dev/null 2>&1 \
        || [[ -z "${WP_DB_USER:-}" ]]; then
        printf "${RED}❌ Could not read the database credentials from wp-config.php. Nothing was changed.${RESET}\n"
        return 1
    fi
    local socket=""
    if [[ "${CONFIG_USE_SOCKET:-auto}" != "false" ]] && declare -F detect_mysql_socket >/dev/null 2>&1; then
        socket=$(detect_mysql_socket "$wp_root" "${CONFIG_MYSQL_SOCKET:-}" 2>/dev/null || true)
    fi
    _build_mysql_args "$socket" "${WP_DB_HOST:-}" "$WP_DB_USER" "" 10
    local -a admin_args=("${_WPDB_MYSQL_ARGS[@]}")

    # 3) scratch database
    local scratch="wpdb_dry_$$_$((RANDOM % 9000 + 1000))"
    local create_err
    if ! create_err=$(MYSQL_PWD="${WP_DB_PASSWORD:-}" "$mysql_bin" "${admin_args[@]}" -e "CREATE DATABASE \`${scratch}\`" 2>&1); then
        printf "${RED}❌ Dry run needs permission to create a temporary database, and the server refused:${RESET}\n"
        # MariaDB's client echoes the statement before the error: show the ERROR line(s)
        printf "   %s\n" "$(printf '%s\n' "$create_err" | { grep -i 'error' || cat; } | head -2 | tr '\n' ' ' | cut -c1-200)"
        printf "${YELLOW}💡 Grant CREATE to the database user (for example GRANT CREATE ON \`wpdb_dry_%%\`.* TO '%s'@'...'), or run without dry run. Nothing was changed.${RESET}\n" "$WP_DB_USER"
        return 1
    fi
    local rc=0
    _dry_run_in_scratch "$mysql_bin" "$scratch" "$sql_file" "$old_domain" "$new_domain" "$config_path" "${socket}" || rc=$?
    MYSQL_PWD="${WP_DB_PASSWORD:-}" "$mysql_bin" "${admin_args[@]}" -e "DROP DATABASE IF EXISTS \`${scratch}\`" >/dev/null 2>&1
    return $rc
}

# The part that runs while the scratch database exists (the caller always drops it)
_dry_run_in_scratch() {
    local mysql_bin="$1" scratch="$2" sql_file="$3" old_domain="$4" new_domain="$5" config_path="$6" socket="$7"
    _build_mysql_args "$socket" "${WP_DB_HOST:-}" "$WP_DB_USER" "$scratch" 30
    local -a args=("${_WPDB_MYSQL_ARGS[@]}")
    local log; log="$(secure_tmpdir)/dry_run.log" || return 1

    # 4) import into the scratch database; try the compatibility filter if the server rejects the dump
    local filter_needed="no" start_ms end_ms
    start_ms=$(_now_ms)
    printf "   Importing into a temporary database... "
    if ! ( _dry_run_stream "$sql_file" false | MYSQL_PWD="${WP_DB_PASSWORD:-}" "$mysql_bin" "${args[@]}" > "$log" 2>&1 ) || import_log_has_errors "$log"; then
        if import_error_is_compat_related "$log"; then
            MYSQL_PWD="${WP_DB_PASSWORD:-}" "$mysql_bin" "${args[@]}" -e "DROP DATABASE \`${scratch}\`; CREATE DATABASE \`${scratch}\`" >/dev/null 2>&1
            if ( _dry_run_stream "$sql_file" true | MYSQL_PWD="${WP_DB_PASSWORD:-}" "$mysql_bin" "${args[@]}" > "$log" 2>&1 ) && ! import_log_has_errors "$log"; then
                filter_needed="yes"
            else
                printf "${RED}failed${RESET}\n"
                printf "${RED}❌ The dump cannot be imported, even with the compatibility filter:${RESET}\n"
                LC_ALL=C grep -E '^ERROR' "$log" | head -3 | cut -c1-300 | sed 's/^/   /'
                return 1
            fi
        else
            printf "${RED}failed${RESET}\n"
            printf "${RED}❌ The dump cannot be imported:${RESET}\n"
            LC_ALL=C grep -E '^ERROR' "$log" | head -3 | cut -c1-300 | sed 's/^/   /'
            printf "${YELLOW}💡 A real import would fail the same way.${RESET}\n"
            return 1
        fi
    fi
    end_ms=$(_now_ms)
    printf "${GREEN}done${RESET} ${DIM}(%d s)${RESET}\n" "$(( (end_ms - start_ms) / 1000 ))"

    local q=(env "MYSQL_PWD=${WP_DB_PASSWORD:-}" "$mysql_bin" "${args[@]}" -N -B)

    # 5) tables and rows
    local tables_list count_sql="" t tcount=0 rows=0 cnt
    tables_list=$("${q[@]}" -e "SELECT table_name FROM information_schema.tables WHERE table_schema = '${scratch}' AND table_type = 'BASE TABLE' ORDER BY table_name" 2>/dev/null)
    while IFS= read -r t; do
        [[ -n "$t" ]] || continue
        tcount=$((tcount + 1))
        count_sql+="SELECT COUNT(*) FROM \`${t//\`/\`\`}\`;"
    done <<< "$tables_list"
    if [[ -n "$count_sql" ]]; then
        while IFS= read -r cnt; do
            [[ "$cnt" =~ ^[0-9]+$ ]] && rows=$((rows + cnt))
        done < <("${q[@]}" -e "$count_sql" 2>/dev/null)
    fi

    # 6) occurrences of each domain, per table
    local cols_list c_table c_col domain_new d_old d_new total_occ=0 total_cells=0 report="" any=false
    cols_list=$("${q[@]}" -e "SELECT table_name, column_name FROM information_schema.columns WHERE table_schema = '${scratch}' AND data_type IN ('char','varchar','tinytext','text','mediumtext','longtext') ORDER BY table_name, ordinal_position" 2>/dev/null)

    printf "\n${CYAN}${BOLD}📋 Dry run summary${RESET}\n"
    printf "   Would import:            ${BOLD}%d tables / %d rows${RESET}\n" "$tcount" "$rows"
    printf "   Compatibility filter:    ${BOLD}%s${RESET}%s\n" "$filter_needed" "$([[ "$filter_needed" == "yes" ]] && printf ' %s' "${DIM}(the server rejected the dump as is; the filter fixes it)${RESET}")"

    while IFS=$'\t' read -r d_old d_new; do
        [[ -n "$d_old" ]] || continue
        local dq union="" per_table
        dq=$(_dry_run_sql_str "$d_old")
        while IFS=$'\t' read -r c_table c_col; do
            [[ -n "$c_table" && -n "$c_col" ]] || continue
            local tq="\`${c_table//\`/\`\`}\`" cq="\`${c_col//\`/\`\`}\`"
            local sq="'" table_lit
            table_lit="${c_table//$sq/$sq$sq}"
            union+="SELECT '${table_lit}', COUNT(*), CAST(SUM((LENGTH(${cq}) - LENGTH(REPLACE(${cq}, ${dq}, ''))) / LENGTH(${dq})) AS UNSIGNED) FROM ${tq} WHERE LOCATE(${dq}, ${cq}) > 0;"
        done <<< "$cols_list"
        per_table=""
        [[ -n "$union" ]] && per_table=$("${q[@]}" -e "$union" 2>/dev/null | awk -F'\t' '$2 > 0 { cells[$1] += $2; occ[$1] += $3 } END { for (t in occ) printf "%s\t%d\t%d\n", t, cells[t], occ[t] }' | sort -t$'\t' -k3,3nr)
        local dom_cells=0 dom_occ=0 dom_tables=0 line_t line_c line_o
        while IFS=$'\t' read -r line_t line_c line_o; do
            [[ -n "$line_t" ]] || continue
            dom_tables=$((dom_tables + 1)); dom_cells=$((dom_cells + line_c)); dom_occ=$((dom_occ + line_o))
        done <<< "$per_table"
        total_occ=$((total_occ + dom_occ)); total_cells=$((total_cells + dom_cells))
        any=true
        printf "\n   ${BOLD}%s${RESET} → ${BOLD}%s${RESET}\n" "$d_old" "$d_new"
        printf "   Would replace:           ${BOLD}%d occurrences${RESET} in %d values across %d tables\n" "$dom_occ" "$dom_cells" "$dom_tables"
        local shown=0
        while IFS=$'\t' read -r line_t line_c line_o; do
            [[ -n "$line_t" ]] || continue
            shown=$((shown + 1)); [[ $shown -gt 8 ]] && break
            printf "      %-34s %6d occurrences\n" "$line_t" "$line_o"
        done <<< "$per_table"
        [[ "$dom_tables" -gt 8 ]] && printf "      ${DIM}... and %d more tables${RESET}\n" "$((dom_tables - 8))"
    done < <(dry_run_domains "$old_domain" "$new_domain" "$config_path")

    # URL findings (www variant, custom [domain_mappings] counts, other hosts): read from the dump only
    declare -F dm_dry_run_report >/dev/null 2>&1 && dm_dry_run_report "$sql_file" "$old_domain" "$new_domain" "$config_path"

    printf "\n"
    if [[ "$any" == "true" && "$total_occ" -eq 0 ]]; then
        printf "   ${YELLOW}⚠️  The old domain does not appear in the dump: a real run would replace nothing.${RESET}\n"
    fi
    printf "${GREEN}${BOLD}✅ Dry run finished. Your database was not changed.${RESET}\n"
    printf "${DIM}   (counts include serialized data; domains that contain each other are counted separately)${RESET}\n"
    printf "${DIM}   Run for real: set dry_run=false in the config, or run without --dry-run.${RESET}\n"
    return 0
}

export -f wpdb_dry_run_requested decide_dry_run_mode dry_run_domains _dry_run_sql_str \
    _dry_run_stream dry_run_preview _dry_run_in_scratch 2>/dev/null
