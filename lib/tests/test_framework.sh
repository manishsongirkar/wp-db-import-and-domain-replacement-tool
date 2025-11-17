#!/bin/bash

# ===============================================
# WordPress Database Import Tool - Test Framework
# ===============================================
#
# This file provides the core testing framework including assertion functions,
# test execution utilities, environment detection, and result reporting.
#
# Features:
# - Cross-platform environment detection
# - Bash version compatibility testing
# - Test isolation and cleanup
# - Assertion functions
# - Test result collection and reporting
# - Color-coded output
#
# ===============================================

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

# Detect the operating system
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

# Detect the current shell
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

# Detect Bash version and features
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

# Detect system utilities and their versions
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
                    version=$(wp --version 2>/dev/null | grep -o '[0-9]\+\.[0-9]\+[0-9.]*' || echo "Unknown")
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
# Test Session Management
# ===============================================

# Initialize test session
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

# Create environment information file
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
# Test Execution Functions
# ===============================================

# Start a test case
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

# Mark test as passed
pass_test() {
    local message="${1:-Test passed}"
    local end_time=$(date +%s)
    local duration=$((end_time - TEST_START_TIME))

    ((TEST_PASSED++))

    printf "${GREEN}✅ PASS${RESET} - $message ${DIM}(${duration}s)${RESET}\n\n"

    # Log result
    log_test_result "PASS" "$message" "$duration"
}

# Mark test as failed
fail_test() {
    local message="${1:-Test failed}"
    local end_time=$(date +%s)
    local duration=$((end_time - TEST_START_TIME))

    ((TEST_FAILED++))

    printf "${RED}❌ FAIL${RESET} - $message ${DIM}(${duration}s)${RESET}\n\n"

    # Log result
    log_test_result "FAIL" "$message" "$duration"
}

# Mark test as skipped
skip_test() {
    local message="${1:-Test skipped}"
    local end_time=$(date +%s)
    local duration=$((end_time - TEST_START_TIME))

    ((TEST_SKIPPED++))

    printf "${YELLOW}⏭️ SKIP${RESET} - $message ${DIM}(${duration}s)${RESET}\n\n"

    # Log result
    log_test_result "SKIP" "$message" "$duration"
}

# Log test result to file
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

# Assert that a command succeeds
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

# Assert that a command fails
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

# Assert that two strings are equal
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

# Assert that two strings are not equal
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

# Assert that a string contains a substring
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

# Assert that a file exists
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

# Assert that a directory exists
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

# Assert that a command is available
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

# Finalize test session and generate reports
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

# Generate final test report
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

# Create a temporary test directory
create_temp_test_dir() {
    local test_name="${1:-test}"
    local temp_dir=$(mktemp -d "/tmp/${test_name}_XXXXXX")
    echo "$temp_dir"
}

# Clean up temporary test directory
cleanup_temp_test_dir() {
    local temp_dir="$1"
    if [[ -n "$temp_dir" && -d "$temp_dir" && "$temp_dir" == /tmp/* ]]; then
        rm -rf "$temp_dir"
    fi
}

# Run a test in isolation
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

# Check if we're running on a supported platform
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

# Skip test if platform requirements not met
require_platform() {
    local required_platform="$1"
    local message="${2:-Test requires $required_platform}"

    if ! is_platform_supported "$required_platform"; then
        skip_test "$message"
        return 1
    fi
    return 0
}

# Skip test if command not available
require_command() {
    local command="$1"
    local message="${2:-Test requires command: $command}"

    if ! command -v "$command" >/dev/null 2>&1; then
        skip_test "$message"
        return 1
    fi
    return 0
}

# Print framework information
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
