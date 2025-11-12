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
wp-db-import show-links         # Show local site links
wp-db-import setup-proxy        # Setup stage file proxy
wp-db-import show-cleanup       # Generate revision cleanup commands
wp-db-import update             # Update to latest version
wp-db-import version            # Show version info
wp-db-import --help             # Show help
```

### Example Workflow
```bash
# Navigate to WordPress directory
cd ~/Local\ Sites/mysite/app/public

# Place your SQL file in the directory
cp ~/Downloads/production-db.sql ./

# Run the import wizard
wp-db-import
```

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
