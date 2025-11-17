# Test Reports Directory

This directory contains generated test reports from the WordPress Database Import Tool test framework.

## Report Types

- **JSON Reports** (`*.json`) - Machine-readable test results for CI/CD integration
- **HTML Reports** (`*.html`) - Interactive web-based reports for manual review
- **Text Reports** (`*.txt`) - Human-readable terminal-style output

## Important Note

⚠️ **Test reports are not committed to the repository** - they are generated locally and excluded via `.gitignore`.

## Report Generation

Reports are automatically generated when running:
- `./run_tests.sh` (all formats by default)
- `./run_tests.sh --format json` (specific format)
- `./run_tests.sh --output ./custom-dir` (custom location)

## Cleaning Reports

To clean old test reports:
```bash
rm -rf lib/tests/reports/*.{json,html,txt}
```

## CI/CD Usage

In automated environments, reports are typically generated to a temporary directory and archived as build artifacts rather than committed to source control.
