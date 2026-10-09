#!/usr/bin/env bash

# ================================================================
# WordPress Specific Tests
# ================================================================
#
# Description:
#   A comprehensive test suite focusing on verifying the correct operation and
#   robustness of the WordPress-specific functionality within the import tool.
#   This includes testing WordPress installation detection (single-site and multisite),
#   WP-CLI integration, configuration file parsing, domain sanitization, search/replace
#   logic, and various error handling scenarios.
#
# Key Features Tested:
# - WordPress root detection.
# - Single-site vs. Multisite configuration type detection.
# - WP-CLI availability and essential command validation.
# - Configuration file loading, variable setting, and syntax validation.
# - Domain and URL cleaning/sanitization routines.
# - Error handling for missing files, invalid config, and permissions.
#
# Functions provided:
# - test_wordpress_detection
# - test_wp_cli_integration
# - test_config_file_handling
# - test_domain_sanitization
# - test_search_replace
# - test_multisite_handling
# - test_error_handling
# - test_cleanup_functions
# - run_wordpress_tests
#
# Dependencies:
# - test_framework.sh (Must be sourced for test session management)
# - External functions from the main script (e.g., `find_wp_root`, `detect_wp_type`, `load_config`, `sanitize_domain`, etc.).
# - Color constants (e.g., ${CYAN}, ${BOLD}, ${RESET}, ${DIM})
#
# Usage:
#   ./test/wordpress_tests.sh
#
# ================================================================

# Source the test framework
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../test_framework.sh"

# ===============================================
# Test WordPress detection functionality
# ===============================================
#
# Description: Verifies the ability of the script's core functions to correctly
#              locate a WordPress installation directory and identify its type (single vs. multisite).
#
# Parameters:
#   - None.
#
# Returns:
#   - Calls `pass_test` or `fail_test`.
#
# Behavior:
#   - Creates temporary test directories and mock `wp-config.php` files for testing.
#   - Tests detection in a non-WP directory, a fake single-site, and a fake multisite environment.
#   - Requires external functions like `find_wp_root` and `detect_wp_type`.
#
test_wordpress_detection() {
    start_test "WordPress Detection" "Test WordPress installation detection capabilities"

    local detection_issues=0

    # Create a temporary test environment
    local temp_dir=$(create_temp_test_dir "wp_detection")
    cd "$temp_dir" || return 1

    printf "  Testing WordPress detection in various scenarios...\n"

    # Test 1: No WordPress installation
    printf "    Testing non-WordPress directory...\n"
    if source "$PROJECT_ROOT_DIR/import_wp_db.sh" >/dev/null 2>&1; then
        if declare -F find_wp_root >/dev/null 2>&1; then
            local wp_root=$(find_wp_root 2>/dev/null)
            if [[ -z "$wp_root" ]]; then
                printf "      ✅ Correctly detected no WordPress installation\n"
            else
                printf "      ❌ False positive WordPress detection\n"
                ((detection_issues++))
            fi
        else
            printf "      ❌ core function find_wp_root is missing\n"
            ((detection_issues++))
        fi
    fi

    # Test 2: Create fake WordPress installation
    printf "    Testing with fake wp-config.php...\n"
    echo "<?php // Fake WordPress config for testing" > wp-config.php
    echo "define('DB_NAME', 'test_db');" >> wp-config.php
    echo "define('DB_USER', 'test_user');" >> wp-config.php

    if source "$PROJECT_ROOT_DIR/import_wp_db.sh" >/dev/null 2>&1; then
        if declare -F find_wp_root >/dev/null 2>&1; then
            local wp_root=$(find_wp_root 2>/dev/null)
            if [[ "$wp_root" == "$temp_dir" ]]; then
                printf "      ✅ Correctly detected WordPress installation\n"
            else
                printf "      ❌ Failed to detect WordPress installation\n"
                ((detection_issues++))
            fi
        fi
    fi

    # Test 3: Test WordPress type detection
    printf "    Testing WordPress type detection...\n"
    if source "$PROJECT_ROOT_DIR/import_wp_db.sh" >/dev/null 2>&1; then
        if declare -F detect_wp_type >/dev/null 2>&1; then
            local wp_type=$(detect_wp_type "$temp_dir" 2>/dev/null || echo "unknown")
            if [[ "$wp_type" == "single" ]]; then
                printf "      ✅ Correctly detected single-site WordPress\n"
            else
                printf "      ⚠️  WordPress type detection: $wp_type\n"
            fi
        fi
    fi

    # Test 4: Create multisite indicators
    printf "    Testing multisite detection...\n"
    echo "define('MULTISITE', true);" >> wp-config.php
    echo "define('SUBDOMAIN_INSTALL', false);" >> wp-config.php

    if source "$PROJECT_ROOT_DIR/import_wp_db.sh" >/dev/null 2>&1; then
        if declare -F detect_wp_type >/dev/null 2>&1; then
            local wp_type=$(detect_wp_type "$temp_dir" 2>/dev/null || echo "unknown")
            if [[ "$wp_type" == *"multisite"* ]]; then
                printf "      ✅ Correctly detected multisite WordPress\n"
            else
                printf "      ⚠️  Multisite detection result: $wp_type\n"
            fi
        fi
    fi

    # Cleanup
    cd / && cleanup_temp_test_dir "$temp_dir"

    if [[ $detection_issues -eq 0 ]]; then
        pass_test "WordPress detection functionality working"
    else
        fail_test "$detection_issues WordPress detection issues"
    fi
}

# ===============================================
# Test WP-CLI integration
# ===============================================
#
# Description: Verifies that the WP-CLI tool is available in the environment,
#              is a sufficiently recent version, and that essential WP-CLI commands
#              required by the import tool (e.g., search-replace, core, db) are available.
#
# Parameters:
#   - None.
#
# Returns:
#   - Calls `pass_test` or `fail_test`. Returns 0 if `wp` command is not found.
#
# Behavior:
#   - Uses `require_command "wp"` to skip if not available.
#   - Checks `wp --info` and `wp --version`.
#
test_wp_cli_integration() {
    if ! require_command "wp"; then
        return 0
    fi

    start_test "WP-CLI Integration" "Test integration with WP-CLI commands"

    local wp_cli_issues=0

    # Test basic WP-CLI functionality
    printf "  Testing WP-CLI basic functionality...\n"

    if wp --info >/dev/null 2>&1; then
        printf "    ✅ WP-CLI info command works\n"
    else
        printf "    ❌ WP-CLI info command failed\n"
        ((wp_cli_issues++))
    fi

    # Test WP-CLI version compatibility
    local wp_version=$(wp --version 2>/dev/null | grep -o '[0-9]\+\.[0-9]\+[0-9.]*' | head -1 || echo "unknown")
    printf "    WP-CLI version: $wp_version\n"

    # Check if version is recent enough (2.0+)
    if [[ "$wp_version" != "unknown" ]]; then
        local major_version=$(echo "$wp_version" | cut -d. -f1)
        if [[ $major_version -ge 2 ]]; then
            printf "    ✅ WP-CLI version is compatible\n"
        else
            printf "    ⚠️  WP-CLI version may be too old\n"
        fi
    fi

    # Test WP-CLI search-replace availability
    if wp help search-replace >/dev/null 2>&1; then
        printf "    ✅ WP-CLI search-replace command available\n"
    else
        printf "    ❌ WP-CLI search-replace command not available\n"
        ((wp_cli_issues++))
    fi

    # Test other essential WP-CLI commands
    local essential_commands="core cache db"
    for cmd in $essential_commands; do
        if wp help "$cmd" >/dev/null 2>&1; then
            printf "    ✅ WP-CLI $cmd command available\n"
        else
            printf "    ❌ WP-CLI $cmd command not available\n"
            ((wp_cli_issues++))
        fi
    done

    if [[ $wp_cli_issues -eq 0 ]]; then
        pass_test "WP-CLI integration tests passed"
    else
        fail_test "$wp_cli_issues WP-CLI integration issues"
    fi
}

# ===============================================
# Test configuration file handling
# ===============================================
#
# Description: Tests the ability of the script to correctly load, parse, and validate
#              variables from an external configuration file (e.g., `config.conf`).
#
# Parameters:
#   - None.
#
# Returns:
#   - Calls `pass_test` or `fail_test`.
#
# Behavior:
#   - Creates a temporary test configuration file with valid and invalid entries.
#   - Requires external functions like `load_config` and `validate_config`.
#
test_config_file_handling() {
    start_test "Config File Handling" "Test configuration file reading and validation"

    local config_issues=0
    local temp_dir=$(create_temp_test_dir "config_test")
    cd "$temp_dir" || return 1

    printf "  Testing configuration file functionality...\n"

    cat > "test-config.conf" <<EOF
[general]
sql_file=production-db.sql
old_domain=old-site.com
new_domain=new-site.local
all_tables=true
dry_run=false
clear_revisions=true
setup_stage_proxy=false
auto_proceed=false
use_socket=false
backup_before_import=false
backup_keep=3

[site_mappings]
1:old-site.com:new-site.local
2:blog.old-site.com:new-site.local/blog
EOF

    if ! source "$PROJECT_ROOT_DIR/import_wp_db.sh" >/dev/null 2>&1; then
        cd / && cleanup_temp_test_dir "$temp_dir"
        fail_test "Failed to load main script"
        return 1
    fi
    local fn
    for fn in load_import_config validate_config_file parse_config_section; do
        if ! declare -F "$fn" >/dev/null 2>&1; then
            printf "    ❌ core function %s is missing\n" "$fn"
            ((config_issues++))
        fi
    done

    if declare -F load_import_config >/dev/null 2>&1; then
        load_import_config "test-config.conf" >/dev/null 2>&1
        [[ "$CONFIG_OLD_DOMAIN" == "old-site.com" && "$CONFIG_NEW_DOMAIN" == "new-site.local" ]] \
            && printf "    ✅ domains loaded from the config file\n" \
            || { printf "    ❌ domains not loaded (%s -> %s)\n" "$CONFIG_OLD_DOMAIN" "$CONFIG_NEW_DOMAIN"; ((config_issues++)); }
        [[ "$CONFIG_USE_SOCKET" == "false" && "$CONFIG_BACKUP_BEFORE_IMPORT" == "false" && "$CONFIG_BACKUP_KEEP" == "3" ]] \
            && printf "    ✅ import, backup and rotation settings loaded\n" \
            || { printf "    ❌ settings not loaded (socket=%s backup=%s keep=%s)\n" "$CONFIG_USE_SOCKET" "$CONFIG_BACKUP_BEFORE_IMPORT" "$CONFIG_BACKUP_KEEP"; ((config_issues++)); }
    fi

    if declare -F validate_config_file >/dev/null 2>&1; then
        validate_config_file "test-config.conf" >/dev/null 2>&1 \
            && printf "    ✅ configuration validation accepts a valid file\n" \
            || { printf "    ❌ a valid configuration was rejected\n"; ((config_issues++)); }
    fi

    # Invalid configuration handling
    printf "  Testing invalid configuration handling...\n"
    cat > "invalid-config.conf" <<EOF
# no [general] section and no mappings
OLD_DOMAIN=old-site.com
EOF
    if declare -F validate_config_file >/dev/null 2>&1; then
        if validate_config_file "invalid-config.conf" >/dev/null 2>&1; then
            printf "    ❌ an invalid configuration was accepted\n"
            ((config_issues++))
        else
            printf "    ✅ invalid configuration correctly rejected\n"
        fi
    fi

    cd / && cleanup_temp_test_dir "$temp_dir"

    if [[ $config_issues -eq 0 ]]; then
        pass_test "Configuration file handling tests passed"
    else
        fail_test "$config_issues configuration handling issues"
    fi
}

# ===============================================
# Test database domain detection (including multisite right after an import)
# ===============================================
#
# Description:
#   After an import into a multisite, `wp option get siteurl` cannot start because wp-config.php
#   names the local network domain while the database still has the production one. The domain
#   must then be read from the database directly (wp_site, then wp_options).
#
test_database_domain_detection() {
    start_test "Database Domain Detection" "domain is found via WP-CLI, or from the database when WP-CLI cannot start"

    if ! source "$PROJECT_ROOT_DIR/import_wp_db.sh" >/dev/null 2>&1; then
        fail_test "Failed to load main script"
        return 1
    fi
    if ! declare -F detect_database_domain >/dev/null 2>&1; then
        fail_test "core function detect_database_domain is missing"
        return 1
    fi

    local issues=0 out queries
    local root; root=$(create_temp_test_dir "domain_detect")
    printf "<?php\n\$table_prefix = 'wpx_';\n" > "$root/wp-config.php"
    export WP_COMMAND="/bin/true"
    queries="$root/queries.log"; : > "$queries"

    # 1) WP-CLI works: its answer is used
    execute_wp_cli() { [[ "$1 $2" == "option get" && "$3" == "siteurl" ]] && { echo "https://wpcli.example.com/path"; return 0; }; return 1; }
    out=$(detect_database_domain "$root")
    [[ "$out" == "wpcli.example.com" ]] && printf "    ✅ domain read through WP-CLI\n" || { printf "    ❌ expected wpcli.example.com, got '%s'\n" "$out"; ((issues++)); }

    # 2) WP-CLI cannot start (multisite after import): wp_site is read from the database
    execute_wp_cli() { return 1; }
    _import_db_query() { printf '%s\n' "$1" >> "$queries"; case "$1" in *"wpx_site"*) echo "prod.example.com";; esac; }
    out=$(detect_database_domain "$root")
    [[ "$out" == "prod.example.com" ]] && printf "    ✅ domain read from wp_site when WP-CLI cannot start\n" || { printf "    ❌ expected prod.example.com, got '%s'\n" "$out"; ((issues++)); }
    grep -q 'FROM `wpx_site`' "$queries" && printf "    ✅ the table prefix from wp-config.php is used\n" || { printf "    ❌ prefix not used\n"; ((issues++)); }

    # 3) wp_site is empty: wp_options siteurl is the next source (scheme and path are stripped)
    _import_db_query() { case "$1" in *"wpx_options"*) echo "https://opts.example.com/blog";; esac; }
    out=$(detect_database_domain "$root")
    [[ "$out" == "opts.example.com" ]] && printf "    ✅ falls back to the siteurl option\n" || { printf "    ❌ expected opts.example.com, got '%s'\n" "$out"; ((issues++)); }

    # 4) nothing works: failure (the caller prints its warning)
    _import_db_query() { return 1; }
    detect_database_domain "$root" >/dev/null 2>&1
    [[ $? -ne 0 ]] && printf "    ✅ returns failure when no source works\n" || { printf "    ❌ should fail\n"; ((issues++)); }

    # 5) a hostile table prefix never reaches SQL
    printf "<?php\n\$table_prefix = 'wp_\`; DROP TABLE x; --';\n" > "$root/wp-config.php"
    : > "$queries"; _import_db_query() { printf '%s\n' "$1" >> "$queries"; }
    detect_database_domain "$root" >/dev/null 2>&1
    [[ ! -s "$queries" ]] && printf "    ✅ an unsafe table prefix is refused before any SQL is built\n" || { printf "    ❌ unsafe prefix reached SQL: %s\n" "$(cat "$queries")"; ((issues++)); }

    unset -f execute_wp_cli _import_db_query
    cd / && cleanup_temp_test_dir "$root"
    if [[ $issues -eq 0 ]]; then
        pass_test "database domain detection works"
    else
        fail_test "$issues domain detection issue(s)"
    fi
}

# ===============================================
# Test: no printf format can be read as an option
# ===============================================
#
# Description:
#   `printf "${CYAN}-- text"` is fine on a terminal but, with colors off (CI, pipes, NO_COLOR),
#   the format starts with "--" and printf fails with "invalid option". Such formats need `printf --`.
#
test_printf_dash_guard() {
    start_test "printf Dash Guard" "no printf format starts with a dash after empty color variables"
    local hits
    hits=$(grep -rnE 'printf "(\$\{[A-Za-z_]+\}|\$[A-Za-z_]+)*-' \
        "$PROJECT_ROOT_DIR/import_wp_db.sh" "$PROJECT_ROOT_DIR/wp-db-import" "$PROJECT_ROOT_DIR/uninstall.sh" "$PROJECT_ROOT_DIR/install.sh" \
        "$PROJECT_ROOT_DIR"/lib/core "$PROJECT_ROOT_DIR"/lib/config "$PROJECT_ROOT_DIR"/lib/database "$PROJECT_ROOT_DIR"/lib/utilities 2>/dev/null \
        | grep -vE ':[0-9]+:\s*#|printf --')
    if [[ -z "$hits" ]]; then
        pass_test "every printf that may start with a dash uses --"
    else
        printf "%s\n" "$hits" | sed 's/^/    /'
        fail_test "printf formats that can start with a dash found (use printf --)"
    fi
}

# ===============================================
# Test domain sanitization
# ===============================================
#
# Description: Verifies that the domain and URL sanitization functions correctly
#              clean up user input, removing protocols (`http://`, `https://`) and
#              trailing slashes, while preserving essential components like ports or subdomains.
#
# Parameters:
#   - None.
#
# Returns:
#   - Calls `pass_test` or `fail_test`.
#
# Behavior:
#   - Uses an array of inputs and expected outputs to test edge cases.
#   - Requires the external function `sanitize_domain`.
#
test_domain_sanitization() {
    start_test "Domain Sanitization" "Test domain and URL sanitization functionality"

    local sanitization_issues=0

    printf "  Testing domain sanitization...\n"

    # Test cases for domain sanitization using separate arrays
    local test_inputs=(
        "https://example.com/"
        "http://example.com"
        "example.com/"
        "www.example.com"
        "subdomain.example.com"
        "example.com:8080"
    )

    local expected_outputs=(
        "example.com"
        "example.com"
        "example.com"
        "www.example.com"
        "subdomain.example.com"
        "example.com:8080"
    )

    # Load the main script to get sanitization functions
    if source "$PROJECT_ROOT_DIR/import_wp_db.sh" >/dev/null 2>&1; then
        if declare -F sanitize_domain >/dev/null 2>&1; then
            for i in "${!test_inputs[@]}"; do
                local input="${test_inputs[$i]}"
                local expected="${expected_outputs[$i]}"
                local result=$(sanitize_domain "$input" 2>/dev/null || echo "$input")

                if [[ "$result" == "$expected" ]]; then
                    printf "    ✅ '$input' → '$result'\n"
                else
                    printf "    ❌ '$input' → '$result' (expected '$expected')\n"
                    ((sanitization_issues++))
                fi
            done
        else
            printf "    ❌ core function sanitize_domain is missing\n"
            ((sanitization_issues++))
        fi
    fi

    if [[ $sanitization_issues -eq 0 ]]; then
        pass_test "Domain sanitization tests passed"
    else
        fail_test "$sanitization_issues domain sanitization issues"
    fi
}

# ===============================================
# Test search and replace functionality
# ===============================================
#
# Description: Validates the readiness and logic of the database search and replace
#              functions, particularly checking for the ability to handle serialized data
#              and different URL patterns.
#
# Parameters:
#   - None.
#
# Returns:
#   - Calls `pass_test` or `fail_test`.
#
# Behavior:
#   - Checks for the availability of `perform_search_replace` and `dry_run_search_replace`.
#   - Validates the test serialized string against the expected result.
#   - Note: Actual execution of WP-CLI commands is simulated or skipped in favor of logic checks.
#
test_search_replace() {
    start_test "Search Replace Functionality" "Test database search and replace operations"

    local search_replace_issues=0

    printf "  Testing search and replace logic...\n"

    if ! source "$PROJECT_ROOT_DIR/import_wp_db.sh" >/dev/null 2>&1; then
        fail_test "Failed to load main script"
        return 1
    fi
    if ! declare -F run_search_replace >/dev/null 2>&1; then
        fail_test "core function run_search_replace is missing"
        return 1
    fi

    # WP-CLI is replaced by a recorder, so the exact commands the tool would run can be checked
    local log
    log=$(mktemp "${TMPDIR:-/tmp}/wpdb-sr-test.XXXXXX")
    execute_wp_cli() { printf 'CALL:'; printf ' [%s]' "$@"; printf '\n'; return "${SR_STUB_RC:-0}"; }

    local all_tables_flag="--all-tables" dry_run_flag=""

    # Plain domain: protocol-relative pass plus the escaped (serialized/JSON) pass
    : > "$log"
    run_search_replace "old-site.com" "new-site.local" "$log" "" >/dev/null 2>&1
    local rc=$? calls; calls=$(grep -c '^CALL:' "$log")
    [[ $rc -eq 0 ]] && printf "    ✅ search-replace succeeds\n" || { printf "    ❌ search-replace failed (rc=%s)\n" "$rc"; ((search_replace_issues++)); }
    [[ "$calls" == "2" ]] && printf "    ✅ two passes: plain and escaped\n" || { printf "    ❌ expected 2 passes, got %s\n" "$calls"; ((search_replace_issues++)); }
    grep -qF '[search-replace] [//old-site.com] [//new-site.local]' "$log" \
        && printf "    ✅ protocol-independent pass (//old-site.com -> //new-site.local)\n" \
        || { printf "    ❌ missing protocol-independent pass\n"; ((search_replace_issues++)); }
    grep -qF '[\\//old-site.com] [\\//new-site.local]' "$log" \
        && printf "    ✅ escaped pass for serialized and JSON data\n" \
        || { printf "    ❌ missing escaped pass\n"; ((search_replace_issues++)); }
    [[ "$(grep -c -- '--skip-columns=guid' "$log")" == "2" ]] && printf "    ✅ guid column is never changed\n" || { printf "    ❌ guid not skipped\n"; ((search_replace_issues++)); }
    [[ "$(grep -c -- '--all-tables' "$log")" == "2" ]] && printf "    ✅ --all-tables is passed through\n" || { printf "    ❌ --all-tables missing\n"; ((search_replace_issues++)); }
    ! grep -q -- '--dry-run' "$log" && printf "    ✅ no --dry-run in live mode\n" || { printf "    ❌ --dry-run present in live mode\n"; ((search_replace_issues++)); }

    # Dry run
    dry_run_flag="--dry-run"; : > "$log"
    run_search_replace "old-site.com" "new-site.local" "$log" "" >/dev/null 2>&1
    [[ "$(grep -c -- '--dry-run' "$log")" == "2" ]] && printf "    ✅ dry-run flag reaches every pass\n" || { printf "    ❌ dry-run flag missing\n"; ((search_replace_issues++)); }
    dry_run_flag=""

    # Without --all-tables
    all_tables_flag=""; : > "$log"
    run_search_replace "old-site.com" "new-site.local" "$log" "" >/dev/null 2>&1
    ! grep -q -- '--all-tables' "$log" && printf "    ✅ --all-tables is optional\n" || { printf "    ❌ --all-tables forced\n"; ((search_replace_issues++)); }
    all_tables_flag="--all-tables"

    # www domain gets its own passes
    : > "$log"
    run_search_replace "www.old-site.com" "new-site.local" "$log" "" >/dev/null 2>&1
    calls=$(grep -c '^CALL:' "$log")
    [[ "$calls" -ge 4 ]] && printf "    ✅ www domain adds extra passes (%s)\n" "$calls" || { printf "    ❌ www domain: expected 4+ passes, got %s\n" "$calls"; ((search_replace_issues++)); }

    # Multisite context: --url and --network are honored
    : > "$log"
    run_search_replace "old-site.com" "new-site.local" "$log" "--network" >/dev/null 2>&1
    grep -q -- '--network' "$log" && printf "    ✅ --network is passed for multisite\n" || { printf "    ❌ --network missing\n"; ((search_replace_issues++)); }
    : > "$log"
    run_search_replace "old-site.com" "new-site.local" "$log" "--url=blog.old-site.com" "/blog/" "/blog/" >/dev/null 2>&1
    grep -q -- '--url=blog.old-site.com' "$log" && printf "    ✅ --url is passed for a subsite\n" || { printf "    ❌ --url missing\n"; ((search_replace_issues++)); }

    # Failure and bad input
    : > "$log"
    SR_STUB_RC=1 run_search_replace "old-site.com" "new-site.local" "$log" "" >/dev/null 2>&1
    [[ $? -ne 0 ]] && printf "    ✅ a failing WP-CLI call makes the function fail\n" || { printf "    ❌ failure was swallowed\n"; ((search_replace_issues++)); }
    run_search_replace "" "new-site.local" "$log" "" >/dev/null 2>&1
    [[ $? -ne 0 ]] && printf "    ✅ missing domain is rejected\n" || { printf "    ❌ missing domain accepted\n"; ((search_replace_issues++)); }

    unset -f execute_wp_cli
    rm -f "$log"

    if [[ $search_replace_issues -eq 0 ]]; then
        pass_test "Search/replace tests passed"
    else
        fail_test "$search_replace_issues search/replace issues"
    fi
}

# ===============================================
# Test multisite handling
# ===============================================
#
# Description: Verifies the ability to correctly detect and differentiate between
#              subdirectory and subdomain WordPress Multisite installations.
#
# Parameters:
#   - None.
#
# Returns:
#   - Calls `pass_test` or `fail_test`.
#
# Behavior:
#   - Creates a mock Multisite `wp-config.php` file.
#   - Tests subdirectory detection, then modifies the config to test subdomain detection.
#   - Requires external functions like `detect_wp_type` and `get_multisite_type`.
#
test_multisite_handling() {
    start_test "Multisite Handling" "Test WordPress multisite functionality"

    local multisite_issues=0

    printf "  Testing multisite detection and handling...\n"

    # Create temporary test environment with multisite configuration
    local temp_dir=$(create_temp_test_dir "multisite_test")
    cd "$temp_dir" || return 1

    # Create multisite wp-config.php
    cat > "wp-config.php" <<EOF
<?php
define('DB_NAME', 'test_multisite_db');
define('DB_USER', 'test_user');
define('DB_PASSWORD', 'test_pass');
define('DB_HOST', 'localhost');

define('MULTISITE', true);
define('SUBDOMAIN_INSTALL', false);
define('DOMAIN_CURRENT_SITE', 'main-site.com');
define('PATH_CURRENT_SITE', '/');
define('SITE_ID_CURRENT_SITE', 1);
define('BLOG_ID_CURRENT_SITE', 1);
EOF

    # Test multisite detection
    if source "$PROJECT_ROOT_DIR/import_wp_db.sh" >/dev/null 2>&1; then
        if declare -F detect_wp_type >/dev/null 2>&1; then
            local wp_type=$(detect_wp_type "$temp_dir" 2>/dev/null)
            if [[ "$wp_type" == *"multisite"* ]]; then
                printf "    ✅ Multisite correctly detected\n"
            else
                printf "    ❌ Multisite not detected (got: $wp_type)\n"
                ((multisite_issues++))
            fi
        fi

        # Test subdirectory vs subdomain detection
        if declare -F get_multisite_type >/dev/null 2>&1; then
            local multisite_type=$(get_multisite_type "$temp_dir" 2>/dev/null)
            if [[ "$multisite_type" == "subdirectory" ]]; then
                printf "    ✅ Subdirectory multisite correctly detected\n"
            else
                printf "    ⚠️  Multisite type: $multisite_type\n"
            fi
        fi
    fi

    # Test subdomain multisite configuration
    sed -i.bak 's/define('"'"'SUBDOMAIN_INSTALL'"'"', false);/define('"'"'SUBDOMAIN_INSTALL'"'"', true);/' wp-config.php

    if source "$PROJECT_ROOT_DIR/import_wp_db.sh" >/dev/null 2>&1; then
        if declare -F get_multisite_type >/dev/null 2>&1; then
            local multisite_type=$(get_multisite_type "$temp_dir" 2>/dev/null)
            if [[ "$multisite_type" == "subdomain" ]]; then
                printf "    ✅ Subdomain multisite correctly detected\n"
            else
                printf "    ⚠️  Multisite type: $multisite_type\n"
            fi
        fi
    fi

    # Cleanup
    cd / && cleanup_temp_test_dir "$temp_dir"

    if [[ $multisite_issues -eq 0 ]]; then
        pass_test "Multisite handling tests passed"
    else
        fail_test "$multisite_issues multisite handling issues"
    fi
}

# ===============================================
# Test error handling and edge cases
# ===============================================
#
# Description: Verifies the script's robustness in handling common failure scenarios,
#              including missing files, invalid configuration syntax, unreadable files,
#              and incorrect directory structure.
#
# Parameters:
#   - None.
#
# Returns:
#   - Calls `pass_test` or `fail_test`.
#
# Behavior:
#   - Explicitly tests `import_sql_file` with a non-existent file.
#   - Tests `find_wp_root` in a directory lacking a valid config.
#   - Tests `validate_wp_config` and `read_wp_config` with corrupted or permission-restricted files.
#
test_error_handling() {
    start_test "Error Handling" "Test error handling and edge case scenarios"

    local error_handling_issues=0

    printf "  Testing error handling scenarios...\n"

    # Test handling of missing files
    local temp_dir=$(create_temp_test_dir "error_test")
    cd "$temp_dir" || return 1

    # Test importing non-existent SQL file
    if source "$PROJECT_ROOT_DIR/import_wp_db.sh" >/dev/null 2>&1; then
        # This should fail gracefully
        if declare -F import_sql_file >/dev/null 2>&1; then
            if import_sql_file "nonexistent.sql" >/dev/null 2>&1; then
                printf "    ❌ Non-existent SQL file import should fail\n"
                ((error_handling_issues++))
            else
                printf "    ✅ Non-existent SQL file correctly rejected\n"
            fi
        fi
    fi

    # Test handling of invalid WordPress directory
    if source "$PROJECT_ROOT_DIR/import_wp_db.sh" >/dev/null 2>&1; then
        if declare -F find_wp_root >/dev/null 2>&1; then
            local wp_root=$(find_wp_root 2>/dev/null)
            if [[ -z "$wp_root" ]]; then
                printf "    ✅ Invalid WordPress directory correctly detected\n"
            else
                printf "    ❌ Invalid WordPress directory not detected\n"
                ((error_handling_issues++))
            fi
        fi
    fi

    # Test handling of corrupted wp-config.php
    echo "This is not a valid PHP file" > wp-config.php

    if source "$PROJECT_ROOT_DIR/import_wp_db.sh" >/dev/null 2>&1; then
        if declare -F validate_wp_config >/dev/null 2>&1; then
            if validate_wp_config "wp-config.php" >/dev/null 2>&1; then
                printf "    ❌ Corrupted wp-config.php should be rejected\n"
                ((error_handling_issues++))
            else
                printf "    ✅ Corrupted wp-config.php correctly rejected\n"
            fi
        fi
    fi

    # Test handling of permission issues
    chmod 000 wp-config.php 2>/dev/null

    if source "$PROJECT_ROOT_DIR/import_wp_db.sh" >/dev/null 2>&1; then
        if declare -F read_wp_config >/dev/null 2>&1; then
            if read_wp_config "wp-config.php" >/dev/null 2>&1; then
                printf "    ❌ Unreadable wp-config.php should be rejected\n"
                ((error_handling_issues++))
            else
                printf "    ✅ Unreadable wp-config.php correctly rejected\n"
            fi
        fi
    fi

    chmod 644 wp-config.php 2>/dev/null  # Restore permissions for cleanup

    # Cleanup
    cd / && cleanup_temp_test_dir "$temp_dir"

    if [[ $error_handling_issues -eq 0 ]]; then
        pass_test "Error handling tests passed"
    else
        fail_test "$error_handling_issues error handling issues"
    fi
}

# ===============================================
# Test cleanup and maintenance functions
# ===============================================
#
# Description: Verifies the availability of post-import maintenance and cleanup
#              functions, such as clearing cache, optimizing the database (revisions),
#              and cleaning up temporary files.
#
# Parameters:
#   - None.
#
# Returns:
#   - Calls `pass_test` or `fail_test`.
#
# Behavior:
#   - Checks for the availability of `show_revision_cleanup_commands`, `clear_wp_cache`, and `cleanup_temp_files`.
#
test_cleanup_functions() {
    start_test "Cleanup Functions" "Test cleanup and maintenance functionality"

    local cleanup_issues=0

    printf "  Testing cleanup functionality...\n"

    if ! source "$PROJECT_ROOT_DIR/import_wp_db.sh" >/dev/null 2>&1; then
        fail_test "Failed to load main script"
        return 1
    fi

    local fn
    for fn in show_revision_cleanup_commands clean_revisions_silent cleanup secure_tmpdir secure_tmpdir_cleanup; do
        if declare -F "$fn" >/dev/null 2>&1; then
            printf "    ✅ %s is available\n" "$fn"
        else
            printf "    ❌ core function %s is missing\n" "$fn"
            ((cleanup_issues++))
        fi
    done

    # The temp-file cleanup really removes the private directory and logs
    if declare -F cleanup >/dev/null 2>&1 && declare -F secure_tmpdir >/dev/null 2>&1; then
        local base d
        base=$(mktemp -d "${TMPDIR:-/tmp}/wpdb-cleanup-test.XXXXXX")
        d=$(TMPDIR="$base" secure_tmpdir)
        echo "log" > "$d/db_import.log"
        ( export TMPDIR="$base"; DB_LOG="$d/db_import.log" cleanup >/dev/null 2>&1 )
        if [[ -z "$(ls -A "$base")" ]]; then
            printf "    ✅ cleanup removes temporary logs and the private directory\n"
        else
            printf "    ❌ cleanup left files behind: %s\n" "$(ls -A "$base")"
            ((cleanup_issues++))
        fi
        rm -rf "$base"
    fi

    # Cache and rewrite flushing run inside the import itself; they are verified by the real
    # end-to-end import test (lib/tests/integration/test_real_import.sh).

    if [[ $cleanup_issues -eq 0 ]]; then
        pass_test "Cleanup function tests passed"
    else
        fail_test "$cleanup_issues cleanup function issues"
    fi
}

# ===============================================
# Run all WordPress specific tests
# ===============================================
#
# Description: The primary entry point function that initializes the test session
#              and executes all individual WordPress functionality test functions.
#
# Parameters:
#   - None.
#
# Returns:
#   - The exit code of the final `finalize_test_session` call (0 on success, non-zero on failure).
#
# Behavior:
#   - Calls `init_test_session`.
#   - Executes all `test_*` functions in logical order by dependency and feature group.
#   - Calls `finalize_test_session`.
#
run_wordpress_tests() {
    init_test_session "wordpress_functionality"

    printf "${CYAN}${BOLD}🔧 WordPress Functionality Tests${RESET}\n"
    printf "${DIM}Testing WordPress-specific features and scenarios${RESET}\n\n"

    # Core WordPress functionality tests
    test_wordpress_detection
    test_wp_cli_integration
    test_config_file_handling

    # Domain and URL handling tests
    test_database_domain_detection
    test_printf_dash_guard
    test_domain_sanitization
    test_search_replace

    # WordPress type specific tests
    test_multisite_handling

    # Robustness tests
    test_error_handling
    test_cleanup_functions

    finalize_test_session
    return $?
}

# Run tests if this script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    run_wordpress_tests
fi
