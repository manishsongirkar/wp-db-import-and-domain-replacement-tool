# WordPress Database Import Tool - Test Suite

A comprehensive test suite for the WordPress Database Import and Domain Replacement Tool, designed to ensure compatibility and reliability across different environments.

## Overview

This test suite provides extensive testing across multiple dimensions:

- **Operating System Compatibility**: Linux distributions, macOS, BSD variants, WSL, Cygwin/MSYS2
- **Shell Compatibility**: Bash versions (3.2, 4.x, 5.x), POSIX compliance, Zsh compatibility
- **Environment Testing**: User permissions, resource limits, utility versions
- **WordPress Functionality**: Single-site, multisite, configuration handling, WP-CLI integration

## Quick Start

```bash
# Run all tests with default settings
./run_tests.sh

# Run specific test suite
./run_tests.sh compatibility

# Quick test run (essential tests only)
./run_tests.sh --quick

# Generate HTML report
./run_tests.sh --format html

# CI mode (minimal output, JSON only)
./run_tests.sh --ci
```

## Test Suites

### 1. Compatibility Tests (`compatibility`)

Tests OS and shell compatibility across different environments:

- Operating system detection (Linux, macOS, BSD, WSL, Cygwin)
- Shell type detection and feature availability
- POSIX compliance verification
- Utility implementation differences (GNU vs BSD)

**Location**: `lib/tests/compatibility/`

### 2. Bash Version Tests (`bash`)

Tests compatibility with different Bash versions:

- Bash 3.2 compatibility (common on older macOS)
- Bash 4.x features (associative arrays, case modification)
- Bash 5.x features (negative array indices, nameref variables)
- Bashism detection and avoidance
- Parameter expansion compatibility

**Location**: `lib/tests/compatibility/test_bash_versions.sh`

### 3. System Environment Tests (`system`)

Tests system resource and environment handling:

- User permissions (root vs regular user)
- Environment variable handling
- Resource limits (file handles, processes, memory)
- Filesystem access and permissions
- External command availability (MySQL, WP-CLI, Git)

**Location**: `lib/tests/system/`

### 4. WordPress Functionality Tests (`wordpress`)

Tests WordPress-specific functionality:

- WordPress installation detection
- WP-CLI integration and version compatibility
- Configuration file handling and validation
- Domain/URL sanitization
- Search and replace functionality
- Multisite detection and handling
- Error handling and edge cases

**Location**: `lib/tests/integration/`

### 5. Unit Tests (`unit`)

Tests individual functions and components:

- Core utility functions
- Module loading system
- Configuration management
- String manipulation utilities
- File handling operations

**Location**: `lib/tests/unit/`

### 6. Validation Tests (`validation`)

Uses the built-in `wp-db-import validate` command to test tool functionality:

- Basic functionality validation
- Environment compatibility checks
- Dependency verification
- Module loading validation
- Configuration system testing

## Directory Structure

```
lib/tests/
├── test_framework.sh           # Core test framework
├── compatibility/              # OS and shell compatibility tests
│   ├── test_os_shell.sh       # Operating system and shell tests
│   └── test_bash_versions.sh  # Bash version compatibility tests
├── system/                     # System environment tests
│   └── test_environment.sh    # Resource and permission tests
├── integration/                # Integration tests
│   └── test_wordpress.sh      # WordPress functionality tests
├── unit/                       # Unit tests
│   └── test_core_functions.sh # Core function tests
├── fixtures/                   # Test fixtures and sample data
│   └── README.md              # Fixture documentation
└── reports/                    # Test reports (generated)
    ├── environment.json        # Environment information
    ├── test_results.json      # Test results in JSON
    ├── test_results.html      # Interactive HTML report
    └── test_results.txt       # Plain text report
```

## Test Framework

The test framework (`test_framework.sh`) provides:

### Core Features

- **Environment Detection**: Automatic OS, shell, and utility version detection
- **Test Isolation**: Each test runs in a clean environment
- **Assertion Functions**: Rich set of assertion functions for different test scenarios
- **Result Tracking**: Comprehensive test result collection and analysis
- **Report Generation**: Multiple output formats (JSON, HTML, text)

### Key Functions

```bash
# Test session management
init_test_session "test_name"
finalize_test_session

# Test execution
start_test "Test Name" "Description"
pass_test "Success message"
fail_test "Failure message"
skip_test "Skip reason"

# Assertions
assert_success "command"
assert_equals "expected" "actual"
assert_file_exists "/path/to/file"
assert_command_available "command"

# Environment checks
require_platform "linux"
require_command "wp"

# Test utilities
create_temp_test_dir "name"
cleanup_temp_test_dir "$temp_dir"
run_isolated_test "test_function"
```

## Running Tests

### Command Line Options

```bash
./run_tests.sh [options] [test_suite]

Options:
  --format FORMAT    Report format: json, html, text, all (default: all)
  --output DIR       Output directory (default: lib/tests/reports)
  --verbose          Enable verbose output
  --quick            Run only essential tests
  --parallel         Run tests in parallel (experimental)
  --ci               CI mode (non-interactive, JSON output only)
  --help             Show help message

Test Suites:
  all               Run all test suites (default)
  compatibility     OS and shell compatibility tests
  bash              Bash version compatibility tests
  system            System environment tests
  wordpress         WordPress functionality tests
  validation        Tool validation tests
```

### Examples

```bash
# Complete test run with all reports
./run_tests.sh

# Quick compatibility check
./run_tests.sh --quick compatibility

# Verbose WordPress testing
./run_tests.sh --verbose wordpress

# CI pipeline testing
./run_tests.sh --ci --format json

# Generate only HTML report
./run_tests.sh --format html --output ./my_reports

# Parallel test execution (experimental)
./run_tests.sh --parallel all
```

### Environment Variables

```bash
# Test configuration
export TEST_TIMEOUT=300          # Test timeout in seconds
export TEST_PARALLEL=true        # Enable parallel execution
export TEST_VERBOSE=true         # Enable verbose mode

# Tool validation
export WP_IMPORT_AUTO_LOAD=true  # Auto-load modules
export BASH_DEBUG_MODULES=true   # Debug module loading
```

## Test Reports

### JSON Report

Machine-readable format for CI/CD integration:

```json
{
  "test_run": {
    "timestamp": "2024-11-14T10:30:00Z",
    "suite": "all",
    "duration": 45
  },
  "summary": {
    "total": 25,
    "passed": 23,
    "failed": 1,
    "skipped": 1,
    "success_rate": 92.0
  },
  "environment": { ... },
  "results": [ ... ]
}
```

### HTML Report

Interactive web-based report with:

- Visual test result dashboard
- Environment information display
- Detailed test breakdowns
- Pass/fail statistics
- Timeline information

### Text Report

Human-readable terminal-friendly format:

```
================================================================================
WordPress Database Import & Domain Replacement Tool - Test Results
================================================================================

Summary:
  Total Tests: 25
  Passed: 23 (92.0%)
  Failed: 1
  Skipped: 1

Detailed Results:
OS/Shell Compatibility           ✅    15s  Operating system detection tests
Bash Version Compatibility      ✅    12s  Bash feature compatibility tests
...
```

## Continuous Integration

### GitHub Actions

```yaml
name: Test Suite
on: [push, pull_request]
jobs:
  test:
    strategy:
      matrix:
        os: [ubuntu-latest, macos-latest]
        bash: ['3.2', '4.4', '5.1']
    runs-on: ${{ matrix.os }}
    steps:
      - uses: actions/checkout@v2
      - name: Run Tests
        run: ./run_tests.sh --ci
      - name: Upload Results
        uses: actions/upload-artifact@v2
        with:
          name: test-results-${{ matrix.os }}-bash${{ matrix.bash }}
          path: lib/tests/reports/
```

### Jenkins

```groovy
pipeline {
    agent any
    stages {
        stage('Test') {
            parallel {
                stage('Compatibility') {
                    steps {
                        sh './run_tests.sh --ci compatibility'
                    }
                }
                stage('WordPress') {
                    steps {
                        sh './run_tests.sh --ci wordpress'
                    }
                }
            }
        }
    }
    post {
        always {
            archiveArtifacts 'lib/tests/reports/**'
            publishHTML([
                allowMissing: false,
                alwaysLinkToLastBuild: true,
                keepAll: true,
                reportDir: 'lib/tests/reports',
                reportFiles: '*.html',
                reportName: 'Test Report'
            ])
        }
    }
}
```

## Writing Tests

### Test Structure

```bash
#!/usr/bin/env bash

# Source the test framework
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../test_framework.sh"

# Individual test function
test_my_functionality() {
    start_test "My Functionality" "Description of what this tests"

    # Test setup
    local temp_dir=$(create_temp_test_dir "my_test")
    cd "$temp_dir" || return 1

    # Test execution
    if my_function_to_test; then
        pass_test "Function works correctly"
    else
        fail_test "Function failed"
    fi

    # Cleanup
    cd / && cleanup_temp_test_dir "$temp_dir"
}

# Test suite runner
run_my_tests() {
    init_test_session "my_test_suite"

    test_my_functionality
    # Add more tests here

    finalize_test_session
    return $?
}

# Run if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    run_my_tests
fi
```

### Best Practices

1. **Test Isolation**: Each test should be independent and not affect others
2. **Resource Cleanup**: Always clean up temporary files and directories
3. **Error Handling**: Use proper error handling and meaningful error messages
4. **Platform Awareness**: Use platform detection to skip inappropriate tests
5. **Documentation**: Document test purpose and expected behavior
6. **Assertion Usage**: Use appropriate assertion functions for clear test intent

### Platform-Specific Testing

```bash
# Skip test if platform requirements not met
test_linux_specific_feature() {
    if ! require_platform "linux"; then
        return 0  # Test is skipped
    fi

    start_test "Linux Feature" "Test Linux-specific functionality"
    # Test implementation
}

# Skip test if command not available
test_wp_cli_feature() {
    if ! require_command "wp"; then
        return 0  # Test is skipped
    fi

    start_test "WP-CLI Feature" "Test WP-CLI functionality"
    # Test implementation
}
```

## Troubleshooting

### Common Issues

1. **Permission Denied**: Ensure `run_tests.sh` is executable
2. **Missing Dependencies**: Install required tools (WP-CLI, MySQL client)
3. **Environment Variables**: Check shell environment and PATH
4. **Temporary Directory**: Ensure `/tmp` is writable
5. **Module Loading**: Verify all modules are present and readable

### Debug Mode

```bash
# Enable verbose output
./run_tests.sh --verbose

# Enable module debug output
export BASH_DEBUG_MODULES=true
./run_tests.sh

# Check test framework loading
bash -x lib/tests/test_framework.sh
```

### Manual Test Execution

```bash
# Run individual test files
bash lib/tests/compatibility/test_os_shell.sh

# Run with debug output
bash -x lib/tests/system/test_environment.sh

# Test specific functionality
wp-db-import validate all
```

## Contributing

When adding new tests:

1. Follow the established test structure and naming conventions
2. Add appropriate documentation and comments
3. Test across multiple platforms when possible
4. Update this README with new test information
5. Ensure tests are idempotent and don't interfere with each other

## Support

For issues with the test suite:

1. Check the test reports for detailed error information
2. Run tests in verbose mode for additional debugging output
3. Verify all dependencies are installed and accessible
4. Check platform compatibility requirements
5. Review environment variable settings

## License

This test suite is part of the WordPress Database Import and Domain Replacement Tool project and follows the same license terms.
