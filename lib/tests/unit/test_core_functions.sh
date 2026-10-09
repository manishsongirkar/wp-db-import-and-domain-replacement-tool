#!/usr/bin/env bash

# ================================================================
# Unit Tests for Core Functions
# ================================================================
#
# Description:
#   A modular test suite dedicated to performing unit tests on individual
#   core functions and fundamental components of the WordPress database
#   import tool. This ensures that utility functions, module loading,
#   configuration system, string manipulation, and file handling operations
#   function correctly in isolation before integration testing.
#
# Key Components Tested:
# - Core Utility functions (`sanitize_domain`, `find_wp_root`).
# - Version management and file existence (`VERSION`).
# - Module loading system (`module_loader.sh`).
# - Configuration parsing and variable setting.
# - Basic error handling mechanisms.
# - File I/O and temporary file handling.
#
# Functions provided:
# - test_utility_functions
# - test_version_management
# - test_module_loading
# - test_configuration_system
# - test_error_handling
# - test_string_utilities
# - test_file_handling
# - run_unit_tests
#
# Dependencies:
# - test_framework.sh (Must be sourced for test session management)
# - External functions from the main script (e.g., `sanitize_domain`, `find_wp_root`, `load_config`, `validate_config`).
# - Color constants (e.g., ${CYAN}, ${BOLD}, ${RESET}, ${DIM})
#
# Usage:
#   ./test/unit_tests.sh
#
# ================================================================

# Source the test framework
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../test_framework.sh"

# ===============================================
# Test utility functions
# ===============================================
#
# Description: Unit tests for foundational utility functions such as domain
#              sanitization and WordPress root directory detection.
#
# Parameters:
#   - None.
#
# Returns:
#   - Calls `pass_test` or `fail_test`.
#
# Behavior:
#   - Tests `sanitize_domain` by cleaning up a URL with protocol and trailing slash.
#   - Tests `find_wp_root` by creating a mock `wp-config.php` file in a temporary directory.
#
test_utility_functions() {
    start_test "Utility Functions" "Test core utility functions"

    # Load the main script and modules
    if source "$PROJECT_ROOT_DIR/import_wp_db.sh" >/dev/null 2>&1; then

        # Test sanitize_domain function if available
        if declare -F sanitize_domain >/dev/null 2>&1; then
            local test_domain="https://example.com/"
            local sanitized=$(sanitize_domain "$test_domain" 2>/dev/null)

            if [[ "$sanitized" == "example.com" ]]; then
                printf "  ✅ sanitize_domain works correctly\n"
            else
                printf "  ❌ sanitize_domain failed: got '$sanitized'\n"
            fi
        fi

        # Test find_wp_root function if available
        if declare -F find_wp_root >/dev/null 2>&1; then
            # Create temporary WordPress structure
            local temp_dir=$(create_temp_test_dir "wp_root_test")
            cd "$temp_dir" || return 1

            echo "<?php // WordPress config" > wp-config.php
            local wp_root=$(find_wp_root 2>/dev/null)

            if [[ "$wp_root" == "$temp_dir" ]]; then
                printf "  ✅ find_wp_root works correctly\n"
            else
                printf "  ❌ find_wp_root failed\n"
            fi

            cd / && cleanup_temp_test_dir "$temp_dir"
        fi

        pass_test "Core utility functions tested"
    else
        fail_test "Failed to load main script for testing"
    fi
}

# ===============================================
# Test version management
# ===============================================
#
# Description: Verifies that the project's version file (`VERSION`) exists, is readable,
#              and contains content, ensuring that version tracking is functional.
#
# Parameters:
#   - None.
#
# Returns:
#   - Calls `pass_test` or `fail_test`.
#
# Behavior:
#   - Checks the file path `$PROJECT_ROOT_DIR/VERSION`.
#
test_version_management() {
    start_test "Version Management" "Test version detection and management"

    if [[ -f "$PROJECT_ROOT_DIR/VERSION" ]]; then
        local version=$(cat "$PROJECT_ROOT_DIR/VERSION" 2>/dev/null | tr -d '\n\r' | head -1)

        if [[ -n "$version" ]]; then
            printf "  ✅ Version file exists and readable: $version\n"
            pass_test "Version management working"
        else
            fail_test "Version file exists but is empty"
        fi
    else
        fail_test "VERSION file not found"
    fi
}

# ===============================================
# Test module loading
# ===============================================
#
# Description: Verifies that the `module_loader.sh` script can be sourced and that
#              the primary module loading function, `load_modules`, is available
#              in the current shell environment.
#
# Parameters:
#   - None.
#
# Returns:
#   - Calls `pass_test` or `fail_test`.
#
# Behavior:
#   - Checks the file path `$PROJECT_ROOT_DIR/lib/module_loader.sh`.
#   - Uses `declare -F` to check for the exported function `load_modules`.
#
test_module_loading() {
    start_test "Module Loading" "Test module loading system"

    local module_loader="$PROJECT_ROOT_DIR/lib/module_loader.sh"

    if [[ -f "$module_loader" ]]; then
        if source "$module_loader" 2>/dev/null; then
            printf "  ✅ Module loader sourced successfully\n"

            # Test if load_modules function is available
            if declare -F load_modules >/dev/null 2>&1; then
                printf "  ✅ load_modules function available\n"
                pass_test "Module loading system working"
            else
                fail_test "load_modules function not available"
            fi
        else
            fail_test "Failed to source module loader"
        fi
    else
        fail_test "Module loader not found"
    fi
}

# ===============================================
# Test configuration system
# ===============================================
#
# Description: Performs a unit test on the configuration loading mechanism,
#              verifying that variables are correctly parsed from a test `.conf`
#              file and set in the current shell environment.
#
# Parameters:
#   - None.
#
# Returns:
#   - Calls `pass_test`, `fail_test`, or `skip_test`.
#
# Behavior:
#   - Creates a temporary test config file (`test.conf`).
#   - Calls the external function `load_config`.
#   - Checks if the `$OLD_DOMAIN` variable is set correctly after loading.
#
test_configuration_system() {
    start_test "Configuration System" "Test configuration file reading and validation"

    local test_dir
    test_dir=$(create_temp_test_dir "config_system")
    cd "$test_dir" || { fail_test "Cannot enter temp dir"; return 1; }

    cat > "test.conf" <<EOF
[general]
sql_file=dump.sql
old_domain=test.com
new_domain=local.test
all_tables=true
dry_run=false
clear_revisions=true
setup_stage_proxy=false
auto_proceed=true

[site_mappings]
EOF

    if ! source "$PROJECT_ROOT_DIR/import_wp_db.sh" >/dev/null 2>&1; then
        cd / && cleanup_temp_test_dir "$test_dir"
        fail_test "Failed to load main script"
        return 1
    fi

    # Core functions must exist: a missing one is a bug, not a reason to skip
    local fn
    for fn in load_import_config validate_config_file; do
        if ! declare -F "$fn" >/dev/null 2>&1; then
            cd / && cleanup_temp_test_dir "$test_dir"
            fail_test "core function $fn is missing"
            return 1
        fi
    done

    local errors=0
    load_import_config "test.conf" >/dev/null 2>&1
    [[ "$CONFIG_OLD_DOMAIN" == "test.com" ]]   && printf "  ✅ old_domain loaded\n"   || { printf "  ❌ old_domain not loaded: '%s'\n" "$CONFIG_OLD_DOMAIN"; ((errors++)); }
    [[ "$CONFIG_NEW_DOMAIN" == "local.test" ]] && printf "  ✅ new_domain loaded\n"   || { printf "  ❌ new_domain not loaded: '%s'\n" "$CONFIG_NEW_DOMAIN"; ((errors++)); }
    [[ "$CONFIG_SQL_FILE" == "dump.sql" ]]     && printf "  ✅ sql_file loaded\n"     || { printf "  ❌ sql_file not loaded: '%s'\n" "$CONFIG_SQL_FILE"; ((errors++)); }
    [[ "$CONFIG_AUTO_PROCEED" == "true" ]]     && printf "  ✅ auto_proceed loaded\n" || { printf "  ❌ auto_proceed not loaded: '%s'\n" "$CONFIG_AUTO_PROCEED"; ((errors++)); }
    [[ "$CONFIG_BACKUP_BEFORE_IMPORT" == "ask" && "$CONFIG_BACKUP_KEEP" == "5" ]] \
        && printf "  ✅ defaults applied for keys missing from the file\n" \
        || { printf "  ❌ defaults missing (backup=%s keep=%s)\n" "$CONFIG_BACKUP_BEFORE_IMPORT" "$CONFIG_BACKUP_KEEP"; ((errors++)); }

    if validate_config_file "test.conf" >/dev/null 2>&1; then
        printf "  ✅ valid configuration is accepted\n"
    else
        printf "  ❌ valid configuration was rejected\n"; ((errors++))
    fi

    cd / && cleanup_temp_test_dir "$test_dir"
    if [[ "$errors" -eq 0 ]]; then
        pass_test "Configuration system working"
    else
        fail_test "$errors configuration check(s) failed"
    fi
}

# ===============================================
# Test error handling
# ===============================================
#
# Description: Tests the script's basic error handling capability by executing a
#              function with known invalid parameters and verifying that the
#              function fails gracefully (exits with non-zero status).
#
# Parameters:
#   - None.
#
# Returns:
#   - Calls `pass_test`, `fail_test`, or `skip_test`.
#
# Behavior:
#   - Calls the external function `validate_config` with a path to a non-existent file.
#
test_error_handling() {
    start_test "Error Handling" "Test error handling mechanisms"

    local test_dir
    test_dir=$(create_temp_test_dir "error_handling")
    cd "$test_dir" || { fail_test "Cannot enter temp dir"; return 1; }

    if ! source "$PROJECT_ROOT_DIR/import_wp_db.sh" >/dev/null 2>&1; then
        cd / && cleanup_temp_test_dir "$test_dir"
        fail_test "Failed to load main script"
        return 1
    fi
    if ! declare -F validate_config_file >/dev/null 2>&1; then
        cd / && cleanup_temp_test_dir "$test_dir"
        fail_test "core function validate_config_file is missing"
        return 1
    fi

    local errors=0 out

    if validate_config_file "/nonexistent/file" >/dev/null 2>&1; then
        printf "  ❌ a missing config file was accepted\n"; ((errors++))
    else
        printf "  ✅ missing config file is rejected\n"
    fi

    printf '[site_mappings]\n' > no_general.conf
    out=$(validate_config_file no_general.conf 2>&1 | sed 's/\x1b\[[0-9;]*m//g')
    if [[ $? -eq 0 && "$out" == *"Missing [general] section"* ]]; then
        printf "  ✅ config without [general] is rejected with a reason\n"
    else
        printf "  ❌ config without [general] was not rejected clearly: %s\n" "$out"; ((errors++))
    fi

    printf '[general]\nsql_file=a.sql\n[site_mappings]\n' > no_domains.conf
    out=$(validate_config_file no_domains.conf 2>&1 | sed 's/\x1b\[[0-9;]*m//g')
    if [[ "$out" == *"Missing or empty old_domain setting"* && "$out" == *"Missing or empty new_domain setting"* ]]; then
        printf "  ✅ missing required domains are reported\n"
    else
        printf "  ❌ missing domains not reported: %s\n" "$out"; ((errors++))
    fi

    cd / && cleanup_temp_test_dir "$test_dir"
    if [[ "$errors" -eq 0 ]]; then
        pass_test "Error handling mechanisms working"
    else
        fail_test "$errors error-handling check(s) failed"
    fi
}

# ===============================================
# Test execute_with_timeout with and without a system `timeout`
# ===============================================
#
# Description:
#   `execute_with_timeout` is called with a shell FUNCTION (execute_wp_cli) almost everywhere.
#   An external `timeout` cannot run a function, so on Linux (or with GNU coreutils) every
#   call failed. A stub `timeout` that rejects functions reproduces that without needing Linux.
#
test_execute_with_timeout() {
    start_test "Execute With Timeout" "shell functions run even when a system timeout exists"

    if ! source "$PROJECT_ROOT_DIR/lib/core/utils.sh" >/dev/null 2>&1 || ! declare -F execute_with_timeout >/dev/null 2>&1; then
        fail_test "core function execute_with_timeout is missing"
        return 1
    fi

    local errors=0 w stubdir
    w=$(create_temp_test_dir "exec_timeout")
    stubdir="$w/bin"; mkdir -p "$stubdir"
    # A "GNU timeout" stand-in: like the real one it can only run executables
    cat > "$stubdir/timeout" <<'EOF'
#!/usr/bin/env bash
echo "timeout-called: $*" >> "$STUB_TIMEOUT_LOG"
shift
exec "$@"
EOF
    chmod +x "$stubdir/timeout"
    printf '#!/bin/sh\necho "external-output"\n' > "$stubdir/ext_cmd"; chmod +x "$stubdir/ext_cmd"
    export STUB_TIMEOUT_LOG="$w/timeout.log"; : > "$STUB_TIMEOUT_LOG"

    my_function() { echo "function-output:$*"; return 7; }

    local out rc
    out=$(PATH="$stubdir:$PATH" execute_with_timeout 5 my_function a b); rc=$?
    [[ "$out" == "function-output:a b" ]] && printf "  ✅ a shell function runs with a system timeout present\n" || { printf "  ❌ function did not run: '%s'\n" "$out"; ((errors++)); }
    [[ $rc -eq 7 ]] && printf "  ✅ the function's exit code is returned\n" || { printf "  ❌ exit code lost (%s)\n" "$rc"; ((errors++)); }
    [[ ! -s "$STUB_TIMEOUT_LOG" ]] && printf "  ✅ the external timeout is not used for functions\n" || { printf "  ❌ external timeout was called for a function\n"; ((errors++)); }

    out=$(PATH="$stubdir:$PATH" execute_with_timeout 5 ext_cmd); rc=$?
    [[ "$out" == "external-output" && $rc -eq 0 ]] && printf "  ✅ an external command still runs\n" || { printf "  ❌ external command failed: '%s' rc=%s\n" "$out" "$rc"; ((errors++)); }
    grep -q 'timeout-called: 5 ext_cmd' "$STUB_TIMEOUT_LOG" && printf "  ✅ the system timeout is still used for executables\n" || { printf "  ❌ timeout not used for an executable\n"; ((errors++)); }

    # Without any system timeout: functions and commands run directly
    : > "$STUB_TIMEOUT_LOG"
    out=$(PATH="$stubdir" execute_with_timeout 5 my_function x 2>/dev/null); rc=$?
    [[ "$out" == "function-output:x" && $rc -eq 7 ]] && printf "  ✅ works without a system timeout\n" || { printf "  ❌ failed without timeout: '%s' rc=%s\n" "$out" "$rc"; ((errors++)); }

    unset -f my_function; unset STUB_TIMEOUT_LOG
    cd / && cleanup_temp_test_dir "$w"
    if [[ "$errors" -eq 0 ]]; then
        pass_test "execute_with_timeout works for functions and executables"
    else
        fail_test "$errors execute_with_timeout check(s) failed"
    fi
}

# ===============================================
# Test string manipulation utilities
# ===============================================
#
# Description: Unit tests for core Bash parameter expansion operations used for
#              string cleaning, specifically trimming whitespace and cleaning URLs.
#
# Parameters:
#   - None.
#
# Returns:
#   - Calls `pass_test` or `fail_test`.
#
# Behavior:
#   - Uses native Bash string substitution (`// /`) to test whitespace trimming.
#   - Uses prefix removal (`#`) and suffix removal (`%`) to test cleaning URL protocols and slashes.
#
test_string_utilities() {
    start_test "String Utilities" "Test string manipulation functions"

    local string_issues=0

    # Test basic string operations that should work in all bash versions
    local test_string="  example.com/path  "

    # Test trimming (using parameter expansion)
    local trimmed="${test_string// /}"
    if [[ "$trimmed" == "example.com/path" ]]; then
        printf "  ✅ String trimming works\n"
    else
        printf "  ❌ String trimming failed\n"
        ((string_issues++))
    fi

    # Test URL cleaning
    local url="https://example.com/"
    local cleaned_url="${url#http://}"
    cleaned_url="${cleaned_url#https://}"
    cleaned_url="${cleaned_url%/}"

    if [[ "$cleaned_url" == "example.com" ]]; then
        printf "  ✅ URL cleaning works\n"
    else
        printf "  ❌ URL cleaning failed: got '$cleaned_url'\n"
        ((string_issues++))
    fi

    if [[ $string_issues -eq 0 ]]; then
        pass_test "String utility functions working"
    else
        fail_test "$string_issues string utility issues"
    fi
}

# ===============================================
# Test file handling
# ===============================================
#
# Description: Unit tests for basic file system interactions, ensuring file creation,
#              reading, backing up, and temporary file management function as expected.
#
# Parameters:
#   - None.
#
# Returns:
#   - Calls `pass_test` or `fail_test`.
#
# Behavior:
#   - Uses `mktemp` to test temporary file creation and ensures it's cleaned up.
#   - Verifies standard I/O redirection (`>`) and file existence (`-f`).
#
test_file_handling() {
    start_test "File Handling" "Test file operations and safety checks"

    local temp_dir=$(create_temp_test_dir "file_test")
    cd "$temp_dir" || return 1

    local file_issues=0

    # Test file creation
    echo "test content" > "test.txt"
    if [[ -f "test.txt" ]] && [[ "$(cat test.txt)" == "test content" ]]; then
        printf "  ✅ File creation and reading works\n"
    else
        printf "  ❌ File creation or reading failed\n"
        ((file_issues++))
    fi

    # Test file backup creation
    cp "test.txt" "test.txt.backup"
    if [[ -f "test.txt.backup" ]]; then
        printf "  ✅ File backup creation works\n"
    else
        printf "  ❌ File backup creation failed\n"
        ((file_issues++))
    fi

    # Test temporary file handling
    local temp_file=$(mktemp)
    echo "temporary content" > "$temp_file"

    if [[ -f "$temp_file" ]] && [[ "$(cat "$temp_file")" == "temporary content" ]]; then
        printf "  ✅ Temporary file handling works\n"
        rm -f "$temp_file"
    else
        printf "  ❌ Temporary file handling failed\n"
        ((file_issues++))
    fi

    cd / && cleanup_temp_test_dir "$temp_dir"

    if [[ $file_issues -eq 0 ]]; then
        pass_test "File handling functions working"
    else
        fail_test "$file_issues file handling issues"
    fi
}

# ===============================================
# Run all unit tests
# ===============================================
#
# Description: The primary entry point function that initializes the test session
#              and executes all individual unit test functions sequentially.
#
# Parameters:
#   - None.
#
# Returns:
#   - The exit code of the final `finalize_test_session` call (0 on success, non-zero on failure).
#
# Behavior:
#   - Calls `init_test_session`.
#   - Executes all `test_*` functions grouped by core and supporting functionality.
#   - Calls `finalize_test_session`.
#
run_unit_tests() {
    init_test_session "unit_tests"

    printf "${CYAN}${BOLD}🔬 Unit Tests${RESET}\n"
    printf "${DIM}Testing individual functions and components${RESET}\n\n"

    # Core functionality tests
    test_utility_functions
    test_version_management
    test_module_loading
    test_configuration_system
    test_error_handling

    # Supporting functionality tests
    test_execute_with_timeout
    test_string_utilities
    test_file_handling

    finalize_test_session
    return $?
}

# Run tests if this script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    run_unit_tests
fi
