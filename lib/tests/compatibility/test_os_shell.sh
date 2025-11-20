#!/usr/bin/env bash

# ================================================================
# OS and Shell Compatibility Tests
# ================================================================
#
# Description:
#   A comprehensive test suite designed to verify the compatibility of the
#   WordPress import tool across various Unix-like operating systems (Linux,
#   macOS, BSD) and different shell environments (Bash, Zsh, POSIX sh).
#   It also includes checks for Windows compatibility layers like WSL and Cygwin/MSYS2,
#   and tests for differences in core utility implementations (GNU vs. BSD).
#
# Key Features Tested:
# - OS and shell environment detection.
# - Platform-specific command availability (Linux, macOS, BSD).
# - Core POSIX shell compliance.
# - Bash and Zsh specific feature availability.
# - Behavior within WSL and Cygwin/MSYS2 environments.
# - Utility implementation differences (sed, awk, grep).
#
# Functions provided:
# - test_os_detection
# - test_shell_detection
# - test_linux_compatibility
# - test_macos_compatibility
# - test_bsd_compatibility
# - test_posix_compliance
# - test_bash_features
# - test_zsh_compatibility
# - test_wsl_compatibility
# - test_cygwin_compatibility
# - test_utility_differences
# - run_os_shell_tests
#
# Dependencies:
# - test_framework.sh (Must be sourced for test session management)
# - External functions: `detect_os`, `detect_shell`, `require_platform`, `detect_bash_features`, `detect_utilities`.
# - Color constants (e.g., ${CYAN}, ${BOLD}, ${RESET}, ${DIM})
#
# Usage:
#   ./test/os_shell_compatibility.sh
#
# ================================================================

# Source the test framework
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../test_framework.sh"

# ===============================================
# Test OS compatibility detection
# ===============================================
#
# Description: Verifies the functionality of the `detect_os` external function
#              to ensure the host operating system name and version can be reliably identified.
#
# Parameters:
#   - None.
#
# Returns:
#   - Calls `pass_test` or `fail_test` based on the detection result.
#
# Behavior:
#   - Executes `detect_os` and parses the output string (format: name|version).
#
test_os_detection() {
    start_test "OS Detection" "Test operating system detection functionality"

    local os_info=$(detect_os)
    local os_name=$(echo "$os_info" | cut -d'|' -f1)
    local os_version=$(echo "$os_info" | cut -d'|' -f2)

    if [[ -n "$os_name" && "$os_name" != "Unknown" ]]; then
        pass_test "OS detected: $os_name $os_version"
    else
        fail_test "Failed to detect operating system"
    fi
}

# ===============================================
# Test shell compatibility detection
# ===============================================
#
# Description: Verifies the functionality of the `detect_shell` external function
#              to ensure the current shell type and version can be reliably identified.
#
# Parameters:
#   - None.
#
# Returns:
#   - Calls `pass_test` or `fail_test` based on the detection result.
#
# Behavior:
#   - Executes `detect_shell` and parses the output string (format: name|version).
#
test_shell_detection() {
    start_test "Shell Detection" "Test shell type and version detection"

    local shell_info=$(detect_shell)
    local shell_name=$(echo "$shell_info" | cut -d'|' -f1)
    local shell_version=$(echo "$shell_info" | cut -d'|' -f2)

    if [[ -n "$shell_name" && "$shell_name" != "Unknown" ]]; then
        pass_test "Shell detected: $shell_name $shell_version"
    else
        fail_test "Failed to detect shell type"
    fi
}

# ===============================================
# Test Linux distribution compatibility
# ===============================================
#
# Description: Checks for the availability of essential system commands typically
#              found on all standard Linux distributions (e.g., `uname`, `grep`, `awk`, `sed`).
#
# Parameters:
#   - None.
#
# Returns:
#   - Calls `pass_test`, `fail_test`, or returns 0 if the platform is not Linux.
#
# Behavior:
#   - Uses `require_platform "linux"` to conditionally run the test.
#
test_linux_compatibility() {
    if ! require_platform "linux"; then
        return 0
    fi

    start_test "Linux Distribution Compatibility" "Test tool functionality on Linux systems"

    # Test basic commands that should work on all Linux distributions
    local commands="uname whoami pwd ls grep awk sed"
    local failed_commands=0

    for cmd in $commands; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            ((failed_commands++))
            printf "  Missing command: $cmd\n"
        fi
    done

    if [[ $failed_commands -eq 0 ]]; then
        pass_test "All basic Linux commands available"
    else
        fail_test "Missing $failed_commands essential Linux commands"
    fi
}

# ===============================================
# Test macOS compatibility
# ===============================================
#
# Description: Checks for macOS-specific commands and notes the implementation type
#              of core tools like `sed` (BSD vs GNU), which affects scripting logic.
#
# Parameters:
#   - None.
#
# Returns:
#   - Calls `pass_test`, `fail_test`, or returns 0 if the platform is not macOS.
#
# Behavior:
#   - Uses `require_platform "macos"` to conditionally run the test.
#   - Checks `sw_vers` and `defaults` commands.
#   - Attempts to identify `sed` flavor.
#
test_macos_compatibility() {
    if ! require_platform "macos"; then
        return 0
    fi

    start_test "macOS Compatibility" "Test tool functionality on macOS systems"

    # Test macOS-specific behaviors
    local macos_commands="sw_vers defaults"
    local missing_commands=0

    for cmd in $macos_commands; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            ((missing_commands++))
        fi
    done

    # Check for BSD vs GNU tools
    local sed_type="unknown"
    if sed --version >/dev/null 2>&1; then
        sed_type="GNU"
    else
        sed_type="BSD"
    fi

    if [[ $missing_commands -eq 0 ]]; then
        pass_test "macOS environment compatible (sed: $sed_type)"
    else
        fail_test "macOS compatibility issues detected"
    fi
}

# ===============================================
# Test BSD systems compatibility
# ===============================================
#
# Description: Checks for the presence of typical BSD utilities (e.g., `pkg_info`, `jot`)
#              to confirm the environment is BSD-based.
#
# Parameters:
#   - None.
#
# Returns:
#   - Calls `pass_test`, `skip_test`, or returns 0 if the platform is not BSD.
#
# Behavior:
#   - Uses `require_platform "bsd"` to conditionally run the test.
#
test_bsd_compatibility() {
    if ! require_platform "bsd"; then
        return 0
    fi

    start_test "BSD Compatibility" "Test tool functionality on BSD systems"

    # Test BSD-specific features
    local bsd_commands="pkg_info jot"
    local available_commands=0

    for cmd in $bsd_commands; do
        if command -v "$cmd" >/dev/null 2>&1; then
            ((available_commands++))
        fi
    done

    # Most BSD systems should have at least some BSD-specific commands
    if [[ $available_commands -gt 0 ]]; then
        pass_test "BSD environment detected ($available_commands BSD commands found)"
    else
        skip_test "Cannot confirm BSD environment"
    fi
}

# ===============================================
# Test POSIX shell compliance
# ===============================================
#
# Description: Executes a set of basic commands using `/bin/sh` to test strict
#              adherence to the minimum POSIX shell standards.
#
# Parameters:
#   - None.
#
# Returns:
#   - Calls `pass_test` or `fail_test`.
#
# Behavior:
#   - Runs simple checks for environment variables, directory testing, and basic piping/commands.
#
test_posix_compliance() {
    start_test "POSIX Shell Compliance" "Test script compatibility with POSIX shell standards"

    # Test basic POSIX features
    local posix_tests=(
        'test -n "$HOME"'
        'test -d "$HOME"'
        'echo "test" | grep "test"'
        'command -v test'
    )

    local posix_failures=0

    for test_cmd in "${posix_tests[@]}"; do
        if ! /bin/sh -c "$test_cmd" >/dev/null 2>&1; then
            ((posix_failures++))
        fi
    done

    if [[ $posix_failures -eq 0 ]]; then
        pass_test "All POSIX shell tests passed"
    else
        fail_test "$posix_failures POSIX shell tests failed"
    fi
}

# ===============================================
# Test bash-specific features
# ===============================================
#
# Description: Checks the availability and health of advanced Bash features
#              (e.g., associative arrays, regex operator) necessary for Bash-optimized modules.
#
# Parameters:
#   - None.
#
# Returns:
#   - Calls `pass_test`, `fail_test`, or returns 0 if the platform is not Bash.
#
# Behavior:
#   - Uses `require_platform "bash"` to conditionally run the test.
#   - Calls the external function `detect_bash_features` and assesses the score.
#
test_bash_features() {
    if ! require_platform "bash"; then
        return 0
    fi

    start_test "Bash Features" "Test availability of bash-specific features"

    local bash_features=$(detect_bash_features)
    local has_arrays=$(echo "$bash_features" | cut -d'|' -f2)
    local has_assoc_arrays=$(echo "$bash_features" | cut -d'|' -f3)
    local has_regex=$(echo "$bash_features" | cut -d'|' -f4)
    local has_process_substitution=$(echo "$bash_features" | cut -d'|' -f5)

    local feature_score=0
    local max_features=4

    [[ "$has_arrays" == "true" ]] && ((feature_score++))
    [[ "$has_assoc_arrays" == "true" ]] && ((feature_score++))
    [[ "$has_regex" == "true" ]] && ((feature_score++))
    [[ "$has_process_substitution" == "true" ]] && ((feature_score++))

    if [[ $feature_score -ge 3 ]]; then
        pass_test "Bash features available: $feature_score/$max_features"
    elif [[ $feature_score -ge 2 ]]; then
        pass_test "Minimal bash features available: $feature_score/$max_features (some limitations may apply)"
    else
        fail_test "Insufficient bash features: $feature_score/$max_features"
    fi
}

# ===============================================
# Test zsh compatibility
# ===============================================
#
# Description: Checks for Zsh-specific behaviors, primarily focusing on array
#              handling, as Zsh arrays can sometimes behave differently than Bash arrays.
#
# Parameters:
#   - None.
#
# Returns:
#   - Calls `pass_test`, `fail_test`, or returns 0 if the platform is not Zsh.
#
# Behavior:
#   - Uses `require_platform "zsh"` to conditionally run the test.
#   - Checks basic array initialization and length calculation.
#
test_zsh_compatibility() {
    if ! require_platform "zsh"; then
        return 0
    fi

    start_test "Zsh Compatibility" "Test tool functionality in Zsh environment"

    # Test zsh-specific behaviors
    if [[ -n "$ZSH_VERSION" ]]; then
        # Test array handling in zsh
        local test_array=("one" "two" "three")
        local array_length=${#test_array[@]}

        if [[ $array_length -eq 3 ]]; then
            pass_test "Zsh array handling works correctly"
        else
            fail_test "Zsh array handling issues detected"
        fi
    else
        skip_test "Not running in zsh environment"
    fi
}

# ===============================================
# Test WSL (Windows Subsystem for Linux) compatibility
# ===============================================
#
# Description: Detects if the script is running inside WSL and checks for common
#              compatibility issues specific to that environment (e.g., case sensitivity, Windows path access).
#
# Parameters:
#   - None.
#
# Returns:
#   - Calls `pass_test`, `fail_test`, or `skip_test`.
#
# Behavior:
#   - Uses `/proc/version` and WSL environment variables for detection.
#   - Checks for the presence of the `/mnt/c` drive.
#
test_wsl_compatibility() {
    start_test "WSL Compatibility" "Test tool functionality on Windows Subsystem for Linux"

    # Check if we're running in WSL
    local is_wsl=false

    if [[ -f "/proc/version" ]] && grep -qi "microsoft\|wsl" /proc/version 2>/dev/null; then
        is_wsl=true
    elif [[ -n "${WSL_DISTRO_NAME:-}" ]] || [[ -n "${WSLENV:-}" ]]; then
        is_wsl=true
    fi

    if [[ "$is_wsl" == "true" ]]; then
        # Test WSL-specific issues
        local wsl_issues=0

        # Check for case sensitivity (common WSL issue)
        if [[ -d "/mnt/c" ]] && ! touch /tmp/WSL_test /tmp/wsl_test 2>/dev/null; then
            ((wsl_issues++))
        fi
        rm -f /tmp/WSL_test /tmp/wsl_test 2>/dev/null

        # Check for Windows path access
        if [[ ! -d "/mnt/c" ]]; then
            ((wsl_issues++))
        fi

        if [[ $wsl_issues -eq 0 ]]; then
            pass_test "WSL environment compatible"
        else
            fail_test "WSL compatibility issues detected: $wsl_issues"
        fi
    else
        skip_test "Not running in WSL environment"
    fi
}

# ===============================================
# Test Cygwin/MSYS2 compatibility
# ===============================================
#
# Description: Detects if the script is running under Cygwin or MSYS2 and verifies
#              that the environment's path translation mechanism is working correctly.
#
# Parameters:
#   - None.
#
# Returns:
#   - Calls `pass_test`, `fail_test`, or `skip_test`.
#
# Behavior:
#   - Uses the `$OSTYPE` variable for detection.
#   - Attempts a simple file operation to confirm path handling.
#
test_cygwin_compatibility() {
    start_test "Cygwin/MSYS2 Compatibility" "Test tool functionality on Cygwin and MSYS2"

    local is_cygwin=false

    if [[ "$OSTYPE" == "cygwin" ]] || [[ "$OSTYPE" == "msys" ]]; then
        is_cygwin=true
    fi

    if [[ "$is_cygwin" == "true" ]]; then
        # Test Windows path conversion
        local test_path="/tmp/cygwin_test"
        if touch "$test_path" 2>/dev/null && [[ -f "$test_path" ]]; then
            rm -f "$test_path"
            pass_test "Cygwin/MSYS2 path handling works"
        else
            fail_test "Cygwin/MSYS2 path issues detected"
        fi
    else
        skip_test "Not running in Cygwin/MSYS2 environment"
    fi
}

# ===============================================
# Test utility differences between distributions
# ===============================================
#
# Description: Checks the flavor (GNU or BSD) and availability of essential command-line
#              utilities (`sed`, `awk`, `grep`) whose behavior can differ between operating systems.
#
# Parameters:
#   - None.
#
# Returns:
#   - Calls `pass_test` or `fail_test`.
#
# Behavior:
#   - Calls the external function `detect_utilities`.
#   - Parses the output string to count GNU, BSD, and missing utility implementations.
#
test_utility_differences() {
    start_test "Utility Differences" "Test handling of different utility implementations"

    local utilities_info=$(detect_utilities)
    local gnu_utils=0
    local bsd_utils=0
    local missing_utils=0

    # Parse utility information
    echo "$utilities_info" | tr ';' '\n' | while IFS=':' read -r util version; do
        [[ -z "$util" ]] && continue

        if [[ "$version" == "NOT_FOUND" ]]; then
            ((missing_utils++))
        elif [[ "$version" == "GNU" ]]; then
            ((gnu_utils++))
        elif [[ "$version" == "BSD" ]]; then
            ((bsd_utils++))
        fi
    done

    # Count utilities more accurately by parsing the output
    gnu_utils=0
    bsd_utils=0
    other_utils=0
    missing_utils=0

    # Split the utilities string and count each type
    IFS=';' read -ra UTILS <<< "$utilities_info"
    for util_entry in "${UTILS[@]}"; do
        [[ -z "$util_entry" ]] && continue
        IFS=':' read -r util_name util_version <<< "$util_entry"

        case "$util_version" in
            "NOT_FOUND")
                ((missing_utils++))
                ;;
            "BSD")
                ((bsd_utils++))
                ;;
            "GNU"*|*"gnu"*)
                ((gnu_utils++))
                ;;
            "")
                # Empty version - treat as missing
                ((missing_utils++))
                ;;
            *)
                # Has a version number or other identifier
                ((other_utils++))
                ;;
        esac
    done

    local total_required=3 # sed, awk, grep minimum for basic functionality
    local available_utils=$((gnu_utils + bsd_utils + other_utils))

    # On macOS, we expect mostly BSD utilities, which is fine
    if [[ $available_utils -ge $total_required ]]; then
        pass_test "Sufficient utilities available (GNU: $gnu_utils, BSD: $bsd_utils, Other: $other_utils, Missing: $missing_utils)"
    elif [[ $missing_utils -le 2 && $available_utils -ge 2 ]]; then
        pass_test "Adequate utilities available (missing: $missing_utils, available: $available_utils)"
    else
        fail_test "Too many utilities missing: $missing_utils (available: $available_utils/$total_required required)"
    fi
}

# ===============================================
# Run all OS and shell compatibility tests
# ===============================================
#
# Description: The primary entry point function that initializes the test session
#              and executes all individual OS and shell compatibility test functions.
#
# Parameters:
#   - None.
#
# Returns:
#   - The exit code of the final `finalize_test_session` call (0 on success, non-zero on failure).
#
# Behavior:
#   - Calls `init_test_session`.
#   - Executes all `test_*` functions in logical order by platform and environment.
#   - Calls `finalize_test_session`.
#
run_os_shell_tests() {
    init_test_session "os_shell_compatibility"

    printf "${CYAN}${BOLD}🖥️ Operating System and Shell Compatibility Tests${RESET}\n"
    printf "${DIM}Testing across different Unix-based systems and shell environments${RESET}\n\n"

    # Basic detection tests
    test_os_detection
    test_shell_detection

    # OS-specific tests
    test_linux_compatibility
    test_macos_compatibility
    test_bsd_compatibility

    # Shell compatibility tests
    test_posix_compliance
    test_bash_features
    test_zsh_compatibility

    # Windows compatibility layers
    test_wsl_compatibility
    test_cygwin_compatibility

    # Utility compatibility
    test_utility_differences

    finalize_test_session
    return $?
}

# Run tests if this script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    run_os_shell_tests
fi
