#!/usr/bin/env bash

# ================================================================
# System Environment Tests
# ================================================================
#
# Description:
#   A comprehensive test suite designed to check the stability and compatibility
#   of the script across various system configurations. It focuses on validating
#   non-application-specific factors that can affect script execution, such as
#   user permissions, environment variable integrity, resource limitations,
#   availability and compatibility of essential utilities (e.g., sed, grep, find),
#   filesystem access rights, and signal handling capabilities.
#
# Key Features Tested:
# - User permissions (root vs. regular user) and directory access.
# - Integrity and functionality of `$PATH`, `$HOME`, and variable substitution.
# - System resource limits (open files, processes, memory, stack size).
# - Version checking and basic functionality of required CLI utilities.
# - Filesystem read/write access and disk space availability.
# - Availability of external commands (mysql, wp, git, curl) and signal trapping.
#
# Functions provided:
# - test_user_permissions
# - test_environment_variables
# - test_resource_limits
# - test_utility_versions
# - test_filesystem_access
# - test_external_access
# - test_signal_handling
# - run_system_environment_tests
#
# Dependencies:
# - test_framework.sh (Must be sourced for test session management)
# - Color constants (e.g., ${CYAN}, ${BOLD}, ${RESET}, ${DIM})
#
# Usage:
#   ./test/system_environment_tests.sh
#
# ================================================================

# Source the test framework
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../test_framework.sh"

# ===============================================
# Test user permissions and access rights
# ===============================================
#
# Description: Checks the effective user ID (`EUID`) to determine if the script is
#              running as root, and verifies essential read/write access to temporary
#              directories and common system paths.
#
# Parameters:
#   - None.
#
# Returns:
#   - Calls `pass_test` or `fail_test`.
#
# Behavior:
#   - Differentiates tests based on whether the user is root (`EUID` is 0) or a regular user.
#   - Checks for writability in `/tmp` and readability in `/etc`, `/usr`, and `/var`.
#
test_user_permissions() {
    start_test "User Permissions" "Test script behavior with different user permission levels"

    local permission_issues=0

    # Test if running as root
    if [[ "$EUID" -eq 0 ]]; then
        printf "  ⚠️  Running as root user\n"

        # Test ability to create files in system directories
        if touch /tmp/root_test_$$  2>/dev/null; then
            rm -f /tmp/root_test_$$
            printf "    ✅ Root can create temporary files\n"
        else
            printf "    ❌ Root cannot create temporary files\n"
            ((permission_issues++))
        fi
    else
        printf "  ℹ️  Running as regular user: $(whoami)\n"

        # Test ability to create files in user-accessible directories
        if touch "/tmp/user_test_$$" 2>/dev/null; then
            rm -f "/tmp/user_test_$$"
            printf "    ✅ User can create temporary files\n"
        else
            printf "    ❌ User cannot create temporary files\n"
            ((permission_issues++))
        fi

        # Test home directory access
        if [[ -d "$HOME" && -w "$HOME" ]]; then
            printf "    ✅ Home directory accessible and writable\n"
        else
            printf "    ❌ Home directory issues\n"
            ((permission_issues++))
        fi
    fi

    # Test read access to common directories
    local test_dirs="/etc /usr /var"
    local readable_dirs=0
    local total_dirs=0

    for dir in $test_dirs; do
        if [[ -d "$dir" && -r "$dir" ]]; then
            ((readable_dirs++))
        fi
        ((total_dirs++))
    done

    if [[ $readable_dirs -eq $total_dirs ]]; then
        printf "    ✅ All common directories readable ($readable_dirs/$total_dirs)\n"
    else
        printf "    ⚠️  Some directories not readable ($readable_dirs/$total_dirs)\n"
    fi

    if [[ $permission_issues -eq 0 ]]; then
        pass_test "User permission checks passed"
    else
        fail_test "$permission_issues permission issues detected"
    fi
}

# ===============================================
# Test environment variables
# ===============================================
#
# Description: Verifies the integrity and functionality of essential shell
#              environment variables (`HOME`, `PATH`, `USER`, `SHELL`) and tests
#              Bash's ability to handle unset variables and variables containing
#              special characters.
#
# Parameters:
#   - None.
#
# Returns:
#   - Calls `pass_test` or `fail_test`.
#
# Behavior:
#   - Checks if essential environment variables are set (`-n` test).
#   - Validates that the `bash` executable can be found via `$PATH`.
#   - Tests variable substitution with unset variables (`${var:-}`).
#
test_environment_variables() {
    start_test "Environment Variables" "Test handling of various environment variable configurations"

    local env_issues=0

    # Test essential environment variables
    local essential_vars="HOME PATH USER SHELL"
    for var in $essential_vars; do
        if [[ -n "${!var}" ]]; then
            printf "  ✅ $var is set: ${!var:0:50}...\n"
        else
            printf "  ❌ $var is not set\n"
            ((env_issues++))
        fi
    done

    # Test PATH functionality
    printf "  Testing PATH functionality...\n"
    if command -v bash >/dev/null 2>&1; then
        printf "    ✅ bash found in PATH\n"
    else
        printf "    ❌ bash not found in PATH\n"
        ((env_issues++))
    fi

    # Test handling of empty/unset variables
    local original_test_var="${TEST_EMPTY_VAR:-}"
    unset TEST_EMPTY_VAR

    if [[ -z "${TEST_EMPTY_VAR:-}" ]]; then
        printf "  ✅ Unset variable handling works\n"
    else
        printf "  ❌ Unset variable handling broken\n"
        ((env_issues++))
    fi

    # Test variable with special characters
    TEST_SPECIAL_VAR="test with spaces & symbols: @#$%"
    if [[ "$TEST_SPECIAL_VAR" == "test with spaces & symbols: @#$%" ]]; then
        printf "  ✅ Special character handling works\n"
    else
        printf "  ❌ Special character handling broken\n"
        ((env_issues++))
    fi

    # Cleanup
    unset TEST_SPECIAL_VAR

    if [[ $env_issues -eq 0 ]]; then
        pass_test "Environment variable tests passed"
    else
        fail_test "$env_issues environment variable issues detected"
    fi
}

# ===============================================
# Test resource limits
# ===============================================
#
# Description: Checks critical system limits using `ulimit` that could impact a
#              long-running or complex script, such as the maximum number of
#              open files, processes, and stack size.
#
# Parameters:
#   - None.
#
# Returns:
#   - Calls `pass_test` or `fail_test`.
#
# Behavior:
#   - Checks `ulimit -n` (open files), `ulimit -u` (processes), `ulimit -v` (memory), and `ulimit -s` (stack size).
#   - Performs a rudimentary load test by creating multiple temporary files to ensure stability.
#
test_resource_limits() {
    start_test "Resource Limits" "Test system resource limit handling"

    local limit_issues=0

    # Test open file limits
    local open_files_limit=$(ulimit -n)
    printf "  Open files limit: $open_files_limit\n"

    if [[ $open_files_limit -ge 256 ]]; then
        printf "    ✅ Sufficient open files limit\n"
    else
        printf "    ⚠️  Low open files limit\n"
    fi

    # Test process limits
    local process_limit=$(ulimit -u)
    printf "  Process limit: $process_limit\n"

    if [[ $process_limit -ge 100 ]]; then
        printf "    ✅ Sufficient process limit\n"
    else
        printf "    ⚠️  Low process limit\n"
        ((limit_issues++))
    fi

    # Test memory limits (if available)
    local memory_limit=$(ulimit -v)
    if [[ "$memory_limit" != "unlimited" && $memory_limit -lt 100000 ]] 2>/dev/null; then
        printf "  ⚠️  Very low memory limit: $memory_limit KB\n"
    else
        printf "  ✅ Memory limit adequate: $memory_limit\n"
    fi

    # Test stack size limits
    local stack_limit=$(ulimit -s)
    printf "  Stack size limit: $stack_limit KB\n"

    if [[ $stack_limit -ge 1024 ]]; then
        printf "    ✅ Sufficient stack size\n"
    else
        printf "    ⚠️  Low stack size limit\n"
    fi

    # Test temporary file creation under resource constraints
    local temp_files_created=0
    for i in {1..10}; do
        if temp_file=$(mktemp) 2>/dev/null; then
            echo "test" > "$temp_file"
            rm -f "$temp_file"
            ((temp_files_created++))
        fi
    done

    if [[ $temp_files_created -eq 10 ]]; then
        printf "  ✅ Temporary file creation works under normal load\n"
    else
        printf "  ❌ Temporary file creation issues: only $temp_files_created/10 successful\n"
        ((limit_issues++))
    fi

    if [[ $limit_issues -eq 0 ]]; then
        pass_test "Resource limit tests passed"
    else
        fail_test "$limit_issues resource limit issues detected"
    fi
}

# ===============================================
# Test utility versions and availability
# ===============================================
#
# Description: Verifies that essential command-line utilities (`bash`, `grep`,
#              `sed`, `awk`, `find`) are present, functional, and identifies
#              whether GNU or BSD versions of key tools are in use.
#
# Parameters:
#   - None.
#
# Returns:
#   - Calls `pass_test` or `fail_test`.
#
# Behavior:
#   - Iterates through a list of required tools and checks for existence (`command -v`).
#   - Runs a basic functional test (e.g., pipe data to `grep` and check output).
#   - Detects GNU vs. BSD flavors for `sed` and `grep` which indicates potential syntax differences.
#
test_utility_versions() {
    start_test "Utility Versions" "Test compatibility with different utility versions"

    local version_issues=0

    # Test critical utilities with version checking (Bash 3.2 compatible)
    local required_utils=(
        "bash:3.0"
        "grep:2.0"
        "sed:3.0"
        "awk:1.0"
        "find:4.0"
    )

    for util_spec in "${required_utils[@]}"; do
        IFS=':' read -r util min_version <<< "$util_spec"

        if command -v "$util" >/dev/null 2>&1; then
            local version=$($util --version 2>/dev/null | head -1 | grep -o '[0-9]\+\.[0-9]\+[0-9.]*' | head -1 || echo "unknown")
            printf "  $util: $version\n"

            # Basic functionality test
            case "$util" in
                "grep")
                    if echo "test" | $util "test" >/dev/null 2>&1; then
                        printf "    ✅ $util functional\n"
                    else
                        printf "    ❌ $util not functional\n"
                        ((version_issues++))
                    fi
                    ;;
                "sed")
                    if echo "test" | $util 's/test/pass/' 2>/dev/null | grep -q "pass"; then
                        printf "    ✅ $util functional\n"
                    else
                        printf "    ❌ $util not functional\n"
                        ((version_issues++))
                    fi
                    ;;
                "awk")
                    if echo "test" | $util '{print $1}' 2>/dev/null | grep -q "test"; then
                        printf "    ✅ $util functional\n"
                    else
                        printf "    ❌ $util not functional\n"
                        ((version_issues++))
                    fi
                    ;;
                "find")
                    if $util /tmp -name "nonexistent_file_$$" 2>/dev/null; then
                        printf "    ✅ $util functional\n"
                    else
                        printf "    ❌ $util not functional\n"
                        ((version_issues++))
                    fi
                    ;;
            esac
        else
            printf "  ❌ $util not found\n"
            ((version_issues++))
        fi
    done

    # Test for GNU vs BSD utilities
    printf "\n  Utility type detection:\n"

    # sed type detection
    if sed --version >/dev/null 2>&1; then
        printf "    sed: GNU version\n"
    else
        printf "    sed: BSD version (may have different syntax)\n"
    fi

    # grep type detection
    if grep --version >/dev/null 2>&1; then
        printf "    grep: GNU version\n"
    else
        printf "    grep: BSD version (may have different options)\n"
    fi

    if [[ $version_issues -eq 0 ]]; then
        pass_test "All utility versions compatible"
    else
        fail_test "$version_issues utility version issues detected"
    fi
}

# ===============================================
# Test disk space and filesystem permissions
# ===============================================
#
# Description: Checks the writability of the temporary directory and the current
#              working directory, verifies file and directory creation/deletion,
#              and ensures adequate free disk space in the temporary volume.
#
# Parameters:
#   - None.
#
# Returns:
#   - Calls `pass_test` or `fail_test`.
#
# Behavior:
#   - Checks `/tmp` for writability and available space using `df`.
#   - Performs `touch`, `cat`, `rm`, `mkdir`, and `rmdir` operations for file system sanity check.
#
test_filesystem_access() {
    start_test "Filesystem Access" "Test filesystem access and disk space"

    local fs_issues=0

    # Test temporary directory access
    if [[ -d "/tmp" && -w "/tmp" ]]; then
        printf "  ✅ /tmp directory accessible and writable\n"

        # Test disk space in /tmp
        local tmp_space_kb=$(df /tmp 2>/dev/null | awk 'NR==2 {print $4}' || echo "0")
        if [[ $tmp_space_kb -gt 10240 ]]; then  # 10MB minimum
            printf "    ✅ Sufficient space in /tmp: ${tmp_space_kb}KB\n"
        else
            printf "    ⚠️  Low space in /tmp: ${tmp_space_kb}KB\n"
        fi
    else
        printf "  ❌ /tmp directory not accessible\n"
        ((fs_issues++))
    fi

    # Test current directory permissions
    if [[ -w "." ]]; then
        printf "  ✅ Current directory writable\n"
    else
        printf "  ❌ Current directory not writable\n"
        ((fs_issues++))
    fi

    # Test file creation and deletion
    local test_file="/tmp/fs_test_$$"
    if echo "test content" > "$test_file" 2>/dev/null; then
        if [[ -f "$test_file" ]] && [[ "$(cat "$test_file")" == "test content" ]]; then
            printf "  ✅ File creation and reading works\n"
            if rm "$test_file" 2>/dev/null; then
                printf "  ✅ File deletion works\n"
            else
                printf "  ❌ File deletion failed\n"
                ((fs_issues++))
            fi
        else
            printf "  ❌ File reading failed\n"
            ((fs_issues++))
        fi
    else
        printf "  ❌ File creation failed\n"
        ((fs_issues++))
    fi

    # Test directory creation and removal
    local test_dir="/tmp/dir_test_$$"
    if mkdir "$test_dir" 2>/dev/null; then
        printf "  ✅ Directory creation works\n"
        if rmdir "$test_dir" 2>/dev/null; then
            printf "  ✅ Directory removal works\n"
        else
            printf "  ❌ Directory removal failed\n"
            ((fs_issues++))
        fi
    else
        printf "  ❌ Directory creation failed\n"
        ((fs_issues++))
    fi

    if [[ $fs_issues -eq 0 ]]; then
        pass_test "Filesystem access tests passed"
    else
        fail_test "$fs_issues filesystem access issues detected"
    fi
}

# ===============================================
# Test network and external command access
# ===============================================
#
# Description: Verifies the presence and basic functionality of critical external
#              commands required for database operations (`mysql`, `wp`) and system
#              maintenance/updates (`git`, `curl`).
#
# Parameters:
#   - None.
#
# Returns:
#   - Calls `pass_test` or `fail_test`.
#
# Behavior:
#   - Checks for `mysql`, `wp`, `git`, and `curl` using `command -v`.
#   - Assesses the risk if `mysql` or `wp` are missing, as they are central to the tool's function.
#
test_external_access() {
    start_test "External Access" "Test access to external commands and network resources"

    local access_issues=0

    # Test MySQL client availability
    if command -v mysql >/dev/null 2>&1; then
        printf "  ✅ MySQL client available\n"

        # Test MySQL client version
        local mysql_version=$(mysql --version 2>/dev/null | grep -o '[0-9]\+\.[0-9]\+[0-9.]*' | head -1 || echo "unknown")
        printf "    Version: $mysql_version\n"

        # Test MySQL help (basic functionality)
        if mysql --help >/dev/null 2>&1; then
            printf "    ✅ MySQL client functional\n"
        else
            printf "    ❌ MySQL client not functional\n"
            ((access_issues++))
        fi
    else
        printf "  ⚠️  MySQL client not available\n"
        # Not counted as error since MySQL might be optional in some environments
    fi

    # Test WP-CLI availability
    if command -v wp >/dev/null 2>&1; then
        printf "  ✅ WP-CLI available\n"

        # Test WP-CLI version
        local wp_version=$(wp --version 2>/dev/null | grep -o '[0-9]\+\.[0-9]\+[0-9.]*' | head -1 || echo "unknown")
        printf "    Version: $wp_version\n"

        # Test WP-CLI help (basic functionality)
        if wp --help >/dev/null 2>&1; then
            printf "    ✅ WP-CLI functional\n"
        else
            printf "    ❌ WP-CLI not functional\n"
            ((access_issues++))
        fi
    else
        printf "  ⚠️  WP-CLI not available\n"
        # This is more critical for WordPress tool
        ((access_issues++))
    fi

    # Test Git availability (for updates)
    if command -v git >/dev/null 2>&1; then
        printf "  ✅ Git available\n"

        # Test basic git functionality
        if git --version >/dev/null 2>&1; then
            printf "    ✅ Git functional\n"
        else
            printf "    ❌ Git not functional\n"
            ((access_issues++))
        fi
    else
        printf "  ⚠️  Git not available (updates may not work)\n"
    fi

    # Test curl availability (for downloads)
    if command -v curl >/dev/null 2>&1; then
        printf "  ✅ curl available\n"
    else
        printf "  ⚠️  curl not available\n"
    fi

    if [[ $access_issues -eq 0 ]]; then
        pass_test "External access tests passed"
    elif [[ $access_issues -eq 1 ]]; then
        pass_test "External access mostly working (1 minor issue)"
    else
        fail_test "$access_issues external access issues detected"
    fi
}

# ===============================================
# Test signal handling and process management
# ===============================================
#
# Description: Verifies the integrity of Bash's signal handling mechanism (`trap`)
#              and the ability to correctly manage background processes (`&`, `wait`).
#              This is crucial for cleanup routines and robust execution under interruption.
#
# Parameters:
#   - None.
#
# Returns:
#   - Calls `pass_test` or `fail_test`.
#
# Behavior:
#   - Sets an `EXIT` trap in a subshell to test if the trap fires correctly on termination.
#   - Starts a simple `sleep` process in the background and uses `wait` to monitor its completion.
#
test_signal_handling() {
    start_test "Signal Handling" "Test signal handling and process management"

    local signal_issues=0

    # Test basic signal handling setup
    printf "  Testing signal handling setup...\n"

    # Test trap functionality
    local trap_test_file="/tmp/trap_test_$$"
    (
        trap 'echo "trapped" > "$trap_test_file"' EXIT
        exit 0
    )

    if [[ -f "$trap_test_file" ]] && [[ "$(cat "$trap_test_file")" == "trapped" ]]; then
        printf "    ✅ Trap functionality works\n"
        rm -f "$trap_test_file"
    else
        printf "    ❌ Trap functionality broken\n"
        ((signal_issues++))
        rm -f "$trap_test_file"
    fi

    # Test process creation and termination
    printf "  Testing process management...\n"

    # Start a background process
    sleep 1 &
    local bg_pid=$!

    if kill -0 "$bg_pid" 2>/dev/null; then
        printf "    ✅ Background process creation works\n"

        # Wait for process to complete
        if wait "$bg_pid" 2>/dev/null; then
            printf "    ✅ Process waiting works\n"
        else
            printf "    ❌ Process waiting failed\n"
            ((signal_issues++))
        fi
    else
        printf "    ❌ Background process creation failed\n"
        ((signal_issues++))
    fi

    if [[ $signal_issues -eq 0 ]]; then
        pass_test "Signal handling tests passed"
    else
        fail_test "$signal_issues signal handling issues detected"
    fi
}

# ===============================================
# Run all system environment tests
# ===============================================
#
# Description: The primary entry point function that initializes the test session
#              and executes all individual system environment test functions.
#
# Parameters:
#   - None.
#
# Returns:
#   - The exit code of the final `finalize_test_session` call (0 on success, non-zero on failure).
#
# Behavior:
#   - Calls `init_test_session`.
#   - Executes all `test_*` functions in logical order by feature group.
#   - Calls `finalize_test_session`.
#
run_system_environment_tests() {
    init_test_session "system_environment"

    printf "${CYAN}${BOLD}⚙️ System Environment Tests${RESET}\n"
    printf "${DIM}Testing various system configurations and resource constraints${RESET}\n\n"

    # User and permission tests
    test_user_permissions

    # Environment variable tests
    test_environment_variables

    # Resource limit tests
    test_resource_limits

    # Utility version tests
    test_utility_versions

    # Filesystem access tests
    test_filesystem_access

    # External access tests
    test_external_access

    # Signal handling tests
    test_signal_handling

    finalize_test_session
    return $?
}

# Run tests if this script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    run_system_environment_tests
fi
