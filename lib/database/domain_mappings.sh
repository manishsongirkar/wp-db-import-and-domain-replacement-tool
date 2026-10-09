#!/usr/bin/env bash

# ================================================================
# Custom Domain / URL Mappings
# ================================================================
#
# Description:
#   Extra search/replace pairs for strings that must not reach staging or local: CDN hosts,
#   third-party API URLs, a www variant, and so on. Works for single sites and multisite.
#
# Config (wpdb-import.conf):
#   [domain_mappings]                 applies to the whole database (the whole network on multisite)
#   //cdn.example.com => //cdn.target.test
#   https://api.example.com/v2 => https://api.sandbox.example.net/v2
#
#   [site_domain_mappings]            multisite only: one site (blog_id: old => new)
#   2: //shop.example.com => //shop.target.test
#
# Rules (see validate below):
#   - the search starts with // or http:// or https:// (never a bare host: a bare
#     "example.com" would also match test@example.com and plain text)
#   - a "//host" search needs a "//newhost" replacement (replacing //host inside
#     https://host with https://new would give "https:https://new")
#   - longest search first, and before the main domain replacement
#   - no entry's replacement may contain another entry's search (double replacement)
#   - on multisite a search must not be the domain of a site
#
# ================================================================

# ===============================================
# Read the entries of a section
# ===============================================
# Prints the raw, trimmed lines of [section] (no comments, no empty lines).
dm_section_lines() {
    local config_path="$1" section="$2"
    [[ -f "$config_path" ]] || return 0
    awk -v sec="$section" '
        BEGIN { in_sec = 0; want = tolower("[" sec "]") }
        { sub(/\r$/, "") }
        /^[[:space:]]*\[.*\]/ { line = tolower($0); gsub(/[[:space:]]/, "", line); in_sec = (line == want); next }
        in_sec {
            l = $0; sub(/^[[:space:]]+/, "", l); sub(/[[:space:]]+$/, "", l)
            if (l == "" || l ~ /^#/ || l ~ /^;/) next
            print l
        }
    ' "$config_path"
}

# "old => new" -> prints "old<TAB>new" (trimmed). Returns 1 when there is no =>.
dm_split_pair() {
    local line="$1" old new
    [[ "$line" == *"=>"* ]] || return 1
    old="${line%%=>*}"; new="${line#*=>}"
    old="${old#"${old%%[![:space:]]*}"}"; old="${old%"${old##*[![:space:]]}"}"
    new="${new#"${new%%[![:space:]]*}"}"; new="${new%"${new##*[![:space:]]}"}"
    printf "%s\t%s\n" "$old" "$new"
}

# ===============================================
# Validate one pair
# ===============================================
# Prints the reason and returns 1 when the pair is not allowed.
dm_validate_pair() {
    local old="$1" new="$2"
    if [[ -z "$old" || -z "$new" ]]; then
        printf "search and replace must both be set"; return 1
    fi
    if [[ "$old" =~ [[:space:][:cntrl:]\"\'\`\\] || "$new" =~ [[:space:][:cntrl:]\"\'\`\\] ]]; then
        printf "spaces, quotes and backslashes are not allowed"; return 1
    fi
    case "$old" in
        //*|http://*|https://*) ;;
        *) printf "the search must start with // or https:// (a bare host would also match emails and plain text). Write //%s" "$old"; return 1 ;;
    esac
    local old_host="${old#*//}"
    if [[ ! "$old_host" =~ ^[A-Za-z0-9] ]]; then
        printf "the search has no host after //"; return 1
    fi
    if [[ "$old" == //* ]]; then
        if [[ "$new" != //* || "$new" == ///* ]]; then
            printf "a //host search needs a //newhost replacement (not a full URL): %s" "$new"; return 1
        fi
    else
        case "$new" in
            //*|http://*|https://*) ;;
            *) printf "the replacement must start with //, http:// or https://"; return 1 ;;
        esac
    fi
    if [[ "$old" == "$new" ]]; then
        printf "search and replace are the same"; return 1
    fi
    return 0
}

# ===============================================
# Load and check all entries
# ===============================================
# Parameters: $1 config path, $2 section (domain_mappings), $3 blog id filter ("" = no id column),
#             $4 site domains to protect (space separated, optional)
# Sets: DM_ENTRIES   "old<TAB>new" lines, longest search first, no duplicates
#       DM_ERRORS    one message per line (empty when all is fine)
#       DM_WARNINGS  one message per line
# Returns 1 when DM_ERRORS is not empty.
dm_load() {
    local config_path="$1" section="${2:-domain_mappings}" blog_id="${3:-}" protect="${4:-}"
    DM_ENTRIES=""; DM_ERRORS=""; DM_WARNINGS=""
    local line pair old new why seen="" id rest d
    local raw=""
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        id=""
        if [[ "$section" == "site_domain_mappings" ]]; then
            if [[ ! "$line" =~ ^[0-9]+[[:space:]]*: ]]; then
                DM_ERRORS="${DM_ERRORS}${line}: expected 'blog_id: old => new'"$'\n'; continue
            fi
            id="${line%%:*}"; id="${id//[[:space:]]/}"; rest="${line#*:}"
            [[ -n "$blog_id" && "$id" != "$blog_id" ]] && continue
            line="$rest"
        fi
        if ! pair=$(dm_split_pair "$line"); then
            DM_ERRORS="${DM_ERRORS}${line}: expected 'old => new'"$'\n'; continue
        fi
        old="${pair%%$'\t'*}"; new="${pair#*$'\t'}"
        if ! why=$(dm_validate_pair "$old" "$new"); then
            DM_ERRORS="${DM_ERRORS}${old} => ${new}: ${why}"$'\n'; continue
        fi
        case "$seen" in
            *$'\n'"$old"$'\n'*) DM_WARNINGS="${DM_WARNINGS}${old}: listed twice, the first entry is used"$'\n'; continue ;;
        esac
        seen="${seen}"$'\n'"${old}"$'\n'
        # a multisite search must not be the domain of a site (it would break wp_blogs / wp_site)
        for d in $protect; do
            if [[ "${old#*//}" == "$d" || "${old#*//}" == "$d/" ]]; then
                DM_ERRORS="${DM_ERRORS}${old}: this is the domain of a site, use the site mapping for it"$'\n'; continue 2
            fi
        done
        raw="${raw}${old}"$'\t'"${new}"$'\n'
    done < <(dm_section_lines "$config_path" "$section")

    # chains: a replacement that contains another search would be replaced again
    local a_old a_new b_old
    while IFS=$'\t' read -r a_old a_new; do
        [[ -z "$a_old" ]] && continue
        while IFS=$'\t' read -r b_old _; do
            [[ -z "$b_old" || "$a_old" == "$b_old" ]] && continue
            if [[ "$a_new" == *"$b_old"* ]]; then
                DM_ERRORS="${DM_ERRORS}${a_old} => ${a_new}: the replacement contains the search of another entry (${b_old}); it would be replaced twice"$'\n'
            fi
        done <<< "$raw"
    done <<< "$raw"

    # longest search first (first listed wins on equal length)
    DM_ENTRIES=$(printf "%s" "$raw" | awk -F'\t' 'NF { print length($1) "\t" NR "\t" $0 }' | sort -t$'\t' -k1,1nr -k2,2n | cut -f3-)
    [[ -z "$DM_ERRORS" ]]
}

# Prints DM_ERRORS / DM_WARNINGS with a title. Returns 1 when there are errors.
dm_print_problems() {
    local title="$1" l
    if [[ -n "$DM_WARNINGS" ]]; then
        while IFS= read -r l; do [[ -n "$l" ]] && printf "${YELLOW}⚠️  %s: %s${RESET}\n" "$title" "$l"; done <<< "$DM_WARNINGS"
    fi
    if [[ -n "$DM_ERRORS" ]]; then
        while IFS= read -r l; do [[ -n "$l" ]] && printf "${RED}❌ %s: %s${RESET}\n" "$title" "$l"; done <<< "$DM_ERRORS"
        return 1
    fi
    return 0
}

# ===============================================
# Run the replacements
# ===============================================
# Parameters: $1 log file, $2 scope flag ("" single site, "--network"), $3 table list (optional,
#             space separated: only these tables, and then no --all-tables)
# Uses DM_ENTRIES (call dm_load first). Same flags as run_search_replace (all_tables_flag,
# dry_run_flag, --skip-columns=guid). Each entry runs twice: plain and JSON-escaped (/ as \/).
# Returns 1 if a WP-CLI call fails.
dm_run() {
    local log_file="$1" url_flag="${2:-}" tables="${3:-}" old new form search replace
    local -a flags tbl
    [[ -z "$DM_ENTRIES" ]] && return 0
    flags=("--skip-columns=guid" "--report-changed-only" "--skip-plugins" "--skip-themes" "--skip-packages")
    [[ "$url_flag" == "--network" ]] && flags+=("$url_flag")
    tbl=()
    if [[ -n "$tables" ]]; then
        # explicit tables of another site are only allowed together with --all-tables-with-prefix
        # shellcheck disable=SC2206
        tbl=($tables)
        flags+=("--all-tables-with-prefix")
    elif [[ -n "${all_tables_flag:-}" ]]; then
        flags+=("$all_tables_flag")
    fi
    [[ -n "${dry_run_flag:-}" ]] && flags+=("$dry_run_flag")
    : > "$log_file"
    while IFS=$'\t' read -r old new; do
        [[ -z "$old" ]] && continue
        for form in plain json; do
            if [[ "$form" == "plain" ]]; then
                search="$old"; replace="$new"
            else
                search="${old//\//\\/}"; replace="${new//\//\\/}"
            fi
            if ! execute_wp_cli search-replace "$search" "$replace" ${tbl[@]+"${tbl[@]}"} "${flags[@]}" >> "$log_file" 2>&1; then
                printf "   ${RED}✖ %s => %s: WP-CLI failed (see %s)${RESET}\n" "$old" "$new" "$log_file"
                return 1
            fi
        done
        printf "   • %s → %s\n" "$old" "$new"
    done <<< "$DM_ENTRIES"
    return 0
}

# Multisite: entries of [site_domain_mappings] for one blog id, limited to THAT site's tables.
# (--url is not used: with --all-tables it does not limit the replacement, and on a
# subdirectory network the subsite's domain is the main domain.)
# Blog 1: the main site's tables (wp db tables --scope=blog). Blog N: <prefix>N_*.
# Parameters: config path, blog id, log file
dm_run_site_scope() {
    local config_path="$1" blog_id="$2" log_file="$3" tables prefix
    [[ -n "$config_path" && -f "$config_path" ]] || return 0
    dm_load "$config_path" "site_domain_mappings" "$blog_id" || { dm_print_problems "[site_domain_mappings]"; return 1; }
    [[ -z "$DM_ENTRIES" ]] && return 0
    if [[ "$blog_id" == "1" ]]; then
        tables=$(execute_wp_cli db tables --scope=blog 2>/dev/null | LC_ALL=C grep -E '^[A-Za-z0-9_]+$' | tr '\n' ' ')
    else
        prefix=$(execute_wp_cli db prefix 2>/dev/null | LC_ALL=C grep -E '^[A-Za-z0-9_]+$' | head -1)
        tables=$(execute_wp_cli db tables "${prefix}${blog_id}_*" --all-tables-with-prefix 2>/dev/null | LC_ALL=C grep -E '^[A-Za-z0-9_]+$' | tr '\n' ' ')
    fi
    if [[ -z "${tables// /}" ]]; then
        printf "   ${RED}❌ Could not list the tables of site %s: its custom replacements were skipped.${RESET}\n" "$blog_id"
        return 1
    fi
    printf "   ${CYAN}Custom replacements for site %s only:${RESET}\n" "$blog_id"
    dm_run "$log_file" "" "$tables"
}

# ===============================================
# Counts and discovery (read-only, from the dump)
# ===============================================
# Number of times any of the given fixed strings appears in the dump (plain + JSON-escaped form).
dm_count_in_dump() {
    local sql_file="$1" needle="$2" esc
    esc="${needle//\//\\/}"
    sql_open_stream "$sql_file" 2>/dev/null | LC_ALL=C grep -oF -e "$needle" -e "$esc" 2>/dev/null | wc -l | tr -d ' '
}

# Most frequent hosts used in URLs inside the dump: "count host", most frequent first.
# Only text with // is counted, so email addresses never show up. Parameters: dump, old domain.
dm_discover_hosts() {
    local sql_file="$1" old_domain="$2" max="${3:-10}"
    local bare="${old_domain#www.}"
    sql_open_stream "$sql_file" 2>/dev/null \
        | LC_ALL=C grep -oE 'https?:(\\/|/)(\\/|/)[A-Za-z0-9][A-Za-z0-9.-]*' 2>/dev/null \
        | sed -e 's#^https\{0,1\}:##' -e 's#^\(\\\{0,1\}/\)\{2\}##' -e 's#\.$##' \
        | tr 'A-Z' 'a-z' \
        | LC_ALL=C grep -vxF -e "$bare" -e "www.$bare" \
        | sort | uniq -c | sort -rn | head -n "$max" | awk '{ print $1 " " $2 }'
}

# The dry-run report: counts of the main domain variants, of each custom entry, other hosts,
# and suggested config lines. Never writes anything.
# Parameters: dump, old domain, new domain, config path
dm_dry_run_report() {
    local sql_file="$1" old_domain="$2" new_domain="$3" config_path="${4:-}"
    local bare="${old_domain#www.}" n_plain n_www hosts line old new

    printf "\n${CYAN}${BOLD}🔎 URL findings in the dump${RESET}\n"
    n_plain=$(dm_count_in_dump "$sql_file" "//${bare}")
    n_www=$(dm_count_in_dump "$sql_file" "//www.${bare}")
    if [[ "$old_domain" == www.* ]]; then
        printf "   //%-34s %8s  (replaced: old_domain has www)\n" "$bare" "$n_plain"
        printf "   //%-34s %8s  (replaced)\n" "www.${bare}" "$n_www"
    else
        printf "   //%-34s %8s  (replaced)\n" "$bare" "$n_plain"
        if [[ "${n_www:-0}" -gt 0 ]]; then
            printf "   //%-34s %8s  ${YELLOW}(NOT replaced: old_domain has no www)${RESET}\n" "www.${bare}" "$n_www"
        else
            printf "   //%-34s %8s\n" "www.${bare}" "0"
        fi
    fi

    local suggest=""
    if [[ "$old_domain" != www.* && "${n_www:-0}" -gt 0 ]]; then
        suggest="//www.${bare} => //${new_domain#www.}"$'\n'
    fi

    if [[ -n "$config_path" ]] && dm_load "$config_path" "domain_mappings"; then
        if [[ -n "$DM_ENTRIES" ]]; then
            printf "${BOLD}   Custom [domain_mappings]:${RESET}\n"
            while IFS=$'\t' read -r old new; do
                [[ -z "$old" ]] && continue
                printf "   %-40s %8s  → %s\n" "$old" "$(dm_count_in_dump "$sql_file" "$old")" "$new"
            done <<< "$DM_ENTRIES"
        fi
    fi

    hosts=$(dm_discover_hosts "$sql_file" "$old_domain" 8)
    if [[ -n "$hosts" ]]; then
        printf "${BOLD}   Other hosts used in URLs (candidates for [domain_mappings]):${RESET}\n"
        while IFS= read -r line; do
            [[ -n "$line" ]] && printf "   %8s  %s\n" "${line%% *}" "${line#* }"
        done <<< "$hosts"
    fi
    if [[ -n "$suggest" ]]; then
        printf "${YELLOW}💡 Suggested lines for [domain_mappings] in the config (nothing was written):${RESET}\n"
        while IFS= read -r line; do [[ -n "$line" ]] && printf "   %s\n" "$line"; done <<< "$suggest"
    fi
    return 0
}

export -f dm_run_site_scope dm_section_lines dm_split_pair dm_validate_pair dm_load dm_print_problems dm_run \
    dm_count_in_dump dm_discover_hosts dm_dry_run_report 2>/dev/null
