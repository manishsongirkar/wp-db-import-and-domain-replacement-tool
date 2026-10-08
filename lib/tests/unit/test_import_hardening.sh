#!/usr/bin/env bash

# ================================================================
# Import Hardening - Unit Tests
# ================================================================
#
# Description:
#   Unit tests for the import safety work:
#     1. Pre-import backup                      (lib/database/db_backup.sh)
#     2. Compressed dumps (.gz/.zip/.bz2)        (lib/database/sql_source.sh)
#     3. MariaDB/MySQL compatibility filter      (lib/database/sql_source.sh)
#     4. Checksum-verified Stage File Proxy download
#     5. Private temp directory instead of fixed /tmp paths
#     6. Benchmark in a scratch database (never the real one)
#     7. Size-based estimate when the sample has no INSERT rows
#   Uses stub `mysql` binaries and stub WP-CLI functions; no database is needed.
#
# Usage:
#   ./lib/tests/unit/test_import_hardening.sh
#
# ================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../test_framework.sh"

# File mode in octal on GNU and BSD stat (GNU first: on GNU stat, -f means "filesystem")
_file_mode() { stat -c %a "$1" 2>/dev/null || stat -f %Lp "$1"; }

_HARD_ROOT="$PROJECT_ROOT_DIR"
_HARD_WORK=""

_hard_load() {
    source "$_HARD_ROOT/lib/core/utils.sh" >/dev/null 2>&1
    source "$_HARD_ROOT/lib/database/sql_source.sh" >/dev/null 2>&1
    source "$_HARD_ROOT/lib/database/db_import.sh" >/dev/null 2>&1
    source "$_HARD_ROOT/lib/database/db_backup.sh" >/dev/null 2>&1
    source "$_HARD_ROOT/lib/utilities/stage_file_proxy.sh" >/dev/null 2>&1
}

_hard_workdir() {
    # Created once by the run function (never inside $(...), which would lose the variable)
    printf "%s" "$_HARD_WORK"
}

# Report helpers: _chk <description> <command...> ; counts failures in $errors
_chk() {
    local desc="$1"; shift
    if "$@" >/dev/null 2>&1; then
        printf "  ✅ %s\n" "$desc"
    else
        printf "  ❌ %s\n" "$desc"
        ((errors++))
    fi
}

_finish() {
    if [[ "$errors" -eq 0 ]]; then
        pass_test "$1"
    else
        fail_test "$errors check(s) failed"
    fi
}

# Stub mysql: logs args and the MYSQL_PWD flag, saves stdin of non-"-e" calls.
# STUB_FAIL_CREATE=1 makes "CREATE DATABASE" fail; STUB_FAIL_IMPORT=1 makes imports fail.
_hard_make_mysql_stub() {
    local dir="$1"
    cat > "$dir/mysql" <<'EOF'
#!/usr/bin/env bash
{ printf 'ARGS:'; printf ' [%s]' "$@"; printf ' PWDSET=%s\n' "${MYSQL_PWD:+yes}"; } >> "$STUB_LOG"
for a in "$@"; do
    if [[ "$a" == *"CREATE DATABASE"* && "${STUB_FAIL_CREATE:-0}" == "1" ]]; then exit 1; fi
done
is_exec=0; for a in "$@"; do [[ "$a" == "-e" ]] && is_exec=1; done
if [[ $is_exec -eq 0 ]]; then
    cat > "${STUB_STDIN:-/dev/null}"
    [[ "${STUB_FAIL_IMPORT:-0}" == "1" ]] && { echo "ERROR 1273 (HY000): Unknown collation" >&2; exit 1; }
fi
exit 0
EOF
    chmod +x "$dir/mysql"
}

# ================================================================
# 5. Private temp directory
# ================================================================
test_secure_tmpdir() {
    start_test "Private Temp Directory" "secure_tmpdir creates a private dir and refuses symlinks"
    _hard_load
    local errors=0 base d
    base=$(_hard_workdir)/tmpbase
    mkdir -p "$base"

    d=$(TMPDIR="$base" secure_tmpdir)
    _chk "directory is created" test -d "$d"
    _chk "directory mode is 700" test "$(_file_mode "$d")" = "700"
    _chk "directory is owned by current user" test -O "$d"
    _chk "path is under TMPDIR, not fixed /tmp" test "${d#"$base"/}" != "$d"
    _chk "second call returns the same directory" test "$(TMPDIR="$base" secure_tmpdir)" = "$d"

    TMPDIR="$base" secure_tmpdir_cleanup
    _chk "cleanup removes the directory" test ! -e "$d"

    # A pre-planted symlink (classic /tmp attack) must be refused. Subshell keeps the same $$.
    _symlink_refused() {
        ( export TMPDIR="$base"; ln -s "$base" "$base/wpdb-import-$(id -u)-$$"; ! secure_tmpdir >/dev/null 2>&1 )
    }
    _chk "symlink in the way is refused" _symlink_refused
    rm -f "$base/wpdb-import-$(id -u)-$$"

    # No new fixed /tmp paths in production code
    local hits
    hits=$(grep -rnE '"/tmp/|=/tmp/' "$_HARD_ROOT/import_wp_db.sh" "$_HARD_ROOT"/lib --include=*.sh 2>/dev/null \
        | grep -vE '/lib/tests/|socket_detector.sh|core/validation.sh|core/cleanup.sh|^\S+:[0-9]+:\s*#' | grep -vE 'TMPDIR:-/tmp')
    _chk "no fixed /tmp file paths left in production code" test -z "$hits"
    [[ -n "$hits" ]] && printf "%s\n" "$hits" | sed 's/^/     /'
    _finish "secure temp directory behaves correctly"
}

# ================================================================
# 2. Compressed dumps
# ================================================================
test_compressed_dumps() {
    start_test "Compressed Dumps" "gz/zip/bz2 streams equal the plain SQL; corrupt archives are rejected"
    _hard_load
    local errors=0 w; w=$(_hard_workdir)
    printf "CREATE TABLE t (id int);\nINSERT INTO t VALUES (1),(2);\n-- \xc3\xa9 utf8\n" > "$w/d.sql"
    gzip -c "$w/d.sql" > "$w/d.sql.gz"
    bzip2 -c "$w/d.sql" > "$w/d.sql.bz2"
    ( cd "$w" && mkdir -p z/__MACOSX && cp d.sql z/d.sql && printf 'junk\000binary' > z/__MACOSX/._d.sql && zip -qr d.zip z/d.sql z/__MACOSX )

    _chk "kind: .sql is plain"      test "$(sql_file_kind a.sql)" = plain
    _chk "kind: .SQL.GZ is gzip"    test "$(sql_file_kind A.SQL.GZ)" = gzip
    _chk "kind: .zip is zip"        test "$(sql_file_kind a.zip)" = zip
    _chk "kind: .bz2 is bzip2"      test "$(sql_file_kind a.bz2)" = bzip2
    _chk "plain stream identical"   cmp -s <(sql_open_stream "$w/d.sql") "$w/d.sql"
    _chk "gzip stream identical"    cmp -s <(sql_open_stream "$w/d.sql.gz") "$w/d.sql"
    _chk "bzip2 stream identical"   cmp -s <(sql_open_stream "$w/d.sql.bz2") "$w/d.sql"
    _chk "zip stream identical (ignores __MACOSX junk)" cmp -s <(sql_open_stream "$w/d.zip") "$w/d.sql"

    local f
    for f in d.sql d.sql.gz d.sql.bz2 d.zip; do
        _chk "verify accepts $f" sql_verify_source "$w/$f"
    done

    head -c 30 "$w/d.sql.gz" > "$w/bad.sql.gz"
    _chk "verify rejects truncated gzip"   bash -c "! source '$_HARD_ROOT/lib/database/sql_source.sh' >/dev/null 2>&1; ! sql_verify_source '$w/bad.sql.gz'"
    printf 'not a zip' > "$w/bad.zip"
    _chk "verify rejects corrupt zip"      bash -c "source '$_HARD_ROOT/lib/database/sql_source.sh' >/dev/null 2>&1; ! sql_verify_source '$w/bad.zip'"
    ( cd "$w" && echo hi > a.txt && zip -q nosql.zip a.txt )
    _chk "verify rejects zip without .sql" bash -c "source '$_HARD_ROOT/lib/database/sql_source.sh' >/dev/null 2>&1; ! sql_verify_source '$w/nosql.zip'"
    _chk "verify rejects missing file"     bash -c "source '$_HARD_ROOT/lib/database/sql_source.sh' >/dev/null 2>&1; ! sql_verify_source '$w/nope.sql'"

    local plain_size gz_size
    plain_size=$(_sql_file_size_bytes "$w/d.sql")
    _chk "uncompressed size of plain = file size"  test "$(sql_uncompressed_size_bytes "$w/d.sql")" = "$plain_size"
    _chk "uncompressed size of gzip = SQL size"    test "$(sql_uncompressed_size_bytes "$w/d.sql.gz")" = "$plain_size"
    gz_size=$(_sql_file_size_bytes "$w/d.sql.bz2")
    _chk "bzip2 size falls back to 5x compressed"  test "$(sql_uncompressed_size_bytes "$w/d.sql.bz2")" = "$((gz_size * 5))"
    _finish "compressed dumps are streamed and verified"
}

# ================================================================
# 3. Compatibility filter
# ================================================================
test_compat_filter() {
    start_test "Compatibility Filter" "rewrites version-specific DDL and never touches row data"
    _hard_load
    local errors=0 out
    out=$(printf '%s\n' \
        '/*M!999999\- enable the sandbox mode */' \
        "SET @@GLOBAL.GTID_PURGED=/*!80000 '+'*/ 'abc:1-5';" \
        'CREATE TABLE `t` (' \
        '  `a` varchar(10) COLLATE utf8mb4_0900_ai_ci DEFAULT NULL,' \
        '  `b` text COLLATE utf8mb4_uca1400_ai_ci,' \
        '  `c` text COLLATE utf8mb4_0900_bin,' \
        '  `d` text CHARACTER SET utf8mb3 COLLATE utf8mb3_general_ci' \
        ') ENGINE=Aria DEFAULT CHARSET=utf8mb3 TRANSACTIONAL=1 PAGE_CHECKSUM=1;' \
        '/*!50013 DEFINER=`root`@`localhost` SQL SECURITY DEFINER */' \
        "/*!50017 DEFINER='bob'@'%' */" \
        "SET sql_mode='NO_AUTO_CREATE_USER,STRICT_TRANS_TABLES';" \
        "SET sql_mode='STRICT_TRANS_TABLES,NO_AUTO_CREATE_USER';" \
        ') ENGINE=InnoDB DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_uca1400_ai_ci;' \
        '  `e` varchar(9) CHARACTER SET utf8mb3 COLLATE utf8mb3_uca1400_ai_ci NOT NULL,' \
        "INSERT INTO \`t\` VALUES ('utf8mb4_0900_ai_ci DEFINER=\`a\`@\`b\` ENGINE=Aria utf8mb3');" \
        "(1,'  \`x\` utf8mb4_0900_ai_ci');" \
        | sql_compat_filter)

    _chk "sandbox-mode line removed"          bash -c "! printf '%s' '$out' | grep -q 'sandbox'"
    _chk "GTID_PURGED statement removed"      bash -c "! printf '%s' '$out' | grep -q 'GTID_PURGED'"
    _chk "0900_ai_ci -> unicode_520_ci"       grep -q 'varchar(10) COLLATE utf8mb4_unicode_520_ci' <<< "$out"
    _chk "uca1400_ai_ci -> unicode_520_ci"    grep -q '`b` text COLLATE utf8mb4_unicode_520_ci' <<< "$out"
    _chk "0900_bin -> utf8mb4_bin"            grep -q 'COLLATE utf8mb4_bin' <<< "$out"
    _chk "utf8mb3 -> utf8 (charset + collation)" grep -q 'CHARACTER SET utf8 COLLATE utf8_general_ci' <<< "$out"
    _chk "table option CHARSET=utf8mb3 -> utf8" grep -q 'DEFAULT CHARSET=utf8;' <<< "$out"
    _chk "table COLLATE=utf8mb3_uca1400_ai_ci -> utf8_unicode_520_ci" grep -q 'DEFAULT CHARSET=utf8 COLLATE=utf8_unicode_520_ci;' <<< "$out"
    _chk "column utf8mb3_uca1400_ai_ci -> utf8_unicode_520_ci"        grep -q '`e` varchar(9) CHARACTER SET utf8 COLLATE utf8_unicode_520_ci' <<< "$out"
    _chk "no uca1400 collation survives the filter"                   bash -c "! printf '%s' '$out' | grep -q uca1400"
    _chk "ENGINE=Aria -> InnoDB"              grep -q 'ENGINE=InnoDB' <<< "$out"
    _chk "TRANSACTIONAL/PAGE_CHECKSUM removed" bash -c "! printf '%s' '$out' | grep -qE 'TRANSACTIONAL|PAGE_CHECKSUM'"
    _chk "DEFINER (backtick form) removed"    grep -q '^/\*!50013 SQL SECURITY DEFINER \*/' <<< "$out"
    _chk "DEFINER (quote form) removed"       grep -q "^/\*!50017 \*/" <<< "$out"
    _chk "NO_AUTO_CREATE_USER removed (first)" grep -q "sql_mode='STRICT_TRANS_TABLES';" <<< "$out"
    _chk "NO_AUTO_CREATE_USER removed (last)"  test "$(grep -c "NO_AUTO_CREATE_USER" <<< "$out")" = 0
    _chk "INSERT row data untouched"          grep -qF "INSERT INTO \`t\` VALUES ('utf8mb4_0900_ai_ci DEFINER=\`a\`@\`b\` ENGINE=Aria utf8mb3');" <<< "$out"
    _chk "continuation row data untouched"    grep -qF "(1,'  \`x\` utf8mb4_0900_ai_ci');" <<< "$out"

    local twice
    twice=$(printf '%s\n' "$out" | sql_compat_filter)
    _chk "filter is idempotent" test "$twice" = "$out"

    # Plain legacy dump passes through byte-for-byte
    local w; w=$(_hard_workdir)
    printf "DROP TABLE IF EXISTS \`wp_a\`;\nCREATE TABLE \`wp_a\` (\n  \`id\` int\n) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;\nINSERT INTO \`wp_a\` VALUES (1);\n" > "$w/ok.sql"
    _chk "already-compatible dump is unchanged" cmp -s <(sql_compat_filter < "$w/ok.sql") "$w/ok.sql"

    # Retry trigger classification
    printf 'ERROR 1273 (HY000) at line 20: Unknown collation: '"'"'utf8mb4_0900_ai_ci'"'"'\n' > "$w/e1.log"
    printf "ERROR 1064 (42000) at line 9: syntax error near 'sandbox mode'\n" > "$w/e2.log"
    printf 'ERROR 1449 (HY000): The user specified as a definer does not exist\n' > "$w/e3.log"
    printf 'ERROR 2002 (HY000): Cannot connect to local MySQL server through socket\n' > "$w/e4.log"
    printf 'ERROR 1045 (28000): Access denied for user\n' > "$w/e5.log"
    _chk "classifier: unknown collation -> retry"  import_error_is_compat_related "$w/e1.log"
    _chk "classifier: sandbox mode -> retry"       import_error_is_compat_related "$w/e2.log"
    _chk "classifier: missing definer -> retry"    import_error_is_compat_related "$w/e3.log"
    _chk "classifier: connection error -> no retry" bash -c "source '$_HARD_ROOT/lib/database/sql_source.sh' >/dev/null 2>&1; ! import_error_is_compat_related '$w/e4.log'"
    _chk "classifier: access denied -> no retry"   bash -c "source '$_HARD_ROOT/lib/database/sql_source.sh' >/dev/null 2>&1; ! import_error_is_compat_related '$w/e5.log'"
    _chk "classifier: missing log -> no retry"     bash -c "source '$_HARD_ROOT/lib/database/sql_source.sh' >/dev/null 2>&1; ! import_error_is_compat_related '$w/none.log'"
    _finish "compatibility filter is correct and safe"
}

# ================================================================
# 2+3. Importer streams (stub mysql)
# ================================================================
test_import_stream_via_stub() {
    start_test "Import Stream" "perform_db_import_via_socket streams gz + optimizations + filter to mysql"
    _hard_load
    local errors=0 w; w=$(_hard_workdir)
    _hard_make_mysql_stub "$w"
    export WPDB_MYSQL_BIN="$w/mysql" STUB_LOG="$w/stub.log" STUB_STDIN="$w/stdin.sql"
    printf "CREATE TABLE \`t\` (\n  \`a\` text COLLATE utf8mb4_0900_ai_ci\n) ENGINE=InnoDB;\nINSERT INTO \`t\` VALUES ('x');\n" > "$w/m.sql"
    gzip -c "$w/m.sql" > "$w/m.sql.gz"

    : > "$STUB_LOG"
    perform_db_import_via_socket "$w/m.sql.gz" "$w/imp.log" "" "db.example:3307" "u" "s3cret" "wpdb" "true" "false" >/dev/null
    _chk "import returns success"                  test $? -eq 0
    _chk "gz content is decompressed"              grep -q 'INSERT INTO `t` VALUES' "$STUB_STDIN"
    _chk "session optimizations wrap the stream"   bash -c "head -3 '$STUB_STDIN' | grep -q 'SET AUTOCOMMIT = 0' && tail -4 '$STUB_STDIN' | grep -q 'SET AUTOCOMMIT = 1'"
    _chk "original collation kept without filter"  grep -q 'utf8mb4_0900_ai_ci' "$STUB_STDIN"
    _chk "TCP host and port passed"                grep -q '\[--host=db.example\] \[--port=3307\]' "$STUB_LOG"
    _chk "password not on the command line"        bash -c "! grep -q 's3cret' '$STUB_LOG'"
    _chk "password passed through MYSQL_PWD"       grep -q 'PWDSET=yes' "$STUB_LOG"

    perform_db_import_via_socket "$w/m.sql.gz" "$w/imp.log" "" "localhost" "u" "p" "wpdb" "false" "true" >/dev/null
    _chk "compat filter applied when requested"    grep -q 'utf8mb4_unicode_520_ci' "$STUB_STDIN"
    _chk "no optimizations when disabled"          bash -c "! grep -q 'AUTOCOMMIT' '$STUB_STDIN'"

    STUB_FAIL_IMPORT=1 perform_db_import_via_socket "$w/m.sql" "$w/imp.log" "" "localhost" "u" "p" "wpdb" "false" "false" >/dev/null
    _chk "failed import returns non-zero"          test $? -ne 0
    _chk "failure log is classified as compat error" import_error_is_compat_related "$w/imp.log"
    unset WPDB_MYSQL_BIN STUB_LOG STUB_STDIN
    _finish "importer streams SQL correctly"
}

# ================================================================
# 6 + 7. Benchmark: scratch database and no-INSERT fallback
# ================================================================
test_benchmark_scratch_db() {
    start_test "Benchmark Safety" "benchmark uses a scratch DB, drops it, and falls back when unsafe"
    _hard_load
    local errors=0 w; w=$(_hard_workdir)
    _hard_make_mysql_stub "$w"
    export WPDB_MYSQL_BIN="$w/mysql" STUB_LOG="$w/bench.log" STUB_STDIN="$w/bench_sample.sql"

    # 110 MB dump with many short INSERT lines
    local big="$w/big.sql"
    { echo 'CREATE TABLE t (id int, v text);'; yes "INSERT INTO t VALUES (1,'xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx');" | head -c 110000000; } > "$big"

    : > "$STUB_LOG"
    local est
    est=$(estimate_import_duration "$big" "" "localhost" "u" "p" "realdb" "auto")
    _chk "estimate has three numeric minutes"      bash -c "[[ '$est' =~ ^[0-9]+\ [0-9]+\ [0-9]+\$ ]]"
    _chk "scratch database is created"             grep -q 'CREATE DATABASE `wpdb_bench_' "$STUB_LOG"
    _chk "sample is imported into the scratch DB"  grep -q '\[--database=wpdb_bench_' "$STUB_LOG"
    _chk "scratch database is dropped"             grep -q 'DROP DATABASE IF EXISTS `wpdb_bench_' "$STUB_LOG"
    _chk "real database is never used"             bash -c "! grep -q 'realdb' '$STUB_LOG'"
    _chk "sample ends on a complete statement"     bash -c "tail -c 3 '$STUB_STDIN' | grep -q ';'"

    # Account cannot create databases: no import, size-based estimate
    : > "$STUB_LOG"
    est=$(STUB_FAIL_CREATE=1 estimate_import_duration "$big" "" "localhost" "u" "p" "realdb" "auto")
    local expect; expect=$(estimate_heuristic $((110000000 / 1048576)))
    _chk "CREATE DATABASE denied -> heuristic estimate" test "$est" = "$expect"
    _chk "no sample import attempted"              bash -c "! grep -q -- '--database=' '$STUB_LOG'"

    # Huge single INSERT line: sample would hold only schema -> heuristic, no mysql call
    local huge="$w/huge.sql"
    { echo 'CREATE TABLE t (id int, v longtext);'; printf "INSERT INTO t VALUES (1,'"; head -c 110000000 /dev/zero | tr '\0' 'x'; printf "');\n"; } > "$huge"
    : > "$STUB_LOG"
    est=$(estimate_import_duration "$huge" "" "localhost" "u" "p" "realdb" "auto")
    _chk "sample without INSERT rows -> heuristic" test "$est" = "$(estimate_heuristic $((110000000 / 1048576)))"
    _chk "no mysql call when sample is unusable"   test ! -s "$STUB_LOG"

    # Small file and compressed file paths
    echo "CREATE TABLE a (i int);" > "$w/s.sql"
    _chk "small file -> heuristic (min 1m)"        test "$(estimate_import_duration "$w/s.sql" "" "h" "u" "p" "d" "auto")" = "1 1 2"
    local h; h=$(estimate_heuristic 300)
    _chk "heuristic: 300 MB -> 10 20 40 style, ordered" bash -c "read a b c <<< '$h'; [[ \$a -le \$b && \$b -le \$c && \$a -ge 1 ]]"
    _chk "heuristic never returns 0"               test "$(estimate_heuristic 0)" = "1 1 2"

    gzip -c "$big" > "$w/big.sql.gz"
    : > "$STUB_LOG"
    est=$(estimate_import_duration "$w/big.sql.gz" "" "localhost" "u" "p" "realdb" "auto")
    _chk "compressed dump uses uncompressed size for benchmark" grep -q 'CREATE DATABASE `wpdb_bench_' "$STUB_LOG"
    rm -f "$big" "$huge" "$w/big.sql.gz"
    unset WPDB_MYSQL_BIN STUB_LOG STUB_STDIN
    _finish "benchmark is safe and falls back correctly"
}

# ================================================================
# 1. Pre-import backup
# ================================================================
test_backup_before_import() {
    start_test "Pre-Import Backup" "backup is written (mode 600), skippable, and cancels the import on failure"
    _hard_load
    local errors=0 w; w=$(_hard_workdir)
    local home="$w/home"; mkdir -p "$home"
    local old_home="$HOME"; export HOME="$home"
    export CONFIG_AUTO_PROCEED=true     # unattended: "ask" backs up without prompting

    # Stubs for WP-CLI
    STUB_TABLES="wp_posts"; STUB_EXPORT_RC=0; STUB_EXPORT_ARGS="$w/export.args"; : > "$STUB_EXPORT_ARGS"
    execute_wp_cli() {
        case "$1 $2" in
            "db tables") [[ -n "$STUB_TABLES" ]] && printf "%s\n" "$STUB_TABLES"; return 0 ;;
            "db export")
                printf '%s\n' "$*" >> "$STUB_EXPORT_ARGS"
                case " $* " in *" --add-drop-table "*) printf -- "DROP TABLE IF EXISTS wp_posts;\n" ;; esac
                printf -- "-- dump\nCREATE TABLE wp_posts (id int);\n"; return "$STUB_EXPORT_RC" ;;
        esac
        return 0
    }
    get_wp_db_credentials() { WP_DB_NAME="my db/name"; export WP_DB_NAME; return 0; }

    # Disabled
    CONFIG_BACKUP_BEFORE_IMPORT=false backup_database_before_import "$w" >/dev/null </dev/null
    _chk "disabled: returns success"               test $? -eq 0
    _chk "disabled: nothing written"               test ! -d "$home/.wp-db-import"

    # Empty database
    STUB_TABLES="" backup_database_before_import "$w" >/dev/null
    _chk "empty database: returns success, no file" bash -c "test ! -d '$home/.wp-db-import/backups' || test -z \"\$(ls '$home/.wp-db-import/backups')\""

    # Success path (default directory)
    CONFIG_BACKUP_BEFORE_IMPORT="" backup_database_before_import "$w" >/dev/null </dev/null
    local rc=$? f
    f=$(ls "$home/.wp-db-import/backups"/*.sql.gz 2>/dev/null | head -1)
    _chk "success: returns 0"                      test "$rc" -eq 0
    _chk "backup file exists and is gzip-valid"    bash -c "gzip -t '$f'"
    _chk "file name has sanitized db name"         bash -c "[[ '$f' == */my_db_name-*.sql.gz ]]"
    _chk "backup content is the SQL dump"          bash -c "gunzip -c '$f' | grep -q 'CREATE TABLE wp_posts'"
    _chk "export is called with --add-drop-table"  grep -q -- '--add-drop-table' "$STUB_EXPORT_ARGS"
    _chk "export writes to stdout ('-')"           grep -q 'db export - ' "$STUB_EXPORT_ARGS"
    _chk "backup contains DROP TABLE IF EXISTS"    bash -c "gunzip -c '$f' | grep -q 'DROP TABLE IF EXISTS wp_posts'"
    _chk "file mode is 600"                        test "$(_file_mode "$f")" = "600"
    _chk "default directory mode is 700"           test "$(_file_mode "$home/.wp-db-import/backups")" = "700"

    # Custom directory with ~ expansion
    CONFIG_BACKUP_DIR="~/custom-bk" backup_database_before_import "$w" >/dev/null
    _chk "custom backup_dir (with ~) is used"      bash -c "ls '$home/custom-bk'/*.sql.gz >/dev/null 2>&1"

    # Export failure: import must be cancelled and no partial file left
    local before; before=$(ls "$home/.wp-db-import/backups" | wc -l | tr -d ' ')
    STUB_EXPORT_RC=1 backup_database_before_import "$w" >/dev/null
    _chk "export failure returns non-zero"         test $? -ne 0
    _chk "no partial backup left behind"           test "$(ls "$home/.wp-db-import/backups" | wc -l | tr -d ' ')" = "$before"
    _chk "failed backup never deletes an earlier one" test -f "$f"
    local f2
    CONFIG_BACKUP_BEFORE_IMPORT="" backup_database_before_import "$w" >/dev/null
    CONFIG_BACKUP_BEFORE_IMPORT="" backup_database_before_import "$w" >/dev/null
    _chk "same-second backups get unique names"    test "$(ls "$home/.wp-db-import/backups"/*.sql.gz | wc -l | tr -d ' ')" -ge $((before + 2))

    # Unwritable directory
    CONFIG_BACKUP_DIR="/dev/null/nope" backup_database_before_import "$w" >/dev/null
    _chk "unwritable backup_dir returns non-zero"  test $? -ne 0

    unset -f execute_wp_cli get_wp_db_credentials
    unset CONFIG_AUTO_PROCEED
    export HOME="$old_home"
    _finish "backup behaves correctly"
}

# ================================================================
# Fixtures must be tracked (a *.sql ignore rule once hid them)
# ================================================================
test_fixtures_tracked() {
    start_test "SQL Fixtures" "matrix fixtures exist and are not git-ignored"
    local errors=0 f
    for f in dump_legacy.sql dump_mariadb11.sql dump_mysql8.sql; do
        _chk "fixture exists: $f"                     test -s "$_HARD_ROOT/lib/tests/fixtures/$f"
        if command -v git >/dev/null 2>&1 && git -C "$_HARD_ROOT" rev-parse --git-dir >/dev/null 2>&1; then
            _chk "fixture is not git-ignored: $f"     bash -c "! git -C '$_HARD_ROOT' check-ignore -q 'lib/tests/fixtures/$f'"
        fi
    done
    _finish "fixtures are available to every contributor"
}

# ================================================================
# 5. Temp files are removed after a run (no log growth)
# ================================================================
test_temp_cleanup() {
    start_test "Temp Cleanup" "logs and the private temp directory are removed on success and on failure paths"
    _hard_load
    source "$_HARD_ROOT/lib/core/cleanup.sh" >/dev/null 2>&1
    local errors=0 w; w=$(_hard_workdir)
    local base="$w/cleanbase"; mkdir -p "$base"

    # cleanup() removes the private directory with everything in it
    ( export TMPDIR="$base"
      d=$(secure_tmpdir); echo log > "$d/db_import.log"; echo s > "$d/compat.sed"; mkdir "$d/sub"; echo x > "$d/sub/f"
      DB_LOG="$d/db_import.log" cleanup
      test ! -e "$d" )
    _chk "cleanup() removes the private temp directory" test $? -eq 0
    _chk "nothing is left in the temp base"           test -z "$(ls -A "$base")"

    # The success path must CALL cleanup before clearing the trap (a bare 'trap - EXIT' leaks files)
    local tail_block
    tail_block=$(awk '/Remove the temporary logs and private temp directory now/{f=1} f{print} /^}/{if(f)exit}' "$_HARD_ROOT/import_wp_db.sh")
    _chk "success path calls cleanup"                 grep -qE '^[[:space:]]+cleanup$' <<< "$tail_block"
    _chk "cleanup runs before the trap is cleared"    bash -c "[[ \$(printf '%s' '$tail_block' | grep -n '^ *cleanup\$' | cut -d: -f1) -lt \$(printf '%s' '$tail_block' | grep -n 'trap - EXIT' | cut -d: -f1) ]]"
    _chk "exit trap is registered at start of import" grep -q '^  trap cleanup EXIT' "$_HARD_ROOT/import_wp_db.sh"

    # Real exit path: a script that sets the trap and exits leaves nothing behind
    cat > "$w/exit_test.sh" <<EOF
source "$_HARD_ROOT/lib/core/utils.sh" >/dev/null 2>&1
source "$_HARD_ROOT/lib/core/cleanup.sh" >/dev/null 2>&1
export TMPDIR="$base"
trap cleanup EXIT
d=\$(secure_tmpdir); echo data > "\$d/x.log"
exit 0
EOF
    bash "$w/exit_test.sh"
    _chk "EXIT trap removes the directory when the script ends" test -z "$(ls -A "$base")"
    _finish "temporary files do not accumulate"
}

# ================================================================
# 1. Backup rotation (log/backup growth)
# ================================================================
test_backup_rotation() {
    start_test "Backup Rotation" "only the newest N backups per database are kept; nothing else is touched"
    _hard_load
    local errors=0 w; w=$(_hard_workdir)
    local d="$w/rot"; mkdir -p "$d"
    local i
    # 8 backups of "wp" with increasing mtimes, plus bystanders
    for i in 1 2 3 4 5 6 7 8; do
        : > "$d/wp-2026010${i}-000000.sql.gz"; touch -t "2026010${i}0000" "$d/wp-2026010${i}-000000.sql.gz"
    done
    : > "$d/other-20260101-000000.sql.gz"; touch -t 202601010000 "$d/other-20260101-000000.sql.gz"
    : > "$d/wp-notes.txt"; : > "$d/wp-latest.sql.gz"; : > "$d/wpx-20260101-000000.sql.gz"
    local cur="$d/wp-20260108-000000.sql.gz"

    local removed
    removed=$(prune_old_backups "$d" wp 3 "$cur")
    _chk "keep=3 removes 5 of 8 backups"            test "$removed" = 5
    _chk "newest 3 remain"                          bash -c "ls '$d'/wp-2026010[678]-000000.sql.gz >/dev/null 2>&1 && test \$(ls '$d'/wp-2026010?-000000.sql.gz | wc -l) -eq 3"
    _chk "other database's backup untouched"        test -f "$d/other-20260101-000000.sql.gz"
    _chk "non-backup names untouched"               bash -c "test -f '$d/wp-notes.txt' && test -f '$d/wp-latest.sql.gz' && test -f '$d/wpx-20260101-000000.sql.gz'"

    # keep=0 keeps everything
    for i in 1 2 3; do : > "$d/wp-2025010${i}-000000.sql.gz"; done
    removed=$(prune_old_backups "$d" wp 0 "$cur")
    _chk "keep=0 keeps all backups"                 test "$removed" = 0 -a -f "$d/wp-20250101-000000.sql.gz"

    # invalid value falls back to the default (5) and never deletes the current backup
    removed=$(prune_old_backups "$d" wp "abc" "$d/wp-20250101-000000.sql.gz")
    _chk "invalid keep falls back to 5"             test "$(ls "$d"/wp-2*-??????.sql.gz | wc -l | tr -d ' ')" = 5
    _chk "current backup is never deleted"          test -f "$d/wp-20250101-000000.sql.gz"
    removed=$(prune_old_backups "$d" wp 1 "$d/wp-20250101-000000.sql.gz")
    _chk "keep=1 still keeps the current one"       test -f "$d/wp-20250101-000000.sql.gz"

    # Stale .partial files are removed, fresh ones kept
    : > "$d/wp-20260101-000000.sql.gz.partial"; touch -t 202001010000 "$d/wp-20260101-000000.sql.gz.partial"
    : > "$d/wp-20990101-000000.sql.gz.partial"
    prune_old_backups "$d" wp 5 "$cur" >/dev/null
    _chk "stale .partial removed"                   test ! -e "$d/wp-20260101-000000.sql.gz.partial"
    _chk "fresh .partial kept"                      test -e "$d/wp-20990101-000000.sql.gz.partial"

    # Hostile directory name with sed/regex metacharacters
    local hd="$w/we|ird&dir [x]"; mkdir -p "$hd"
    for i in 1 2 3 4; do : > "$hd/wp-2026010${i}-000000.sql.gz"; touch -t "2026010${i}0000" "$hd/wp-2026010${i}-000000.sql.gz"; done
    removed=$(prune_old_backups "$hd" wp 2 "$hd/wp-20260104-000000.sql.gz")
    _chk "directory with | & [ ] handled safely"    test "$removed" = 2

    # End to end: backup_keep from the config is applied by the backup function
    local home="$w/home3"; mkdir -p "$home"; local old_home="$HOME"; export HOME="$home"
    execute_wp_cli() { case "$1 $2" in "db tables") echo t;; "db export") echo x;; esac; return 0; }
    get_wp_db_credentials() { WP_DB_NAME="wp"; export WP_DB_NAME; return 0; }
    local bk="$home/rot"; mkdir -p "$bk"
    for i in 1 2 3 4; do : > "$bk/wp-2020010${i}-000000.sql.gz"; touch -t "2020010${i}0000" "$bk/wp-2020010${i}-000000.sql.gz"; done
    CONFIG_AUTO_PROCEED=true CONFIG_BACKUP_BEFORE_IMPORT=true CONFIG_BACKUP_DIR="$bk" CONFIG_BACKUP_KEEP=2 backup_database_before_import "$w" >/dev/null 2>&1 </dev/null
    _chk "backup run with backup_keep=2 leaves 2 files" test "$(ls "$bk"/*.sql.gz | wc -l | tr -d ' ')" = 2
    unset -f execute_wp_cli get_wp_db_credentials
    export HOME="$old_home"
    _finish "backups are rotated safely"
}

# ================================================================
# Import logs: error scan, size cap, no false success
# ================================================================
test_import_log_handling() {
    start_test "Import Log Handling" "errors in the log fail an import even if exit code is 0; logs are size-capped"
    _hard_load
    local errors=0 w; w=$(_hard_workdir)

    printf 'ERROR 1273 (HY000) at line 26: Unknown collation\n' > "$w/e.log"
    printf 'Success: Imported\n' > "$w/ok.log"
    printf 'some text ERROR 5 mid-line\n' > "$w/mid.log"
    _chk "ERROR line is detected"                   import_log_has_errors "$w/e.log"
    _chk "clean log is not an error"                bash -c "source '$_HARD_ROOT/lib/database/sql_source.sh' >/dev/null 2>&1; ! import_log_has_errors '$w/ok.log'"
    _chk "ERROR must start the line (no false hit)" bash -c "source '$_HARD_ROOT/lib/database/sql_source.sh' >/dev/null 2>&1; ! import_log_has_errors '$w/mid.log'"
    _chk "missing log is not an error"              bash -c "source '$_HARD_ROOT/lib/database/sql_source.sh' >/dev/null 2>&1; ! import_log_has_errors '$w/none.log'"

    # A client that exits 0 although it printed errors must not count as success
    cat > "$w/liar-wp" <<'EOF'
#!/usr/bin/env bash
cat > /dev/null
echo "ERROR 1273 (HY000) at line 26: Unknown collation: 'utf8mb4_uca1400_ai_ci'"
exit 0
EOF
    chmod +x "$w/liar-wp"
    printf "SELECT 1;\n" > "$w/x.sql"
    perform_db_import_via_wpcli "$w/x.sql" "$w/liar.log" false "$w/liar-wp"
    _chk "exit-0-with-errors is treated as failure (plain)"  test $? -ne 0
    perform_db_import_via_wpcli "$w/x.sql" "$w/liar.log" true "$w/liar-wp"
    _chk "exit-0-with-errors is treated as failure (stream)" test $? -ne 0

    # The socket importer too (stub mysql that prints errors but exits 0)
    cat > "$w/mysql" <<'EOF'
#!/usr/bin/env bash
cat > /dev/null
echo "ERROR 1146 (42S02) at line 3: Table 'x' doesn't exist"
exit 0
EOF
    chmod +x "$w/mysql"
    WPDB_MYSQL_BIN="$w/mysql" perform_db_import_via_socket "$w/x.sql" "$w/s.log" "" "h" "u" "p" "d" "false" "false" >/dev/null 2>&1
    _chk "socket import: exit-0-with-errors is a failure" test $? -ne 0

    # Size cap keeps head and tail, adds a marker, and leaves small logs alone
    { printf 'HEAD-LINE\n'; head -c 3000000 /dev/zero | tr '\0' 'x'; printf '\nTAIL-LINE\n'; } > "$w/big.log"
    cap_log_file "$w/big.log" 100000
    _chk "log is capped near the limit"             test "$(_sql_file_size_bytes "$w/big.log")" -lt 101000
    _chk "head of the log is kept"                  grep -q 'HEAD-LINE' "$w/big.log"
    _chk "tail of the log is kept"                  grep -q 'TAIL-LINE' "$w/big.log"
    _chk "truncation marker is present"             grep -q 'log truncated' "$w/big.log"
    printf 'small\n' > "$w/small.log"; cap_log_file "$w/small.log" 100000
    _chk "small log is unchanged"                   test "$(cat "$w/small.log")" = small
    _chk "capping a missing file is harmless"       cap_log_file "$w/none.log"
    _chk "no .cap temp file left behind"            test ! -e "$w/big.log.cap"

    # Failed import prints the cause (the log itself is deleted at exit)
    _chk "failure path prints error lines"          grep -q "grep -E '^(ERROR|Error)'" "$_HARD_ROOT/lib/database/db_import.sh"
    _finish "import logs are trustworthy and bounded"
}

# ================================================================
# 1. Backup preference prompt (ask / true / false)
# ================================================================
test_backup_preference_prompt() {
    start_test "Backup Preference" "ask prompts (default Yes); 'n' is saved as backup_before_import=false"
    _hard_load
    source "$_HARD_ROOT/lib/config/config_manager.sh" >/dev/null 2>&1
    local errors=0 w; w=$(_hard_workdir)
    local home="$w/home2"; mkdir -p "$home"
    local old_home="$HOME"; export HOME="$home"
    execute_wp_cli() {
        case "$1 $2" in
            "db tables") echo wp_posts ;;
            "db export") printf -- "-- dump\n" ;;
        esac
        return 0
    }
    get_wp_db_credentials() { WP_DB_NAME="wp"; export WP_DB_NAME; return 0; }
    export CONFIG_BACKUP_KEEP=0      # keep all: this test counts backups
    local bk="$home/.wp-db-import/backups" cfg="$w/pref.conf"
    _count() { ls "$bk"/*.sql.gz 2>/dev/null | wc -l | tr -d ' '; }
    _fresh_cfg() { printf '[general]\nsql_file=a.sql\nbackup_before_import=ask\n[site_mappings]\n' > "$cfg"; }

    # Answer "n" -> no backup, preference persisted, import allowed to continue
    _fresh_cfg
    CONFIG_AUTO_PROCEED="" CONFIG_BACKUP_BEFORE_IMPORT=ask backup_database_before_import "$w" "$cfg" >/dev/null <<< "n"
    _chk "answer n: returns 0 (import may continue)"  test $? -eq 0
    _chk "answer n: no backup written"                test "$(_count)" = 0
    _chk "answer n: config now has backup_before_import=false" grep -q '^backup_before_import=false' "$cfg"
    _chk "answer n: only that key changed"            test "$(grep -c '^backup_before_import' "$cfg")" = 1

    # Saved false is honored on the next run without prompting
    CONFIG_AUTO_PROCEED="" CONFIG_BACKUP_BEFORE_IMPORT=false backup_database_before_import "$w" "$cfg" >/dev/null </dev/null
    _chk "saved false: still no backup, no prompt"    test "$(_count)" = 0

    # Uppercase N, and "no"
    _fresh_cfg
    CONFIG_AUTO_PROCEED="" CONFIG_BACKUP_BEFORE_IMPORT=ask backup_database_before_import "$w" "$cfg" >/dev/null <<< "N"
    _chk "answer N (uppercase) is a refusal"          grep -q '^backup_before_import=false' "$cfg"
    _fresh_cfg
    CONFIG_AUTO_PROCEED="" CONFIG_BACKUP_BEFORE_IMPORT=ask backup_database_before_import "$w" "$cfg" >/dev/null <<< "no"
    _chk "answer 'no' is a refusal"                   grep -q '^backup_before_import=false' "$cfg"

    # Yes, Enter and EOF all back up and leave the config as ask
    local ans
    for ans in "y" "Y" "yes" ""; do
        _fresh_cfg
        CONFIG_AUTO_PROCEED="" CONFIG_BACKUP_BEFORE_IMPORT=ask backup_database_before_import "$w" "$cfg" >/dev/null <<< "$ans"
        _chk "answer '${ans:-<Enter>}': backup is made" test "$(_count)" -ge 1
        _chk "answer '${ans:-<Enter>}': config stays ask" grep -q '^backup_before_import=ask' "$cfg"
    done
    local before; before=$(_count)
    _fresh_cfg
    CONFIG_AUTO_PROCEED="" CONFIG_BACKUP_BEFORE_IMPORT=ask backup_database_before_import "$w" "$cfg" >/dev/null </dev/null
    _chk "closed stdin (EOF): defaults to Yes, backs up" test "$(_count)" -gt "$before"

    # Unattended mode must not depend on other modules and must never read stdin (no hang)
    before=$(_count)
    cat > "$w/standalone.sh" <<EOF
source '$_HARD_ROOT/lib/core/utils.sh' >/dev/null 2>&1
source '$_HARD_ROOT/lib/database/sql_source.sh' >/dev/null 2>&1
source '$_HARD_ROOT/lib/database/db_backup.sh' >/dev/null 2>&1
unset -f is_config_true
execute_wp_cli() { case "\$1 \$2" in 'db tables') echo t;; 'db export') echo x;; esac; return 0; }
backup_database_before_import '$w'
EOF
    # stdin stays open (a pipe that never ends) so a stray prompt would hang; a watchdog kills it after 10s
    TMPDIR="$w" CONFIG_AUTO_PROCEED=TRUE CONFIG_BACKUP_BEFORE_IMPORT=ask bash "$w/standalone.sh" >/dev/null 2>&1 < <(sleep 12) &
    local sa_pid=$!
    ( sleep 10; kill "$sa_pid" 2>/dev/null ) &
    local wd_pid=$!
    wait "$sa_pid" 2>/dev/null
    kill "$wd_pid" 2>/dev/null; wait "$wd_pid" 2>/dev/null
    _chk "auto_proceed works standalone and never waits on stdin" test "$(_count)" -gt "$before"

    # Unattended and explicit modes never prompt
    before=$(_count)
    CONFIG_AUTO_PROCEED=true CONFIG_BACKUP_BEFORE_IMPORT=ask backup_database_before_import "$w" "$cfg" >/dev/null </dev/null
    _chk "auto_proceed + ask: backs up without prompting" test "$(_count)" -gt "$before"
    before=$(_count)
    CONFIG_AUTO_PROCEED="" CONFIG_BACKUP_BEFORE_IMPORT=true backup_database_before_import "$w" "$cfg" >/dev/null <<< "n"
    _chk "true ignores a 'n' and always backs up"     test "$(_count)" -gt "$before"
    before=$(_count)
    CONFIG_AUTO_PROCEED="" CONFIG_BACKUP_BEFORE_IMPORT="garbage" backup_database_before_import "$w" "$cfg" >/dev/null <<< "n"
    _chk "unknown value fails safe: backs up"         test "$(_count)" -gt "$before"

    # Refusal with no config file: still continues, nothing written anywhere
    CONFIG_AUTO_PROCEED="" CONFIG_BACKUP_BEFORE_IMPORT=ask backup_database_before_import "$w" "$w/missing.conf" >/dev/null <<< "n"
    _chk "refusal without a config file returns 0"    test $? -eq 0
    _chk "no config file is created by a refusal"     test ! -e "$w/missing.conf"

    unset CONFIG_BACKUP_KEEP
    unset -f execute_wp_cli get_wp_db_credentials _count _fresh_cfg
    export HOME="$old_home"
    _finish "backup preference works"
}

# ================================================================
# 1. Backup config keys
# ================================================================
test_backup_config_keys() {
    start_test "Backup Config Keys" "new keys exist in templates, defaults load, old configs migrate"
    _hard_load
    source "$_HARD_ROOT/lib/config/config_manager.sh" >/dev/null 2>&1
    source "$_HARD_ROOT/lib/config/config_reader.sh" >/dev/null 2>&1
    source "$_HARD_ROOT/lib/config/integration.sh" >/dev/null 2>&1
    local errors=0 w; w=$(_hard_workdir)
    local f
    for f in wpdb-import-example-single.conf wpdb-import-example-multisite.conf; do
        _chk "$f has backup_before_import=ask" grep -q '^backup_before_import=ask' "$_HARD_ROOT/$f"
        _chk "$f has backup_dir="               grep -q '^backup_dir=' "$_HARD_ROOT/$f"
        _chk "$f has backup_keep=5"             grep -q '^backup_keep=5' "$_HARD_ROOT/$f"
    done
    _chk "config template has the keys"     bash -c "grep -c '^backup_before_import=ask\|^backup_dir=' '$_HARD_ROOT/lib/config/config_manager.sh' | grep -q 2"

    # Old config (no new keys) migrates, and migration is idempotent
    printf '[general]\nsql_file=a.sql\nold_domain=a.com\nnew_domain=a.test\n[site_mappings]\n' > "$w/old.conf"
    ensure_socket_config_settings "$w/old.conf" >/dev/null 2>&1
    _chk "migration adds backup_before_import=ask" grep -q '^backup_before_import=ask' "$w/old.conf"
    _chk "migration adds backup_dir"           grep -q '^backup_dir=' "$w/old.conf"
    _chk "migration adds backup_keep=5"        grep -q '^backup_keep=5' "$w/old.conf"
    _chk "migration still adds socket keys"    grep -q '^use_socket=auto' "$w/old.conf"
    local sum1; sum1=$(md5 -q "$w/old.conf" 2>/dev/null || md5sum "$w/old.conf" | cut -d' ' -f1)
    ensure_socket_config_settings "$w/old.conf" >/dev/null 2>&1
    local sum2; sum2=$(md5 -q "$w/old.conf" 2>/dev/null || md5sum "$w/old.conf" | cut -d' ' -f1)
    _chk "migration is idempotent"             test "$sum1" = "$sum2"

    # Loading: defaults and explicit values
    printf '[general]\nsql_file=a.sql\n[site_mappings]\n' > "$w/min.conf"
    load_import_config "$w/min.conf" >/dev/null 2>&1
    _chk "default: backup_before_import is ask" test "$CONFIG_BACKUP_BEFORE_IMPORT" = ask
    printf '[general]\nsql_file=a.sql\nbackup_before_import=false\nbackup_dir=/x/y\n[site_mappings]\n' > "$w/set.conf"
    load_import_config "$w/set.conf" >/dev/null 2>&1
    _chk "explicit false is honored"           test "$CONFIG_BACKUP_BEFORE_IMPORT" = false
    _chk "backup_dir is loaded"                test "$CONFIG_BACKUP_DIR" = /x/y
    _chk "default: backup_keep is 5"           test "$CONFIG_BACKUP_KEEP" = 5
    printf '[general]\nsql_file=a.sql\nbackup_keep=9\n[site_mappings]\n' > "$w/keep.conf"
    load_import_config "$w/keep.conf" >/dev/null 2>&1
    _chk "explicit backup_keep is loaded"      test "$CONFIG_BACKUP_KEEP" = 9
    _finish "backup config keys work"
}

# ================================================================
# 4. Stage File Proxy checksum
# ================================================================
test_sfp_checksum() {
    start_test "Stage File Proxy Checksum" "download is installed only if SHA-256 matches the pinned value"
    _hard_load
    local errors=0 w; w=$(_hard_workdir)
    printf 'abc' > "$w/abc.txt"
    _chk "sha256_of_file known vector"        test "$(sha256_of_file "$w/abc.txt")" = "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"

    printf 'plugin-zip-bytes' > "$w/src.zip"
    local good; good=$(sha256_of_file "$w/src.zip")

    SFP_RELEASE_URL="file://$w/src.zip" SFP_RELEASE_SHA256="$good" download_verified_stage_file_proxy_zip "$w/out.zip" "$w/dl.log"
    _chk "matching checksum is accepted"      test $? -eq 0
    _chk "file is kept when verified"         test -f "$w/out.zip"

    rm -f "$w/out.zip"
    SFP_RELEASE_URL="file://$w/src.zip" SFP_RELEASE_SHA256="0000000000000000000000000000000000000000000000000000000000000000" download_verified_stage_file_proxy_zip "$w/out.zip" "$w/dl.log" >/dev/null
    _chk "wrong checksum is rejected"         test $? -ne 0
    _chk "rejected file is deleted"           test ! -e "$w/out.zip"

    SFP_RELEASE_URL="file://$w/does-not-exist.zip" download_verified_stage_file_proxy_zip "$w/out2.zip" "$w/dl.log" >/dev/null
    _chk "download failure is rejected"       test $? -ne 0

    _chk "release URL points at the project's own GitHub release" grep -q 'github.com/manishsongirkar/stage-file-proxy/releases/download/' "$_HARD_ROOT/lib/utilities/stage_file_proxy.sh"
    _chk "pinned checksum is a 64-char hex"  bash -c "[[ '$SFP_RELEASE_SHA256' =~ ^[0-9a-f]{64}\$ ]]"
    _chk "installers never use the unverified URL directly" bash -c "! grep -nE 'wp plugin install https?://' '$_HARD_ROOT/lib/utilities/stage_file_proxy.sh'"
    _finish "Stage File Proxy download is verified"
}

# ================================================================
# Run all
# ================================================================
run_import_hardening_tests() {
    printf "\n${CYAN}${BOLD}🛡️  Import Hardening Tests${RESET}\n"
    printf "%s\n\n" "$(printf '=%.0s' {1..50})"

    init_test_session "import_hardening"
    _HARD_WORK=$(mktemp -d "${TMPDIR:-/tmp}/wpdb-hardening-test.XXXXXX")
    trap 'secure_tmpdir_cleanup 2>/dev/null; rm -rf "$_HARD_WORK"' EXIT

    test_secure_tmpdir
    test_compressed_dumps
    test_compat_filter
    test_import_stream_via_stub
    test_benchmark_scratch_db
    test_backup_before_import
    test_fixtures_tracked
    test_temp_cleanup
    test_backup_rotation
    test_import_log_handling
    test_backup_preference_prompt
    test_backup_config_keys
    test_sfp_checksum

    [[ -n "$_HARD_WORK" ]] && rm -rf "$_HARD_WORK"
    finalize_test_session
    return $?
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    run_import_hardening_tests
fi
