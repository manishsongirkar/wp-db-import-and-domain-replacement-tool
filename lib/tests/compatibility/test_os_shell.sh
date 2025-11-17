#!/bin/bash

# ===============================================
# OS and Shell Compatibility Tests
# ===============================================
#
# Tests for different Unix-based operating systems and shell types
# to ensure the WordPress import tool works across various environments.
#
# ===============================================

# Source the test framework
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../test_framework.sh"

# Test OS compatibility detection
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

# Test shell compatibility detection
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

# Test Linux distribution compatibility
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

# Test macOS compatibility
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

# Test BSD systems compatibility
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

# Test POSIX shell compliance
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

# Test bash-specific features
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

# Test zsh compatibility
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

# Test WSL (Windows Subsystem for Linux) compatibility
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

# Test Cygwin/MSYS2 compatibility
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

# Test utility differences between distributions
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

# Run all OS and shell compatibility tests
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
