#!/usr/bin/env bash

# ================================================================
# Unit Tests for New Modules
# ================================================================
#
# Description:
#   This script contains unit tests for the newly refactored modules
#   in the wp-db-import-and-domain-replacement-tool project. These
#   tests ensure the correctness and reliability of the following modules:
#
#   - cleanup.sh: Handles cleanup operations, such as removing temporary files.
#   - db_import.sh: Manages database import functionality.
#   - domain_manager.sh: Validates and manages domain replacements.
#   - multisite_manager.sh: Updates multisite tables for WordPress installations.
#
# Usage:
#   This script is executed as part of the unit testing suite. It can
#   also be run independently to verify the functionality of the new modules.
#
# Dependencies:
#   - test_framework.sh: Provides the testing framework for defining and running tests.
#   - Mock functions: Used to simulate external dependencies like WP-CLI.
#
# ================================================================

# Source the test framework
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../test_framework.sh"

# Mock functions to prevent actual execution during tests
mock_wp_cli() {
    echo "Mock WP-CLI execution: $*"
    return 0
}

# ===============================================
# Test Cleanup Module
# ===============================================
#
# Description:
#   Tests the cleanup module to ensure it removes temporary files
#   and performs cleanup operations correctly.
#
# Test Cases:
#   - Verify that the cleanup function removes the DB_LOG file.
#   - Handle cases where the cleanup module is not found.
#

test_cleanup_module() {
    start_test "Cleanup Module" "Test cleanup functionality"

    local cleanup_module="$PROJECT_ROOT_DIR/lib/core/cleanup.sh"

    if [[ -f "$cleanup_module" ]]; then
        source "$cleanup_module"

        # Create a temp file and set it in DB_LOG
        local test_log="/tmp/test_db_log_$$.sql"
        touch "$test_log"
        DB_LOG="$test_log"

        # Mock WP-CLI
        execute_wp_cli() { return 0; }

        # Run cleanup
        cleanup >/dev/null 2>&1

        # Verify DB_LOG file was removed
        if [[ ! -f "$test_log" ]]; then
            pass_test "Cleanup function removed DB_LOG file successfully"
        else
            fail_test "Cleanup function did not remove DB_LOG file"
            rm -f "$test_log"
        fi
    else
        fail_test "Cleanup module not found"
    fi
}

# ===============================================
# Test DB Import Module
# ===============================================
#
# Description:
#   Tests the database import module to ensure it handles database
#   import operations correctly.
#
# Test Cases:
#   - Verify that perform_db_import executes successfully.
#   - Handle cases where the db_import module is not found.
#

test_db_import_module() {
    start_test "DB Import Module" "Test database import logic"

    local db_import_module="$PROJECT_ROOT_DIR/lib/database/db_import.sh"

    if [[ -f "$db_import_module" ]]; then
        source "$db_import_module"

        # Mock dependencies
        execute_wp_cli() { echo "Import success"; return 0; }
        show_spinner() { return 0; }

        # Test perform_db_import with a real SQL file
        local sql_file
        sql_file=$(mktemp "${TMPDIR:-/tmp}/wpdb-test-import.XXXXXX")
        printf "CREATE TABLE t (id int);\n" > "$sql_file"
        local log_file="$sql_file.log"

        if ! perform_db_import "$sql_file" "$log_file" >/dev/null 2>&1; then
            fail_test "perform_db_import failed"
        # A missing SQL file must be refused, never reported as imported
        elif perform_db_import "$sql_file.missing" "$log_file" >/dev/null 2>&1; then
            fail_test "perform_db_import accepted a missing SQL file"
        else
            pass_test "perform_db_import succeeds with a real file and refuses a missing one"
        fi
        rm -f "$sql_file" "$log_file"
        # perform_db_import may create the private temp directory (table snapshot); remove it
        declare -F secure_tmpdir_cleanup >/dev/null 2>&1 && secure_tmpdir_cleanup
    else
        fail_test "DB Import module not found"
    fi
}

# ===============================================
# Test Domain Manager Module
# ===============================================
#
# Description:
#   Tests the domain manager module to ensure it validates and manages
#   domain replacements correctly.
#
# Test Cases:
#   - Validate domains with valid input.
#   - Handle cases with empty new domain values.
#   - Handle cases where the domain manager module is not found.
#

test_domain_manager_module() {
    start_test "Domain Manager Module" "Test domain validation logic"

    local domain_manager_module="$PROJECT_ROOT_DIR/lib/core/domain_manager.sh"

    if [[ -f "$domain_manager_module" ]]; then
        source "$domain_manager_module"

        # Test validate_domains with valid input
        # Mock global arrays
        domain_keys=("old.com")
        domain_values=("new.com")
        domain_blog_ids=("1")

        # Mock dependencies
        execute_wp_cli() { return 0; }

        if validate_domains >/dev/null 2>&1; then
            pass_test "validate_domains passed with valid data"
        else
            fail_test "validate_domains failed with valid data"
        fi

        # Test with empty new domain (should fail or warn, but function returns 0 if user confirms,
        # here we just check it runs without syntax error)
        domain_values=("")
        if validate_domains >/dev/null 2>&1; then
             pass_test "validate_domains handled empty new domain"
        else
             fail_test "validate_domains crashed on empty new domain"
        fi
    else
        fail_test "Domain Manager module not found"
    fi
}

# ===============================================
# Test Multisite Manager Module
# ===============================================
#
# Description:
#   Tests the multisite manager module to ensure it updates multisite
#   tables for WordPress installations correctly.
#
# Test Cases:
#   - Verify that update_multisite_tables executes successfully.
#   - Handle cases where the multisite manager module is not found.
#

test_multisite_manager_module() {
    start_test "Multisite Manager Module" "Test multisite table update logic"

    local multisite_module="$PROJECT_ROOT_DIR/lib/core/multisite_manager.sh"

    if [[ -f "$multisite_module" ]]; then
        source "$multisite_module"

        # Setup mock data
        domain_keys=("old.com" "sub.old.com")
        domain_values=("new.com" "sub.new.com")
        domain_blog_ids=("1" "2")

        # Mock execute_wp_cli to simulate success
        execute_wp_cli() {
            if [[ "$1" == "eval" ]]; then
                echo "SUCCESS"
            else
                return 0
            fi
        }

        # Run update_multisite_tables
        if update_multisite_tables "1" "subdomain" "old.com" >/dev/null 2>&1; then
            pass_test "update_multisite_tables execution successful"
        else
            fail_test "update_multisite_tables failed"
        fi
    else
        fail_test "Multisite Manager module not found"
    fi
}

# ===============================================
# Multisite tables: table prefix and hostile values
# ===============================================
#
# Description:
#   update_multisite_tables sends PHP code to `wp eval`. The code must (1) name the tables with
#   the site's own prefix ($wpdb->base_prefix), never a fixed "wp_", and (2) treat domains and
#   paths as data: a quote or backslash must not leave the PHP string. With php installed the
#   recorded code is run against a fake $wpdb and the values it receives are compared.
#
_nm_chk() {
    local desc="$1"; shift
    if "$@" >/dev/null 2>&1; then printf "  ✅ %s\n" "$desc"; else printf "  ❌ %s\n" "$desc"; ((_nm_errors++)); fi
}

test_multisite_prefix_and_escaping() {
    start_test "Multisite Tables: Prefix And Escaping" "custom table prefix is used; hostile domains stay data"
    _nm_errors=0
    local module="$PROJECT_ROOT_DIR/lib/core/multisite_manager.sh" w log
    [[ -f "$module" ]] || { fail_test "Multisite Manager module not found"; return; }
    source "$module"
    w=$(mktemp -d "${TMPDIR:-/tmp}/wpdb-nm.XXXXXX"); log="$w/eval.log"

    execute_wp_cli() {
        if [[ "$1" == "eval" ]]; then
            # one record per call: code between markers (the code itself has no newline)
            printf '%s\n' "$2" >> "$log"
            echo "SUCCESS"
        fi
        return 0
    }

    # --- normal run: tables follow the prefix, no fixed wp_
    : > "$log"
    domain_keys=("old.com" "sub.old.com"); domain_values=("new.com" "sub.new.com"); domain_blog_ids=("1" "2")
    update_multisite_tables "1" "subdomain" "old.com" >/dev/null 2>&1
    _nm_chk "normal run succeeds"                          test $? -eq 0
    _nm_chk "site table named through base_prefix"         grep -q "base_prefix . 'site'" "$log"
    _nm_chk "blogs table named through base_prefix"        grep -q "base_prefix . 'blogs'" "$log"
    _nm_chk "no fixed wp_ table name is left"              bash -c '! grep -qE "wp_(blogs|site)" "$0"' "$log"
    _nm_chk "normal domain is unchanged in the code"       grep -q "'domain' => 'sub.new.com'" "$log"

    # --- hostile values: every quote and backslash from a value is escaped
    : > "$log"
    local evil="x'));system('id');\$a=array('y" evil_path
    domain_keys=("old.com" "sub.old.com"); domain_values=("new.com" "$evil"); domain_blog_ids=("1" "2")
    update_multisite_tables "1" "subdomain" "old.com" >/dev/null 2>&1
    _nm_chk "hostile domain: the quote is escaped in the code" grep -qF "x\\'));system(\\'id\\');" "$log"
    _nm_chk "hostile domain: no unescaped breakout"        bash -c '! grep -qF "'"'"'x'"'"'));system" "$0"' "$log"
    local bs_evil='a\'"'"'b'
    : > "$log"
    domain_values=("new.com" "$bs_evil")
    update_multisite_tables "1" "subdomain" "old.com" >/dev/null 2>&1
    _nm_chk "backslash before a quote: both are escaped"   grep -qF "a\\\\\\'b" "$log"

    # --- run the recorded code against a fake $wpdb (needs php)
    if command -v php >/dev/null 2>&1; then
        : > "$log"
        domain_values=("new.com" "$evil")
        update_multisite_tables "1" "subdomain" "old.com" >/dev/null 2>&1
        cat > "$w/run.php" <<'PHPEOF'
<?php
class FakeDb { public $base_prefix = 'xx_'; public $calls = array();
  function update($t, $d, $wh) { $this->calls[] = array($t, $d, $wh); return 1; } }
$wpdb = new FakeDb();
foreach (file($argv[1], FILE_IGNORE_NEW_LINES) as $code) {
    if ($code === '') continue;
    $fn = function () use ($code, $wpdb) { global $wpdb; ob_start(); eval($code); ob_end_clean(); };
    $fn();
}
echo json_encode($wpdb->calls);
PHPEOF
        local out; out=$(php "$w/run.php" "$log" 2>/dev/null)
        _nm_chk "php: tables are xx_site and xx_blogs"       bash -c 'grep -q "\"xx_site\"" <<< "$0" && grep -q "\"xx_blogs\"" <<< "$0"' "$out"
        _nm_chk "php: hostile domain arrives as plain data"  bash -c 'php -r '"'"'$c=json_decode($argv[1],true); $ok=false; foreach($c as $x){ if(isset($x[1]["domain"]) && $x[1]["domain"]===$argv[2]) $ok=true; } exit($ok?0:1);'"'"' "$0" "$1"' "$out" "$evil"
        _nm_chk "php: exactly 3 updates (site, subsite, main)" bash -c 'test "$(php -r '"'"'echo count(json_decode($argv[1],true));'"'"' "$0")" = 3' "$out"
    else
        printf "  ⏭️  php not installed: the fake-wpdb run is skipped\n"
    fi

    # --- blog ids go into PHP unquoted: only plain numbers are accepted
    : > "$log"
    domain_keys=("old.com" "sub.old.com"); domain_values=("new.com" "sub.new.com"); domain_blog_ids=("1" "2); system('id'); //")
    update_multisite_tables "1" "subdomain" "old.com" >/dev/null 2>&1
    _nm_chk "non-numeric blog id: run fails"               test $? -ne 0
    _nm_chk "non-numeric blog id: never reaches the code"  bash -c '! grep -q "system(" "$0"' "$log"
    : > "$log"
    domain_blog_ids=("1" "2")
    update_multisite_tables "1; system('id')" "subdomain" "old.com" >/dev/null 2>&1
    _nm_chk "non-numeric main site id: never reaches the code" bash -c '! grep -q "system(" "$0"' "$log"

    # --- the helper is required (fail closed)
    local saved; saved=$(declare -f php_sq_escape); unset -f php_sq_escape
    : > "$log"
    update_multisite_tables "1" "subdomain" "old.com" >/dev/null 2>&1
    _nm_chk "helper missing: returns 1 and sends nothing"  bash -c 'test ! -s "$0"' "$log"
    eval "$saved"

    unset -f execute_wp_cli
    rm -rf "$w"
    if [[ "$_nm_errors" -eq 0 ]]; then pass_test "table prefix used, values stay data"; else fail_test "$_nm_errors check(s) failed"; fi
}

# ===============================================
# Table prefix detection
# ===============================================
test_table_prefix_detection() {
    start_test "Table Prefix Detection" "wp-config.php prefix is read safely; main-site queries use it"
    _nm_errors=0
    local w; w=$(mktemp -d "${TMPDIR:-/tmp}/wpdb-pre.XXXXXX")
    local old_pwd="$PWD"

    _pre() { ( cd "$w" && printf '<?php\n%s\n' "$1" > wp-config.php && get_safe_table_prefix ); }
    _pre_raw() { ( cd "$w" && printf '<?php\n%s\n' "$1" > wp-config.php && get_wp_table_prefix ); }
    _nm_chk "single quotes"                              test "$(_pre "\$table_prefix = 'abc_';")" = abc_
    _nm_chk "double quotes"                              test "$(_pre '$table_prefix = "dq_";')" = dq_
    _nm_chk "indented, spaced, trailing comment"         test "$(_pre '   $table_prefix  =  '"'"'sp_'"'"';  // note')" = sp_
    _nm_chk "digits and uppercase"                       test "$(_pre "\$table_prefix = 'Wp9_';")" = Wp9_
    _nm_chk "commented line is ignored"                  test "$(_pre "// \$table_prefix = 'no_';
\$table_prefix = 'yes_';")" = yes_
    _nm_chk "last assignment wins (as in PHP)"           test "$(_pre "\$table_prefix = 'one_';
\$table_prefix = 'two_';")" = two_
    _nm_chk "unsafe characters fall back to wp_ (safe form)" test "$(_pre "\$table_prefix = 'a-b;DROP';")" = wp_
    _nm_chk "raw form returns the unsafe value (callers refuse it)" test "$(_pre_raw "\$table_prefix = 'a-b;DROP';")" = "a-b;DROP"
    _nm_chk "backtick and space fall back to wp_"        test "$(_pre "\$table_prefix = 'a b\`';")" = wp_
    _nm_chk "empty prefix falls back to wp_"             test "$(_pre "\$table_prefix = '';")" = wp_
    _nm_chk "computed prefix falls back to wp_"          test "$(_pre "\$table_prefix = getenv('X');")" = wp_
    _nm_chk "no assignment falls back to wp_"            test "$(_pre "define('A', 1);")" = wp_
    _nm_chk "CRLF line endings"                          test "$(_pre "\$table_prefix = 'crlf_';$(printf '\r')")" = crlf_
    mkdir -p "$w/site" && printf '<?php\n$table_prefix = "up_";\n' > "$w/wp-config.php"
    _nm_chk "wp-config.php one folder above the site"    test "$(cd "$w/site" && get_wp_table_prefix)" = up_
    rm -f "$w/wp-config.php"
    _pre_none() { ( cd "$1" && out=$(get_wp_table_prefix); rc=$?; [[ "$out" == wp_ && $rc -eq 1 ]] ); }
    _nm_chk "no wp-config.php: wp_ and return code 1"    _pre_none "$w/site"
    _safe_none() { ( cd "$1" && out=$(get_safe_table_prefix); rc=$?; [[ "$out" == wp_ && $rc -eq 0 ]] ); }
    _nm_chk "safe form: no wp-config.php gives wp_, rc 0" _safe_none "$w/site"

    # detect_main_site: the network tables carry the prefix
    printf '<?php\n$table_prefix = "net_";\n' > "$w/wp-config.php"
    local qlog="$w/q.log"; : > "$qlog"
    execute_wp_cli() {
        case "$1" in
            core) echo "6.0" ;;
            eval) echo "yes" ;;
            db) shift; printf '%s\n' "$*" >> "$qlog"; echo "1" ;;
            option) echo "https://x.test" ;;
        esac
        return 0
    }
    ( cd "$w" && detect_main_site yes x.test >/dev/null 2>&1 )
    _nm_chk "main site query uses net_site"              grep -q 'net_site' "$qlog"
    _nm_chk "no query names wp_site or wp_blogs"         bash -c '! grep -qE "wp_(site|blogs)" "$0"' "$qlog"
    : > "$qlog"
    execute_wp_cli() {
        case "$1" in
            core) echo "6.0" ;;
            eval) echo "yes" ;;
            db) shift; printf '%s\n' "$*" >> "$qlog"; case "$*" in *net_site*) echo "";; *net_blogs*WHERE\ path*) echo "3";; *net_3_options*) echo "https://three.test";; esac ;;
            option) return 1 ;;
            site) return 1 ;;
        esac
        return 0
    }
    ( cd "$w" && detect_main_site yes x.test >/dev/null 2>&1 )
    _nm_chk "blogs fallback uses net_blogs"              grep -q 'net_blogs' "$qlog"
    _nm_chk "subsite options table is net_3_options"     grep -q 'net_3_options' "$qlog"
    unset -f execute_wp_cli
    cd "$old_pwd"; rm -rf "$w"
    if [[ "$_nm_errors" -eq 0 ]]; then pass_test "prefix read safely and used"; else fail_test "$_nm_errors check(s) failed"; fi
}

# ===============================================
# Remote database warning
# ===============================================
test_remote_database_warning() {
    start_test "Remote Database Warning" "a server that does not look local is warned about, never blocked"
    _nm_errors=0
    local h
    for h in "" localhost localhost:3306 "localhost:/tmp/mysql.sock" 127.0.0.1 127.0.0.1:3307 "[::1]:3306" ::1 db database db:3306 \
             host.docker.internal mysite.local shop.test 10.1.2.3 192.168.0.5:3306 172.16.0.1 172.31.9.9 169.254.1.1 LOCALHOST "  localhost  " fd12::1; do
        _nm_chk "local: '$h'"  bash -c '! db_host_is_remote "$0"' "$h"
    done
    for h in db.example.com prod-db.abc.rds.amazonaws.com 8.8.8.8 203.0.113.9:3306 172.32.0.1 172.15.0.1 "[2001:db8::1]" MySQL.Example.COM:3306; do
        _nm_chk "remote: '$h'" db_host_is_remote "$h"
    done

    # warn_if_remote_database: message only, globals untouched, return code 0
    local w; w=$(mktemp -d "${TMPDIR:-/tmp}/wpdb-rem.XXXXXX")
    get_wp_db_credentials() { WP_DB_HOST="${FAKE_HOST:-}"; export WP_DB_HOST; return 0; }
    unset WP_DB_HOST
    local out
    out=$(FAKE_HOST="db.example.com" warn_if_remote_database "$w" 2>&1); local rc=$?
    _nm_chk "remote host: warning names the host"        grep -q "'db.example.com' does not look like your own machine" <<< "$out"
    _nm_chk "remote host: return code 0 (never blocks)"  test $rc -eq 0
    out=$(FAKE_HOST="localhost" warn_if_remote_database "$w" 2>&1)
    _nm_chk "local host: no output"                      test -z "$out"
    out=$(FAKE_HOST="" warn_if_remote_database "$w" 2>&1)
    _nm_chk "no host in wp-config: no output"            test -z "$out"
    out=$(warn_if_remote_database "" 2>&1)
    _nm_chk "no path: no output, return code 0"          test -z "$out"
    FAKE_HOST="db.example.com" warn_if_remote_database "$w" >/dev/null 2>&1
    _nm_chk "global WP_DB_HOST is not changed"           test -z "${WP_DB_HOST+x}"
    get_wp_db_credentials() { return 1; }
    # shellcheck disable=SC2218  # defined in lib/core/utils.sh, sourced by the test framework
    out=$(warn_if_remote_database "$w" 2>&1); rc=$?
    _nm_chk "unreadable wp-config: no output, rc 0"      bash -c 'test -z "$0" -a "$1" -eq 0' "$out" "$rc"
    unset -f get_wp_db_credentials; source "$PROJECT_ROOT_DIR/lib/core/utils.sh" >/dev/null 2>&1
    _nm_chk "the import warns before its prompt"         grep -q 'warn_if_remote_database "\$wp_root"' "$PROJECT_ROOT_DIR/import_wp_db.sh"
    rm -rf "$w"
    if [[ "$_nm_errors" -eq 0 ]]; then pass_test "remote servers are flagged, never blocked"; else fail_test "$_nm_errors check(s) failed"; fi
}

# ===============================================
# Run All Tests
# ===============================================
run_new_module_tests() {
    init_test_session "new_modules"

    printf "${CYAN}${BOLD}🔬 New Modules Unit Tests${RESET}\n"

    test_cleanup_module
    test_db_import_module
    test_domain_manager_module
    test_multisite_manager_module
    test_multisite_prefix_and_escaping
    test_table_prefix_detection
    test_remote_database_warning

    finalize_test_session
    return $?
}

# Execute if run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    run_new_module_tests
fi
