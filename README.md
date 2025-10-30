# 🧩 WordPress Database Import & Domain Replacement Bash Script

A powerful **interactive Bash function** that automates importing a WordPress database dump (`.sql` file), performs **domain replacements**, handles **multisite setups**, and optionally **cleans post revisions** — all with color-coded feedback, safety prompts, and detailed logging.

---

## 🚀 Features

- ✅ **Automatic WordPress installation detection** (single-site or multisite)
- ✅ **Intelligent domain sanitization** (removes protocols, trailing slashes)
- ✅ **Interactive domain mapping** for multisite installations
- ✅ **Two-pass search-replace** (standard + serialized data)
- ✅ **Post revision cleanup** for improved performance
- ✅ **Cache and transient clearing** (object cache, rewrites, transients)
- ✅ **Dry-run mode** for testing before applying changes
- ✅ **MySQL command generation** for phpMyAdmin manual execution
- ✅ **Stage File Proxy integration** - Automatic setup for local development
- ✅ **Comprehensive error handling** and logging
- ✅ **Colored terminal output** with progress indicators
- ✅ **Smart WordPress root detection** (works from any subdirectory)
- ✅ **Safe exit traps** and automatic cleanup of temporary files
- ✅ **Supports both multisite types** (subdomain and subdirectory networks)

---

## 🧰 Requirements

| Requirement | Description |
|--------------|-------------|
| **Operating System** | macOS/Linux environment (Bash shell) |
| **WP-CLI** | Installed and accessible in PATH |
| **WordPress** | WordPress installation (wp-config.php present) |
| **Database** | MySQL/MariaDB database |
| **Permissions** | User must have DB import privileges |
| **File Access** | SQL file in same directory or accessible path |

Check your environment:
```bash
wp --info
mysql --version
bash --version
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

You'll be guided step-by-step through the process:

1. **SQL File**: Confirm SQL file name (default: `vip-db.sql`)
2. **Domain Mapping**: Enter old domain (production) and new domain (local)
3. **Import Confirmation**: Review and confirm database import
4. **Multisite Detection**: Automatic detection of WordPress type
5. **Revision Cleanup**: Optional cleanup of post revisions for better performance
6. **Options**: Choose `--all-tables` and dry-run mode settings
7. **Domain Mapping** (Multisite): Interactive mapping for each subsite
8. **Execution**: Two-pass search-replace with progress indicators
9. **Cache Cleanup**: Automatic flushing of caches and transients
10. **MySQL Commands**: Generated commands for manual phpMyAdmin execution
11. **SQL Confirmation**: Confirmation prompt for MySQL command execution
12. **Stage File Proxy Setup**: Automatic configuration if plugin is installed

---

## 🔄 Stage File Proxy Integration

The script automatically detects and configures the **Stage File Proxy** plugin for seamless local development. This plugin allows your local WordPress installation to fetch missing media files from the production server automatically.

### How It Works

1. **Silent Detection**: After displaying MySQL commands, the script silently checks for the stage-file-proxy plugin
2. **Confirmation Required**: For multisite installations, asks if you've executed the MySQL commands (default: Yes)
3. **Automatic Configuration**: If plugin is found and confirmed, automatically:
   - Activates the plugin (if not already active)
   - Configures source domains using existing domain mappings
   - Sets up redirect method for file proxying

### Example Output

#### When Plugin is Found:
```
📋 MySQL Commands Confirmation
Have you executed the above MySQL commands in phpMyAdmin/database? (Y/n): y
🚀 Database Migration Completed Successfully!

🔍 stage-file-proxy plugin found! Configuring...
✅ Plugin already active
🧩 Configuring single site stage-file-proxy...
  ✅ Configured: local.dev → https://production.com
🎉 stage-file-proxy configuration complete!
```

#### When Plugin is Not Found:
The script continues silently without any stage-file-proxy messages.

### Benefits

- **Zero Configuration**: Automatically uses your existing domain mappings
- **Seamless Development**: Missing images/files load from production
- **Multisite Support**: Configures each subsite individually
- **Safe Timing**: Only runs after database structure is properly updated
- **Non-Intrusive**: Only shows output if plugin is present and being configured

### Manual Setup Alternative

If you prefer to set up stage-file-proxy manually, you can source the standalone setup script:

```bash
# Uncomment this line in your shell configuration
if [ -f "$HOME/wp-db-import-and-domain-replacement-tool/setup-stage-file-proxy.sh" ]; then
    source "$HOME/wp-db-import-and-domain-replacement-tool/setup-stage-file-proxy.sh"
fi

# Then use the manual setup function
setup_stage_file_proxy
```

---

## 🧪 Example Terminal Session

### 🟢 Single-Site Example

```
$ import_wp_db

� WordPress Database Import & Domain Replace Tool
---------------------------------------------------

📦 Enter SQL file name (default: vip-db.sql): production-backup.sql
✅ WordPress root found: /Users/john/Sites/my-wp-site

✅ Found SQL file: production-backup.sql

� Enter the OLD (production) domain to search for: example.com
� Enter the NEW (local) domain/base URL to replace with: example.local

🧾 Summary:
    🔍 Search for:   example.com
    🔄 Replace with: example.local

Proceed with database import? (Y/n): y

⏳ Importing database...
✅ Database import successful!

🔍 Checking WordPress installation type...
✅ Multisite status: no

Clear ALL post revisions? (improves search-replace speed) (Y/n): y
🗑️ REVISION CLEANUP - STEP BY STEP
=====================================================

🧩 SINGLE SITE DETECTED - Processing main site only...
  Step A: Processing revisions for the main site

  🌍 Processing Main Site
  ✅ Revisions deleted

Include --all-tables (recommended for full DB imports)? (Y/n): y
✅ Will include all tables.

Run in dry-run mode (no data will be changed)? (y/N): n
🚀 Running in live mode (changes will be applied).

Proceed with search-replace now? (Y/n): y

� Running search-replace (Double Pass)...
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
```

---

### 🟢 Multisite Example

```
$ import_wp_db

� WordPress Database Import & Domain Replace Tool
---------------------------------------------------

📦 Enter SQL file name (default: vip-db.sql): multisite-backup.sql
✅ WordPress root found: /Users/john/Sites/multisite-wp

✅ Found SQL file: multisite-backup.sql

� Enter the OLD (production) domain to search for: example.com
� Enter the NEW (local) domain/base URL to replace with: example.local

🧾 Summary:
    🔍 Search for:   example.com
    🔄 Replace with: example.local

Proceed with database import? (Y/n): y

⏳ Importing database...
✅ Database import successful!

🔍 Checking WordPress installation type...
✅ Multisite status: subdomain

Clear ALL post revisions? (improves search-replace speed) (Y/n): y
🗑️ REVISION CLEANUP - STEP BY STEP
=====================================================

🌐 MULTISITE DETECTED - Processing all subsites...
  Step A: Getting list of all sites in the network
Found 3 sites to process:
    1. example.com
    2. blog.example.com
    3. shop.example.com

  Step B: Processing revisions for each site individually

  🌍 Site 1/3: example.com
  ✅ Revisions deleted

  🌍 Site 2/3: blog.example.com
  ✅ Revisions deleted

  🌍 Site 3/3: shop.example.com
  ✅ Revisions deleted

Include --all-tables (recommended for full DB imports)? (Y/n): y
✅ Will include all tables.

Run in dry-run mode (no data will be changed)? (y/N): n
🚀 Running in live mode (changes will be applied).

🌐 Multisite (subdomain) detected — gathering subsites for mapping...

✅ Found 3 subsites:
+--------+------------------+------+
| blog_id| domain           | path |
+--------+------------------+------+
| 1      | example.com      | /    |
| 2      | blog.example.com | /    |
| 3      | shop.example.com | /    |
+--------+------------------+------+

Enter the NEW URL/Domain for each site:
(Example: Map 'sub1.example.com' to 'example.local/sub1')

→ Local URL for 'example.com' (Blog ID 1): (example.local) example.local
→ Local URL for 'blog.example.com' (Blog ID 2): blog.example.local
→ Local URL for 'shop.example.com' (Blog ID 3): shop.example.local

🧾 Domain mapping summary:
    🔁 example.com → example.local
    🔁 blog.example.com → blog.example.local
    🔁 shop.example.com → shop.example.local

Proceed with search-replace for all subsites? (Y/n): y

� Starting search-replace (per subsite, sequential)...

➡️  Replacing for Site ID 1: example.com → example.local
  [Pass 1] Simple replacement: //example.com → //example.local
  [Pass 2] Serialized replacement: \\/\\/example.com → \\/\\/example.local
✅ Completed for example.com.

➡️  Replacing for Site ID 2: blog.example.com → blog.example.local
  [Pass 1] Simple replacement: //blog.example.com → //blog.example.local
  [Pass 2] Serialized replacement: \\/\\/blog.example.com → \\/\\/blog.example.local
✅ Completed for blog.example.com.

➡️  Replacing for Site ID 3: shop.example.com → shop.example.local
  [Pass 1] Simple replacement: //shop.example.com → //shop.example.local
  [Pass 2] Serialized replacement: \\/\\/shop.example.com → \\/\\/shop.example.local
✅ Completed for shop.example.com.

🧹 Flushing WordPress and WP-CLI caches & transients...
  ✅ Object cache flushed.
  ✅ Rewrite rule flushed.
  ✅ All transients deleted.

🎉 All done! Database import and replacements completed successfully.

================================================================

📋 MySQL Commands for Manual Execution in phpMyAdmin:

================================================================

-- Update the main site domain
UPDATE wp_site SET domain = 'example.local' WHERE id = 1;

-- Update blog domains and paths based on domain mapping
UPDATE wp_blogs SET domain = "example.local", path = "/" WHERE blog_id = 1;
UPDATE wp_blogs SET domain = "example.local", path = "/" WHERE blog_id = 2;
UPDATE wp_blogs SET domain = "example.local", path = "/" WHERE blog_id = 3;

💡 Copy the above commands and paste them into phpMyAdmin → SQL command to execute.
```

---

## ⚡ Options Overview

| Option               | Description                                   | Default |
| -------------------- | --------------------------------------------- | ------- |
| **SQL filename**     | Database dump file to import                  | `vip-db.sql` |
| **Old Domain**       | Production domain to search for               | Required input |
| **New Domain**       | Local/staging domain to replace with         | Required input |
| **Revision cleanup** | Delete all post revisions before search-replace | Optional (Y/n) |
| **All tables**       | Include non-WordPress prefixed tables        | Recommended (Y/n) |
| **Dry-run mode**     | Preview changes without applying them        | Optional (y/N) |
| **Multisite mapping**| Per-subsite domain mapping (auto-detected)   | Interactive prompts |
| **SQL confirmation** | Confirm MySQL commands executed (multisite)  | Default Yes (Y/n) |
| **Stage File Proxy** | Auto-setup if plugin installed              | Automatic detection |
| **Cache clearing**   | Flush object cache, rewrites, and transients | Automatic |

---

## 📂 Log Files

During execution, logs are written to `/tmp/` with PID-based names:

| File                              | Purpose                    |
| --------------------------------- | -------------------------- |
| `/tmp/wp_db_import_$$.log`        | Database import process    |
| `/tmp/wp_replace_single_$$.log`   | Single-site search-replace |
| `/tmp/wp_replace_<blogid>_$$.log` | Multisite search-replace   |
| `/tmp/wp_revision_delete_$$.log`  | Revision cleanup           |
| `/tmp/wp_subsite_data_$$.csv`     | Multisite subsite list     |

> All temporary files are deleted automatically upon successful completion or exit.

---

## 🧮 Example MySQL Helper Commands

After running, the script generates SQL commands, run these commands from PHPMyAdmin > SQL Commands:

```sql
UPDATE wp_site SET domain = 'example.local' WHERE id = 1;

UPDATE wp_blogs set domain="example.local", path="/" where blog_id=1;
UPDATE wp_blogs set domain="example.local", path="/sub1/" where blog_id=2;
UPDATE wp_blogs set domain="example.local", path="/sub2/" where blog_id=3;
UPDATE wp_blogs set domain="example.local", path="/sub3/" where blog_id=4;
```

These can be used inside phpMyAdmin or MySQL directly if needed.

---

## 🧹 Cleanup Behavior

* **Automatic:** Temporary logs are deleted when the script exits.
* **Manual:** If the script is interrupted (e.g., Ctrl+C), you can remove leftovers:

  ```bash
  rm -f /tmp/wp_*_$$.*
  ```

---

## 🧩 Troubleshooting

| Problem                                    | Cause                     | Solution                                                                     |
| ------------------------------------------ | ------------------------- | ---------------------------------------------------------------------------- |
| `❌ WP-CLI not found in PATH`             | WP-CLI not in PATH        | Install via `brew install wp-cli` or `composer global require wp-cli/wp-cli` |
| `❌ File 'filename.sql' not found`        | Wrong filename or path    | Ensure `.sql` file exists in current directory or specify full path          |
| `❌ WordPress root not found`             | Script not run in WP root | Navigate to folder containing `wp-config.php` or its subdirectory           |
| `❌ No WordPress installation detected`   | Invalid WordPress setup   | Check `wp-config.php` and database connection                               |
| `❌ Database import failed`               | Database connection issue | Check database credentials in `wp-config.php` and user privileges           |
| `❌ Failed to change directory`           | Permission issues         | Check directory permissions and disk space                                  |
| Search-replace fails midway               | WP-CLI timeout/memory     | Check available memory and `php.ini` settings                               |
| `env: php: No such file or directory`     | PHP not in PATH          | Ensure PHP is installed and accessible in system PATH                       |
| Stage-file-proxy not configuring          | Plugin not installed      | Install stage-file-proxy plugin or answer 'n' to SQL confirmation           |

---

## 🛡️ Safety Recommendations

* **Always backup your database** before importing:
  ```bash
  wp db export backup-$(date +%F).sql
  ```

* **Use dry-run mode** for first-time replacements to preview changes

* **Test on staging environment** before applying to production

* **Verify domain sanitization** - the script automatically removes protocols and trailing slashes

* **Review generated logs** before deleting them (stored in `/tmp/`)

* **Check multisite domain mapping** carefully for complex network setups

* **Backup wp-config.php** as it contains critical database connection info

---

🟩 **Quick Start:**

```bash
# 1. Clone the repository
cd ~
git clone https://github.com/manishsongirkar/wp-db-import-and-domain-replacement-tool.git

# 2. Add to your shell configuration (~/.bashrc or ~/.zshrc)
if [ -f "$HOME/wp-db-import-and-domain-replacement-tool/import_wp_db.sh" ]; then
    source "$HOME/wp-db-import-and-domain-replacement-tool/import_wp_db.sh"
fi

# Uncomment this line in your shell configuration
# if [ -f "$HOME/wp-db-import-and-domain-replacement-tool/setup-stage-file-proxy.sh" ]; then
#     source "$HOME/wp-db-import-and-domain-replacement-tool/setup-stage-file-proxy.sh"
# fi

# 3. Reload your shell
source ~/.bashrc  # or ~/.zshrc

# 4. Verify installation
type import_wp_db

# 5. Navigate to your WordPress project and run
cd /path/to/your/wordpress/site
import_wp_db
```

---
