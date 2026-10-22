#!/usr/bin/env bash

# ================================================================
# import_sql_mode (zero dates, strict sql_mode) - Tests
# ================================================================
#
# Description:
#   Tests for issue #24. A dump with zero dates fails on a server whose sql_mode has NO_ZERO_DATE /
#   NO_ZERO_IN_DATE. With import_sql_mode=auto (default) a failed import that shows a zero-date error
#   is retried once with those two modes off for the import SESSION only. Checked here: the SQL that
#   wraps the stream (set first, restored last, the dump's rows untouched, the server never changed),
#   which errors count as zero-date errors (and which do not), the retry plan for auto / keep / an
#   explicit list, the whole perform_db_import flow with a fake importer (one retry, no retry for
#   keep, an explicit list from the first attempt, a dump with other compatibility errors), the dry
#   run parity, and the config handling. (lib/tests/integration/test_real_import.sh runs it on a real
#   strict-mode server.)
#
# Usage:
#   ./lib/tests/unit/test_sql_mode.sh
#
# ================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../test_framework.sh"

_Q_ROOT="$PROJECT_ROOT_DIR"
_Q_WORK=""

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

_q_load() {
    source "$_Q_ROOT/lib/core/utils.sh" >/dev/null 2>&1
    source "$_Q_ROOT/lib/config/config_manager.sh" >/dev/null 2>&1
    source "$_Q_ROOT/lib/config/integration.sh" >/dev/null 2>&1
    source "$_Q_ROOT/lib/database/sql_source.sh" >/dev/null 2>&1
    source "$_Q_ROOT/lib/database/db_import.sh" >/dev/null 2>&1
}

# ----------------------------------------------------------------
test_stream() {
    start_test "Stream" "the session wrapper: set first, restored last, rows untouched, global mode never set"
    _q_load
    local errors=0 w="$_Q_WORK" out
    printf "CREATE TABLE \`t\` (d datetime NOT NULL DEFAULT '0000-00-00 00:00:00');\nINSERT INTO \`t\` VALUES ('0000-00-00 00:00:00');\nINSERT INTO \`o\` VALUES ('SET SESSION sql_mode = x; NO_ZERO_DATE');\n" > "$w/z.sql"

    out=$(_emit_import_stream "$w/z.sql" false false)
    _chk "default (no mode): the stream is the dump, nothing added"  test "$out" = "$(cat "$w/z.sql")"
    out=$(_emit_import_stream "$w/z.sql" false false "")
    _chk "empty mode argument: nothing added"                        test "$out" = "$(cat "$w/z.sql")"

    out=$(_emit_import_stream "$w/z.sql" false false relax)
    _chk "relax: the old mode is saved first"                        bash -c 'head -1 <<< "$0" | grep -qx "SET @wpdb_old_sql_mode = @@SESSION.sql_mode;"' "$out"
    _chk "relax: only the two zero-date modes are removed (the other modes stay)" bash -c 'grep -q "REPLACE(REPLACE(REPLACE(REPLACE(@@SESSION.sql_mode, .NO_ZERO_IN_DATE., ..), .NO_ZERO_DATE., ..)" <<< "$0"' "$out"
    _chk "relax: the old mode is restored last"                      bash -c 'tail -1 <<< "$0" | grep -qx "SET SESSION sql_mode = @wpdb_old_sql_mode;"' "$out"
    _chk "relax: it is a SESSION setting, never GLOBAL"              bash -c '! grep -qi "GLOBAL" <<< "$0"' "$out"
    _chk "relax: the dump lines are all there, in order, unchanged"  test "$(printf '%s\n' "$out" | sed '1,2d;$d')" = "$(cat "$w/z.sql")"
    _chk "relax: a row that contains the text sql_mode is not touched" grep -q "INSERT INTO \`o\` VALUES ('SET SESSION sql_mode = x; NO_ZERO_DATE');" <<< "$out"

    out=$(_emit_import_stream "$w/z.sql" false false "NO_AUTO_VALUE_ON_ZERO")
    _chk "explicit list: set for the session"                        grep -qx "SET SESSION sql_mode = 'NO_AUTO_VALUE_ON_ZERO';" <<< "$out"
    _chk "explicit list: restored at the end"                        bash -c 'tail -1 <<< "$0" | grep -qx "SET SESSION sql_mode = @wpdb_old_sql_mode;"' "$out"

    # together with the session optimizations and the compatibility filter
    printf "CREATE TABLE \`t\` (c varchar(9) COLLATE utf8mb4_0900_ai_ci);\n" > "$w/c.sql"
    out=$(_emit_import_stream "$w/c.sql" true true relax)
    _chk "all three: mode saved before the optimizations"            bash -c 'a=$(grep -n "wpdb_old_sql_mode = @@" <<< "$0" | head -1 | cut -d: -f1); b=$(grep -n "AUTOCOMMIT = 0" <<< "$0" | head -1 | cut -d: -f1); test "$a" -lt "$b"' "$out"
    _chk "all three: mode restored after the optimizations end"      bash -c 'a=$(grep -n "AUTOCOMMIT = 1" <<< "$0" | head -1 | cut -d: -f1); b=$(grep -n "sql_mode = @wpdb_old" <<< "$0" | tail -1 | cut -d: -f1); test "$a" -lt "$b"' "$out"
    _chk "all three: the compatibility filter still ran"             grep -q "utf8mb4_unicode_520_ci" <<< "$out"

    # a compressed dump
    gzip -c "$w/z.sql" > "$w/z.sql.gz"
    out=$(_emit_import_stream "$w/z.sql.gz" false false relax)
    _chk "a .gz dump is wrapped the same way"                        bash -c 'grep -q "INSERT INTO .t. VALUES" <<< "$0" && head -1 <<< "$0" | grep -q wpdb_old_sql_mode' "$out"

    # the dry-run stream passes the mode through
    source "$_Q_ROOT/lib/database/db_dry_run.sh" >/dev/null 2>&1
    out=$(_dry_run_stream "$w/z.sql" false relax)
    _chk "the dry-run stream is wrapped too"                         grep -q "wpdb_old_sql_mode" <<< "$out"
    out=$(_dry_run_stream "$w/c.sql" false)
    _chk "the dry-run stream without a mode is as before"            bash -c '! grep -q "sql_mode" <<< "$0"' "$out"
    _finish "the wrapper is correct"
}

# ----------------------------------------------------------------
test_detection() {
    start_test "Detection" "which failures are zero-date errors, and the retry plan"
    _q_load
    local errors=0 w="$_Q_WORK" l="$_Q_WORK/err.log"
    _log() { printf '%s\n' "$1" > "$l"; }

    _log "ERROR 1067 (42000) at line 12: Invalid default value for 'post_date'"
    _chk "ERROR 1067 Invalid default value"                  import_error_is_zero_date "$l"
    _log "ERROR 1292 (22007) at line 80: Incorrect datetime value: '0000-00-00 00:00:00' for column 'd' at row 1"
    _chk "ERROR 1292 Incorrect datetime value"               import_error_is_zero_date "$l"
    _log "ERROR 1292 (22007) at line 80: Incorrect date value: '2019-00-10' for column 'e' at row 1"
    _chk "ERROR 1292 Incorrect date value (zero month/day)"  import_error_is_zero_date "$l"
    _log "ERROR 1292 (22007): Truncated incorrect DOUBLE value: 'abc'"
    _chk "ERROR 1292 Truncated incorrect DOUBLE is NOT a date error" bash -c '! import_error_is_zero_date "$0"' "$l"
    _log "ERROR 1064 (42000) at line 3: You have an error in your SQL syntax"
    _chk "a syntax error is not a zero-date error"           bash -c '! import_error_is_zero_date "$0"' "$l"
    _log "ERROR 1366 (HY000): Incorrect string value: '\\xF0' for column 'c'"
    _chk "an incorrect string value is not a zero-date error" bash -c '! import_error_is_zero_date "$0"' "$l"
    _log "ERROR 1273 (HY000): Unknown collation: 'utf8mb4_0900_ai_ci'"
    _chk "a collation error is not a zero-date error"        bash -c '! import_error_is_zero_date "$0"' "$l"
    _chk "a missing log is not a zero-date error"            bash -c '! import_error_is_zero_date "$0/none"' "$w"
    _chk "import_error_is_compat_related is unchanged (a zero-date error is not a compat error)" bash -c '_log() { printf "%s\n" "$1" > "$0"; }; _log "ERROR 1067 (42000): Invalid default value for x"; ! import_error_is_compat_related "$0"' "$l"

    # the retry plan
    local zero="ERROR 1067 (42000) at line 12: Invalid default value for 'd'" compat="ERROR 1273 (HY000): Unknown collation: 'x'"
    CONFIG_IMPORT_SQL_MODE=auto
    _log "$zero"; import_retry_plan "$l"; local rc=$?
    _chk "auto + zero-date error: retry, relax, no filter"   test "$rc" -eq 0 -a "$RETRY_SQLMODE" = relax -a "$RETRY_FILTER" = false
    _log "$compat"; import_retry_plan "$l"; rc=$?
    _chk "auto + compat error: retry with the filter only"   test "$rc" -eq 0 -a -z "$RETRY_SQLMODE" -a "$RETRY_FILTER" = true
    printf '%s\n%s\n' "$zero" "$compat" > "$l"; import_retry_plan "$l"; rc=$?
    _chk "auto + both errors: both changes"                  test "$rc" -eq 0 -a "$RETRY_SQLMODE" = relax -a "$RETRY_FILTER" = true
    _log "ERROR 2002 (HY000): Can't connect to MySQL server"; import_retry_plan "$l"; rc=$?
    _chk "auto + an unrelated error: no retry"               test "$rc" -ne 0 -a -z "$RETRY_SQLMODE" -a "$RETRY_FILTER" = false
    CONFIG_IMPORT_SQL_MODE=""
    _log "$zero"; import_retry_plan "$l"; rc=$?
    _chk "empty value behaves as auto"                       test "$rc" -eq 0 -a "$RETRY_SQLMODE" = relax
    unset CONFIG_IMPORT_SQL_MODE
    _log "$zero"; import_retry_plan "$l"; rc=$?
    _chk "variable not set behaves as auto"                  test "$rc" -eq 0 -a "$RETRY_SQLMODE" = relax
    CONFIG_IMPORT_SQL_MODE=KEEP
    _log "$zero"; import_retry_plan "$l"; rc=$?
    _chk "keep + zero-date error: no retry at all"           test "$rc" -ne 0 -a -z "$RETRY_SQLMODE"
    _log "$compat"; import_retry_plan "$l"; rc=$?
    _chk "keep + compat error: the filter retry still works (as before)" test "$rc" -eq 0 -a "$RETRY_FILTER" = true -a -z "$RETRY_SQLMODE"
    CONFIG_IMPORT_SQL_MODE="NO_AUTO_VALUE_ON_ZERO"
    _log "$zero"; import_retry_plan "$l"; rc=$?
    _chk "explicit list + zero-date error: no second change (the list is already used)" test "$rc" -ne 0 -a -z "$RETRY_SQLMODE"
    unset CONFIG_IMPORT_SQL_MODE

    # the value check
    _chk "validate: empty, auto, keep, AUTO"                 bash -c 'import_sql_mode_validate "" && import_sql_mode_validate auto && import_sql_mode_validate keep && import_sql_mode_validate AUTO'
    _chk "validate: a mode list"                             import_sql_mode_validate "NO_AUTO_VALUE_ON_ZERO,STRICT_TRANS_TABLES"
    local bad
    for bad in "a b" "x;DROP" "x'y" 'x"y' 'x`y' 'x$(id)' "../x" "a|b"; do
        _chk "validate refuses: $bad"                        bash -c '! import_sql_mode_validate "$0" >/dev/null' "$bad"
    done
    _chk "validate: the message names the key"               bash -c 'out=$(import_sql_mode_validate "a b"); grep -q "import_sql_mode: .a b." <<< "$out"'
    _finish "the retry plan is correct"
}

# ----------------------------------------------------------------
test_flow() {
    start_test "Flow" "perform_db_import with a fake importer: one retry for zero dates, none for keep, explicit list from the start"
    _q_load
    local errors=0 w="$_Q_WORK" out raw rc
    local attempts="$w/q_attempts" state="$w/q_state"
    show_spinner() { return 0; }
    export CONFIG_USE_SOCKET=false CONFIG_BACKUP_BEFORE_IMPORT=false
    # fake WP-CLI importer: records "filter|mode|kind"; the dump fails with the error named in Q_ERR unless it is handled
    perform_db_import_via_wpcli() {
        local f="$1" log="$2" compat="$3" kind="${5:-}" mode="${6:-}"
        echo "$compat|$mode|$kind" >> "$attempts"
        : > "$log"
        case "${Q_ERR:-zero}" in
            zero)  if [[ -z "$mode" ]]; then echo "ERROR 1067 (42000) at line 12: Invalid default value for 'd'" > "$log"; return 1; fi ;;
            both)  if [[ "$compat" != "true" || -z "$mode" ]]; then printf "ERROR 1273 (HY000): Unknown collation: 'x'\nERROR 1067 (42000): Invalid default value for 'd'\n" > "$log"; return 1; fi ;;
            none)  echo "ERROR 1064 (42000): syntax error" > "$log"; return 1 ;;
        esac
        return 0
    }
    execute_wp_cli() { return 0; }
    printf 'DROP TABLE IF EXISTS t1;\nCREATE TABLE t1 (d datetime DEFAULT 0);\n' > "$w/q.sql"
    _run() { : > "$attempts"; perform_db_import "$w/q.sql" "$w/q.log" > "$w/q.out" 2>&1 </dev/null; rc=$?; out=$(_strip < "$w/q.out"); }

    CONFIG_IMPORT_SQL_MODE=auto; Q_ERR=zero; _run
    _chk "auto: the import succeeds"                         bash -c 'test "$1" -eq 0 && grep -q "Database import successful" <<< "$0"' "$out" "$rc"
    _chk "auto: exactly two attempts (plain, then relaxed)"  test "$(wc -l < "$attempts" | tr -d ' ')" = 2
    _chk "auto: the first attempt changed nothing"           bash -c 'sed -n 1p "$0" | grep -qx "false||"' "$attempts"
    _chk "auto: the retry relaxed the mode, no filter"       bash -c 'sed -n 2p "$0" | grep -qx "false|relax|"' "$attempts"
    _chk "auto: the user is told what changed and that it is session only" bash -c 'grep -q "zero-date error" <<< "$0" && grep -q "this import session only" <<< "$0"' "$out"
    _chk "auto: the final note says the server mode was not changed" grep -q 'the server sql_mode was not changed' <<< "$out"
    _chk "auto: no 'compatibility filter' note (it was not used)" bash -c '! grep -q "Imported with the SQL compatibility filter" <<< "$0"' "$out"
    _chk "auto: the report notes name the zero dates"        grep -q 'zero dates allowed' <<< "$WPDB_IMPORT_NOTES"

    CONFIG_IMPORT_SQL_MODE=auto; Q_ERR=both; _run
    _chk "both errors: succeeds on the retry with filter and relaxed mode" bash -c 'test "$1" -eq 0 && sed -n 2p "$2" | grep -qx "true|relax|"' "$out" "$rc" "$attempts"
    _chk "both errors: both notes are printed"               bash -c 'grep -q "compatibility filter" <<< "$0" && grep -q "zero dates allowed" <<< "$0"' "$out"

    CONFIG_IMPORT_SQL_MODE=keep; Q_ERR=zero; _run
    _chk "keep: the zero-date failure is not retried with a changed mode" bash -c 'test "$1" -ne 0 && ! grep -q "relax" "$2" && grep -q "Database import failed" <<< "$0"' "$out" "$rc" "$attempts"
    _chk "keep: the error is shown to the user"              grep -q 'ERROR 1067' <<< "$out"

    CONFIG_IMPORT_SQL_MODE="NO_AUTO_VALUE_ON_ZERO"; Q_ERR=zero; _run
    _chk "explicit list: used from the first attempt, succeeds at once" bash -c 'test "$1" -eq 0 && test "$(wc -l < "$2" | tr -d " ")" = 1 && sed -n 1p "$2" | grep -qx "false|NO_AUTO_VALUE_ON_ZERO|"' "$out" "$rc" "$attempts"
    _chk "explicit list: announced"                          grep -q 'Session sql_mode for this import: NO_AUTO_VALUE_ON_ZERO' <<< "$out"

    CONFIG_IMPORT_SQL_MODE=auto; Q_ERR=none; _run
    _chk "an unrelated error: no sql_mode retry (as before)" bash -c 'test "$1" -ne 0 && ! grep -q "relax" "$2"' "$out" "$rc" "$attempts"

    unset CONFIG_IMPORT_SQL_MODE
    Q_ERR=zero; _run
    _chk "variable not set: behaves as auto"                 bash -c 'test "$1" -eq 0 && grep -q "|relax|" "$2"' "$out" "$rc" "$attempts"

    # a clean import is exactly as before: one attempt, no sql_mode argument, no extra message
    Q_ERR=ok; CONFIG_IMPORT_SQL_MODE=auto; _run
    _chk "a dump without zero dates: one attempt, no mode change" bash -c 'test "$1" -eq 0 && test "$(wc -l < "$2" | tr -d " ")" = 1 && sed -n 1p "$2" | grep -qx "false||"' "$out" "$rc" "$attempts"
    _chk "a dump without zero dates: no sql_mode message at all" bash -c '! grep -qi "sql_mode\|zero" <<< "$0"' "$out"

    unset -f execute_wp_cli show_spinner perform_db_import_via_wpcli _run
    unset CONFIG_USE_SOCKET CONFIG_BACKUP_BEFORE_IMPORT CONFIG_IMPORT_SQL_MODE Q_ERR
    _q_load
    _finish "the flow is correct"
}

# ----------------------------------------------------------------
test_socket_stream() {
    start_test "Socket stream" "the mysql client receives the wrapped stream; the password stays in MYSQL_PWD"
    _q_load
    local errors=0 w="$_Q_WORK"
    cat > "$w/mysql" <<'EOF'
#!/usr/bin/env bash
{ printf 'ARGS:'; printf ' [%s]' "$@"; printf ' PWDSET=%s\n' "${MYSQL_PWD:+yes}"; } >> "$STUB_LOG"
cat > "$STUB_STDIN"
exit 0
EOF
    chmod +x "$w/mysql"
    printf "CREATE TABLE t (d datetime DEFAULT '0000-00-00 00:00:00');\n" > "$w/s.sql"
    export WPDB_MYSQL_BIN="$w/mysql" STUB_LOG="$w/s.log" STUB_STDIN="$w/s.in"
    : > "$STUB_LOG"
    perform_db_import_via_socket "$w/s.sql" "$w/s.out" "" "localhost" "u" "s3cret" "wpdb" "true" "false" "relax" >/dev/null 2>&1
    _chk "the stream sent to mysql has the session wrapper"  bash -c 'head -4 "$0" | grep -q wpdb_old_sql_mode && tail -2 "$0" | grep -q "sql_mode = @wpdb_old_sql_mode"' "$STUB_STDIN"
    _chk "the optimizations are still there"                 grep -q 'SET AUTOCOMMIT = 0' "$STUB_STDIN"
    _chk "the password is not on the command line"           bash -c '! grep -q s3cret "$0"' "$STUB_LOG"
    perform_db_import_via_socket "$w/s.sql" "$w/s.out" "" "localhost" "u" "s3cret" "wpdb" "false" "false" >/dev/null 2>&1
    _chk "without the argument: the stream has no sql_mode lines" bash -c '! grep -q sql_mode "$0"' "$STUB_STDIN"
    unset WPDB_MYSQL_BIN STUB_LOG STUB_STDIN
    _finish "the socket path sends the right stream"
}

# ----------------------------------------------------------------
test_config() {
    start_test "Config" "upgrade, load, validate, show, new config, examples"
    _q_load
    local errors=0 old="$_Q_WORK/old.conf" run="$_Q_WORK/run.conf" a out
    printf '%s\n' '[general]' 'sql_file=dump.sql' 'old_domain=prod.com' 'new_domain=local.test' '[site_mappings]' '1:prod.com:local.test' > "$old"
    cp "$old" "$run"
    ensure_socket_config_settings "$run" >/dev/null 2>&1
    _chk "the upgrade names the key"                       bash -c '[[ "$0" == *"import_sql_mode"* ]]' "$CONFIG_SETTINGS_MIGRATED_ITEMS"
    _chk "default: import_sql_mode=auto with its comment"  bash -c 'source "'"$_Q_ROOT"'/lib/core/utils.sh" >/dev/null 2>&1; source "'"$_Q_ROOT"'/lib/config/config_manager.sh" >/dev/null 2>&1; t=$(cat "$0"); grep -qx "import_sql_mode=auto" "$0" && [[ -n "$(config_key_comment import_sql_mode)" && "$t" == *"$(config_key_comment import_sql_mode)"*"import_sql_mode=auto"* ]]' "$run"
    _chk "no line of the old file changed or was removed"  bash -c '! diff "$0" "$1" | grep -q "^<"' "$old" "$run"
    a=$(cksum < "$run"); ensure_socket_config_settings "$run" >/dev/null 2>&1
    _chk "a second run changes nothing"                    test "$a" = "$(cksum < "$run")"
    printf '%s\n' '[general]' 'sql_file=a.sql' 'import_sql_mode=keep' '' '[site_mappings]' > "$run"
    ensure_socket_config_settings "$run" >/dev/null 2>&1
    _chk "an existing value is kept"                       bash -c 'grep -qx "import_sql_mode=keep" "$0" && test "$(grep -c "^import_sql_mode" "$0")" = 1' "$run"

    load_import_config "$run" >/dev/null 2>&1
    _chk "load_import_config reads keep"                   test "$CONFIG_IMPORT_SQL_MODE" = keep
    cp "$old" "$_Q_WORK/nokeys.conf"; load_import_config "$_Q_WORK/nokeys.conf" >/dev/null 2>&1
    _chk "a config without the key loads auto"             test "$CONFIG_IMPORT_SQL_MODE" = auto
    printf '%s\n' '[general]' 'sql_file=a.sql' 'import_sql_mode=' '[site_mappings]' > "$_Q_WORK/empty.conf"
    load_import_config "$_Q_WORK/empty.conf" >/dev/null 2>&1
    _chk "an empty value loads auto"                       test "$CONFIG_IMPORT_SQL_MODE" = auto

    create_config_file "$_Q_WORK/fresh.conf" a.sql a.com b.test >/dev/null 2>&1
    _chk "a new config has the key and validates"          bash -c 'source "'"$_Q_ROOT"'/lib/core/utils.sh" >/dev/null 2>&1; source "'"$_Q_ROOT"'/lib/config/config_manager.sh" >/dev/null 2>&1; grep -qx "import_sql_mode=auto" "$0" && validate_config_file "$0"' "$_Q_WORK/fresh.conf"
    printf '%s\n' '[general]' 'sql_file=a.sql' 'old_domain=a.com' 'new_domain=b.test' 'import_sql_mode=a b;x' '[site_mappings]' > "$run"
    out=$(validate_config_file "$run" 2>&1); a=$?
    _chk "validate: a bad value fails with a message"      bash -c 'test "$1" -ne 0 && grep -q "import_sql_mode" <<< "$0"' "$out" "$a"
    printf '%s\n' '[general]' 'sql_file=a.sql' 'old_domain=a.com' 'new_domain=b.test' 'import_sql_mode=NO_AUTO_VALUE_ON_ZERO' '[site_mappings]' > "$run"
    _chk "validate: a mode list passes"                    validate_config_file "$run"
    out=$(show_config "$run" 2>&1 | _strip)
    _chk "config-show prints the value"                    grep -q 'Import SQL Mode: *NO_AUTO_VALUE_ON_ZERO' <<< "$out"
    printf '%s\n' '[general]' 'sql_file=a.sql' '[site_mappings]' > "$run"
    out=$(show_config "$run" 2>&1 | _strip)
    _chk "config-show default is auto"                     grep -q 'Import SQL Mode: *auto' <<< "$out"
    local f
    for f in single multisite; do
        _chk "example $f config has the key"               grep -qx 'import_sql_mode=auto' "$_Q_ROOT/wpdb-import-example-$f.conf"
    done
    _chk "doctor's strict-mode row points to import_sql_mode" grep -q 'import_sql_mode=auto' "$_Q_ROOT/lib/utilities/doctor.sh"
    _finish "config handling is complete"
}

# ----------------------------------------------------------------
test_wiring() {
    start_test "Wiring" "every import attempt passes the session mode; the dry run uses the same plan"
    local errors=0 f="$_Q_ROOT/lib/database/db_import.sh" d="$_Q_ROOT/lib/database/db_dry_run.sh"
    _chk "socket path: first attempt and retry pass the mode"   bash -c '[[ $(grep -c "\"\$sql_mode_arg\"" "$0") -ge 4 ]]' "$f"
    _chk "the old compat-only retry test is replaced by the plan in both paths" bash -c '[[ $(grep -c "import_retry_plan" "$0") -eq 2 ]] && ! grep -q "elif import_error_is_compat_related\|if import_error_is_compat_related" "$0"' "$f"
    _chk "the WP-CLI fallbacks pass the mode"                   bash -c 'grep -q "\"\$wp_cmd\" direct \"\$sql_mode_arg\"" "$0" && grep -q "\"\$wp_cmd\" \"\" \"\$sql_mode_arg\"" "$0"' "$f"
    _chk "a plain file is streamed (not read directly) when a mode is set" bash -c '[[ $(grep -c "\-z \"\$sql_mode_arg\"" "$0") -eq 2 ]]' "$f"
    _chk "the dry run uses the same retry plan"                 bash -c 'grep -q "import_retry_plan" "$0" && grep -q "_dry_run_stream \"\$sql_file\" \"\$retry_filter\" \"\$sql_mode_arg\"" "$0"' "$d"
    _chk "the global sql_mode is never set anywhere"            bash -c '! grep -rniE "SET[[:space:]]+(@@)?GLOBAL[[:space:].]+sql_mode" "$0" "$1" "$2"' "$f" "$d" "$_Q_ROOT/lib/database/sql_source.sh"
    _finish "wiring is complete"
}

run_sql_mode_tests() {
    printf "\n${CYAN}${BOLD}🧪 Import SQL Mode Tests${RESET}\n"
    printf "%s\n\n" "$(printf '=%.0s' {1..50})"
    init_test_session "sql_mode"
    _Q_WORK=$(mktemp -d "${TMPDIR:-/tmp}/wpdb-sqlmode-test.XXXXXX")
    trap 'rm -rf "$_Q_WORK"' EXIT

    test_stream
    test_detection
    test_flow
    test_socket_stream
    test_config
    test_wiring

    finalize_test_session
    return $?
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    run_sql_mode_tests
fi
