![Image](https://github.com/user-attachments/assets/e32b7caf-defa-4c78-aed2-70d8601b2fd8)

# 🧩 WordPress Database Import & Domain Replacement Tool

![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg) ![GitHub issues](https://img.shields.io/github/issues/manishsongirkar/wp-db-import-and-domain-replacement-tool)

Accelerate your local development setup with this advanced WP-CLI wrapper. Built for reliable WordPress migration automation, it effortlessly manages database imports and performs accurate database search and replace (including serialized data) to synchronize production data with local or staging environments.

## 📦 Installation & Setup

### 🚀 Quick Install (Recommended)

**Option 1: Git Clone (Auto-updates enabled)**
```bash
# 1. Clone the repository
git clone https://github.com/manishsongirkar/wp-db-import-and-domain-replacement-tool.git
cd wp-db-import-and-domain-replacement-tool

# 2. Install globally
./install.sh

# 3. Use from anywhere!
cd ~/Local\ Sites/mysite/app/public
wp-db-import
```

**Option 2: ZIP Download (Manual updates)**
```bash
# 1. Download and extract ZIP from GitHub releases
# 2. Navigate to extracted folder
cd wp-db-import-and-domain-replacement-tool

# 3. Install globally
./install.sh

# 4. Use from anywhere!
cd ~/Local\ Sites/mysite/app/public
wp-db-import
```

### ✅ Verification
```bash
# Test installation
wp-db-import --help

# Check version and installation info
wp-db-import version
```

### 🚀 Usage:
- 📖 **Comprehensive usage examples and workflows:** [Usage Guide](USAGE.md)
- 📖 **See detailed demo outputs:** [Usage Example Output](docs/USAGE_EXAMPLE.md)

## ✨ Features

- 🌍 **Global Command Access** — Install once and run `wp-db-import` from any project directory.
- 🔧 **Cross-shell Compatibility** — Designed for macOS/Linux and supports a wide range of Bash versions with fallbacks.
- 📋 **Project-scoped Configuration** — Stores settings and per-site mappings in `wpdb-import.conf` within the WP root.
- 🔄 **Automatic WP Detection** — Finds WordPress root and detects single-site vs multisite installations.
- 🗺️ **Multisite-aware Mapping** — Persisted per-site mappings; prompts only for missing sites.
- ⚡ **Fast Revision Cleanup** — High-speed bulk deletion of post revisions to speed up search-replace.
- 🔁 **Reliable Search & Replace** — WP-CLI powered search-replace with dry-run support and serialized data handling.
- 📦 **Safe Multisite Updates** — Attempts wp_blogs/wp_site updates and emits MySQL commands when manual intervention is needed.
- 🧹 **Post-Import Cleanup** — Flushes caches, rewrite rules, and transients after operations.
- 📸 **Stage File Proxy Integration** — Optional setup for serving media from production in local environments.
- 🧪 **Dry-run & Safety** — Preview changes before applying them; comprehensive logging for troubleshooting.
- ⚡ **Fast Local Import** — Imports through the MySQL Unix socket (or the `mysql` client) with WP-CLI as the automatic fallback.
- 💾 **Pre-Import Backup** — Saves a compressed copy of the current database before it is replaced, and lets you opt out (the choice is saved in the config).
- 🗜️ **Compressed Dumps** — Imports `.sql.gz`, `.zip` and `.sql.bz2` directly, streamed without extracting to disk.
- 🔀 **Cross-Version SQL Compatibility** — Retries a failed import with a filter that fixes MariaDB/MySQL version differences (collations, engines, `DEFINER`, GTID).
- 🔒 **Hardened by Default** — Private temp files, checksum-verified plugin download, passwords never on the command line, benchmark that never touches your real database.

## 🧰 Requirements

| Requirement | Description | Version Notes |
|--------------|-------------|---------------|
| **Operating System** | macOS/Linux environment with Bash shell | **All Bash versions supported (3.2+)** |
| **Bash Compatibility** | Cross-version support with automatic fallbacks | **Bash 3.2, 4.x, 5.x** |
| **WP-CLI** | WordPress Command Line Interface | Latest stable version |
| **WordPress** | WordPress installation with wp-config.php | Single-site or multisite |
| **Database** | MySQL/MariaDB database with import privileges | 5.7+ or 10.2+ |
| **PHP** | PHP runtime for WP-CLI operations | 7.4+ recommended |
| **File System** | Read/write access to WordPress directory | Sufficient disk space for import |

### 🔧 Troubleshooting

**Command not found:**
```bash
# Check if ~/.local/bin is in PATH
echo $PATH | grep -q "$HOME/.local/bin" && echo "✅ In PATH" || echo "❌ Not in PATH"

# Add to PATH manually (for current session)
export PATH="$HOME/.local/bin:$PATH"

# Add to shell profile (permanent)
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.zshrc  # or ~/.bashrc
source ~/.zshrc  # or ~/.bashrc
```

**Permission issues:**
```bash
# Check symlink and permissions
ls -la ~/.local/bin/wp-db-import
ls -la "$(readlink ~/.local/bin/wp-db-import)"

# Recreate symlink if needed
rm ~/.local/bin/wp-db-import
./install.sh
```

### 🔄 Updates

**Auto-updates (Git installations):**
```bash
wp-db-import update  # Automatic git pull
```

**Manual updates (ZIP installations):**
```bash
# Download latest version and replace files
# Then re-run: ./install.sh
```

### 🔄 Updating and Uninstalling

```bash
wp-db-import update        # git installations: fast-forward update, shows version change
./uninstall.sh             # interactive uninstall
./uninstall.sh --yes       # no prompts; saved backups are kept
./uninstall.sh --delete-backups   # also delete ~/.wp-db-import (cannot be undone)
```

- `update` only fast-forwards (it never merges or rewrites your history). If it fails it prints the cause and how to fix it, for example when your installed branch was deleted after a merge (`git checkout main && git pull`).
- `uninstall.sh` removes the command, the Bash/Zsh completions and stale private temp directories. It **never deletes your saved database backups unless you answer yes** (or pass `--delete-backups`). If anything cannot be removed it prints the exact error, the path, its permissions and a hint, lists every problem in the summary, and exits non-zero. Per-project `wpdb-import.conf` files and the cloned repository folder are not removed.

### 🤖 Unattended Mode (`--yes`) for Scripts and CI

```bash
wp-db-import --yes                     # or: -y, --non-interactive
WPDB_ASSUME_YES=1 wp-db-import         # same, through the environment
bash import_wp_db.sh --yes             # when running the script directly
```

In unattended mode:
- **Every prompt takes its default**, exactly as if you pressed Enter. Confirmations (`Proceed with database import?`, `Proceed with search-replace?`) are skipped with the reason shown, like `auto_proceed=true`. Values you set in `wpdb-import.conf` are used as before.
- **Nothing is read from stdin or the terminal**, and stdin is closed for the whole run, so a script can never hang waiting for input (even if its stdin is a pipe that never ends).
- **A prompt without a safe default fails** with a clear message and exit code 1: the SQL file name (`sql_file`), the old and new domains, the choice when the config and database domains differ, and "have you run the MySQL commands manually?". Put these in `wpdb-import.conf` first (`wp-db-import config-create`, or copy an example config).
- **Backups still run** when `backup_before_import=ask` (the default). `false` skips them, `true` always runs them.
- `wp-db-import update` answers "no" to its "uncommitted changes" question, so it never overwrites local changes.
- Prompts that are not configured in `wpdb-import.conf` use their documented defaults (for example revision cleanup `Y`, `--all-tables` `Y`, dry-run `N`, Stage File Proxy setup `Y`). **Set these keys in the config** for a predictable CI run.

**Exit codes:** `0` success, `1` failure (including a missing required value), `2` usage error (unknown command or option).

```bash
# Example CI step (config file already contains sql_file, old_domain, new_domain)
cd /path/to/wordpress && wp-db-import --yes
```

### 📋 Available Commands
```bash
# Run main interactive import wizard
wp-db-import

# Unattended (scripts, CI): every prompt takes its default, nothing is read from stdin
wp-db-import --yes              # also: -y, --non-interactive, WPDB_ASSUME_YES=1

# Configuration management
wp-db-import config-show        # Show unified configuration status
wp-db-import config-create      # Create configuration with site mappings
wp-db-import config-validate    # Validate configuration structure
wp-db-import config-edit        # Open configuration in editor

# Show local site links
wp-db-import show-links

# Generate revision cleanup commands
wp-db-import show-cleanup [<path|options>]

# Stage File Proxy setup
wp-db-import setup-proxy

# Detect WordPress installation type
wp-db-import detect [<path>] [--verbose]

# Run the test suite
wp-db-import test [all|unit|integration]

# Update (git installations)
wp-db-import update

# Version and update info
wp-db-import version

# Help
wp-db-import --help
```

## 🧪 Testing

The tool includes a comprehensive test suite that ensures cross-platform compatibility and reliability across different Unix-based operating systems and Bash versions.

### ⚡ Quick Test
```bash
# Run all tests from anywhere (recommended)
wp-db-import test

# Or run from project directory
./run_tests.sh
```

### 🎯 Test Coverage
- **Operating System Compatibility** - Linux, macOS, FreeBSD, WSL, Cygwin/MSYS2
- **Bash Version Support** - Bash 3.2, 4.x, 5.x with feature detection
- **System Environment** - User permissions, utilities, resource limits
- **WordPress Functionality** - WP-CLI integration, database operations, multisite handling
- **Unit Tests** - Core functions, string utilities, configuration management
- **Import Hardening** - Backup preference prompt, compressed dumps, compatibility filter, checksum verification, private temp files, benchmark safety
- **Security Tests** - Penetration-style checks: command injection (file names, passwords, config), path traversal, symlink attacks, tampered downloads, gzip bombs, static scan
- **Server Matrix (opt-in)** - Imports fixture dumps into real MySQL 8.x and MariaDB servers: `./run_tests.sh matrix`
- **Real Import (opt-in)** - Runs the real tool on real WordPress sites (single site, multisite subdirectory and subdomain, `.gz`, compatibility retry) on a throw-away MySQL and checks the database: `./run_tests.sh real-import`

### 📊 Test Reports
Tests generate comprehensive reports in multiple formats:
- **HTML** - Interactive web report with detailed results
- **JSON** - Machine-readable for CI/CD integration
- **Text** - Terminal-friendly summary

Reports are saved to `reports/` directory and automatically cleaned up between runs.

## 🔧 Configuration System

### 🔧 Configuration System

The tool now features a **project-specific configuration system** that remembers your settings and site mappings, making subsequent imports much faster and more convenient.

### 📁 Configuration File Location

The configuration file `wpdb-import.conf` is automatically created in your **WordPress root directory** (same location as `wp-config.php`), making it project-specific.

### ⚙️ Configuration Format

```ini
# ===============================================
# WordPress Database Import Configuration
# ===============================================

[general]
sql_file=production-database.sql
old_domain=admin.example.com
new_domain=example.test
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
# Format: blog_id:old_domain:new_domain
1:admin.example.com:example.test
2:blog.example.com:example.test/blog
3:shop.example.com:example.test/shop
4:news.example.com:example.test/news
5:support.example.com:example.test/support
6:docs.example.com:example.test/docs
```

### MySQL Socket Notes

- `use_socket=auto` tries a Unix socket first for faster local imports, then falls back to WP-CLI if no usable socket is available.
- `use_socket=true` forces a socket attempt, and `use_socket=false` disables socket import entirely.
- `mysql_socket=` lets you pin a known socket path when your environment uses a non-standard location.
- Host-side Docker tools like Lando and DDEV do not expose the MySQL socket on the host filesystem, so the tool intentionally skips socket probing there and uses the WP-CLI path instead.

### Import Performance Notes

- `import_optimizations=auto` enables session-level MySQL flags during direct mysql/socket imports: `AUTOCOMMIT=0`, `FOREIGN_KEY_CHECKS=0`, `UNIQUE_CHECKS=0`.
- `import_optimizations=true` forces those flags for direct mysql imports, and `import_optimizations=false` disables them.
- `parallel_import=false` remains the safe default because generic SQL dumps are order-sensitive. Turning it on currently logs a warning and continues with safe single-stream import.
- For dumps of 100 MB or more the tool prints an import time estimate. It benchmarks a sample in a **temporary scratch database** (dropped afterwards), so your real database is never touched. If the account cannot create databases, or the sample has no `INSERT` rows, a size-based estimate is shown instead.

### 💾 Pre-Import Backup

Before the current database is replaced, the tool can save a compressed copy so a bad import can be undone.

| `backup_before_import` | Behavior |
|---|---|
| `ask` (default) | Asks `Back up the current database before importing? (Y/n)`. **Enter = Yes.** Answering `n` saves `backup_before_import=false` to `wpdb-import.conf`, so you are not asked again. |
| `true` | Always back up, never ask. |
| `false` | Never back up, never ask. |

- Unattended runs (`auto_proceed=true`) back up without asking when the value is `ask`.
- If a requested backup fails, the import is **cancelled** to protect your current data.
- An empty or missing database is skipped (nothing to back up).
- Backups are saved as `<dbname>-<timestamp>.sql.gz` in `~/.wp-db-import/backups` (folder mode `700`, files mode `600`). Set `backup_dir=` to use another folder. Two backups in the same second never overwrite each other.
- The export uses `--add-drop-table`, so a restore replaces existing tables cleanly.
- **Rotation:** `backup_keep=5` (default) keeps the newest 5 backups per database and deletes older ones after each new backup, so the folder cannot grow forever. Use `backup_keep=0` to keep everything. Only files named `<dbname>-YYYYMMDD-HHMMSS.sql.gz` are ever deleted; other files and other databases' backups are never touched. Stale `.partial` files from interrupted runs are cleaned up too.

### 🧾 Logs and Temporary Files

The tool does not keep log files between runs. Import and search-replace logs live in a private temporary directory that is **removed when the run ends** (on success and on failure). Each import log is also size-capped (first and last 128 KB are kept) so a failing import cannot fill the disk, and the first error lines are printed on screen when an import fails. The only data that persists is your backups, which are rotated as described above.

Some MySQL/MariaDB clients exit with code 0 even when statements fail. The tool also scans the import output for `ERROR nnnn` lines, so such an import is reported as failed (and retried with the compatibility filter when appropriate) instead of showing a false "successful".
- **Restore in one command:** `wp-db-import restore --last` (see below). The manual way still works: `gunzip -c <backup-file> | wp db import -`

#### ♻️ Restoring a Backup

```bash
wp-db-import restore --list            # backups of this site's database, newest first
wp-db-import restore --list --all      # backups of every database in the backup folder
wp-db-import restore --last            # restore the newest backup of this database
wp-db-import restore <file>            # restore a specific file (.sql, .sql.gz, .zip, .sql.bz2)
wp-db-import --yes restore --last      # no question (scripts, CI)
```

- The backup is **checked first** (a corrupt archive is refused and nothing is changed).
- You are **asked to confirm** (default No) unless you use `--yes` or `WPDB_ASSUME_YES=1`.
- The **current database is backed up first**, so a restore can be undone (`Undo with: wp-db-import restore "<safety backup>"` is printed). `backup_before_import=false` is honored. `backup_keep` rotation never deletes the file being restored.
- The import uses the same fast path as a normal import (socket, mysql, WP-CLI), checks the output for errors and retries with the compatibility filter when needed.
- After a successful import, **tables that did not exist when the backup was made** are removed (views are never removed, and nothing is removed if the backup's table list cannot be read). The object cache is flushed.
- Exit codes: `0` success or cancelled, `1` failure (no backup found, corrupt archive, import failed), `2` usage error.

### 🗜️ Compressed Dumps

Set `sql_file` to a `.sql.gz`, `.zip` or `.sql.bz2` file. The dump is checked for corruption first, then streamed straight into MySQL or WP-CLI. Nothing is extracted to disk. For `.zip` files only the `.sql` entries are used (macOS `__MACOSX` junk is ignored). Requires `gzip`, `unzip` or `bzip2` on the machine.

### 🔀 Cross-Version SQL Compatibility

Dumps from a different server version (for example a MariaDB 11 dump into MySQL 8.4, or a MySQL 8 dump into MariaDB 10.6) can contain SQL the target rejects. The tool never changes a dump that imports fine. If the first attempt fails with a known compatibility error, it retries **once** with a filter that:

- maps `utf8mb4_0900_*` and `utf8mb4_uca1400_*` collations to `utf8mb4_unicode_520_ci` / `utf8mb4_bin`, `utf8mb3_uca1400_*` to `utf8_unicode_520_ci`, and `utf8mb3` to `utf8`;
- changes `ENGINE=Aria` to `InnoDB` and removes `TRANSACTIONAL` / `PAGE_CHECKSUM`;
- removes `DEFINER=...` clauses, `NO_AUTO_CREATE_USER`, `GTID_PURGED` / `SQL_LOG_BIN` statements and the MariaDB "sandbox mode" first line.

The filter only touches DDL and session statements. Row data inside `INSERT` statements is never modified. When the filter was used, the tool says so after the import.

**Retry safety:** most dumps drop and recreate their tables, so a retry starts clean. For dumps made without `DROP TABLE` statements (for example `mysqldump --skip-add-drop-table`), the tool saves the table list before importing. Before any retry or fallback it removes only the tables the failed attempt created; tables that existed before are never touched. If the table list cannot be saved, the tool does not retry and tells you why.

### 🔧 Which mysql client is used

The tool uses the `mysql` client that comes first in your `PATH`, so the client of your environment (Local, MAMP, DBngin, a Homebrew service you chose, ...) is the one that talks to the server. `/opt/homebrew/bin` and `/usr/local/bin` are only searched **after** your `PATH`, as a fallback. If the client and the server are different products (a MariaDB client with a MySQL server, or the reverse) the tool prints a warning with the client path.

| Variable | Purpose |
|---|---|
| `WPDB_MYSQL_BIN=/path/to/mysql` | Use exactly this client |
| `WPDB_FALLBACK_PATH=/dir1:/dir2` | Fallback directories searched after `PATH` (default `/opt/homebrew/bin:/usr/local/bin`) |
| `WPDB_VERBOSE=1` | Print which mysql client is used |

### 🔒 Security Notes

- Logs and scratch files live in a private per-run temp directory (mode `700`), never in predictable `/tmp` file names. Symlink attacks are refused.
- The database password is passed through the `MYSQL_PWD` environment variable, never on the command line.
- The Stage File Proxy plugin is downloaded from this project's GitHub release and installed **only if its SHA-256 matches the pinned value**.
- Config values, file names, passwords and database names are treated as data and are never evaluated by the shell. See the penetration-style tests in `lib/tests/unit/test_import_security.sh`.

### 🤖 How It Works

1. **First Run**: The tool prompts for all settings and creates the config file
2. **Subsequent Runs**: Settings are loaded automatically from the config file
3. **Missing Mappings**: If new sites are detected, you're only prompted for those
4. **Auto-Update**: The config file is updated with any new mappings you provide

### 📋 Configuration Commands

```bash
# Show unified configuration status
wp-db-import config-show

# Create configuration with site mappings interactively
wp-db-import config-create

# Validate configuration structure and format
wp-db-import config-validate

# Open configuration in your default editor
wp-db-import config-edit
```

### 🔧 Manual Configuration

You can manually edit the `wpdb-import.conf` file in your WordPress root directory:

```bash
# Edit with nano
nano wpdb-import.conf

# Edit with VSCode
code wpdb-import.conf
```

### 💡 Configuration Benefits

- **⚡ Faster Imports**: No need to re-enter the same information
- **🗺️ Site Mapping Memory**: Multisite mappings are remembered
- **🔄 Incremental Setup**: Only prompts for new/missing sites
- **📋 Project-Specific**: Each WordPress project has its own config
- **🧪 Testing-Friendly**: Easily switch between dry-run and live mode

### 📁 Configuration Examples

Ready-to-use configuration examples are available in the project root:

- **`wpdb-import-example-single.conf`** - For standard WordPress sites
- **`wpdb-import-example-multisite.conf`** - For WordPress Multisite networks
- **`USAGE.md`** - Complete usage guide with setup instructions and examples

Quick setup:
```bash
# Copy example to your WordPress root
cp wpdb-import-example-single.conf ~/path/to/wordpress/wpdb-import.conf

# Edit the configuration
nano ~/path/to/wordpress/wpdb-import.conf
```

## 🚀 Usage

### Basic Usage

1. Navigate to your WordPress root directory (where `wp-config.php` file present)
2. Place your SQL (`.sql`) file in the same directory
3. Run the global command:
   ```bash
   wp-db-import
   ```
4. Follow the interactive prompts

## Pre-Operation Safety Checklist:

```bash
# Create timestamped backup with compression
wp db export "backup-$(date +%Y%m%d-%H%M%S).sql.gz" --compress

# Verify backup integrity
gunzip -t "backup-$(date +%Y%m%d-%H%M%S).sql.gz"

# Store backup in secure location
cp backup-*.sql.gz ~/wp-backups/$(basename $(pwd))/
```

## ⚡ Configuration Options

### Configuration File Settings

All options can be pre-configured in your `wpdb-import.conf` file, eliminating the need for manual input on subsequent runs:

| Configuration Key | Description | Default Value | Config Example |
| ----------------- | ----------- | ------------- | -------------- |
| **sql_file** | Database dump file to import | `vip-db.sql` | `sql_file=production-database.sql` |
| **old_domain** | Production domain to search for | Required input | `old_domain=example.com` |
| **new_domain** | Local/staging domain to replace with | Required input | `new_domain=example.test` |
| **all_tables** | Include non-WordPress prefixed tables | `true` | `all_tables=true` |
| **dry_run** | Preview changes without applying them | `false` | `dry_run=false` |
| **clear_revisions** | Delete all post revisions before search-replace | `true` | `clear_revisions=true` |
| **setup_stage_proxy** | Automatically configure stage file proxy | `true` | `setup_stage_proxy=true` |
| **auto_proceed** | Skip confirmation prompts | `false` | `auto_proceed=false` |

### Interactive Options (Runtime Behavior)

| Option | Description | Default | Advanced Notes |
| -------- | ----------- | ------- | -------------- |
| **SQL filename** | Database dump file to import | From config or `vip-db.sql` | Supports absolute and relative paths; auto-detected from config |
| **Old Domain** | Production domain to search for | From config or prompt | Auto-sanitized (protocols/slashes removed); config override available |
| **New Domain** | Local/staging domain to replace with | From config or prompt | Security validation applied; config override available |
| **Revision cleanup** | Delete all post revisions before search-replace | From config or Optional (Y/n) | High-speed bulk operation using xargs; MySQL commands shown when skipped |
| **All tables** | Include non-WordPress prefixed tables | From config or Recommended (Y/n) | Essential for full migrations; remembers choice in config |
| **Dry-run mode** | Preview changes without applying them | From config or Optional (y/N) | Shows exact operations to be executed; easily toggled in config |
| **Enhanced www/non-www handling** | Automatic detection and conditional processing of www variants | Automatic | Smart 2-4 pass system based on source domain |
| **Multisite mapping** | Per-subsite domain mapping (auto-detected) | Smart prompts with config memory | Remembers mappings, only prompts for new sites |
| **Automatic DB Updates** | wp_blogs and wp_site table updates via wp eval | Automatic for multisite | Executed before search-replace operations |
| **Stage File Proxy Setup** | Interactive setup prompt for media management | From config or Default Yes (Y/n) | Includes automatic plugin installation |
| **Cache clearing** | Flush object cache, rewrites, and transients | Automatic | Network-wide for multisite |

### Complete Process Flow:

1. **� Configuration Discovery & Setup**
   - **Config file detection**: Searches for `wpdb-import.conf` in WordPress root directory
   - **First-time setup**: Interactive prompts with automatic config file creation
   - **Subsequent runs**: Auto-loads settings from config file with override options
   - **Smart defaults**: Pre-fills values from config while allowing runtime overrides

2. **�🔍 Environment Detection**
   - WordPress root directory discovery (works from any subdirectory)
   - Installation type detection via multiple methods (database analysis, wp-config.php, WP-CLI)
   - Multisite configuration analysis (subdomain vs subdirectory)

3. **📦 Database Import Setup**
   - SQL file selection (config-aware with fallback to `vip-db.sql`)
   - Domain mapping configuration (production → local) with config memory
   - Import confirmation with summary display
   - Progress tracking with elapsed time

4. **🗂️ Pre-Processing Operations**
   - High-speed bulk revision cleanup using xargs (config-controlled, site-by-site for multisite)
   - MySQL commands for manual revision cleanup (shown when automatic cleanup is skipped)
   - Table scope selection (`--all-tables` option, remembers config preference)
   - Dry-run mode selection for safe testing (config-configurable)

5. **🔄 Enhanced Domain Replacement Process**
   - **www/non-www Detection**: Automatic detection of source domain type using regex pattern `^www\.`
   - **Smart Pass System**: Conditional execution based on source domain:
     - **Non-www source**: 2 passes (standard + serialized URL replacement)
     - **www source**: 4 passes (non-www standard + www standard + non-www serialized + www serialized)
   - **Single-site**: Enhanced search-replace with conditional www handling
   - **Multisite (subdirectory)**: Network-wide replacement with shared domain
   - **Multisite (subdomain)**: Configuration-aware site mapping with smart prompts
   - **Clean Output**: Dynamic pass numbering with descriptive messages (no confusing skip notifications)

6. **🗺️ Intelligent Multisite Mapping** (Configuration-Enhanced)
   - **Config-aware mapping**: Loads existing site mappings from configuration
   - **Incremental prompts**: Only asks for mappings for new/unmapped sites
   - **Smart defaults**: Suggests intelligent subdirectory mappings based on existing config
   - **Auto-update config**: Saves new mappings back to configuration file
   - **Mapping validation**: Ensures consistency and prevents conflicts

7. **📊 Database Structure Updates** (Multisite)
   - **Automatic Updates**: wp_blogs and wp_site tables updated via wp eval before search-replace
   - **Fallback Commands**: Manual MySQL commands generated only if automatic updates fail
   - **Verification**: Success/failure reporting for each operation

8. **🧹 Post-Processing Cleanup**
   - Object cache flushing
   - Rewrite rules regeneration
   - Transient data cleanup

9. **📸 Stage File Proxy Integration** (Configuration-Aware)
   - **Config-driven setup**: Uses configuration setting to determine if setup is needed
   - **Smart activation**: Detects existing plugin and skips redundant setup
   - **Automatic plugin installation** from GitHub release if not present (multiple fallback methods)
   - **Context-aware activation**: Network-wide for multisite, site-wide for single-site
   - **Mapping-aware configuration**: Uses established domain mappings from import process
   - **HTTPS protocol enforcement**: Security compliance with proper protocol handling
   - **🔒 GitIgnore Protection**: Automatically adds plugin to .gitignore to prevent accidental commits

10. **💾 Configuration Updates & Memory**
    - **Auto-save new mappings**: Any new site mappings are saved to config file
    - **Setting persistence**: User choices are remembered for future runs
    - **Config validation**: Ensures configuration integrity after updates

## 🌟 Supported WordPress Types

- **Single-site installations**
- **Multisite subdomain networks**
- **Multisite subdirectory networks** (including multi-domain to single-domain migrations)

## 🧹 Enhanced Revision Cleanup System

The tool includes a sophisticated revision cleanup system that automatically generates MySQL commands when automatic cleanup is skipped or unavailable.

### Key Features:

✅ **Smart Auto-Detection:**
- Automatically detects single site vs multisite installations
- Uses WP-CLI `wp site list` for robust multisite detection
- Works even when direct database queries fail

✅ **Clean Command Generation:**
- Generates safe DELETE commands
- Individual commands for each subsite in multisite networks
- Clean output format with blog ID labeling

✅ **Flexible Usage:**
- Can be run from any directory with WordPress path parameter
- Integrates seamlessly with main import script
- Available as standalone command: `wp-db-import show-cleanup`
- Conditional display when automatic cleanup is skipped

## Manual MySQL Commands (Fallback Only)

Manual commands are only shown if automatic updates fail:

### Multisite Commands (Subdomain Network):

```sql
-- Update the main network domain
UPDATE wp_site SET domain = 'example.test' WHERE id = 1;

-- Update individual blog domains (each subsite gets unique domain)
UPDATE wp_blogs SET domain = "blog.example.test", path = "/" WHERE blog_id = 2;
UPDATE wp_blogs SET domain = "shop.example.test", path = "/" WHERE blog_id = 3;
UPDATE wp_blogs SET domain = "news.example.test", path = "/" WHERE blog_id = 4;
UPDATE wp_blogs SET domain = "support.example.test", path = "/" WHERE blog_id = 6;
UPDATE wp_blogs SET domain = "docs.example.test", path = "/" WHERE blog_id = 7;
```

### Multisite Commands (Subdirectory Network):

```sql
-- Update the main network domain
UPDATE wp_site SET domain = 'example.test' WHERE id = 1;

-- Update blog domains (shared domain with individual paths)
UPDATE wp_blogs SET domain = "example.test", path = "/" WHERE blog_id = 1;
UPDATE wp_blogs SET domain = "example.test", path = "/blog/" WHERE blog_id = 2;
UPDATE wp_blogs SET domain = "example.test", path = "/shop/" WHERE blog_id = 3;
UPDATE wp_blogs SET domain = "example.test", path = "/news/" WHERE blog_id = 4;
UPDATE wp_blogs SET domain = "example.test", path = "/support/" WHERE blog_id = 6;
UPDATE wp_blogs SET domain = "example.test", path = "/docs/" WHERE blog_id = 7;
```

## 🔧 Additional Functions

### Configuration Management Commands

The tool provides comprehensive configuration management for project-specific settings:

#### Show Unified Configuration Status
Display your current unified configuration settings in a user-friendly format:
```bash
wp-db-import config-show
```
Shows all general settings, site mappings, auto-detection status, and configuration file location.

#### Create Configuration with Site Mappings
Interactively create a new configuration file with guided prompts and site mappings:
```bash
wp-db-import config-create
```
Walks through all settings including site mappings and creates a properly formatted unified config file.

#### Validate Configuration Structure
Check your configuration file for proper structure, format and required settings:
```bash
wp-db-import config-validate
```
Validates INI format, required sections, site mappings, and setting completeness.

#### Edit Configuration
Open your configuration file in your preferred editor:
```bash
wp-db-import config-edit
```
Uses your `$EDITOR` environment variable or defaults to nano.

### Utility Functions

#### Auto-Setup Stage File Proxy
Automatically setup the Stage File Proxy plugin using existing configuration or interactive mapping:
```bash
wp-db-import setup-proxy
```
Auto-detects existing configuration and applies site mappings automatically. Falls back to interactive mode only if no config exists. Configures media proxy settings for both single-site and multisite installations. **Note:** Automatically includes GitIgnore protection to prevent accidental plugin commits.

#### GitIgnore Management
The tool includes comprehensive GitIgnore management for Stage File Proxy plugin:

**Automatic Protection** (included in all setup processes):
- Automatically adds `/plugins/stage-file-proxy/` to `wp-content/.gitignore`
- Prevents accidental commits of local/staging-only plugin to repository
- Works across all Unix-based systems (macOS, Linux, Flywheel)

**Manual GitIgnore Operations** (available via module functions):
```bash
# Load gitignore manager module
source lib/utilities/gitignore_manager.sh

# Add stage-file-proxy to .gitignore
add_stage_file_proxy_to_gitignore

# Check current gitignore status
show_stage_file_proxy_gitignore_status

# Remove from gitignore (if needed)
remove_stage_file_proxy_from_gitignore
```

#### Show Local Site Links
Display clickable links to local WordPress sites:
```bash
wp-db-import show-links
```
**Requirements:** Must be run from within a WordPress directory with WP-CLI installed

#### Show Revision Cleanup Commands
Generate MySQL commands for manual revision cleanup with enhanced auto-detection:
```bash
# Auto-detect WordPress installation and generate commands
wp-db-import show-cleanup

# Use from any directory with WordPress path
wp-db-import show-cleanup /path/to/wordpress
```
Provides safe DELETE commands for manual revision cleanup when automatic cleanup is unavailable.

### System Management

#### Version Management
Check current version and update information:
```bash
# Show version and git information
wp-db-import version

# Update to latest version (git installations only)
wp-db-import update
```

#### Help System
Get comprehensive help and usage information:
```bash
wp-db-import --help
```
Shows all available commands, setup instructions, and usage examples.

## 🛡️ Security Features

- Uses absolute paths to prevent directory traversal
- Validates all user inputs
- Sanitizes domain inputs
- Uses temporary files with process-specific names
- Prevents SQL injection in generated commands

## 📁 Project Structure

### Core Files
- **`wp-db-import`** - Global command executable with comprehensive subcommand support
- **`import_wp_db.sh`** - Main database import and domain replacement script with config integration
- **`install.sh`** - User-local installation script with symlink management
- **`uninstall.sh`** - Clean removal script with complete cleanup
- **`VERSION`** - Centralized version management file with semantic versioning

### Configuration System
- **`wpdb-import-example-single.conf`** - Single-site configuration template with comprehensive settings
- **`wpdb-import-example-multisite.conf`** - Multisite configuration template with site mapping examples
- **`USAGE.md`** - Complete configuration setup guide with practical examples and workflows

### Modular Library Architecture
```bash
lib/
├── version.sh                 # Version management utilities and git integration
├── module_loader.sh           # Automatic module discovery and loading system
├── core/                      # Core functionality modules
│   ├── utils.sh               # Utility functions, domain sanitization, file operations
│   ├── validation.sh          # Validation helpers and test hooks
│   └── wp_detection.sh        # WordPress installation detection helpers
├── config/                    # Configuration management system
│   ├── config_manager.sh      # Config file operations, parsing, creation
│   ├── config_reader.sh       # Unified config reader utilities
│   └── integration.sh         # Config integration with import flow and prompts
├── database/                  # Database operation modules
│   └── search_replace.sh      # Advanced search-replace with multisite support
└── utilities/                 # Standalone utility modules
   ├── site_links.sh           # Show local site links with clickable URLs
   ├── stage_file_proxy.sh     # Media proxy setup with automatic plugin management
   └── revision_cleanup.sh     # Revision cleanup commands with multisite detection
```

### Configuration Features
- **📋 INI-style Configuration**: Standard format with `[general]` and `[site_mappings]` sections
- **🔄 Auto-Discovery**: Searches WordPress root directory for project-specific configs
- **💾 Auto-Save**: Remembers user choices and site mappings for subsequent runs
- **🧠 Smart Prompts**: Only asks for missing information, shows existing values
- **✅ Validation**: Comprehensive config file format and content validation
- **🔧 Management Commands**: Create, show, edit, and validate configuration files

### Runtime Behavior
- **📝 Temporary Files**: Creates process-specific log files in `/tmp/` (PID-based collision prevention)
- **🧹 Auto-Cleanup**: Automatically removes temporary files on exit
- **📊 Operation Logging**: Comprehensive logging of all WP-CLI operations for troubleshooting
- **🔗 Symlink Installation**: Enables instant updates without reinstallation
- **⚡ Configuration Caching**: Loads and caches config settings for improved performance

### Development Structure
- **🛠️ Modular Design**: Clean separation of concerns with dedicated modules
- **📦 Auto-Loading**: Dynamic module loading based on functionality needs
- **🔌 Plugin Architecture**: Easy extension with new utility modules
- **📋 Configuration API**: Consistent interface for config operations across modules
- **🧪 Error Handling**: Comprehensive error handling and graceful degradation

### GitIgnore Protection System
- **🔒 Automatic Integration**: All stage-file-proxy setups include automatic .gitignore protection
- **🌍 Cross-Platform**: Works reliably across macOS, Linux, and Flywheel hosting environments
- **🛡️ Repository Safety**: Prevents accidental commits of local/staging-only plugins
- **📁 Smart Detection**: Auto-detects WordPress root directory and wp-content location
- **🔧 Manual Control**: Standalone functions available for advanced gitignore management
- **✅ Validation**: Comprehensive permission and file existence checking
- **📋 Status Reporting**: Clear feedback about gitignore operations and current status

## Log Analysis:

```bash
# Check recent error logs
tail -100 /tmp/wp_*_$$.log | grep -i error

# Monitor WordPress debug logs
tail -f wp-content/debug.log | grep -E "(FATAL|ERROR|WARNING)"
```

### Manual Logs Cleanup Commands:

```bash
# Remove all logs for current process
rm -f /tmp/wp_*_$$.log /tmp/wp_*_$$.csv

# Remove all WordPress tool logs (all processes)
rm -f /tmp/wp_*_*.log /tmp/wp_*_*.csv

# Find and remove old logs (older than 1 day)
find /tmp -name "wp_*_*.log" -mtime +1 -delete
find /tmp -name "wp_*_*.csv" -mtime +1 -delete

# Clean up WP-CLI cache files
find /tmp -type f -name "wp-cli-*" -mtime +1 -delete 2>/dev/null
```

## 📚 Documentation

For additional documentation, see:

- **[Bash Compatibility Guide](docs/BASH_COMPATIBILITY.md)** - Cross-version bash support and compatibility features
- **[Usage Guide](USAGE.md)** - Comprehensive usage examples and workflows
- **[Usage Example Output](docs/USAGE_EXAMPLE.md)** - Example demo outputs
- **[Installation Methods](docs/INSTALLATION_METHODS.md)** - Detailed installation options and troubleshooting
- **[Version Management](docs/VERSION_MANAGEMENT.md)** - Version control and update procedures

## 🤝 Contributing

Found a bug or have a feature request? [Open an issue](https://github.com/manishsongirkar/wp-db-import-and-domain-replacement-tool/issues) or check our [Contribution Guidelines](CONTRIBUTING.md).

## 📄 License

This project is licensed under the MIT License.

## 👨‍💻 Author

**Manish Songirkar** ([@manishsongirkar](https://github.com/manishsongirkar))
