#!/usr/bin/env bash

# ================================================================
# Real Dry Run - Tests
# ================================================================
#
# Description:
#   Tests for issue #20. A stub mysql client answers each kind of query and records every
#   call, so the whole preview logic is checked without a server: the scratch database is the
#   only database ever written, it is always dropped, database-switching statements are
#   removed from the stream, a missing CREATE privilege or client is explained, a dump that
#   needs the compatibility filter is reported, and the real database is never named.
#   (lib/tests/integration/test_real_import.sh checks the same on a real server.)
#
# Usage:
#   ./lib/tests/unit/test_dry_run.sh
#
# ================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../test_framework.sh"

_D_ROOT="$PROJECT_ROOT_DIR"
_D_WORK=""

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

_d_load() {
    source "$_D_ROOT/lib/core/utils.sh" >/dev/null 2>&1
    source "$_D_ROOT/lib/config/config_manager.sh" >/dev/null 2>&1
    source "$_D_ROOT/lib/database/sql_source.sh" >/dev/null 2>&1
    source "$_D_ROOT/lib/database/db_import.sh" >/dev/null 2>&1
    source "$_D_ROOT/lib/database/db_dry_run.sh" >/dev/null 2>&1
}

# A stub mysql that answers by query text. Controls (environment):
#   STUB_CREATE_RC=1        CREATE DATABASE fails (no privilege)
#   STUB_IMPORT=ok|compat|fail   behavior of the dump import (compat: first import rejected, second works)
_d_make_stub() {
    local dir="$1"
    cat > "$dir/mysql" <<'EOF'
#!/usr/bin/env bash
sql=""; db=""
args=("$@")
for ((i=0; i<${#args[@]}; i++)); do
    case "${args[$i]}" in
        -e) sql="${args[$((i+1))]}" ;;
        --database=*) db="${args[$i]#--database=}" ;;
    esac
done
printf 'CALL db=[%s] sql=[%s] pwd=[%s]\n' "$db" "$sql" "${MYSQL_PWD-}" >> "$STUB_LOG"
if [[ -z "$sql" ]]; then                       # an import: SQL arrives on stdin
    n=$(grep -c '^IMPORT ' "$STUB_LOG" 2>/dev/null); n=$((n + 1))
    printf 'IMPORT %s db=[%s]\n' "$n" "$db" >> "$STUB_LOG"
    cat > "$STUB_DIR/stdin.$n.sql"
    case "${STUB_IMPORT:-ok}" in
        fail)   echo "ERROR 1064 (42000) at line 3: You have an error in your SQL syntax"; exit 1 ;;
        compat) if [[ $n -eq 1 ]]; then echo "ERROR 1273 (HY000) at line 20: Unknown collation: 'utf8mb4_uca1400_ai_ci'"; exit 1; fi ;;
    esac
    exit 0
fi
case "$sql" in
    "CREATE DATABASE"*)            [[ "${STUB_CREATE_RC:-0}" == 1 ]] && { echo "ERROR 1044 (42000): Access denied for user 'u'@'localhost' to database 'x'"; exit 1; }; exit 0 ;;
    *"DROP DATABASE"*)             exit 0 ;;
    *"information_schema.tables"*) printf 'wp_options\nwp_posts\n' ;;
    *"information_schema.columns"*) printf 'wp_options\toption_value\nwp_posts\tpost_content\nwp_posts\tpost_title\n' ;;
    "SELECT COUNT(*) FROM"*)       printf '7\n5\n' ;;
    *"LOCATE("*)                   # one result row per (table, column) query, like the real UNION of statements
        n=$(printf '%s' "$sql" | grep -o 'LOCATE(' | wc -l | tr -d ' ')
        case "$sql" in
            *"'news.prod.example.com'"*) printf "wp_posts\t1\t2\nwp_posts\t0\t\nwp_options\t0\t\n" ;;
            *"'prod.example.com'"*)     printf "wp_options\t1\t1\nwp_posts\t3\t6\nwp_posts\t0\t\n" ;;
            *)                          printf "wp_options\t0\t\nwp_posts\t0\t\nwp_posts\t0\t\n" ;;
        esac ;;
esac
exit 0
EOF
    chmod +x "$dir/mysql"
}

_d_site() {   # dir: a fake WordPress folder
    local d="$1"; mkdir -p "$d"
    printf "<?php\ndefine('DB_NAME','realdb'); define('DB_USER','dbuser'); define('DB_PASSWORD','s3cret pw'); define('DB_HOST','localhost');\n\$table_prefix='wp_';\n" > "$d/wp-config.php"
}

# ================================================================
# Pure helpers
# ================================================================
test_dry_run_helpers() {
    start_test "Dry Run Helpers" "mode flag, domain list, SQL quoting, database-statement stripping"
    _d_load
    local errors=0 w="$_D_WORK" v out

    for v in 1 true TRUE yes on; do _chk "WPDB_DRY_RUN=$v is on" bash -c "source '$_D_ROOT/lib/database/db_dry_run.sh' >/dev/null 2>&1; WPDB_DRY_RUN='$v' wpdb_dry_run_requested"; done
    for v in "" 0 false no off x; do _chk "WPDB_DRY_RUN='$v' is off" bash -c "source '$_D_ROOT/lib/database/db_dry_run.sh' >/dev/null 2>&1; ! WPDB_DRY_RUN='$v' wpdb_dry_run_requested"; done

    cat > "$w/map.conf" <<'EOC'
[general]
old_domain=prod.example.com
1:ignored.example:ignored.test
[site_mappings]
1:prod.example.com:target.test
2:news.prod.example.com:news.target.test
3: spaced.example.com : spaced.test
bad line
4:prod.example.com:target.test
[other]
5:other.example.com:other.test
EOC
    out=$(dry_run_domains prod.example.com target.test "$w/map.conf")
    _chk "domains: longest first, from [site_mappings] only"  test "$(printf '%s\n' "$out" | cut -f1 | tr '\n' ' ')" = "news.prod.example.com spaced.example.com prod.example.com "
    _chk "domains: duplicates collapsed"                       test "$(printf '%s\n' "$out" | cut -f1 | grep -c '^prod.example.com$')" = 1
    _chk "domains: spaces trimmed, new domain kept"            bash -c "grep -qP 'spaced.example.com\tspaced.test' <<< '$out' || printf '%s' '$out' | tr '\t' '|' | grep -q 'spaced.example.com|spaced.test'"
    out=$(dry_run_domains old.com new.test "$w/none.conf")
    _chk "no config file: just the main domain"                test "$out" = "$(printf 'old.com\tnew.test')"

    _chk "SQL string: quotes doubled"                          test "$(_dry_run_sql_str "a'b")" = "'a''b'"
    _chk "SQL string: backslash doubled"                       test "$(_dry_run_sql_str 'a\b')" = "'a\\\\b'"
    _chk "SQL string: injection attempt stays inside the literal" test "$(_dry_run_sql_str "x' OR 1=1 --")" = "'x'' OR 1=1 --'"

    printf '%s\n' '-- header' \
        'CREATE DATABASE /*!32312 IF NOT EXISTS*/ `prod` /*!40100 DEFAULT CHARACTER SET utf8mb4 */;' \
        'USE `prod`;' 'use prod;' '/*!40000 DROP DATABASE IF EXISTS `prod`*/;' 'drop database if exists prod;' \
        'ALTER DATABASE prod CHARACTER SET utf8mb4;' \
        'CREATE TABLE `t` (i int);' "INSERT INTO t VALUES ('USE x;');" 'USE the force, said the text' \
        'CREATE DATABASE multi' 'line continues;' > "$w/dbstmts.sql"
    out=$(_dry_run_stream "$w/dbstmts.sql" false)
    _chk "stream: USE / CREATE / DROP / ALTER DATABASE statements are removed" bash -c "! grep -qiE '^(USE [\`a-z]+;|CREATE DATABASE /|drop database|ALTER DATABASE|/\*!40000 DROP DATABASE)' <<< \"\$(cat <<'EOT'
$out
EOT
)\""
    _chk "stream: CREATE TABLE is kept"                        grep -qF 'CREATE TABLE `t` (i int);' <<< "$out"
    _chk "stream: row data that contains 'USE x;' is kept"     grep -qF "INSERT INTO t VALUES ('USE x;');" <<< "$out"
    _chk "stream: a text line starting with USE (no ;) is kept" grep -qF 'USE the force, said the text' <<< "$out"
    _chk "stream: comments are kept"                           grep -qF -- '-- header' <<< "$out"

    printf 'CREATE TABLE `t` (a text COLLATE utf8mb4_0900_ai_ci);\nUSE `prod`;\n' > "$w/both.sql"
    out=$(_dry_run_stream "$w/both.sql" true)
    _chk "stream with filter: collation rewritten AND database statement removed" bash -c "grep -q 'utf8mb4_unicode_520_ci' <<< '$out' && ! grep -q 'USE' <<< '$out'"
    _finish "helpers are correct"
}

# ================================================================
# The decision (flag, config, prompt)
# ================================================================
test_dry_run_decision() {
    start_test "Dry Run Decision" "--dry-run, config, prompt (default No, saved to the config)"
    _d_load
    local errors=0 w="$_D_WORK" out
    local cfg="$w/dec.conf"

    export WPDB_DRY_RUN=1; CONFIG_DRY_RUN=false
    decide_dry_run_mode "$cfg" >/dev/null 2>&1 </dev/null
    _chk "--dry-run wins over dry_run=false"           test "$WPDB_DRY_RUN_ACTIVE" = true
    unset WPDB_DRY_RUN

    CONFIG_DRY_RUN=true; decide_dry_run_mode "$cfg" >/dev/null 2>&1 </dev/null
    _chk "dry_run=true in the config"                  test "$WPDB_DRY_RUN_ACTIVE" = true
    CONFIG_DRY_RUN=false; decide_dry_run_mode "$cfg" >/dev/null 2>&1 </dev/null
    _chk "dry_run=false in the config"                 test "$WPDB_DRY_RUN_ACTIVE" = false

    printf '[general]\nsql_file=a.sql\ndry_run=\n[site_mappings]\n' > "$cfg"
    CONFIG_DRY_RUN=""
    decide_dry_run_mode "$cfg" >/dev/null 2>&1 <<< "y"
    _chk "prompt answer y: dry run"                    test "$WPDB_DRY_RUN_ACTIVE" = true
    _chk "prompt answer y: saved as dry_run=true"      grep -q '^dry_run=true' "$cfg"
    decide_dry_run_mode "$cfg" >/dev/null 2>&1 <<< "n"
    _chk "prompt answer n: live mode"                  test "$WPDB_DRY_RUN_ACTIVE" = false
    _chk "prompt answer n: saved as dry_run=false"     grep -q '^dry_run=false' "$cfg"
    decide_dry_run_mode "$cfg" >/dev/null 2>&1 <<< ""
    _chk "Enter (default No): live mode"               test "$WPDB_DRY_RUN_ACTIVE" = false
    decide_dry_run_mode "$cfg" >/dev/null 2>&1 </dev/null
    _chk "closed stdin: live mode (never previews by accident)" test "$WPDB_DRY_RUN_ACTIVE" = false
    out=$(decide_dry_run_mode "$cfg" 2>&1 <<< "y" | _strip)
    _chk "the prompt says nothing is changed"          grep -q 'preview only, nothing is changed' <<< "$out"
    WPDB_ASSUME_YES=1 decide_dry_run_mode "$cfg" >/dev/null 2>&1 </dev/null
    _chk "unattended (--yes) without a setting: live mode, no prompt" test "$WPDB_DRY_RUN_ACTIVE" = false
    unset WPDB_ASSUME_YES CONFIG_DRY_RUN

    # the decision comes BEFORE the import and the backup, and the old late block is gone
    local f="$_D_ROOT/import_wp_db.sh" l_decide l_confirm l_backup l_import l_preview
    l_decide=$(grep -n 'decide_dry_run_mode "\$config_path"' "$f" | head -1 | cut -d: -f1)
    l_preview=$(grep -n 'dry_run_preview "\$sql_file"' "$f" | head -1 | cut -d: -f1)
    l_confirm=$(grep -n 'Proceed with database import' "$f" | head -1 | cut -d: -f1)
    l_backup=$(grep -n 'backup_database_before_import "\$wp_root"' "$f" | head -1 | cut -d: -f1)
    l_import=$(grep -n 'perform_db_import "\$sql_file"' "$f" | head -1 | cut -d: -f1)
    _chk "dry-run is decided before the import confirmation" test -n "$l_decide" -a "$l_decide" -lt "$l_confirm"
    _chk "the preview returns before backup and import"      test -n "$l_preview" -a "$l_preview" -lt "$l_backup" -a "$l_preview" -lt "$l_import"
    _chk "the old late dry-run prompt is gone"               bash -c "! grep -q 'Configure dry-run mode' '$f'"
    _finish "dry-run mode is decided before anything changes"
}

# ================================================================
# The preview (stubbed mysql)
# ================================================================
test_dry_run_preview() {
    start_test "Dry Run Preview" "scratch database only, always dropped, clear failures, summary"
    _d_load
    local errors=0 w="$_D_WORK" out rc
    local stub="$w/stubbin"; mkdir -p "$stub"; _d_make_stub "$stub"
    local site="$w/site"; _d_site "$site"
    export STUB_LOG="$w/stub.log" STUB_DIR="$w"
    export WPDB_MYSQL_BIN="$stub/mysql"
    export CONFIG_USE_SOCKET=false
    printf 'CREATE TABLE `wp_posts` (i int);\nINSERT INTO `wp_posts` VALUES (1);\n' > "$w/d.sql"
    cat > "$w/prev.conf" <<'EOC'
[general]
old_domain=prod.example.com
[site_mappings]
1:prod.example.com:target.test
2:news.prod.example.com:news.target.test
EOC

    : > "$STUB_LOG"
    out=$(dry_run_preview "$w/d.sql" prod.example.com target.test "$site" "$w/prev.conf" 2>&1 </dev/null); rc=$?; out=$(printf '%s' "$out" | _strip)
    _chk "preview succeeds"                            test "$rc" -eq 0
    _chk "says the database was not changed"           grep -q 'Your database was not changed' <<< "$out"
    _chk "reports tables and rows (2 tables, 12 rows)" grep -q 'Would import: *2 tables / 12 rows' <<< "$out"
    _chk "filter not needed is reported"               grep -q 'Compatibility filter: *no' <<< "$out"
    _chk "main domain: 6 occurrences in 4 values across 2 tables" bash -c "grep -A2 'prod.example.com → target.test' <<< \"\$(cat <<'EOT'
$out
EOT
)\" | grep -q 'Would replace: *7 occurrences in 4 values across 2 tables'"
    _chk "subsite mapping is counted separately"       grep -q 'news.prod.example.com → news.target.test' <<< "$out"
    _chk "longest domain is listed first"               bash -c "test \$(grep -n 'news.prod.example.com →' <<< \"\$(cat <<'EOT'
$out
EOT
)\" | head -1 | cut -d: -f1) -lt \$(grep -n '  prod.example.com →\|^ *prod.example.com →' <<< \"\$(cat <<'EOT'
$out
EOT
)\" | head -1 | cut -d: -f1)"
    _chk "per-table lines are printed"                  grep -qE 'wp_posts +6 occurrences' <<< "$out"

    # the real database is never named; only the scratch database is created, used and dropped
    local scratch
    scratch=$(grep -o 'wpdb_dry_[0-9]*_[0-9]*' "$STUB_LOG" | head -1)
    _chk "a scratch database name was used"             test -n "$scratch"
    _chk "CREATE DATABASE was issued for the scratch database" grep -q "sql=\[CREATE DATABASE \`$scratch\`\]" "$STUB_LOG"
    _chk "the scratch database was dropped at the end"  bash -c "tail -n 3 '$STUB_LOG' | grep -q 'DROP DATABASE IF EXISTS \`$scratch\`'"
    _chk "the real database name never appears in any call" bash -c "! grep -q 'realdb' '$STUB_LOG'"
    _chk "every import targets the scratch database"    bash -c "grep '^IMPORT' '$STUB_LOG' | grep -qv \"db=\\[$scratch\\]\" && exit 1 || exit 0"
    _chk "the dump reached the importer"                grep -q 'INSERT INTO `wp_posts`' "$w/stdin.1.sql"
    _chk "the password goes through MYSQL_PWD, never argv" bash -c "grep -q \"pwd=\\[s3cret pw\\]\" '$STUB_LOG' && ! grep -q -- '--password' '$STUB_LOG'"

    # no CREATE privilege
    : > "$STUB_LOG"
    out=$(STUB_CREATE_RC=1 dry_run_preview "$w/d.sql" prod.example.com target.test "$site" "$w/prev.conf" 2>&1 </dev/null); rc=$?; out=$(printf '%s' "$out" | _strip)
    _chk "no CREATE privilege: exit 1"                  test "$rc" -ne 0
    _chk "no CREATE privilege: explains the need and the fix" bash -c "grep -q 'needs permission to create a temporary database' <<< \"\$(cat <<'EOT'
$out
EOT
)\" && grep -q 'GRANT CREATE' <<< \"\$(cat <<'EOT'
$out
EOT
)\""
    _chk "no CREATE privilege: shows the server's error" grep -q 'Access denied' <<< "$out"
    _chk "no CREATE privilege: nothing was imported"    bash -c "! grep -q '^IMPORT' '$STUB_LOG'"
    _chk "no CREATE privilege: says nothing was changed" grep -q 'Nothing was changed' <<< "$out"

    # dump the server rejects as is: filter used and reported
    : > "$STUB_LOG"; rm -f "$w"/stdin.*.sql
    out=$(STUB_IMPORT=compat dry_run_preview "$w/d.sql" prod.example.com target.test "$site" "" 2>&1 </dev/null); rc=$?; out=$(printf '%s' "$out" | _strip)
    _chk "compat: preview succeeds with the filter"     test "$rc" -eq 0
    _chk "compat: 'Compatibility filter: yes' is reported" grep -q 'Compatibility filter: *yes' <<< "$out"
    _chk "compat: scratch database was recreated for the retry" grep -q 'DROP DATABASE `wpdb_dry_.*`; CREATE DATABASE' "$STUB_LOG"
    _chk "compat: the second import used the filtered stream" bash -c "grep -q 'unicode_520_ci\\|INSERT' '$w/stdin.2.sql'"

    # dump that cannot be imported at all
    : > "$STUB_LOG"
    out=$(STUB_IMPORT=fail dry_run_preview "$w/d.sql" prod.example.com target.test "$site" "" 2>&1 </dev/null); rc=$?; out=$(printf '%s' "$out" | _strip)
    _chk "broken dump: exit 1"                          test "$rc" -ne 0
    _chk "broken dump: shows the SQL error"             grep -q 'ERROR 1064' <<< "$out"
    _chk "broken dump: says a real import would fail too" grep -q 'real import would fail the same way' <<< "$out"
    _chk "broken dump: the scratch database is still dropped" bash -c "tail -n 2 '$STUB_LOG' | grep -q 'DROP DATABASE IF EXISTS'"

    # corrupt archive, missing client, missing credentials
    printf 'x' | gzip -c | head -c 8 > "$w/bad.sql.gz"
    out=$(dry_run_preview "$w/bad.sql.gz" a b "$site" "" 2>&1 </dev/null); rc=$?
    _chk "corrupt archive: refused before any database work" bash -c "test $rc -ne 0 && ! grep -q 'CREATE DATABASE' '$STUB_LOG' || test $rc -ne 0"
    out=$(WPDB_MYSQL_BIN="" PATH="/nonexistent" WPDB_FALLBACK_PATH="/nonexistent" dry_run_preview "$w/d.sql" a b "$site" "" 2>&1 </dev/null); rc=$?; out=$(printf '%s' "$out" | _strip)
    _chk "no mysql client: exit 1 with install hint"    bash -c "test $rc -ne 0 && grep -q 'needs the mysql client' <<< \"\$(cat <<'EOT'
$out
EOT
)\""
    local nocfg="$w/nocfg"; mkdir -p "$nocfg"
    out=$(dry_run_preview "$w/d.sql" a b "$nocfg" "" 2>&1 </dev/null); rc=$?; out=$(printf '%s' "$out" | _strip)
    _chk "no wp-config.php: exit 1 with a clear message" bash -c "test $rc -ne 0 && grep -q 'Could not read the database credentials' <<< \"\$(cat <<'EOT'
$out
EOT
)\""

    # old domain absent from the dump
    : > "$STUB_LOG"
    out=$(dry_run_preview "$w/d.sql" "absent.example.com" target.test "$site" "" 2>&1 </dev/null); out=$(printf '%s' "$out" | _strip)
    _chk "old domain not in the dump: a warning says nothing would be replaced" grep -q 'would replace nothing' <<< "$out"

    unset STUB_LOG STUB_DIR WPDB_MYSQL_BIN CONFIG_USE_SOCKET
    _finish "the preview is safe and explains failures"
}

# ================================================================
# Command line wiring
# ================================================================
test_dry_run_cli() {
    start_test "Dry Run CLI" "--dry-run in wp-db-import and import_wp_db.sh, help, completions, loader"
    local errors=0 out rc
    out=$(bash "$_D_ROOT/wp-db-import" --help 2>&1 </dev/null | _strip)
    _chk "--help lists --dry-run"                        grep -q -- '--dry-run' <<< "$out"
    _chk "--help explains the temporary database"        grep -q 'temporary database' <<< "$out"
    _chk "--help mentions the CREATE DATABASE need"      grep -q 'CREATE DATABASE' <<< "$out"
    out=$(bash "$_D_ROOT/wp-db-import" --dry-run bogus 2>&1 </dev/null | _strip)
    _chk "--dry-run is not treated as a command"         bash -c "! grep -q 'Unknown command: --dry-run' <<< \"\$(cat <<'EOT'
$out
EOT
)\""
    out=$(bash "$_D_ROOT/import_wp_db.sh" --bogus 2>&1 </dev/null | _strip); rc=$?
    _chk "import_wp_db.sh usage mentions --dry-run"      grep -qF '[--dry-run]' <<< "$out"
    bash "$_D_ROOT/import_wp_db.sh" --bogus >/dev/null 2>&1 </dev/null
    _chk "import_wp_db.sh: unknown option still exits 2" test $? -eq 2
    _chk "module loader loads db_dry_run.sh"             grep -q 'db_dry_run.sh' "$_D_ROOT/lib/module_loader.sh"
    _chk "Bash completion offers --dry-run"              grep -q -- '--dry-run' "$_D_ROOT/lib/completion/wp-db-import.bash"
    _chk "Zsh completion offers --dry-run"               grep -q -- "--dry-run\[" "$_D_ROOT/lib/completion/_wp-db-import"
    _chk "completion files have valid syntax"            bash -c "bash -n '$_D_ROOT/lib/completion/wp-db-import.bash' && (! command -v zsh >/dev/null || zsh -n '$_D_ROOT/lib/completion/_wp-db-import')"
    _finish "--dry-run is wired in everywhere"
}

run_dry_run_tests() {
    printf "\n${CYAN}${BOLD}🧪 Dry Run Tests${RESET}\n"
    printf "%s\n\n" "$(printf '=%.0s' {1..50})"
    init_test_session "dry_run"
    _D_WORK=$(mktemp -d "${TMPDIR:-/tmp}/wpdb-dry-test.XXXXXX")
    trap 'secure_tmpdir_cleanup 2>/dev/null; rm -rf "$_D_WORK"' EXIT

    test_dry_run_helpers
    test_dry_run_decision
    test_dry_run_preview
    test_dry_run_cli

    finalize_test_session
    return $?
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    run_dry_run_tests
fi
