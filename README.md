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

### 📋 Available Commands
```bash
# Run main interactive import wizard
wp-db-import

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

[site_mappings]
# Format: blog_id:old_domain:new_domain
1:admin.example.com:example.test
2:blog.example.com:example.test/blog
3:shop.example.com:example.test/shop
4:news.example.com:example.test/news
5:support.example.com:example.test/support
6:docs.example.com:example.test/docs
```

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
UPDATE wp_blogs SET domain = "example.test", path = "/" WHERE blog_id = 1;      -- Main site
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
