# 🧩 WordPress Database Import & Domain Replacement Tool

A robust bash utility for performing WordPress database imports and domain/URL replacements, commonly needed for migrating environments (e.g., production to local/staging). It efficiently handles single-site and multi-domain WordPress Multisite setups.

## ✨ Features

- 🔄 **Automatic WordPress installation detection** (single-site or multisite)
- ⚡ **High-Speed Bulk Post Revision Cleanup** (via xargs)
- 🧹 **Intelligent domain sanitization** (removes protocols, trailing slashes)
- 🌐 **Robust Multi-Domain/Per-Site Mapping** for Multisite
- 🔁 **Two-pass search-replace** (standard + serialized data)
- 🗑️ **Cache and transient clearing** via WP-CLI
- 🧪 **Dry-run mode** for testing replacements
- 📦 **MySQL command generation** for network domain tables
- 🛡️ **Comprehensive error handling** and logging
- 🎨 **Colored terminal output** with clear progress indicators
- 📸 **Stage File Proxy Plugin** automatic installation and configuration

## 🧰 Requirements

| Requirement | Description | Version Notes |
|--------------|-------------|---------------|
| **Operating System** | macOS/Linux environment with Bash shell | Bash 4.0+ recommended |
| **WP-CLI** | WordPress Command Line Interface | Latest stable version |
| **WordPress** | WordPress installation with wp-config.php | Single-site or multisite |
| **Database** | MySQL/MariaDB database with import privileges | 5.7+ or 10.2+ |
| **PHP** | PHP runtime for WP-CLI operations | 7.4+ recommended |
| **File System** | Read/write access to WordPress directory | Sufficient disk space for import |

## 📦 Installation & Setup:

```bash
# 1. Clone repository into your main user directory, where your `.bashrc` or `.zshrc` file is located:
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
source ~/.zshrc

# or
# source ~/.bashrc

# 5. Verify installation
type import_wp_db && echo "✅ Installation successful" || echo "❌ Installation failed"

# 6. Navigate to your WordPress project and run
cd /path/to/your/wordpress/site
import_wp_db

# 7. Optional: Manual stage-file-proxy setup
setup_stage_file_proxy

# 8. Optional: To view Single or Multisite links (Local site)
show_local_site_links
```

## 🚀 Usage

### Basic Usage

1. Navigate to your WordPress root directory (where `wp-config.php` file present)
1. Place your SQL (`.sql`) file in the same directory
2. Run the function:
   ```bash
   import_wp_db
   ```
3. Follow the interactive prompts

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
| **Revision cleanup** | Delete all post revisions before search-replace | Optional (Y/n) | High-speed bulk operation using xargs |
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
$ import_wp_db

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
✅ Multisite status: no

Clear ALL post revisions? (improves search-replace speed) (Y/n): y
🗑️ Clearing ALL Post Revisions (improves search-replace speed)...
🗑️ REVISION CLEANUP - STEP BY STEP
=====================================================

🧩 SINGLE SITE DETECTED - Processing main site only...
  Step A: Processing revisions for the main site

  🌍 Processing Main Site
     Revisions found: 4394
  ✅ Revisions deleted (WP-CLI reported success)


Include --all-tables (recommended for full DB imports)? (Y/n): y
✅ Will include all tables.

Run in dry-run mode (no data will be changed)? (y/N): n
🚀 Running in live mode (changes will be applied).

🧩 Single site detected.
Proceed with search-replace now? (Y/n): y

🔁 Running search-replace operations...
[Pass 1] Updating standard domain URLs: //example.com → //example.test
[Pass 3] Updating standard domain URLs (www): //www.example.com → //example.test
[Pass 2] Updating serialized domain URLs: \\//example.com → \\//example.test
[Pass 4] Updating serialized domain URLs (www): \\//www.example.com → \\//example.test

✅ Search-replace completed successfully!

🧹 Flushing WordPress and WP-CLI caches & transients...
  ✅ Object cache flushed.
  ✅ Rewrite rule flushed.
  ✅ All transients deleted.

🎉 All done! Database import and replacements completed successfully.

✅ Single site domain replacement completed via WP-CLI.

📸 Stage File Proxy Setup
Do you want to setup the stage file proxy plugin for media management? (Y/n): y
� stage-file-proxy plugin found! Configuring...
📦 Activating stage-file-proxy plugin...
✅ Plugin activated successfully
🧩 Configuring single site stage-file-proxy...
  ✅ Configured successfully: example.test (URL: https://www.example.com, Mode: header)
🎉 stage-file-proxy configuration complete!

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
$ import_wp_db

🔧 WordPress Database Import & Domain Replace Tool
---------------------------------------------------

📦 Enter SQL file name (default: vip-db.sql): multisite-production.sql
✅ WordPress root found: /Users/john/Sites/example-multisite/app/public

✅ Found SQL file: multisite-production.sql

🌍 Enter the OLD (production) domain to search for: https://admin.example.com/
🏠 Enter the NEW (local) domain/base URL to replace with: https://example.test/

� Cleaned search domain: 'https://admin.example.com/' → 'admin.example.com'
🧹 Cleaned replace domain: 'https://example.test/' → 'example.test'
�🧾 Summary:
    🔍 Search for:   admin.example.com
    🔄 Replace with: example.test

Proceed with database import? (Y/n): y

⏳ Importing database...
[2] 4185
  Importing \ (00:16)[2]  + 4185 done       /bin/sh -c
✅ Database import successful! [Completed in 00:16]

🔍 Checking WordPress installation type...
✅ Multisite detected via wp-config.php constants


Clear ALL post revisions? (improves search-replace speed) (Y/n): y
🗑️ Clearing ALL Post Revisions (improves search-replace speed)...
🗑️ REVISION CLEANUP - STEP BY STEP
=====================================================

🌐 MULTISITE DETECTED - Processing all subsites...
  Step A: Getting list of all sites in the network
  Found 6 sites to process:
    1. https://admin.example.com/
    2. https://shop.example.com/
    3. https://blog.example.com/
    4. https://news.example.com/
    5. https://support.example.com/
    6. https://docs.example.com/

  Step B: Processing revisions for each site individually

  🌍 Site 1/6: https://admin.example.com/
     Revisions found: 9
  ✅ Revisions deleted (WP-CLI reported success)

  🌍 Site 2/6: https://shop.example.com/
     Revisions found: 709
  ✅ Revisions deleted (WP-CLI reported success)

  🌍 Site 3/6: https://blog.example.com/
     Revisions found: 23
  ✅ Revisions deleted (WP-CLI reported success)

  🌍 Site 4/6: https://news.example.com/
     Revisions found: 2
  ✅ Revisions deleted (WP-CLI reported success)

  🌍 Site 5/6: https://support.example.com/
     Revisions found: 12
  ✅ Revisions deleted (WP-CLI reported success)

  🌍 Site 6/6: https://docs.example.com/
     Revisions found: 349
  ✅ Revisions deleted (WP-CLI reported success)


Include --all-tables (recommended for full DB imports)? (Y/n): y
✅ Will include all tables.

Run in dry-run mode (no data will be changed)? (y/N): n
🚀 Running in live mode (changes will be applied).

🌐 Multisite (subdomain) detected — gathering subsites for mapping...


✅ Found 6 subsites:
blog_id  domain                         path
1        admin.example.com              /
2        shop.example.com               /
3        blog.example.com               /
4        news.example.com               /
6        support.example.com            /
7        docs.example.com               /

🌐 Subdomain Multisite Detected
Each subsite has its own domain. Individual mapping input is required.

Enter the NEW URL/Domain for each site:
(Example: Map 'sub1.example.com' to 'sub1.example.local')


  Processing: Blog ID 1, Domain: 'admin.example.com', Path: '/'
→ Local URL for 'admin.example.com' (Blog ID 1): (example.test) example.test
  ✅ Added mapping: 'admin.example.com' → 'example.test' (ID: 1, Path: /)

  Processing: Blog ID 2, Domain: 'shop.example.com', Path: '/'
→ Local URL for 'shop.example.com' (Blog ID 2): example.test/shop
  ✅ Added mapping: 'shop.example.com' → 'example.test/shop' (ID: 2, Path: /)

  Processing: Blog ID 3, Domain: 'blog.example.com', Path: '/'
→ Local URL for 'blog.example.com' (Blog ID 3): example.test/blog
  ✅ Added mapping: 'blog.example.com' → 'example.test/blog' (ID: 3, Path: /)

  Processing: Blog ID 4, Domain: 'news.example.com', Path: '/'
→ Local URL for 'news.example.com' (Blog ID 4): example.test/news
  ✅ Added mapping: 'news.example.com' → 'example.test/news' (ID: 4, Path: /)

  Processing: Blog ID 6, Domain: 'support.example.com', Path: '/'
→ Local URL for 'support.example.com' (Blog ID 6): example.test/support
  ✅ Added mapping: 'support.example.com' → 'example.test/support' (ID: 6, Path: /)

  Processing: Blog ID 7, Domain: 'docs.example.com', Path: '/'
→ Local URL for 'docs.example.com' (Blog ID 7): example.test/docs
  ✅ Added mapping: 'docs.example.com' → 'example.test/docs' (ID: 7, Path: /)

🧾 Domain mapping summary:
    🔁 [ID: 1] admin.example.com/ → example.test
    🔁 [ID: 2] shop.example.com/ → example.test/shop
    🔁 [ID: 3] blog.example.com/ → example.test/blog
    🔁 [ID: 4] news.example.com/ → example.test/news
    🔁 [ID: 6] support.example.com/ → example.test/support
    🔁 [ID: 7] docs.example.com/ → example.test/docs

Proceed with search-replace for all sites? (Y/n): y

🔧 Updating wp_blogs and wp_site tables (before search-replace)...
================================================================

🔄 Executing wp_blogs and wp_site table updates via wp eval...

📝 Preparing wp_blogs updates for subsites...
  → Blog ID 2: shop.example.com → example.test/shop/
  → Blog ID 3: blog.example.com → example.test/blog/
  → Blog ID 4: news.example.com → example.test/news/
  → Blog ID 6: support.example.com → example.test/support/
  → Blog ID 7: docs.example.com → example.test/docs/

📝 Preparing wp_blogs update for main site (ID: 1)...
  → Blog ID 1: admin.example.com → example.test/

📝 Preparing wp_site update for network (ID: 1)...
  → Site ID 1: Network domain → example.test

⚡ Updating wp_blogs and wp_site tables...
✅ Database tables wp_blogs & wp_site updated successfully!
new_domain=example.test/docs
  ⏸️  Skipping Main Site (ID 1) - will process last.

➡️  Replacing for Site ID 2: shop.example.com/ → example.test/shop
[Pass 1] Updating standard domain URLs: //shop.example.com → //example.test/shop
[Pass 2] Updating serialized domain URLs: \\//shop.example.com → \\//example.test/shop
✅ Completed for shop.example.com/ (ID 2).

➡️  Replacing for Site ID 3: blog.example.com/ → example.test/blog
[Pass 1] Updating standard domain URLs: //blog.example.com → //example.test/blog
[Pass 2] Updating serialized domain URLs: \\//blog.example.com → \\//example.test/blog
✅ Completed for blog.example.com/ (ID 3).

➡️  Replacing for Site ID 4: news.example.com/ → example.test/news
[Pass 1] Updating standard domain URLs: //news.example.com → //example.test/news
[Pass 2] Updating serialized domain URLs: \\//news.example.com → \\//example.test/news
✅ Completed for news.example.com/ (ID 4).

➡️  Replacing for Site ID 6: support.example.com/ → example.test/support
[Pass 1] Updating standard domain URLs: //support.example.com → //example.test/support
[Pass 2] Updating serialized domain URLs: \\//support.example.com → \\//example.test/support
✅ Completed for support.example.com/ (ID 6).

➡️  Replacing for Site ID 7: docs.example.com/ → example.test/docs
[Pass 1] Updating standard domain URLs: //docs.example.com → //example.test/docs
[Pass 2] Updating serialized domain URLs: \\//docs.example.com → \\//example.test/docs
✅ Completed for docs.example.com/ (ID 7).

  MAIN SITE REPLACEMENT (ID = 1)

➡️  Replacing for Main Site ID 1: admin.example.com/ → example.test
[Pass 1] Updating standard domain URLs: //admin.example.com → //example.test
[Pass 2] Updating serialized domain URLs: \\//admin.example.com → \\//example.test
✅ Completed for Main Site (ID 1).

🧹 Flushing WordPress and WP-CLI caches & transients...
  ✅ Object cache flushed.
  ⚠️ Failed to flush rewrite rule (Not always necessary/available).
  ✅ All transients deleted.

🎉 All done! Database import and replacements completed successfully.


🚀 Database Migration Completed Successfully! (Tables updated automatically)

📸 Stage File Proxy Setup
Do you want to setup the stage file proxy plugin for media management? (Y/n): y
🔍 stage-file-proxy plugin found! Configuring...
📦 Activating stage-file-proxy plugin...
✅ Plugin activated successfully
🌐 Configuring multisite stage-file-proxy...
✅ Configuring 6 sites with stage-file-proxy
  ✅ Configured successfully: example.test (URL: https://admin.example.com, Mode: header)
  ✅ Configured successfully: example.test/shop (URL: https://shop.example.com, Mode: header)
  ✅ Configured successfully: example.test/blog (URL: https://blog.example.com, Mode: header)
  ✅ Configured successfully: example.test/news (URL: https://news.example.com, Mode: header)
  ✅ Configured successfully: example.test/support (URL: https://support.example.com, Mode: header)
  ✅ Configured successfully: example.test/docs (URL: https://docs.example.com, Mode: header)
🎉 stage-file-proxy configuration complete!

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
setup_stage_file_proxy
```

### Show Local Site Links
Display clickable links to local WordPress sites:

```bash
show_local_site_links
```

**Requirements:** Must be run from within a WordPress directory with WP-CLI installed

## 🛡️ Security Features

- Uses absolute paths to prevent directory traversal
- Validates all user inputs
- Sanitizes domain inputs
- Uses temporary files with process-specific names
- Prevents SQL injection in generated commands

## 📁 File Structure

- Creates temporary log files in `/tmp/` for debugging (uses PID to prevent collision)
- Automatically cleans up temporary files on exit
- Logs all WP-CLI operations for troubleshooting

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

## 🤝 Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## 📄 License

This project is licensed under the MIT License.

## 👨‍💻 Author

**Manish Songirkar** ([@manishsongirkar](https://github.com/manishsongirkar))
