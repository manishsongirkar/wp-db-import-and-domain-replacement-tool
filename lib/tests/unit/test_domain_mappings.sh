#!/usr/bin/env bash

# ================================================================
# Custom Domain / URL Mappings - Tests
# ================================================================
#
# Description:
#   Tests for issue #23 ([domain_mappings] and [site_domain_mappings]). WP-CLI is replaced
#   by a recorder, so the exact search-replace commands are checked: anchoring (a bare host is
#   rejected, so emails and plain text are never matched), replace-form rules, longest-first
#   order, duplicates, chains, protected site domains, plain + JSON-escaped passes, flags for
#   single site / --network / --url, failure handling, the dump report (www variant, other
#   hosts, suggestions, nothing written), config validation, and the regression guards
#   (no section = no command; a [site_domain_mappings] line never counts as a site mapping).
#
# Usage:
#   ./lib/tests/unit/test_domain_mappings.sh
#
# ================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../test_framework.sh"

_M_ROOT="$PROJECT_ROOT_DIR"
_M_WORK=""

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
_strip() { sed 's/\x1b\[[0-9;]*[a-zA-Z]//g'; }

_m_load() {
    source "$_M_ROOT/lib/core/utils.sh" >/dev/null 2>&1
    source "$_M_ROOT/lib/config/config_manager.sh" >/dev/null 2>&1
    source "$_M_ROOT/lib/database/sql_source.sh" >/dev/null 2>&1
    source "$_M_ROOT/lib/database/domain_mappings.sh" >/dev/null 2>&1
}

# Recorder: every WP-CLI call is appended to $_M_CALLS (one line per call, args joined by |)
_m_recorder() {
    _M_CALLS="$_M_WORK/calls.$RANDOM"; : > "$_M_CALLS"
    execute_wp_cli() {
        local IFS='|'; printf "%s\n" "$*" >> "$_M_CALLS"
        [[ -n "${M_FAIL_ON:-}" && "$*" == *"$M_FAIL_ON"* ]] && return 1
        return 0
    }
}

_m_conf() { local f="$_M_WORK/c.$RANDOM.conf"; printf "%b" "$1" > "$f"; printf "%s" "$f"; }

# ----------------------------------------------------------------
test_validation() {
    start_test "Validation" "anchored searches only, replace form, characters, same value"
    _m_load
    local errors=0 why
    _chk "//host => //newhost is valid"                   dm_validate_pair "//cdn.example.com" "//cdn.target.test"
    _chk "https URL => https URL is valid"                dm_validate_pair "https://api.example.com/v2" "https://api.sandbox.test/v2"
    _chk "https URL => //host is valid"                   dm_validate_pair "https://api.example.com" "//api.test"
    _chk "bare host is rejected"                          bash -c 'source "'"$_M_ROOT"'/lib/database/domain_mappings.sh"; ! dm_validate_pair "cdn.example.com" "cdn.test"'
    why=$(dm_validate_pair "cdn.example.com" "cdn.test")
    _chk "bare host: the message says to write //host"    grep -q '//cdn.example.com' <<< "$why"
    _chk "bare host: the message names emails"            grep -qi 'email' <<< "$why"
    _chk "an email-like search is rejected"               bash -c 'source "'"$_M_ROOT"'/lib/database/domain_mappings.sh"; ! dm_validate_pair "@example.com" "@test"'
    _chk "//host => full URL is rejected (https:https://)" bash -c 'source "'"$_M_ROOT"'/lib/database/domain_mappings.sh"; ! dm_validate_pair "//a.example.com" "https://a.test"'
    _chk "//host => bare host is rejected"                bash -c 'source "'"$_M_ROOT"'/lib/database/domain_mappings.sh"; ! dm_validate_pair "//a.example.com" "a.test"'
    _chk "scheme search => bare host is rejected"         bash -c 'source "'"$_M_ROOT"'/lib/database/domain_mappings.sh"; ! dm_validate_pair "https://a.example.com" "a.test"'
    _chk "space is rejected"                              bash -c 'source "'"$_M_ROOT"'/lib/database/domain_mappings.sh"; ! dm_validate_pair "//a b.com" "//c.com"'
    _chk "quote is rejected"                              bash -c 'source "'"$_M_ROOT"'/lib/database/domain_mappings.sh"; ! dm_validate_pair "//a.com\"" "//c.com"'
    _chk "backslash is rejected"                          bash -c 'source "'"$_M_ROOT"'/lib/database/domain_mappings.sh"; ! dm_validate_pair "//a.com\\x" "//c.com"'
    _chk "empty replace is rejected"                      bash -c 'source "'"$_M_ROOT"'/lib/database/domain_mappings.sh"; ! dm_validate_pair "//a.com" ""'
    _chk "no host after // is rejected"                   bash -c 'source "'"$_M_ROOT"'/lib/database/domain_mappings.sh"; ! dm_validate_pair "///x" "//y"'
    _chk "same search and replace is rejected"            bash -c 'source "'"$_M_ROOT"'/lib/database/domain_mappings.sh"; ! dm_validate_pair "//a.com" "//a.com"'
    # the anchor really keeps emails and plain text out: the search is not inside these strings
    local text='Mail test@example.com or mailto:a@example.com, visit example.com or www.example.com'
    _chk "//example.com does not occur in emails or plain text" bash -c '[[ "$1" != *"//example.com"* ]]' _ "$text"
    _finish "validation rules hold"
}

# ----------------------------------------------------------------
test_loading() {
    start_test "Loading" "section parsing, order, duplicates, chains, protected domains, per-site filter"
    _m_load
    local errors=0 c
    c=$(_m_conf "[general]\nold_domain=a.com\n\n[domain_mappings]\n# comment\n\n//cdn.example.com => //cdn.target.test\r\nhttps://api.example.com/v2/long/path => https://api.test/v2/long/path\n//api.example.com => //api.test\n//cdn.example.com => //other.test\n[site_mappings]\n1:a.com:b.test\n")
    dm_load "$c" domain_mappings; local rc=$?
    _chk "valid section loads (rc 0)"                      test "$rc" -eq 0
    _chk "three unique entries (duplicate dropped)"        bash -c '[[ $(printf "%s\n" "$0" | grep -c .) -eq 3 ]]' "$DM_ENTRIES"
    _chk "duplicate gives a warning, first entry wins"     bash -c 'grep -q "listed twice" <<< "$0" && grep -q "cdn.target.test" <<< "$1" && ! grep -q "other.test" <<< "$1"' "$DM_WARNINGS" "$DM_ENTRIES"
    _chk "longest search first"                            bash -c 'first=$(printf "%s\n" "$0" | head -1 | cut -f1); [[ "$first" == "https://api.example.com/v2/long/path" ]]' "$DM_ENTRIES"
    _chk "CRLF line endings are handled"                   bash -c '! grep -q $'"'"'\r'"'"' <<< "$0"' "$DM_ENTRIES"
    _chk "other sections are not read"                     bash -c '! grep -q "a.com" <<< "$0"' "$DM_ENTRIES"

    c=$(_m_conf "[domain_mappings]\nexample.com => example.test\n//ok.com => //ok.test\n//noarrow.com\n")
    dm_load "$c" domain_mappings; rc=$?
    _chk "invalid lines give rc 1 and a message each"      bash -c 'test "$1" -eq 1 && [[ $(printf "%s\n" "$0" | grep -c .) -eq 2 ]]' "$DM_ERRORS" "$rc"
    _chk "the missing => is explained"                     grep -q "expected 'old => new'" <<< "$DM_ERRORS"
    _chk "the valid entry still loads"                     grep -q '//ok.com' <<< "$DM_ENTRIES"

    c=$(_m_conf "[domain_mappings]\n//a.example.com => //b.example.com/x\n//b.example.com => //c.test\n")
    dm_load "$c" domain_mappings; rc=$?
    _chk "a chain (replacement contains another search) is an error" bash -c 'test "$1" -eq 1 && grep -q "replaced twice" <<< "$0"' "$DM_ERRORS" "$rc"

    c=$(_m_conf "[domain_mappings]\n//shop.example.com => //shop.test\n//cdn.example.com => //cdn.test\n")
    dm_load "$c" domain_mappings "" "shop.example.com example.com"; rc=$?
    _chk "a search equal to a site domain is an error"     bash -c 'test "$1" -eq 1 && grep -q "domain of a site" <<< "$0"' "$DM_ERRORS" "$rc"
    _chk "the other entry still loads"                     grep -q 'cdn.example.com' <<< "$DM_ENTRIES"

    c=$(_m_conf "[site_domain_mappings]\n2: //shop-cdn.example.com => //shop-cdn.test\n3: //other.example.com => //other.test\nbad line\n")
    dm_load "$c" site_domain_mappings 2; rc=$?
    _chk "per-site: only the entries of blog 2"            bash -c 'grep -q shop-cdn <<< "$0" && ! grep -q other.example <<< "$0"' "$DM_ENTRIES"
    _chk "per-site: a line without blog_id is an error"    grep -q "expected 'blog_id: old => new'" <<< "$DM_ERRORS"

    c=$(_m_conf "[general]\nold_domain=a.com\n")
    dm_load "$c" domain_mappings; rc=$?
    _chk "no section: rc 0 and no entries"                 bash -c 'test "$1" -eq 0 && test -z "$0"' "$DM_ENTRIES" "$rc"
    dm_load "$_M_WORK/does-not-exist.conf" domain_mappings; rc=$?
    _chk "no config file: rc 0 and no entries"             bash -c 'test "$1" -eq 0 && test -z "$0"' "$DM_ENTRIES" "$rc"
    _finish "loading rules hold"
}

# ----------------------------------------------------------------
test_commands() {
    start_test "Commands" "exact WP-CLI calls: order, plain + JSON-escaped, flags, failures"
    _m_load; _m_recorder
    local errors=0 c log="$_M_WORK/run.log" out
    c=$(_m_conf "[domain_mappings]\n//cdn.example.com => //cdn.target.test\nhttps://api.example.com/v2 => https://api.sandbox.test/v2\n")
    dm_load "$c" domain_mappings
    all_tables_flag=""; dry_run_flag=""
    out=$(dm_run "$log" "" 2>&1); local rc=$?
    local n; n=$(wc -l < "$_M_CALLS" | tr -d ' ')
    _chk "single site: rc 0, 4 calls (2 entries x plain + JSON)" test "$rc" -eq 0 -a "$n" -eq 4
    _chk "longest search first (the https entry is call 1)" bash -c 'sed -n 1p "$0" | grep -q "^search-replace|https://api.example.com/v2|https://api.sandbox.test/v2|"' "$_M_CALLS"
    _chk "JSON-escaped form: / becomes \\/"                 bash -c 'sed -n 2p "$0" | grep -qF "search-replace|https:\/\/api.example.com\/v2|https:\/\/api.sandbox.test\/v2|"' "$_M_CALLS"
    _chk "//host plain form"                                bash -c 'sed -n 3p "$0" | grep -q "^search-replace|//cdn.example.com|//cdn.target.test|"' "$_M_CALLS"
    _chk "//host JSON-escaped form"                         bash -c 'sed -n 4p "$0" | grep -qF "search-replace|\/\/cdn.example.com|\/\/cdn.target.test|"' "$_M_CALLS"
    _chk "guid is skipped, plugins and themes are not loaded" bash -c 'while read -r l; do [[ "$l" == *"--skip-columns=guid"* && "$l" == *"--skip-plugins"* && "$l" == *"--skip-themes"* ]] || exit 1; done < "$0"' "$_M_CALLS"
    _chk "single site: no --network and no --url"           bash -c '! grep -q -e "--network" -e "--url=" "$0"' "$_M_CALLS"
    _chk "progress line per entry"                          bash -c 'grep -q "//cdn.example.com → //cdn.target.test" <<< "$0"' "$out"

    : > "$_M_CALLS"; all_tables_flag="--all-tables"; dry_run_flag="--dry-run"
    dm_run "$log" "--network" >/dev/null 2>&1
    _chk "network: --network, --all-tables and --dry-run on every call" bash -c 'while read -r l; do [[ "$l" == *"|--network"* && "$l" == *"|--all-tables"* && "$l" == *"|--dry-run"* ]] || exit 1; done < "$0"' "$_M_CALLS"
    : > "$_M_CALLS"; all_tables_flag="--all-tables"
    dm_run "$log" "" "wp_2_posts wp_2_options" >/dev/null 2>&1
    _chk "with a table list: tables + --all-tables-with-prefix, not --all-tables" bash -c 'while read -r l; do [[ "$l" == *"|wp_2_posts|wp_2_options|"* && "$l" == *"|--all-tables-with-prefix"* && "$l" != *"|--all-tables|"* && "$l" != *"|--all-tables" ]] || exit 1; done < "$0"' "$_M_CALLS"
    all_tables_flag=""; dry_run_flag=""

    : > "$_M_CALLS"; M_FAIL_ON="//cdn.example.com"
    out=$(dm_run "$log" "" 2>&1); rc=$?
    unset M_FAIL_ON
    _chk "a failing WP-CLI call: rc 1 and the log path is shown" bash -c 'test "$1" -eq 1 && grep -q "WP-CLI failed" <<< "$0"' "$out" "$rc"

    : > "$_M_CALLS"
    dm_load "$(_m_conf "[general]\nold_domain=a.com\n")" domain_mappings
    dm_run "$log" "" >/dev/null 2>&1; rc=$?
    _chk "no [domain_mappings]: rc 0 and no WP-CLI call (no regression)" bash -c 'test "$1" -eq 0 && ! test -s "$0"' "$_M_CALLS" "$rc"

    # per-site scope: only the tables of that site, never --url
    c=$(_m_conf "[site_domain_mappings]\n2: //shop-cdn.example.com => //shop-cdn.test\n3: //x.example.com => //x.test\n")
    execute_wp_cli() {
        local IFS='|'; printf "%s\n" "$*" >> "$_M_CALLS"
        case "$*" in
            "db|prefix") echo "wp_" ;;
            "db|tables|wp_2_*|--all-tables-with-prefix") printf "wp_2_posts\nwp_2_options\n" ;;
            "db|tables|--scope=blog") printf "wp_posts\nwp_options\n" ;;
            "db|tables|wp_9_*|--all-tables-with-prefix") : ;;
        esac
        return 0
    }
    : > "$_M_CALLS"; all_tables_flag="--all-tables"
    dm_run_site_scope "$c" 2 "$log" >/dev/null 2>&1
    _chk "site 2: only blog 2 entries run, on its tables"  bash -c 'grep -q "^search-replace|//shop-cdn.example.com|//shop-cdn.test|wp_2_posts|wp_2_options|" "$0" && ! grep -q "x.example" "$0"' "$_M_CALLS"
    _chk "site 2: no --url and no --all-tables"            bash -c '! grep "^search-replace" "$0" | grep -qE -e "--url" -e "--all-tables(\||$)"' "$_M_CALLS"
    c=$(_m_conf "[site_domain_mappings]\n1: //main-only.example.com => //main-only.test\n")
    : > "$_M_CALLS"
    dm_run_site_scope "$c" 1 "$log" >/dev/null 2>&1
    _chk "site 1: the main site's tables (--scope=blog)"   bash -c 'grep -q "^search-replace|//main-only.example.com|//main-only.test|wp_posts|wp_options|" "$0"' "$_M_CALLS"
    c=$(_m_conf "[site_domain_mappings]\n9: //x.example.com => //x.test\n")
    : > "$_M_CALLS"
    out=$(dm_run_site_scope "$c" 9 "$log" 2>&1); rc=$?
    _chk "no tables found: rc 1, explained, nothing replaced" bash -c 'test "$1" -eq 1 && grep -q "Could not list the tables" <<< "$0" && ! grep -q "^search-replace" "$2"' "$out" "$rc" "$_M_CALLS"
    c=$(_m_conf "[site_domain_mappings]\n2: //shop-cdn.example.com => //shop-cdn.test\n")
    : > "$_M_CALLS"
    dm_run_site_scope "$c" 5 "$log" >/dev/null 2>&1
    _chk "a blog without entries runs nothing"             bash -c '! test -s "$0"' "$_M_CALLS"
    _finish "commands are exact"
}

# ----------------------------------------------------------------
test_report() {
    start_test "Dump report" "www variant, custom counts, other hosts (no emails), suggestions, read-only"
    _m_load
    local errors=0 dump="$_M_WORK/d.sql" c out before after
    cat > "$dump" <<'SQLEOF'
INSERT INTO wp_posts VALUES ('<a href="https://example.com/a">a</a> <a href="https://example.com/b">b</a>');
INSERT INTO wp_posts VALUES ('<img src="//www.example.com/x.png"> <img src="https:\/\/www.example.com\/y.png">');
INSERT INTO wp_posts VALUES ('<script src="https://cdn.example.com/a.js"></script><script src="https://cdn.example.com/b.js"></script>');
INSERT INTO wp_posts VALUES ('<a href="https://api.thirdparty.io/v1">t</a> contact: test@example.com and info@cdn.example.com');
SQLEOF
    c=$(_m_conf "[general]\nold_domain=example.com\nnew_domain=target.test\n\n[domain_mappings]\n//cdn.example.com => //cdn.target.test\n")
    before=$(cksum < "$c")
    out=$(dm_dry_run_report "$dump" "example.com" "target.test" "$c" 2>&1 | _strip)
    after=$(cksum < "$c")
    _chk "main domain count (2 plain, emails not counted)"  grep -qE '//example.com +2 +\(replaced\)' <<< "$out"
    _chk "www variant counted (plain + JSON-escaped)"       grep -qE '//www.example.com +2 +\(NOT replaced: old_domain has no www\)' <<< "$out"
    _chk "custom entry count"                               grep -qE '//cdn.example.com +2 +→ //cdn.target.test' <<< "$out"
    _chk "other hosts: cdn.example.com and the third party" bash -c 'grep -qE "2 +cdn.example.com" <<< "$0" && grep -qE "1 +api.thirdparty.io" <<< "$0"' "$out"
    _chk "other hosts: the old domain and its www are left out" bash -c '! grep -E "^ +[0-9]+ +(www\.)?example\.com$" <<< "$0"' "$out"
    _chk "other hosts: email domains never appear"          bash -c 'test "$(grep -c "info@" <<< "$0")" -eq 0' "$out"
    _chk "suggested line for the www variant"               grep -q '//www.example.com => //target.test' <<< "$out"
    _chk "the report says nothing was written"              grep -q 'nothing was written' <<< "$out"
    _chk "the config file is not changed"                   test "$before" = "$after"

    out=$(dm_dry_run_report "$dump" "www.example.com" "www.target.test" "" 2>&1 | _strip)
    _chk "old_domain with www: both forms are 'replaced', no suggestion" bash -c 'grep -q "old_domain has www" <<< "$0" && ! grep -q "Suggested" <<< "$0"' "$out"

    gzip -c "$dump" > "$_M_WORK/d.sql.gz"
    out=$(dm_dry_run_report "$_M_WORK/d.sql.gz" "example.com" "target.test" "" 2>&1 | _strip)
    _chk "a .sql.gz dump is read the same way"              grep -qE '//example.com +2 +\(replaced\)' <<< "$out"
    _finish "the report is correct and read-only"
}

# ----------------------------------------------------------------
test_config_integration() {
    start_test "Config integration" "validate, show, template, and the site-mapping regression guard"
    _m_load
    local errors=0 c out
    c=$(_m_conf "[general]\nsql_file=a.sql\nold_domain=a.com\nnew_domain=b.test\n\n[site_mappings]\n\n[domain_mappings]\n//cdn.a.com => //cdn.b.test\n")
    _chk "validate_config_file: valid entries pass"        validate_config_file "$c"
    c=$(_m_conf "[general]\nsql_file=a.sql\nold_domain=a.com\nnew_domain=b.test\n\n[site_mappings]\n\n[domain_mappings]\ncdn.a.com => cdn.b.test\n")
    out=$(validate_config_file "$c" 2>&1 | _strip)
    _chk "validate_config_file: a bare host fails and is named" bash -c '! validate_config_file "$1" >/dev/null 2>&1 && grep -q "\[domain_mappings\].*cdn.a.com" <<< "$0"' "$out" "$c"
    c=$(_m_conf "[general]\nsql_file=a.sql\nold_domain=a.com\nnew_domain=b.test\n\n[site_mappings]\n\n[domain_mappings]\n//cdn.a.com => //cdn.b.test\n")
    out=$(show_config "$c" 2>&1 | _strip)
    _chk "show_config lists the custom mappings"           grep -q '//cdn.a.com → //cdn.b.test' <<< "$out"

    local t="$_M_WORK/new.conf"
    create_config_file "$t" >/dev/null 2>&1
    _chk "the new-config template has both sections"       bash -c 'grep -q "^\[domain_mappings\]" "$0" && grep -q "^\[site_domain_mappings\]" "$0"' "$t"
    _chk "the template examples are comments only"         bash -c '[[ -z "$(awk "/^\[domain_mappings\]/{s=1;next} /^\[/{s=0} s && !/^#/ && NF" "$0")" ]]' "$t"
    _chk "a fresh template passes validation (with sql/domains set)" bash -c 'sed -i.bak "s/^sql_file=.*/sql_file=a.sql/; s/^old_domain=.*/old_domain=a.com/; s/^new_domain=.*/new_domain=b.test/" "$1"; validate_config_file "$1"' _ "$t"

    # regression guard: a [site_domain_mappings] line "2: ..." must not hide a missing site mapping
    c=$(_m_conf "[general]\nold_domain=a.com\n\n[site_mappings]\n1:a.com:b.test\n\n[site_domain_mappings]\n2: //cdn.a.com => //cdn.b.test\n")
    update_site_mapping "$c" 2 "shop.a.com" "shop.b.test" >/dev/null 2>&1
    _chk "update_site_mapping adds blog 2 although [site_domain_mappings] has '2:'" bash -c 'get_site_mappings "$0" | grep -q "^2:shop.a.com:shop.b.test"' "$c"
    _chk "the [site_domain_mappings] line is untouched"    grep -q '^2: //cdn.a.com => //cdn.b.test' "$c"
    _chk "blog 1 mapping is untouched"                     bash -c 'get_site_mappings "$0" | grep -q "^1:a.com:b.test"' "$c"
    update_site_mapping "$c" 2 "shop.a.com" "shop2.b.test" >/dev/null 2>&1
    _chk "a second update replaces blog 2 (no duplicate)"  bash -c '[[ $(get_site_mappings "$0" | grep -c "^2:") -eq 1 ]] && get_site_mappings "$0" | grep -q "shop2.b.test"' "$c"
    _chk "get_site_mappings does not read [domain_mappings]" bash -c '! get_site_mappings "$0" | grep -q "cdn.a.com"' "$c"
    _finish "config integration holds"
}

# ----------------------------------------------------------------
test_config_migration() {
    start_test "Config migration" "an existing config gets the new keys and sections at import time, nothing else changes"
    _m_load
    local errors=0 old="$_M_WORK/old.conf" run="$_M_WORK/old.run.conf" a b
    # a config written by an older version: no backup keys, no mapping sections, custom values and comments
    printf '%s\n' '# my notes' '[general]' 'sql_file=dump.sql' 'old_domain=prod.com' 'new_domain=local.test' 'all_tables=true' 'dry_run=false' 'auto_proceed=true' 'use_socket=false' 'mysql_socket=' 'import_optimizations=auto' 'parallel_import=false' '' '[site_mappings]' '# comment' '1:prod.com:local.test' > "$old"
    cp "$old" "$run"; chmod 640 "$run"
    ensure_socket_config_settings "$run" >/dev/null 2>&1; local rc=$?
    _chk "migration succeeds and reports it"               test "$rc" -eq 0 -a "$CONFIG_SOCKET_SETTINGS_MIGRATED" = true
    _chk "the item list names only what was added"         test "$CONFIG_SETTINGS_MIGRATED_ITEMS" = "backup_before_import, backup_dir, backup_keep, backup_keep_days, backup_encrypt, backup_gpg_recipient, [domain_mappings], [site_domain_mappings]"
    _chk "no line of the old file was removed or changed"  bash -c '! diff "$0" "$1" | grep -q "^<"' "$old" "$run"
    _chk "every old value reads the same"                  bash -c 'source "'"$_M_ROOT"'/lib/core/utils.sh" >/dev/null 2>&1; source "'"$_M_ROOT"'/lib/config/config_manager.sh" >/dev/null 2>&1; for k in sql_file old_domain new_domain all_tables dry_run auto_proceed use_socket mysql_socket import_optimizations parallel_import; do [[ "$(parse_config_section "$0" general $k)" == "$(parse_config_section "$1" general $k)" ]] || exit 1; done' "$old" "$run"
    _chk "new keys get the defaults (ask, blank, 5)"       bash -c 'source "'"$_M_ROOT"'/lib/core/utils.sh" >/dev/null 2>&1; source "'"$_M_ROOT"'/lib/config/config_manager.sh" >/dev/null 2>&1; [[ "$(parse_config_section "$0" general backup_before_import)" == ask && -z "$(parse_config_section "$0" general backup_dir)" && "$(parse_config_section "$0" general backup_keep)" == 5 ]]' "$run"
    _chk "both sections were added, after [site_mappings]" bash -c 'l=$(grep -n "^\[" "$0" | cut -d: -f2 | tr "\n" " "); [[ "$l" == "[general] [site_mappings] [domain_mappings] [site_domain_mappings] " ]]' "$run"
    _chk "the sections hold comments only (no active entry)" bash -c '[[ -z "$(awk "/^\[(domain_mappings|site_domain_mappings)\]/{s=1;next} /^\[/{s=0} s && !/^#/ && NF" "$0")" ]]' "$run"
    _chk "the site mapping is untouched"                   bash -c 'source "'"$_M_ROOT"'/lib/core/utils.sh" >/dev/null 2>&1; source "'"$_M_ROOT"'/lib/config/config_manager.sh" >/dev/null 2>&1; [[ "$(get_site_mappings "$0")" == "1:prod.com:local.test" ]]' "$run"
    _chk "the file mode is kept"                           bash -c '[[ "$(stat -c %a "$0" 2>/dev/null || stat -f %Lp "$0")" == 640 ]]' "$run"
    _chk "the migrated config validates and has no entries" bash -c 'source "'"$_M_ROOT"'/lib/core/utils.sh" >/dev/null 2>&1; source "'"$_M_ROOT"'/lib/config/config_manager.sh" >/dev/null 2>&1; source "'"$_M_ROOT"'/lib/database/sql_source.sh" >/dev/null 2>&1; source "'"$_M_ROOT"'/lib/database/domain_mappings.sh" >/dev/null 2>&1; validate_config_file "$0" >/dev/null && dm_load "$0" domain_mappings && test -z "$DM_ENTRIES"' "$run"

    a=$(cksum < "$run")
    ensure_socket_config_settings "$run" >/dev/null 2>&1
    _chk "a second run changes nothing and reports nothing" test "$CONFIG_SOCKET_SETTINGS_MIGRATED" = false -a -z "$CONFIG_SETTINGS_MIGRATED_ITEMS" -a "$a" = "$(cksum < "$run")"

    # regression: a comment such as "# Example: mysql_socket=/path" is not a setting
    printf '[general]\n# Example: mysql_socket=/from/a/comment\n# backup_keep=99\nmysql_socket=\n; old_domain=commented.com\nold_domain=real.com\n' > "$_M_WORK/cm.conf"
    _chk "parse_config_section ignores commented lines"    bash -c 'source "'"$_M_ROOT"'/lib/core/utils.sh" >/dev/null 2>&1; source "'"$_M_ROOT"'/lib/config/config_manager.sh" >/dev/null 2>&1; [[ -z "$(parse_config_section "$0" general mysql_socket)" && -z "$(parse_config_section "$0" general backup_keep)" && "$(parse_config_section "$0" general old_domain)" == real.com ]]' "$_M_WORK/cm.conf"
    create_config_file "$_M_WORK/fresh.conf" a.sql a.com b.test >/dev/null 2>&1
    _chk "a fresh config reads mysql_socket as empty (not the comment's example path)" bash -c 'source "'"$_M_ROOT"'/lib/core/utils.sh" >/dev/null 2>&1; source "'"$_M_ROOT"'/lib/config/config_manager.sh" >/dev/null 2>&1; [[ -z "$(parse_config_section "$0" general mysql_socket)" ]]' "$_M_WORK/fresh.conf"
    # the comment of each added key comes with it (same text as the new-config template)
    _chk "every migrated key has its template comment"     bash -c 'source "'"$_M_ROOT"'/lib/core/utils.sh" >/dev/null 2>&1; source "'"$_M_ROOT"'/lib/config/config_manager.sh" >/dev/null 2>&1; for k in use_socket mysql_socket import_optimizations parallel_import backup_before_import backup_dir backup_keep; do c=$(config_key_comment $k); [[ -n "$c" ]] || exit 1; done; t=$(cat "$0"); [[ "$t" == *"$(config_key_comment backup_keep)"*"backup_keep=5"* && "$t" == *"$(config_key_comment backup_before_import)"*"backup_before_import=ask"* ]]' "$run"
    local min="$_M_WORK/min.conf"
    printf '[general]\nsql_file=a.sql\nold_domain=a.com\nnew_domain=b.test\n\n[site_mappings]\n1:a.com:b.test\n' > "$min"
    ensure_socket_config_settings "$min" >/dev/null 2>&1
    _chk "a minimal config: all 10 keys + comments + both sections" bash -c 'source "'"$_M_ROOT"'/lib/core/utils.sh" >/dev/null 2>&1; source "'"$_M_ROOT"'/lib/config/config_manager.sh" >/dev/null 2>&1; t=$(cat "$0"); for k in use_socket mysql_socket import_optimizations parallel_import backup_before_import backup_dir backup_keep backup_keep_days backup_encrypt backup_gpg_recipient; do [[ "$t" == *"$(config_key_comment $k)"*"${k}="* ]] || exit 1; done; grep -q "^\[domain_mappings\]" "$0" && grep -q "^\[site_domain_mappings\]" "$0"' "$min"
    _chk "the added keys are inside [general], before [site_mappings]" bash -c 'g=$(grep -n "^\[general\]" "$0" | cut -d: -f1); m=$(grep -n "^\[site_mappings\]" "$0" | cut -d: -f1); k=$(grep -n "^backup_keep=" "$0" | cut -d: -f1); [[ "$g" -lt "$k" && "$k" -lt "$m" ]]' "$min"
    _chk "a blank line still separates [general] from [site_mappings]" bash -c 'm=$(grep -n "^\[site_mappings\]" "$0" | cut -d: -f1); [[ -z "$(sed -n "$((m - 1))p" "$0")" ]]' "$min"
    _chk "no double blank lines and no trailing blank line"  bash -c '! awk "/^$/{b++; if (b>1) bad=1; next} {b=0} END{exit bad?0:1}" "$0" && [[ -n "$(tail -n1 "$0")" ]]' "$min"
    _chk "the minimal config still validates"              bash -c 'source "'"$_M_ROOT"'/lib/core/utils.sh" >/dev/null 2>&1; source "'"$_M_ROOT"'/lib/config/config_manager.sh" >/dev/null 2>&1; source "'"$_M_ROOT"'/lib/database/sql_source.sh" >/dev/null 2>&1; source "'"$_M_ROOT"'/lib/database/domain_mappings.sh" >/dev/null 2>&1; validate_config_file "$0" >/dev/null' "$min"

    # a later site-mapping update still lands inside [site_mappings]
    update_site_mapping "$run" 2 "shop.prod.com" "shop.local.test" >/dev/null 2>&1
    _chk "update_site_mapping adds blog 2 to [site_mappings]" bash -c 'source "'"$_M_ROOT"'/lib/core/utils.sh" >/dev/null 2>&1; source "'"$_M_ROOT"'/lib/config/config_manager.sh" >/dev/null 2>&1; get_site_mappings "$0" | grep -q "^2:shop.prod.com:shop.local.test"' "$run"

    # a file without a final newline
    printf '[general]\nsql_file=a.sql\n\n[site_mappings]\n1:a.com:b.test' > "$run"
    ensure_socket_config_settings "$run" >/dev/null 2>&1
    _chk "no final newline: the last line is kept intact"  bash -c 'grep -qx "1:a.com:b.test" "$0" && grep -q "^\[domain_mappings\]$" "$0"' "$run"

    # entries the user already wrote are never touched or duplicated
    printf '[general]\nsql_file=a.sql\n\n[site_mappings]\n\n[Domain_Mappings]\n//cdn.a.com => //cdn.b.test\n' > "$run"
    a=$(cksum < "$run")
    ensure_socket_config_settings "$run" >/dev/null 2>&1
    _chk "an existing [domain_mappings] (any case) is not duplicated and keeps its entry" bash -c 'test "$(grep -ci "^\[domain_mappings\]" "$0")" -eq 1 && grep -qx "//cdn.a.com => //cdn.b.test" "$0" && grep -q "^\[site_domain_mappings\]" "$0"' "$run"
    _chk "only the missing section is reported and added"  test "$(printf '%s' "$CONFIG_SETTINGS_MIGRATED_ITEMS" | grep -o '\[site_domain_mappings\]\|\[domain_mappings\]' | tr '\n' ' ')" = "[site_domain_mappings] "

    # the new-config template and the migration use the same text
    create_config_file "$_M_WORK/new.conf" >/dev/null 2>&1
    config_mapping_sections_template > "$_M_WORK/tpl.txt"
    _chk "create_config_file contains the exact template text" bash -c '[[ "$(sed -n "/^\[domain_mappings\]/,\$p" "$0")" == "$(cat "$1")" ]]' "$_M_WORK/new.conf" "$_M_WORK/tpl.txt"
    ensure_socket_config_settings "$_M_WORK/new.conf" >/dev/null 2>&1
    _chk "a freshly created config needs no migration"      test "$CONFIG_SOCKET_SETTINGS_MIGRATED" = false

    # the import path prints the real list
    _chk "the import message uses the real item list"      grep -q 'CONFIG_SETTINGS_MIGRATED_ITEMS' "$_M_ROOT/import_wp_db.sh"
    _finish "config migration is safe and idempotent"
}

# ----------------------------------------------------------------
test_wiring() {
    start_test "Wiring" "module loaded, used by import, per-site and dry-run hooks"
    local errors=0
    _chk "module_loader loads domain_mappings.sh"          grep -q 'domain_mappings.sh' "$_M_ROOT/lib/module_loader.sh"
    _chk "single site: custom replacements run before the main replacement" bash -c 'a=$(grep -n "dm_run \"\$WPDB_TMP_DIR/replace_custom.log\" \"\"" "$0" | head -1 | cut -d: -f1); b=$(grep -n "run_search_replace \"\$search_domain\"" "$0" | head -1 | cut -d: -f1); [[ -n "$a" && -n "$b" && "$a" -lt "$b" ]]' "$_M_ROOT/import_wp_db.sh"
    _chk "multisite: network pass runs before process_multisite_mappings" bash -c 'a=$(grep -n "dm_run .*--network" "$0" | head -1 | cut -d: -f1); b=$(grep -n "^      process_multisite_mappings" "$0" | head -1 | cut -d: -f1); [[ -n "$a" && -n "$b" && "$a" -lt "$b" ]]' "$_M_ROOT/import_wp_db.sh"
    _chk "invalid entries stop the run before the dry-run decision" bash -c 'a=$(grep -n "dm_print_problems \"\[domain_mappings\]\"" "$0" | head -1 | cut -d: -f1); b=$(grep -n "decide_dry_run_mode \"\$config_path\"" "$0" | head -1 | cut -d: -f1); [[ -n "$a" && -n "$b" && "$a" -lt "$b" ]]' "$_M_ROOT/import_wp_db.sh"
    _chk "per-site hook in process_multisite_mappings"     grep -q 'dm_run_site_scope' "$_M_ROOT/lib/database/search_replace.sh"
    _chk "dry run prints the URL findings"                 grep -q 'dm_dry_run_report' "$_M_ROOT/lib/database/db_dry_run.sh"
    _finish "wiring is complete"
}

run_domain_mappings_tests() {
    printf "\n${CYAN}${BOLD}🧪 Domain Mappings Tests${RESET}\n"
    printf "%s\n\n" "$(printf '=%.0s' {1..50})"
    init_test_session "domain_mappings"
    _M_WORK=$(mktemp -d "${TMPDIR:-/tmp}/wpdb-dm-test.XXXXXX")
    trap 'rm -rf "$_M_WORK"' EXIT

    test_validation
    test_loading
    test_commands
    test_report
    test_config_integration
    test_config_migration
    test_wiring

    finalize_test_session
    return $?
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    run_domain_mappings_tests
fi
