#!/usr/bin/env bash

# ================================================================
# WordPress Database Import Tool - Test Framework
# ================================================================
#
# Description:
#   This file provides the core Bash testing framework used to validate the
#   WordPress database import tool across various environments and configurations.
#   It includes utilities for detecting the operating system and shell, managing
#   test sessions, providing powerful assertion functions, and generating
#   detailed, color-coded reports.
#
# Key Features:
# - Cross-platform environment detection (OS, Shell, Utilities, Bash features).
# - Test isolation using temporary directories and subshells.
# - Comprehensive assertion functions (e.g., equals, contains, file/command existence).
# - Test result logging to JSON files for machine readability.
# - Requirement checks for skipping tests based on platform or command availability.
# - Color-coded output for enhanced readability.
#
# Global Variables:
# - TEST_FRAMEWORK_VERSION, TEST_COUNT, TEST_PASSED, TEST_FAILED, TEST_SKIPPED, etc.
# - Color definitions (RED, GREEN, YELLOW, etc.)
# - Directory paths (TEST_FRAMEWORK_DIR, PROJECT_ROOT_DIR)
#
# ================================================================

# Test Framework Global Variables
TEST_FRAMEWORK_VERSION="1.0.0"
TEST_RESULTS_DIR=""
TEST_SESSION_ID=""
TEST_COUNT=0
TEST_PASSED=0
TEST_FAILED=0
TEST_SKIPPED=0
TEST_CURRENT=""
TEST_START_TIME=""
TEST_SUITE_START_TIME=""

# Color definitions (ANSI escape codes) - only define if not already set
[[ -z "${RED:-}" ]] && readonly RED='\033[0;31m'
[[ -z "${GREEN:-}" ]] && readonly GREEN='\033[0;32m'
[[ -z "${YELLOW:-}" ]] && readonly YELLOW='\033[1;33m'
[[ -z "${BLUE:-}" ]] && readonly BLUE='\033[0;34m'
[[ -z "${CYAN:-}" ]] && readonly CYAN='\033[0;36m'
[[ -z "${MAGENTA:-}" ]] && readonly MAGENTA='\033[0;35m'
[[ -z "${BOLD:-}" ]] && readonly BOLD='\033[1m'
[[ -z "${DIM:-}" ]] && readonly DIM='\033[2m'
[[ -z "${RESET:-}" ]] && readonly RESET='\033[0m'

# Test framework paths - only define if not already set
[[ -z "${TEST_FRAMEWORK_DIR:-}" ]] && readonly TEST_FRAMEWORK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[[ -z "${TEST_ROOT_DIR:-}" ]] && readonly TEST_ROOT_DIR="$(dirname "$TEST_FRAMEWORK_DIR")"
[[ -z "${PROJECT_ROOT_DIR:-}" ]] && readonly PROJECT_ROOT_DIR="$(dirname "$TEST_ROOT_DIR")"

# ===============================================
# Environment Detection Functions
# ===============================================

# ===============================================
# Detect the operating system
# ===============================================
#
# Description: Identifies the host operating system type (e.g., Linux, macOS, FreeBSD)
#              and attempts to determine the specific distribution or version.
#
# Parameters:
#   - None.
#
# Returns:
#   - The operating system name and version (echoed) in the format `name|version`.
#
# Behavior:
#   - Uses the standard `$OSTYPE` variable for initial detection.
#   - Uses specific commands (`lsb_release`, `sw_vers`, `/etc/os-release`) for version/distribution details.
#
detect_os() {
    local os_name=""
    local os_version=""

    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        os_name="Linux"
        # Try to detect specific distribution
        if command -v lsb_release >/dev/null 2>&1; then
            os_version=$(lsb_release -d | cut -f2)
        elif [[ -f /etc/os-release ]]; then
            os_version=$(grep PRETTY_NAME /etc/os-release | cut -d'"' -f2)
        elif [[ -f /etc/redhat-release ]]; then
            os_version=$(cat /etc/redhat-release)
        elif [[ -f /etc/debian_version ]]; then
            os_version="Debian $(cat /etc/debian_version)"
        else
            os_version="Unknown Linux"
        fi
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        os_name="macOS"
        os_version=$(sw_vers -productVersion)
    elif [[ "$OSTYPE" == "cygwin" ]]; then
        os_name="Cygwin"
        os_version=$(uname -r)
    elif [[ "$OSTYPE" == "msys" ]]; then
        os_name="MSYS2"
        os_version=$(uname -r)
    elif [[ "$OSTYPE" == "freebsd"* ]]; then
        os_name="FreeBSD"
        os_version=$(uname -r)
    elif [[ "$OSTYPE" == "netbsd"* ]]; then
        os_name="NetBSD"
        os_version=$(uname -r)
    elif [[ "$OSTYPE" == "openbsd"* ]]; then
        os_name="OpenBSD"
        os_version=$(uname -r)
    elif [[ "$OSTYPE" == "solaris"* ]]; then
        os_name="Solaris"
        os_version=$(uname -r)
    else
        os_name="Unknown"
        os_version="Unknown"
    fi

    echo "${os_name}|${os_version}"
}

# ===============================================
# Detect the current shell
# ===============================================
#
# Description: Identifies the shell currently executing the script (e.g., bash, zsh, ksh, dash)
#              and extracts its version number where available.
#
# Parameters:
#   - None.
#
# Returns:
#   - The shell name and version (echoed) in the format `name|version`.
#
# Behavior:
#   - Relies on shell-specific variables (`$ZSH_VERSION`, `$BASH_VERSION`, etc.).
#   - Uses `ps -p $$ -o comm=` as a fallback for generic shells like `dash` or `ash`.
#
detect_shell() {
    local shell_name=""
    local shell_version=""

    if [[ -n "$ZSH_VERSION" ]]; then
        shell_name="zsh"
        shell_version="$ZSH_VERSION"
    elif [[ -n "$BASH_VERSION" ]]; then
        shell_name="bash"
        shell_version="$BASH_VERSION"
    elif [[ -n "$KSH_VERSION" ]]; then
        shell_name="ksh"
        shell_version="$KSH_VERSION"
    elif [[ -n "$FISH_VERSION" ]]; then
        shell_name="fish"
        shell_version="$FISH_VERSION"
    elif [[ "$(ps -p $$ -o comm=)" == "dash" ]]; then
        shell_name="dash"
        shell_version=$(dash --version 2>/dev/null | head -1 || echo "Unknown")
    elif [[ "$(ps -p $$ -o comm=)" == "ash" ]]; then
        shell_name="ash"
        shell_version="Unknown"
    else
        shell_name="$(ps -p $$ -o comm=)"
        shell_version="Unknown"
    fi

    echo "${shell_name}|${shell_version}"
}

# ===============================================
# Detect Bash version and features
# ===============================================
#
# Description: Detects the current Bash version and checks for the availability
#              of key Bash-specific features that influence scripting compatibility
#              (e.g., associative arrays, regex operator, process substitution).
#
# Parameters:
#   - None.
#
# Returns:
#   - A string (echoed) containing version and feature flags in the format:
#     `version|has_arrays|has_associative_arrays|has_regex|has_process_substitution`
#
# Behavior:
#   - Uses `declare -a` and `declare -A` to test array feature availability.
#   - Uses the `=~` operator and process substitution syntax to test their availability.
#
detect_bash_features() {
    local bash_version=""
    local has_arrays="false"
    local has_associative_arrays="false"
    local has_regex="false"
    local has_process_substitution="false"

    if [[ -n "$BASH_VERSION" ]]; then
        bash_version="$BASH_VERSION"

        # Check for array support (Bash 2.0+)
        if declare -a test_array >/dev/null 2>&1; then
            has_arrays="true"
        fi

        # Check for associative array support (Bash 4.0+)
        if declare -A test_assoc >/dev/null 2>&1; then
            has_associative_arrays="true"
        fi

        # Check for regex support (Bash 3.0+)
        if [[ "test" =~ ^test$ ]] >/dev/null 2>&1; then
            has_regex="true"
        fi

        # Check for process substitution support
        if echo "test" | cat <(echo "test") >/dev/null 2>&1; then
            has_process_substitution="true"
        fi
    fi

    echo "${bash_version}|${has_arrays}|${has_associative_arrays}|${has_regex}|${has_process_substitution}"
}

# ===============================================
# Detect system utilities and their versions
# ===============================================
#
# Description: Checks for the presence and attempts to determine the version or
#              type (GNU vs. BSD) of a predefined set of essential system utilities.
#
# Parameters:
#   - None.
#
# Returns:
#   - A semicolon-separated string (echoed) detailing each utility's status:
#     `util1:version1;util2:version2;...` (version can be `GNU`, `BSD`, or `NOT_FOUND`).
#
# Behavior:
#   - Uses `command -v` to check for existence.
#   - Uses utility-specific flags (`--version`) and heuristics to determine the flavor (e.g., `sed` and `grep`).
#
detect_utilities() {
    local utilities="sed awk grep find xargs mysql wp git curl"
    local utility_info=""

    for utility in $utilities; do
        if command -v "$utility" >/dev/null 2>&1; then
            local version=""
            case "$utility" in
                sed)
                    if sed --version >/dev/null 2>&1; then
                        version=$(sed --version | head -1 | grep -o '[0-9]\+\.[0-9]\+[0-9.]*' || echo "GNU")
                    else
                        version="BSD"
                    fi
                    ;;
                awk)
                    version=$(awk --version 2>/dev/null | head -1 | grep -o '[0-9]\+\.[0-9]\+[0-9.]*' || echo "Unknown")
                    ;;
                grep)
                    if grep --version >/dev/null 2>&1; then
                        version=$(grep --version | head -1 | grep -o '[0-9]\+\.[0-9]\+[0-9.]*' || echo "GNU")
                    else
                        version="BSD"
                    fi
                    ;;
                mysql)
                    version=$(mysql --version 2>/dev/null | grep -o '[0-9]\+\.[0-9]\+[0-9.]*' | head -1 || echo "Unknown")
                    ;;
                wp)
                    version=$(wp --version 2>/dev/null | grep -o '[0-9]\+\.[0-9]\+[0-9.]*' | head -1 || echo "Unknown")
                    ;;
                *)
                    version=$($utility --version 2>/dev/null | head -1 | grep -o '[0-9]\+\.[0-9]\+[0-9.]*' | head -1 || echo "Unknown")
                    ;;
            esac
            utility_info="${utility_info}${utility}:${version};"
        else
            utility_info="${utility_info}${utility}:NOT_FOUND;"
        fi
    done

    echo "$utility_info"
}

# ===============================================
# Initialize test session
# ===============================================
#
# Description: Sets up the environment for a new test session, including defining
#              global session variables, creating a results directory, and resetting counters.
#
# Parameters:
#   - $1: test_name (A descriptive name for the test session, used for directory naming).
#
# Returns:
#   - Prints initialization status to stdout.
#
# Behavior:
#   - Creates the `$TEST_RESULTS_DIR` structure.
#   - Resets `$TEST_COUNT`, `$TEST_PASSED`, etc.
#   - Calls `create_environment_info`.
#
init_test_session() {
    local test_name="${1:-test_session}"

    TEST_SESSION_ID="${test_name}"
    # Use the main reports directory with a test_sessions subdirectory
    if [[ -n "${OUTPUT_DIR:-}" ]]; then
        TEST_RESULTS_DIR="$OUTPUT_DIR/test_sessions/$TEST_SESSION_ID"
    else
        TEST_RESULTS_DIR="$TEST_FRAMEWORK_DIR/../../reports/test_sessions/$TEST_SESSION_ID"
    fi
    TEST_SUITE_START_TIME=$(date +%s)

    # Create results directory
    mkdir -p "$TEST_RESULTS_DIR"

    # Reset counters
    TEST_COUNT=0
    TEST_PASSED=0
    TEST_FAILED=0
    TEST_SKIPPED=0

    # Create environment info file
    create_environment_info

    printf "${BOLD}${CYAN}🧪 Test Session Initialized: $TEST_SESSION_ID${RESET}\n"
    printf "${DIM}Results Directory: $TEST_RESULTS_DIR${RESET}\n\n"
}

# ===============================================
# Create environment information file
# ===============================================
#
# Description: Gathers comprehensive information about the execution environment
#              (OS, shell, Bash features, utility versions, system limits) and
#              writes it to a JSON file for detailed reporting.
#
# Parameters:
#   - None.
#
# Returns:
#   - Creates a `environment.json` file in `$TEST_RESULTS_DIR`.
#
# Behavior:
#   - Calls external detection functions (`detect_os`, etc.).
#   - Formats the output as structured JSON.
#   - Uses `ulimit` to capture system resource constraints.
#
create_environment_info() {
    local env_file="$TEST_RESULTS_DIR/environment.json"
    local os_info shell_info bash_features utilities_info

    os_info=$(detect_os)
    shell_info=$(detect_shell)
    bash_features=$(detect_bash_features)
    utilities_info=$(detect_utilities)

    cat > "$env_file" <<EOF
{
  "test_session": "$TEST_SESSION_ID",
  "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "environment": {
    "os": {
      "name": "$(echo "$os_info" | cut -d'|' -f1)",
      "version": "$(echo "$os_info" | cut -d'|' -f2)"
    },
    "shell": {
      "name": "$(echo "$shell_info" | cut -d'|' -f1)",
      "version": "$(echo "$shell_info" | cut -d'|' -f2)"
    },
    "bash": {
      "version": "$(echo "$bash_features" | cut -d'|' -f1)",
      "has_arrays": "$(echo "$bash_features" | cut -d'|' -f2)",
      "has_associative_arrays": "$(echo "$bash_features" | cut -d'|' -f3)",
      "has_regex": "$(echo "$bash_features" | cut -d'|' -f4)",
      "has_process_substitution": "$(echo "$bash_features" | cut -d'|' -f5)"
    },
    "utilities": {
$(echo "$utilities_info" | tr ';' '\n' | grep -v '^$' | while IFS=':' read -r util ver; do
    printf '      "%s": "%s"' "$util" "$ver"
    if [[ $(echo "$utilities_info" | tr ';' '\n' | grep -v '^$' | tail -1) != "$util:$ver" ]]; then
        printf ','
    fi
    printf '\n'
done)
    }
  },
  "system_info": {
    "hostname": "$(hostname)",
    "user": "$(whoami)",
    "pwd": "$(pwd)",
    "path": "$PATH",
    "ulimits": {
      "open_files": "$(ulimit -n)",
      "processes": "$(ulimit -u)",
      "memory": "$(ulimit -v)"
    }
  }
}
EOF
}

# ===============================================
# Start a test case
# ===============================================
#
# Description: Marks the beginning of a new test case within the current session,
#              increments the test count, and records the start time.
#
# Parameters:
#   - $1: test_name (The name of the test case).
#   - $2: test_description (Optional short description of what the test does).
#
# Returns:
#   - Updates global variables and prints a formatted header to stdout.
#
start_test() {
    local test_name="$1"
    local test_description="${2:-}"

    TEST_CURRENT="$test_name"
    TEST_START_TIME=$(date +%s)
    ((TEST_COUNT++))

    printf "${BOLD}${BLUE}[TEST $TEST_COUNT] $test_name${RESET}\n"
    if [[ -n "$test_description" ]]; then
        printf "${DIM}Description: $test_description${RESET}\n"
    fi
}

# ===============================================
# Mark test as passed
# ===============================================
#
# Description: Records a successful test result, calculates the duration,
#              increments the pass count, and logs the result.
#
# Parameters:
#   - $1: message (Optional message detailing the successful assertion).
#
# Returns:
#   - Updates global variables and prints success status to stdout.
#
# Behavior:
#   - Calls `log_test_result` with status "PASS".
#
pass_test() {
    local message="${1:-Test passed}"
    local end_time=$(date +%s)
    local duration=$((end_time - TEST_START_TIME))

    ((TEST_PASSED++))

    printf "${GREEN}✅ PASS${RESET} - $message ${DIM}(${duration}s)${RESET}\n\n"

    # Log result
    log_test_result "PASS" "$message" "$duration"
}

# ===============================================
# Mark test as failed
# ===============================================
#
# Description: Records a failed test result, calculates the duration,
#              increments the failure count, and logs the result.
#
# Parameters:
#   - $1: message (Optional message detailing the reason for the failure).
#
# Returns:
#   - Updates global variables and prints failure status to stdout.
#
# Behavior:
#   - Calls `log_test_result` with status "FAIL".
#
fail_test() {
    local message="${1:-Test failed}"
    local end_time=$(date +%s)
    local duration=$((end_time - TEST_START_TIME))

    ((TEST_FAILED++))

    printf "${RED}❌ FAIL${RESET} - $message ${DIM}(${duration}s)${RESET}\n\n"

    # Log result
    log_test_result "FAIL" "$message" "$duration"
}

# ===============================================
# Mark test as skipped
# ===============================================
#
# Description: Records a skipped test result (usually due to unmet environmental
#              requirements), calculates the duration, increments the skip count, and logs the result.
#
# Parameters:
#   - $1: message (Optional message detailing the reason for skipping).
#
# Returns:
#   - Updates global variables and prints skip status to stdout.
#
# Behavior:
#   - Calls `log_test_result` with status "SKIP".
#
skip_test() {
    local message="${1:-Test skipped}"
    local end_time=$(date +%s)
    local duration=$((end_time - TEST_START_TIME))

    ((TEST_SKIPPED++))

    printf "${YELLOW}⏭️ SKIP${RESET} - $message ${DIM}(${duration}s)${RESET}\n\n"

    # Log result
    log_test_result "SKIP" "$message" "$duration"
}

# ===============================================
# Log test result to file
# ===============================================
#
# Description: Appends the result of the currently executing test (`$TEST_CURRENT`)
#              to the session's JSON log file (`test_results.json`).
#
# Parameters:
#   - $1: status (PASS, FAIL, or SKIP).
#   - $2: message (The test message).
#   - $3: duration (The test duration in seconds).
#
# Returns:
#   - Appends a JSON object to the `tests` array in the log file.
#
# Behavior:
#   - Prefers using `jq` for robust JSON manipulation if available.
#   - Falls back to `grep` and `sed` for basic JSON array appending if `jq` is missing.
#
log_test_result() {
    local status="$1"
    local message="$2"
    local duration="$3"
    local log_file="$TEST_RESULTS_DIR/test_results.json"

    # Create log file if it doesn't exist
    if [[ ! -f "$log_file" ]]; then
        echo '{"tests": []}' > "$log_file"
    fi

    # Create temporary file for new result
    local temp_result=$(mktemp)
    cat > "$temp_result" <<EOF
{
  "name": "$TEST_CURRENT",
  "status": "$status",
  "message": "$message",
  "duration": $duration,
  "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
}
EOF

    # Add result to log file (basic JSON append)
    local temp_log=$(mktemp)
    if jq --argjson new_test "$(cat "$temp_result")" '.tests += [$new_test]' "$log_file" > "$temp_log" 2>/dev/null; then
        mv "$temp_log" "$log_file"
    else
        # Fallback if jq is not available
        local existing_tests=$(grep -o '"tests":\[.*\]' "$log_file" | sed 's/"tests":\[\(.*\)\]/\1/')
        if [[ -n "$existing_tests" && "$existing_tests" != "null" ]]; then
            echo "{\"tests\": [$existing_tests, $(cat "$temp_result")]}" > "$log_file"
        else
            echo "{\"tests\": [$(cat "$temp_result")]}" > "$log_file"
        fi
    fi

    rm -f "$temp_result" "$temp_log"
}

# ===============================================
# Assertion Functions
# ===============================================

# ===============================================
# Assert that a command succeeds
# ===============================================
#
# Description: Executes a command and asserts that its exit code is 0 (success).
#
# Parameters:
#   - $1: command (The command string to execute).
#   - $2: message (Optional custom message for the assertion).
#
# Returns:
#   - 0 (Success) if the command succeeds.
#   - 1 (Failure) if the command fails, calling `fail_test`.
#
assert_success() {
    local command="$1"
    local message="${2:-Command should succeed: $command}"

    if eval "$command" >/dev/null 2>&1; then
        pass_test "$message"
        return 0
    else
        fail_test "$message (exit code: $?)"
        return 1
    fi
}

# ===============================================
# Assert that a command fails
# ===============================================
#
# Description: Executes a command and asserts that its exit code is non-zero (failure).
#
# Parameters:
#   - $1: command (The command string to execute).
#   - $2: message (Optional custom message for the assertion).
#
# Returns:
#   - 0 (Success) if the command fails.
#   - 1 (Failure) if the command unexpectedly succeeds, calling `fail_test`.
#
assert_failure() {
    local command="$1"
    local message="${2:-Command should fail: $command}"

    if eval "$command" >/dev/null 2>&1; then
        fail_test "$message (unexpectedly succeeded)"
        return 1
    else
        pass_test "$message"
        return 0
    fi
}

# ===============================================
# Assert that two strings are equal
# ===============================================
#
# Description: Compares two string values and asserts that they are identical.
#
# Parameters:
#   - $1: expected (The expected string value).
#   - $2: actual (The actual string value).
#   - $3: message (Optional custom message for the assertion).
#
# Returns:
#   - 0 (Success) if strings match.
#   - 1 (Failure) if strings do not match, calling `fail_test`.
#
assert_equals() {
    local expected="$1"
    local actual="$2"
    local message="${3:-Expected '$expected', got '$actual'}"

    if [[ "$expected" == "$actual" ]]; then
        pass_test "$message"
        return 0
    else
        fail_test "$message"
        return 1
    fi
}

# ===============================================
# Assert that two strings are not equal
# ===============================================
#
# Description: Compares two string values and asserts that they are different.
#
# Parameters:
#   - $1: expected (The expected string value).
#   - $2: actual (The actual string value).
#   - $3: message (Optional custom message for the assertion).
#
# Returns:
#   - 0 (Success) if strings do not match.
#   - 1 (Failure) if strings are identical, calling `fail_test`.
#
assert_not_equals() {
    local expected="$1"
    local actual="$2"
    local message="${3:-Expected '$expected' to not equal '$actual'}"

    if [[ "$expected" != "$actual" ]]; then
        pass_test "$message"
        return 0
    else
        fail_test "$message"
        return 1
    fi
}

# ===============================================
# Assert that a string contains a substring
# ===============================================
#
# Description: Asserts that a "haystack" string contains a specified "needle" substring.
#
# Parameters:
#   - $1: haystack (The string to search within).
#   - $2: needle (The substring to find).
#   - $3: message (Optional custom message for the assertion).
#
# Returns:
#   - 0 (Success) if the substring is found.
#   - 1 (Failure) if the substring is not found, calling `fail_test`.
#
assert_contains() {
    local haystack="$1"
    local needle="$2"
    local message="${3:-String should contain '$needle': $haystack}"

    if [[ "$haystack" == *"$needle"* ]]; then
        pass_test "$message"
        return 0
    else
        fail_test "$message"
        return 1
    fi
}

# ===============================================
# Assert that a file exists
# ===============================================
#
# Description: Checks the filesystem and asserts that a file exists at the given path.
#
# Parameters:
#   - $1: file (The path to the file).
#   - $2: message (Optional custom message for the assertion).
#
# Returns:
#   - 0 (Success) if the file exists.
#   - 1 (Failure) if the file does not exist, calling `fail_test`.
#
assert_file_exists() {
    local file="$1"
    local message="${2:-File should exist: $file}"

    if [[ -f "$file" ]]; then
        pass_test "$message"
        return 0
    else
        fail_test "$message"
        return 1
    fi
}

# ===============================================
# Assert that a directory exists
# ===============================================
#
# Description: Checks the filesystem and asserts that a directory exists at the given path.
#
# Parameters:
#   - $1: dir (The path to the directory).
#   - $2: message (Optional custom message for the assertion).
#
# Returns:
#   - 0 (Success) if the directory exists.
#   - 1 (Failure) if the directory does not exist, calling `fail_test`.
#
assert_dir_exists() {
    local dir="$1"
    local message="${2:-Directory should exist: $dir}"

    if [[ -d "$dir" ]]; then
        pass_test "$message"
        return 0
    else
        fail_test "$message"
        return 1
    fi
}

# ===============================================
# Assert that a command is available
# ===============================================
#
# Description: Uses `command -v` to check the system PATH and asserts that an
#              executable command is available for use.
#
# Parameters:
#   - $1: command (The name of the executable command).
#   - $2: message (Optional custom message for the assertion).
#
# Returns:
#   - 0 (Success) if the command is found.
#   - 1 (Failure) if the command is not found, calling `fail_test`.
#
assert_command_available() {
    local command="$1"
    local message="${2:-Command should be available: $command}"

    if command -v "$command" >/dev/null 2>&1; then
        pass_test "$message"
        return 0
    else
        fail_test "$message"
        return 1
    fi
}

# ===============================================
# Test Suite Management
# ===============================================

# ===============================================
# Finalize test session and generate reports
# ===============================================
#
# Description: Concludes the current test session, calculates the total duration,
#              prints the summary to the console, and generates the final JSON report.
#
# Parameters:
#   - None.
#
# Returns:
#   - Prints summary to stdout.
#   - Returns 0 (Success) if no tests failed, 1 (Failure) otherwise.
#
# Behavior:
#   - Calls `generate_final_report`.
#   - Determines the exit code based on the value of `$TEST_FAILED`.
#
finalize_test_session() {
    local end_time=$(date +%s)
    local total_duration=$((end_time - TEST_SUITE_START_TIME))

    printf "${BOLD}${CYAN}📊 Test Session Complete: $TEST_SESSION_ID${RESET}\n"
    printf "${BOLD}Results Summary:${RESET}\n"
    printf "  ${GREEN}✅ Passed: $TEST_PASSED${RESET}\n"
    printf "  ${RED}❌ Failed: $TEST_FAILED${RESET}\n"
    printf "  ${YELLOW}⏭️ Skipped: $TEST_SKIPPED${RESET}\n"
    printf "  ${CYAN}📈 Total: $TEST_COUNT${RESET}\n"
    printf "  ${DIM}⏱️ Duration: ${total_duration}s${RESET}\n\n"

    # Generate final report
    generate_final_report "$total_duration"

    # Return appropriate exit code
    if [[ $TEST_FAILED -gt 0 ]]; then
        return 1
    else
        return 0
    fi
}

# ===============================================
# Generate final test report
# ===============================================
#
# Description: Generates a JSON file (`summary.json`) containing the final metrics
#              of the test run (total count, pass/fail numbers, duration, success rate).
#
# Parameters:
#   - $1: total_duration (Total time taken by the test suite in seconds).
#
# Returns:
#   - Creates the `summary.json` file in `$TEST_RESULTS_DIR`.
#
# Behavior:
#   - Calculates the success rate using `bc -l` (if available).
#
generate_final_report() {
    local total_duration="$1"
    local summary_file="$TEST_RESULTS_DIR/summary.json"

    cat > "$summary_file" <<EOF
{
  "test_session": "$TEST_SESSION_ID",
  "summary": {
    "total": $TEST_COUNT,
    "passed": $TEST_PASSED,
    "failed": $TEST_FAILED,
    "skipped": $TEST_SKIPPED,
    "duration": $total_duration,
    "success_rate": $(echo "scale=2; $TEST_PASSED * 100 / $TEST_COUNT" | bc -l 2>/dev/null || echo "0.00")
  },
  "generated_at": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
}
EOF

    printf "${DIM}📄 Reports saved to: $TEST_RESULTS_DIR${RESET}\n"
}

# ===============================================
# Utility Functions
# ===============================================

# ===============================================
# Create a temporary test directory
# ===============================================
#
# Description: Creates a secure, unique temporary directory for test isolation.
#
# Parameters:
#   - $1: test_name (A prefix for the directory name).
#
# Returns:
#   - The path to the newly created directory (echoed).
#
# Behavior:
#   - Uses `mktemp -d` for safety.
#
create_temp_test_dir() {
    local test_name="${1:-test}"
    local temp_dir=$(mktemp -d "/tmp/${test_name}_XXXXXX")
    echo "$temp_dir"
}

# ===============================================
# Clean up temporary test directory
# ===============================================
#
# Description: Safely removes a temporary test directory, ensuring it is located
#              under `/tmp` and preventing accidental deletion of system files.
#
# Parameters:
#   - $1: temp_dir (The path to the directory to remove).
#
# Returns:
#   - Removes the directory using `rm -rf`.
#
# Behavior:
#   - Performs a strict check (`"$temp_dir" == /tmp/*`) before running `rm -rf`.
#
cleanup_temp_test_dir() {
    local temp_dir="$1"
    if [[ -n "$temp_dir" && -d "$temp_dir" && "$temp_dir" == /tmp/* ]]; then
        rm -rf "$temp_dir"
    fi
}

# ===============================================
# Run a test in isolation
# ===============================================
#
# Description: Executes a test function within an isolated temporary directory
#              and a subshell with `set -e` enabled, protecting the main environment
#              from contamination.
#
# Parameters:
#   - $1: test_function (The name of the function to execute).
#   - $2: test_name (The name for the test, optional).
#   - $3: test_description (Optional description).
#
# Returns:
#   - The exit code of the executed test function.
#
# Behavior:
#   - Calls `create_temp_test_dir` and changes directory (`cd`).
#   - Executes the test function in a subshell `(...)` with `set -e`.
#   - Calls `start_test` before execution and `pass_test`/`fail_test` after if the function didn't report already.
#
run_isolated_test() {
    local test_function="$1"
    local test_name="${2:-$test_function}"
    local test_description="$3"

    # Create isolated environment
    local temp_dir=$(create_temp_test_dir "$test_name")
    local old_pwd="$(pwd)"

    # Change to temp directory
    cd "$temp_dir" || return 1

    # Run the test
    start_test "$test_name" "$test_description"

    # Execute test function in subshell to prevent environment contamination
    (
        set -e
        eval "$test_function"
    )
    local test_result=$?

    # Restore environment
    cd "$old_pwd" || true
    cleanup_temp_test_dir "$temp_dir"

    # Report result if test function didn't already do it
    if [[ $test_result -eq 0 ]]; then
        [[ $TEST_PASSED -eq 0 && $TEST_FAILED -eq 0 && $TEST_SKIPPED -eq 0 ]] && pass_test "Isolated test completed successfully"
    else
        [[ $TEST_PASSED -eq 0 && $TEST_FAILED -eq 0 && $TEST_SKIPPED -eq 0 ]] && fail_test "Isolated test failed with exit code $test_result"
    fi

    return $test_result
}

# ===============================================
# Check if we're running on a supported platform
# ===============================================
#
# Description: Checks if the current operating system or shell matches a required platform type.
#
# Parameters:
#   - $1: platform (The required platform: `linux`, `macos`, `bsd`, `bash`, or `zsh`).
#
# Returns:
#   - 0 (Success) if the platform matches.
#   - 1 (Failure) otherwise.
#
# Behavior:
#   - Calls `detect_os` and `detect_shell` internally.
#
is_platform_supported() {
    local platform="$1"
    local os_info shell_info

    os_info=$(detect_os)
    shell_info=$(detect_shell)

    case "$platform" in
        "linux")
            [[ "$(echo "$os_info" | cut -d'|' -f1)" == "Linux" ]]
            ;;
        "macos")
            [[ "$(echo "$os_info" | cut -d'|' -f1)" == "macOS" ]]
            ;;
        "bsd")
            [[ "$(echo "$os_info" | cut -d'|' -f1)" == *BSD ]]
            ;;
        "bash")
            [[ "$(echo "$shell_info" | cut -d'|' -f1)" == "bash" ]]
            ;;
        "zsh")
            [[ "$(echo "$shell_info" | cut -d'|' -f1)" == "zsh" ]]
            ;;
        *)
            return 1
            ;;
    esac
}

# ===============================================
# Skip test if platform requirements not met
# ===============================================
#
# Description: Wrapper function that uses `is_platform_supported` to check a requirement
#              and automatically calls `skip_test` if the environment is unsuitable.
#
# Parameters:
#   - $1: required_platform (The platform type).
#   - $2: message (Optional skip message).
#
# Returns:
#   - 0 if platform is supported, 1 if skipped.
#
# Behavior:
#   - Calls `skip_test` if `is_platform_supported` returns 1.
#
require_platform() {
    local required_platform="$1"
    local message="${2:-Test requires $required_platform}"

    if ! is_platform_supported "$required_platform"; then
        skip_test "$message"
        return 1
    fi
    return 0
}

# ===============================================
# Skip test if command not available
# ===============================================
#
# Description: Checks the system PATH for a required executable command and
#              automatically calls `skip_test` if the command is not found.
#
# Parameters:
#   - $1: command (The command name).
#   - $2: message (Optional skip message).
#
# Returns:
#   - 0 if command is available, 1 if skipped.
#
# Behavior:
#   - Uses `command -v`.
#
require_command() {
    local command="$1"
    local message="${2:-Test requires command: $command}"

    if ! command -v "$command" >/dev/null 2>&1; then
        skip_test "$message"
        return 1
    fi
    return 0
}

# ===============================================
# Print framework information
# ===============================================
#
# Description: Prints the version and directory information of the test framework.
#
# Parameters:
#   - None.
#
# Returns:
#   - Prints formatted information to stdout.
#
print_framework_info() {
    printf "${BOLD}${CYAN}WordPress DB Import Tool - Test Framework v$TEST_FRAMEWORK_VERSION${RESET}\n"
    printf "${DIM}Framework Directory: $TEST_FRAMEWORK_DIR${RESET}\n"
    printf "${DIM}Project Root: $PROJECT_ROOT_DIR${RESET}\n\n"
}

# Main test framework initialization
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    print_framework_info
    printf "${YELLOW}This is the test framework library. Source it in your test files.${RESET}\n"
    printf "${CYAN}Example:${RESET}\n"
    printf "  source lib/tests/test_framework.sh\n"
    printf "  init_test_session \"my_test\"\n"
    printf "  # ... run tests ...\n"
    printf "  finalize_test_session\n"
fi
