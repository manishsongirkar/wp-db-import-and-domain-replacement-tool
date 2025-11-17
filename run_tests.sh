#!/bin/bash

# ===============================================
# WordPress Database Import Tool - Main Test Runner
# ===============================================
#
# This script executes all test suites and generates comprehensive
# reports in multiple formats. It provides a single command to run
# the entire test suite across different environments and configurations.
#
# Usage:
#   ./run_tests.sh [options] [test_suite]
#
# Options:
#   --format FORMAT    Report format: json, html, text (default: all)
#   --output DIR       Output directory for reports (default: lib/tests/reports)
#   --verbose          Enable verbose output
#   --quick            Run only essential tests (faster)
#   --ci               CI mode (non-interactive, minimal output)
#   --help             Show this help message
#
# Test Suites:
#   all                Run all test suites (default)
#   compatibility      OS and shell compatibility tests
#   bash               Bash version compatibility tests
#   system             System environment tests
#   wordpress          WordPress functionality tests
#   unit               Unit tests
#   validation         Tool validation tests
#
# ===============================================

set -euo pipefail

# Script directory and paths
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$SCRIPT_DIR"
readonly TEST_FRAMEWORK="$SCRIPT_DIR/lib/tests/test_framework.sh"
readonly DEFAULT_OUTPUT_DIR="$SCRIPT_DIR/reports"

# Default configuration
REPORT_FORMATS=("json" "html" "text")
OUTPUT_DIR="$DEFAULT_OUTPUT_DIR"
VERBOSE=false
QUICK_MODE=false
CI_MODE=false
TEST_SUITE="all"
PARALLEL_TESTS=false

# Color definitions
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly BOLD='\033[1m'
readonly DIM='\033[2m'
readonly RESET='\033[0m'

# Test results tracking
declare -a TEST_RESULTS=()
declare -a FAILED_TESTS=()
TOTAL_TESTS=0
TOTAL_PASSED=0
TOTAL_FAILED=0
TOTAL_SKIPPED=0
START_TIME=""
END_TIME=""

# Function to clean up old reports
cleanup_old_reports() {
    local output_dir="$1"
    if [[ -d "$output_dir" ]]; then
        echo "🧹 Cleaning up old reports in $output_dir..."
        rm -rf "$output_dir"/*.html "$output_dir"/*.json "$output_dir"/*.txt 2>/dev/null || true
        # DON'T remove test_sessions here - wait until after report generation
    fi
}

# Function to clean up test sessions after report generation
cleanup_test_sessions() {
    local output_dir="$1"
    if [[ -d "$output_dir/test_sessions" ]]; then
        rm -rf "$output_dir"/test_sessions 2>/dev/null || true
    fi
}

# ===============================================
# Utility Functions
# ===============================================

log_info() {
    if [[ "$CI_MODE" != "true" ]]; then
        printf "${CYAN}ℹ️  %s${RESET}\n" "$1" >&2
    fi
}

log_warning() {
    printf "${YELLOW}⚠️  %s${RESET}\n" "$1" >&2
}

log_error() {
    printf "${RED}❌ %s${RESET}\n" "$1" >&2
}

log_success() {
    if [[ "$CI_MODE" != "true" ]]; then
        printf "${GREEN}✅ %s${RESET}\n" "$1" >&2
    fi
}

log_verbose() {
    if [[ "$VERBOSE" == "true" ]]; then
        printf "${DIM}🔍 %s${RESET}\n" "$1" >&2
    fi
}

# ===============================================
# Help and Usage
# ===============================================

show_help() {
    cat << EOF
${BOLD}${CYAN}WordPress Database Import Tool - Test Runner${RESET}

${BOLD}USAGE:${RESET}
  $0 [options] [test_suite]

${BOLD}OPTIONS:${RESET}
  --format FORMAT     Report format: json, html, text, all (default: all)
  --output DIR        Output directory for reports (default: reports)
  --verbose           Enable verbose output and detailed logging
  --quick             Run only essential tests for faster feedback
  --parallel          Run tests in parallel when possible
  --ci                CI mode (non-interactive, minimal output)
  --help              Show this help message

${BOLD}TEST SUITES:${RESET}
  ${CYAN}all${RESET}               Run all test suites (default)
  ${CYAN}compatibility${RESET}     OS and shell compatibility tests
  ${CYAN}bash${RESET}              Bash version compatibility tests
  ${CYAN}system${RESET}            System environment tests
  ${CYAN}unit${RESET}              Unit tests for core functions
  ${CYAN}wordpress${RESET}         WordPress functionality tests
  ${CYAN}validation${RESET}        Tool validation tests${BOLD}EXAMPLES:${RESET}
  $0                                    # Run all tests with default settings
  $0 --quick compatibility              # Quick compatibility check
  $0 --format html --output ./reports  # Generate only HTML reports
  $0 --ci --format json                # CI mode with JSON output
  $0 --verbose wordpress                # Verbose WordPress tests

${BOLD}ENVIRONMENT VARIABLES:${RESET}
  ${CYAN}TEST_TIMEOUT${RESET}      Timeout for individual tests (default: 300s)
  ${CYAN}TEST_PARALLEL${RESET}     Enable parallel test execution (default: false)
  ${CYAN}TEST_VERBOSE${RESET}      Enable verbose mode (default: false)

${BOLD}OUTPUT:${RESET}
  Test reports are generated in the specified output directory.
  Available formats:
  - ${CYAN}JSON${RESET}   Machine-readable test results
  - ${CYAN}HTML${RESET}   Interactive web-based report
  - ${CYAN}TEXT${RESET}   Human-readable terminal output

${BOLD}EXIT CODES:${RESET}
  ${GREEN}0${RESET}   All tests passed
  ${RED}1${RESET}   Some tests failed
  ${RED}2${RESET}   Test runner error (setup, configuration, etc.)
EOF
}

# ===============================================
# Argument Parsing
# ===============================================

parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --format)
                shift
                if [[ $# -eq 0 ]]; then
                    log_error "Missing format argument"
                    return 1
                fi

                case "$1" in
                    json|html|text)
                        REPORT_FORMATS=("$1")
                        ;;
                    all)
                        REPORT_FORMATS=("json" "html" "text")
                        ;;
                    *)
                        log_error "Invalid format: $1. Use: json, html, text, all"
                        return 1
                        ;;
                esac
                ;;
            --output)
                shift
                if [[ $# -eq 0 ]]; then
                    log_error "Missing output directory argument"
                    return 1
                fi
                OUTPUT_DIR="$1"
                ;;
            --verbose)
                VERBOSE=true
                ;;
            --quick)
                QUICK_MODE=true
                ;;
            --parallel)
                PARALLEL_TESTS=true
                ;;
            --ci)
                CI_MODE=true
                VERBOSE=false
                REPORT_FORMATS=("json")
                ;;
            --help|-h)
                show_help
                exit 0
                ;;
            --*)
                log_error "Unknown option: $1"
                show_help
                return 1
                ;;
            *)
                # Test suite argument
                case "$1" in
                    all|compatibility|bash|system|unit|wordpress|validation)
                        TEST_SUITE="$1"
                        ;;
                    *)
                        log_error "Unknown test suite: $1"
                        show_help
                        return 1
                        ;;
                esac
                ;;
        esac
        shift
    done

    # Apply environment variable overrides
    [[ "${TEST_VERBOSE:-false}" == "true" ]] && VERBOSE=true
    [[ "${TEST_PARALLEL:-false}" == "true" ]] && PARALLEL_TESTS=true

    return 0
}

# ===============================================
# Test Execution Functions
# ===============================================

# Check if test framework is available
check_test_framework() {
    if [[ ! -f "$TEST_FRAMEWORK" ]]; then
        log_error "Test framework not found: $TEST_FRAMEWORK"
        return 1
    fi

    # Source the test framework
    if ! source "$TEST_FRAMEWORK"; then
        log_error "Failed to load test framework: $TEST_FRAMEWORK"
        return 1
    fi

    log_verbose "Test framework loaded successfully"
    return 0
}

# Execute a single test suite
run_test_suite() {
    local suite_name="$1"
    local test_script="$2"
    local suite_description="$3"

    log_info "Running $suite_name tests..."

    if [[ ! -f "$test_script" ]]; then
        log_warning "$suite_name test script not found: $test_script"
        return 0
    fi

    local start_time=$(date +%s)
    local result=0

    # Execute the test script
    if [[ "$VERBOSE" == "true" ]]; then
        bash "$test_script"
        result=$?
    else
        bash "$test_script" >/dev/null 2>&1
        result=$?
    fi

    local end_time=$(date +%s)
    local duration=$((end_time - start_time))

    # Record test results
    local status="FAIL"
    if [[ $result -eq 0 ]]; then
        status="PASS"
        ((TOTAL_PASSED++))
        log_success "$suite_name tests completed (${duration}s)"
    else
        status="FAIL"
        ((TOTAL_FAILED++))
        FAILED_TESTS+=("$suite_name")
        log_error "$suite_name tests failed (${duration}s)"
    fi

    ((TOTAL_TESTS++))

    # Store detailed result
    TEST_RESULTS+=("$suite_name|$status|$duration|$suite_description")

    return $result
}

# Run compatibility tests
run_compatibility_tests() {
    local test_dir="$SCRIPT_DIR/lib/tests/compatibility"
    local overall_result=0

    # OS and Shell compatibility
    if [[ -f "$test_dir/test_os_shell.sh" ]]; then
        run_test_suite "OS/Shell Compatibility" "$test_dir/test_os_shell.sh" "Operating system and shell compatibility tests"
        [[ $? -ne 0 ]] && overall_result=1
    fi

    # Bash version compatibility (unless quick mode and not specifically testing bash)
    if [[ "$QUICK_MODE" != "true" || "$TEST_SUITE" == "bash" ]] && [[ -f "$test_dir/test_bash_versions.sh" ]]; then
        run_test_suite "Bash Versions" "$test_dir/test_bash_versions.sh" "Bash version compatibility and feature tests"
        [[ $? -ne 0 ]] && overall_result=1
    fi

    return $overall_result
}

# Run system environment tests
run_system_tests() {
    local test_dir="$SCRIPT_DIR/lib/tests/system"
    local overall_result=0

    if [[ -f "$test_dir/test_environment.sh" ]]; then
        run_test_suite "System Environment" "$test_dir/test_environment.sh" "System environment and resource tests"
        [[ $? -ne 0 ]] && overall_result=1
    fi

    return $overall_result
}

# Run WordPress functionality tests
run_wordpress_tests() {
    local test_dir="$SCRIPT_DIR/lib/tests/integration"
    local overall_result=0

    if [[ -f "$test_dir/test_wordpress.sh" ]]; then
        run_test_suite "WordPress Functionality" "$test_dir/test_wordpress.sh" "WordPress-specific functionality tests"
        [[ $? -ne 0 ]] && overall_result=1
    fi

    return $overall_result
}

# Run unit tests
run_unit_tests() {
    local test_dir="$SCRIPT_DIR/lib/tests/unit"
    local overall_result=0

    if [[ -f "$test_dir/test_core_functions.sh" ]]; then
        run_test_suite "Unit Tests" "$test_dir/test_core_functions.sh" "Core function unit tests"
        [[ $? -ne 0 ]] && overall_result=1
    fi

    return $overall_result
}

# Run validation tests
run_validation_tests() {
    log_info "Running validation tests..."

    local start_time=$(date +%s)
    local result=0

    # Use the wp-db-import validate command
    if [[ -f "$PROJECT_ROOT/wp-db-import" ]]; then
        if [[ "$VERBOSE" == "true" ]]; then
            "$PROJECT_ROOT/wp-db-import" validate all
            result=$?
        else
            "$PROJECT_ROOT/wp-db-import" validate all >/dev/null 2>&1
            result=$?
        fi
    else
        log_warning "wp-db-import script not found for validation tests"
        return 0
    fi

    local end_time=$(date +%s)
    local duration=$((end_time - start_time))

    # Record results
    local status="FAIL"
    if [[ $result -eq 0 ]]; then
        status="PASS"
        ((TOTAL_PASSED++))
        log_success "Validation tests completed (${duration}s)"
    else
        status="FAIL"
        ((TOTAL_FAILED++))
        FAILED_TESTS+=("Validation")
        log_error "Validation tests failed (${duration}s)"
    fi

    ((TOTAL_TESTS++))
    TEST_RESULTS+=("Tool Validation|$status|$duration|Tool functionality validation tests")

    return $result
}

# Main test execution orchestrator
execute_tests() {
    START_TIME=$(date +%s)

    log_info "Starting test execution..."
    log_verbose "Test suite: $TEST_SUITE"
    log_verbose "Quick mode: $QUICK_MODE"
    log_verbose "Parallel mode: $PARALLEL_TESTS"
    log_verbose "Output directory: $OUTPUT_DIR"

    local overall_result=0

    case "$TEST_SUITE" in
        "all")
            run_compatibility_tests || overall_result=1
            run_system_tests || overall_result=1
            run_unit_tests || overall_result=1
            run_wordpress_tests || overall_result=1
            run_validation_tests || overall_result=1
            ;;
        "compatibility")
            run_compatibility_tests || overall_result=1
            ;;
        "bash")
            local test_dir="$SCRIPT_DIR/lib/tests/compatibility"
            if [[ -f "$test_dir/test_bash_versions.sh" ]]; then
                run_test_suite "Bash Versions" "$test_dir/test_bash_versions.sh" "Bash version compatibility tests"
                [[ $? -ne 0 ]] && overall_result=1
            fi
            ;;
        "system")
            run_system_tests || overall_result=1
            ;;
        "unit")
            run_unit_tests || overall_result=1
            ;;
        "wordpress")
            run_wordpress_tests || overall_result=1
            ;;
        "validation")
            run_validation_tests || overall_result=1
            ;;
        *)
            log_error "Unknown test suite: $TEST_SUITE"
            return 2
            ;;
    esac

    END_TIME=$(date +%s)

    return $overall_result
}

# ===============================================
# Report Generation Functions
# ===============================================

# Create output directory and clean up old reports
create_output_directory() {
    # Clean up old reports first
    cleanup_old_reports "$OUTPUT_DIR"

    if [[ ! -d "$OUTPUT_DIR" ]]; then
        if ! mkdir -p "$OUTPUT_DIR"; then
            log_error "Failed to create output directory: $OUTPUT_DIR"
            return 1
        fi
    fi

    log_verbose "Output directory: $OUTPUT_DIR"
    return 0
}

# Generate JSON report
generate_json_report() {
    local json_file="$OUTPUT_DIR/test_results.json"
    local total_duration=$((END_TIME - START_TIME))

    cat > "$json_file" <<EOF
{
  "test_run": {
    "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
    "suite": "$TEST_SUITE",
    "duration": $total_duration,
    "quick_mode": $QUICK_MODE,
    "ci_mode": $CI_MODE
  },
  "summary": {
    "total": $TOTAL_TESTS,
    "passed": $TOTAL_PASSED,
    "failed": $TOTAL_FAILED,
    "skipped": $TOTAL_SKIPPED,
    "success_rate": $(echo "scale=2; $TOTAL_PASSED * 100 / $TOTAL_TESTS" | bc -l 2>/dev/null || echo "0.00")
  },
  "environment": {
    "os": "$(uname -s)",
    "os_version": "$(uname -r)",
    "architecture": "$(uname -m)",
    "shell": "${SHELL##*/}",
    "bash_version": "${BASH_VERSION:-unknown}",
    "user": "$(whoami)",
    "hostname": "$(hostname)",
    "pwd": "$(pwd)"
  },
  "results": [
EOF

    local first=true
    for result in "${TEST_RESULTS[@]}"; do
        IFS='|' read -r name status duration description <<< "$result"

        if [[ "$first" != "true" ]]; then
            echo "," >> "$json_file"
        fi
        first=false

        cat >> "$json_file" <<EOF
    {
      "name": "$name",
      "status": "$status",
      "duration": $duration,
      "description": "$description"
    },
EOF
    done

    cat >> "$json_file" <<EOF

  ],
  "failed_tests": []
}
EOF

    log_success "JSON report generated: $json_file"
}

# Generate HTML report
# Generate HTML report
generate_html_report() {
    local html_file="$OUTPUT_DIR/test_results.html"
    local total_duration=$((END_TIME - START_TIME))

    cat > "$html_file" <<'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>WordPress DB Import Tool - Test Results</title>
    <style>
        body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', system-ui, sans-serif; margin: 0; padding: 20px; background: #f5f5f5; }
        .container { max-width: 1200px; margin: 0 auto; background: white; border-radius: 8px; box-shadow: 0 2px 10px rgba(0,0,0,0.1); overflow: hidden; }
        .header { background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); color: white; padding: 30px; text-align: center; }
        .header h1 { margin: 0; font-size: 2.5em; }
        .header p { margin: 10px 0 0 0; opacity: 0.9; }
        .summary { display: grid; grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); gap: 20px; padding: 30px; background: #f8f9fa; }
        .metric { text-align: center; padding: 20px; background: white; border-radius: 8px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
        .metric-value { font-size: 2.5em; font-weight: bold; margin-bottom: 5px; }
        .metric-label { color: #666; font-size: 0.9em; }
        .passed { color: #28a745; }
        .failed { color: #dc3545; }
        .skipped { color: #ffc107; }
        .results { padding: 30px; }
        .test-suite { margin-bottom: 30px; border: 1px solid #e9ecef; border-radius: 8px; overflow: hidden; }
        .suite-header { background: #f8f9fa; padding: 20px; border-bottom: 1px solid #e9ecef; display: flex; justify-content: space-between; align-items: center; }
        .suite-title { font-size: 1.3em; font-weight: bold; margin: 0; }
        .suite-stats { display: flex; gap: 15px; font-size: 0.9em; }
        .suite-stat { padding: 4px 8px; border-radius: 4px; font-weight: bold; }
        .suite-stat.pass { background: #d4edda; color: #155724; }
        .suite-stat.fail { background: #f8d7da; color: #721c24; }
        .suite-stat.skip { background: #fff3cd; color: #856404; }
        .test-list { padding: 0; }
        .test-item { display: flex; align-items: center; padding: 15px 20px; margin: 0; border-bottom: 1px solid #f8f9fa; }
        .test-item:last-child { border-bottom: none; }
        .test-item.pass { border-left: 4px solid #28a745; background: #f8fff9; }
        .test-item.fail { border-left: 4px solid #dc3545; background: #fff8f8; }
        .test-item.skip { border-left: 4px solid #ffc107; background: #fffbf0; }
        .individual-test { display: flex; align-items: center; padding: 10px 15px; margin: 0 0 5px 0; border-radius: 4px; font-size: 0.9em; }
        .individual-test.pass { border-left: 3px solid #28a745; background: #f0f9ff; }
        .individual-test.fail { border-left: 3px solid #dc3545; background: #fef5f5; }
        .individual-test.skip { border-left: 3px solid #6c757d; background: #f8f9fa; }
        .individual-test .test-name { font-weight: 500; min-width: 250px; }
        .individual-test .test-message { flex: 1; color: #666; margin: 0 15px; }
        .individual-test .test-duration { min-width: 50px; color: #888; font-size: 0.85em; }
        .individual-test .test-status { min-width: 80px; font-weight: 600; text-align: center; }
        .test-name { font-weight: bold; flex: 1; }
        .test-message { color: #666; margin-left: 15px; font-size: 0.9em; }
        .test-duration { color: #999; margin-left: 15px; font-size: 0.8em; }
        .test-status { padding: 4px 12px; border-radius: 20px; font-size: 0.8em; font-weight: bold; text-transform: uppercase; }
        .status-pass { background: #28a745; color: white; }
        .status-fail { background: #dc3545; color: white; }
        .status-skip { background: #ffc107; color: #333; }
        .environment { background: #f8f9fa; padding: 20px; margin: 20px; border-radius: 8px; }
        .environment h3 { margin-top: 0; }
        .env-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(250px, 1fr)); gap: 10px; }
        .env-item { display: flex; justify-content: space-between; padding: 5px 0; }
        .env-label { font-weight: bold; }
        .footer { text-align: center; padding: 20px; color: #666; font-size: 0.9em; }
        .expand-toggle { cursor: pointer; user-select: none; }
        .expand-toggle:hover { background: rgba(0,0,0,0.05); }
        .collapsible-content { max-height: 0; overflow: hidden; transition: max-height 0.3s ease; }
        .collapsible-content.expanded { max-height: 2000px; }
    </style>
    <script>
        function toggleSuite(id) {
            const content = document.getElementById('suite-' + id);
            const header = content.previousElementSibling;
            if (content.classList.contains('expanded')) {
                content.classList.remove('expanded');
                header.querySelector('.expand-toggle').innerHTML = '▶️ Show Details';
            } else {
                content.classList.add('expanded');
                header.querySelector('.expand-toggle').innerHTML = '🔽 Hide Details';
            }
        }
    </script>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>🧪 Test Results</h1>
            <p>WordPress Database Import & Domain Replacement Tool</p>
        </div>

        <div class="summary">
            <div class="metric">
                <div class="metric-value">TOTAL_INDIVIDUAL_TESTS_PLACEHOLDER</div>
                <div class="metric-label">Individual Tests</div>
            </div>
            <div class="metric">
                <div class="metric-value passed">TOTAL_INDIVIDUAL_PASSED_PLACEHOLDER</div>
                <div class="metric-label">Passed</div>
            </div>
            <div class="metric">
                <div class="metric-value failed">TOTAL_INDIVIDUAL_FAILED_PLACEHOLDER</div>
                <div class="metric-label">Failed</div>
            </div>
            <div class="metric">
                <div class="metric-value skipped">TOTAL_INDIVIDUAL_SKIPPED_PLACEHOLDER</div>
                <div class="metric-label">Skipped</div>
            </div>
            <div class="metric">
                <div class="metric-value">TOTAL_SUITES_PLACEHOLDER</div>
                <div class="metric-label">Test Suites</div>
            </div>
            <div class="metric">
                <div class="metric-value">TOTAL_DURATION_PLACEHOLDER</div>
                <div class="metric-label">Duration (seconds)</div>
            </div>
        </div>

        <div class="environment">
            <h3>🖥️ Test Environment</h3>
            <div class="env-grid">
                <div class="env-item"><span class="env-label">Test Suite:</span> <span>TEST_SUITE_PLACEHOLDER</span></div>
                <div class="env-item"><span class="env-label">Timestamp:</span> <span>TIMESTAMP_PLACEHOLDER</span></div>
                <div class="env-item"><span class="env-label">Operating System:</span> <span>OS_PLACEHOLDER</span></div>
                <div class="env-item"><span class="env-label">Bash Version:</span> <span>BASH_VERSION_PLACEHOLDER</span></div>
                <div class="env-item"><span class="env-label">User:</span> <span>USER_PLACEHOLDER</span></div>
                <div class="env-item"><span class="env-label">Hostname:</span> <span>HOSTNAME_PLACEHOLDER</span></div>
            </div>
        </div>

        <div class="results">
            <h2>📊 Detailed Test Results</h2>
            TEST_SUITES_DETAILED_PLACEHOLDER
        </div>

        <div class="footer">
            Generated on TIMESTAMP_PLACEHOLDER by WordPress DB Import Tool Test Runner
        </div>
    </div>
</body>
</html>
EOF

    # Collect detailed test results from all test sessions
    local detailed_suites_html=""
    local total_individual_tests=0
    local total_individual_passed=0
    local total_individual_failed=0
    local total_individual_skipped=0
    local suite_counter=0

    for result in "${TEST_RESULTS[@]}"; do
        IFS='|' read -r suite_name status duration description <<< "$result"
        ((suite_counter++))

        # Map suite names to directory patterns
        local search_pattern=""
        case "$suite_name" in
            "OS/Shell Compatibility"|"Compatibility")
                search_pattern="os_shell_compatibility"
                ;;
            "Bash Version Compatibility"|"Bash Versions"|"Bash")
                search_pattern="bash_version_compatibility"
                ;;
            "System Environment"|"System")
                search_pattern="system_environment"
                ;;
            "Unit Tests"|"Unit")
                search_pattern="unit_tests"
                ;;
            "WordPress Functionality"|"WordPress")
                search_pattern="wordpress_functionality"
                ;;
            "Tool Validation"|"Validation")
                search_pattern="validation"
                ;;
            *)
                search_pattern=$(echo "${suite_name}" | tr ' ' '_' | tr '[:upper:]' '[:lower:]')
                ;;
        esac

        # Find the corresponding test session directory
        local reports_dir="$(cd "$(dirname "$0")" && pwd)/$OUTPUT_DIR"
        local session_dir="$reports_dir/test_sessions/${search_pattern}"

        local individual_tests_html=""
        local suite_individual_passed=0
        local suite_individual_failed=0
        local suite_individual_skipped=0
        if [[ -n "$session_dir" && -f "$session_dir/test_results.json" ]]; then
            # Parse individual test results
            if command -v jq >/dev/null 2>&1; then
                # Use jq for proper JSON parsing
                local test_count=$(jq -r '.tests | length' "$session_dir/test_results.json" 2>/dev/null || echo "0")
                for ((i=0; i<test_count; i++)); do
                    local test_name=$(jq -r ".tests[$i].name" "$session_dir/test_results.json" 2>/dev/null || echo "Unknown Test")
                    local test_status=$(jq -r ".tests[$i].status" "$session_dir/test_results.json" 2>/dev/null || echo "UNKNOWN")
                    local test_message=$(jq -r ".tests[$i].message" "$session_dir/test_results.json" 2>/dev/null || echo "")
                    local test_duration=$(jq -r ".tests[$i].duration" "$session_dir/test_results.json" 2>/dev/null || echo "0")

                    # Count by status
                    case "$test_status" in
                        "PASS") ((suite_individual_passed++)) ;;
                        "FAIL") ((suite_individual_failed++)) ;;
                        "SKIP") ((suite_individual_skipped++)) ;;
                    esac

                    # Generate HTML for individual test
                    local status_class=""
                    local status_icon=""
                    case "$test_status" in
                        "PASS") status_class="pass"; status_icon="✅" ;;
                        "FAIL") status_class="fail"; status_icon="❌" ;;
                        "SKIP") status_class="skip"; status_icon="⏭️" ;;
                        *) status_class="unknown"; status_icon="❓" ;;
                    esac

                    # Escape HTML entities
                    test_name=$(echo "$test_name" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g; s/"/\&quot;/g')
                    test_message=$(echo "$test_message" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g; s/"/\&quot;/g')

                    individual_tests_html="$individual_tests_html<div class=\"individual-test $status_class\"><div class=\"test-name\">$status_icon $test_name</div><div class=\"test-message\">$test_message</div><div class=\"test-duration\">${test_duration}s</div><div class=\"test-status status-$status_class\">$test_status</div></div>"
                done
            else
                # Fallback to manual parsing if jq is not available
                while IFS= read -r line; do
                    if [[ "$line" =~ \"name\":\ *\"([^\"]*)\" ]]; then
                        local test_name="${BASH_REMATCH[1]}"
                        local test_status=""
                        local test_message=""
                        local test_duration=""

                        # Read the next few lines to get status, message, and duration
                        for j in {1..6}; do
                            read -r nextline
                            if [[ "$nextline" =~ \"status\":\ *\"([^\"]*)\" ]]; then
                                test_status="${BASH_REMATCH[1]}"
                            elif [[ "$nextline" =~ \"message\":\ *\"([^\"]*)\" ]]; then
                                test_message="${BASH_REMATCH[1]}"
                            elif [[ "$nextline" =~ \"duration\":\ *([0-9]+) ]]; then
                                test_duration="${BASH_REMATCH[1]}"
                            fi
                        done

                        # Count by status
                        case "$test_status" in
                            "PASS") ((suite_individual_passed++)) ;;
                            "FAIL") ((suite_individual_failed++)) ;;
                            "SKIP") ((suite_individual_skipped++)) ;;
                        esac

                        # Generate HTML for individual test
                        local status_class=""
                        local status_icon=""
                        case "$test_status" in
                            "PASS") status_class="pass"; status_icon="✅" ;;
                            "FAIL") status_class="fail"; status_icon="❌" ;;
                            "SKIP") status_class="skip"; status_icon="⏭️" ;;
                            *) status_class="unknown"; status_icon="❓" ;;
                        esac

                        # Escape HTML entities
                        test_name=$(echo "$test_name" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g; s/"/\&quot;/g')
                        test_message=$(echo "$test_message" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g; s/"/\&quot;/g')

                        individual_tests_html="$individual_tests_html<div class=\"individual-test $status_class\"><div class=\"test-name\">$status_icon $test_name</div><div class=\"test-message\">$test_message</div><div class=\"test-duration\">${test_duration}s</div><div class=\"test-status status-$status_class\">$test_status</div></div>"
                    fi
                done < "$session_dir/test_results.json"
            fi
        fi

        # If no individual tests found, show suite-level result
        if [[ -z "$individual_tests_html" ]]; then
            ((total_individual_tests++))
            local status_class="pass"
            local status_label="PASS"

            case "$status" in
                "PASS")
                    ((total_individual_passed++))
                    ;;
                "FAIL")
                    status_class="fail"
                    status_label="FAIL"
                    ((total_individual_failed++))
                    ;;
                "SKIP")
                    status_class="skip"
                    status_label="SKIP"
                    ((total_individual_skipped++))
                    ;;
            esac

            individual_tests_html="<div class=\"test-item $status_class\">"
            individual_tests_html+="<div class=\"test-name\">$suite_name Test Suite</div>"
            individual_tests_html+="<div class=\"test-message\">$description</div>"
            individual_tests_html+="<div class=\"test-duration\">${duration}s</div>"
            individual_tests_html+="<div class=\"test-status status-$status_class\">$status_label</div>"
            individual_tests_html+="</div>"
        fi

        # Build suite HTML
        detailed_suites_html+="<div class=\"test-suite\">"
        detailed_suites_html+="<div class=\"suite-header expand-toggle\" onclick=\"toggleSuite($suite_counter)\">"
        detailed_suites_html+="<div class=\"suite-title\">$suite_name</div>"
        detailed_suites_html+="<div class=\"suite-stats\">"
        if [[ $suite_individual_passed -gt 0 ]]; then
            detailed_suites_html+="<span class=\"suite-stat pass\">✅ $suite_individual_passed</span>"
        fi
        if [[ $suite_individual_failed -gt 0 ]]; then
            detailed_suites_html+="<span class=\"suite-stat fail\">❌ $suite_individual_failed</span>"
        fi
        if [[ $suite_individual_skipped -gt 0 ]]; then
            detailed_suites_html+="<span class=\"suite-stat skip\">⏭️ $suite_individual_skipped</span>"
        fi
        detailed_suites_html+="<span class=\"expand-toggle\">▶️ Show Details</span>"
        detailed_suites_html+="</div>"
        detailed_suites_html+="</div>"
        detailed_suites_html+="<div id=\"suite-$suite_counter\" class=\"collapsible-content\">"
        detailed_suites_html+="<div class=\"test-list\">$individual_tests_html</div>"
        detailed_suites_html+="</div>"
        detailed_suites_html+="</div>"
    done

    # Replace placeholders
    local timestamp=$(date)

    sed -i.bak \
        -e "s/TOTAL_INDIVIDUAL_TESTS_PLACEHOLDER/$total_individual_tests/g" \
        -e "s/TOTAL_INDIVIDUAL_PASSED_PLACEHOLDER/$total_individual_passed/g" \
        -e "s/TOTAL_INDIVIDUAL_FAILED_PLACEHOLDER/$total_individual_failed/g" \
        -e "s/TOTAL_INDIVIDUAL_SKIPPED_PLACEHOLDER/$total_individual_skipped/g" \
        -e "s/TOTAL_SUITES_PLACEHOLDER/$TOTAL_TESTS/g" \
        -e "s/TOTAL_DURATION_PLACEHOLDER/$total_duration/g" \
        -e "s/TEST_SUITE_PLACEHOLDER/$TEST_SUITE/g" \
        -e "s/TIMESTAMP_PLACEHOLDER/$timestamp/g" \
        -e "s/OS_PLACEHOLDER/$(uname -s)/g" \
        -e "s/BASH_VERSION_PLACEHOLDER/${BASH_VERSION:-unknown}/g" \
        -e "s/USER_PLACEHOLDER/$(whoami)/g" \
        -e "s/HOSTNAME_PLACEHOLDER/$(hostname)/g" \
        -e "s|TEST_SUITES_DETAILED_PLACEHOLDER|$detailed_suites_html|g" \
        "$html_file"

    rm -f "$html_file.bak"

    log_success "HTML report generated: $html_file"
}

# Generate text report
generate_text_report() {
    local text_file="$OUTPUT_DIR/test_results.txt"
    local total_duration=$((END_TIME - START_TIME))

    cat > "$text_file" <<EOF
================================================================================
WordPress Database Import & Domain Replacement Tool - Test Results
================================================================================

Test Run Information:
  Suite: $TEST_SUITE
  Date: $(date)
  Duration: ${total_duration}s
  Quick Mode: $QUICK_MODE
  CI Mode: $CI_MODE

Environment:
  OS: $(uname -s) $(uname -r)
  Architecture: $(uname -m)
  Shell: ${SHELL##*/}
  Bash Version: ${BASH_VERSION:-unknown}
  User: $(whoami)
  Hostname: $(hostname)
  Working Directory: $(pwd)

Summary:
  Total Tests: $TOTAL_TESTS
  Passed: $TOTAL_PASSED
  Failed: $TOTAL_FAILED
  Skipped: $TOTAL_SKIPPED
  Success Rate: $(echo "scale=1; $TOTAL_PASSED * 100 / $TOTAL_TESTS" | bc -l 2>/dev/null || echo "0.0")%

Detailed Results:
================================================================================
EOF

    for result in "${TEST_RESULTS[@]}"; do
        IFS='|' read -r name status duration description <<< "$result"
        local status_symbol="✅"

        if [[ "$status" == "FAIL" ]]; then
            status_symbol="❌"
        elif [[ "$status" == "SKIP" ]]; then
            status_symbol="⏭️"
        fi

        printf "%-50s %s %6ss  %s\n" "$name" "$status_symbol" "$duration" "$description" >> "$text_file"
    done

    if [[ ${#FAILED_TESTS[@]} -gt 0 ]]; then
        cat >> "$text_file" <<EOF

Failed Tests:
$(printf "  - %s\n" "${FAILED_TESTS[@]}")
EOF
    fi

    cat >> "$text_file" <<EOF

================================================================================
Generated by WordPress DB Import Tool Test Runner
EOF

    log_success "Text report generated: $text_file"
}

# Generate all reports
generate_reports() {
    if ! create_output_directory; then
        return 1
    fi

    log_info "Generating test reports..."

    for format in "${REPORT_FORMATS[@]}"; do
        case "$format" in
            json)
                generate_json_report
                ;;
            html)
                generate_html_report
                ;;
            text)
                generate_text_report
                ;;
        esac
    done

    return 0
}

# ===============================================
# Main Function
# ===============================================

main() {
    # Parse command line arguments
    if ! parse_arguments "$@"; then
        return 2
    fi

    # Export OUTPUT_DIR for use by test frameworks
    export OUTPUT_DIR

    # Check prerequisites
    if ! check_test_framework; then
        return 2
    fi

    # Print banner unless in CI mode
    if [[ "$CI_MODE" != "true" ]]; then
        printf "${BOLD}${CYAN}"
        cat << 'EOF'
╭─────────────────────────────────────────────────────────────────╮
│  🧪 WordPress Database Import & Domain Replacement Tool Tests  │
╰─────────────────────────────────────────────────────────────────╯
EOF
        printf "${RESET}\n"

        printf "${DIM}Test Suite: %s${RESET}\n" "$TEST_SUITE"
        printf "${DIM}Report Formats: %s${RESET}\n" "${REPORT_FORMATS[*]}"
        printf "${DIM}Output Directory: %s${RESET}\n\n" "$OUTPUT_DIR"
    fi

    # Execute tests
    local test_result
    execute_tests
    test_result=$?

    # Generate reports
    if ! generate_reports; then
        log_error "Failed to generate reports"
        return 2
    fi

    # Clean up test sessions after report generation
    cleanup_test_sessions "$OUTPUT_DIR"

    # Print summary unless in CI mode
    if [[ "$CI_MODE" != "true" ]]; then
        printf "\n${BOLD}${CYAN}📊 Test Summary${RESET}\n"
        printf "Tests: %d | " "$TOTAL_TESTS"
        printf "${GREEN}Passed: %d${RESET} | " "$TOTAL_PASSED"
        printf "${RED}Failed: %d${RESET} | " "$TOTAL_FAILED"
        printf "${YELLOW}Skipped: %d${RESET}\n" "$TOTAL_SKIPPED"

        if [[ $test_result -eq 0 ]]; then
            printf "\n${GREEN}${BOLD}✅ All tests passed!${RESET}\n"
        else
            printf "\n${RED}${BOLD}❌ Some tests failed${RESET}\n"
            if [[ ${#FAILED_TESTS[@]} -gt 0 ]]; then
                printf "${RED}Failed suites:${RESET}\n"
                printf "${RED}  - %s${RESET}\n" "${FAILED_TESTS[@]}"
            fi
        fi

        printf "\n${DIM}Reports available in: %s${RESET}\n" "$OUTPUT_DIR"
    fi

    return $test_result
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
