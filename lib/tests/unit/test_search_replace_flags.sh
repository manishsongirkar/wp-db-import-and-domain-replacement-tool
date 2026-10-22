#!/usr/bin/env bash

# ================================================================
# Search-Replace Flags (skip_tables, precise) - Tests
# ================================================================
#
# Description:
#   Tests for issue #45. WP-CLI is replaced by a recorder, so the exact commands are checked:
#   every pass of run_search_replace (single site, www, multisite --url and --network) and every
#   call of the custom mappings (dm_run, also per site and with a dry-run flag) gets the same
#   flags (sr_build_flags), including --skip-tables and --precise. Also checks: the default
#   (no keys) gives the same flags as before, bad skip_tables values are refused, wildcard
#   matching, the config upgrade (adds the keys, changes nothing else), config-validate,
#   config-show and the wiring in the import script (the doctor row is in test_doctor.sh,
#   the dry-run counts in test_dry_run.sh, a real server run in test_real_import.sh).
#
# Usage:
#   ./lib/tests/unit/test_search_replace_flags.sh
#
# ================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../test_framework.sh"

_F_ROOT="$PROJECT_ROOT_DIR"
_F_WORK=""

_chk() {
    local desc="$1"; shift
    if "$@" >/dev/null 2>&1; then
        printf "  ✅ %s\n" "$desc"
    else
        printf "  ❌ %s\n" "$desc"
        ((errors++))
    fi
}
_finish() { if [[ "$errors" -eq 0 ]]; then pass_test "$1"; else fail_test "$errors check(s) failed"; fi; }

_f_load() {
    source "$_F_ROOT/lib/core/utils.sh" >/dev/null 2>&1
    source "$_F_ROOT/lib/config/config_manager.sh" >/dev/null 2>&1
    source "$_F_ROOT/lib/config/integration.sh" >/dev/null 2>&1
    source "$_F_ROOT/lib/database/sql_source.sh" >/dev/null 2>&1
    source "$_F_ROOT/lib/database/search_replace.sh" >/dev/null 2>&1
    source "$_F_ROOT/lib/database/domain_mappings.sh" >/dev/null 2>&1
}

# Recorder: one line per WP-CLI call, arguments joined by |
_f_recorder() {
    _F_CALLS="$_F_WORK/calls.$RANDOM"; : > "$_F_CALLS"
    execute_wp_cli() { local IFS='|'; printf "%s\n" "$*" >> "$_F_CALLS"; return 0; }
}

# Every recorded search-replace line must contain every given argument ("|arg" matches the whole argument)
_f_every_call_has() {
    local f="$1" a l n=0; shift
    while IFS= read -r l; do
        [[ "$l" == search-replace* ]] || continue
        n=$((n + 1))
        for a in "$@"; do [[ "|$l|" == *"|$a|"* ]] || return 1; done
    done < "$f"
    [[ "$n" -gt 0 ]]
}
_f_no_call_has() {
    local f="$1" a; shift
    for a in "$@"; do ! grep -q -- "|$a" "$f" || return 1; done
}
_f_calls() { grep -c '^search-replace' "$1" | tr -d ' '; }

# ----------------------------------------------------------------
test_flags() {
    start_test "Flags" "skip_tables and precise reach every pass; no keys = the same flags as before"
    _f_load; _f_recorder
    local errors=0 log="$_F_WORK/sr.log" n
    local all_tables_flag="--all-tables" dry_run_flag="" skip_tables_flag="" precise_flag=""

    # default: no new flag, same flags as before the keys existed
    run_search_replace "old-site.com" "new-site.test" "$log" "" >/dev/null 2>&1
    _chk "default: 2 passes, no --skip-tables and no --precise" bash -c 'test "$1" = 2 && ! grep -qE -e "--skip-tables" -e "--precise" "$0"' "$_F_CALLS" "$(_f_calls "$_F_CALLS")"
    _chk "default: the flags are the old ones, in the old order" bash -c 'while read -r l; do [[ "$l" == *"|--skip-columns=guid|--report-changed-only|--skip-plugins|--skip-themes|--skip-packages|--all-tables" ]] || exit 1; done < "$0"' "$_F_CALLS"

    # single site: plain + escaped
    : > "$_F_CALLS"; skip_tables_flag="--skip-tables=wp_a,wp_b_*"; precise_flag="--precise"
    run_search_replace "old-site.com" "new-site.test" "$log" "" >/dev/null 2>&1
    _chk "single site: 2 passes"                           test "$(_f_calls "$_F_CALLS")" = 2
    _chk "single site: --skip-tables and --precise on every pass" _f_every_call_has "$_F_CALLS" "--skip-tables=wp_a,wp_b_*" "--precise" "--all-tables"

    # www source: 4 passes
    : > "$_F_CALLS"
    run_search_replace "www.old-site.com" "new-site.test" "$log" "" >/dev/null 2>&1
    _chk "www source: 4 passes, all with both flags"       bash -c 'test "$1" = 4' _ "$(_f_calls "$_F_CALLS")"
    _chk "www source: --skip-tables and --precise on all 4" _f_every_call_has "$_F_CALLS" "--skip-tables=wp_a,wp_b_*" "--precise"

    # multisite: --network and --url
    : > "$_F_CALLS"
    run_search_replace "old-site.com" "new-site.test" "$log" "--network" >/dev/null 2>&1
    _chk "--network: both flags and --network on every pass" _f_every_call_has "$_F_CALLS" "--skip-tables=wp_a,wp_b_*" "--precise" "--network"
    : > "$_F_CALLS"
    run_search_replace "old-site.com" "new-site.test" "$log" "--url=news.old-site.com" "/news/" "/news/" >/dev/null 2>&1
    _chk "--url: both flags and --url on every pass"       _f_every_call_has "$_F_CALLS" "--skip-tables=wp_a,wp_b_*" "--precise" "--url=news.old-site.com"

    # dry-run flag travels with the same flags
    : > "$_F_CALLS"; dry_run_flag="--dry-run"
    run_search_replace "old-site.com" "new-site.test" "$log" "" >/dev/null 2>&1
    _chk "dry-run flag: same flags plus --dry-run on every pass" _f_every_call_has "$_F_CALLS" "--skip-tables=wp_a,wp_b_*" "--precise" "--dry-run"
    dry_run_flag=""

    # each flag alone
    : > "$_F_CALLS"; precise_flag=""
    run_search_replace "old-site.com" "new-site.test" "$log" "" >/dev/null 2>&1
    _chk "only skip_tables: no --precise"                  bash -c 'grep -q -e "--skip-tables=wp_a,wp_b_\*" "$0" && ! grep -q -e "--precise" "$0"' "$_F_CALLS"
    : > "$_F_CALLS"; precise_flag="--precise"; skip_tables_flag=""
    run_search_replace "old-site.com" "new-site.test" "$log" "" >/dev/null 2>&1
    _chk "only precise: no --skip-tables"                  bash -c 'grep -q -e "--precise" "$0" && ! grep -q -e "--skip-tables" "$0"' "$_F_CALLS"

    # without --all-tables the flags still arrive
    : > "$_F_CALLS"; skip_tables_flag="--skip-tables=wp_x"; all_tables_flag=""
    run_search_replace "old-site.com" "new-site.test" "$log" "" >/dev/null 2>&1
    _chk "all_tables=false: --skip-tables still passed, no --all-tables" bash -c 'grep -q -e "--skip-tables=wp_x" "$0" && ! grep -q -e "--all-tables" "$0"' "$_F_CALLS"
    all_tables_flag="--all-tables"

    # a failing call stops the passes and returns 1 (as before)
    execute_wp_cli() { return 1; }
    run_search_replace "old-site.com" "new-site.test" "$log" "" >/dev/null 2>&1; n=$?
    _chk "a failing WP-CLI call: rc 1"                     test "$n" -eq 1
    _f_recorder

    # sr_build_flags directly
    skip_tables_flag="--skip-tables=wp_x"; precise_flag="--precise"
    sr_build_flags "--all-tables-with-prefix"
    _chk "sr_build_flags: an override replaces --all-tables" bash -c 'l="$*"; [[ "$l" == *"--all-tables-with-prefix"* && "$l" != *" --all-tables "* && "$l" == *"--skip-tables=wp_x"* && "$l" == *"--precise"* ]]' "${SR_FLAGS[@]}"
    sr_build_flags ""
    _chk "sr_build_flags: an empty override means no all-tables flag" bash -c '[[ "$*" != *"--all-tables"* ]]' "${SR_FLAGS[@]}"
    _finish "every pass gets the same flags"
}

# ----------------------------------------------------------------
test_custom_mappings() {
    start_test "Custom mappings" "dm_run and the per-site scope get the same flags"
    _f_load; _f_recorder
    local errors=0 log="$_F_WORK/dm.log" c
    local all_tables_flag="--all-tables" dry_run_flag="" skip_tables_flag="--skip-tables=wp_a,wp_b_*" precise_flag="--precise"
    c="$_F_WORK/dm.conf"; printf '[domain_mappings]\n//cdn.example.com => //cdn.target.test\n\n[site_domain_mappings]\n2: //shop.example.com => //shop.target.test\n' > "$c"

    dm_load "$c" domain_mappings
    dm_run "$log" "" >/dev/null 2>&1
    _chk "single site: 2 calls (plain + JSON), both flags on each"  bash -c 'test "$1" = 2' _ "$(_f_calls "$_F_CALLS")"
    _chk "single site: --skip-tables, --precise and --all-tables"    _f_every_call_has "$_F_CALLS" "--skip-tables=wp_a,wp_b_*" "--precise" "--all-tables"
    : > "$_F_CALLS"; dry_run_flag="--dry-run"
    dm_run "$log" "--network" >/dev/null 2>&1
    _chk "network + dry run: all flags on every call"                _f_every_call_has "$_F_CALLS" "--skip-tables=wp_a,wp_b_*" "--precise" "--network" "--dry-run" "--all-tables"
    dry_run_flag=""

    : > "$_F_CALLS"
    dm_run "$log" "" "wp_2_posts wp_2_options" >/dev/null 2>&1
    _chk "with a table list: tables, --all-tables-with-prefix and both flags, no --all-tables" bash -c 'while read -r l; do [[ "$l" == *"|wp_2_posts|wp_2_options|"* && "$l" == *"|--all-tables-with-prefix"* && "$l" == *"|--skip-tables=wp_a,wp_b_*"* && "$l" == *"|--precise"* && "$l" != *"|--all-tables|"* && "$l" != *"|--all-tables" ]] || exit 1; done < "$0"' "$_F_CALLS"

    # per-site scope (tables are looked up through WP-CLI)
    execute_wp_cli() {
        local IFS='|'; printf "%s\n" "$*" >> "$_F_CALLS"
        case "$*" in
            "db|prefix") echo "wp_" ;;
            "db|tables|wp_2_*|--all-tables-with-prefix") printf "wp_2_posts\nwp_2_options\n" ;;
        esac
        return 0
    }
    : > "$_F_CALLS"
    dm_run_site_scope "$c" 2 "$log" >/dev/null 2>&1
    _chk "per-site scope: both flags on its calls"                   _f_every_call_has "$_F_CALLS" "--skip-tables=wp_a,wp_b_*" "--precise" "--all-tables-with-prefix"

    # no keys: nothing new
    skip_tables_flag=""; precise_flag=""; _f_recorder
    dm_run "$log" "" >/dev/null 2>&1
    _chk "no keys: no --skip-tables and no --precise"                _f_no_call_has "$_F_CALLS" "--skip-tables" "--precise"
    _finish "custom mappings use the shared flags"
}

# ----------------------------------------------------------------
test_values() {
    start_test "Values" "skip_tables is cleaned or refused, precise must be a boolean, wildcard matching"
    _f_load
    local errors=0 out
    _chk "empty value: empty list, ok"                      bash -c 'source "'"$_F_ROOT"'/lib/core/utils.sh" >/dev/null 2>&1; [[ -z "$(sr_normalize_skip_tables "")" ]]'
    _chk "spaces and empty items are removed"               test "$(sr_normalize_skip_tables " wp_a ,, wp_b_* , ")" = "wp_a,wp_b_*"
    _chk "wildcards * and ? are kept"                       test "$(sr_normalize_skip_tables "wp_?_log,*_cache")" = "wp_?_log,*_cache"
    _chk "a single table"                                   test "$(sr_normalize_skip_tables "wp_custom")" = "wp_custom"
    local bad
    for bad in "wp_a;DROP" "wp a" "wp_a'b" 'wp_a"' 'wp_a`' 'wp_$(id)' "wp_a|b" "wp_[ab]" "wp_a\\b" "../x"; do
        _chk "refused: $bad"                                bash -c 'source "'"$_F_ROOT"'/lib/core/utils.sh" >/dev/null 2>&1; ! sr_normalize_skip_tables "$0" >/dev/null' "$bad"
    done
    out=$(sr_normalize_skip_tables "wp_a;DROP" 2>&1)
    _chk "the message names the bad item"                   grep -q "'wp_a;DROP'" <<< "$out"

    _chk "validate: both empty is fine"                     sr_validate_settings "" ""
    _chk "validate: a list and true is fine"                sr_validate_settings "wp_a,wp_b*" "true"
    for bad in true TRUE false yes no 1 0 on off; do
        _chk "precise=$bad is accepted"                     sr_validate_settings "" "$bad"
    done
    _chk "precise=maybe is refused"                         bash -c 'source "'"$_F_ROOT"'/lib/core/utils.sh" >/dev/null 2>&1; ! sr_validate_settings "" "maybe" >/dev/null'
    out=$(sr_validate_settings "bad name" "maybe")
    _chk "both problems are reported, one per line"         test "$(printf '%s\n' "$out" | grep -c .)" = 2

    _chk "match: exact name"                                sr_table_is_skipped "wp_cache" "wp_cache"
    _chk "match: * wildcard"                                sr_table_is_skipped "wp_logs_2024" "wp_other,wp_logs_*"
    _chk "match: ? wildcard (one character)"                sr_table_is_skipped "wp_2_log" "wp_?_log"
    _chk "no match: ? is exactly one character"             bash -c 'source "'"$_F_ROOT"'/lib/core/utils.sh" >/dev/null 2>&1; ! sr_table_is_skipped "wp_12_log" "wp_?_log"'
    _chk "no match: a different table"                      bash -c 'source "'"$_F_ROOT"'/lib/core/utils.sh" >/dev/null 2>&1; ! sr_table_is_skipped "wp_posts" "wp_cache,wp_logs_*"'
    _chk "no match: a prefix of the name is not enough"     bash -c 'source "'"$_F_ROOT"'/lib/core/utils.sh" >/dev/null 2>&1; ! sr_table_is_skipped "wp_posts_extra" "wp_posts"'
    _finish "values are checked"
}

# ----------------------------------------------------------------
test_config() {
    start_test "Config" "upgrade adds the keys only, load, validate, show, new config, examples"
    _f_load
    local errors=0 old="$_F_WORK/old.conf" run="$_F_WORK/run.conf" a out
    printf '%s\n' '[general]' 'sql_file=dump.sql' 'old_domain=prod.com' 'new_domain=local.test' 'all_tables=true' 'dry_run=false' 'auto_proceed=true' 'use_socket=false' 'mysql_socket=' 'import_optimizations=auto' 'parallel_import=false' 'backup_before_import=ask' 'backup_dir=' 'backup_keep=5' 'backup_keep_days=0' 'backup_encrypt=false' 'backup_gpg_recipient=' '' '[site_mappings]' '1:prod.com:local.test' > "$old"
    cp "$old" "$run"
    ensure_socket_config_settings "$run" >/dev/null 2>&1
    _chk "the upgrade names the two keys"                  test "$CONFIG_SETTINGS_MIGRATED_ITEMS" = "skip_tables, precise, [domain_mappings], [site_domain_mappings]"
    _chk "defaults: skip_tables empty, precise=false"      bash -c 'grep -qx "skip_tables=" "$0" && grep -qx "precise=false" "$0"' "$run"
    _chk "every new key comes with its comment"            bash -c 'source "'"$_F_ROOT"'/lib/core/utils.sh" >/dev/null 2>&1; source "'"$_F_ROOT"'/lib/config/config_manager.sh" >/dev/null 2>&1; t=$(cat "$0"); for k in skip_tables precise; do [[ -n "$(config_key_comment $k)" && "$t" == *"$(config_key_comment $k)"*"${k}="* ]] || exit 1; done' "$run"
    _chk "no line of the old file changed or was removed"  bash -c '! diff "$0" "$1" | grep -q "^<"' "$old" "$run"
    a=$(cksum < "$run"); ensure_socket_config_settings "$run" >/dev/null 2>&1
    _chk "a second run changes nothing"                    test "$a" = "$(cksum < "$run")"

    # values the user already set are never changed
    printf '%s\n' '[general]' 'sql_file=a.sql' 'old_domain=a.com' 'new_domain=b.test' 'skip_tables=wp_keep,wp_logs_*' 'precise=true' '' '[site_mappings]' '1:a.com:b.test' > "$run"
    ensure_socket_config_settings "$run" >/dev/null 2>&1
    _chk "existing values are kept (skip_tables, precise)" bash -c 'grep -qx "skip_tables=wp_keep,wp_logs_\*" "$0" && grep -qx "precise=true" "$0" && [[ $(grep -c "^skip_tables=" "$0") = 1 && $(grep -c "^precise=" "$0") = 1 ]]' "$run"
    _chk "the item list does not name keys that exist"     bash -c '[[ "$0" != *skip_tables* && "$0" != *precise* ]]' "$CONFIG_SETTINGS_MIGRATED_ITEMS"

    # load
    load_import_config "$run" >/dev/null 2>&1
    _chk "load_import_config reads both keys"              test "$CONFIG_SKIP_TABLES" = "wp_keep,wp_logs_*" -a "$CONFIG_PRECISE" = "true"
    cp "$old" "$_F_WORK/nokeys.conf"
    load_import_config "$_F_WORK/nokeys.conf" >/dev/null 2>&1
    _chk "a config without the keys: the upgrade adds the defaults, nothing is skipped" bash -c '[[ -z "$CONFIG_SKIP_TABLES" && "$CONFIG_PRECISE" == false ]]'

    # a new config
    create_config_file "$_F_WORK/fresh.conf" a.sql a.com b.test >/dev/null 2>&1
    _chk "a new config contains both keys"                 bash -c 'grep -qx "skip_tables=" "$0" && grep -qx "precise=false" "$0"' "$_F_WORK/fresh.conf"
    _chk "a new config validates"                          bash -c 'source "'"$_F_ROOT"'/lib/core/utils.sh" >/dev/null 2>&1; source "'"$_F_ROOT"'/lib/config/config_manager.sh" >/dev/null 2>&1; validate_config_file "$0"' "$_F_WORK/fresh.conf"

    # validate
    out=$(validate_config_file "$run" 2>&1)
    _chk "validate: good values pass"                      bash -c 'source "'"$_F_ROOT"'/lib/core/utils.sh" >/dev/null 2>&1; source "'"$_F_ROOT"'/lib/config/config_manager.sh" >/dev/null 2>&1; validate_config_file "$0"' "$run"
    sed -i.bak 's/^skip_tables=.*/skip_tables=wp keep;x/; s/^precise=.*/precise=maybe/' "$run" && rm -f "$run.bak"
    out=$(validate_config_file "$run" 2>&1); a=$?
    _chk "validate: bad values fail with a message each"   bash -c 'test "$1" -ne 0 && grep -q "skip_tables" <<< "$0" && grep -q "precise" <<< "$0"' "$out" "$a"

    # show
    printf '%s\n' '[general]' 'sql_file=a.sql' 'skip_tables=wp_keep' 'precise=true' '[site_mappings]' > "$run"
    out=$(show_config "$run" 2>&1 | sed 's/\x1b\[[0-9;]*[a-zA-Z]//g')
    _chk "config-show prints Skip Tables and Precise"      bash -c 'grep -q "Skip Tables: *wp_keep" <<< "$0" && grep -q "Precise: *true" <<< "$0"' "$out"
    printf '%s\n' '[general]' 'sql_file=a.sql' '[site_mappings]' > "$run"
    out=$(show_config "$run" 2>&1 | sed 's/\x1b\[[0-9;]*[a-zA-Z]//g')
    _chk "config-show: defaults are none and false"        bash -c 'grep -q "Skip Tables: *none" <<< "$0" && grep -q "Precise: *false" <<< "$0"' "$out"

    # example configs
    local f
    for f in single multisite; do
        _chk "example $f config has both keys"             bash -c 'grep -qx "skip_tables=" "$0" && grep -qx "precise=false" "$0"' "$_F_ROOT/wpdb-import-example-$f.conf"
    done
    _finish "config handling is complete"
}

# ----------------------------------------------------------------
test_wiring() {
    start_test "Wiring" "flags built from the config, bad values stop the import before any change"
    local errors=0 f="$_F_ROOT/import_wp_db.sh" a b

    _chk "the import flags come from the config"          bash -c 'grep -q "skip_tables_flag=\"--skip-tables=\$skip_tables_list\"" "$0" && grep -q "precise_flag=\"--precise\"" "$0"' "$f"
    a=$(grep -n 'sr_validate_settings "\${CONFIG_SKIP_TABLES' "$f" | head -1 | cut -d: -f1)
    b=$(grep -n 'decide_dry_run_mode "\$config_path"' "$f" | head -1 | cut -d: -f1)
    _chk "bad values stop the run before the dry-run decision (before any change)" test -n "$a" -a -n "$b" -a "$a" -lt "$b"
    a=$(grep -n 'skip_tables_flag="--skip-tables' "$f" | head -1 | cut -d: -f1)
    b=$(grep -n 'process_multisite_mappings "\$main_site_id"' "$f" | head -1 | cut -d: -f1)
    _chk "the flags are set before the first search-replace" test -n "$a" -a -n "$b" -a "$a" -lt "$b"
    _chk "the dry run leaves skipped tables out of the counts" grep -q 'sr_table_is_skipped' "$_F_ROOT/lib/database/db_dry_run.sh"
    _chk "refusal text names the fix"                      grep -q 'Fix skip_tables and precise' "$f"
    _finish "wiring is complete"
}

run_search_replace_flags_tests() {
    printf "\n${CYAN}${BOLD}🧪 Search-Replace Flags Tests${RESET}\n"
    printf "%s\n\n" "$(printf '=%.0s' {1..50})"
    init_test_session "search_replace_flags"
    _F_WORK=$(mktemp -d "${TMPDIR:-/tmp}/wpdb-srf-test.XXXXXX")
    trap 'rm -rf "$_F_WORK"' EXIT

    test_flags
    test_custom_mappings
    test_values
    test_config
    test_wiring

    finalize_test_session
    return $?
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    run_search_replace_flags_tests
fi
