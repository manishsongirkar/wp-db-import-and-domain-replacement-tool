#!/usr/bin/env bash

# ================================================================
# Human-error hardening - Tests
# ================================================================
#
# Description:
#   Checks that common mistakes never switch a safety setting off or start a live change:
#   - a bad dry_run value in the config stops the run (it is never read as "live")
#   - restore honors --dry-run (nothing is decrypted, backed up or imported)
#   - the config parser reads [General], Require_Dry_Run = true and "key = value" the same in every
#     awk (macOS awk has no IGNORECASE), and update_config_general writes into such a file
#   - import_sql_mode is checked before the dry-run decision, so a bad value never reaches the SQL stream
#
# Usage:
#   ./lib/tests/unit/test_hardening.sh
#
# ================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../test_framework.sh"

_H_ROOT="$PROJECT_ROOT_DIR"
_H_WORK=""

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

_h_load() {
    source "$_H_ROOT/lib/core/utils.sh" >/dev/null 2>&1
    source "$_H_ROOT/lib/config/config_manager.sh" >/dev/null 2>&1
    source "$_H_ROOT/lib/config/integration.sh" >/dev/null 2>&1
    source "$_H_ROOT/lib/database/sql_source.sh" >/dev/null 2>&1
    source "$_H_ROOT/lib/database/db_dry_run.sh" >/dev/null 2>&1
    source "$_H_ROOT/lib/database/db_restore.sh" >/dev/null 2>&1
}

# ----------------------------------------------------------------
test_dry_run_value() {
    start_test "dry_run value" "a bad value stops the run; it is never read as live mode"
    _h_load
    local errors=0 v out rc
    for v in ture enabled "true # preview" maybe 2; do
        CONFIG_DRY_RUN="$v"; unset WPDB_DRY_RUN
        out=$(decide_dry_run_mode "" </dev/null 2>&1); rc=$?
        _chk "dry_run='$v': refused (exit 1) with a message" bash -c 'test "$1" -eq 1 && grep -q "is not true or false" <<< "$0"' "$out" "$rc"
    done
    for v in false no 0 off FALSE; do
        CONFIG_DRY_RUN="$v"; unset WPDB_DRY_RUN
        decide_dry_run_mode "" </dev/null >/dev/null 2>&1; rc=$?
        _chk "dry_run='$v': live mode, exit 0" test "$rc" -eq 0 -a "$WPDB_DRY_RUN_ACTIVE" = "false"
    done
    for v in true yes 1 on TRUE; do
        CONFIG_DRY_RUN="$v"; unset WPDB_DRY_RUN
        decide_dry_run_mode "" </dev/null >/dev/null 2>&1; rc=$?
        _chk "dry_run='$v': dry-run mode, exit 0" test "$rc" -eq 0 -a "$WPDB_DRY_RUN_ACTIVE" = "true"
    done
    CONFIG_DRY_RUN="ture"; WPDB_DRY_RUN=1
    decide_dry_run_mode "" </dev/null >/dev/null 2>&1; rc=$?
    _chk "--dry-run wins over a bad config value (still a dry run)" test "$rc" -eq 0 -a "$WPDB_DRY_RUN_ACTIVE" = "true"
    unset WPDB_DRY_RUN CONFIG_DRY_RUN

    local cfg="$_H_WORK/bad.conf"
    printf '[general]\nsql_file=a.sql\nold_domain=a.com\nnew_domain=b.test\ndry_run=ture\n' > "$cfg"
    out=$(validate_config_file "$cfg" 2>&1)
    _chk "config-validate reports a bad dry_run" bash -c 'grep -q "dry_run: .ture. is not true or false" <<< "$0"' "$out"
    _finish "dry_run values are handled"
}

# ----------------------------------------------------------------
test_restore_dry_run() {
    start_test "restore --dry-run" "restore only says what it would do"
    _h_load
    local errors=0 out rc f="$_H_WORK/b.sql.gz.gpg"
    : > "$f"
    _RESTORE_CALLS=""
    _restore_database_plain() { _RESTORE_CALLS="${_RESTORE_CALLS}plain "; return 0; }
    restore_decrypt_backup() { _RESTORE_CALLS="${_RESTORE_CALLS}decrypt "; return 1; }

    WPDB_DRY_RUN=1
    out=$(restore_database "$f" "$_H_WORK" 2>&1); rc=$?
    restore_database "$f" "$_H_WORK" >/dev/null 2>&1
    _chk "dry run: exit 0 and the file is named"         bash -c 'test "$1" -eq 0 && grep -q "Dry run: nothing is restored" <<< "$0" && grep -q "b.sql.gz.gpg" <<< "$0"' "$out" "$rc"
    _chk "dry run: nothing decrypted or imported"        test -z "$_RESTORE_CALLS"
    unset WPDB_DRY_RUN
    : > "$_H_WORK/b.sql"
    restore_database "$_H_WORK/b.sql" "$_H_WORK" >/dev/null 2>&1
    _chk "without --dry-run the restore runs as before" test -n "$_RESTORE_CALLS"
    unset -f _restore_database_plain restore_decrypt_backup
    _chk "wp-db-import passes --dry-run to restore (global flag)" grep -q -- '--dry-run) export WPDB_DRY_RUN=1' "$_H_ROOT/wp-db-import"
    _finish "restore honors --dry-run"
}

# ----------------------------------------------------------------
test_config_parser() {
    start_test "Config parser" "[General], Require_Dry_Run = true, spaces: read the same in every awk"
    _h_load
    local errors=0 c="$_H_WORK/p.conf"
    printf '[General]\nRequire_Dry_Run = true\ndry_run=false\nold_domain = a.com  \n[Other]\nold_domain=zzz\n' > "$c"
    _chk "[General] header is found"                       test "$(parse_config_section "$c" general old_domain)" = "a.com"
    _chk "key in another case, spaces around ="            test "$(parse_config_section "$c" general require_dry_run)" = "true"
    _chk "dry_run is not read from require_dry_run"        test "$(parse_config_section "$c" general dry_run)" = "false"
    _chk "another section is not mixed in"                 test "$(parse_config_section "$c" other old_domain)" = "zzz"
    printf '[general] # main\nauto_proceed=true\n  [other]\nauto_proceed=no\n' > "$c"
    _chk "a header with a comment after it"                test "$(parse_config_section "$c" general auto_proceed)" = "true"
    _chk "an indented header"                              test "$(parse_config_section "$c" other auto_proceed)" = "no"
    printf '[general]\nrequire_dry_run=false\nrequire_dry_run=true\n' > "$c"
    _chk "a repeated key: the first one wins (as before)"  test "$(parse_config_section "$c" general require_dry_run)" = "false"
    printf '[general]\n# dry_run=true\n;dry_run=true\n' > "$c"
    _chk "commented lines are not settings"                test -z "$(parse_config_section "$c" general dry_run)"

    printf '[General]\nREQUIRE_DRY_RUN = false\nold_domain=a.com\n\n[site_mappings]\n1:a:b\n' > "$c"
    update_config_general "$c" require_dry_run true
    _chk "update_config_general writes into [General] and replaces the key (no second copy)" bash -c 'test "$(grep -ci "^require_dry_run" "$0")" -eq 1 && grep -q "^require_dry_run=true$" "$0" && test "$(grep -c "^\[" "$0")" -eq 2' "$c"
    update_config_general "$c" brand_new_key 1
    _chk "a new key lands inside [General], before the next section" bash -c 'a=$(grep -n "^brand_new_key=1" "$0" | cut -d: -f1); b=$(grep -n "^\[site_mappings\]" "$0" | cut -d: -f1); test -n "$a" -a "$a" -lt "$b"' "$c"
    _finish "config parsing is portable"
}

# ----------------------------------------------------------------
test_sql_mode_preflight() {
    start_test "import_sql_mode" "a bad value is refused before the dry-run decision and any change"
    local errors=0 f="$_H_ROOT/import_wp_db.sh" a b
    a=$(grep -n 'import_sql_mode_validate "\${CONFIG_IMPORT_SQL_MODE' "$f" | head -1 | cut -d: -f1)
    b=$(grep -n 'decide_dry_run_mode "\$config_path"' "$f" | head -1 | cut -d: -f1)
    _chk "the check is before decide_dry_run_mode"          test -n "$a" -a -n "$b" -a "$a" -lt "$b"
    _chk "a failed dry-run decision stops the import"       grep -q 'decide_dry_run_mode "\$config_path" || return 1' "$f"
    _h_load
    _chk "a value with a quote and ; is refused"            bash -c '! import_sql_mode_validate "x'"'"'; DROP DATABASE prod; -- "'
    _chk "auto, keep and a normal list are accepted"       bash -c 'import_sql_mode_validate auto && import_sql_mode_validate keep && import_sql_mode_validate "STRICT_TRANS_TABLES,NO_ZERO_DATE"'
    _finish "import_sql_mode is checked before use"
}

# ----------------------------------------------------------------
test_small_fixes() {
    start_test "Small fixes" "missing domains stop the run; skip_tables globs are not expanded; hours like 08"
    _h_load
    local errors=0 f="$_H_ROOT/import_wp_db.sh" d="$_H_WORK/globdir" out rc
    _chk "get_domains failure stops the run (--yes, closed stdin)" grep -q 'get_domains "\$config_path" || return 1' "$f"
    mkdir -p "$d"; : > "$d/wp_users"
    _chk "skip_tables=wp_*: matches by pattern, not by the file names in the folder (old code read wp_* as wp_users)" bash -c 'cd "$1" && source "$0/lib/core/utils.sh" >/dev/null 2>&1; sr_table_is_skipped wp_other "wp_*"' "$_H_ROOT" "$d"
    _chk "skip_tables=*: every table is matched"          bash -c 'cd "$1" && source "$0/lib/core/utils.sh" >/dev/null 2>&1; sr_table_is_skipped wp_other "*"' "$_H_ROOT" "$d"
    _chk "a plain list still matches its names"          bash -c 'source "$0/lib/core/utils.sh" >/dev/null 2>&1; sr_table_is_skipped wp_b "wp_a,wp_b" && ! sr_table_is_skipped wp_c "wp_a,wp_b" && sr_table_is_skipped wp_x_1 "wp_?_1"' "$_H_ROOT"
    local cfgdir="$_H_WORK/g"; mkdir -p "$cfgdir"
    CONFIG_REQUIRE_DRY_RUN=true; CONFIG_REQUIRE_DRY_RUN_HOURS=08
    out=$(WPDB_STAMP_DIR="$cfgdir" dry_run_guard_check "$_H_WORK/b.sql" a.com b.test "" "$_H_WORK" 2>&1); rc=$?
    _chk "require_dry_run_hours=08: no shell error (refused only for the missing dry run)" bash -c 'test "$1" -eq 1 && ! grep -q "too great\|value too great" <<< "$0" && grep -q "no dry run of this dump" <<< "$0"' "$out" "$rc"
    CONFIG_REQUIRE_DRY_RUN_HOURS=99999999999999999999
    out=$(WPDB_STAMP_DIR="$cfgdir" dry_run_guard_check "$_H_WORK/b.sql" a.com b.test "" "$_H_WORK" 2>&1); rc=$?
    _chk "a huge hours value is refused with the 'whole number' message" bash -c 'test "$1" -eq 1 && grep -q "not a whole number of hours" <<< "$0"' "$out" "$rc"
    unset CONFIG_REQUIRE_DRY_RUN CONFIG_REQUIRE_DRY_RUN_HOURS
    _finish "the small fixes hold"
}

# ----------------------------------------------------------------
test_db_switch() {
    start_test "Database switch" "a dump that selects another database is refused for a live import"
    _h_load
    local errors=0 w="$_H_WORK/sw" f="$_H_ROOT/import_wp_db.sh" a b c
    mkdir -p "$w"
    printf "CREATE TABLE t (id int);\nINSERT INTO t VALUES (1);\n" > "$w/ok.sql"
    printf "USE \`victim\`;\nCREATE TABLE t (id int);\n" > "$w/use.sql"
    printf "CREATE DATABASE /*!32312 IF NOT EXISTS*/ \`other\` /*!40100 DEFAULT CHARACTER SET utf8mb4 */;\nUSE \`other\`;\n" > "$w/cd.sql"
    printf "/*!40000 DROP DATABASE IF EXISTS \`other\`*/;\nCREATE TABLE t (id int);\n" > "$w/dd.sql"
    printf "USE site_db;\nCREATE TABLE t (id int);\n" > "$w/same.sql"
    printf "INSERT INTO p VALUES ('use victim; and more');\n-- USE x;\n" > "$w/data.sql"
    gzip -c "$w/use.sql" > "$w/use.sql.gz"
    _chk "a normal dump: no switch"                       bash -c '! sql_dump_switches_database "$0" site_db' "$w/ok.sql"
    _chk "USE \`victim\`; is a switch (and is printed)"    bash -c 'sql_dump_switches_database "$0" site_db | grep -q victim' "$w/use.sql"
    _chk "CREATE DATABASE ... IF NOT EXISTS and USE other"  bash -c 'sql_dump_switches_database "$0" site_db >/dev/null' "$w/cd.sql"
    _chk "versioned DROP DATABASE comment line"            bash -c 'sql_dump_switches_database "$0" site_db >/dev/null' "$w/dd.sql"
    _chk "USE of the target database itself is fine"       bash -c '! sql_dump_switches_database "$0" site_db' "$w/same.sql"
    _chk "unknown target: any USE counts"                  bash -c 'sql_dump_switches_database "$0" "" >/dev/null' "$w/same.sql"
    _chk "row data and comments are not statements"        bash -c '! sql_dump_switches_database "$0" site_db' "$w/data.sql"
    _chk "a gzip dump is read too"                         bash -c 'sql_dump_switches_database "$0" site_db >/dev/null' "$w/use.sql.gz"
    a=$(grep -n 'sql_dump_switches_database "\$sql_file"' "$f" | head -1 | cut -d: -f1)
    b=$(grep -n 'dry_run_guard_check "\$sql_file"' "$f" | head -1 | cut -d: -f1)
    c=$(grep -n 'backup_database_before_import "\$wp_root"' "$f" | head -1 | cut -d: -f1)
    _chk "wiring: checked before the guard, the prompt and the backup" test -n "$a" -a -n "$b" -a -n "$c" -a "$a" -lt "$b" -a "$b" -lt "$c"
    _finish "a dump cannot redirect the import to another database"
}

run_hardening_tests() {
    printf "\n${CYAN}${BOLD}🛡️  Hardening Tests${RESET}\n"
    printf "%s\n\n" "$(printf '=%.0s' {1..50})"
    init_test_session "hardening"
    _H_WORK=$(mktemp -d "${TMPDIR:-/tmp}/wpdb-hard-test.XXXXXX")
    trap 'rm -rf "$_H_WORK"' EXIT

    test_dry_run_value
    test_restore_dry_run
    test_config_parser
    test_sql_mode_preflight
    test_small_fixes
    test_db_switch

    finalize_test_session
    return $?
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    run_hardening_tests
fi
