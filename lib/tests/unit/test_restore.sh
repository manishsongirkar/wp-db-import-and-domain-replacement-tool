#!/usr/bin/env bash

# ================================================================
# Restore Command - Tests
# ================================================================
#
# Description:
#   Tests for issue #18: `wp-db-import restore --list | --last | <file>`.
#   WP-CLI and the importer are replaced by stubs that record what happens, so the logic
#   (choice of file, integrity check, confirmation, safety backup, rotation protection,
#   removal of extra tables) is checked without a database.
#
# Usage:
#   ./lib/tests/unit/test_restore.sh
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
    source "$_R_ROOT/lib/database/sql_source.sh" >/dev/null 2>&1
    source "$_R_ROOT/lib/database/db_import.sh" >/dev/null 2>&1
    source "$_R_ROOT/lib/database/db_backup.sh" >/dev/null 2>&1
    source "$_R_ROOT/lib/database/db_restore.sh" >/dev/null 2>&1
}

# A backup file: gzip of a small dump. Parameters: path [table names...]
_r_make_backup() {
    local path="$1"; shift
    local t sql="-- dump\n"
    for t in "$@"; do sql+="DROP TABLE IF EXISTS \`$t\`;\nCREATE TABLE \`$t\` (i int);\nINSERT INTO \`$t\` VALUES (1);\n"; done
    printf -- "$sql" | gzip -c > "$path"
    chmod 600 "$path"
}

# ================================================================
# Listing and choosing
# ================================================================
test_restore_listing() {
    start_test "Restore Listing" "backups are listed newest first; only this database unless --all"
    _r_load
    local errors=0 w="$_R_WORK"
    local d="$w/bk1"; mkdir -p "$d"
    _r_make_backup "$d/wp-20260101-000000.sql.gz" t
    _r_make_backup "$d/wp-20260102-030405.sql.gz" t
    _r_make_backup "$d/wp-20260102-030405-1.sql.gz" t       # same second, later
    _r_make_backup "$d/wp-20251231-235959.sql.gz" t
    _r_make_backup "$d/other-20270101-000000.sql.gz" t
    : > "$d/notes.txt"; : > "$d/wp-latest.sql.gz"; : > "$d/wp-20260103-000000.sql.gz.partial"; : > "$d/wpx-20260105-000000.sql.gz"

    local out
    out=$(restore_list_files "$d" wp | xargs -n1 basename | tr '\n' ' ')
    _chk "order: newest first, suffix -1 after the same second" test "$out" = "wp-20260102-030405-1.sql.gz wp-20260102-030405.sql.gz wp-20260101-000000.sql.gz wp-20251231-235959.sql.gz "
    _chk "other databases, junk, .partial and look-alike names are ignored" bash -c "! grep -qE 'other|notes|latest|partial|wpx' <<< '$out'"
    out=$(restore_list_files "$d" "" | xargs -n1 basename | head -1)
    _chk "--all: the newest of every database comes first" test "$out" = "other-20270101-000000.sql.gz"
    _chk "empty folder: no output, success"            bash -c "source '$_R_ROOT/lib/core/utils.sh' >/dev/null 2>&1; source '$_R_ROOT/lib/database/sql_source.sh' >/dev/null 2>&1; source '$_R_ROOT/lib/database/db_restore.sh' >/dev/null 2>&1; mkdir -p '$w/empty'; test -z \"\$(restore_list_files '$w/empty' wp)\""
    _chk "missing folder: no output, success"          bash -c "source '$_R_ROOT/lib/core/utils.sh' >/dev/null 2>&1; source '$_R_ROOT/lib/database/sql_source.sh' >/dev/null 2>&1; source '$_R_ROOT/lib/database/db_restore.sh' >/dev/null 2>&1; test -z \"\$(restore_list_files '$w/nope' wp)\""

    out=$(restore_print_list "$d" wp | _strip)
    _chk "table has a header and a row per backup"     bash -c "grep -q 'DATE' <<< '$out' && test \$(grep -c 'wp-2' <<< '$out') -eq 4"
    _chk "date is shown as YYYY-MM-DD HH:MM:SS"        grep -q '2026-01-02 03:04:05' <<< "$out"
    _chk "size is shown"                               grep -qE '[0-9]+ KB' <<< "$out"
    _chk "a hint explains how to restore"              grep -q 'restore --last' <<< "$out"
    out=$(restore_print_list "$w/empty" wp | _strip)
    _chk "no backups: says so"                         grep -q 'No backups found' <<< "$out"

    # database name rule is the same as the backup's (sanitized)
    printf "<?php\ndefine('DB_NAME','my db/name'); define('DB_USER','u'); define('DB_PASSWORD','p'); define('DB_HOST','h');\n" > "$w/wp-config.php"
    _chk "database name is sanitized like backup file names" bash -c "source '$_R_ROOT/lib/core/utils.sh' >/dev/null 2>&1; source '$_R_ROOT/lib/database/sql_source.sh' >/dev/null 2>&1; source '$_R_ROOT/lib/database/db_restore.sh' >/dev/null 2>&1; test \"\$(restore_current_db_name '$w')\" = 'my_db_name'"

    # backup_dir: default, config and ~
    _chk "default folder is ~/.wp-db-import/backups"   bash -c "source '$_R_ROOT/lib/database/db_restore.sh' >/dev/null 2>&1; export HOME=/h; CONFIG_BACKUP_DIR=; test \"\$(restore_backup_dir)\" = /h/.wp-db-import/backups"
    _chk "config backup_dir with ~ is expanded"        bash -c "source '$_R_ROOT/lib/database/db_restore.sh' >/dev/null 2>&1; export HOME=/h; CONFIG_BACKUP_DIR='~/bk'; test \"\$(restore_backup_dir)\" = /h/bk"
    _finish "listing works"
}

# ================================================================
# Restore flow (stubbed WP-CLI and importer)
# ================================================================
_r_stubs() {
    local w="$1"
    CALLS="$w/calls.log"; DBSTATE="$w/db.state"; : > "$CALLS"
    printf 'wp_posts\tBASE TABLE\nwp_options\tBASE TABLE\nplugin_new\tBASE TABLE\nplugin_view\tVIEW\n' > "$DBSTATE"
    execute_wp_cli() { echo "wpcli: $*" >> "$CALLS"; return 0; }
    _import_list_tables() { sort "$DBSTATE"; }
    _import_db_query() {
        echo "sql: $1" >> "$CALLS"
        local n; for n in $(printf '%s' "$1" | tr ';' '\n' | sed -n 's/^ *DROP TABLE IF EXISTS `\(.*\)`$/\1/p'); do
            awk -F'\t' -v n="$n" '$1 != n' "$DBSTATE" > "$DBSTATE.t"; mv "$DBSTATE.t" "$DBSTATE"
        done
        return "${R_DROP_RC:-0}"
    }
    perform_db_import() { echo "import: $1" >> "$CALLS"; return "${R_IMPORT_RC:-0}"; }
    backup_database_before_import() {
        echo "backup: mode=${CONFIG_BACKUP_BEFORE_IMPORT:-} protect=${WPDB_BACKUP_PROTECT:-}" >> "$CALLS"
        WPDB_LAST_BACKUP_FILE="$w/safety.sql.gz"
        return "${R_BACKUP_RC:-0}"
    }
}

test_restore_flow() {
    start_test "Restore Flow" "integrity check, confirmation, safety backup, import, cleanup of extra tables"
    _r_load
    local errors=0 w="$_R_WORK" out rc
    _r_stubs "$w"
    local good="$w/good.sql.gz"; _r_make_backup "$good" wp_posts wp_options
    export WPDB_ASSUME_YES=""

    # corrupt archive: refused before anything else happens
    head -c 20 "$good" > "$w/bad.sql.gz"
    : > "$CALLS"
    out=$(restore_database "$w/bad.sql.gz" "$w" "" 2>&1 </dev/null); rc=$?; out=$(printf '%s' "$out" | _strip)
    _chk "corrupt archive: restore fails"              test "$rc" -ne 0
    _chk "corrupt archive: says nothing was changed"   grep -q 'Nothing was changed' <<< "$out"
    _chk "corrupt archive: no backup, no import, no SQL" test ! -s "$CALLS"
    restore_database "$w/missing.sql.gz" "$w" "" >/dev/null 2>&1 </dev/null
    _chk "missing file: restore fails"                 test $? -ne 0
    restore_database "" "$w" "" >/dev/null 2>&1 </dev/null
    _chk "no file given: restore fails"                test $? -ne 0

    # confirmation: default answer is No
    : > "$CALLS"
    out=$(restore_database "$good" "$w" "" 2>&1 <<< "" ); rc=$?; out=$(printf '%s' "$out" | _strip)
    _chk "Enter (default No) cancels"                  bash -c "test $rc -eq 0 && grep -q 'Restore cancelled' <<< '$out'"
    _chk "cancelled: nothing was backed up or imported" test ! -s "$CALLS"
    out=$(restore_database "$good" "$w" "" 2>&1 <<< "n"); rc=$?
    _chk "answer n cancels"                            bash -c "test $rc -eq 0 && ! grep -q 'import:' '$CALLS'"
    out=$(restore_database "$good" "$w" "" 2>&1 </dev/null); rc=$?
    _chk "closed stdin cancels (never restores by accident)" bash -c "test $rc -eq 0 && ! grep -q 'import:' '$CALLS'"

    # confirmed: safety backup first, then import, then extra tables removed
    : > "$CALLS"; _r_stubs "$w"
    out=$(restore_database "$good" "$w" "" 2>&1 <<< "y"); rc=$?; out=$(printf '%s' "$out" | _strip)
    _chk "answer y restores"                           test "$rc" -eq 0
    _chk "order: safety backup BEFORE the import"      bash -c "test \$(grep -n '^backup:' '$CALLS' | head -1 | cut -d: -f1) -lt \$(grep -n '^import:' '$CALLS' | head -1 | cut -d: -f1)"
    _chk "the file is imported"                        grep -q "import: $good" "$CALLS"
    _chk "rotation is told to protect the file being restored" grep -q "protect=$good" "$CALLS"
    _chk "'ask' counts as yes for the safety backup"   grep -q 'mode=true' "$CALLS"
    _chk "only tables missing from the backup are dropped" bash -c "grep -q 'DROP TABLE IF EXISTS \`plugin_new\`' '$CALLS' && ! grep -q 'DROP TABLE IF EXISTS \`wp_posts\`' '$CALLS' && ! grep -q 'DROP TABLE IF EXISTS \`wp_options\`' '$CALLS'"
    _chk "views are never dropped"                     bash -c "! grep -q 'plugin_view' '$CALLS'"
    _chk "foreign key checks off while dropping"       grep -q 'SET FOREIGN_KEY_CHECKS=0' "$CALLS"
    _chk "tells how many tables were removed"          grep -q 'Removed 1 table' <<< "$out"
    _chk "cache is flushed after the restore"          grep -q 'wpcli: cache flush' "$CALLS"
    _chk "success message and undo hint"               bash -c "grep -q 'Database restored from good.sql.gz' <<< '$out' && grep -q 'Undo with: wp-db-import restore' <<< '$out'"
    _chk "pre-existing backup tables are kept in the database" bash -c "grep -q wp_posts '$DBSTATE' && grep -q wp_options '$DBSTATE' && ! grep -q plugin_new '$DBSTATE'"

    # --yes: no question, no stdin
    : > "$CALLS"; _r_stubs "$w"; export WPDB_ASSUME_YES=1
    out=$(restore_database "$good" "$w" "" 2>&1 < <(sleep 6)); rc=$?; out=$(printf '%s' "$out" | _strip)
    _chk "--yes restores without asking"               bash -c "test $rc -eq 0 && grep -q 'import:' '$CALLS' && ! grep -q 'Restore this backup now' <<< '$out'"
    export WPDB_ASSUME_YES=""

    # backup_before_import=false is honored (passed through to the backup function)
    : > "$CALLS"; _r_stubs "$w"; CONFIG_BACKUP_BEFORE_IMPORT=false
    restore_database "$good" "$w" "" >/dev/null 2>&1 <<< "y"
    _chk "backup_before_import=false is passed on (the user opted out)" grep -q 'mode=false' "$CALLS"
    CONFIG_BACKUP_BEFORE_IMPORT=""

    # safety backup fails: restore is cancelled, nothing imported
    : > "$CALLS"; _r_stubs "$w"
    out=$(R_BACKUP_RC=1 restore_database "$good" "$w" "" 2>&1 <<< "y"); rc=$?
    _chk "failed safety backup cancels the restore"    bash -c "test $rc -ne 0 && ! grep -q 'import:' '$CALLS'"

    # import fails: failure, extra tables are NOT dropped, safety backup location is shown
    : > "$CALLS"; _r_stubs "$w"
    out=$(R_IMPORT_RC=1 restore_database "$good" "$w" "" 2>&1 <<< "y"); rc=$?; out=$(printf '%s' "$out" | _strip)
    _chk "failed import: restore fails"                test "$rc" -ne 0
    _chk "failed import: no table is dropped"          bash -c "! grep -q 'DROP TABLE' '$CALLS'"
    _chk "failed import: points to the safety backup"  grep -q "$w/safety.sql.gz" <<< "$out"

    # table list of the backup unreadable: nothing is removed blindly
    printf 'garbage without create statements\n' | gzip -c > "$w/nolist.sql.gz"
    : > "$CALLS"; _r_stubs "$w"
    restore_database "$w/nolist.sql.gz" "$w" "" >/dev/null 2>&1 <<< "y"
    _chk "unreadable table list: nothing is dropped"   bash -c "grep -q 'import:' '$CALLS' && ! grep -q 'DROP TABLE' '$CALLS'"

    # hostile table name (backtick) is escaped
    : > "$CALLS"; _r_stubs "$w"; printf 'we`ird\tBASE TABLE\n' >> "$DBSTATE"
    restore_database "$good" "$w" "" >/dev/null 2>&1 <<< "y"
    _chk "backtick in a table name is escaped by doubling" grep -qF 'DROP TABLE IF EXISTS `we``ird`' "$CALLS"

    # works for the other file types
    local f
    printf "CREATE TABLE \`wp_posts\` (i int);\n" > "$w/plain.sql"
    gzip -c "$w/plain.sql" > "$w/plain.sql.gz"; bzip2 -c "$w/plain.sql" > "$w/plain.sql.bz2"
    ( cd "$w" && zip -q plain.zip plain.sql )
    for f in plain.sql plain.sql.gz plain.sql.bz2 plain.zip; do
        : > "$CALLS"; _r_stubs "$w"
        restore_database "$w/$f" "$w" "" >/dev/null 2>&1 <<< "y"
        _chk "file type accepted: $f"                  grep -q "import: $w/$f" "$CALLS"
    done

    unset -f execute_wp_cli _import_list_tables _import_db_query perform_db_import backup_database_before_import
    unset WPDB_ASSUME_YES; _r_load
    _finish "the restore flow is safe and complete"
}

# ================================================================
# Command line
# ================================================================
test_restore_cli() {
    start_test "Restore CLI" "--list, --last, <file>, usage errors and exit codes"
    _r_load
    local errors=0 w="$_R_WORK" out rc
    local d="$w/bk_cli"; mkdir -p "$d"
    printf "<?php\ndefine('DB_NAME','wp'); define('DB_USER','u'); define('DB_PASSWORD','p'); define('DB_HOST','h');\n" > "$w/wp-config.php"
    _r_make_backup "$d/wp-20260101-000000.sql.gz" wp_posts
    _r_make_backup "$d/wp-20260202-000000.sql.gz" wp_posts
    export WP_ROOT="$w" CONFIG_BACKUP_DIR="$d"
    _r_stubs "$w"

    out=$(restore_cli --list 2>&1 | _strip)
    _chk "--list shows this database's backups"        bash -c "grep -q 'wp-20260202-000000' <<< '$out' && grep -q 'wp-20260101-000000' <<< '$out'"
    restore_cli --list >/dev/null 2>&1; _chk "--list exits 0" test $? -eq 0

    : > "$CALLS"
    restore_cli --last >/dev/null 2>&1 <<< "y"; rc=$?
    _chk "--last restores the NEWEST backup"           bash -c "test $rc -eq 0 && grep -q 'import: $d/wp-20260202-000000.sql.gz' '$CALLS'"

    : > "$CALLS"
    restore_cli "$d/wp-20260101-000000.sql.gz" >/dev/null 2>&1 <<< "y"
    _chk "a file path restores that file"              grep -q "import: $d/wp-20260101-000000.sql.gz" "$CALLS"

    CONFIG_BACKUP_DIR="$w/empty_cli" restore_cli --last >/dev/null 2>&1; rc=$?
    out=$(CONFIG_BACKUP_DIR="$w/empty_cli" restore_cli --last 2>&1 | _strip)
    _chk "--last with no backup: exit 1"               test "$rc" -eq 1
    _chk "--last with no backup: explains and hints"   bash -c "grep -q 'No backup found' <<< '$out' && grep -q 'restore --list --all' <<< '$out'"

    restore_cli >/dev/null 2>&1; _chk "no arguments: usage error (2)" test $? -eq 2
    restore_cli --bogus >/dev/null 2>&1; _chk "unknown option: usage error (2)" test $? -eq 2
    restore_cli a.sql b.sql >/dev/null 2>&1; _chk "two files: usage error (2)" test $? -eq 2
    restore_cli --last a.sql >/dev/null 2>&1; _chk "file together with --last: usage error (2)" test $? -eq 2
    out=$(restore_cli 2>&1 | _strip)
    _chk "usage text lists --list, --last and <file>"  bash -c "grep -q -- '--list' <<< '$out' && grep -q -- '--last' <<< '$out' && grep -q '<file' <<< '$out'"

    unset WP_ROOT CONFIG_BACKUP_DIR
    unset -f execute_wp_cli _import_list_tables _import_db_query perform_db_import backup_database_before_import
    _finish "command line behaves correctly"
}

# ================================================================
# Rotation never deletes the file being restored
# ================================================================
test_restore_rotation_protection() {
    start_test "Rotation Protection" "backup_keep never deletes the backup that is being restored"
    _r_load
    local errors=0 w="$_R_WORK" i
    local d="$w/bk_rot"; mkdir -p "$d"
    for i in 1 2 3 4; do
        : > "$d/wp-2026010${i}-000000.sql.gz"; touch -t "2026010${i}0000" "$d/wp-2026010${i}-000000.sql.gz"
    done
    local current="$d/wp-20260105-000000.sql.gz"; : > "$current"; touch -t 202601050000 "$current"
    local oldest="$d/wp-20260101-000000.sql.gz"

    prune_old_backups "$d" wp 2 "$current" >/dev/null
    _chk "without protection the oldest backup is rotated away" test ! -e "$oldest"

    : > "$oldest"; touch -t 202601010000 "$oldest"
    WPDB_BACKUP_PROTECT="$oldest" prune_old_backups "$d" wp 2 "$current" >/dev/null
    _chk "WPDB_BACKUP_PROTECT keeps the file being restored" test -e "$oldest"
    _chk "other old backups are still rotated"         test ! -e "$d/wp-20260102-000000.sql.gz"
    _chk "the new backup is kept"                      test -e "$current"
    _finish "the file being restored is protected"
}

# ================================================================
# Wiring: command, help, completions, modules
# ================================================================
test_restore_wiring() {
    start_test "Restore Wiring" "restore is a command, in --help, in completions and loaded by the module loader"
    local errors=0 out
    out=$(bash "$_R_ROOT/wp-db-import" --help 2>&1 </dev/null | _strip)
    _chk "--help lists restore --last"                 grep -q 'restore --last' <<< "$out"
    _chk "--help lists restore --list"                 grep -q 'restore --list' <<< "$out"
    _chk "--help lists restore <file>"                 grep -q 'restore <file>' <<< "$out"
    _chk "module loader loads db_restore.sh"           grep -q 'db_restore.sh' "$_R_ROOT/lib/module_loader.sh"
    _chk "Bash completion offers restore"              grep -q 'restore' "$_R_ROOT/lib/completion/wp-db-import.bash"
    _chk "Zsh completion offers restore"               grep -q "'restore:" "$_R_ROOT/lib/completion/_wp-db-import"
    _chk "completion files have valid syntax"          bash -c "bash -n '$_R_ROOT/lib/completion/wp-db-import.bash' && (! command -v zsh >/dev/null || zsh -n '$_R_ROOT/lib/completion/_wp-db-import')"

    # outside a WordPress folder the command refuses (exit 1) instead of touching anything
    # (a folder of its own: the tool also looks in parent folders for wp-config.php)
    local empty rc
    empty=$(mktemp -d "${TMPDIR:-/tmp}/wpdb-notwp.XXXXXX")
    out=$(cd "$empty" && bash "$_R_ROOT/wp-db-import" restore --list 2>&1 </dev/null); rc=$?
    rmdir "$empty"
    _chk "outside WordPress: exit 1 with a message"    bash -c "test $rc -eq 1 && grep -qi 'wordpress' <<< '$out'"
    _finish "restore is wired in everywhere"
}

run_restore_tests() {
    printf "\n${CYAN}${BOLD}♻️  Restore Command Tests${RESET}\n"
    printf "%s\n\n" "$(printf '=%.0s' {1..50})"
    init_test_session "restore"
    _R_WORK=$(mktemp -d "${TMPDIR:-/tmp}/wpdb-restore-test.XXXXXX")
    trap 'secure_tmpdir_cleanup 2>/dev/null; rm -rf "$_R_WORK"' EXIT

    test_restore_listing
    test_restore_flow
    test_restore_cli
    test_restore_rotation_protection
    test_restore_wiring

    finalize_test_session
    return $?
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    run_restore_tests
fi
