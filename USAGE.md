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
wp-db-import config-show        # Show unified configuration status
wp-db-import config-create      # Create configuration with site mappings
wp-db-import config-validate    # Validate configuration structure
wp-db-import config-edit        # Open configuration in editor
wp-db-import show-links         # Show local site links
wp-db-import setup-proxy        # Auto-setup Stage File Proxy (uses config)
wp-db-import show-cleanup       # Show revision cleanup commands
wp-db-import update             # Update to latest version
wp-db-import version            # Show version and git info
wp-db-import test               # Run test suite to validate tool functionality
wp-db-import --help             # Show this help message
```

💡 **Tab Completion**: Type `wp-db-import ` and press TAB to see all available commands!

> **Note:** Autocomplete suggestions are automatically updated when you run `./install.sh`.

### Example Workflow
```bash
cd ~/Local\ Sites/mysite/app/public
cp ~/Downloads/production-db.sql ./
wp-db-import
```

## 🗂️ Configuration System

- First run prompts for SQL file, domains, and creates `wpdb-import.conf`
- Multisite: prompts for site mappings, saves all settings
- Subsequent runs auto-load config, only prompt for new sites
- Config management via `config-show`, `config-create`, `config-validate`, `config-edit`

### Example Configuration File
```ini
[general]
sql_file=vip-db.sql
old_domain=production-site.com
new_domain=local-site.test
all_tables=true
dry_run=false
clear_revisions=true
setup_stage_proxy=true
auto_proceed=false

[site_mappings]
1:production-site.com:local-site.test
2:blog.production-site.com:local-site.test/blog
3:shop.production-site.com:local-site.test/shop
```

### Example Setup
```bash
cp wpdb-import-example-single.conf ~/path/to/wordpress/wpdb-import.conf
nano ~/path/to/wordpress/wpdb-import.conf
wp-db-import
```

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
├── USAGE.md                            # Usage guide
├── CONTRIBUTING.md                     # Contributor guidelines
├── LICENSE                             # License file
├── lib/
│   ├── module_loader.sh                # Module loader
│   ├── version.sh                      # Version management
│   ├── completion/                     # Autocomplete scripts
│   ├── config/                         # Config management modules
│   ├── core/                           # Core utilities
│   ├── database/                       # Database utilities
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
