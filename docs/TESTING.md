# WordPress Database Import Tool - Test Framework Documentation

## Overview

The WordPress Database Import Tool includes a comprehensive test framework to validate functionality, compatibility, and reliability across different operating systems, shell versions, and WordPress environments. The test suite covers everything needed for production-grade deployments and CI/CD pipelines.

## Test Categories

- **Compatibility Tests**: OS and shell compatibility (Linux, macOS, BSD, WSL, Cygwin, Bash 3.2+, Zsh, POSIX)
- **System Tests**: Environment validation, resource checks, permissions, utilities
- **Unit Tests**: Core function and module validation
- **Integration Tests**: WordPress-specific scenarios, WP-CLI, multisite, config
- **Validation Tests**: Tool/module loading, version info, basic diagnostics

## Quick Start

### Run All Tests
```bash
# From project directory
./run_tests.sh

# From anywhere (if installed globally)
wp-db-import test
```

### Run Specific Test Suites
```bash
./run_tests.sh compatibility      # OS/shell compatibility
./run_tests.sh bash               # Bash version compatibility
./run_tests.sh system             # System environment
./run_tests.sh unit               # Core functions
./run_tests.sh wordpress          # WordPress integration
./run_tests.sh validation         # Tool validation
```

### Common Options
```bash
./run_tests.sh --quick all        # Fast essential tests
./run_tests.sh --format html      # Generate HTML report
./run_tests.sh --ci --format json # CI mode, JSON output
./run_tests.sh --verbose wordpress # Verbose WordPress tests
```

## Directory Structure
```
lib/tests/
├── test_framework.sh           # Core test framework
├── compatibility/              # OS and shell compatibility
│   ├── test_os_shell.sh
│   └── test_bash_versions.sh
├── system/
│   └── test_environment.sh
├── integration/
│   └── test_wordpress.sh
├── unit/
│   └── test_core_functions.sh
├── fixtures/
│   └── README.md
└── reports/                    # Test reports (generated)
    ├── test_results.json
    ├── test_results.html
    └── test_results.txt
```

## Test Reports
- **HTML**: Interactive, color-coded, browser-friendly
- **JSON**: Machine-readable, CI/CD integration
- **Text**: Terminal summary, color-coded

Reports are saved to `lib/tests/reports/` (or custom output dir) and auto-cleaned between runs. Not committed to git.

## CI/CD Integration

### GitHub Actions Example
```yaml
- name: Run Tests
  run: ./run_tests.sh --ci --format json --output ./test-reports
- name: Upload Results
  uses: actions/upload-artifact@v3
  with:
    name: test-reports
    path: test-reports/
```

### Jenkins Example
```groovy
stage('Test') {
    steps {
        sh './run_tests.sh --ci --format json --output ./test-reports'
        publishHTML([
            reportDir: 'test-reports',
            reportFiles: '*.html',
            reportName: 'Test Report'
        ])
    }
}
```

## Writing Tests

- Place new test files in the appropriate category directory
- Source `test_framework.sh` for assertions and utilities
- Use `start_test`, `pass_test`, `fail_test`, `skip_test`, and assertion helpers
- See `lib/tests/README.md` for examples and API

## Troubleshooting

- **Permission Denied**: `chmod +x run_tests.sh`
- **Missing Dependencies**: Install WP-CLI, MySQL client, etc.
- **Test Failures**: Check logs in `lib/tests/reports/`, use `--verbose`
- **Debug Mode**: `bash -x ./run_tests.sh --verbose all`

## Support

- Run `./run_tests.sh --help` for usage
- See `lib/tests/README.md` for advanced details
- Use `wp-db-import validate` for quick diagnostics

---

*This test framework ensures the WordPress Database Import Tool works reliably across all supported environments and configurations.*
