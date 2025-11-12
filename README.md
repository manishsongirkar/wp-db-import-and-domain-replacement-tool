# 🧩 WordPress Database Import & Domain Replacement Tool

A robust bash utility for performing WordPress database imports and domain/URL replacements, commonly needed for migrating environments (e.g., production to local/staging). It efficiently handles single-site and multi-domain WordPress Multisite setups.

## ✨ Features

- � **Global Command Access** - Available anywhere after installation with `wp-db-import`
- �🔄 **Automatic WordPress installation detection** (single-site or multisite)
- ⚡ **High-Speed Bulk Post Revision Cleanup** (via WP-CLI)
- 🧹 **Smart MySQL Commands for Manual Revision Cleanup** (when automatic cleanup is skipped)
  - ✅ **Auto-detects multisite** using WP-CLI site functions
  - ✅ **Generates clean commands** without problematic OPTIMIZE TABLE statements
  - ✅ **Works from any directory** with WordPress path detection
- 🔄 **Auto-Update System** - Git-based installations update with `wp-db-import update`
- 🛠️ **Modular Architecture** - Clean separation of utilities and core functions
- 🔗 **Clickable Site Links** - Terminal links to quickly access local sites
- 🧹 **Intelligent domain sanitization** (removes protocols, trailing slashes)
- 🌐 **Robust Multi-Domain/Per-Site Mapping** for Multisite
- 🔁 **Enhanced search-replace** (2-4 passes based on source domain type)
- 🗑️ **Cache and transient clearing** via WP-CLI
- 🧪 **Dry-run mode** for testing replacements
- 📦 **MySQL command generation** for network domain tables
- 🛡️ **Comprehensive error handling** and logging
- 🎨 **Colored terminal output** with clear progress indicators
- 📸 **Stage File Proxy Plugin** automatic installation and configuration
- 📦 **User-Local Installation** - Installs to ~/.local/bin
- 📋 **Centralized Version Management** - Single VERSION file with automated tracking

## 🧰 Requirements

| Requirement | Description | Version Notes |
|--------------|-------------|---------------|
| **Operating System** | macOS/Linux environment with Bash shell | Bash 4.0+ recommended |
| **WP-CLI** | WordPress Command Line Interface | Latest stable version |
| **WordPress** | WordPress installation with wp-config.php | Single-site or multisite |
| **Database** | MySQL/MariaDB database with import privileges | 5.7+ or 10.2+ |
| **PHP** | PHP runtime for WP-CLI operations | 7.4+ recommended |
| **File System** | Read/write access to WordPress directory | Sufficient disk space for import |

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
# Main database import wizard
wp-db-import

# Show local site links
wp-db-import show-links

# Setup stage file proxy
wp-db-import setup-proxy

# Show revision cleanup commands
wp-db-import show-cleanup

# Update to latest version (git only)
wp-db-import update

# Show version info
wp-db-import version

# Get help
wp-db-import --help
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

| Option | Description | Default | Advanced Notes |
| -------- | ----------- | ------- | -------------- |
| **SQL filename** | Database dump file to import | `vip-db.sql` | Supports absolute and relative paths |
| **Old Domain** | Production domain to search for | Required input | Auto-sanitized (protocols/slashes removed) |
| **New Domain** | Local/staging domain to replace with | Required input | Security validation applied |
| **Revision cleanup** | Delete all post revisions before search-replace | Optional (Y/n) | High-speed bulk operation using xargs; MySQL commands shown when skipped |
| **All tables** | Include non-WordPress prefixed tables | Recommended (Y/n) | Essential for full migrations |
| **Dry-run mode** | Preview changes without applying them | Optional (y/N) | Shows exact operations to be executed |
| **Enhanced www/non-www handling** | Automatic detection and conditional processing of www variants | Automatic | Smart 2-4 pass system based on source domain |
| **Multisite mapping** | Per-subsite domain mapping (auto-detected) | Interactive prompts | Supports both subdomain and subdirectory |
| **Automatic DB Updates** | wp_blogs and wp_site table updates via wp eval | Automatic for multisite | Executed before search-replace operations |
| **Stage File Proxy Setup** | Interactive setup prompt for media management | Default Yes (Y/n) | Includes automatic plugin installation |
| **Cache clearing** | Flush object cache, rewrites, and transients | Automatic | Network-wide for multisite |

### Complete Process Flow:

1. **🔍 Environment Detection**
   - WordPress root directory discovery (works from any subdirectory)
   - Installation type detection via multiple methods (database analysis, wp-config.php, WP-CLI)
   - Multisite configuration analysis (subdomain vs subdirectory)

2. **📦 Database Import Setup**
   - SQL file selection (default: `vip-db.sql`)
   - Domain mapping configuration (production → local)
   - Import confirmation with summary display
   - Progress tracking with elapsed time

3. **🗂️ Pre-Processing Operations**
   - High-speed bulk revision cleanup using xargs (optional, site-by-site for multisite)
   - MySQL commands for manual revision cleanup (shown when automatic cleanup is skipped)
   - Table scope selection (`--all-tables` option)
   - Dry-run mode selection for safe testing

4. **🔄 Enhanced Domain Replacement Process**
   - **www/non-www Detection**: Automatic detection of source domain type using regex pattern `^www\.`
   - **Smart Pass System**: Conditional execution based on source domain:
     - **Non-www source**: 2 passes (standard + serialized URL replacement)
     - **www source**: 4 passes (non-www standard + www standard + non-www serialized + www serialized)
   - **Single-site**: Enhanced search-replace with conditional www handling
   - **Multisite (subdirectory)**: Network-wide replacement with shared domain
   - **Multisite (subdomain)**: Individual site mapping with custom domains and automatic database updates
   - **Clean Output**: Dynamic pass numbering with descriptive messages (no confusing skip notifications)

5. **� Database Structure Updates** (Multisite)
   - **Automatic Updates**: wp_blogs and wp_site tables updated via wp eval before search-replace
   - **Fallback Commands**: Manual MySQL commands generated only if automatic updates fail
   - **Verification**: Success/failure reporting for each operation

6. **🧹 Post-Processing Cleanup**
   - Object cache flushing
   - Rewrite rules regeneration
   - Transient data cleanup

7. **📁 Stage File Proxy Integration**
   - **Interactive setup prompt** with default "Yes" option
   - **Automatic plugin installation** from GitHub release if not present (multiple fallback methods)
   - **Smart plugin activation** (network-wide for multisite, site-wide for single-site)
   - **Source domain configuration** using existing mappings from import process
   - **HTTPS protocol enforcement** for security compliance

## 📖 Usage Examples

### Single Site Example

**Terminal Input/Output:**
```
$ wp-db-import

🔧 WordPress Database Import & Domain Replace Tool
---------------------------------------------------

📦 Enter SQL file name (default: vip-db.sql): production-database.sql
✅ WordPress root found: /Users/john/Sites/example-site/app/public

✅ Found SQL file: production-database.sql

🌍 Enter the OLD (production) domain to search for: https://www.example.com/
🏠 Enter the NEW (local) domain/base URL to replace with: https://example.test/

🧹 Cleaned search domain: 'https://www.example.com/' → 'www.example.com'
🧹 Cleaned replace domain: 'https://example.test/' → 'example.test'
🧾 Summary:
    🔍 Search for:   www.example.com
    🔄 Replace with: example.test

Proceed with database import? (Y/n): y

⏳ Importing database...
[2] 456
  Importing / (00:14)[2]  + 456 done       /bin/sh -c
✅ Database import successful! [Completed in 00:14]

🔍 Checking WordPress installation type...
✅ Single site installation detected

Clear ALL post revisions? (improves search-replace speed) (Y/n): y
🗑️ Clearing ALL Post Revisions...
✅ Revisions deleted successfully

Include --all-tables (recommended for full DB imports)? (Y/n): y
✅ Will include all tables.

Run in dry-run mode (no data will be changed)? (y/N): n
🚀 Running in live mode (changes will be applied).

🔄 SEARCH-REPLACE OPERATIONS
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

🌍 Single Site Processing:
   From: www.example.com
   To:   example.test

   Step 1: ✅ Standard URL replacement complete
   Step 2: ✅ Serialized data replacement complete

🧹 Flushing WordPress and WP-CLI caches & transients...
  ✅ Object cache flushed.

📸 Stage File Proxy Setup
Do you want to setup the stage file proxy plugin? (Y/n): y
✅ Plugin activated successfully
✅ Configured: example.test → https://www.example.com

================================================================
🌐 LOCAL SITE ACCESS LINKS
================================================================

✅ Your WordPress Single Site is ready:

  🏠 Frontend: http://example.test
  ⚙️  Admin:    http://example.test/wp-admin

================================================================
```

### Multisite Example

**Terminal Input/Output:**
```
$ wp-db-import

🔧 WordPress Database Import & Domain Replace Tool
---------------------------------------------------

📦 Enter SQL file name (default: vip-db.sql): multisite-production.sql
✅ WordPress root found: /Users/john/Sites/example-multisite/app/public

✅ Found SQL file: multisite-production.sql

🌍 Enter the OLD (production) domain to search for: https://admin.example.com/
🏠 Enter the NEW (local) domain/base URL to replace with: https://example.test/

🧹 Cleaned search domain: 'https://admin.example.com/' → 'admin.example.com'
🧹 Cleaned replace domain: 'https://example.test/' → 'example.test'
🧾 Summary:
    🔍 Search for:   admin.example.com
    🔄 Replace with: example.test

Proceed with database import? (Y/n): y

⏳ Importing database...
✅ Database import successful!

🔍 Checking WordPress installation type...
✅ Multisite detected via wp-config.php constants

Clear ALL post revisions? (Y/n): y
🗑️ Clearing ALL Post Revisions...
✅ All revisions deleted across 6 sites

Include --all-tables? (Y/n): y
✅ Will include all tables.

Run in dry-run mode? (y/N): n
🚀 Running in live mode.

🌐 Multisite (subdomain) detected — gathering subsites for mapping...

✅ Found 6 subsites:
blog_id  domain                         path
1        admin.example.com              /
2        shop.example.com               /
3        blog.example.com               /
4        news.example.com               /
6        support.example.com            /
7        docs.example.com               /

🌐 Individual domain mapping required for subdomain multisite:

  ┌─ Processing Site  1 ─────────────────────────────────────────
  │ Domain: admin.example.com
  │ Path:   /
  │ Enter local URL for Main Site (default: example.test): example.test
  └──────────────────────────────────────────────────────────────
  ✅ Mapping confirmed:
     admin.example.com → example.test
     (Blog ID: 1, Path: /)

  ┌─ Processing Site  2 ─────────────────────────────────────────
  │ Domain: shop.example.com
  │ Path:   /
  │ Enter local URL for Blog ID 2: example.test/shop
  └──────────────────────────────────────────────────────────────
  ✅ Mapping confirmed:
     shop.example.com → example.test/shop
     (Blog ID: 2, Path: /)

  ┌─ Processing Site  3 ─────────────────────────────────────────
  │ Domain: blog.example.com
  │ Path:   /
  │ Enter local URL for Blog ID 3: example.test/blog
  └──────────────────────────────────────────────────────────────
  ✅ Mapping confirmed:
     blog.example.com → example.test/blog
     (Blog ID: 3, Path: /)

🧾 Domain mapping summary:
    🔁 [ID: 1] admin.example.com/ → example.test
    🔁 [ID: 2] shop.example.com/ → example.test/shop
    🔁 [ID: 3] blog.example.com/ → example.test/blog
    🔁 [ID: 4] news.example.com/ → example.test/news
    🔁 [ID: 6] support.example.com/ → example.test/support
    🔁 [ID: 7] docs.example.com/ → example.test/docs

⚡ Updating wp_blogs and wp_site tables...
✅ Database tables wp_blogs & wp_site updated successfully!

� SEARCH-REPLACE OPERATIONS
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

🌍 Site 2 Processing:
   From: shop.example.com
   To:   example.test/shop

   Step 1: ✅ Standard URL replacement complete
   Step 2: ✅ Serialized data replacement complete

🌍 Site 3 Processing:
   From: blog.example.com
   To:   example.test/blog

   Step 1: ✅ Standard URL replacement complete
   Step 2: ✅ Serialized data replacement complete

🌍 Site 4 Processing:
   From: news.example.com
   To:   example.test/news

   Step 1: ✅ Standard URL replacement complete
   Step 2: ✅ Serialized data replacement complete

🌍 Site 6 Processing:
   From: support.example.com
   To:   example.test/support

   Step 1: ✅ Standard URL replacement complete
   Step 2: ✅ Serialized data replacement complete

🌍 Site 7 Processing:
   From: docs.example.com
   To:   example.test/docs

   Step 1: ✅ Standard URL replacement complete
   Step 2: ✅ Serialized data replacement complete

🏠 Main Site Processing:
   From: admin.example.com
   To:   example.test

   Step 1: ✅ Standard URL replacement complete
   Step 2: ✅ Serialized data replacement complete

🧹 Flushing WordPress and WP-CLI caches & transients...
  ✅ Object cache flushed.

📸 Stage File Proxy Setup
Do you want to setup the stage file proxy plugin? (Y/n): y
✅ Plugin activated successfully
🌐 Configuring multisite stage-file-proxy...
  ✅ Configured: example.test → https://admin.example.com
  ✅ Configured: example.test/shop → https://shop.example.com
  ✅ Configured: example.test/blog → https://blog.example.com
  ✅ Configured: example.test/news → https://news.example.com
  ✅ Configured: example.test/support → https://support.example.com
  ✅ Configured: example.test/docs → https://docs.example.com

================================================================
🌐 LOCAL SITE ACCESS LINKS
================================================================

✅ Your WordPress Multisite is ready:

  🏠 Main Site (ID: 1): https://example.test
  🌍 Subsite   (ID: 2): https://example.test/shop
  🌍 Subsite   (ID: 3): https://example.test/blog
  🌍 Subsite   (ID: 4): https://example.test/news
  🌍 Subsite   (ID: 6): https://example.test/support
  🌍 Subsite   (ID: 7): https://example.test/docs

💡 Network Admin: Add /wp-admin/network/ to any of the above URLs

================================================================
```

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

### Manual Setup Stage File Proxy
Setup the Stage File Proxy plugin, follow the interactive prompts for domain mapping.

```bash
wp-db-import setup-proxy
```

### Show Local Site Links
Display clickable links to local WordPress sites:

```bash
wp-db-import show-links
```

**Requirements:** Must be run from within a WordPress directory with WP-CLI installed

### Show Revision Cleanup Commands
Generate MySQL commands for manual revision cleanup with enhanced auto-detection:

```bash
# Auto-detect WordPress installation and generate commands
wp-db-import show-cleanup

# Use from any directory with WordPress path
wp-db-import show-cleanup /path/to/wordpress
```

### Version Management
Check current version and update information:

```bash
# Show version and git information
wp-db-import version

# Update to latest version (git installations only)
wp-db-import update
```

## 🛡️ Security Features

- Uses absolute paths to prevent directory traversal
- Validates all user inputs
- Sanitizes domain inputs
- Uses temporary files with process-specific names
- Prevents SQL injection in generated commands

## 📁 Project Structure

### Core Files
- `wp-db-import` - Global command executable with subcommands
- `import_wp_db.sh` - Main database import and domain replacement script
- `install.sh` - User-local installation script
- `uninstall.sh` - Clean removal script
- `VERSION` - Centralized version management file

### Library Structure
```
lib/
├── version.sh              # Version management utilities
├── module_loader.sh        # Automatic module loading system
├── core/                   # Core functionality modules
│   ├── utils.sh           # Utility functions
│   ├── environment.sh     # Environment detection
│   ├── error_handler.sh   # Error handling
│   ├── logger.sh          # Logging utilities
│   └── orchestrator.sh    # Main orchestration
└── utilities/             # Standalone utility modules
    ├── site_links.sh      # Show local site links
    ├── stage_file_proxy.sh # Media proxy setup
    └── revision_cleanup.sh # Revision cleanup commands
```

### Runtime Behavior
- Creates temporary log files in `/tmp/` for debugging (uses PID to prevent collision)
- Automatically cleans up temporary files on exit
- Logs all WP-CLI operations for troubleshooting
- Symlink-based installation for instant updates

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

For additional documentation, see the `docs/` directory:

- **[Installation Methods](docs/INSTALLATION_METHODS.md)** - Detailed installation options and troubleshooting
- **[Version Management](docs/VERSION_MANAGEMENT.md)** - Version control and update procedures
- **[Usage Guide](USAGE.md)** - Comprehensive usage examples and workflows

## 🤝 Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## 📄 License

This project is licensed under the MIT License.

## 👨‍💻 Author

**Manish Songirkar** ([@manishsongirkar](https://github.com/manishsongirkar))
