# 🧩 WordPress Database Import & Domain Replacement Bash Script

A powerful **interactive Bash function** that automates importing a WordPress database dump (`.sql` file), performs **domain replacements**, handles **multisite setups**, and optionally **cleans post revisions** — all with color-coded feedback, safety prompts, and detailed logging.

---

## 🚀 Features

- ✅ Import `.sql` dump directly into your WordPress database 
- ✅ Interactive domain replacement (`old-domain → new-domain`) 
- ✅ Supports **multisite** and **single-site** WordPress installs 
- ✅ Optional **revision cleanup** for faster search-replace 
- ✅ Smart detection of WordPress root 
- ✅ Double-pass serialized data-safe replacements 
- ✅ Automatic log management in `/tmp/` 
- ✅ Safe exit traps and progress spinners 
- ✅ Optional **dry-run** mode (preview replacements) 
- ✅ Generates MySQL helper commands for manual use 

---

## 🧰 Requirements

| Requirement | Description |
|--------------|-------------|
| **Operating System** | Linux or macOS (Bash 4+) |
| **WP-CLI** | Installed and available in `$PATH` |
| **MySQL CLI** | Required for `wp db import` |
| **WordPress** | Standard installation (non-Bedrock) |
| **Permissions** | User must have DB import privileges |

Check your environment:
```bash
wp --info
mysql --version
bash --version
````

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
#    source "$HOME/wp-db-import-and-domain-replacement-tool/setup-stage-file-proxy.sh"
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

You’ll be guided step-by-step through the process:

1. Confirm SQL file (default: `vip-db.sql`)
2. Enter **old domain** (e.g., `production.com`)
3. Enter **new domain** (e.g., `local.test`)
4. Confirm import and replacement
5. (Optional) Clean post revisions
6. (Optional) Choose dry-run or all-tables mode
7. Wait for the process to complete 🎉

---

## 🧪 Example Terminal Session

### 🟢 Single-Site Example

```
$ import_wp_db

💾 Enter the SQL file name [vip-db.sql]: vip-db.sql
✅ WordPress installation detected.
🌐 Enter OLD domain (e.g., production.com): example.com
🌐 Enter NEW domain (e.g., local.test): example.local
⚠️ Confirm import and replacement from example.com → example.local? (Y/n): y
🔄 Importing database vip-db.sql...

✅ Database imported successfully.
🧹 Delete all post revisions before search-replace? (y/N): y
✅ Post revisions deleted successfully.

🧠 Perform dry-run first? (Y/n): y
💬 Running search-replace dry-run for example.com → example.local...
✅ Dry-run complete.

🧠 Proceed with actual replacement? (Y/n): y
🔍 Running search-replace pass 1...
🔍 Running search-replace pass 2...
✅ Replacement complete.

🧹 Flushing cache and rewrites...
✅ Done.

✨ All tasks complete. Logs saved in /tmp/wp_replace_single_12345.log
```

---

### 🟢 Multisite Example

```
$ import_wp_db

💾 Enter the SQL file name [vip-db.sql]: staging.sql
✅ Detected WordPress Multisite installation.
🌐 Enter OLD domain (e.g., production.com): example.com
🌐 Enter NEW domain (e.g., local.test): example.local
⚠️ Confirm import and replacement from example.com → example.local? (Y/n): y

🧠 Found 3 subsites:
  1) example.com/
  2) blog.example.com/
  3) shop.example.com/

Enter NEW domain for subsite 1 (example.com) [example.local]:
Enter NEW domain for subsite 2 (blog.example.com) [blog.local.test]:
Enter NEW domain for subsite 3 (shop.example.com) [shop.local.test]:

🔍 Processing site #1 (example.com)
✅ Replacement done.
🔍 Processing site #2 (blog.example.com)
✅ Replacement done.
🔍 Processing site #3 (shop.example.com)
✅ Replacement done.

✅ All subsites processed successfully.
🧹 Cache and rewrites flushed.
```

---

## ⚡ Options Overview

| Option               | Description                                   |
| -------------------- | --------------------------------------------- |
| **SQL filename**     | Defaults to `vip-db.sql`, or specify manually |
| **Old / New Domain** | Required — used for replacements              |
| **Revision cleanup** | Optional, improves search speed               |
| **Dry-run**          | Optional, safe preview mode                   |
| **All tables**       | Optional, includes non-WP prefixed tables     |
| **Multisite mode**   | Auto-detected, prompts per-site               |

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

| Problem                          | Cause                     | Solution                                                                     |
| -------------------------------- | ------------------------- | ---------------------------------------------------------------------------- |
| `❌ WP-CLI not found`             | WP-CLI not in PATH        | Install via `brew install wp-cli` or `composer global require wp-cli/wp-cli` |
| `❌ SQL file not found`           | Wrong filename or path    | Ensure `.sql` file exists in current directory                               |
| `❌ Not a WordPress installation` | Script not run in WP root | `cd` into the folder with `wp-config.php`                                    |
| `Error: database not found`      | Wrong DB credentials      | Check `wp-config.php`                                                        |
| Script stops midway              | Permissions / disk full   | Check `/tmp/` and DB user privileges                                         |

---

## 🛡️ Safety Recommendations

* Always **backup your database** before importing:

  ```bash
  wp db export backup-$(date +%F).sql
  ```
* Use **dry-run** for first-time replacements.
* Review generated logs before deleting them.

---

🟩 **Quick Start:**

```bash
cd ~
git clone https://github.com/manishsongirkar/wp-db-import-and-domain-replacement-tool.git

# Add this to ~/.bashrc or ~/.zshrc
if [ -f "$HOME/wp-db-import-and-domain-replacement-tool/import_wp_db.sh" ]; then
    source "$HOME/wp-db-import-and-domain-replacement-tool/import_wp_db.sh"
fi

# if [ -f "$HOME/wp-db-import-and-domain-replacement-tool/setup-stage-file-proxy.sh" ]; then
#     source "$HOME/wp-db-import-and-domain-replacement-tool/setup-stage-file-proxy.sh"
# fi

source ~/.bashrc
# OR
source ~/.zshrc

# Navigate to your WordPress project directory (where `wp-config.php` exists) and run:

import_wp_db
```

---
