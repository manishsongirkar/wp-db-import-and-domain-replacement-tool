# WordPress Database Import & Domain Replacement Tool

A robust command-line tool for WordPress database imports and domain/URL replacements, perfect for migrating environments.

## 🚀 Quick Installation

```bash
# 1. Clone the repository
git clone https://github.com/manishsongirkar/wp-db-import-and-domain-replacement-tool.git

# 2. Install globally (creates symlink in ~/.local/bin)
cd wp-db-import-and-domain-replacement-tool
./install.sh

# 3. Use from anywhere!
cd ~/Local\ Sites/mysite/app/public
wp-db-import
```

## 📋 Usage

### Main Commands
```bash
wp-db-import                    # Main import wizard
wp-db-import config-show        # Show current configuration
wp-db-import config-create      # Create new configuration file
wp-db-import config-validate    # Validate configuration file
wp-db-import config-edit        # Open configuration in editor
wp-db-import show-links         # Show local site links
wp-db-import setup-proxy        # Setup stage file proxy
wp-db-import show-cleanup       # Generate revision cleanup commands
wp-db-import update             # Update to latest version
wp-db-import version            # Show version info
wp-db-import --help             # Show help
```

💡 **Tab Completion**: Type `wp-db-import ` and press TAB to see all available commands!

### Example Workflow
```bash
# Navigate to WordPress directory
cd ~/Local\ Sites/mysite/app/public

# Place your SQL file in the directory
cp ~/Downloads/production-db.sql ./

# Run the import wizard
wp-db-import
```

## 📋 Configuration System

### First-Time Setup
When you run `wp-db-import` for the first time in a project, it will:
1. Prompt for SQL file, old domain, and new domain
2. Create a `wpdb-import.conf` file in your WordPress root
3. For multisite, prompt for individual site mappings
4. Save all settings for future use

### Subsequent Runs
On subsequent runs, the tool will:
1. Load settings from the config file automatically
2. Only prompt for new sites not yet mapped
3. Update the config file with any new mappings

### Configuration Management
```bash
# View current configuration
wp-db-import config-show

# Create/recreate configuration file
wp-db-import config-create

# Validate configuration format
wp-db-import config-validate

# Edit configuration file
wp-db-import config-edit
```

### Example Configuration File
The `wpdb-import.conf` file is created in your WordPress root:
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

### 📁 Configuration Examples

The project includes example configuration files you can copy and customize:

#### 🌐 Single Site Example
**File**: `wpdb-import-example-single.conf`
- For standard WordPress installations
- Simple domain replacement setup
- Includes all common settings with explanations

#### 🗂️ Multisite Example
**File**: `wpdb-import-example-multisite.conf`
- For WordPress Multisite installations
- Includes site mapping examples
- Shows both subdirectory and subdomain patterns

#### 🚀 Quick Setup Guide

1. **Choose your example**: Copy the appropriate file for your setup
2. **Rename**: Copy to your WordPress root as `wpdb-import.conf`
3. **Customize**: Edit the settings for your specific project
4. **Run**: Use `wp-db-import` - it will automatically use your config

```bash
# For single site
cp wpdb-import-example-single.conf ~/path/to/wordpress/wpdb-import.conf

# For multisite
cp wpdb-import-example-multisite.conf ~/path/to/wordpress/wpdb-import.conf

# Edit the config
nano ~/path/to/wordpress/wpdb-import.conf

# Run the import
cd ~/path/to/wordpress && wp-db-import
```

#### ⚙️ Configuration Options Reference

| Option | Description | Values |
|--------|-------------|--------|
| `sql_file` | Database file to import | Filename or path |
| `old_domain` | Production domain to replace | Domain without protocol |
| `new_domain` | Local domain to use | Domain without protocol |
| `all_tables` | Include all database tables | `true` / `false` |
| `dry_run` | Preview mode (no changes) | `true` / `false` |
| `clear_revisions` | Remove post revisions first | `true` / `false` |
| `setup_stage_proxy` | Configure media proxy | `true` / `false` |
| `auto_proceed` | Skip confirmations | `true` / `false` |

#### 💡 Configuration Tips

- **Start Conservative**: Use `auto_proceed=false` until you're confident
- **Test First**: Use `dry_run=true` for initial testing
- **Version Control**: Add config files to your project's `.gitignore`
- **Team Sharing**: Share config templates with your development team

## 🔄 Auto-Updates

**Updates work automatically!** The installation creates a symlink to the repository, so:

### Method 1: Automatic Update Command
```bash
wp-db-import update
```

### Method 2: Manual Git Pull
```bash
cd ~/path/to/wp-db-import-and-domain-replacement-tool
git pull
# Changes are immediately available globally!
```

## ✨ Features

- **🚀 User Local Installation** - Installs to user directory only
- **🔗 Symlinked installation** - Updates apply immediately
- **⌨️ Tab Completion** - Auto-complete commands with TAB key
- **🌐 Multisite support** - Handles subdomain & subdirectory networks
- **🗑️ Bulk revision cleanup** - High-speed cleanup via xargs
- **📸 Stage File Proxy** - Media management between environments
- **🔄 Smart domain replacement** - Handles serialized data & www variants
- **💻 Terminal-friendly** - Colored output with progress indicators

## 🛠️ Requirements

- WP-CLI installed and in PATH
- WordPress installation (wp-config.php present)
- MySQL/MariaDB database access
- Bash shell (macOS/Linux)

## 🗑️ Uninstallation

```bash
# From the repository directory
./uninstall.sh
```

## 🔧 Development

### File Structure
```
wp-db-import-and-domain-replacement-tool/
├── wp-db-import              # Main executable (global command)
├── import_wp_db.sh           # Core import functionality
├── install.sh                # Installation script
├── uninstall.sh              # Clean removal
├── VERSION                   # Version file
└── lib/
    ├── module_loader.sh      # Module loading system
    ├── version.sh            # Version management script
    ├── core/                 # Core utilities
    └── utilities/            # Modular utility functions
        ├── site_links.sh     # Local site link display
        ├── stage_file_proxy.sh # Media proxy setup
        └── revision_cleanup.sh # Cleanup commands
```

### Backward Compatibility
The original sourcing method still works:
```bash
source ~/wp-db-import-and-domain-replacement-tool/import_wp_db.sh
import_wp_db
```

---
