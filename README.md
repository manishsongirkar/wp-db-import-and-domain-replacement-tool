# 🧩 WordPress Database Import & Domain Replacement Tool

A comprehensive **interactive Bash toolkit** that automates importing WordPress database dumps (`.sql` files), performs **intelligent domain replacements**, handles **complex multisite setups**, and provides **stage-file-proxy integration** — all with sophisticated error handling, progress tracking, and detailed logging.

---

## 🚀 Features

### Core Functionality
- ✅ **Automatic WordPress installation detection** (single-site or multisite subdomain/subdirectory)
- ✅ **Enhanced domain sanitization** with security validation and protocol handling
- ✅ **Interactive domain mapping** with per-subsite configuration for multisite
- ✅ **Dual-pass search-replace** (standard URLs + serialized data structures)
- ✅ **Enhanced domain+path replacement** for complex multisite configurations with intelligent slash handling
- ✅ **Intelligent post revision cleanup** with site-by-site processing
- ✅ **Comprehensive cache clearing** (object cache, rewrites, transients)
- ✅ **Advanced dry-run mode** for safe testing and validation
- ✅ **MySQL command generation** with automatic blog_id and path detection
- ✅ **Integrated Stage File Proxy setup** with automatic activation and configuration

### Technical Features
- ✅ **Smart WordPress root detection** (works from any subdirectory)
- ✅ **Process-safe temporary files** with automatic cleanup on exit
- ✅ **Enhanced error handling** with detailed logging and recovery options
- ✅ **Progress indicators** with elapsed time tracking and spinners
- ✅ **Multi-site type support** (subdomain networks, subdirectory networks)
- ✅ **Input validation** with dangerous character detection and sanitization
- ✅ **Modern plugin support** for Stage File Proxy
- ✅ **Network-wide operations** with site-specific processing
- ✅ **Protocol enforcement** (automatic HTTPS for stage-file-proxy)

### User Experience
- ✅ **Color-coded terminal output** with status indicators and progress bars
- ✅ **Interactive prompts** with smart defaults and validation
- ✅ **Comprehensive help documentation** with usage examples
- ✅ **Step-by-step guidance** with clear confirmation points
- ✅ **Detailed summary reports** showing all changes made

---

## 🧰 Requirements

| Requirement | Description | Version Notes |
|--------------|-------------|---------------|
| **Operating System** | macOS/Linux environment with Bash shell | Bash 4.0+ recommended |
| **WP-CLI** | WordPress Command Line Interface | Latest stable version |
| **WordPress** | WordPress installation with wp-config.php | Single-site or multisite |
| **Database** | MySQL/MariaDB database with import privileges | 5.7+ or 10.2+ |
| **PHP** | PHP runtime for WP-CLI operations | 7.4+ recommended |
| **File System** | Read/write access to WordPress directory | Sufficient disk space for import |

### Environment Validation Commands
```bash
# Check WP-CLI installation and version
wp --info

# Verify database connectivity
wp db check

# Test PHP version
php --version

# Confirm WordPress installation
wp core version

# Validate database permissions
wp db query "SELECT 1 as test;"
```

---

## 📦 Installation

Follow these steps to install the `import_wp_db` tool globally on your system.

### 1️⃣ Clone the repository

Clone this repository into your **main user directory**, where your `.bashrc` or `.zshrc` file is located:

```bash
cd ~
git clone https://github.com/manishsongirkar/wp-db-import-and-domain-replacement-tool.git
```

### 2️⃣ Update your shell configuration

Edit your shell configuration file (`.bashrc` or `.zshrc`) and add the following lines:

```bash
# Import WordPress Database Tool
# Check if the file exists before sourcing to prevent errors
if [ -f "$HOME/wp-db-import-and-domain-replacement-tool/import_wp_db.sh" ]; then
    source "$HOME/wp-db-import-and-domain-replacement-tool/import_wp_db.sh"
fi

# if [ -f "$HOME/wp-db-import-and-domain-replacement-tool/setup-stage-file-proxy.sh" ]; then
#     source "$HOME/wp-db-import-and-domain-replacement-tool/setup-stage-file-proxy.sh"
# fi
```

### 3️⃣ Apply changes

Reload your shell configuration:

```bash
source ~/.bashrc
# or
source ~/.zshrc
```

### 4️⃣ Verify installation

Run this to confirm the function is available:

```bash
type import_wp_db
```

Expected output:

```
import_wp_db is a function
```

---

## 🧩 Usage

Once installed, navigate to your WordPress project directory (where `wp-config.php` exists) and run:

```bash
import_wp_db
```

### Complete Process Flow:

1. **🔍 Environment Detection**
   - WordPress root directory discovery
   - Installation type detection (single-site vs multisite)
   - Multisite configuration analysis (subdomain vs subdirectory)

2. **📦 Database Import Setup**
   - SQL file selection (default: `vip-db.sql`)
   - Domain mapping configuration (production → local)
   - Import confirmation with summary display

3. **🗂️ Pre-Processing Operations**
   - Revision cleanup (optional, site-by-site for multisite)
   - Table scope selection (`--all-tables` option)
   - Dry-run mode selection for safe testing

4. **🔄 Domain Replacement Process**
   - **Single-site**: Direct search-replace with dual-pass processing
   - **Multisite (subdirectory)**: Network-wide replacement with shared domain
   - **Multisite (subdomain)**: Individual site mapping with custom domains

5. **🧹 Post-Processing Cleanup**
   - Object cache flushing
   - Rewrite rules regeneration
   - Transient data cleanup

6. **🛠️ Database Structure Updates** (Multisite only)
   - Automatic MySQL command generation
   - Blog domain and path updates
   - User confirmation for phpMyAdmin execution

7. **📁 Stage File Proxy Integration**
   - **Interactive setup prompt** with default "Yes" option
   - **Automatic plugin installation** from GitHub release if not present
   - **Smart plugin activation** (network-wide for multisite, site-wide for single-site)
   - **Source domain configuration** using existing mappings from import process
   - **HTTPS protocol enforcement** for security compliance

---

## 🔄 Stage File Proxy Integration

The script provides sophisticated **Stage File Proxy** integration for seamless local development workflows. This feature **automatically installs and configures** your local WordPress installation to fetch missing media files from the production server.

### How It Works

1. **🔍 Interactive Setup Prompt**: After completing database operations, prompts user with clear options
2. **📦 Automatic Plugin Installation**: If stage-file-proxy plugin is not installed, automatically downloads and installs from GitHub release
3. **📋 MySQL Confirmation**: For multisite installations, confirms MySQL commands were executed (ensures proper site structure)
4. **⚙️ Smart Configuration**: When setup is requested:
   - **Plugin Detection**: Checks if plugin is already installed
   - **Auto-Installation**: Downloads from `https://github.com/manishsongirkar/stage-file-proxy/releases/download/101/stage-file-proxy.zip`
   - **Plugin Activation**: Network-wide activation for multisite, site-wide for single-site
   - **Domain Mapping**: Uses existing domain mappings from the import process
   - **Protocol Security**: Enforces HTTPS protocol for all source domains
   - **Separate Options**: Uses new `sfp_url` and `sfp_mode` options

### New Setup Process

The enhanced setup process now includes an interactive prompt:

```
📸 Stage File Proxy Setup
Do you want to setup the stage file proxy plugin for media management? (Y/n):
```

**Default Response**: `Y` (Yes) - If user presses Enter without input, setup proceeds automatically.

**Installation Flow**:
- ✅ **Plugin Already Installed**: Proceeds directly to configuration
- 📦 **Plugin Not Found**: Automatically installs from GitHub release, then configures
- ❌ **Installation Fails**: Shows error message and skips configuration
- ⏭️ **User Declines**: Skips entire setup with appropriate message

#### Security & Validation
- **Input Sanitization**: Comprehensive validation of domain inputs with dangerous character detection
- **Protocol Enforcement**: Automatic conversion of HTTP to HTTPS for security
- **Option Safety**: Direct WordPress option updates with proper validation
- **Length Validation**: URL length limits to prevent buffer overflow attacks

#### Multisite Support
- **Individual Site Configuration**: Each subsite gets its own stage-file-proxy settings
- **Bulk Configuration**: Option to apply same source domain to all sites
- **Network Detection**: Automatic detection of subdomain vs subdirectory networks
- **Site-Specific Mapping**: Uses individual domain mappings from the import process

### Example Configuration Output

#### Single Site (New Installation Flow):
```
📸 Stage File Proxy Setup
Do you want to setup the stage file proxy plugin for media management? (Y/n): y
📦 Installing stage-file-proxy plugin...
✅ Plugin installed successfully
📦 Activating stage-file-proxy plugin...
✅ Plugin activated successfully
🧩 Configuring single site stage-file-proxy...
  ✅ Configured successfully: example.local (URL: https://production.example.com, Mode: header)
🎉 stage-file-proxy configuration complete!
```

#### Single Site (Plugin Already Installed):
```
� Stage File Proxy Setup
Do you want to setup the stage file proxy plugin for media management? (Y/n):
�🔍 stage-file-proxy plugin found! Configuring...
📦 Activating stage-file-proxy plugin...
✅ Plugin activated successfully
🧩 Configuring single site stage-file-proxy...
  ✅ Configured successfully: example.local (URL: https://production.example.com, Mode: header)
🎉 stage-file-proxy configuration complete!
```

#### Multisite (New Installation Flow):
```
� Stage File Proxy Setup
Do you want to setup the stage file proxy plugin for media management? (Y/n): y
📦 Installing stage-file-proxy plugin...
✅ Plugin installed successfully
📦 Activating stage-file-proxy plugin...
✅ Plugin activated successfully
🌐 Configuring multisite stage-file-proxy...
✅ Configuring 3 sites with stage-file-proxy
  ✅ Configured successfully: example.local (URL: https://example.com, Mode: header)
  ✅ Configured successfully: blog.example.local (URL: https://blog.example.com, Mode: header)
  ✅ Configured successfully: shop.example.local (URL: https://shop.example.com, Mode: header)
🎉 stage-file-proxy configuration complete!
```

#### User Declines Setup:
```
📸 Stage File Proxy Setup
Do you want to setup the stage file proxy plugin for media management? (Y/n): n
ℹ️ Skipping stage-file-proxy setup as requested
```

#### Installation Failure:
```
📸 Stage File Proxy Setup
Do you want to setup the stage file proxy plugin for media management? (Y/n): y
📦 Installing stage-file-proxy plugin...
❌ Failed to install plugin
⚠️ Skipping stage-file-proxy configuration
```

### Benefits

- **🔄 Zero Configuration**: Automatically inherits domain mappings from import process
- **� Automatic Installation**: Downloads and installs plugin if not present (no manual setup required)
- **�🖼️ Seamless Media**: Missing images/files automatically load from production
- **🌐 Multisite Ready**: Individual configuration for each subsite
- **⏱️ Smart Timing**: Only runs after database structure is properly updated
- **🎯 User Choice**: Interactive prompt with sensible defaults (Yes/No options)
- **🔇 Non-Intrusive**: Silent operation when user declines setup
- **🔒 Security First**: HTTPS enforcement and input validation
- **✨ Modern Structure**: Compatible with latest plugin architecture
- **🛡️ Error Handling**: Graceful failure handling with clear messaging

### Available Proxy Modes

The new plugin supports multiple proxy modes with `header` as the default:

| Mode | Description | Use Case |
|------|-------------|----------|
| **header** | HTTP redirect to remote files (fastest) | **Default** - Best for most setups |
| **download** | Download and save files locally | When you want local file caching |
| **photon** | Use Photon/Jetpack for image processing | For sites using Jetpack |
| **local** | Use local fallback images if remote fails | When you have local replacement images |
| **lorempixel** | Use placeholder service for missing images | For design/development work |

### Manual Setup Alternative

For advanced users or custom setups, use the standalone setup script which also includes automatic installation:

```bash
# Source the setup script
source ~/wp-db-import-and-domain-replacement-tool/setup-stage-file-proxy.sh

# Interactive setup (includes automatic plugin installation if needed)
setup_stage_file_proxy

# Bulk configuration for multisite
bulk_configure_multisite

# View current configuration
show_stage_file_proxy_config
```

**Note**: The standalone setup script now follows the same installation pattern as the main import script - it automatically detects if the plugin is missing and installs it from the GitHub release before proceeding with configuration.

### Configuration Functions

#### Available Functions:
- **`setup_stage_file_proxy`**: Interactive setup with validation
- **`show_stage_file_proxy_config`**: Display current settings (shows new separate options)
- **`bulk_configure_multisite`**: Set same domain for all sites (multisite only)
- **`configure_stage_file_proxy`**: Core configuration function (new plugin structure)

#### Enhanced Input Handling:
- **Domain Validation**: URL format validation with TLD requirements
- **Localhost Support**: Special handling for localhost and IP addresses
- **Protocol Conversion**: Automatic HTTP to HTTPS conversion
- **Whitespace Cleaning**: Automatic trimming of input strings
- **Character Filtering**: Prevention of dangerous characters and injection attempts

---

## 🧪 Example Terminal Session

### 🟢 Single-Site Example

```
$ import_wp_db

🔧 WordPress Database Import & Domain Replace Tool
---------------------------------------------------

📦 Enter SQL file name (default: vip-db.sql): production-backup.sql
✅ WordPress root found: /Users/john/Sites/my-wp-site

✅ Found SQL file: production-backup.sql

🌍 Enter the OLD (production) domain to search for:
⚠️  Production domain is required. Please enter a value.
🌍 Enter the OLD (production) domain to search for: https://example.com/
🏠 Enter the NEW (local) domain/base URL to replace with:
⚠️  Local domain is required. Please enter a value.
🏠 Enter the NEW (local) domain/base URL to replace with: http://example.local

🧹 Cleaned search domain: 'https://example.com/' → 'example.com'
🧹 Cleaned replace domain: 'http://example.local' → 'example.local'
🧾 Summary:
    🔍 Search for:   example.com
    🔄 Replace with: example.local

Proceed with database import? (Y/n): y

⏳ Importing database...
✅ Database import successful! [Completed in 02:34]

🔍 Checking WordPress installation type...
✅ Single site installation detected

Clear ALL post revisions? (improves search-replace speed) (Y/n): y
🗑️ Clearing ALL Post Revisions (improves search-replace speed)...
🗑️ REVISION CLEANUP - STEP BY STEP
=====================================================

🧩 SINGLE SITE DETECTED - Processing main site only...
  Step A: Processing revisions for the main site

  🌍 Processing Main Site
   Revisions found: 15
  ✅ Revisions deleted (WP-CLI reported success)

Include --all-tables (recommended for full DB imports)? (Y/n): y
✅ Will include all tables.

Run in dry-run mode (no data will be changed)? (y/N): n
🚀 Running in live mode (changes will be applied).

🧩 Single site detected.
Proceed with search-replace now? (Y/n): y

🔁 Running search-replace (Double Pass)...
  [Pass 1] Simple replacement: //example.com → //example.local
  [Pass 2] Serialized replacement: \\/\\/example.com → \\/\\/example.local

✅ Search-replace completed successfully!

🧹 Flushing WordPress and WP-CLI caches & transients...
  ✅ Object cache flushed.
  ✅ Rewrite rule flushed.
  ✅ All transients deleted.

🎉 All done! Database import and replacements completed successfully.

📋 MySQL Commands for Single Site:
================================================================

-- Single site setup - domain updated via WP-CLI search-replace
-- No additional MySQL commands needed for single site installations

✅ Single site domain replacement completed via WP-CLI.

================================================================

📋 MySQL Commands Confirmation
Have you executed the above MySQL commands in phpMyAdmin/database? (Y/n): y
🚀 Database Migration Completed Successfully!

� Stage File Proxy Setup
Do you want to setup the stage file proxy plugin for media management? (Y/n): y
📦 Installing stage-file-proxy plugin...
✅ Plugin installed successfully
📦 Activating stage-file-proxy plugin...
✅ Plugin activated successfully
🧩 Configuring single site stage-file-proxy...
  ✅ Configured successfully: example.local (URL: https://example.com, Mode: header)
🎉 stage-file-proxy configuration complete!
```

---

### 🟢 Multisite Example

This comprehensive example demonstrates the enhanced domain+path replacement logic for complex multisite setups:

```
$ import_wp_db

🔧 WordPress Database Import & Domain Replace Tool
---------------------------------------------------

📦 Enter SQL file name (default: vip-db.sql): example-multisite.sql
✅ WordPress root found: /Users/john/Sites/example-wp

✅ Found SQL file: example-multisite.sql

🌍 Enter the OLD (production) domain to search for: example.com
🏠 Enter the NEW (local) domain/base URL to replace with: example.test

🧾 Summary:
    🔍 Search for:   example.com
    🔄 Replace with: example.test

Proceed with database import? (Y/n): y

⏳ Importing database...
✅ Database import successful! [Completed in 03:22]

🔍 Checking WordPress installation type...
✅ Multisite detected via database analysis (blogs: 4, sites: 1)

Clear ALL post revisions? (improves search-replace speed) (Y/n): y
🗑️ Clearing ALL Post Revisions (improves search-replace speed)...
🗑️ REVISION CLEANUP - STEP BY STEP
=====================================================

🌐 MULTISITE DETECTED - Processing all subsites...
  Step A: Getting list of all sites in the network
  Found 4 sites to process:
    1. vip.example.com
    2. us.example.com
    3. demo.example.com
    4. blog.example.com

  Step B: Processing revisions for each site individually

  🌍 Site 1/4: vip.example.com
    Revisions found: 8
  ✅ Revisions deleted (WP-CLI reported success)

  🌍 Site 2/4: us.example.com
    Revisions found: 5
  ✅ Revisions deleted (WP-CLI reported success)

  🌍 Site 3/4: demo.example.com
    Revisions found: 3
  ✅ Revisions deleted (WP-CLI reported success)

  🌍 Site 4/4: blog.example.com
    Revisions found: 12
  ✅ Revisions deleted (WP-CLI reported success)

Include --all-tables (recommended for full DB imports)? (Y/n): y
✅ Will include all tables.

Run in dry-run mode (no data will be changed)? (y/N): n
🚀 Running in live mode (changes will be applied).

�🌐 Multisite (subdomain) detected — gathering subsites for mapping...

✅ Found 4 subsites:
+--------+---------------------------+-------------+
| blog_id| domain                    | path        |
+--------+---------------------------+-------------+
| 1      | vip.example.com           | /           |
| 2      | us.example.com            | /           |
| 3      | demo.example.com          | /           |
| 4      | blog.example.com          | /           |
+--------+---------------------------+-------------+

🌐 Subdomain Multisite Detected
Each subsite has its own domain. Individual mapping required.

Enter the NEW URL/Domain for each site:
(Example: Map 'sub1.example.com' to 'sub1.example.test')

  Processing: Blog ID 1, Domain: 'vip.example.com', Path: '/'
→ Local URL for 'vip.example.com' (Blog ID 1): (example.test) example.test
    ✅ Added mapping: 'vip.example.com' → 'example.test' (ID: 1, Path: /)

  Processing: Blog ID 2, Domain: 'us.example.com', Path: '/'
→ Local URL for 'us.example.com' (Blog ID 2): us.example.test
    ✅ Added mapping: 'us.example.com' → 'example.test/us' (ID: 2, Path: /)

  Processing: Blog ID 3, Domain: 'demo.example.com', Path: '/'
→ Local URL for 'demo.example.com' (Blog ID 3): demo.example.test
    ✅ Added mapping: 'demo.example.com' → 'example.test/demo' (ID: 3, Path: /)

  Processing: Blog ID 4, Domain: 'blog.example.com', Path: '/'
→ Local URL for 'blog.example.com' (Blog ID 4): blog.example.test
    ✅ Added mapping: 'blog.example.com' → 'example.test/blog' (ID: 4, Path: /)

🧾 Domain mapping summary:
    🔁 [ID: 1] vip.example.com/ → example.test
    🔁 [ID: 2] us.example.com/ → example.test/us
    🔁 [ID: 3] demo.example.com/ → example.test/demo
    🔁 [ID: 4] blog.example.com/ → example.test/blog

Proceed with search-replace for all sites? (Y/n): y

🔄 Starting search-replace (per site, sequential) - Subsites first, then Main Site...

➡️  Replacing for Site ID 2: us.example.com/ → us.example.test
  [Pass 1] Simple replacement: //us.example.com → //example.test/us
  [Pass 2] Serialized replacement: \\/\\/us.example.com → \\/\\/example.test/us
✅ Completed for us.example.com/ (ID 2).

➡️  Replacing for Site ID 3: demo.example.com/ → example.test/demo
  [Pass 1] Simple replacement: //demo.example.com → //example.test/demo
  [Pass 2] Serialized replacement: \\/\\/demo.example.com → \\/\\/example.test/demo
✅ Completed for demo.example.com/ (ID 3).

➡️  Replacing for Site ID 4: blog.example.com/ → example.test/blog
  [Pass 1] Simple replacement: //blog.example.com → //example.test/blog
  [Pass 2] Serialized replacement: \\/\\/blog.example.com → \\/\\/example.test/blog
✅ Completed for blog.example.com/ (ID 4).

  MAIN SITE REPLACEMENT (ID = 1)

➡️  Replacing for Main Site ID 1: vip.example.com/ → example.test
  [Pass 1] Simple replacement: //vip.example.com → //example.test
  [Pass 2] Serialized replacement: \\/\\/vip.example.com → \\/\\/example.test
✅ Completed for Main Site (ID 1).

🧹 Flushing WordPress and WP-CLI caches & transients...
  ✅ Object cache flushed.
  ✅ Rewrite rule flushed.
  ✅ All transients deleted.

🎉 All done! Database import and replacements completed successfully.

================================================================

📋 MySQL Commands for Manual Execution in phpMyAdmin:

================================================================

-- 1. Update blog domains and paths for SUB-SITES (ID != 1)

UPDATE wp_blogs SET domain = "example.test", path = "/us/" WHERE blog_id = 2; -- us.example.com → example.test/us (Subsite)
UPDATE wp_blogs SET domain = "example.test", path = "/demo/" WHERE blog_id = 3; -- demo.example.com → example.test/demo (Subsite)
UPDATE wp_blogs SET domain = "example.test", path = "/blog/" WHERE blog_id = 4; -- vip.example.com → example.test/blog (Subsite)

-- 2. Update blog domain and path for MAIN SITE (ID = 1)

UPDATE wp_blogs SET domain = "example.test", path = "/" WHERE blog_id = 1; -- vip.example.com → example.test (Main Site)

-- 3. Update the main network site domain (ID = 1)
UPDATE wp_site SET domain = 'example.test' WHERE id = 1;


💡 Copy the above commands and paste them into phpMyAdmin → SQL command to execute.

================================================================

📋 MySQL Commands Confirmation
Have you executed the above MySQL commands in phpMyAdmin/database? (Y/n): y
🚀 Database Migration Completed Successfully!

� Stage File Proxy Setup
Do you want to setup the stage file proxy plugin for media management? (Y/n): y
📦 Installing stage-file-proxy plugin...
✅ Plugin installed successfully
📦 Activating stage-file-proxy plugin...
✅ Plugin activated successfully
🌐 Configuring multisite stage-file-proxy...
✅ Configuring 4 sites with stage-file-proxy
  ✅ Configured successfully: example.test (URL: https://vip.example.com, Mode: header)
  ✅ Configured successfully: us.example.test (URL: https://us.example.com, Mode: header)
  ✅ Configured successfully: demo.example.test (URL: https://demo.example.com, Mode: header)
  ✅ Configured successfully: blog.example.test (URL: https://blog.example.com, Mode: header)
🎉 stage-file-proxy configuration complete!
```

---

## ⚡ Configuration Options

| Option | Description | Default | Advanced Notes |
| -------- | ----------- | ------- | -------------- |
| **SQL filename** | Database dump file to import | `vip-db.sql` | Supports absolute and relative paths |
| **Old Domain** | Production domain to search for | Required input | Auto-sanitized (protocols/slashes removed) |
| **New Domain** | Local/staging domain to replace with | Required input | Security validation applied |
| **Revision cleanup** | Delete all post revisions before search-replace | Optional (Y/n) | Site-by-site processing for multisite |
| **All tables** | Include non-WordPress prefixed tables | Recommended (Y/n) | Essential for full migrations |
| **Dry-run mode** | Preview changes without applying them | Optional (y/N) | Shows exact SQL commands to be executed |
| **Multisite mapping** | Per-subsite domain mapping (auto-detected) | Interactive prompts | Supports both subdomain and subdirectory |
| **SQL confirmation** | Confirm MySQL commands executed (multisite) | Default Yes (Y/n) | Required for stage-file-proxy setup |
| **Stage File Proxy Setup** | Interactive setup prompt for media management | Default Yes (Y/n) | Includes automatic plugin installation if not present |
| **Cache clearing** | Flush object cache, rewrites, and transients | Automatic | Network-wide for multisite |

### Advanced Configuration Details

#### Domain Sanitization Process:
1. **Protocol Removal**: Strips `http://` and `https://` prefixes
2. **Whitespace Cleaning**: Removes leading/trailing spaces and control characters
3. **Slash Normalization**: Removes trailing slashes for consistency
4. **Security Validation**: Blocks dangerous characters and injection attempts
5. **Format Validation**: Ensures valid domain format with TLD requirements

#### Multisite Handling:
- **Subdirectory Networks**: Single network-wide replacement with shared domain
- **Subdomain Networks**: Individual site mapping with custom local domains
- **Path Detection**: Automatic blog path generation for subdirectory setups
- **Blog ID Mapping**: Precise mapping of blog_id to domain/path combinations

#### Stage File Proxy Security:
- **HTTPS Enforcement**: All source domains stored with HTTPS protocol
- **Input Validation**: Comprehensive validation of domain inputs
- **Protocol Conversion**: Automatic HTTP to HTTPS upgrade for security

---

## 📂 Enhanced Logging System

The tool creates comprehensive logs with process-specific names for debugging and audit trails:

| File Pattern | Purpose | Lifecycle | Content |
| ------------ | ------- | --------- | ------- |
| `/tmp/wp_db_import_$$.log` | Database import operations | Process duration | Import success/failure, SQL errors |
| `/tmp/wp_replace_single_$$.log` | Single-site search-replace | Process duration | URL replacements, serialized data changes |
| `/tmp/wp_replace_<blogid>_$$.log` | Multisite per-site operations | Process duration | Site-specific URL replacements |
| `/tmp/wp_revision_delete_$$.log` | Post revision cleanup | Process duration | Revision deletion results |
| `/tmp/wp_subsite_data_$$.csv` | Multisite site information | Process duration | Blog ID, domain, path mappings |

### Log Management Features:
- **🔄 Automatic Cleanup**: All temporary files deleted on successful exit
- **💥 Crash Recovery**: Manual cleanup commands provided for interrupted processes
- **🔍 Process Isolation**: PID-based naming prevents conflicts in concurrent runs
- **📊 Audit Trail**: Complete record of all operations for troubleshooting
- **🗂️ Structured Data**: CSV format for multisite data enables easy parsing

### Manual Cleanup Commands:
```bash
# Remove all logs for current process
rm -f /tmp/wp_*_$$.log /tmp/wp_*_$$.csv

# Remove all WordPress tool logs (all processes)
rm -f /tmp/wp_*_*.log /tmp/wp_*_*.csv

# Find and remove old logs (older than 1 day)
find /tmp -name "wp_*_*.log" -mtime +1 -delete
find /tmp -name "wp_*_*.csv" -mtime +1 -delete
```

---

## 🧮 Enhanced MySQL Command Generation

The script generates sophisticated SQL commands for manual execution in phpMyAdmin, with intelligent handling of different multisite configurations:

### Single-Site Commands:
```sql
-- Single site installations use WP-CLI search-replace exclusively
-- No additional MySQL commands needed
-- Domain replacement handled automatically via WordPress core functions
```

### Multisite Commands (Subdomain Network):
```sql
-- Update the main network domain
UPDATE wp_site SET domain = 'example.local' WHERE id = 1;

-- Update individual blog domains (each subsite gets unique domain)
UPDATE wp_blogs SET domain = "blog.example.local", path = "/" WHERE blog_id = 2; -- blog.example.com → blog.example.local
UPDATE wp_blogs SET domain = "shop.example.local", path = "/" WHERE blog_id = 3; -- shop.example.com → shop.example.local
UPDATE wp_blogs SET domain = "news.example.local", path = "/" WHERE blog_id = 4; -- news.example.com → news.example.local
```

### Multisite Commands (Subdirectory Network):
```sql
-- Update the main network domain
UPDATE wp_site SET domain = 'example.local' WHERE id = 1;

-- Update blog domains (shared domain with individual paths)
UPDATE wp_blogs SET domain = "example.local", path = "/" WHERE blog_id = 1;      -- Main site
UPDATE wp_blogs SET domain = "example.local", path = "/blog/" WHERE blog_id = 2; -- example.com/blog → example.local/blog
UPDATE wp_blogs SET domain = "example.local", path = "/shop/" WHERE blog_id = 3; -- example.com/shop → example.local/shop
UPDATE wp_blogs SET domain = "example.local", path = "/news/" WHERE blog_id = 4; -- example.com/news → example.local/news
```

### Advanced Command Features:

#### Intelligent Path Generation:
- **Automatic Detection**: Script determines subdomain vs subdirectory network type
- **Path Extraction**: For subdirectory sites, extracts path from mapped local domain
- **Slash Normalization**: Ensures proper leading/trailing slash format
- **Duplicate Prevention**: Prevents duplicate SQL commands for same blog_id

#### Security Enhancements:
- **SQL Injection Protection**: All values properly quoted and escaped
- **Blog ID Validation**: Ensures blog_id exists before generating commands
- **Domain Validation**: Validates domain format before including in SQL
- **Comment Documentation**: Each command includes source → target mapping

#### Execution Instructions:
```
💡 Copy the above commands and paste them into phpMyAdmin → SQL tab to execute.

⚠️  Important: Execute these commands AFTER the WP-CLI search-replace operations complete.
    The commands update the multisite network structure which is separate from content URLs.
```

---

## 🧹 Advanced Cleanup & Maintenance

### Automatic Cleanup Features:
- **🔄 Exit Traps**: Comprehensive cleanup on script completion or interruption
- **🗂️ Process Isolation**: PID-based file naming prevents conflicts
- **🧹 Multi-Pattern Cleanup**: Removes logs, CSV files, and temporary data
- **⏰ Time-Based Cleanup**: Automatic removal of old WP-CLI cache files
- **🛡️ Safe Removal**: Validates file existence before deletion attempts

### Manual Cleanup Commands:

#### For Current Process:
```bash
# Remove logs for current shell session
rm -f /tmp/wp_*_$$.log /tmp/wp_*_$$.csv /tmp/wp_*_$$.tmp

# Clean up any missed files with current PID
find /tmp -name "*_$$.*" -type f -delete 2>/dev/null
```

#### For All WordPress Tool Processes:
```bash
# Remove all WordPress migration tool logs
find /tmp -type f -name "wp_db_import_*.log" -delete 2>/dev/null
find /tmp -type f -name "wp_replace_*.log" -delete 2>/dev/null
find /tmp -type f -name "wp_revision_*.log" -delete 2>/dev/null
find /tmp -type f -name "wp_subsite_*.csv" -delete 2>/dev/null

# Clean old WP-CLI cache files (older than 1 day)
find /tmp -type f -name "wp-cli-*" -mtime +1 -delete 2>/dev/null
```

#### Emergency Cleanup (if process was killed):
```bash
# Nuclear option - removes ALL temporary WordPress-related files
sudo find /tmp -type f \( -name "wp_*" -o -name "wp-cli-*" \) -delete 2>/dev/null

# Check remaining temp files
ls -la /tmp/wp_* 2>/dev/null | head -10
```

### Cleanup Verification:
```bash
# Check for remaining WordPress tool files
ls -la /tmp/wp_* 2>/dev/null && echo "Files found" || echo "All clean"

# Monitor temp directory size
du -sh /tmp/ | grep -E "[0-9]+[MG]" && echo "Large temp directory detected"
```

---

## 🧩 Comprehensive Troubleshooting

### Common Issues & Advanced Solutions

| Problem Category | Symptoms | Root Cause | Advanced Solution |
| --------------- | -------- | ---------- | ----------------- |
| **WP-CLI Issues** | `❌ WP-CLI not found in PATH` | Missing or incorrect installation | Install via Homebrew: `brew install wp-cli`<br/>Or Composer: `composer global require wp-cli/wp-cli`<br/>Add to PATH: `export PATH="$PATH:$HOME/.composer/vendor/bin"` |
| **File System** | `❌ File 'filename.sql' not found` | Incorrect path or permissions | Use absolute path: `import_wp_db` then enter `/full/path/to/file.sql`<br/>Check permissions: `ls -la filename.sql` |
| **WordPress Detection** | `❌ WordPress root not found` | Script run from wrong directory | Navigate to WordPress root: `cd /path/to/wordpress`<br/>Or any subdirectory containing wp-config.php |
| **Database Connection** | `❌ Database import failed` | Invalid credentials or privileges | Check wp-config.php credentials<br/>Test connection: `wp db check`<br/>Verify user privileges: `GRANT ALL ON database.* TO 'user'@'localhost';` |
| **Memory/Performance** | Search-replace fails midway | PHP memory limits or timeouts | Increase PHP memory: `ini_set('memory_limit', '512M')`<br/>Use revision cleanup first<br/>Run in smaller batches |
| **Multisite Complexity** | Site mapping confusion | Complex network setup | Use dry-run mode first<br/>Document existing site structure<br/>Test with backup database |
| **Stage File Proxy** | Plugin not configuring | Missing plugin or wrong timing | Install plugin: `wp plugin install stage-file-proxy`<br/>Confirm MySQL commands executed<br/>Check plugin compatibility |

### Advanced Debugging Techniques

#### Verbose WP-CLI Output:
```bash
# Run WP-CLI commands with debug info
wp --debug import database.sql

# Check WP-CLI configuration
wp cli info

# Test specific WordPress functions
wp eval 'echo is_multisite() ? "multisite" : "single-site";'
```

#### Database Connection Testing:
```bash
# Test database connectivity
wp db query "SELECT COUNT(*) as posts FROM wp_posts;"

# Check table permissions
wp db query "SHOW GRANTS FOR CURRENT_USER();"

# Validate database structure
wp db check --repair
```

#### File System Diagnostics:
```bash
# Check WordPress file permissions
find /path/to/wordpress -type f -not -perm 644 -o -type d -not -perm 755

# Verify wp-config.php accessibility
wp config list

# Test write permissions in WordPress directory
touch /path/to/wordpress/test_write.tmp && rm /path/to/wordpress/test_write.tmp
```

### Performance Optimization

#### For Large Databases:
```bash
# Skip revision cleanup if database is very large
# Select "n" for revision cleanup option

# Use specific table targeting instead of --all-tables
# Select "n" for all-tables option

# Run search-replace in smaller chunks
wp search-replace "old.com" "new.com" --dry-run | head -50
```

#### For Multisite Networks:
```bash
# Process sites individually if network-wide operations fail
wp site list --field=url | while read url; do
  wp --url="$url" search-replace "old.com" "new.com" --dry-run
done

# Check multisite configuration
wp network meta list 1
```

### Security Considerations

#### Input Validation Errors:
- **Dangerous Characters**: Script blocks `;`, `|`, `&`, `$`, backticks, quotes
- **Control Characters**: Non-printable characters automatically filtered
- **Length Limits**: URL inputs limited to 2048 characters
- **Protocol Enforcement**: HTTPS automatically applied for stage-file-proxy

#### Safe Recovery Procedures:
```bash
# Create database backup before any operation
wp db export backup-$(date +%Y%m%d-%H%M%S).sql

# Test operations in staging environment first
wp --url=staging.site.com search-replace "prod.com" "staging.com" --dry-run

# Rollback using backup if needed
wp db import backup-YYYYMMDD-HHMMSS.sql
```

---

## 🛡️ Enhanced Safety & Security Recommendations

### Pre-Operation Safety Checklist:

#### Database Protection:
```bash
# Create timestamped backup with compression
wp db export "backup-$(date +%Y%m%d-%H%M%S).sql.gz" --compress

# Verify backup integrity
gunzip -t "backup-$(date +%Y%m%d-%H%M%S).sql.gz"

# Store backup in secure location
cp backup-*.sql.gz ~/wp-backups/$(basename $(pwd))/
```

#### Configuration Backup:
```bash
# Backup critical WordPress files
tar -czf "wp-config-backup-$(date +%Y%m%d).tar.gz" wp-config.php .htaccess

# Backup multisite configuration (if applicable)
wp network meta list 1 > network-config-backup.txt
```

### Security Best Practices:

#### Input Validation Features:
- **🔍 Domain Sanitization**: Automatic removal of protocols, trailing slashes, and dangerous characters
- **🛡️ Injection Prevention**: Blocks shell metacharacters (`;`, `|`, `&`, `$`, backticks)
- **📏 Length Validation**: Enforces reasonable URL length limits (2048 chars)
- **🔒 Protocol Security**: Enforces HTTPS for stage-file-proxy configurations
- **🧹 Character Filtering**: Removes control characters and non-printable content

#### Operational Security:
```bash
# Run in dry-run mode first for all new migrations
import_wp_db  # Select "y" for dry-run when prompted

# Verify search-replace operations before applying
wp search-replace "old.com" "new.com" --dry-run --report-changed-only

# Test database connectivity before import
wp db check && echo "Database OK" || echo "Database Issues"

# Monitor system resources during operation
watch -n 1 'ps aux | grep "wp\|mysql" | head -10'
```

### Environment Validation:

#### Pre-Flight Checks:
```bash
# Comprehensive environment validation
wp --info | grep -E "(PHP version|MySQL|WP-CLI version)"
df -h . | grep -v "Filesystem"  # Check disk space
free -h | grep -E "(Mem|Swap)"  # Check memory
```

#### Permission Verification:
```bash
# WordPress directory permissions
find . -type f -exec chmod 644 {} \; -o -type d -exec chmod 755 {} \;

# Verify write access
touch test-write.tmp && rm test-write.tmp && echo "Write OK" || echo "Write Failed"
```

### Recovery Procedures:

#### Emergency Rollback:
```bash
# Quick database restore (if backup exists)
wp db import backup-YYYYMMDD-HHMMSS.sql

# Reset multisite network (if structure corrupted)
wp site list --format=ids | xargs -I {} wp site delete {} --yes
wp network meta delete 1 --all
```

#### Log Analysis:
```bash
# Check recent error logs
tail -100 /tmp/wp_*_$$.log | grep -i error

# Monitor WordPress debug logs
tail -f wp-content/debug.log | grep -E "(FATAL|ERROR|WARNING)"
```

### Testing & Validation:

#### Staged Deployment Workflow:
1. **🧪 Development**: Test with small database subset
2. **🔍 Staging**: Full test with production data copy
3. **📊 Validation**: Verify all URLs, images, and links work
4. **🚀 Production**: Apply with confidence after validation

#### Post-Migration Checks:
```bash
# Verify WordPress functionality
wp option get home
wp option get siteurl
wp user list --field=user_email | head -5

# Test multisite network (if applicable)
wp site list --field=url
wp network meta get 1 site_name
```

---

🟩 **Quick Start Guide:**

```bash
# 1. Clone the repository to your home directory
cd ~
git clone https://github.com/manishsongirkar/wp-db-import-and-domain-replacement-tool.git

# 2. Add to your shell configuration (~/.bashrc or ~/.zshrc)
echo '# WordPress Database Import Tool' >> ~/.zshrc
echo 'if [ -f "$HOME/wp-db-import-and-domain-replacement-tool/import_wp_db.sh" ]; then' >> ~/.zshrc
echo '    source "$HOME/wp-db-import-and-domain-replacement-tool/import_wp_db.sh"' >> ~/.zshrc
echo 'fi' >> ~/.zshrc

# 3. Optional: Add Stage File Proxy manual setup tool
echo 'if [ -f "$HOME/wp-db-import-and-domain-replacement-tool/setup-stage-file-proxy.sh" ]; then' >> ~/.zshrc
echo '    source "$HOME/wp-db-import-and-domain-replacement-tool/setup-stage-file-proxy.sh"' >> ~/.zshrc
echo 'fi' >> ~/.zshrc

# 4. Reload your shell configuration
source ~/.zshrc  # or ~/.bashrc

# 5. Verify installation
type import_wp_db && echo "✅ Installation successful" || echo "❌ Installation failed"

# 6. Navigate to your WordPress project and run
cd /path/to/your/wordpress/site
import_wp_db

# 7. Optional: Manual stage-file-proxy setup (if uncommented in step 3)
# setup_stage_file_proxy
# show_stage_file_proxy_config
# bulk_configure_multisite  # For multisite only
```

---
