# 📖 Usage Examples

**About This Demo Output**

This document showcases real-world terminal output examples from the WordPress Database Import & Domain Replacement Tool. Each example demonstrates the step-by-step process of importing a WordPress database, replacing domains, cleaning up revisions, mapping multisite domains, and setting up the Stage File Proxy plugin. Outputs reflect both single-site and multisite scenarios, including configuration prompts, automatic detection, and final site access links. Use these examples to preview the tool's workflow, understand expected prompts, and verify successful operations in your own environment.

**Table of Contents**

- [Single Site Example (First-Time Run)](#single-site-example-first-time-run)
- [Single Site Example (Subsequent Run with Config)](#single-site-example-subsequent-run-with-config)
- [Multisite Example (First-Time Setup)](#multisite-example-first-time-setup)
- [Multisite Example (Subsequent Run with Existing Config)](#multisite-example-subsequent-run-with-existing-config)
- [Revision Cleanup (Single)](#revision-cleanup-single)
- [Revision Cleanup (Multisite)](#revision-cleanup-multisite)
- [Show Links (Single)](#show-links-single)
- [Show Links (Multisite)](#show-links-multisite)


## Single Site Example (First-Time Run)

**Terminal Input/Output:**
```bash
$ wp-db-import
🚀 Starting WordPress database import...

✅ WordPress installation found: /Users/john/Sites/example-site/app/public

🔧 WordPress Database Import & Domain Replace Tool
====================================================

✅ WordPress root found: /Users/john/Sites/example-site/app/public
📝 No configuration file found.
💡 Creating new config: /Users/john/Sites/example-site/app/public/wpdb-import.conf

📦 Enter SQL file name (default: vip-db.sql): production-database.sql
✅ Found SQL file: production-database.sql
📊 File size: 133.03 MB

🌍 Enter the OLD (production) domain to search for: www.example.com
🏠 Enter the NEW (local) domain/base URL to replace with: example.test
📝 Creating configuration file...
✅ Configuration file created: /Users/john/Sites/example-site/app/public/wpdb-import.conf
✅ Configuration file created: wpdb-import.conf

🧾 Summary:
    🔍 Search for:   www.example.com
    🔄 Replace with: example.test

Proceed with database import? (Y/n): y

⏳ Importing database...
✅ Database import successful! [Completed in 00:07]

🔍 Validating domain configuration...
✅ Detected domain in database: www.example.com

🔍 Checking WordPress installation type...
✅ Single site installation detected via wp-cli

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

✅ Search-replace completed successfully!
💾 Saved domain mapping to config for future Stage File Proxy usage

🧹 Flushing WordPress and WP-CLI caches & transients...
  ✅ Object cache flushed.
  ✅ Rewrite rule flushed.
  ✅ All transients deleted.

🎉 All done! Database import and replacements completed successfully.

✅ Single site domain replacement completed via WP-CLI.

📸 Stage File Proxy Setup
Do you want to setup the stage file proxy plugin for media management? (Y/n): y

📸 Stage File Proxy Unified Setup
=== Unified Stage File Proxy Setup ===

✓ Stage File Proxy plugin already installed
✓ Domain mappings found - using automatic mode

=== Automatic Setup for Single Site ===
✓ Plugin activated successfully

 Site Configuration
 Source:      https://example.test
 Destination: https://www.example.com
 Mode:        header

 ✅ Configuration successful
 🎉 Stage File Proxy setup completed successfully!

================================================================
🌐 LOCAL SITE ACCESS LINKS
================================================================

✅ Your WordPress Single Site is ready:

  🏠 Frontend: https://example.test
  ⚙️  Admin:   https://example.test/wp-admin


================================================================

⏱️  Total Execution Time: 01:32 (mm:ss)
```

## Single Site Example (Subsequent Run with Config)

**Terminal Input/Output:**
```bash
$ wp-db-import
🚀 Starting WordPress database import...

✅ WordPress installation found: /Users/john/Sites/example-site/app/public

🔧 WordPress Database Import & Domain Replace Tool
====================================================

✅ WordPress root found: /Users/john/Sites/example-site/app/public
✅ Configuration found: /Users/john/Sites/example-site/app/public/wpdb-import.conf

📋  Using configuration settings...

📦 SQL file: production-database.sql (from config)
✅ Found SQL file: production-database.sql
📊 File size: 133.03 MB

🌍 OLD (production) domain: www.example.com (from config)
   Press Enter to use this domain, or type a new domain to override:
🏠 NEW (local) domain: example.test (from config)
   Press Enter to use this domain, or type a new domain to override:

🧾 Summary:
    🔍 Search for:   www.example.com
    🔄 Replace with: example.test

Proceed with database import? (Y/n): y

⏳ Importing database...
✅ Database import successful! [Completed in 00:04]

🔍 Validating domain configuration...
✅ Detected domain in database: www.example.com

🔍 Checking WordPress installation type...
✅ Single site installation detected via wp-cli

Clear ALL post revisions: enabled (from config)
   Press Enter to confirm, or 'n' to skip revision cleanup:
   ✅ Proceeding with revision cleanup
🗑️ Clearing ALL Post Revisions (improves search-replace speed)...
🗑️ REVISION CLEANUP - STEP BY STEP
=====================================================

🧩 SINGLE SITE DETECTED - Processing main site only...
  Step A: Processing revisions for the main site

  🌍 Processing Main Site
     Revisions found: 4394
  ✅ Revisions deleted (WP-CLI reported success)


Include --all-tables: enabled (from config)

Run in dry-run mode: live mode (from config)

🧩 Single site detected.
Proceed with search-replace now? (Y/n): y

🔁 Running search-replace operations...

✅ Search-replace completed successfully!
💾 Saved domain mapping to config for future Stage File Proxy usage

🧹 Flushing WordPress and WP-CLI caches & transients...
  ✅ Object cache flushed.
  ✅ Rewrite rule flushed.
  ✅ All transients deleted.

🎉 All done! Database import and replacements completed successfully.

✅ Single site domain replacement completed via WP-CLI.

📸 Stage File Proxy Setup
Setup stage file proxy: enabled (from config)

📸 Stage File Proxy Unified Setup
=== Unified Stage File Proxy Setup ===

✓ Stage File Proxy plugin already installed
✓ Domain mappings found - using automatic mode

=== Automatic Setup for Single Site ===
✓ Plugin activated successfully

 Site Configuration
 Source:      https://example.test
 Destination: https://www.example.com
 Mode:        header

 ✅ Configuration successful
 🎉 Stage File Proxy setup completed successfully!

================================================================
🌐 LOCAL SITE ACCESS LINKS
================================================================

✅ Your WordPress Single Site is ready:

  🏠 Frontend: https://example.test
  ⚙️  Admin:   https://example.test/wp-admin


================================================================

⏱️  Total Execution Time: 00:50 (mm:ss)
```

## Multisite Example (First-Time Setup)

**Terminal Input/Output:**
```bash
$ wp-db-import
🚀 Starting WordPress database import...

✅ WordPress installation found: /Users/john/Sites/example-multisite/app/public

🔧 WordPress Database Import & Domain Replace Tool
====================================================

✅ WordPress root found: /Users/john/Sites/example-multisite/app/public
📝 No configuration file found.
💡 Creating new config: /Users/john/Sites/example-multisite/app/public/wpdb-import.conf

📦 Enter SQL file name (default: vip-db.sql): production-domain.sql
✅ Found SQL file: production-domain.sql
📊 File size: 68.30 MB

🌍 Enter the OLD (production) domain to search for: https://example.com/
🏠 Enter the NEW (local) domain/base URL to replace with: https://example.test/
📝 Creating configuration file...
✅ Configuration file created: /Users/john/Sites/example-multisite/app/public/wpdb-import.conf
✅ Configuration file created: wpdb-import.conf

🧹 Cleaned search domain: 'https://example.com/' → 'example.com'
🧹 Cleaned replace domain: 'https://example.test/' → 'example.test'
🧾 Summary:
    🔍 Search for:   example.com
    🔄 Replace with: example.test

Proceed with database import? (Y/n): y

⏳ Importing database...
✅ Database import successful! [Completed in 00:07]

🔍 Validating domain configuration...
⚠️  Could not detect domain from database. Proceeding with provided domain.

🔍 Checking WordPress installation type...
✅ Multisite detected (subdirectory) via wp-config (blogs: 1, sites: 0)

Clear ALL post revisions? (improves search-replace speed) (Y/n): y
🗑️ Clearing ALL Post Revisions (improves search-replace speed)...
🗑️ REVISION CLEANUP - STEP BY STEP
=====================================================

🌐 MULTISITE DETECTED - Processing all subsites...
  Step A: Getting list of all sites in the network
  Found 6 sites to process:
    1. https://example.com/
    2. https://example.com/shop/
    3. https://example.com/blog/
    4. https://example.com/news/
    5. https://example.com/support/
    6. https://example.com/docs/

  Step B: Processing revisions for each site individually

  🌍 Site 1/6: https://example.com/
     Revisions found: 9
  ✅ Revisions deleted (WP-CLI reported success)

  🌍 Site 2/6: https://example.com/shop/
     Revisions found: 717
  ✅ Revisions deleted (WP-CLI reported success)

  🌍 Site 3/6: https://example.com/blog/
     Revisions found: 22
  ✅ Revisions deleted (WP-CLI reported success)

  🌍 Site 4/6: https://example.com/news/
     Revisions found: 2
  ✅ Revisions deleted (WP-CLI reported success)

  🌍 Site 5/6: https://example.com/support/
     Revisions found: 20
  ✅ Revisions deleted (WP-CLI reported success)

  🌍 Site 6/6: https://example.com/docs/
     Revisions found: 351
  ✅ Revisions deleted (WP-CLI reported success)


Include --all-tables (recommended for full DB imports)? (Y/n): y
✅ Will include all tables.

Run in dry-run mode (no data will be changed)? (y/N): n
🚀 Running in live mode (changes will be applied).

🌐 Multisite (subdirectory) detected — gathering subsites for mapping...

🔍 Detecting main site using WordPress database structure...
✅ Found main site via WP-CLI site list
✅ Main site detection complete: Blog ID 1 via wp-cli-site-list

✅ Main site detected: Blog ID 1, URL: https://example.com

✅ Found 6 subsites:
blog_id  domain                  path
1        example.com             /
2        example.com/shop        /
3        example.com/blog        /
4        example.com/news        /
6        example.com/support     /
7        example.com/docs        /

🌐 Subdirectory Multisite Detected
Using configuration-aware site mapping...


🗺️  Site Mapping Configuration
===============================

⚠️  Missing mappings for 6 sites:

  📍 Site 1
     🌐 Domain: example.com
     📁 Path:   /

     💡 Suggested URL: example.test
     🔗 Local URL: example.test

   ✔ Mapping confirmed:
     example.com → example.test
     (Blog ID: 1, Path: /)


  📍 Site 2
     🌐 Domain: example.com/shop
     📁 Path:   /

     💡 Suggested URL: example.test/shop
     🔗 Local URL: example.test/shop

   ✔ Mapping confirmed:
     example.com/shop → example.test/shop
     (Blog ID: 2, Path: /shop)


  📍 Site 3
     🌐 Domain: example.com/blog
     📁 Path:   /

     💡 Suggested URL: example.test/blog
     🔗 Local URL: example.test/blog

   ✔ Mapping confirmed:
     example.com/blog → example.test/blog
     (Blog ID: 3, Path: /blog)


  📍 Site 4
     🌐 Domain: example.com/news
     📁 Path:   /

     💡 Suggested URL: example.test/news
     🔗 Local URL: example.test/news

   ✔ Mapping confirmed:
     example.com/news → example.test/news
     (Blog ID: 4, Path: /news)


  📍 Site 6
     🌐 Domain: example.com/support
     📁 Path:   /

     💡 Suggested URL: example.test/support
     🔗 Local URL: example.test/support

   ✔ Mapping confirmed:
     example.com/support → example.test/support
     (Blog ID: 6, Path: /support)


  📍 Site 7
     🌐 Domain: example.com/docs
     📁 Path:   /

     💡 Suggested URL: example.test/docs
     🔗 Local URL: example.test/docs

   ✔ Mapping confirmed:
     example.com/docs → example.test/docs
     (Blog ID: 7, Path: /docs)


✅ Configuration updated with new site mappings

🧾 Domain Mapping Summary:

  Blog ID   Production Domain           → Local Domain
  -------   -----------------             ------------
  1    🏠   example.com                 → example.test
  2         example.com/shop            → example.test/shop
  3         example.com/blog            → example.test/blog
  4         example.com/news            → example.test/news
  6         example.com/support         → example.test/support
  7         example.com/docs            → example.test/docs

Proceed with search-replace for all sites? (Y/n): y

🔧 Updating wp_blogs and wp_site tables (before search-replace)...
================================================================

🔄 Executing wp_blogs and wp_site table updates via wp eval...

📝 Preparing wp_blogs updates for subsites...
  → Blog ID 2: example.com/shop → example.test/shop/
  → Blog ID 3: example.com/blog → example.test/blog/
  → Blog ID 4: example.com/news → example.test/news/
  → Blog ID 6: example.com/support → example.test/support/
  → Blog ID 7: example.com/docs → example.test/docs/

📝 Preparing wp_blogs update for main site (ID: 1)...
  → Blog ID 1: example.com → example.test/

📝 Preparing wp_site update for network (ID: 1)...
  → Site ID 1: Network domain → example.test

⚡ Updating wp_blogs and wp_site tables...
✅ Database tables wp_blogs & wp_site updated successfully!

🔄 SEARCH-REPLACE OPERATIONS
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

🌍 Site 2 Processing:
   From: example.com/shop
   To:   example.test/shop

   Step 1: ✅ Standard URL replacement complete
   Step 2: ✅ Serialized data replacement complete

🌍 Site 3 Processing:
   From: example.com/blog
   To:   example.test/blog

   Step 1: ✅ Standard URL replacement complete
   Step 2: ✅ Serialized data replacement complete

🌍 Site 4 Processing:
   From: example.com/news
   To:   example.test/news

   Step 1: ✅ Standard URL replacement complete
   Step 2: ✅ Serialized data replacement complete

🌍 Site 6 Processing:
   From: example.com/support
   To:   example.test/support

   Step 1: ✅ Standard URL replacement complete
   Step 2: ✅ Serialized data replacement complete

🌍 Site 7 Processing:
   From: example.com/docs
   To:   example.test/docs

   Step 1: ✅ Standard URL replacement complete
   Step 2: ✅ Serialized data replacement complete

🏠 Main Site Processing:
   From: example.com
   To:   example.test

   Step 1: ✅ Standard URL replacement complete
   Step 2: ✅ Serialized data replacement complete

🧹 Flushing WordPress and WP-CLI caches & transients...
  ✅ Object cache flushed.
  ✅ Rewrite rule flushed.
  ✅ All transients deleted.

🎉 All done! Database import and replacements completed successfully.

🚀 Database Migration Completed Successfully! (Tables updated automatically)

📸 Stage File Proxy Setup
Do you want to setup the stage file proxy plugin for media management? (Y/n): y

📸 Stage File Proxy Unified Setup
=== Unified Stage File Proxy Setup ===

✓ Stage File Proxy plugin already installed
✓ Domain mappings found - using automatic mode

=== Automatic Setup for Multisite ===
Activating Stage File Proxy plugin network-wide...
Cannot load Zend OPcache - it was already loaded
✓ Plugin activated network-wide successfully

Configuring sites automatically using existing mappings...

 Site Configuration (ID: 1)
 Source:      https://example.test
 Destination: https://example.com
 Mode:        header

 ✅ Configuration successful


 Site Configuration (ID: 2)
 Source:      https://example.test/shop
 Destination: https://example.com/shop
 Mode:        header

 ✅ Configuration successful


 Site Configuration (ID: 3)
 Source:      https://example.test/blog
 Destination: https://example.com/blog
 Mode:        header

 ✅ Configuration successful


 Site Configuration (ID: 4)
 Source:      https://example.test/news
 Destination: https://example.com/news
 Mode:        header

 ✅ Configuration successful


 Site Configuration (ID: 6)
 Source:      https://example.test/support
 Destination: https://example.com/support
 Mode:        header

 ✅ Configuration successful


 Site Configuration (ID: 7)
 Source:      https://example.test/docs
 Destination: https://example.com/docs
 Mode:        header

 ✅ Configuration successful


=== Automatic Multisite Setup Complete ===
Configured 6 out of 6 sites
 🎉 Stage File Proxy setup completed successfully!

================================================================
🌐 LOCAL SITE ACCESS LINKS
================================================================

✅ Your WordPress Multisite is ready (6 sites):

✅ Found main site via WP-CLI site list
✅ Main site detection complete: Blog ID 1 via wp-cli-site-list

  🏠 Main Site (ID: 1): https://example.test
  🌍 Subsite   (ID: 2): https://example.test/shop
  🌍 Subsite   (ID: 3): https://example.test/blog
  🌍 Subsite   (ID: 4): https://example.test/news
  🌍 Subsite   (ID: 6): https://example.test/support
  🌍 Subsite   (ID: 7): https://example.test/docs

💡 Network Admin: Add /wp-admin/network/ to any of the above URLs

================================================================

⏱️  Total Execution Time: 1:30 (mm:ss)
```

## Multisite Example (Subsequent Run with Existing Config)

**Terminal Input/Output:**
```bash
$ wp-db-import
🚀 Starting WordPress database import...

✅ WordPress installation found: /Users/john/Sites/example-multisite/app/public

🔧 WordPress Database Import & Domain Replace Tool
====================================================

✅ WordPress root found: /Users/john/Sites/example-multisite/app/public
✅ Configuration found: /Users/john/Sites/example-multisite/app/public/wpdb-import.conf

📋  Using configuration settings...

📦 SQL file: production-domain.sql (from config)
✅ Found SQL file: production-domain.sql
📊 File size: 68.30 MB

🌍 OLD (production) domain: example.com (from config)
   Press Enter to use this domain, or type a new domain to override:
🏠 NEW (local) domain: example.test (from config)
   Press Enter to use this domain, or type a new domain to override:

🧾 Summary:
    🔍 Search for:   example.com
    🔄 Replace with: example.test

Proceed with database import? (Y/n):

⏳ Importing database...
✅ Database import successful! [Completed in 00:10]

🔍 Validating domain configuration...
⚠️  Could not detect domain from database. Proceeding with provided domain.

🔍 Checking WordPress installation type...
✅ Multisite detected (subdirectory) via wp-config (blogs: 1, sites: 0)

Clear ALL post revisions: enabled (from config)
   Press Enter to confirm, or 'n' to skip revision cleanup:
   ✅ Proceeding with revision cleanup
🗑️ Clearing ALL Post Revisions (improves search-replace speed)...
🗑️ REVISION CLEANUP - STEP BY STEP
=====================================================

🌐 MULTISITE DETECTED - Processing all subsites...
  Step A: Getting list of all sites in the network
  Found 6 sites to process:
    1. https://example.com/
    2. https://example.com/shop/
    3. https://example.com/blog/
    4. https://example.com/news/
    5. https://example.com/support/
    6. https://example.com/docs/

  Step B: Processing revisions for each site individually

  🌍 Site 1/6: https://example.com/
     Revisions found: 9
  ✅ Revisions deleted (WP-CLI reported success)

  🌍 Site 2/6: https://example.com/shop/
     Revisions found: 717
  ✅ Revisions deleted (WP-CLI reported success)

  🌍 Site 3/6: https://example.com/blog/
     Revisions found: 22
  ✅ Revisions deleted (WP-CLI reported success)

  🌍 Site 4/6: https://example.com/news/
     Revisions found: 2
  ✅ Revisions deleted (WP-CLI reported success)

  🌍 Site 5/6: https://example.com/support/
     Revisions found: 20
  ✅ Revisions deleted (WP-CLI reported success)

  🌍 Site 6/6: https://example.com/docs/
     Revisions found: 351
  ✅ Revisions deleted (WP-CLI reported success)


Include --all-tables: enabled (from config)

Run in dry-run mode: live mode (from config)

🌐 Multisite (subdirectory) detected — gathering subsites for mapping...

🔍 Detecting main site using WordPress database structure...
✅ Found main site via WP-CLI site list
✅ Main site detection complete: Blog ID 1 via wp-cli-site-list

✅ Main site detected: Blog ID 1, URL: https://example.com

✅ Found 6 subsites:
blog_id  domain                    path
1        example.com               /
2        example.com/shop          /
3        example.com/blog          /
4        example.com/news          /
6        example.com/support       /
7        example.com/docs          /

🌐 Subdirectory Multisite Detected
Using configuration-aware site mapping...


🗺️  Site Mapping Configuration
===============================

✅ Found existing mappings for 6/6 sites:

  Blog ID  Production Domain             → Local Domain
  -------  -----------------               ------------
  1        example.com                   → example.test
  2        example.com/shop              → example.test/shop
  3        example.com/blog              → example.test/blog
  4        example.com/news              → example.test/news
  6        example.com/support           → example.test/support
  7        example.com/docs              → example.test/docs

🎉 All sites are already mapped! Proceeding with existing configuration.

🧾 Domain Mapping Summary:

  Blog ID   Production Domain            → Local Domain
  -------   -----------------              ------------
  1    🏠   example.com                  → example.test
  2         example.com/shop             → example.test/shop
  3         example.com/blog             → example.test/blog
  4         example.com/news             → example.test/news
  6         example.com/support          → example.test/support
  7         example.com/docs             → example.test/docs

Proceed with search-replace for all sites? (Y/n):

🔧 Updating wp_blogs and wp_site tables (before search-replace)...
================================================================

🔄 Executing wp_blogs and wp_site table updates via wp eval...

📝 Preparing wp_blogs updates for subsites...
  → Blog ID 2: example.com/shop → example.test/shop/
  → Blog ID 3: example.com/blog → example.test/blog/
  → Blog ID 4: example.com/news → example.test/news/
  → Blog ID 6: example.com/support → example.test/support/
  → Blog ID 7: example.com/docs → example.test/docs/

📝 Preparing wp_blogs update for main site (ID: 1)...
  → Blog ID 1: example.com → example.test/

📝 Preparing wp_site update for network (ID: 1)...
  → Site ID 1: Network domain → example.test

⚡ Updating wp_blogs and wp_site tables...
✅ Database tables wp_blogs & wp_site updated successfully!

🔄 SEARCH-REPLACE OPERATIONS
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

🌍 Site 2 Processing:
   From: example.com/shop
   To:   example.test/shop

   Step 1: ✅ Standard URL replacement complete
   Step 2: ✅ Serialized data replacement complete

🌍 Site 3 Processing:
   From: example.com/blog
   To:   example.test/blog

   Step 1: ✅ Standard URL replacement complete
   Step 2: ✅ Serialized data replacement complete

🌍 Site 4 Processing:
   From: example.com/news
   To:   example.test/news

   Step 1: ✅ Standard URL replacement complete
   Step 2: ✅ Serialized data replacement complete

🌍 Site 6 Processing:
   From: example.com/support
   To:   example.test/support

   Step 1: ✅ Standard URL replacement complete
   Step 2: ✅ Serialized data replacement complete

🌍 Site 7 Processing:
   From: example.com/docs
   To:   example.test/docs

   Step 1: ✅ Standard URL replacement complete
   Step 2: ✅ Serialized data replacement complete

🏠 Main Site Processing:
   From: example.com
   To:   example.test

   Step 1: ✅ Standard URL replacement complete
   Step 2: ✅ Serialized data replacement complete

🧹 Flushing WordPress and WP-CLI caches & transients...
  ✅ Object cache flushed.
  ✅ Rewrite rule flushed.
  ✅ All transients deleted.

🎉 All done! Database import and replacements completed successfully.

🚀 Database Migration Completed Successfully! (Tables updated automatically)

📸 Stage File Proxy Setup
Setup stage file proxy: enabled (from config)

📸 Stage File Proxy Unified Setup
=== Unified Stage File Proxy Setup ===

✓ Stage File Proxy plugin already installed
✓ Domain mappings found - using automatic mode

=== Automatic Setup for Multisite ===
Activating Stage File Proxy plugin network-wide...
Cannot load Zend OPcache - it was already loaded
✓ Plugin activated network-wide successfully

Configuring sites automatically using existing mappings...

 Site Configuration (ID: 1)
 Source:      https://example.test
 Destination: https://example.com
 Mode:        header

 ✅ Configuration successful


 Site Configuration (ID: 2)
 Source:      https://example.test/shop
 Destination: https://example.com/shop
 Mode:        header

 ✅ Configuration successful


 Site Configuration (ID: 3)
 Source:      https://example.test/blog
 Destination: https://example.com/blog
 Mode:        header

 ✅ Configuration successful


 Site Configuration (ID: 4)
 Source:      https://example.test/news
 Destination: https://example.com/news
 Mode:        header

 ✅ Configuration successful


 Site Configuration (ID: 6)
 Source:      https://example.test/support
 Destination: https://example.com/support
 Mode:        header

 ✅ Configuration successful


 Site Configuration (ID: 7)
 Source:      https://example.test/docs
 Destination: https://example.com/docs
 Mode:        header

 ✅ Configuration successful


=== Automatic Multisite Setup Complete ===
Configured 6 out of 6 sites
 🎉 Stage File Proxy setup completed successfully!

================================================================
🌐 LOCAL SITE ACCESS LINKS
================================================================

✅ Your WordPress Multisite is ready (6 sites):

✅ Found main site via WP-CLI site list
✅ Main site detection complete: Blog ID 1 via wp-cli-site-list

  🏠 Main Site (ID: 1): https://example.test
  🌍 Subsite   (ID: 2): https://example.test/shop
  🌍 Subsite   (ID: 3): https://example.test/blog
  🌍 Subsite   (ID: 4): https://example.test/news
  🌍 Subsite   (ID: 6): https://example.test/support
  🌍 Subsite   (ID: 7): https://example.test/docs

💡 Network Admin: Add /wp-admin/network/ to any of the above URLs

================================================================

⏱️  Total Execution Time: 01:15 (mm:ss)
```

## Revision Cleanup (Single)

```bash
$ wp-db-import show-cleanup

🗑️ Generating revision cleanup commands...

✅ WordPress installation found: /Users/john/Sites/example-site/app/public

================================================================
🧹 MYSQL COMMANDS FOR REVISION CLEANUP
================================================================

💡 These commands will permanently delete ALL post revisions from your database.
💡 Copy and paste these commands into phpMyAdmin → SQL tab or MySQL console.

✅ WordPress Single Site detected

📊 Site Information:
   Blog ID: 1 (Main Site) - Tables: wp_posts, wp_postmeta

🗂️  MySQL Commands for Single Site:

DELETE FROM `wp_postmeta` WHERE `post_id` in (SELECT ID FROM `wp_posts` WHERE `post_type` = 'revision');
DELETE FROM `wp_posts` WHERE `post_type` = 'revision';

================================================================
```

## Revision Cleanup (Multisite)

```bash
$ wp-db-import show-cleanup

🗑️ Generating revision cleanup commands...

✅ WordPress installation found: /Users/john/Sites/example-multisite/app/public

================================================================
🧹 MYSQL COMMANDS FOR REVISION CLEANUP
================================================================

💡 These commands will permanently delete ALL post revisions from your database.
💡 Copy and paste these commands into phpMyAdmin → SQL tab or MySQL console.

✅ WordPress Multisite detected (6 sites)

🗂️  MySQL Commands for Multisite:

-- Blog ID 1 (Main Site) - Tables: wp_posts, wp_postmeta
DELETE FROM `wp_postmeta` WHERE `post_id` in (SELECT ID FROM `wp_posts` WHERE `post_type` = 'revision');
DELETE FROM `wp_posts` WHERE `post_type` = 'revision';

-- Blog ID 2 (Subsite) - Tables: wp_2_posts, wp_2_postmeta
DELETE FROM `wp_2_postmeta` WHERE `post_id` in (SELECT ID FROM `wp_2_posts` WHERE `post_type` = 'revision');
DELETE FROM `wp_2_posts` WHERE `post_type` = 'revision';

-- Blog ID 3 (Subsite) - Tables: wp_3_posts, wp_3_postmeta
DELETE FROM `wp_3_postmeta` WHERE `post_id` in (SELECT ID FROM `wp_3_posts` WHERE `post_type` = 'revision');
DELETE FROM `wp_3_posts` WHERE `post_type` = 'revision';

-- Blog ID 4 (Subsite) - Tables: wp_4_posts, wp_4_postmeta
DELETE FROM `wp_4_postmeta` WHERE `post_id` in (SELECT ID FROM `wp_4_posts` WHERE `post_type` = 'revision');
DELETE FROM `wp_4_posts` WHERE `post_type` = 'revision';

-- Blog ID 6 (Subsite) - Tables: wp_6_posts, wp_6_postmeta
DELETE FROM `wp_6_postmeta` WHERE `post_id` in (SELECT ID FROM `wp_6_posts` WHERE `post_type` = 'revision');
DELETE FROM `wp_6_posts` WHERE `post_type` = 'revision';

-- Blog ID 7 (Subsite) - Tables: wp_7_posts, wp_7_postmeta
DELETE FROM `wp_7_postmeta` WHERE `post_id` in (SELECT ID FROM `wp_7_posts` WHERE `post_type` = 'revision');
DELETE FROM `wp_7_posts` WHERE `post_type` = 'revision';

================================================================
```

## Show Links (Single)

```bash
$ wp-db-import show-links
🔗 Displaying local site links...

✅ WordPress installation found: /Users/john/Sites/example-site/app/public

================================================================
🌐 LOCAL SITE ACCESS LINKS
================================================================

✅ Your WordPress Single Site is ready:

  🏠 Frontend: https://example.test
  ⚙️ Admin:    https://example.test/wp-admin


================================================================
```

## Show Links (Multisite)

```bash
$ wp-db-import show-links

🔗 Displaying local site links...

✅ WordPress installation found: /Users/john/Sites/example-multisite/app/public

================================================================
🌐 LOCAL SITE ACCESS LINKS
================================================================

✅ Your WordPress Multisite is ready (6 sites):

✅ Found main site via WP-CLI site list
✅ Main site detection complete: Blog ID 1 via wp-cli-site-list

  🏠 Main Site (ID: 1): https://example.test
  🌍 Subsite   (ID: 2): https://example.test/shop
  🌍 Subsite   (ID: 3): https://example.test/blog
  🌍 Subsite   (ID: 4): https://example.test/news
  🌍 Subsite   (ID: 6): https://example.test/support
  🌍 Subsite   (ID: 7): https://example.test/docs

💡 Network Admin: Add /wp-admin/network/ to any of the above URLs

================================================================
```
