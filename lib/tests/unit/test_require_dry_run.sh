#!/usr/bin/env bash

# ================================================================
# require_dry_run (dry-run guard) - Tests
# ================================================================
#
# Description:
#   Tests for issue #47. With require_dry_run=true a live import is refused unless a dry run of
#   the same dump (path, size, modification time), domains and mappings finished in the last
#   require_dry_run_hours hours. Checked here: no stamp, stale stamp, changed dump / domain /
#   mapping, fresh stamp, key off (no check and no stamp written), bad values (never switch the
#   guard off by accident), the private stamp folder, the config keys (upgrade, load, validate,
#   show, examples, doctor) and the wiring in the import script (--dry-run is never blocked).
#   (lib/tests/integration/test_real_import.sh runs the whole flow on a real server.)
#
# Usage:
#   ./lib/tests/unit/test_require_dry_run.sh
#
# ================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../test_framework.sh"

_R_ROOT="$PROJECT_ROOT_DIR"
_R_WORK=""

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

_r_load() {
    source "$_R_ROOT/lib/core/utils.sh" >/dev/null 2>&1
    source "$_R_ROOT/lib/config/config_manager.sh" >/dev/null 2>&1
    source "$_R_ROOT/lib/config/integration.sh" >/dev/null 2>&1
    source "$_R_ROOT/lib/database/sql_source.sh" >/dev/null 2>&1
    source "$_R_ROOT/lib/database/domain_mappings.sh" >/dev/null 2>&1
    source "$_R_ROOT/lib/database/db_dry_run.sh" >/dev/null 2>&1
    export WPDB_STAMP_DIR="$_R_WORK/stamps"
}

# A fresh dump, config and stamp folder. Sets: _R_SQL _R_CONF
_r_fixture() {
    rm -rf "$_R_WORK/stamps" "$_R_WORK/dump.sql" "$_R_WORK/c.conf"
    printf 'CREATE TABLE t (i int);\nINSERT INTO t VALUES (1);\n' > "$_R_WORK/dump.sql"
    touch -t 202601010000 "$_R_WORK/dump.sql"
    printf '[general]\nold_domain=prod.com\nnew_domain=local.test\n\n[site_mappings]\n1:prod.com:local.test\n\n[domain_mappings]\n# a comment\n//cdn.prod.com => //cdn.local.test\n' > "$_R_WORK/c.conf"
    _R_SQL="$_R_WORK/dump.sql"; _R_CONF="$_R_WORK/c.conf"
    CONFIG_REQUIRE_DRY_RUN="true"; CONFIG_REQUIRE_DRY_RUN_HOURS="24"
}
_r_refused() { ! dry_run_guard_check "$@" >/dev/null 2>&1; }
_r_relative() { ( cd "$_R_WORK" && dry_run_guard_check dump.sql prod.com local.test "$_R_CONF" "$_R_WORK/site" ) >/dev/null 2>&1; }
# Rewrites the time inside the (only) stamp: $1 = seconds ago
_r_age_stamp() {
    local f; f=$(ls "$_R_WORK"/stamps/* | head -1)
    { sed -n 1p "$f"; echo $(( $(date +%s) - $1 )); } > "$f.new" && mv "$f.new" "$f"
}

# ----------------------------------------------------------------
test_guard() {
    start_test "Guard" "refused without a fresh dry run of the same dump; allowed with one"
    _r_load; _r_fixture
    local errors=0 out rc

    out=$(dry_run_guard_check "$_R_SQL" prod.com local.test "$_R_CONF" "$_R_WORK/site" 2>&1); rc=$?; out=$(printf '%s' "$out" | _strip)
    _chk "no stamp: refused"                               test "$rc" -eq 1
    _chk "no stamp: the message names the command to run"  grep -q 'wp-db-import --dry-run' <<< "$out"
    _chk "no stamp: the message says nothing was changed"  grep -q 'Nothing was changed' <<< "$out"
    _chk "no stamp: nothing is written by the check"       bash -c '! test -e "$0"' "$_R_WORK/stamps"

    dry_run_stamp_write "$_R_SQL" prod.com local.test "$_R_CONF" "$_R_WORK/site" >/dev/null 2>&1
    _chk "a finished dry run writes one stamp"             bash -c 'test "$(ls "$0" | wc -l | tr -d " ")" = 1' "$_R_WORK/stamps"
    _chk "fresh stamp: allowed"                            dry_run_guard_check "$_R_SQL" prod.com local.test "$_R_CONF" "$_R_WORK/site"
    _chk "the stamp folder is private (700) and the file 600" bash -c 'm() { stat -c %a "$1" 2>/dev/null || stat -f %Lp "$1"; }; test "$(m "$0")" = 700 && test "$(m "$(ls -d "$0"/* | head -1)")" = 600' "$_R_WORK/stamps"
    _chk "the stamp is outside the project folder and the WordPress folder" bash -c '[[ "$0" != "$1"* ]]' "$_R_WORK/stamps" "$_R_ROOT"

    # age: inside and outside the 24 hours
    _r_age_stamp $((23 * 3600 + 3000))
    _chk "23 h 50 min old: still allowed"                  dry_run_guard_check "$_R_SQL" prod.com local.test "$_R_CONF" "$_R_WORK/site"
    _r_age_stamp $((24 * 3600 + 120))
    out=$(dry_run_guard_check "$_R_SQL" prod.com local.test "$_R_CONF" "$_R_WORK/site" 2>&1); rc=$?; out=$(printf '%s' "$out" | _strip)
    _chk "24 h 2 min old: refused, says how old"           bash -c 'test "$1" -eq 1 && grep -q "finished 24 hours ago (the limit is 24)" <<< "$0"' "$out" "$rc"
    _chk "a stale stamp also names the command to run"     grep -q 'wp-db-import --dry-run' <<< "$out"

    # a custom limit
    dry_run_stamp_write "$_R_SQL" prod.com local.test "$_R_CONF" "$_R_WORK/site" >/dev/null 2>&1
    CONFIG_REQUIRE_DRY_RUN_HOURS=2
    _r_age_stamp $((2 * 3600 - 60))
    _chk "limit 2 h, 1 h 59 min old: allowed"              dry_run_guard_check "$_R_SQL" prod.com local.test "$_R_CONF" "$_R_WORK/site"
    _r_age_stamp $((2 * 3600 + 60))
    _chk "limit 2 h, 2 h 1 min old: refused"               _r_refused "$_R_SQL" prod.com local.test "$_R_CONF" "$_R_WORK/site"
    CONFIG_REQUIRE_DRY_RUN_HOURS=24

    # a stamp from the future (clock moved back) is not trusted
    _r_age_stamp -600
    _chk "a stamp from the future: refused"                _r_refused "$_R_SQL" prod.com local.test "$_R_CONF" "$_R_WORK/site"
    _finish "the guard decides correctly"
}

# ----------------------------------------------------------------
test_changes() {
    start_test "Changes" "a changed dump, domain, mapping or site needs a new dry run"
    _r_load; _r_fixture
    local errors=0 g
    dry_run_stamp_write "$_R_SQL" prod.com local.test "$_R_CONF" "$_R_WORK/site" >/dev/null 2>&1
    g() { dry_run_guard_check "$@" >/dev/null 2>&1; }
    _chk "baseline: allowed"                               g "$_R_SQL" prod.com local.test "$_R_CONF" "$_R_WORK/site"
    _chk "another old domain: refused"                     _r_refused "$_R_SQL" other.com local.test "$_R_CONF" "$_R_WORK/site"
    _chk "another new domain: refused"                     _r_refused "$_R_SQL" prod.com other.test "$_R_CONF" "$_R_WORK/site"
    _chk "another WordPress folder: refused"               _r_refused "$_R_SQL" prod.com local.test "$_R_CONF" "$_R_WORK/site/other"

    # same name and size, new modification time
    touch -t 202602020000 "$_R_SQL"
    _chk "the dump was touched (same size): refused"       _r_refused "$_R_SQL" prod.com local.test "$_R_CONF" "$_R_WORK/site"
    touch -t 202601010000 "$_R_SQL"
    _chk "the old time back: allowed again"                g "$_R_SQL" prod.com local.test "$_R_CONF" "$_R_WORK/site"

    # another size
    printf 'more\n' >> "$_R_SQL"; touch -t 202601010000 "$_R_SQL"
    _chk "the dump grew (same time): refused"              _r_refused "$_R_SQL" prod.com local.test "$_R_CONF" "$_R_WORK/site"
    _r_fixture
    dry_run_stamp_write "$_R_SQL" prod.com local.test "$_R_CONF" "$_R_WORK/site" >/dev/null 2>&1

    # a copy of the dump under another path
    cp -p "$_R_SQL" "$_R_WORK/copy.sql"
    _chk "the same bytes under another path: refused"      _r_refused "$_R_WORK/copy.sql" prod.com local.test "$_R_CONF" "$_R_WORK/site"
    _chk "a relative path to the same file: allowed"       _r_relative

    # mappings
    printf '\n1:blog.prod.com:blog.local.test\n' >> "$_R_CONF"
    _chk "a new site mapping: refused"                     _r_refused "$_R_SQL" prod.com local.test "$_R_CONF" "$_R_WORK/site"
    _r_fixture; dry_run_stamp_write "$_R_SQL" prod.com local.test "$_R_CONF" "$_R_WORK/site" >/dev/null 2>&1
    printf '//api.prod.com => //api.local.test\n' >> "$_R_CONF"
    _chk "a new [domain_mappings] entry: refused"          _r_refused "$_R_SQL" prod.com local.test "$_R_CONF" "$_R_WORK/site"
    _r_fixture; dry_run_stamp_write "$_R_SQL" prod.com local.test "$_R_CONF" "$_R_WORK/site" >/dev/null 2>&1
    printf '# only a new comment\n\n' >> "$_R_CONF"
    _chk "a comment or blank line in the config: still allowed" g "$_R_SQL" prod.com local.test "$_R_CONF" "$_R_WORK/site"
    sed -i.bak 's/^old_domain=.*/old_domain=changed.com/' "$_R_CONF"; rm -f "$_R_CONF.bak"
    _chk "other [general] keys do not matter (domains come from the arguments)" g "$_R_SQL" prod.com local.test "$_R_CONF" "$_R_WORK/site"

    # a corrupt or forged stamp
    local f; f=$(ls "$_R_WORK"/stamps/* | head -1)
    printf 'some other key\n%s\n' "$(date +%s)" > "$f"
    _chk "a stamp whose key does not match: refused"       _r_refused "$_R_SQL" prod.com local.test "$_R_CONF" "$_R_WORK/site"
    : > "$f"
    _chk "an empty stamp: refused"                         _r_refused "$_R_SQL" prod.com local.test "$_R_CONF" "$_R_WORK/site"
    printf '%s\nnot-a-number\n' "$(dry_run_stamp_key "$_R_SQL" prod.com local.test "$_R_CONF" "$_R_WORK/site")" > "$f"
    _chk "a stamp with a bad time: refused"                _r_refused "$_R_SQL" prod.com local.test "$_R_CONF" "$_R_WORK/site"
    _finish "every change needs a new dry run"
}

# ----------------------------------------------------------------
test_off_and_values() {
    start_test "Off and values" "default off: no check and no stamp; a bad value never switches the guard off by accident"
    _r_load; _r_fixture
    local errors=0 v out rc
    for v in "" false FALSE no 0 off; do
        CONFIG_REQUIRE_DRY_RUN="$v"
        _chk "require_dry_run='$v': a live run is allowed with no stamp" dry_run_guard_check "$_R_SQL" prod.com local.test "$_R_CONF" "$_R_WORK/site"
    done
    CONFIG_REQUIRE_DRY_RUN=false
    dry_run_stamp_write "$_R_SQL" prod.com local.test "$_R_CONF" "$_R_WORK/site" >/dev/null 2>&1
    _chk "off: a dry run writes no stamp and creates no folder" bash -c '! test -e "$0"' "$_R_WORK/stamps"
    out=$(dry_run_stamp_write "$_R_SQL" prod.com local.test "$_R_CONF" "$_R_WORK/site" 2>&1)
    _chk "off: a dry run prints nothing about stamps"      test -z "$out"
    unset CONFIG_REQUIRE_DRY_RUN
    _chk "the variable not set at all: allowed"            dry_run_guard_check "$_R_SQL" prod.com local.test "$_R_CONF" "$_R_WORK/site"

    for v in true TRUE yes 1 on; do
        CONFIG_REQUIRE_DRY_RUN="$v"
        _chk "require_dry_run='$v' turns the guard on"     _r_refused "$_R_SQL" prod.com local.test "$_R_CONF" "$_R_WORK/site"
    done

    for v in maybe tru enabled 2; do
        CONFIG_REQUIRE_DRY_RUN="$v"
        out=$(dry_run_guard_check "$_R_SQL" prod.com local.test "$_R_CONF" "$_R_WORK/site" 2>&1); rc=$?
        _chk "require_dry_run='$v': refused and explained, not ignored" bash -c 'test "$1" -eq 1 && grep -q "is not true or false" <<< "$0"' "$out" "$rc"
    done

    CONFIG_REQUIRE_DRY_RUN=true
    for v in abc 0 -1 1.5 "2 h"; do
        CONFIG_REQUIRE_DRY_RUN_HOURS="$v"
        out=$(dry_run_guard_check "$_R_SQL" prod.com local.test "$_R_CONF" "$_R_WORK/site" 2>&1); rc=$?
        _chk "require_dry_run_hours='$v': refused and explained" bash -c 'test "$1" -eq 1 && grep -q "not a whole number of hours" <<< "$0"' "$out" "$rc"
    done
    CONFIG_REQUIRE_DRY_RUN_HOURS=""
    dry_run_stamp_write "$_R_SQL" prod.com local.test "$_R_CONF" "$_R_WORK/site" >/dev/null 2>&1
    _chk "empty hours: the default 24 applies"             dry_run_guard_check "$_R_SQL" prod.com local.test "$_R_CONF" "$_R_WORK/site"

    # a stamp folder that cannot be written
    CONFIG_REQUIRE_DRY_RUN_HOURS=24
    printf 'x' > "$_R_WORK/afile"
    out=$(WPDB_STAMP_DIR="$_R_WORK/afile/sub" dry_run_stamp_write "$_R_SQL" prod.com local.test "$_R_CONF" "$_R_WORK/site" 2>&1); rc=$?
    _chk "unwritable stamp folder: the dry run says so (and a live run will be refused)" bash -c 'test "$1" -eq 1 && grep -q "Could not write the dry-run stamp" <<< "$0"' "$out" "$rc"
    _finish "the default is off and bad values are refused"
}

# ----------------------------------------------------------------
test_config() {
    start_test "Config" "upgrade, load, validate, show, new config, examples, doctor"
    _r_load
    local errors=0 old="$_R_WORK/old.conf" run="$_R_WORK/run.conf" a out
    printf '%s\n' '[general]' 'sql_file=dump.sql' 'old_domain=prod.com' 'new_domain=local.test' 'all_tables=true' 'dry_run=false' 'auto_proceed=true' 'use_socket=false' 'mysql_socket=' 'import_optimizations=auto' 'parallel_import=false' 'backup_before_import=ask' 'backup_dir=' 'backup_keep=5' 'backup_keep_days=0' 'backup_encrypt=false' 'backup_gpg_recipient=' '' '[site_mappings]' '1:prod.com:local.test' > "$old"
    cp "$old" "$run"
    ensure_socket_config_settings "$run" >/dev/null 2>&1
    _chk "the upgrade names the two keys"                  bash -c '[[ "$0" == *"require_dry_run, require_dry_run_hours"* ]]' "$CONFIG_SETTINGS_MIGRATED_ITEMS"
    _chk "defaults: false and 24"                          bash -c 'grep -qx "require_dry_run=false" "$0" && grep -qx "require_dry_run_hours=24" "$0"' "$run"
    _chk "each key comes with its comment"                 bash -c 'source "'"$_R_ROOT"'/lib/core/utils.sh" >/dev/null 2>&1; source "'"$_R_ROOT"'/lib/config/config_manager.sh" >/dev/null 2>&1; t=$(cat "$0"); for k in require_dry_run require_dry_run_hours; do [[ -n "$(config_key_comment $k)" && "$t" == *"$(config_key_comment $k)"*"${k}="* ]] || exit 1; done' "$run"
    _chk "no line of the old file changed or was removed"  bash -c '! diff "$0" "$1" | grep -q "^<"' "$old" "$run"
    a=$(cksum < "$run"); ensure_socket_config_settings "$run" >/dev/null 2>&1
    _chk "a second run changes nothing"                    test "$a" = "$(cksum < "$run")"
    printf '%s\n' '[general]' 'sql_file=a.sql' 'require_dry_run=true' 'require_dry_run_hours=6' '' '[site_mappings]' > "$run"
    ensure_socket_config_settings "$run" >/dev/null 2>&1
    _chk "values already set are kept"                     bash -c 'grep -qx "require_dry_run=true" "$0" && grep -qx "require_dry_run_hours=6" "$0" && test "$(grep -c "^require_dry_run" "$0")" = 2' "$run"

    # regression: "require_dry_run=true" must not be read as "dry_run" when it comes first in [general]
    printf '%s\n' '[general]' 'require_dry_run=true' 'dry_run=false' 'old_domain=a.com' '  new_domain = b.test' '[site_mappings]' > "$_R_WORK/order.conf"
    _chk "a key must start the line: dry_run is not read from require_dry_run" bash -c 'source "'"$_R_ROOT"'/lib/core/utils.sh" >/dev/null 2>&1; source "'"$_R_ROOT"'/lib/config/config_manager.sh" >/dev/null 2>&1; test "$(parse_config_section "$0" general dry_run)" = false -a "$(parse_config_section "$0" general require_dry_run)" = true' "$_R_WORK/order.conf"
    _chk "an indented key and spaces around = still work"  bash -c 'source "'"$_R_ROOT"'/lib/core/utils.sh" >/dev/null 2>&1; source "'"$_R_ROOT"'/lib/config/config_manager.sh" >/dev/null 2>&1; test "$(parse_config_section "$0" general new_domain)" = b.test' "$_R_WORK/order.conf"
    load_import_config "$run" >/dev/null 2>&1
    _chk "load_import_config reads true and 6"             test "$CONFIG_REQUIRE_DRY_RUN" = true -a "$CONFIG_REQUIRE_DRY_RUN_HOURS" = 6
    cp "$old" "$_R_WORK/nokeys.conf"; load_import_config "$_R_WORK/nokeys.conf" >/dev/null 2>&1
    _chk "a config without the keys loads false and 24"    test "$CONFIG_REQUIRE_DRY_RUN" = false -a "$CONFIG_REQUIRE_DRY_RUN_HOURS" = 24
    printf '%s\n' '[general]' 'sql_file=a.sql' 'require_dry_run=' 'require_dry_run_hours=' '[site_mappings]' > "$_R_WORK/empty.conf"
    load_import_config "$_R_WORK/empty.conf" >/dev/null 2>&1
    _chk "empty values load the defaults"                  test "$CONFIG_REQUIRE_DRY_RUN" = false -a "$CONFIG_REQUIRE_DRY_RUN_HOURS" = 24

    create_config_file "$_R_WORK/fresh.conf" a.sql a.com b.test >/dev/null 2>&1
    _chk "a new config contains both keys and validates"   bash -c 'source "'"$_R_ROOT"'/lib/core/utils.sh" >/dev/null 2>&1; source "'"$_R_ROOT"'/lib/config/config_manager.sh" >/dev/null 2>&1; grep -qx "require_dry_run=false" "$0" && grep -qx "require_dry_run_hours=24" "$0" && validate_config_file "$0"' "$_R_WORK/fresh.conf"

    printf '%s\n' '[general]' 'sql_file=a.sql' 'old_domain=a.com' 'new_domain=b.test' 'require_dry_run=maybe' 'require_dry_run_hours=0' '[site_mappings]' > "$run"
    out=$(validate_config_file "$run" 2>&1); a=$?
    _chk "validate: bad values fail with a message each"   bash -c 'test "$1" -ne 0 && grep -q "require_dry_run: .maybe." <<< "$0" && grep -q "require_dry_run_hours: .0." <<< "$0"' "$out" "$a"
    printf '%s\n' '[general]' 'sql_file=a.sql' 'old_domain=a.com' 'new_domain=b.test' 'require_dry_run=true' 'require_dry_run_hours=48' '[site_mappings]' > "$run"
    _chk "validate: true and 48 pass"                      validate_config_file "$run"

    out=$(show_config "$run" 2>&1 | _strip)
    _chk "config-show prints the guard and the hours"      grep -q 'Require Dry Run: *true (48 h)' <<< "$out"
    printf '%s\n' '[general]' 'sql_file=a.sql' '[site_mappings]' > "$run"
    out=$(show_config "$run" 2>&1 | _strip)
    _chk "config-show defaults: false (24 h)"              grep -q 'Require Dry Run: *false (24 h)' <<< "$out"

    local f
    for f in single multisite; do
        _chk "example $f config has both keys"             bash -c 'grep -qx "require_dry_run=false" "$0" && grep -qx "require_dry_run_hours=24" "$0"' "$_R_ROOT/wpdb-import-example-$f.conf"
    done
    _chk "doctor checks the stamp folder when the guard is on" grep -q 'Dry-run guard' "$_R_ROOT/lib/utilities/doctor.sh"
    _finish "config handling is complete"
}

# ----------------------------------------------------------------
test_wiring() {
    start_test "Wiring" "the stamp is written after a finished dry run; the guard runs before any change; --dry-run is never blocked"
    local errors=0 f="$_R_ROOT/import_wp_db.sh" a b c d
    a=$(grep -n 'decide_dry_run_mode "\$config_path"' "$f" | head -1 | cut -d: -f1)
    b=$(grep -n 'dry_run_stamp_write "\$sql_file"' "$f" | head -1 | cut -d: -f1)
    c=$(grep -n 'dry_run_guard_check "\$sql_file"' "$f" | head -1 | cut -d: -f1)
    d=$(grep -n 'backup_database_before_import "\$wp_root"' "$f" | head -1 | cut -d: -f1)
    _chk "order: dry-run decision, stamp, guard, backup"   test -n "$a" -a -n "$b" -a -n "$c" -a -n "$d" -a "$a" -lt "$b" -a "$b" -lt "$c" -a "$c" -lt "$d"
    _chk "the guard is after the dry-run return (a dry run is never blocked)" bash -c 'r=$(grep -n "return \$dry_run_rc" "$0" | head -1 | cut -d: -f1); g=$(grep -n "dry_run_guard_check" "$0" | head -1 | cut -d: -f1); test "$r" -lt "$g"' "$f"
    _chk "the stamp is written only when the preview succeeded" grep -q '\[\[ "\$dry_run_rc" -eq 0 \]\] && dry_run_stamp_write' "$f"
    _chk "the guard runs before the remote-database warning and the confirmation" bash -c 'g=$(grep -n "dry_run_guard_check" "$0" | head -1 | cut -d: -f1); w=$(grep -n "warn_if_remote_database \"\$wp_root\"" "$0" | head -1 | cut -d: -f1); c=$(grep -n "Proceed with database import" "$0" | head -1 | cut -d: -f1); test "$g" -lt "$w" -a "$g" -lt "$c"' "$f"
    _chk "the functions are exported for the other modules" grep -q 'dry_run_stamp_write dry_run_guard_check' "$_R_ROOT/lib/database/db_dry_run.sh"
    _finish "wiring is complete"
}

run_require_dry_run_tests() {
    printf "\n${CYAN}${BOLD}🧪 Require Dry Run Tests${RESET}\n"
    printf "%s\n\n" "$(printf '=%.0s' {1..50})"
    init_test_session "require_dry_run"
    _R_WORK=$(mktemp -d "${TMPDIR:-/tmp}/wpdb-rdr-test.XXXXXX")
    trap 'rm -rf "$_R_WORK"' EXIT

    test_guard
    test_changes
    test_off_and_values
    test_config
    test_wiring

    finalize_test_session
    return $?
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    run_require_dry_run_tests
fi
