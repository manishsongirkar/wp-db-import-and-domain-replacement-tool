#!/usr/bin/env bash

# ================================================================
# Unit Tests for Import Performance Features
# ================================================================
#
# Description:
#   Tests the new import performance optimizations:
#     1. estimate_import_duration() - benchmark function
#     2. Multi-path import strategy (socket → mysql CLI → WP-CLI)
#     3. Session-level SQL optimization detection
#     4. Import method selection logic
#
# Functions provided:
# - test_import_duration_estimation
# - test_should_enable_optimized_import_session
# - test_import_method_priority
# - test_mysql_cli_fallback_when_socket_unavailable
# - test_session_optimization_skipped_on_wpcli
# - test_parallel_import_warning
# - test_import_config_keys_loading
# - run_import_performance_tests
#
# Dependencies:
# - test_framework.sh (Must be sourced for test session management)
# - lib/database/db_import.sh (functions under test)
# - lib/config/integration.sh (config loading)
#
# ================================================================

# Source the test framework
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../test_framework.sh"

# ================================================================
# Test: estimate_import_duration function
# ================================================================
#
# Description:
#   Tests that the benchmark function correctly estimates import
#   duration based on file size and returns reasonable min/likely/max
#   values in the correct format.
#
test_import_duration_estimation() {
    start_test "Import Duration Estimation" "estimate_import_duration outputs min/likely/max minutes"

    if ! source "$PROJECT_ROOT_DIR/lib/database/db_import.sh" >/dev/null 2>&1; then
        fail_test "Could not source db_import.sh"
        return 1
    fi

    if ! declare -F estimate_import_duration >/dev/null 2>&1; then
        fail_test "estimate_import_duration function not found"
        return 1
    fi

    local errors=0

    # Test 1: Small file estimate (should use conservative estimate, no benchmark)
    local small_file
    small_file=$(mktemp "/tmp/test_small_sql_$$.sql")
    echo "CREATE TABLE test (id INT);" > "$small_file"
    local estimate
    estimate=$(estimate_import_duration "$small_file" "" "" "" "" "" "auto" 2>/dev/null)
    rm -f "$small_file"

    if [[ -n "$estimate" ]]; then
        local min likely max
        IFS=' ' read -r min likely max <<< "$estimate"
        if [[ "$min" =~ ^[0-9]+$ && "$likely" =~ ^[0-9]+$ && "$max" =~ ^[0-9]+$ ]]; then
            if [[ "$min" -le "$likely" && "$likely" -le "$max" ]]; then
                printf "  ✅ Small file estimate: %sm (min) → %sm (likely) → %sm (max)\n" "$min" "$likely" "$max"
            else
                printf "  ❌ Estimate order invalid: min=%s likely=%s max=%s\n" "$min" "$likely" "$max"
                ((errors++))
            fi
        else
            printf "  ❌ Estimate output not numeric: '%s'\n" "$estimate"
            ((errors++))
        fi
    else
        printf "  ❌ estimate_import_duration returned empty\n"
        ((errors++))
    fi

    # Test 2: Non-existent file should return fallback estimate
    estimate=$(estimate_import_duration "/tmp/nonexistent_file_$$.sql" "" "" "" "" "" "auto" 2>/dev/null)
    if [[ "$estimate" =~ ^[0-9]+\ [0-9]+\ [0-9]+$ ]]; then
        printf "  ✅ Non-existent file returns fallback estimate\n"
    else
        printf "  ❌ Non-existent file estimate invalid: '%s'\n" "$estimate"
        ((errors++))
    fi

    if [[ "$errors" -eq 0 ]]; then
        pass_test "estimate_import_duration function works correctly"
    else
        fail_test "$errors estimate validation(s) failed"
    fi
}

# ================================================================
# Test: should_enable_optimized_import_session function
# ================================================================
#
# Description:
#   Tests that session-level SQL optimization is only applied to
#   direct mysql imports (socket or mysql-cli), not to WP-CLI.
#
test_should_enable_optimized_import_session() {
    start_test "Session Optimization Detection" "Optimization flags only apply to direct mysql imports"

    if ! source "$PROJECT_ROOT_DIR/lib/database/db_import.sh" >/dev/null 2>&1; then
        fail_test "Could not source db_import.sh"
        return 1
    fi

    if ! declare -F should_enable_optimized_import_session >/dev/null 2>&1; then
        fail_test "should_enable_optimized_import_session function not found"
        return 1
    fi

    local errors=0

    # Test 1: auto mode + socket import = enabled
    if should_enable_optimized_import_session "auto" "socket" 2>/dev/null; then
        printf "  ✅ auto + socket: optimization enabled\n"
    else
        printf "  ❌ auto + socket: optimization should be enabled\n"
        ((errors++))
    fi

    # Test 2: auto mode + mysql-cli import = enabled
    if should_enable_optimized_import_session "auto" "mysql-cli" 2>/dev/null; then
        printf "  ✅ auto + mysql-cli: optimization enabled\n"
    else
        printf "  ❌ auto + mysql-cli: optimization should be enabled\n"
        ((errors++))
    fi

    # Test 3: auto mode + wp-cli = disabled
    if ! should_enable_optimized_import_session "auto" "wp-cli" 2>/dev/null; then
        printf "  ✅ auto + wp-cli: optimization disabled (correct)\n"
    else
        printf "  ❌ auto + wp-cli: optimization should NOT be enabled for WP-CLI\n"
        ((errors++))
    fi

    # Test 4: true mode + socket = enabled
    if should_enable_optimized_import_session "true" "socket" 2>/dev/null; then
        printf "  ✅ true + socket: optimization enabled\n"
    else
        printf "  ❌ true + socket: optimization should be enabled\n"
        ((errors++))
    fi

    # Test 5: false mode + socket = disabled
    if ! should_enable_optimized_import_session "false" "socket" 2>/dev/null; then
        printf "  ✅ false + socket: optimization disabled (correct)\n"
    else
        printf "  ❌ false + socket: optimization should NOT be enabled when forced false\n"
        ((errors++))
    fi

    if [[ "$errors" -eq 0 ]]; then
        pass_test "Session optimization detection works correctly"
    else
        fail_test "$errors optimization detection check(s) failed"
    fi
}

# ================================================================
# Test: _is_truthy helper function
# ================================================================
#
# Description:
#   Tests that _is_truthy correctly identifies boolean true values
#   across different string formats.
#
test_is_truthy_function() {
    start_test "Truthy Value Detection" "_is_truthy recognizes true/yes/1/on variants"

    if ! source "$PROJECT_ROOT_DIR/lib/database/db_import.sh" >/dev/null 2>&1; then
        fail_test "Could not source db_import.sh"
        return 1
    fi

    if ! declare -F _is_truthy >/dev/null 2>&1; then
        fail_test "_is_truthy function not found"
        return 1
    fi

    local errors=0

    # Test truthy values
    for value in "true" "True" "TRUE" "yes" "Yes" "YES" "1" "on" "ON"; do
        if _is_truthy "$value" 2>/dev/null; then
            printf "  ✅ '%s' recognized as truthy\n" "$value"
        else
            printf "  ❌ '%s' should be truthy\n" "$value"
            ((errors++))
        fi
    done

    # Test falsy values
    for value in "false" "False" "FALSE" "no" "No" "NO" "0" "off" "OFF" "maybe" "" "random"; do
        if ! _is_truthy "$value" 2>/dev/null; then
            printf "  ✅ '%s' recognized as falsy\n" "$value"
        else
            printf "  ❌ '%s' should be falsy\n" "$value"
            ((errors++))
        fi
    done

    if [[ "$errors" -eq 0 ]]; then
        pass_test "_is_truthy function works correctly"
    else
        fail_test "$errors truthy value check(s) failed"
    fi
}

# ================================================================
# Test: Import method selection (socket vs mysql-cli vs wp-cli)
# ================================================================
#
# Description:
#   Tests that the import flow selects the correct method based on
#   availability (socket available → use socket,
#   no socket but mysql available → use mysql CLI,
#   otherwise → use WP-CLI).
#
test_import_method_priority() {
    start_test "Import Method Priority" "Socket > MySQL CLI > WP-CLI path selection"

    if ! source "$PROJECT_ROOT_DIR/lib/module_loader.sh" >/dev/null 2>&1; then
        fail_test "Could not source module_loader.sh"
        return 1
    fi

    load_modules >/dev/null 2>&1

    local errors=0

    # This is a logic verification test; actual import would require MySQL
    # We verify the decision logic is present in the code

    # Check that perform_db_import function exists
    if declare -F perform_db_import >/dev/null 2>&1; then
        printf "  ✅ perform_db_import function available\n"
    else
        printf "  ❌ perform_db_import function not found\n"
        ((errors++))
    fi

    # Check that perform_db_import_via_socket function exists
    if declare -F perform_db_import_via_socket >/dev/null 2>&1; then
        printf "  ✅ perform_db_import_via_socket function available\n"
    else
        printf "  ❌ perform_db_import_via_socket function not found\n"
        ((errors++))
    fi

    # Verify the multi-path logic by checking function signatures
    local perform_sig
    perform_sig=$(declare -f perform_db_import | grep -c "import_method")
    if [[ "$perform_sig" -gt 0 ]]; then
        printf "  ✅ perform_db_import tracks import method selection\n"
    else
        printf "  ❌ perform_db_import should track which method was used\n"
        ((errors++))
    fi

    if [[ "$errors" -eq 0 ]]; then
        pass_test "Import method priority logic is in place"
    else
        fail_test "$errors method priority check(s) failed"
    fi
}

# ================================================================
# Test: MySQL CLI fallback when socket unavailable
# ================================================================
#
# Description:
#   Tests that when socket is not available (but mysql CLI is),
#   the tool correctly falls back to direct mysql import instead
#   of immediately jumping to WP-CLI.
#
test_mysql_cli_fallback_when_socket_unavailable() {
    start_test "MySQL CLI Fallback" "mysql-cli attempted before WP-CLI when socket missing"

    # This is a code structure test
    if ! grep -q "mysql via DB_HOST (TCP)" "$PROJECT_ROOT_DIR/lib/database/db_import.sh" 2>/dev/null; then
        fail_test "mysql via DB_HOST (TCP) path not found in code"
        return 1
    fi

    # Check fallback messaging
    if grep -q "Direct mysql import failed, falling back to WP-CLI" "$PROJECT_ROOT_DIR/lib/database/db_import.sh" 2>/dev/null; then
        pass_test "MySQL CLI fallback to WP-CLI logic is implemented"
    else
        fail_test "MySQL CLI fallback messaging not found"
    fi
}

# ================================================================
# Test: Session optimization skipped on WP-CLI
# ================================================================
#
# Description:
#   Tests that session-level optimization flags (AUTOCOMMIT, etc.)
#   are never applied when using WP-CLI fallback path.
#
test_session_optimization_skipped_on_wpcli() {
    start_test "Session Optimization Gating" "Optimization flags skip WP-CLI fallback"

    if ! source "$PROJECT_ROOT_DIR/lib/database/db_import.sh" >/dev/null 2>&1; then
        fail_test "Could not source db_import.sh"
        return 1
    fi

    local errors=0

    # Verify that optimization is only applied to socket and mysql-cli paths
    if should_enable_optimized_import_session "true" "wp-cli" 2>/dev/null; then
        printf "  ❌ Optimization should NOT apply to WP-CLI\n"
        ((errors++))
    else
        printf "  ✅ Optimization correctly skipped for WP-CLI\n"
    fi

    if should_enable_optimized_import_session "true" "wp-cli-direct" 2>/dev/null; then
        printf "  ❌ Optimization should NOT apply to WP-CLI direct\n"
        ((errors++))
    else
        printf "  ✅ Optimization correctly skipped for WP-CLI direct\n"
    fi

    if [[ "$errors" -eq 0 ]]; then
        pass_test "Session optimization correctly gated to direct mysql only"
    else
        fail_test "$errors optimization gating check(s) failed"
    fi
}

# ================================================================
# Test: Parallel import warning (not implemented yet)
# ================================================================
#
# Description:
#   Tests that if parallel_import=true is set, a warning is shown
#   and import continues with safe single-stream method.
#
test_parallel_import_warning() {
    start_test "Parallel Import Guard" "Parallel mode shows warning and uses safe path"

    # Check that warning message exists in code
    if grep -q "parallel_import=true requested, but generic SQL files are order-sensitive" "$PROJECT_ROOT_DIR/lib/database/db_import.sh" 2>/dev/null; then
        printf "  ✅ Parallel import warning is present\n"
        pass_test "Parallel import safety guard is in place"
    else
        fail_test "Parallel import warning message not found"
    fi
}

# ================================================================
# Test: New config keys loading (import_optimizations, parallel_import)
# ================================================================
#
# Description:
#   Tests that the new configuration keys are properly loaded from
#   config file and exported as environment variables.
#
test_import_config_keys_loading() {
    start_test "Import Config Keys Loading" "import_optimizations and parallel_import loaded from config"

    if ! source "$PROJECT_ROOT_DIR/lib/module_loader.sh" >/dev/null 2>&1; then
        fail_test "Could not source module_loader.sh"
        return 1
    fi

    load_modules >/dev/null 2>&1

    if ! declare -F load_import_config >/dev/null 2>&1; then
        fail_test "load_import_config function not found"
        return 1
    fi

    # Create a temp config with new keys
    local tmp_config
    tmp_config=$(mktemp "/tmp/test_perf_config_$$.XXXXXX.conf")
    cat > "$tmp_config" << 'EOF'
[general]
sql_file=test.sql
old_domain=example.com
new_domain=example.test
import_optimizations=true
parallel_import=false
EOF

    unset CONFIG_IMPORT_OPTIMIZATIONS CONFIG_PARALLEL_IMPORT

    load_import_config "$tmp_config" >/dev/null 2>&1
    rm -f "$tmp_config"

    local errors=0
    [[ "$CONFIG_IMPORT_OPTIMIZATIONS" == "true" ]] || { printf "  ❌ CONFIG_IMPORT_OPTIMIZATIONS: expected 'true', got '%s'\n" "$CONFIG_IMPORT_OPTIMIZATIONS"; ((errors++)); }
    [[ "$CONFIG_PARALLEL_IMPORT" == "false" ]] || { printf "  ❌ CONFIG_PARALLEL_IMPORT: expected 'false', got '%s'\n" "$CONFIG_PARALLEL_IMPORT"; ((errors++)); }

    if [[ "$errors" -eq 0 ]]; then
        printf "  ✅ CONFIG_IMPORT_OPTIMIZATIONS: %s\n" "$CONFIG_IMPORT_OPTIMIZATIONS"
        printf "  ✅ CONFIG_PARALLEL_IMPORT: %s\n" "$CONFIG_PARALLEL_IMPORT"
        pass_test "New config keys load correctly"
    else
        fail_test "$errors config key(s) did not load correctly"
    fi
}

# ================================================================
# Test: Config defaults when keys absent
# ================================================================
#
# Description:
#   Tests that missing optimization keys default to sensible values.
#
test_import_config_defaults() {
    start_test "Import Config Defaults" "Missing keys default to safe values"

    if ! source "$PROJECT_ROOT_DIR/lib/module_loader.sh" >/dev/null 2>&1; then
        fail_test "Could not source module_loader.sh"
        return 1
    fi

    load_modules >/dev/null 2>&1

    if ! declare -F load_import_config >/dev/null 2>&1; then
        fail_test "load_import_config function not found"
        return 1
    fi

    # Create a config WITHOUT the new keys
    local tmp_config
    tmp_config=$(mktemp "/tmp/test_default_config_$$.XXXXXX.conf")
    cat > "$tmp_config" << 'EOF'
[general]
sql_file=test.sql
old_domain=example.com
new_domain=example.test

[site_mappings]
EOF

    unset CONFIG_IMPORT_OPTIMIZATIONS CONFIG_PARALLEL_IMPORT

    load_import_config "$tmp_config" >/dev/null 2>&1
    rm -f "$tmp_config"

    local errors=0
    [[ "$CONFIG_IMPORT_OPTIMIZATIONS" == "auto" ]] || { printf "  ❌ CONFIG_IMPORT_OPTIMIZATIONS: expected 'auto' (default), got '%s'\n" "$CONFIG_IMPORT_OPTIMIZATIONS"; ((errors++)); }
    [[ "$CONFIG_PARALLEL_IMPORT" == "false" ]] || { printf "  ❌ CONFIG_PARALLEL_IMPORT: expected 'false' (default), got '%s'\n" "$CONFIG_PARALLEL_IMPORT"; ((errors++)); }

    if [[ "$errors" -eq 0 ]]; then
        printf "  ✅ CONFIG_IMPORT_OPTIMIZATIONS defaults to: auto\n"
        printf "  ✅ CONFIG_PARALLEL_IMPORT defaults to: false\n"
        pass_test "Config defaults are safe and sensible"
    else
        fail_test "$errors default value(s) incorrect"
    fi
}

# ================================================================
# Test: portable millisecond clock
# ================================================================
#
# Description:
#   Verifies _now_ms returns numeric milliseconds, advances with time, and
#   still works when `date +%s%N` is unsupported (older BSD/macOS prints "N").
#
test_portable_ms_clock() {
    start_test "Portable Millisecond Clock" "_now_ms works when date has no nanosecond support"

    if ! source "$PROJECT_ROOT_DIR/lib/database/db_import.sh" >/dev/null 2>&1; then
        fail_test "Could not source db_import.sh"
        return 1
    fi

    local errors=0 t1 t2 t3

    t1=$(_now_ms)
    sleep 1
    t2=$(_now_ms)
    if [[ "$t1" =~ ^[0-9]{13}$ && "$t2" =~ ^[0-9]{13}$ && $((t2 - t1)) -ge 900 && $((t2 - t1)) -lt 3000 ]]; then
        printf "  ✅ _now_ms returns ms epoch and advances ~1s (%sms)\n" "$((t2 - t1))"
    else
        printf "  ❌ _now_ms invalid or not advancing: '%s' -> '%s'\n" "$t1" "$t2"
        ((errors++))
    fi

    # Simulate BSD date that does not understand %N
    t3=$(
        unset EPOCHREALTIME
        date() { if [[ "$1" == "+%s%N" ]]; then printf '%sN\n' "$(command date +%s)"; else command date "$@"; fi; }
        _now_ms
    )
    if [[ "$t3" =~ ^[0-9]{13}$ ]]; then
        printf "  ✅ _now_ms falls back correctly when date lacks %%N\n"
    else
        printf "  ❌ _now_ms fallback invalid: '%s'\n" "$t3"
        ((errors++))
    fi

    if [[ "$errors" -eq 0 ]]; then
        pass_test "_now_ms is portable"
    else
        fail_test "$errors clock check(s) failed"
    fi
}

# ================================================================
# Run all import performance tests
# ================================================================
#
run_import_performance_tests() {
    printf "\n${CYAN}${BOLD}⚡ Import Performance Feature Tests${RESET}\n"
    printf "%s\n\n" "$(printf '=%.0s' {1..50})"

    init_test_session "import_performance"

    test_import_duration_estimation
    test_portable_ms_clock
    test_should_enable_optimized_import_session
    test_is_truthy_function
    test_import_method_priority
    test_mysql_cli_fallback_when_socket_unavailable
    test_session_optimization_skipped_on_wpcli
    test_parallel_import_warning
    test_import_config_keys_loading
    test_import_config_defaults

    finalize_test_session
    return $?
}

# Run tests if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    run_import_performance_tests
fi
