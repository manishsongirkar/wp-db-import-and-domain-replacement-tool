# WordPress Database Import Tool - Test Framework Documentation

## Overview

The WordPress Database Import Tool includes a comprehensive test framework designed to validate functionality across different environments, operating systems, and shell versions. The test suite ensures reliability and compatibility for production deployments.

## Test Framework Features

### 🧪 **Test Categories**
1. **Compatibility Tests** - OS and shell compatibility across Unix-based systems
2. **System Tests** - Environment validation and resource checking
3. **Unit Tests** - Core function testing and validation
4. **Integration Tests** - WordPress-specific functionality testing
5. **Validation Tests** - Tool functionality and dependency validation

### 🔧 **Technical Capabilities**
- **Cross-platform support**: Linux, macOS, BSD, WSL, Cygwin/MSYS2
- **Shell compatibility**: bash 3.2+ (macOS compatible), zsh, POSIX shells
- **Multi-format reporting**: JSON, HTML, and text outputs
- **CI/CD integration**: Non-interactive modes with machine-readable reports
- **Parallel execution**: Optional parallel test execution for faster feedback

## Quick Start

### Basic Usage

**From the tool directory:**
```bash
./run_tests.sh                           # Run all tests with default settings
./run_tests.sh --quick compatibility     # Quick compatibility check
```

**From any directory (if tool is installed globally):**
```bash
wp-db-import test                         # Run all tests (default: --quick all)
wp-db-import test --quick compatibility   # Quick compatibility check
wp-db-import test --verbose wordpress     # Verbose WordPress testing
wp-db-import test --ci --format json      # CI mode with JSON output
```

### Test Execution Options

| Command | Description | Requirements |
|---------|-------------|--------------|
| `wp-db-import test` | Global command (works from any directory) | Tool installed globally |
| `./run_tests.sh` | Full-featured test runner | Run from tool directory |
| `./run_tests.sh --quick all` | Fast execution of all test suites | Run from tool directory |
| `./run_tests.sh compatibility` | Run only compatibility tests | Run from tool directory |
| `./run_tests.sh --ci --format json` | CI mode with JSON output | Run from tool directory |
| `./run_tests.sh --verbose wordpress` | Verbose WordPress testing | Run from tool directory |

### Alternative Test Runners

**Global Test Command** (works from any directory):
```bash
wp-db-import test [options] [test_suite]    # If tool is installed globally
```

**Simple Test Runner** (no dependencies):
```bash
./test-runner-simple.sh                     # From tool directory only
```

**Validation Command** (private testing):
```bash
./wp-db-import validate                     # Quick functionality check
```

## Important Notes

🌍 **Global Test Command**: If the tool is installed globally (via `./install.sh`), you can run `wp-db-import test` from any directory. The command automatically changes to the tool's directory, runs the tests, and returns to your original location.

⚠️ **Test reports are not committed to the repository** - they are generated locally in `lib/tests/reports/` and excluded via `.gitignore`. This prevents repository bloat and ensures clean commits.

💡 **Report Management**: Reports are automatically cleaned up between test runs. For CI/CD, use custom output directories or archive reports as build artifacts.

## Test Suites Reference

### 1. Compatibility Tests (`compatibility`)

**OS/Shell Compatibility (`test_os_shell.sh`)**
- Operating system detection (Linux, macOS, BSD variants)
- Shell type and version detection
- POSIX shell compliance testing
- Utility implementation differences (GNU vs BSD tools)

**Bash Version Compatibility (`test_bash_versions.sh`)**
- Bash version detection and feature testing
- Bash 3.2 limitations handling (macOS)
- Bash 4.x/5.x feature availability
- Associative array support detection

### 2. System Tests (`system`)

**Environment Testing (`test_environment.sh`)**
- System resource validation (memory, disk space)
- Required utilities availability
- File system access permissions
- Network connectivity testing
- Signal handling validation

### 3. Unit Tests (`unit`)

**Core Functions (`test_core_functions.sh`)**
- Function definition validation
- Module loading testing
- Configuration handling
- Error handling verification

### 4. Integration Tests (`integration`)

**WordPress Functionality (`test_wordpress.sh`)**
- WP-CLI integration testing
- Configuration file validation
- Domain sanitization testing
- Database connection simulation
- Multisite environment detection

### 5. Validation Tests (`validation`)

**Tool Validation (`validate` command)**
- Script loading verification
- Module availability checking
- Version information validation
- Core function availability testing

## Command Line Options

### Main Test Runner (`./run_tests.sh`)

```bash
./run_tests.sh [options] [test_suite]
```

#### Options
- `--format FORMAT` - Report format: `json`, `html`, `text`, `all` (default: all)
- `--output DIR` - Output directory for reports (default: `lib/tests/reports`)
- `--verbose` - Enable verbose output and detailed logging
- `--quick` - Run only essential tests for faster feedback
- `--parallel` - Run tests in parallel when possible
- `--ci` - CI mode (non-interactive, minimal output)
- `--help` - Show help message

#### Test Suites
- `all` - Run all test suites (default)
- `compatibility` - OS and shell compatibility tests
- `system` - System environment tests
- `unit` - Unit tests for core functions
- `wordpress` - WordPress functionality tests
- `validation` - Tool validation tests

### Environment Variables

- `TEST_TIMEOUT` - Timeout for individual tests (default: 300s)
- `TEST_PARALLEL` - Enable parallel test execution (default: false)
- `TEST_VERBOSE` - Enable verbose mode (default: false)

## Report Formats

### JSON Reports
Machine-readable format suitable for CI/CD integration:
```json
{
  "timestamp": "2025-11-17T11:56:34Z",
  "test_suite": "all",
  "summary": {
    "total": 5,
    "passed": 5,
    "failed": 0,
    "skipped": 0
  },
  "tests": [...]
}
```

### HTML Reports
Interactive web-based reports with:
- Color-coded test results
- Expandable test details
- Performance metrics
- Browser-friendly viewing

### Text Reports
Human-readable terminal output with:
- Color-coded status indicators
- Detailed test descriptions
- Execution timing information
- Summary statistics

## CI/CD Integration

### GitHub Actions Example
```yaml
- name: Run WordPress DB Import Tests
  run: |
    chmod +x run_tests.sh
    ./run_tests.sh --ci --format json --output ./test-reports

- name: Archive Test Reports
  uses: actions/upload-artifact@v3
  if: always()
  with:
    name: test-reports
    path: test-reports/
```

### Jenkins Pipeline Example
```groovy
stage('Test WordPress DB Import Tool') {
    steps {
        sh './run_tests.sh --ci --format json --output ./test-reports'
        publishHTML([
            allowMissing: false,
            alwaysLinkToLastBuild: true,
            keepAll: true,
            reportDir: 'test-reports',
            reportFiles: '*.html',
            reportName: 'WordPress DB Import Test Report'
        ])
    }
}
```

**Important**: Always use custom output directories (like `./test-reports`) in CI/CD to avoid conflicts with the default `lib/tests/reports/` directory which is gitignored.
```

### Docker Testing Example
```dockerfile
FROM ubuntu:20.04
RUN apt-get update && apt-get install -y bash mysql-client
COPY . /app
WORKDIR /app
RUN chmod +x run_tests.sh
CMD ["./run_tests.sh", "--ci", "--format", "json"]
```

## Troubleshooting

### Common Issues

**1. Permission Denied**
```bash
chmod +x run_tests.sh test-runner-simple.sh
```

**2. Bash Version Compatibility**
- macOS uses Bash 3.2 by default (supported)
- Linux typically uses Bash 4.x/5.x (full features)
- Test framework automatically detects and adapts

**3. Missing Dependencies**
```bash
# Check system requirements
./wp-db-import validate

# Install missing tools (example for Ubuntu)
sudo apt-get install mysql-client
```

**4. Test Failures**
- Check individual test logs in `lib/tests/reports/`
- Run with `--verbose` flag for detailed output
- Verify environment compatibility

### Debug Mode

Run tests with maximum debugging:
```bash
bash -x ./run_tests.sh --verbose all
```

## Development

### Adding New Tests

1. **Create test file** in appropriate category directory:
```bash
# Example: lib/tests/unit/test_new_feature.sh
```

2. **Use test framework functions**:
```bash
#!/bin/bash
source "$(dirname "$0")/../test_framework.sh"

init_test_session "new_feature_tests"

test_my_function() {
    start_test "My Function" "Test my function works correctly"

    # Test logic here
    if my_function_works; then
        pass_test "Function works as expected"
    else
        fail_test "Function failed"
    fi
}

# Run tests
run_my_tests() {
    print_test_header "🔧 My Feature Tests"
    test_my_function
}

run_my_tests
finalize_test_session
```

3. **Test framework automatically detects** new tests in standard locations

### Test Framework API

**Session Management**
- `init_test_session "session_name"` - Initialize test session
- `finalize_test_session` - Complete session and save results

**Test Execution**
- `start_test "name" "description"` - Begin individual test
- `pass_test "message"` - Mark test as passed
- `fail_test "message"` - Mark test as failed
- `skip_test "reason"` - Skip test with reason

**Assertions**
- `assert_equals "expected" "actual" "message"`
- `assert_not_empty "value" "message"`
- `assert_file_exists "path" "message"`
- `assert_command_success "command" "message"`

**Environment Detection**
- `detect_os()` - Get operating system
- `detect_shell()` - Get shell type and version
- `detect_utilities()` - Check available utilities

## Exit Codes

- `0` - All tests passed
- `1` - Some tests failed
- `2` - Test runner error (setup, configuration, etc.)

## Support

For issues with the test framework:
1. Check this documentation
2. Run `./run_tests.sh --help` for usage information
3. Examine test reports in `lib/tests/reports/`
4. Use `./wp-db-import validate` for basic diagnostics

---

*This test framework ensures the WordPress Database Import Tool works reliably across diverse environments and configurations.*
