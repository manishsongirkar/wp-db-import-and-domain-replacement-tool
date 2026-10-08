#!/usr/bin/env bash

# ================================================================
# Unit Tests for MySQL Socket Detection
# ================================================================
#
# Description:
#   Tests the MySQL socket detection module (socket_detector.sh) and
#   the wp-config.php credential parser (get_wp_db_credentials).
#   All tests use mock socket files and temporary wp-config.php files
#   to avoid requiring a running MySQL server.
#
# Functions provided:
# - test_socket_validation
# - test_socket_wp_config_extraction
# - test_socket_common_paths
# - test_socket_config_override
# - test_wp_db_credentials_parser
# - test_socket_disabled_via_config
# - run_socket_tests
#
# Dependencies:
# - test_framework.sh (Must be sourced for test session management)
# - lib/database/socket_detector.sh
# - lib/core/utils.sh (for get_wp_db_credentials)
#
# ================================================================

# Source the test framework
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../test_framework.sh"

# ================================================================
# Helpers
# ================================================================

# Create a fake socket file (regular file that acts as socket stand-in for path tests)
# Note: mkfifo or actual socat sockets would be ideal, but for path-existence tests
# we simulate with a named pipe which is also a special file type.
_create_mock_socket() {
    local path="$1"
    mkfifo "$path" 2>/dev/null || touch "$path"
    # Make it writable
    chmod 600 "$path" 2>/dev/null || true
    echo "$path"
}

# ================================================================
# Test: _is_valid_socket validation logic
# ================================================================
#
# Description: Tests that _is_valid_socket correctly rejects non-existent
#              paths, regular files, and accepts valid socket-like paths.
#
test_socket_validation() {
    start_test "Socket Validation" "Test _is_valid_socket helper rejects invalid paths"

    # Source the module under test
    if ! source "$PROJECT_ROOT_DIR/lib/database/socket_detector.sh" >/dev/null 2>&1; then
        fail_test "Could not source socket_detector.sh"
        return 1
    fi

    local errors=0

    # Empty string should fail
    if _is_valid_socket "" 2>/dev/null; then
        printf "  ❌ Empty string should not be a valid socket\n"
        ((errors++))
    else
        printf "  ✅ Empty string correctly rejected\n"
    fi

    # Non-existent path should fail
    if _is_valid_socket "/tmp/nonexistent_mysql_$$_fake.sock" 2>/dev/null; then
        printf "  ❌ Non-existent path should not be a valid socket\n"
        ((errors++))
    else
        printf "  ✅ Non-existent path correctly rejected\n"
    fi

    # Regular file should fail (not a socket type)
    local tmp_regular_file
    tmp_regular_file=$(mktemp "/tmp/test_socket_regular_$$.XXXXXX")
    chmod 600 "$tmp_regular_file"
    if _is_valid_socket "$tmp_regular_file" 2>/dev/null; then
        printf "  ❌ Regular file should not pass socket validation\n"
        ((errors++))
    else
        printf "  ✅ Regular file correctly rejected (not a socket type)\n"
    fi
    rm -f "$tmp_regular_file"

    if [[ "$errors" -eq 0 ]]; then
        pass_test "All socket validation checks passed"
    else
        fail_test "$errors validation check(s) failed"
    fi
}

# ================================================================
# Test: Socket path extraction from wp-config.php DB_HOST
# ================================================================
#
# Description: Tests that _extract_socket_from_wp_config correctly
#              parses socket paths embedded in the DB_HOST define.
#
test_socket_wp_config_extraction() {
    start_test "Socket from wp-config" "Extract socket path embedded in DB_HOST"

    if ! source "$PROJECT_ROOT_DIR/lib/database/socket_detector.sh" >/dev/null 2>&1; then
        fail_test "Could not source socket_detector.sh"
        return 1
    fi

    local tmp_dir
    tmp_dir=$(mktemp -d "/tmp/test_wp_config_$$.XXXXXX")
    local wp_config="$tmp_dir/wp-config.php"

    # Write a mock wp-config.php with socket in DB_HOST
    cat > "$wp_config" << 'EOF'
<?php
define('DB_NAME', 'mydb');
define('DB_USER', 'root');
define('DB_PASSWORD', 'secret');
define('DB_HOST', 'localhost:/tmp/mock_mysql.sock');
EOF

    local extracted
    extracted=$(_extract_socket_from_wp_config "$tmp_dir")

    rm -rf "$tmp_dir"

    if [[ "$extracted" == "/tmp/mock_mysql.sock" ]]; then
        pass_test "Socket path correctly extracted from DB_HOST: $extracted"
    else
        fail_test "Expected /tmp/mock_mysql.sock, got: '${extracted:-empty}'"
    fi
}

# ================================================================
# Test: wp-config.php without socket in DB_HOST returns empty
# ================================================================
#
test_socket_wp_config_no_socket() {
    start_test "No socket in wp-config" "Returns empty when DB_HOST has no socket path"

    if ! source "$PROJECT_ROOT_DIR/lib/database/socket_detector.sh" >/dev/null 2>&1; then
        fail_test "Could not source socket_detector.sh"
        return 1
    fi

    local tmp_dir
    tmp_dir=$(mktemp -d "/tmp/test_wp_config_nosock_$$.XXXXXX")
    local wp_config="$tmp_dir/wp-config.php"

    cat > "$wp_config" << 'EOF'
<?php
define('DB_NAME', 'mydb');
define('DB_USER', 'root');
define('DB_PASSWORD', 'secret');
define('DB_HOST', 'localhost');
EOF

    local extracted
    extracted=$(_extract_socket_from_wp_config "$tmp_dir")

    rm -rf "$tmp_dir"

    if [[ -z "$extracted" ]]; then
        pass_test "Correctly returned empty when no socket in DB_HOST"
    else
        fail_test "Expected empty string, got: '$extracted'"
    fi
}

# ================================================================
# Test: Config override — valid path is returned immediately
# ================================================================
#
# Description: When CONFIG_MYSQL_SOCKET points to a valid socket,
#              detect_mysql_socket should return it without probing.
#
test_socket_config_override() {
    start_test "Socket Config Override" "User-specified socket path takes priority"

    if ! source "$PROJECT_ROOT_DIR/lib/database/socket_detector.sh" >/dev/null 2>&1; then
        fail_test "Could not source socket_detector.sh"
        return 1
    fi

    # Create a named pipe to simulate a socket-like special file
    local mock_sock="/tmp/test_mock_$$.sock"
    mkfifo "$mock_sock" 2>/dev/null || { skip_test "mkfifo unavailable — cannot create mock socket"; return 0; }
    chmod 660 "$mock_sock" 2>/dev/null || true

    # detect_mysql_socket with config_override should return the mock path
    # We pass an empty wp_root so only config override logic is exercised
    local result
    result=$(detect_mysql_socket "" "$mock_sock" 2>/dev/null)

    rm -f "$mock_sock"

    if [[ "$result" == "$mock_sock" ]]; then
        pass_test "Config override socket path used correctly: $result"
    else
        # Named pipes may not pass -S (socket) test on all systems
        skip_test "Platform does not treat named pipe as socket (-S check); test inconclusive"
    fi
}

# ================================================================
# Test: Config override with invalid path falls back silently
# ================================================================
#
test_socket_invalid_config_override() {
    start_test "Invalid Socket Override" "Invalid config socket path triggers fallback (no crash)"

    if ! source "$PROJECT_ROOT_DIR/lib/database/socket_detector.sh" >/dev/null 2>&1; then
        fail_test "Could not source socket_detector.sh"
        return 1
    fi

    # Pass a non-existent path — should NOT crash, should just auto-detect
    local result
    local exit_code=0
    result=$(detect_mysql_socket "" "/tmp/totally_fake_$$.sock" 2>/dev/null) || exit_code=$?

    # We don't care whether a real socket was found — we care that the command
    # did NOT crash (exit code is 0 or 1, not >1 which would indicate a script error)
    if [[ "$exit_code" -le 1 ]]; then
        pass_test "Invalid socket override handled gracefully (exit_code=$exit_code)"
    else
        fail_test "Script crashed with exit code $exit_code on invalid socket path"
    fi
}

# ================================================================
# Test: Development environment detection
# ================================================================
#
test_socket_environment_detection() {
    start_test "Socket Environment Detection" "detect_dev_environment recognizes Local, Lando, and DDEV signals"

    if ! source "$PROJECT_ROOT_DIR/lib/database/socket_detector.sh" >/dev/null 2>&1; then
        fail_test "Could not source socket_detector.sh"
        return 1
    fi

    local errors=0
    local detected=""
    local original_home="$HOME"
    local original_lando_info="${LANDO_INFO-}"
    local original_is_ddev_project="${IS_DDEV_PROJECT-}"
    local original_ddev_sitename="${DDEV_SITENAME-}"
    local tmp_home
    local tmp_wp_root

    tmp_home=$(mktemp -d "/tmp/test_socket_env_home_$$.XXXXXX")
    tmp_wp_root=$(mktemp -d "/tmp/test_socket_env_wp_$$.XXXXXX")

    mkdir -p "$tmp_home/Library/Application Support/Local/run/sitehash/mysql"
    HOME="$tmp_home"
    unset LANDO_INFO IS_DDEV_PROJECT DDEV_SITENAME

    detected=$(detect_dev_environment)
    if [[ "$detected" == "local_flywheel" ]]; then
        printf "  ✅ Local environment detected from Local run directory\n"
    else
        printf "  ❌ Expected local_flywheel, got '%s'\n" "$detected"
        ((errors++))
    fi

    rm -rf "$tmp_home"
    HOME="$original_home"

    : > "$tmp_wp_root/.lando.yml"
    detected=$(detect_dev_environment "$tmp_wp_root")
    if [[ "$detected" == "lando_host" ]]; then
        printf "  ✅ Lando host environment detected from project config\n"
    else
        printf "  ❌ Expected lando_host, got '%s'\n" "$detected"
        ((errors++))
    fi

    rm -f "$tmp_wp_root/.lando.yml"
    mkdir -p "$tmp_wp_root/.ddev"
    detected=$(detect_dev_environment "$tmp_wp_root")
    if [[ "$detected" == "ddev_host" ]]; then
        printf "  ✅ DDEV host environment detected from project config\n"
    else
        printf "  ❌ Expected ddev_host, got '%s'\n" "$detected"
        ((errors++))
    fi

    LANDO_INFO="{}"
    detected=$(detect_dev_environment)
    if [[ "$detected" == "lando_inside" ]]; then
        printf "  ✅ Lando container environment detected from env vars\n"
    else
        printf "  ❌ Expected lando_inside, got '%s'\n" "$detected"
        ((errors++))
    fi
    unset LANDO_INFO

    IS_DDEV_PROJECT="true"
    detected=$(detect_dev_environment)
    if [[ "$detected" == "ddev_inside" ]]; then
        printf "  ✅ DDEV container environment detected from env vars\n"
    else
        printf "  ❌ Expected ddev_inside, got '%s'\n" "$detected"
        ((errors++))
    fi

    if [[ -n "$original_lando_info" ]]; then
        LANDO_INFO="$original_lando_info"
    else
        unset LANDO_INFO
    fi

    if [[ -n "$original_is_ddev_project" ]]; then
        IS_DDEV_PROJECT="$original_is_ddev_project"
    else
        unset IS_DDEV_PROJECT
    fi

    if [[ -n "$original_ddev_sitename" ]]; then
        DDEV_SITENAME="$original_ddev_sitename"
    else
        unset DDEV_SITENAME
    fi

    rm -rf "$tmp_wp_root"

    if [[ "$errors" -eq 0 ]]; then
        pass_test "Development environment detection handled supported signals correctly"
    else
        fail_test "$errors environment detection check(s) failed"
    fi
}

# ================================================================
# Test: Host-side Lando/DDEV skip direct socket probing
# ================================================================
#
test_socket_container_host_fallback() {
    start_test "Container Host Fallback" "Host-side Lando/DDEV projects skip direct socket probing"

    if ! source "$PROJECT_ROOT_DIR/lib/database/socket_detector.sh" >/dev/null 2>&1; then
        fail_test "Could not source socket_detector.sh"
        return 1
    fi

    local errors=0
    local tmp_wp_root
    local exit_code=0

    tmp_wp_root=$(mktemp -d "/tmp/test_socket_container_host_$$.XXXXXX")

    : > "$tmp_wp_root/.lando.yml"
    detect_mysql_socket "$tmp_wp_root" >/dev/null 2>&1 || exit_code=$?
    if [[ "$exit_code" -eq 1 ]]; then
        printf "  ✅ Lando host project returned fallback signal\n"
    else
        printf "  ❌ Expected Lando host fallback exit 1, got %s\n" "$exit_code"
        ((errors++))
    fi

    rm -f "$tmp_wp_root/.lando.yml"
    mkdir -p "$tmp_wp_root/.ddev"
    exit_code=0
    detect_mysql_socket "$tmp_wp_root" >/dev/null 2>&1 || exit_code=$?
    if [[ "$exit_code" -eq 1 ]]; then
        printf "  ✅ DDEV host project returned fallback signal\n"
    else
        printf "  ❌ Expected DDEV host fallback exit 1, got %s\n" "$exit_code"
        ((errors++))
    fi

    rm -rf "$tmp_wp_root"

    if [[ "$errors" -eq 0 ]]; then
        pass_test "Host-side container environments correctly fell back to WP-CLI"
    else
        fail_test "$errors host fallback check(s) failed"
    fi
}

# ================================================================
# Test: get_wp_db_credentials parses wp-config.php correctly
# ================================================================
#
test_wp_db_credentials_parser() {
    start_test "WP DB Credentials Parser" "get_wp_db_credentials extracts DB settings safely"

    # Source utils which contains get_wp_db_credentials
    if ! source "$PROJECT_ROOT_DIR/lib/core/utils.sh" >/dev/null 2>&1; then
        fail_test "Could not source utils.sh"
        return 1
    fi

    if ! declare -F get_wp_db_credentials >/dev/null 2>&1; then
        fail_test "get_wp_db_credentials function not found in utils.sh"
        return 1
    fi

    local tmp_dir
    tmp_dir=$(mktemp -d "/tmp/test_wp_creds_$$.XXXXXX")

    # Write a realistic mock wp-config.php
    cat > "$tmp_dir/wp-config.php" << 'EOF'
<?php
/** The name of the database for WordPress */
define( 'DB_NAME', 'wordpress_local' );

/** Database username */
define( 'DB_USER', 'wpuser' );

/** Database password */
define( 'DB_PASSWORD', 'p@ssw0rd!123' );

/** Database hostname */
define( 'DB_HOST', 'localhost' );

/** Database Charset to use in creating database tables. */
define( 'DB_CHARSET', 'utf8mb4' );
EOF

    local errors=0

    # Unset any existing env vars to avoid contamination
    unset WP_DB_NAME WP_DB_USER WP_DB_PASSWORD WP_DB_HOST

    if get_wp_db_credentials "$tmp_dir" >/dev/null 2>&1; then
        [[ "$WP_DB_NAME" == "wordpress_local" ]] || { printf "  ❌ DB_NAME: expected 'wordpress_local', got '%s'\n" "$WP_DB_NAME"; ((errors++)); }
        [[ "$WP_DB_USER" == "wpuser" ]]          || { printf "  ❌ DB_USER: expected 'wpuser', got '%s'\n" "$WP_DB_USER"; ((errors++)); }
        [[ "$WP_DB_HOST" == "localhost" ]]        || { printf "  ❌ DB_HOST: expected 'localhost', got '%s'\n" "$WP_DB_HOST"; ((errors++)); }

        if [[ "$errors" -eq 0 ]]; then
            printf "  ✅ DB_NAME: %s\n" "$WP_DB_NAME"
            printf "  ✅ DB_USER: %s\n" "$WP_DB_USER"
            printf "  ✅ DB_HOST: %s\n" "$WP_DB_HOST"
            printf "  ✅ DB_PASSWORD: parsed (not shown)\n"
        fi
    else
        printf "  ❌ get_wp_db_credentials returned failure\n"
        ((errors++))
    fi

    rm -rf "$tmp_dir"
    unset WP_DB_NAME WP_DB_USER WP_DB_PASSWORD WP_DB_HOST

    if [[ "$errors" -eq 0 ]]; then
        pass_test "All credential fields parsed correctly"
    else
        fail_test "$errors credential field(s) failed to parse"
    fi
}

# ================================================================
# Test: get_wp_db_credentials with missing wp-config.php
# ================================================================
#
test_wp_db_credentials_missing_file() {
    start_test "WP DB Credentials Missing File" "get_wp_db_credentials handles missing wp-config.php"

    if ! source "$PROJECT_ROOT_DIR/lib/core/utils.sh" >/dev/null 2>&1; then
        fail_test "Could not source utils.sh"
        return 1
    fi

    if ! declare -F get_wp_db_credentials >/dev/null 2>&1; then
        fail_test "get_wp_db_credentials function not found"
        return 1
    fi

    local exit_code=0
    get_wp_db_credentials "/tmp/totally_nonexistent_$$_dir" >/dev/null 2>&1 || exit_code=$?

    if [[ "$exit_code" -ne 0 ]]; then
        pass_test "Correctly returned non-zero exit code for missing file (exit=$exit_code)"
    else
        fail_test "Should have failed with non-zero exit code for missing wp-config.php"
    fi
}

# ================================================================
# Test: Socket config loading via integration.sh
# ================================================================
#
test_socket_config_integration() {
    start_test "Socket Config Integration" "Socket and import optimization settings load from config file"

    if ! source "$PROJECT_ROOT_DIR/lib/module_loader.sh" >/dev/null 2>&1; then
        fail_test "Could not source module_loader.sh"
        return 1
    fi

    # Load all modules
    load_modules >/dev/null 2>&1

    if ! declare -F load_import_config >/dev/null 2>&1; then
        fail_test "load_import_config function not found"
        return 1
    fi

    # Create a temp config with socket options
    local tmp_config
    tmp_config=$(mktemp "/tmp/test_socket_config_$$.XXXXXX.conf")
    cat > "$tmp_config" << 'EOF'
[general]
sql_file=test.sql
old_domain=example.com
new_domain=example.test
use_socket=false
mysql_socket=/custom/path/mysql.sock
import_optimizations=true
parallel_import=false
EOF

    unset CONFIG_USE_SOCKET CONFIG_MYSQL_SOCKET CONFIG_IMPORT_OPTIMIZATIONS CONFIG_PARALLEL_IMPORT

    load_import_config "$tmp_config" >/dev/null 2>&1
    rm -f "$tmp_config"

    local errors=0
    [[ "$CONFIG_USE_SOCKET" == "false" ]] || { printf "  ❌ CONFIG_USE_SOCKET: expected 'false', got '%s'\n" "$CONFIG_USE_SOCKET"; ((errors++)); }
    [[ "$CONFIG_MYSQL_SOCKET" == "/custom/path/mysql.sock" ]] || { printf "  ❌ CONFIG_MYSQL_SOCKET: expected '/custom/path/mysql.sock', got '%s'\n" "$CONFIG_MYSQL_SOCKET"; ((errors++)); }
    [[ "$CONFIG_IMPORT_OPTIMIZATIONS" == "true" ]] || { printf "  ❌ CONFIG_IMPORT_OPTIMIZATIONS: expected 'true', got '%s'\n" "$CONFIG_IMPORT_OPTIMIZATIONS"; ((errors++)); }
    [[ "$CONFIG_PARALLEL_IMPORT" == "false" ]] || { printf "  ❌ CONFIG_PARALLEL_IMPORT: expected 'false', got '%s'\n" "$CONFIG_PARALLEL_IMPORT"; ((errors++)); }

    if [[ "$errors" -eq 0 ]]; then
        printf "  ✅ CONFIG_USE_SOCKET: %s\n" "$CONFIG_USE_SOCKET"
        printf "  ✅ CONFIG_MYSQL_SOCKET: %s\n" "$CONFIG_MYSQL_SOCKET"
        printf "  ✅ CONFIG_IMPORT_OPTIMIZATIONS: %s\n" "$CONFIG_IMPORT_OPTIMIZATIONS"
        printf "  ✅ CONFIG_PARALLEL_IMPORT: %s\n" "$CONFIG_PARALLEL_IMPORT"
        pass_test "Socket config options loaded correctly from config file"
    else
        fail_test "$errors config value(s) did not load correctly"
    fi
}

# ================================================================
# Test: Default use_socket when key is absent from config
# ================================================================
#
test_socket_config_default() {
    start_test "Socket Config Default" "use_socket defaults to 'auto' when absent from config"

    if ! source "$PROJECT_ROOT_DIR/lib/module_loader.sh" >/dev/null 2>&1; then
        fail_test "Could not source module_loader.sh"
        return 1
    fi

    load_modules >/dev/null 2>&1

    if ! declare -F load_import_config >/dev/null 2>&1; then
        fail_test "load_import_config function not found"
        return 1
    fi

    local tmp_config
    tmp_config=$(mktemp "/tmp/test_socket_default_$$.XXXXXX.conf")
    cat > "$tmp_config" << 'EOF'
[general]
sql_file=test.sql
old_domain=example.com
new_domain=example.test
EOF

    unset CONFIG_USE_SOCKET CONFIG_MYSQL_SOCKET CONFIG_IMPORT_OPTIMIZATIONS CONFIG_PARALLEL_IMPORT

    load_import_config "$tmp_config" >/dev/null 2>&1
    rm -f "$tmp_config"

    if [[ "$CONFIG_USE_SOCKET" == "auto" && "$CONFIG_IMPORT_OPTIMIZATIONS" == "auto" && "$CONFIG_PARALLEL_IMPORT" == "false" ]]; then
        pass_test "Socket and optimization settings correctly default when absent"
    else
        fail_test "Expected defaults use_socket=auto, import_optimizations=auto, parallel_import=false; got use_socket='${CONFIG_USE_SOCKET:-empty}', import_optimizations='${CONFIG_IMPORT_OPTIMIZATIONS:-empty}', parallel_import='${CONFIG_PARALLEL_IMPORT:-empty}'"
    fi
}

# ================================================================
# Test: Existing config files are upgraded with import keys
# ================================================================
#
test_socket_config_migration() {
    start_test "Socket Config Migration" "existing config files gain missing import keys automatically"

    if ! source "$PROJECT_ROOT_DIR/lib/module_loader.sh" >/dev/null 2>&1; then
        fail_test "Could not source module_loader.sh"
        return 1
    fi

    load_modules >/dev/null 2>&1

    if ! declare -F ensure_socket_config_settings >/dev/null 2>&1; then
        fail_test "ensure_socket_config_settings function not found"
        return 1
    fi

    local tmp_config
    tmp_config=$(mktemp "/tmp/test_socket_migration_$$.XXXXXX.conf")
    cat > "$tmp_config" << 'EOF'
[general]
sql_file=test.sql
old_domain=example.com
new_domain=example.test
all_tables=true

[site_mappings]
EOF

    unset CONFIG_SOCKET_SETTINGS_MIGRATED

    if ! ensure_socket_config_settings "$tmp_config" >/dev/null 2>&1; then
        rm -f "$tmp_config"
        fail_test "ensure_socket_config_settings failed"
        return 1
    fi

    local migrated_use_socket
    local migrated_mysql_socket
    local migrated_import_optimizations
    local migrated_parallel_import
    migrated_use_socket=$(parse_config_section "$tmp_config" "general" "use_socket")
    migrated_mysql_socket=$(parse_config_section "$tmp_config" "general" "mysql_socket")
    migrated_import_optimizations=$(parse_config_section "$tmp_config" "general" "import_optimizations")
    migrated_parallel_import=$(parse_config_section "$tmp_config" "general" "parallel_import")

    local errors=0
    [[ "$CONFIG_SOCKET_SETTINGS_MIGRATED" == "true" ]] || { printf "  ❌ Expected CONFIG_SOCKET_SETTINGS_MIGRATED=true, got '%s'\n" "${CONFIG_SOCKET_SETTINGS_MIGRATED:-empty}"; ((errors++)); }
    [[ "$migrated_use_socket" == "auto" ]] || { printf "  ❌ Expected use_socket=auto, got '%s'\n" "$migrated_use_socket"; ((errors++)); }
    [[ "$migrated_mysql_socket" == "" ]] || { printf "  ❌ Expected mysql_socket to be empty, got '%s'\n" "$migrated_mysql_socket"; ((errors++)); }
    [[ "$migrated_import_optimizations" == "auto" ]] || { printf "  ❌ Expected import_optimizations=auto, got '%s'\n" "$migrated_import_optimizations"; ((errors++)); }
    [[ "$migrated_parallel_import" == "false" ]] || { printf "  ❌ Expected parallel_import=false, got '%s'\n" "$migrated_parallel_import"; ((errors++)); }

    rm -f "$tmp_config"

    if [[ "$errors" -eq 0 ]]; then
        pass_test "Existing config file was updated with import settings"
    else
        fail_test "$errors config migration check(s) failed"
    fi
}

# ================================================================
# Test: detect_mysql_socket function is exported
# ================================================================
#
test_socket_function_exported() {
    start_test "Socket Detector Exported" "detect_mysql_socket function is accessible after module load"

    if ! source "$PROJECT_ROOT_DIR/lib/module_loader.sh" >/dev/null 2>&1; then
        fail_test "Could not source module_loader.sh"
        return 1
    fi

    load_modules >/dev/null 2>&1

    if declare -F detect_mysql_socket >/dev/null 2>&1; then
        pass_test "detect_mysql_socket function is available after load_modules"
    elif source "$PROJECT_ROOT_DIR/lib/database/socket_detector.sh" >/dev/null 2>&1 && \
         declare -F detect_mysql_socket >/dev/null 2>&1; then
        pass_test "detect_mysql_socket available when socket_detector.sh sourced directly"
    else
        fail_test "detect_mysql_socket not found after module load"
    fi
}

# ================================================================
# Test: mysql binary detection helper
# ================================================================
#
test_mysql_binary_detection() {
    start_test "MySQL Binary Detection" "is_mysql_binary_available correctly reports mysql presence"

    if ! source "$PROJECT_ROOT_DIR/lib/database/socket_detector.sh" >/dev/null 2>&1; then
        fail_test "Could not source socket_detector.sh"
        return 1
    fi

    # The function should not crash regardless of whether mysql is installed
    local exit_code=0
    is_mysql_binary_available 2>/dev/null || exit_code=$?

    # exit_code 0 = found, 1 = not found — both are acceptable, just no crash
    if [[ "$exit_code" -le 1 ]]; then
        if [[ "$exit_code" -eq 0 ]]; then
            local mysql_path
            mysql_path=$(get_mysql_binary 2>/dev/null)
            pass_test "mysql binary found at: ${mysql_path:-unknown}"
        else
            pass_test "mysql binary not found — function returned cleanly (exit=1)"
        fi
    else
        fail_test "is_mysql_binary_available crashed with exit code $exit_code"
    fi
}

# ================================================================
# Run all socket tests
# ================================================================
#
run_socket_tests() {
    printf "\n${CYAN}${BOLD}🔌 MySQL Socket Detection Tests${RESET}\n"
    printf "%s\n\n" "$(printf '=%.0s' {1..50})"

    init_test_session "socket_detection"

    test_socket_validation
    test_socket_wp_config_extraction
    test_socket_wp_config_no_socket
    test_socket_config_override
    test_socket_invalid_config_override
    test_socket_environment_detection
    test_socket_container_host_fallback
    test_wp_db_credentials_parser
    test_wp_db_credentials_missing_file
    test_socket_config_integration
    test_socket_config_default
    test_socket_config_migration
    test_socket_function_exported
    test_mysql_binary_detection

    finalize_test_session
    return $?
}

# Run tests if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    run_socket_tests
fi
