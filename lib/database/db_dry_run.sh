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
#        table, i.e. what search-replace would change; tables with no primary key are listed,
#        because WP-CLI skips them
#     5. the scratch database is dropped, and a summary is printed
#   Nothing is backed up, imported or replaced in the real database.
#
# With require_dry_run=true a LIVE run is refused until a dry run of the same dump has finished
#   (see "require_dry_run" below).
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
            # Not saved: an N must not switch the question off for later runs (set dry_run=false for that)
            printf "${GREEN}🚀 Running in live mode (changes will be applied).${RESET}\n\n"
        fi
    fi
    export WPDB_DRY_RUN_ACTIVE
}

# ===============================================
# require_dry_run: a live run needs a fresh dry run
# ===============================================
# require_dry_run=true (default false) and require_dry_run_hours=N (default 24) in the config.
# A dry run that finishes writes a small "stamp" file in a private folder outside the project
# (~/.wp-db-import/dry-run-stamps, or WPDB_STAMP_DIR). A live run is refused unless a stamp
# of the same dump, domains and mappings is not older than N hours. The dump is identified by
# its absolute path, size and modification time (a checksum of a multi-GB dump is too slow); a
# dump that changed on disk gets a new time and so needs a new dry run.
# Nothing is written, and nothing is refused, while require_dry_run is off.

# What a dry run previewed, as one line. Parameters: sql file, old domain, new domain, config path, WordPress root
dry_run_stamp_key() {
    local sql="$1" old="$2" new="$3" config="${4:-}" wp_root="${5:-}" abs size mtime maps=""
    abs="$(cd "$(dirname "$sql")" 2>/dev/null && pwd -P)/$(basename "$sql")"
    size=$(_sql_file_size_bytes "$sql")
    mtime=$(stat -f %m "$sql" 2>/dev/null)
    [[ "$mtime" =~ ^[0-9]+$ ]] || mtime=$(stat -c %Y "$sql" 2>/dev/null)
    [[ "$mtime" =~ ^[0-9]+$ ]] || mtime=0
    if [[ -n "$config" && -f "$config" ]] && declare -F dm_section_lines >/dev/null 2>&1; then
        maps=$( { dm_section_lines "$config" site_mappings; dm_section_lines "$config" domain_mappings; dm_section_lines "$config" site_domain_mappings; } | cksum | awk '{ print $1 "-" $2 }')
    fi
    printf '%s|%s|%s|%s|%s|%s|%s' "$abs" "$size" "$mtime" "$old" "$new" "$wp_root" "$maps"
}

dry_run_stamp_dir() { printf '%s' "${WPDB_STAMP_DIR:-$HOME/.wp-db-import/dry-run-stamps}"; }

# The stamp file of a key: the file name is a checksum, the content (key, time) is what is compared
_dry_run_stamp_file() { printf '%s/%s' "$(dry_run_stamp_dir)" "$(printf '%s' "$1" | cksum | awk '{ print $1 "-" $2 }')"; }

# Writes the stamp of a finished dry run. Does nothing while require_dry_run is off.
# Parameters: sql file, old domain, new domain, config path, WordPress root
dry_run_stamp_write() {
    is_config_true "${CONFIG_REQUIRE_DRY_RUN:-}" || return 0
    local key file dir
    key=$(dry_run_stamp_key "$@") || return 1
    file=$(_dry_run_stamp_file "$key")
    dir=$(dry_run_stamp_dir)
    if ! (umask 077; mkdir -p "$dir") 2>/dev/null || ! (umask 077; printf '%s\n%s\n' "$key" "$(date +%s)" > "$file") 2>/dev/null; then
        printf "${YELLOW}⚠️  Could not write the dry-run stamp in %s: a live run with require_dry_run=true will be refused.${RESET}\n" "$dir"
        return 1
    fi
    [[ "$dir" == "$HOME/.wp-db-import/dry-run-stamps" ]] && chmod 700 "$HOME/.wp-db-import" "$dir" 2>/dev/null
    printf "${DIM}   Dry-run stamp saved: a live run of this dump is allowed for %s hours (require_dry_run=true).${RESET}\n" "${CONFIG_REQUIRE_DRY_RUN_HOURS:-24}"
    return 0
}

# Allows or refuses a LIVE run. Returns 0 when allowed, 1 when refused (the reason and the command to run are printed).
# Parameters: sql file, old domain, new domain, config path, WordPress root
dry_run_guard_check() {
    is_config_true "${CONFIG_REQUIRE_DRY_RUN:-}" || {
        # an unknown value must not switch a safety guard off without a word
        case "$(printf '%s' "${CONFIG_REQUIRE_DRY_RUN:-}" | tr '[:upper:]' '[:lower:]')" in
            ""|false|no|0|off) return 0 ;;
        esac
        printf "${RED}❌ require_dry_run: '%s' is not true or false. Nothing was changed.${RESET}\n" "$CONFIG_REQUIRE_DRY_RUN"
        return 1
    }
    local hours="${CONFIG_REQUIRE_DRY_RUN_HOURS:-24}" key file stamp_key stamp_time now age
    if [[ ! "$hours" =~ ^[0-9]+$ || "$hours" -lt 1 ]]; then
        printf "${RED}❌ require_dry_run_hours: '%s' is not a whole number of hours (1 or more). Nothing was changed.${RESET}\n" "$hours"
        return 1
    fi
    key=$(dry_run_stamp_key "$@")
    file=$(_dry_run_stamp_file "$key")
    if [[ -f "$file" ]]; then
        { IFS= read -r stamp_key; IFS= read -r stamp_time; } < "$file"
        now=$(date +%s)
        if [[ "$stamp_key" == "$key" && "$stamp_time" =~ ^[0-9]+$ ]]; then
            age=$((now - stamp_time))
            [[ "$age" -ge 0 && "$age" -le $((hours * 3600)) ]] && return 0
            printf "${RED}❌ require_dry_run=true: the last dry run of this dump finished %s hours ago (the limit is %s).${RESET}\n" "$((age / 3600))" "$hours"
        else
            printf "${RED}❌ require_dry_run=true: the dry-run stamp is not valid for this dump.${RESET}\n"
        fi
    else
        printf "${RED}❌ require_dry_run=true: no dry run of this dump, with these domains and mappings, was finished in the last %s hours.${RESET}\n" "$hours"
    fi
    printf "${YELLOW}💡 Run the preview first:  wp-db-import --dry-run${RESET}\n"
    printf "   Then run the import again. A changed dump, domain or mapping needs a new dry run. Nothing was changed.\n"
    return 1
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
# Tables WP-CLI search-replace skips
# ===============================================
# WP-CLI replaces one row at a time and needs a key to find the row: a table with no primary key is
# reported as "skipped" and keeps the old domain. It uses the columns SHOW COLUMNS marks PRI, which
# includes a UNIQUE NOT NULL key when there is no PRIMARY KEY, so this does the same (and views are not tables).
# Parameters: $1 scratch database, then the client command (read-only queries only).
# Prints "table<TAB>rows" lines, most rows first. Prints nothing when every table has a key.
dry_run_tables_without_key() {
    local scratch="$1" list t count_sql="" sq="'"
    shift
    list=$("$@" -e "SELECT t.table_name FROM information_schema.tables t WHERE t.table_schema = '${scratch}' AND t.table_type = 'BASE TABLE' AND NOT EXISTS (SELECT 1 FROM information_schema.columns c WHERE c.table_schema = t.table_schema AND c.table_name = t.table_name AND c.column_key = 'PRI') ORDER BY t.table_name" 2>/dev/null)
    while IFS= read -r t; do
        [[ -n "$t" ]] || continue
        count_sql+="SELECT '${t//$sq/$sq$sq}', COUNT(*) FROM \`${t//\`/\`\`}\`;"
    done <<< "$list"
    [[ -n "$count_sql" ]] || return 0
    "$@" -e "$count_sql" 2>/dev/null | sort -t$'\t' -k2,2nr -k1,1
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

    # MYSQL_PWD in the environment of this function only: the password never appears in a command line
    local -x MYSQL_PWD="${WP_DB_PASSWORD:-}"
    local q=("$mysql_bin" "${args[@]}" -N -B)

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

    # skip_tables: the live run leaves these tables alone, so the counts leave them out too
    local skip_list="" skipped_tables="" st
    skip_list=$(sr_normalize_skip_tables "${CONFIG_SKIP_TABLES:-}" 2>/dev/null) || skip_list=""
    if [[ -n "$skip_list" ]]; then
        while IFS= read -r st; do
            [[ -n "$st" ]] && sr_table_is_skipped "$st" "$skip_list" && skipped_tables+="${skipped_tables:+, }$st"
        done <<< "$tables_list"
        cols_list=$(while IFS=$'\t' read -r c_table c_col; do
            [[ -n "$c_table" ]] && ! sr_table_is_skipped "$c_table" "$skip_list" && printf '%s\t%s\n' "$c_table" "$c_col"
        done <<< "$cols_list")
    fi

    printf "\n${CYAN}${BOLD}📋 Dry run summary${RESET}\n"
    printf "   Would import:            ${BOLD}%d tables / %d rows${RESET}\n" "$tcount" "$rows"
    printf "   Compatibility filter:    ${BOLD}%s${RESET}%s\n" "$filter_needed" "$([[ "$filter_needed" == "yes" ]] && printf ' %s' "${DIM}(the server rejected the dump as is; the filter fixes it)${RESET}")"

    if [[ -n "$skip_list" ]]; then
        printf "   Skipped tables:          ${BOLD}%s${RESET} ${DIM}(skip_tables=%s; not counted below)${RESET}\n" "${skipped_tables:-none match}" "$skip_list"
    fi
    if is_config_true "${CONFIG_PRECISE:-}"; then
        printf "   Precise mode:            ${BOLD}on${RESET} ${DIM}(the live run passes --precise: slower, same counts)${RESET}\n"
    fi

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

    # tables without a key: WP-CLI skips them, so the old domain would stay in them
    local nokey nk_table nk_rows nk_n=0
    nokey=$(dry_run_tables_without_key "$scratch" "${q[@]}")
    if [[ -n "$nokey" ]]; then
        printf "\n   ${YELLOW}⚠️  Tables WP-CLI search-replace will SKIP (no primary key): the old domain stays in them${RESET}\n"
        while IFS=$'\t' read -r nk_table nk_rows; do
            [[ -n "$nk_table" ]] || continue
            nk_n=$((nk_n + 1))
            [[ "$nk_n" -le 10 ]] && printf "      %-34s %8s rows\n" "$nk_table" "$nk_rows"
        done <<< "$nokey"
        [[ "$nk_n" -gt 10 ]] && printf "      ${DIM}... and %d more tables${RESET}\n" "$((nk_n - 10))"
        printf "      ${DIM}They are counted above, but a real run leaves them unchanged. Add a primary key (or a UNIQUE NOT NULL key)\n      to them in the dump, or run an SQL REPLACE() on them after the import.${RESET}\n"
    fi

    # URL findings (www variant, custom [domain_mappings] counts, other hosts): read from the dump only
    [[ -n "$skip_list" ]] && printf "\n${DIM}   (the URL findings below read the whole dump, skipped tables included)${RESET}"
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
    _dry_run_stream dry_run_preview _dry_run_in_scratch dry_run_tables_without_key dry_run_stamp_key dry_run_stamp_dir _dry_run_stamp_file \
    dry_run_stamp_write dry_run_guard_check 2>/dev/null
