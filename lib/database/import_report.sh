#!/usr/bin/env bash

# ================================================================
# Post-Import Report
# ================================================================
#
# Description:
#   After a LIVE import and its search-replace, prints a summary and saves it as
#   wpdb-import-report.txt next to wpdb-import.conf (mode 600):
#     - replacements per table (read from the WP-CLI logs: --report-changed-only)
#     - how many replacements the PHP (serialized-aware) replacer made, and how many SQL did
#     - tables WP-CLI skipped (no primary key), and the Error:/Warning: lines of the logs
#     - the old domain that is still in the database (one read-only `search-replace --dry-run`
#       per old host, same flags as the real run), with the top tables
#     - the time of each step
#   It never changes the database, and a problem in the report never fails the import.
#
# Config (wpdb-import.conf):
#   import_report=true     (default) set false to skip the report and the extra read of the database
#   report_keep=5          reports to keep; older ones are renamed wpdb-import-report.<date>.txt
#                          and the oldest are deleted (0 keeps all)
#
# Functions:
#   report_step_add NAME SECONDS      record the time of a step
#   report_parse_logs FILE...         "R table total php sql", "S table", "N note" records
#   report_leftovers HOST...          "host<TAB>table<TAB>count" records (read-only)
#   report_rotate DIR KEEP            rename the last report and delete the oldest
#   import_report_generate ...        print and save the report
#
# ================================================================

WPDB_REPORT_STEPS=""

# Record the time of a step. Parameters: name, seconds
report_step_add() {
    WPDB_REPORT_STEPS="${WPDB_REPORT_STEPS}${1}|${2}"$'\n'
}

# 75 -> 01:15
_report_mmss() { printf "%02d:%02d" "$(($1 / 60))" "$(($1 % 60))"; }

# ===============================================
# Read the WP-CLI search-replace logs
# ===============================================
# WP-CLI prints "Table<TAB>Column<TAB>Replacements<TAB>Type" rows when its output is not a terminal
# (Type is SQL or PHP: PHP means the serialized-aware replacer did the work). A table with no primary
# key is reported as "skipped".
# Prints tab separated records:  R<TAB>table<TAB>total<TAB>php<TAB>sql   S<TAB>table   N<TAB>note
# Parameters: log files (missing files are ignored)
report_parse_logs() {
    local f
    for f in "$@"; do [[ -f "$f" ]] && cat "$f"; done | LC_ALL=C awk -F'\t' '
        NF >= 4 && $1 ~ /^[A-Za-z0-9_$.-]+$/ && $3 ~ /^[0-9]+$/ && ($4 == "PHP" || $4 == "SQL") {
            n[$1] += $3; if ($4 == "PHP") p[$1] += $3; else s[$1] += $3; next
        }
        NF >= 3 && $1 ~ /^[A-Za-z0-9_$.-]+$/ && $3 == "skipped" { sk[$1] = 1; next }
        /^(Error|Warning):/ { if (!seen[$0]++ && nn < 10) note[++nn] = substr($0, 1, 200); next }
        END {
            for (t in n) printf "R\t%s\t%d\t%d\t%d\n", t, n[t], p[t] + 0, s[t] + 0
            for (t in sk) printf "S\t%s\n", t
            for (i = 1; i <= nn; i++) printf "N\t%s\n", note[i]
        }'
}

# ===============================================
# The old domain that is still in the database
# ===============================================
# One read-only `wp search-replace <host> <placeholder> --dry-run` per host: the host is searched without
# "//" so JSON-escaped URLs, www and e-mail addresses are found too (the main replacement leaves those
# addresses alone on purpose). The same table flags as the real run are used (sr_build_flags: --all-tables,
# --skip-tables, ...); guid columns are skipped as in the real run. Nothing is written.
# Parameters: hosts. Uses (caller's variables): all_tables_flag, skip_tables_flag, precise_flag, network_flag.
# Prints "host<TAB>table<TAB>count" lines, most first per host. A failing WP-CLI call prints nothing.
report_leftovers() {
    local host out dry_run_flag="--dry-run" net=""
    local -a cmd
    [[ "${network_flag:-}" == "--network" ]] && net="--network"
    sr_build_flags
    for host in "$@"; do
        [[ -n "$host" ]] || continue
        cmd=(search-replace "$host" "__wpdb_report__")
        [[ -n "$net" ]] && cmd+=("$net")
        cmd+=("${SR_FLAGS[@]}")
        out=$(execute_wp_cli "${cmd[@]}" 2>/dev/null) || continue
        printf '%s\n' "$out" | LC_ALL=C awk -F'\t' -v h="$host" '
            NF >= 4 && $3 ~ /^[0-9]+$/ && ($4 == "PHP" || $4 == "SQL") { n[$1] += $3 }
            END { for (t in n) printf "%s\t%s\t%d\n", h, t, n[t] }' | sort -t$'\t' -k3,3nr -k2,2
    done
}

# ===============================================
# Which old hosts to look for
# ===============================================
# Parameters: the main old domain, then the old domains (with an optional path) of the site mappings.
# Prints one host per line: duplicates and paths are removed, and a host that is a subdomain of another
# listed host is left out (searching the parent host finds it too).
report_old_hosts() {
    local h g keep="" list=""
    for h in "$@"; do
        h="${h#http://}"; h="${h#https://}"; h="${h%%/*}"
        [[ -n "$h" ]] && list="${list}${h}"$'\n'
    done
    while IFS= read -r h; do
        [[ -n "$h" ]] || continue
        case "$keep" in *$'\n'"$h"$'\n'*) continue ;; esac
        while IFS= read -r g; do
            [[ -n "$g" && "$g" != "$h" && "$h" == *."$g" ]] && continue 2
        done <<< "$list"
        keep="${keep}"$'\n'"${h}"$'\n'
        printf '%s\n' "$h"
    done <<< "$list"
}

# ===============================================
# Keep the latest N reports
# ===============================================
# The last report is renamed wpdb-import-report.<YYYYmmdd-HHMMSS>.txt; of those, the newest (keep - 1) stay
# (the new report counts as one). keep=0 keeps all. Other files are never touched.
# Parameters: folder, keep
report_rotate() {
    local dir="$1" keep="${2:-5}" cur stamp n=0 f
    cur="$dir/wpdb-import-report.txt"
    if [[ -f "$cur" ]]; then
        stamp=$(date '+%Y%m%d-%H%M%S')
        f="$dir/wpdb-import-report.$stamp.txt"
        while [[ -e "$f" ]]; do n=$((n + 1)); f="$dir/wpdb-import-report.$stamp-$n.txt"; done
        mv "$cur" "$f" 2>/dev/null || return 1
    fi
    [[ "$keep" =~ ^[0-9]+$ && "$keep" -gt 0 ]] || return 0
    n=0
    # newest first: the names sort by date
    while IFS= read -r f; do
        [[ -n "$f" ]] || continue
        n=$((n + 1))
        [[ "$n" -ge "$keep" ]] && rm -f "$f"
    done < <(ls -1 "$dir"/wpdb-import-report.[0-9]*.txt 2>/dev/null | LC_ALL=C sort -r)
    return 0
}

# ===============================================
# Build the text of the report
# ===============================================
# Parameters: $1 = max tables to list (0 = all), $2 = old domain, $3 = new domain, $4 = site type text,
#             $5 = parsed log records file, $6 = leftover records file
_report_text() {
    local max="$1" old="$2" new="$3" site="$4" recs="$5" left="$6"
    local kind a b c d total=0 php=0 sql=0 ntables=0 shown=0 step secs
    printf 'WP DB Import report\n'
    printf '===================\n'
    printf 'Date:         %s\n' "$(date '+%Y-%m-%d %H:%M:%S %Z')"
    printf 'Tool version: %s\n' "$(get_tool_version 2>/dev/null)"
    printf 'Site type:    %s\n' "$site"
    [[ -n "${WP_DB_NAME:-}" ]] && printf 'Database:     %s\n' "$WP_DB_NAME"
    printf 'Replacement:  %s -> %s\n' "$old" "$new"
    [[ -n "${WPDB_IMPORT_NOTES:-}" ]] && printf 'Import notes: %s\n' "$WPDB_IMPORT_NOTES"
    [[ -n "${CONFIG_SKIP_TABLES:-}" ]] && printf 'skip_tables:  %s\n' "$CONFIG_SKIP_TABLES"
    is_config_true "${CONFIG_PRECISE:-}" && printf 'precise:      on\n'

    printf '\nReplacements per table\n----------------------\n'
    while IFS=$'\t' read -r kind a b c d; do
        [[ "$kind" == "R" ]] || continue
        ntables=$((ntables + 1)); total=$((total + b)); php=$((php + c)); sql=$((sql + d))
    done < "$recs"
    if [[ "$ntables" -eq 0 ]]; then
        printf '  No replacements were reported.\n'
    else
        while IFS=$'\t' read -r kind a b c d; do
            [[ "$kind" == "R" ]] || continue
            shown=$((shown + 1))
            if [[ "$max" -gt 0 && "$shown" -gt "$max" ]]; then
                printf '  ... and %d more tables (the saved report lists all)\n' "$((ntables - max))"
                break
            fi
            printf '  %-40s %8d   (PHP %d, SQL %d)\n' "$a" "$b" "$c" "$d"
        done < <(grep '^R' "$recs" | LC_ALL=C sort -t$'\t' -k3,3nr -k2,2)
        printf '  Total: %d replacements in %d tables\n' "$total" "$ntables"
        printf '  Serialized-aware (PHP) replacer: %d replacements; plain SQL: %d\n' "$php" "$sql"
    fi

    printf '\nSkipped and errors\n------------------\n'
    if grep -q '^S' "$recs"; then
        printf '  Skipped by WP-CLI (no primary key, the old domain stays in them): %s\n' "$(grep '^S' "$recs" | cut -f2 | LC_ALL=C sort -u | paste -sd, - | sed 's/,/, /g')"
    fi
    if grep -q '^N' "$recs"; then
        grep '^N' "$recs" | cut -f2- | sed 's/^/  /'
    fi
    if ! grep -q '^[SN]' "$recs"; then
        printf '  None.\n'
    fi

    printf '\nOld domain still in the database\n--------------------------------\n'
    if [[ ! -s "$left" ]]; then
        printf '  None found (guid columns are not counted).\n'
    else
        local host lt lc lines=0 sum
        while IFS= read -r host; do
            sum=$(awk -F'\t' -v h="$host" '$1 == h { s += $3 } END { print s + 0 }' "$left")
            printf '  %s: %d reference(s) (guid columns are not counted; e-mail addresses are included)\n' "$host" "$sum"
            lines=0
            while IFS=$'\t' read -r lt a lc; do
                [[ "$lt" == "$host" ]] || continue
                lines=$((lines + 1))
                [[ "$max" -gt 0 && "$lines" -gt 5 ]] && { printf '      ...\n'; break; }
                printf '      %-38s %8d\n' "$a" "$lc"
            done < "$left"
        done < <(cut -f1 "$left" | awk '!s[$0]++')
    fi

    printf '\nTime per step\n-------------\n'
    if [[ -n "${WPDB_REPORT_STEPS:-}" ]]; then
        while IFS='|' read -r step secs; do
            [[ -n "$step" ]] && printf '  %-30s %s\n' "$step" "$(_report_mmss "${secs:-0}")"
        done <<< "$WPDB_REPORT_STEPS"
    else
        printf '  Not recorded.\n'
    fi
    return 0
}

# ===============================================
# Print and save the report
# ===============================================
# Parameters: report folder (where wpdb-import.conf is), old domain, new domain, site type text, "--", then the
#             old hosts to look for. The logs are read from the private temp folder (secure_tmpdir):
#             replace_single.log replace_custom.log wp_replace_<blog>.log wp_custom_<blog>.log
# Never returns an error (the import already succeeded).
import_report_generate() {
    is_config_true "${CONFIG_IMPORT_REPORT:-true}" || return 0
    local dir="$1" old="$2" new="$3" site="$4" tmp recs left file
    shift 4
    [[ "${1:-}" == "--" ]] && shift
    tmp=$(secure_tmpdir 2>/dev/null) || return 0
    recs="$tmp/report_records.txt"; left="$tmp/report_left.txt"
    report_parse_logs "$tmp"/replace_single.log "$tmp"/replace_custom.log "$tmp"/wp_replace_*.log "$tmp"/wp_custom_*.log > "$recs" 2>/dev/null
    report_leftovers "$@" > "$left" 2>/dev/null

    printf "\n${CYAN}${BOLD}📋 Post-import report${RESET}\n"
    _report_text 10 "$old" "$new" "$site" "$recs" "$left" | sed 's/^/   /'

    if [[ -d "$dir" && -w "$dir" ]]; then
        file="$dir/wpdb-import-report.txt"
        report_rotate "$dir" "${CONFIG_REPORT_KEEP:-5}" 2>/dev/null
        if (umask 077; _report_text 0 "$old" "$new" "$site" "$recs" "$left" > "$file") 2>/dev/null; then
            chmod 600 "$file" 2>/dev/null
            printf "\n   ${GREEN}💾 Report saved:${RESET} %s ${DIM}(mode 600; report_keep=%s; import_report=false turns it off)${RESET}\n" "$file" "${CONFIG_REPORT_KEEP:-5}"
        else
            printf "\n   ${YELLOW}⚠️  Could not save the report in %s.${RESET}\n" "$dir"
        fi
    else
        printf "\n   ${YELLOW}⚠️  Could not save the report: %s is not writable.${RESET}\n" "$dir"
    fi
    rm -f "$recs" "$left" 2>/dev/null
    return 0
}

export -f report_step_add _report_mmss report_parse_logs report_leftovers report_old_hosts report_rotate _report_text import_report_generate 2>/dev/null
