# WordPress Database Import Tool - Test Framework Documentation

## Overview

The WordPress Database Import Tool includes a comprehensive test framework to validate functionality, compatibility, and reliability across different operating systems, shell versions, and WordPress environments. The test suite covers everything needed for production-grade deployments and CI/CD pipelines.

## Test Categories

- **Compatibility Tests**: OS and shell compatibility (Linux, macOS, BSD, WSL, Cygwin, Bash 3.2+, Zsh, POSIX)
- **System Tests**: Environment validation, resource checks, permissions, utilities
- **Unit Tests**: Core function and module validation, plus import hardening (backup, compressed dumps, compatibility filter, checksum, temp files, benchmark safety)
- **Security Tests**: Penetration-style checks (injection, traversal, symlink, tampering, gzip bomb, static scan)
- **Server Matrix (opt-in)**: Fixture dumps imported into real MySQL/MariaDB servers
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
./run_tests.sh security           # Penetration-style security tests
./run_tests.sh matrix             # Real server version matrix (opt-in, not part of "all")
```

### Real Import (end to end)

`./run_tests.sh real-import` runs the **real tool against real WordPress sites** and checks the database afterwards. It is opt-in (not part of `all`) because it starts a server, downloads WordPress and takes about two minutes.

What it does:
1. Starts a throw-away MySQL (temporary data directory, Unix socket only, no network). Your own databases are never touched: `MYSQL_*` variables are cleared and the test only talks to its own server.
2. Installs a "production" WordPress with WP-CLI, adds content (links, protocol-relative links, serialized data), and exports a dump.
3. Installs a separate "target" WordPress and runs `import_wp_db.sh` with a config file.
4. Checks `siteurl`/`home`, replaced links and serialized options, that no old domain is left, the pre-import backup (valid gzip, original data, mode 600), cache and rewrite flush, no temp files left, and that the console shows no shell or PHP errors.

Scenarios: single site (socket), `use_socket=false` (WP-CLI path), `.sql.gz` dump, MariaDB collations (compatibility retry), multisite subdirectory, multisite subdomain, and **dry run** (`--dry-run` and `dry_run=true`): every table checksum and the database list must be identical before and after, reported tables/rows/occurrences must equal independent counts from the dump, a dump with `CREATE/USE/DROP DATABASE` must not touch the real database, a user without `CREATE DATABASE` gets a clear message, and a multisite dry run lists the subsite mapping first. **Custom mappings** (8a, 8b): a third-party host, a `www` URL and a serialized option are replaced, an email on the main domain is not, a second run changes nothing, an invalid entry stops the run before anything changes, and on a subdirectory network a `[domain_mappings]` entry applies to every site while a `[site_domain_mappings]` entry applies to one site only. Offline: `WPDB_TEST_WP_VERSION=<cached version>`.

Needs: a MySQL/MariaDB server binary (found automatically in Local and Homebrew), `php` with `mysqli`, WP-CLI, and network access for `wp core download` (WP-CLI caches it). The suite is skipped with a reason when something is missing.

```bash
./run_tests.sh real-import
WPDB_TEST_SERVER_BIN=/path/to/mysql/bin ./run_tests.sh real-import   # choose the server
WPDB_TEST_DEBUG=1 ./run_tests.sh real-import                         # print the tool's output
```

### Server Version Matrix

`./run_tests.sh matrix` starts throw-away MySQL/MariaDB servers (temporary data directory, socket only, no network) and imports `lib/tests/fixtures/dump_*.sql` into each with and without the compatibility filter. Servers are found automatically (Local by Flywheel, Homebrew). Add others with:

```bash
WPDB_MATRIX_SERVERS="/opt/homebrew/opt/mariadb@10.6/bin /path/to/mysql-8.0/bin" ./run_tests.sh matrix
```

The test is skipped when no server binaries are found. It is not part of `all` because it starts real servers.

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
├── server_helpers.sh           # throw-away MySQL/MariaDB servers (matrix, real import)
├── compatibility/              # OS and shell compatibility
│   ├── test_os_shell.sh
│   └── test_bash_versions.sh
├── system/
│   └── test_environment.sh
├── integration/
│   ├── test_real_import.sh     # opt-in: real sites, real server, real tool
│   ├── test_server_matrix.sh   # opt-in
│   └── test_wordpress.sh
├── unit/
│   ├── test_core_functions.sh
│   ├── test_ci_workflow.sh        # CI workflow file and VERSION/CHANGELOG/tag check
│   ├── test_dry_run.sh            # --dry-run: helpers, decision, stubbed preview, wiring
│   ├── test_import_hardening.sh
│   ├── test_import_performance.sh
│   ├── test_import_security.sh
│   ├── test_new_modules.sh
│   ├── test_domain_mappings.sh    # [domain_mappings]: anchoring, order, scopes, report, config, regression guards
│   ├── test_backup_edge.sh        # backup: free space, backup_keep_days, gpg encryption, progress, restore of encrypted files
│   ├── test_doctor.sh             # wp-db-import doctor: tools, connection, config, backup folder, no secrets
│   ├── test_restore.sh            # wp-db-import restore: listing, flow, safety backup, rotation protection
│   ├── test_socket_detection.sh
│   ├── test_update_uninstall.sh   # update command and uninstall.sh in a sandbox
│   └── test_yes_flag.sh           # --yes / --non-interactive: helpers, flags, no-hang, required values
├── fixtures/
│   ├── README.md
│   ├── dump_legacy.sql         # accepted by every server version
│   ├── dump_mariadb11.sql      # MariaDB 11 collations/engine/sandbox line
│   ├── dump_mysql8.sql         # MySQL 8 collations/GTID/DEFINER
│   └── dump_nodrop_mariadb11.sql  # no DROP TABLE: retry needs cleanup (#27)
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

### GitHub Actions (this repository)
`.github/workflows/tests.yml` runs on every pull request, on pushes to `main` and on `v*` tags:

| Job | What it runs |
|-----|--------------|
| `lint` | `bash -n`, `shellcheck -S error -s bash`, `lib/tests/check_version.sh` (VERSION = newest CHANGELOG release; on tags, tag = VERSION) |
| `unit` | `./run_tests.sh --ci unit` and `security` on macOS (system Bash 3.2 and Homebrew Bash 5, BSD and GNU userland) and Ubuntu (Bash 5, GNU) |
| `matrix` | `./run_tests.sh matrix` and `real-import` on Ubuntu with MySQL and with MariaDB (installed from apt, `WPDB_MATRIX_SERVERS=/usr/sbin`) |

Reports (`test-reports/`) are uploaded as workflow artifacts. Run the version check locally with `lib/tests/check_version.sh [tag]`.

Not covered yet: Bash 4.4 and the older MySQL/MariaDB versions (the Ubuntu runner installs one distribution version of each). Add them to `WPDB_MATRIX_SERVERS` when needed.

### Generic example
```yaml
- name: Run Tests
  run: ./run_tests.sh --ci --format json --output ./test-reports
- name: Upload Results
  uses: actions/upload-artifact@v4
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
