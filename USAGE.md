# WordPress Database Import & Domain Replacement Tool

A robust, cross-platform CLI tool for WordPress database imports, domain/URL replacements, multisite migration, and advanced configuration management.

## 🚀 Quick Installation
```bash
git clone https://github.com/manishsongirkar/wp-db-import-and-domain-replacement-tool.git
cd wp-db-import-and-domain-replacement-tool
./install.sh
wp-db-import --help
```

## 📋 Usage

### Main Commands
```bash
wp-db-import                    # Run the main import function
wp-db-import --dry-run          # Preview only: nothing is changed (temporary database)
wp-db-import --yes              # Unattended: every prompt takes its default (also -y, --non-interactive)
wp-db-import config-show        # Show unified configuration status
wp-db-import config-create      # Create configuration with site mappings
wp-db-import config-validate    # Validate configuration structure
wp-db-import config-edit        # Open configuration in editor
wp-db-import show-links         # Show local site links
wp-db-import setup-proxy        # Auto-setup Stage File Proxy (uses config)
wp-db-import show-cleanup       # Show revision cleanup commands
wp-db-import restore --last     # Restore the newest backup of this site's database
wp-db-import restore --list     # List backups (--all: every database)
wp-db-import restore <file>     # Restore a specific backup file
wp-db-import update             # Update to latest version
wp-db-import version            # Show version and git info
wp-db-import test               # Run test suite to validate tool functionality
wp-db-import --help             # Show this help message
```

💡 **Tab Completion**: Type `wp-db-import ` and press TAB to see all available commands!

> **Note:** Autocomplete suggestions are automatically updated when you run `./install.sh`.

### Dry Run (`--dry-run`)

```bash
wp-db-import --dry-run             # or dry_run=true in the config, or WPDB_DRY_RUN=1
```

Imports the dump into a **temporary database**, reports `Would import: N tables / M rows`, whether the compatibility filter is needed, and how many occurrences of the old domain (and of every site-mapping domain) would be replaced per table, then drops the temporary database. Your database is not changed: no backup, no import, no replacement. Needs the mysql client and permission to `CREATE DATABASE` (a clear message is shown if missing). Before this change `dry_run=true` still imported the dump; now it imports nothing.

### Unattended Mode (`--yes`)

For scripts and CI. Every prompt takes its default (same as Enter), nothing is read from stdin, and stdin is closed for the whole run.

```bash
wp-db-import --yes                 # or -y, --non-interactive, or WPDB_ASSUME_YES=1
bash import_wp_db.sh --yes         # direct script call
```

- A prompt with no safe default fails with a clear message (exit 1): SQL file name, old/new domain, the domain-mismatch choice, "MySQL commands executed manually?". Set them in `wpdb-import.conf`.
- Backups run when `backup_before_import=ask`. `update` never overwrites local changes.
- Keys missing from the config use the documented defaults (revision cleanup `Y`, all tables `Y`, dry-run `N`, Stage File Proxy `Y`): set them for predictable runs.
- Exit codes: `0` success, `1` failure, `2` usage error.

### Example Workflow
```bash
cd ~/Local\ Sites/mysite/app/public
cp ~/Downloads/production-db.sql ./
wp-db-import
```

> 📖 **See detailed demo outputs:** [Usage Example Output](docs/USAGE_EXAMPLE.md)

## 🗂️ Configuration System

- First run prompts for SQL file, domains, and creates `wpdb-import.conf`
- Multisite: prompts for site mappings, saves all settings
- Subsequent runs auto-load config, only prompt for new sites
- Config management via `config-show`, `config-create`, `config-validate`, `config-edit`

### Example Configuration File
```ini
[general]
sql_file=production-database.sql
old_domain=production-site.com
new_domain=local-site.test
all_tables=true
dry_run=false
clear_revisions=true
setup_stage_proxy=true
auto_proceed=false
use_socket=auto
mysql_socket=
import_optimizations=auto
parallel_import=false
backup_before_import=ask
backup_dir=
backup_keep=5

[site_mappings]
1:production-site.com:local-site.test
2:blog.production-site.com:local-site.test/blog
3:shop.production-site.com:local-site.test/shop
```

### Socket Import Behavior

- `use_socket=auto` is the recommended default for Local, Homebrew MySQL, MAMP, DBngin, and similar host-native setups.
- Set `mysql_socket` only if you want to override auto-detection with a fixed socket path.
- On host-side Lando and DDEV projects, MySQL runs inside Docker, so there is no host-accessible socket file to use. In that case the tool skips socket import and falls back to WP-CLI automatically.

### Import Optimization Behavior

- `import_optimizations=auto` applies session-level MySQL import flags (`AUTOCOMMIT=0`, `FOREIGN_KEY_CHECKS=0`, `UNIQUE_CHECKS=0`) when using direct mysql/socket import.
- These flags are skipped automatically when importing through WP-CLI fallback so behavior stays compatible.
- `parallel_import` stays disabled by default because regular SQL dumps are order-sensitive; forcing parallel execution can corrupt import order.

### Pre-Import Backup Behavior

- `backup_before_import=ask` (default) asks `Back up the current database before importing? (Y/n)` on every run. Press Enter for Yes.
- Answer `n` and the tool saves `backup_before_import=false` into `wpdb-import.conf`, so it will not ask again. Change it back to `ask` or `true` to re-enable.
- `true` always backs up without asking. `false` never backs up.
- With `auto_proceed=true`, `ask` backs up without prompting. If a requested backup fails, the import is cancelled.
- Backups are written to `~/.wp-db-import/backups/<dbname>-<timestamp>.sql.gz` (owner-only). Override with `backup_dir=`.
- `backup_keep=5` keeps the newest 5 backups per database and deletes older ones after each backup (rotation). `0` keeps all.
- The tool keeps no log files between runs: logs are in a private temp directory removed when the run ends, and are size-capped. When an import fails, the first error lines are printed on screen.
- Restore: `gunzip -c ~/.wp-db-import/backups/<file>.sql.gz | wp db import -`

### Restoring a Backup

```bash
wp-db-import restore --list          # newest first; --all for every database
wp-db-import restore --last          # asks first (default No); --yes skips the question
wp-db-import restore ~/.wp-db-import/backups/mydb-20261009-124840.sql.gz
```

The backup is verified, the current database is backed up first (so you can undo), the import uses the normal fast path with error checks, and tables that were not in the backup are removed afterwards. `backup_keep` rotation never deletes the file being restored.

### Compressed Dumps

`sql_file` can be `.sql.gz`, `.zip` or `.sql.bz2`. The archive is verified, then streamed (no extraction to disk).

### Cross-Version Compatibility

If an import fails with a known compatibility error (unknown collation, missing definer, `ENGINE=Aria`, GTID statements, ...), the tool retries once with a filter that adapts the SQL to the target server. Dumps that already import are never changed, and row data is never modified.

For dumps without `DROP TABLE` statements, the tables created by the failed attempt are removed before the retry (pre-existing tables are never touched).

### mysql Client

The `mysql` client first in your `PATH` is used; Homebrew directories are only a fallback. `WPDB_MYSQL_BIN` picks a client explicitly, `WPDB_VERBOSE=1` shows which one is used, and a warning appears if the client and server are different products (MariaDB vs MySQL).

### Example Setup
```bash
cp wpdb-import-example-single.conf ~/path/to/wordpress/wpdb-import.conf
nano ~/path/to/wordpress/wpdb-import.conf
wp-db-import
```

## 🧹 Uninstall
```bash
./uninstall.sh                    # interactive
./uninstall.sh --yes              # no prompts (backups are kept)
./uninstall.sh --delete-backups   # also delete saved backups in ~/.wp-db-import
./uninstall.sh --keep-backups     # never ask about backups
```
Removes the command, shell completions and stale temp directories. Saved backups are only deleted on an explicit yes. Failures print the exact cause (error text, path, permissions, hint) and the script exits non-zero.

## 🔄 Auto-Updates
```bash
wp-db-import update         # Automatic (git installations)
cd ~/path/to/wp-db-import-and-domain-replacement-tool && git pull  # Manual
```

## ✨ Features
- User-local installation (no sudo required)
- Symlinked global command (instant updates)
- Tab completion for all commands
- Multisite support (subdomain/subdirectory)
- Bulk revision cleanup (xargs)
- Stage File Proxy integration
- GitIgnore protection for dev plugins
- Smart domain replacement (handles serialized data)
- Modern, colored terminal output
- Full bash/zsh/POSIX compatibility (see BASH_COMPATIBILITY.md)
- Comprehensive test suite (see TESTING.md)

## 🛠️ Requirements
- WP-CLI installed and in PATH
- WordPress installation (wp-config.php present)
- MySQL/MariaDB database access
- Bash shell (macOS/Linux)

## 🧪 Testing
```bash
wp-db-import test                # Run all tests (globally)
./run_tests.sh                   # Run all tests from project directory
./run_tests.sh compatibility     # OS/shell compatibility only
./run_tests.sh --quick all       # Fast essential tests
./run_tests.sh security          # Penetration-style security tests
./run_tests.sh matrix            # Real MySQL/MariaDB version matrix (opt-in)
```
See TESTING.md for full details.

## 🔒 GitIgnore Protection System
- Automatically adds `/plugins/stage-file-proxy/` to `wp-content/.gitignore`
- Detects semantic duplicates and whitespace variations
- Prevents accidental commits of local/staging-only plugins
- Manual management via `add_stage_file_proxy_to_gitignore`, `show_stage_file_proxy_gitignore_status`, `remove_stage_file_proxy_from_gitignore`

## 🔧 Development Structure
```markdown
wp-db-import-and-domain-replacement-tool/
├── wp-db-import                        # Main executable
├── import_wp_db.sh                     # Core import logic
├── install.sh                          # Installer
├── uninstall.sh                        # Uninstaller
├── VERSION                             # Version file
├── README.md                           # Main documentation
├── CHANGELOG.md                        # Release notes
├── hooks/pre-commit                    # Optional pre-commit test hook
├── install_pre_commit_hook.sh          # Installs the hook
├── watch_and_test.sh                   # Re-run tests on file change
├── USAGE.md                            # Usage guide
├── CONTRIBUTING.md                     # Contributor guidelines
├── LICENSE                             # License file
├── lib/
│   ├── module_loader.sh                # Module loader
│   ├── version.sh                      # Version management
│   ├── completion/                     # Autocomplete scripts
│   ├── config/                         # Config management modules
│   ├── core/                           # Core utilities
│   ├── database/                       # Import, socket detection, backup, SQL compatibility, search-replace
│   ├── tests/                          # Test framework and suites
│   ├── utilities/                      # Utility modules
├── docs/                               # Documentation
│   ├── BASH_COMPATIBILITY.md           # Bash compatibility info
│   ├── INSTALLATION_METHODS.md         # Installation methods
│   ├── TESTING.md                      # Test documentation
│   ├── VERSION_MANAGEMENT.md           # Version management
├── reports/                            # Test reports (generated)
│   ├── test_results.html               # HTML report
│   ├── test_results.json               # JSON report
│   ├── test_results.txt                # Text report
├── temp/                               # Temporary files, examples, modules
│   ├── examples/                       # Example configs/scripts
│   ├── modules/                        # Example modules
│   ├── patterns/                       # Example patterns
│   ├── utilities/                      # Example utilities
├── wpdb-import-example-single.conf     # Example single-site config
├── wpdb-import-example-multisite.conf  # Example multisite config
```

## 🗑️ Uninstallation
```bash
./uninstall.sh
```

## 🕰️ Backward Compatibility
```bash
source ~/wp-db-import-and-domain-replacement-tool/import_wp_db.sh
import_wp_db
```

---
