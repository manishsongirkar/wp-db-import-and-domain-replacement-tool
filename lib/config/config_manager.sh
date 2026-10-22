#!/usr/bin/env bash

# ===============================================
# Configuration Manager for WordPress Import Tool
# ===============================================
#
# Description:
#   This module handles all aspects of the tool's INI-style configuration file,
#   including location finding, creation, parsing, validation, and updating
#   for both general settings and multisite mappings.
#
# Config File Location:
#   - Searches for 'wpdb-import.conf' in the WordPress root directory
#     (same directory as wp-config.php)
#
# Config File Format:
#   [general]
#   sql_file=production-database.sql
#   old_domain=mobility-admin.coxautoinc.com
#   new_domain=coxautoinc-mobility.test
#   all_tables=true
#   dry_run=false
#
#   [site_mappings]
#   # Format: blog_id:old_domain:new_domain
#   1:blog.example.com:example.test/blog
#   2:news.example.com:example.test/news
#   3:news.example.com:example.test/news
#
# ===============================================

# Global config file name (constant)
readonly CONFIG_FILE_NAME="wpdb-import.conf"

# ===============================================
# Find WP Root
# ===============================================
#
# Description: Searches up the directory tree to find the WordPress root directory.
#
# Parameters:
#	- None
#
# Returns:
#	- WordPress root path (echoed) on success
#	- Returns 1 if wp-config.php not found
#
# Behavior:
#	- Starts from current directory and moves up
#	- Looks for wp-config.php file
#	- Returns the directory containing wp-config.php
#
find_wp_root() {
    local current_dir="$(pwd)"
    local wp_root="$current_dir"

    # Search for wp-config.php up the directory tree
    while [[ "$wp_root" != "/" && ! -f "$wp_root/wp-config.php" ]]; do
        wp_root=$(dirname "$wp_root")
    done

    if [[ -f "$wp_root/wp-config.php" ]]; then
        echo "$wp_root"
        return 0
    else
        return 1
    fi
}

# ===============================================
# Get Config File Path
# ===============================================
#
# Description: Determines the full, expected path of the configuration file.
#
# Parameters:
#	- None
#
# Returns:
#	- Full config file path (echoed) on success
#	- Returns 1 if the WordPress root directory cannot be found
#
get_config_file_path() {
    local wp_root
    if wp_root=$(find_wp_root); then
        echo "$wp_root/$CONFIG_FILE_NAME"
        return 0
    else
        return 1
    fi
}

# ===============================================
# Config File Exists
# ===============================================
#
# Description: Checks if the configuration file is present at its expected location.
#
# Parameters:
#	- None
#
# Returns:
#	- 0 (Success) if the file exists
#	- 1 (Failure) if the file does not exist or WP root is not found
#
config_file_exists() {
    local config_path
    if config_path=$(get_config_file_path); then
        [[ -f "$config_path" ]]
    else
        return 1
    fi
}

# ===============================================
# Template of the optional [general] settings
# ===============================================
#
# Description: Prints the optional settings (socket, import optimizations, backup) with their
#              comments and defaults. Used for new config files, and by
#              ensure_socket_config_settings to add the comment of each key it adds.
#
config_general_settings_template() {
    cat <<'TEMPLATE_EOF'
# -----------------------------------------------
# MySQL Socket Settings (optional)
# -----------------------------------------------
# use_socket controls whether to attempt a Unix socket connection for
# the import. Socket connections bypass the TCP/IP stack and are
# significantly faster for local development environments.
#
# Values:
#   auto  — Auto-detect. Uses socket if available, falls back to WP-CLI (default)
#   true  — Always attempt socket import; error if socket not found
#   false — Disable socket import; always use WP-CLI
#
use_socket=auto

# mysql_socket allows you to pin a specific socket file path.
# Leave blank to let the tool auto-detect the socket path.
# Example: mysql_socket=/opt/homebrew/var/mysql/mysql.sock
mysql_socket=

# -----------------------------------------------
# Import Optimization Settings (optional)
# -----------------------------------------------
# import_optimizations controls whether session-level MySQL optimization
# flags are applied during direct mysql imports:
#   SET AUTOCOMMIT=0;
#   SET FOREIGN_KEY_CHECKS=0;
#   SET UNIQUE_CHECKS=0;
#
# Values:
#   auto  — Enable only for direct mysql/socket imports (default)
#   true  — Force-enable optimizations for direct mysql imports
#   false — Disable optimizations
#
import_optimizations=auto

# parallel_import remains disabled because generic SQL dumps are order-sensitive.
# Safe parallel loading requires table-chunked exports generated for parallel tools.
#
# Values:
#   false — Disabled (default)
#   true  — Reserved for future specialized workflows
#
parallel_import=false

# -----------------------------------------------
# Pre-Import Backup (recommended)
# -----------------------------------------------
# backup_before_import saves a compressed copy of the CURRENT database before
# it is replaced, so a bad import can be undone. If a requested backup fails, the
# import is cancelled to protect your data.
#
# Values:
#   ask   — Ask before each import (Y/n, default Yes). Answering "n" saves false here.
#           Unattended runs (auto_proceed=true) back up without asking. (default)
#   true  — Always back up, never ask
#   false — Never back up, never ask
#
backup_before_import=ask

# backup_dir is where backups are stored (created with mode 700, files 600).
# Leave blank for the default: ~/.wp-db-import/backups
# Restore with:  gunzip -c <backup-file> | wp db import -
backup_dir=

# backup_keep is the number of backups to keep per database. After each new backup the
# oldest ones beyond this number are deleted (rotation), so the folder cannot grow forever.
# Use 0 to keep every backup.
backup_keep=5

# backup_keep_days also deletes backups older than this many days (in addition to
# backup_keep). The backup just made is never deleted. Use 0 to turn it off.
backup_keep_days=0

# backup_encrypt encrypts new backups with GnuPG (the file name ends in .sql.gz.gpg).
#
# Values:
#   false — Off (default): backups are gzip files, readable by the owner only (mode 600)
#   gpg   — Encrypt with the public key named in backup_gpg_recipient. If gpg or the key
#           is missing, the backup (and so the import) is cancelled. It never falls back
#           to an unencrypted file.
#
# Restore: wp-db-import restore <file>.sql.gz.gpg   (gpg asks for your passphrase)
backup_encrypt=false

# backup_gpg_recipient is the key id, fingerprint or e-mail of the public key to encrypt to.
backup_gpg_recipient=

# -----------------------------------------------
# Search-Replace Settings (optional)
# -----------------------------------------------
# skip_tables lists tables the replacement must NOT touch (WP-CLI --skip-tables). Use it for
# custom tables that hold data in a format WP-CLI cannot read safely. Separate names with
# commas; * and ? are wildcards. Leave blank to skip none (default).
# Example: skip_tables=wp_custom_cache,wp_logs_*
skip_tables=

# precise makes WP-CLI do the replacement in PHP (--precise): slower, but it also fixes
# serialized or JSON data that is in a non-standard format (some custom tables).
#
# Values:
#   false — WP-CLI default (default)
#   true  — Pass --precise to every search-replace call
precise=false

# -----------------------------------------------
# Dry-Run Guard (optional)
# -----------------------------------------------
# require_dry_run makes the tool REFUSE a live import unless a dry run of the same dump
# (same file, size and modification time), domains and mappings finished in the last
# require_dry_run_hours hours. The dry run writes a small stamp file in a private folder
# outside the project (~/.wp-db-import/dry-run-stamps). Ignored when --dry-run is used.
# For CI, run `wp-db-import --dry-run` and then `wp-db-import --yes` in the same job.
#
# Values:
#   false — No check (default)
#   true  — Refuse a live import without a fresh dry run
require_dry_run=false

# require_dry_run_hours is how long a finished dry run stays valid (a whole number, 1 or more).
require_dry_run_hours=24

# -----------------------------------------------
# Import SQL Mode (optional)
# -----------------------------------------------
# Dumps with zero dates (DEFAULT '0000-00-00 00:00:00') fail on a server whose sql_mode has
# NO_ZERO_DATE / NO_ZERO_IN_DATE (ERROR 1067 / 1292). import_sql_mode decides what the tool does.
# Only the import connection is changed; the server's own sql_mode is never changed.
#
# Values:
#   auto  — Import as before. If it fails with a zero-date error, retry once with NO_ZERO_DATE
#           and NO_ZERO_IN_DATE switched off for that session (default)
#   keep  — Never change the session sql_mode
#   <list> — Use this sql_mode for the import session, for example NO_AUTO_VALUE_ON_ZERO
import_sql_mode=auto

# -----------------------------------------------
# Post-Import Report (optional)
# -----------------------------------------------
# import_report prints a summary after a live import and saves it as wpdb-import-report.txt
# next to this file (mode 600): replacements per table, serialized-aware replacements, tables
# WP-CLI skipped, errors, the old domain still found in the database, and the time per step.
# The check for the old domain reads the whole database once, so set false to skip the report.
import_report=true

# report_keep is the number of reports to keep. Older ones are renamed
# wpdb-import-report.<date>.txt and the oldest beyond this number are deleted. Use 0 to keep all.
report_keep=5
TEMPLATE_EOF
}

# Prints the comment block above one key of the template (nothing if the key has none)
config_key_comment() {
    config_general_settings_template | awk -v key="$1" '
        /^[[:space:]]*$/ { buf = ""; next }
        $0 ~ "^" key "=" { printf "%s", buf; exit }
        { buf = buf $0 "\n" }'
}

# ===============================================
# Template of the custom URL mapping sections
# ===============================================
#
# Description: Prints the [domain_mappings] and [site_domain_mappings] sections (comments only).
#              Used for new config files and added to existing ones by ensure_socket_config_settings.
#
config_mapping_sections_template() {
    cat <<'TEMPLATE_EOF'
[domain_mappings]
# Extra search => replace pairs for URLs that must not reach staging or local
# (CDN hosts, third-party APIs, a www variant). Works for single sites and multisite
# (applied to the whole network). One pair per line, "old => new".
#
# The search MUST start with // or http:// or https:// (a bare host would also match emails).
#   //cdn.example.com => //cdn.target.test            http, https and protocol-relative URLs
#   https://api.example.com/v2 => https://api.sandbox.example.net/v2   this exact text only
#   //www.example.com => //target.test                www variant when old_domain has no www
# A //host search needs a //newhost replacement. Longest search runs first, before old_domain.
# End a search with / to match the exact host (//example.com/ does not match //example.com.au).

[site_domain_mappings]
# Multisite only: pairs for ONE site, "blog_id: old => new"
#   2: //shop-cdn.example.com => //shop-cdn.target.test
TEMPLATE_EOF
}

# ===============================================
# Create Config File
# ===============================================
#
# Description: Creates a new configuration file with a basic structure and default settings.
#
# Parameters:
#	- $1: Path where the config file should be created.
#	- $2: Optional. Default SQL file name.
#	- $3: Optional. Default old domain.
#	- $4: Optional. Default new domain.
#
# Returns:
#	- 0 (Success) on successful creation
#	- 1 (Failure) on error
#
create_config_file() {
    local config_path="$1"
    local sql_file="${2:-vip-db.sql}"
    local old_domain="$(sanitize_domain "${3:-}")"
    local new_domain="$(sanitize_domain "${4:-}")"

    cat > "$config_path" << EOF
# ===============================================
# WordPress Database Import Configuration
# ===============================================
# This file stores your import settings to avoid re-entering them each time.
# Edit this file to customize your import settings.

[general]
sql_file=$sql_file
old_domain=$old_domain
new_domain=$new_domain
all_tables=true
dry_run=false
clear_revisions=true
setup_stage_proxy=true
auto_proceed=false

$(config_general_settings_template)

[site_mappings]
# Format:
# blog_id:old_domain:new_domain

# Example:
# 1:production-site.com:local-site.test

# Add your multisite mappings below:

$(config_mapping_sections_template)

EOF

    if [[ $? -eq 0 ]]; then
        printf "${GREEN}✅ Configuration file created: ${CYAN}%s${RESET}\n" "$config_path"
        return 0
    else
        printf "${RED}❌ Failed to create configuration file: %s${RESET}\n" "$config_path"
        return 1
    fi
}

# ===============================================
# Parse Config Section
# ===============================================
#
# Description: Extracts the value of a specific key within a specific INI section.
#
# Parameters:
#	- $1: Path to the config file.
#	- $2: The INI section name (e.g., "general"). Case-insensitive.
#	- $3: The key name (e.g., "sql_file"). Case-insensitive.
#
# Returns:
#	- The value of the key (echoed)
#	- Returns 1 if the config file does not exist
#
parse_config_section() {
    local config_path="$1"
    local section="$2"
    local key="$3"

    if [[ ! -f "$config_path" ]]; then
        return 1
    fi

    # Use awk to parse INI-style config. Section and key names are matched without regard to case and
    # surrounding spaces, in every awk (IGNORECASE is gawk only; macOS awk would read nothing for [General]).
    # The first match wins.
    awk -v section="$section" -v key="$key" '
        function trim(s) { gsub(/^[ \t]+|[ \t]+$/, "", s); return s }
        BEGIN { in_section = 0; section = tolower(section); key = tolower(key) }
        /^[[:space:]]*\[.*\]/ {
            h = tolower(trim($0))
            sub(/\][ \t]*[#;].*$/, "]", h)
            in_section = (h == "[" section "]")
            next
        }
        in_section && !/^[[:space:]]*[#;]/ && index($0, "=") {
            # (comment lines are skipped: "# Example: mysql_socket=/path" is not a setting;
            #  the whole key must match: "require_dry_run=true" is not "dry_run")
            eq = index($0, "=")
            if (tolower(trim(substr($0, 1, eq - 1))) == key) {
                print trim(substr($0, eq + 1))
                exit
            }
        }
    ' "$config_path"
}

# ===============================================
# Get Site Mappings
# ===============================================
#
# Description: Extracts all valid site mapping entries from the [site_mappings] section.
#
# Parameters:
#	- $1: Path to the config file.
#
# Returns:
#	- A list of all site mapping lines (e.g., "1:old.com:new.test"), one per line (echoed)
#	- Returns 1 if the config file does not exist
#
get_site_mappings() {
    local config_path="$1"

    if [[ ! -f "$config_path" ]]; then
        return 1
    fi

    # Parse site_mappings section
    awk '
        BEGIN {
            in_section = 0
            IGNORECASE = 1
        }
        /^\[.*\]/ {
            if ($0 ~ "\\[site_mappings\\]") {
                in_section = 1
            } else {
                in_section = 0
            }
            next
        }
        in_section && /^[[:space:]]*[0-9]+:/ && !/^[[:space:]]*#/ {
            sub(/^[[:space:]]+/, "")  # Remove leading whitespace
            sub(/[[:space:]]+$/, "")  # Remove trailing whitespace
            print $0
        }
    ' "$config_path"
}

# ===============================================
# Get Site Mapping
# ===============================================
#
# Description: Retrieves the new domain for a specific blog ID from site mappings.
#
# Parameters:
#	- $1: Path to the config file.
#	- $2: The Blog ID (e.g., "1").
#
# Returns:
#	- The new domain string (echoed)
#	- Returns 1 if the mapping or config file is not found
#
get_site_mapping() {
    local config_path="$1"
    local blog_id="$2"

    if [[ ! -f "$config_path" ]]; then
        return 1
    fi

    # Get all mappings and filter for specific blog_id
    get_site_mappings "$config_path" | while IFS=':' read -r map_blog_id old_domain new_domain; do
        if [[ "$map_blog_id" == "$blog_id" ]]; then
            echo "$new_domain"
            return 0
        fi
    done

    return 1
}

# ===============================================
# Update Site Mapping
# ===============================================
#
# Description: Adds a new site mapping or updates an existing one for a given blog ID.
#
# Parameters:
#	- $1: Path to the config file.
#	- $2: The Blog ID (key for the mapping).
#	- $3: The old domain.
#	- $4: The new domain.
#
# Returns:
#	- 0 (Success) on successful update/add
#	- 1 (Failure) on error or if the config file is not found
#
update_site_mapping() {
    local config_path="$1"
    local blog_id="$2"
    local old_domain="$3"
    local new_domain="$4"

    if [[ ! -f "$config_path" ]]; then
        return 1
    fi

    local mapping_line="${blog_id}:${old_domain}:${new_domain}"
    local temp_file="$config_path.tmp"

    # Check if the mapping already exists
    # Only [site_mappings] counts: "2: //old => //new" in [site_domain_mappings] is not a site mapping
    if get_site_mappings "$config_path" 2>/dev/null | grep -q "^[[:space:]]*${blog_id}:"; then
        # Update existing mapping
        awk -v blog_id="$blog_id" -v new_mapping="$mapping_line" '
            BEGIN {
                in_section = 0
                updated = 0
                IGNORECASE = 1
            }
            /^\[.*\]/ {
                if ($0 ~ "\\[site_mappings\\]") {
                    in_section = 1
                } else {
                    in_section = 0
                }
                print $0
                next
            }
            in_section && $0 ~ "^[[:space:]]*" blog_id ":" {
                print new_mapping
                updated = 1
                next
            }
            { print $0 }
        ' "$config_path" > "$temp_file"
    else
        # Add new mapping
        awk -v blog_id="$blog_id" -v new_mapping="$mapping_line" '
            BEGIN {
                in_section = 0
                added = 0
                IGNORECASE = 1
            }
            /^\[.*\]/ {
                if ($0 ~ "\\[site_mappings\\]") {
                    in_section = 1
                    print $0
                    next
                } else if (in_section && !added) {
                    print new_mapping
                    added = 1
                    in_section = 0
                }
                print $0
                next
            }
            { print $0 }
            END {
                if (!added && in_section) {
                    print new_mapping
                }
            }
        ' "$config_path" > "$temp_file"
    fi

    if [[ -f "$temp_file" ]]; then
        # cat keeps the file's mode and owner (mv would replace them with the temp file's)
        cat "$temp_file" > "$config_path" && rm -f "$temp_file"
        return 0
    else
        return 1
    fi
}

# ===============================================
# Update Config General
# ===============================================
#
# Description: Updates a single key-value pair within the [general] section.
#
# Parameters:
#	- $1: Path to the config file.
#	- $2: The key name to update.
#	- $3: The new value for the key.
#
# Returns:
#	- 0 (Success) on successful update/add
#	- 1 (Failure) on error or if the config file is not found
#
update_config_general() {
    local config_path="$1"
    local key="$2"
    local value="$3"
    local comment="${4:-}"   # optional: comment lines written above the key when it is ADDED

    # Sanitize domains if the key is old_domain or new_domain
    if [[ "$key" == "old_domain" || "$key" == "new_domain" ]]; then
        value="$(sanitize_domain "$value")"
    fi

    if [[ ! -f "$config_path" ]]; then
        return 1
    fi

    local temp_file="$config_path.tmp"

    WPDB_CFG_COMMENT="$comment" awk -v key="$key" -v value="$value" '
        # blank lines at the end of [general] are held back, so an added key (with its comment)
        # lands right after the last setting and the blank lines stay in front of the next section
        function flush() { while (pend > 0) { print ""; pend-- } }
        function trim(s) { gsub(/^[ \t]+|[ \t]+$/, "", s); return s }
        function add_key() {
            if (comment != "") { print ""; print comment }
            print key "=" value
            flush()
        }
        BEGIN {
            in_section = 0
            updated = 0
            pend = 0
            lkey = tolower(key)
            comment = ENVIRON["WPDB_CFG_COMMENT"]
        }
        /^[[:space:]]*\[.*\]/ {
            h = tolower(trim($0))
            sub(/\][ \t]*[#;].*$/, "]", h)
            if (h == "[general]") {
                in_section = 1
            } else {
                if (in_section) {
                    if (!updated) { add_key(); updated = 1 } else { flush() }
                }
                in_section = 0
            }
            print $0
            next
        }
        in_section && /^[[:space:]]*$/ { pend++; next }
        in_section && !/^[[:space:]]*[#;]/ && index($0, "=") && tolower(trim(substr($0, 1, index($0, "=") - 1))) == lkey {
            flush()
            print key "=" value
            updated = 1
            next
        }
        { if (in_section) flush(); print $0 }
        END {
            if (in_section) {
                if (!updated) { add_key() } else { flush() }
            }
        }
    ' "$config_path" > "$temp_file"

    if [[ -f "$temp_file" ]]; then
        # cat keeps the file's mode and owner (mv would replace them with the temp file's)
        cat "$temp_file" > "$config_path" && rm -f "$temp_file"
        return 0
    else
        return 1
    fi
}

# ===============================================
# Ensure Import Config Settings Exist
# ===============================================
#
# Description: Updates an existing config file with import settings if they are
#              missing from the [general] section.
#
# Parameters:
#	- $1: Path to the config file.
#
# Returns:
#	- 0 (Success) if the config already had the settings or was updated.
#	- 1 (Failure) if the config file does not exist or an update fails.
#
ensure_socket_config_settings() {
    local config_path="$1"
    local updated=false

    CONFIG_SOCKET_SETTINGS_MIGRATED="false"
    CONFIG_SETTINGS_MIGRATED_ITEMS=""

    if [[ ! -f "$config_path" ]]; then
        return 1
    fi

    # key=default pairs added to configs created before these settings existed
    local pair key default
    for pair in "use_socket=auto" "mysql_socket=" "import_optimizations=auto" \
                "parallel_import=false" "backup_before_import=ask" "backup_dir=" "backup_keep=5" \
                "backup_keep_days=0" "backup_encrypt=false" "backup_gpg_recipient=" \
                "skip_tables=" "precise=false" \
                "require_dry_run=false" "require_dry_run_hours=24" \
                "import_sql_mode=auto" "import_report=true" "report_keep=5"; do
        key="${pair%%=*}"
        default="${pair#*=}"
        if ! grep -qi "^[[:space:]]*${key}[[:space:]]*=" "$config_path" 2>/dev/null; then
            if ! update_config_general "$config_path" "$key" "$default" "$(config_key_comment "$key")"; then
                return 1
            fi
            updated=true
            CONFIG_SETTINGS_MIGRATED_ITEMS="${CONFIG_SETTINGS_MIGRATED_ITEMS:+$CONFIG_SETTINGS_MIGRATED_ITEMS, }${key}"
        fi
    done

    # Sections added in later versions: appended at the end (comments only, no active entry),
    # so nothing that is already in the file is moved or changed
    local sec missing=""
    for sec in domain_mappings site_domain_mappings; do
        if ! grep -qi "^[[:space:]]*\\[[[:space:]]*${sec}[[:space:]]*\\]" "$config_path" 2>/dev/null; then
            missing="${missing:+$missing }${sec}"
        fi
    done
    if [[ -n "$missing" ]]; then
        {
            # a file without a final newline: finish its last line first
            [[ -s "$config_path" && -n "$(tail -c1 "$config_path" 2>/dev/null)" ]] && printf "\n"
            for sec in $missing; do
                printf "\n"
                config_mapping_sections_template | awk -v want="[$sec]" '
                    /^\[.*\]/ { on = ($0 == want) }
                    on && /^[[:space:]]*$/ { pend++; next }
                    on { while (pend > 0) { print ""; pend-- }; print }'
            done
        } >> "$config_path" 2>/dev/null || return 1
        updated=true
        for sec in $missing; do
            CONFIG_SETTINGS_MIGRATED_ITEMS="${CONFIG_SETTINGS_MIGRATED_ITEMS:+$CONFIG_SETTINGS_MIGRATED_ITEMS, }[$sec]"
        done
    fi

    if [[ "$updated" == "true" ]]; then
        CONFIG_SOCKET_SETTINGS_MIGRATED="true"
    fi

    return 0
}

# ===============================================
# Validate Config File
# ===============================================
#
# Description: Checks the config file for the presence of required sections and general settings.
#
# Parameters:
#	- $1: Path to the config file.
#
# Returns:
#	- 0 (Success) if the config is valid
#	- 1 (Failure) if validation fails (prints specific errors)
#
validate_config_file() {
    local config_path="$1"
    local errors=()

    if [[ ! -f "$config_path" ]]; then
        echo "Config file does not exist: $config_path"
        return 1
    fi

    # Check for required sections
    if ! grep -q '^\[general\]' "$config_path" 2>/dev/null; then
        errors+=("Missing [general] section")
    fi

    if ! grep -q '^\[site_mappings\]' "$config_path" 2>/dev/null; then
        errors+=("Missing [site_mappings] section")
    fi

    # Check for required general settings
    local sql_file old_domain new_domain all_tables dry_run clear_revisions setup_stage_proxy auto_proceed
    sql_file=$(parse_config_section "$config_path" "general" "sql_file")
    old_domain=$(parse_config_section "$config_path" "general" "old_domain")
    new_domain=$(parse_config_section "$config_path" "general" "new_domain")
    all_tables=$(parse_config_section "$config_path" "general" "all_tables")
    dry_run=$(parse_config_section "$config_path" "general" "dry_run")
    clear_revisions=$(parse_config_section "$config_path" "general" "clear_revisions")
    setup_stage_proxy=$(parse_config_section "$config_path" "general" "setup_stage_proxy")
    auto_proceed=$(parse_config_section "$config_path" "general" "auto_proceed")

    # dry_run: a bad value would start a live import
    case "$(printf '%s' "$dry_run" | tr '[:upper:]' '[:lower:]')" in
        ""|true|false|yes|no|1|0|on|off) ;;
        *) errors+=("dry_run: '$dry_run' is not true or false") ;;
    esac

    # skip_tables and precise: report every bad value
    if declare -F sr_validate_settings >/dev/null 2>&1; then
        local sr_line
        while IFS= read -r sr_line; do
            [[ -n "$sr_line" ]] && errors+=("$sr_line")
        done < <(sr_validate_settings "$(parse_config_section "$config_path" "general" "skip_tables")" "$(parse_config_section "$config_path" "general" "precise")")
    fi

    # require_dry_run and require_dry_run_hours: a bad value would switch the guard off or lock every live run
    local rdr rdh
    rdr=$(parse_config_section "$config_path" "general" "require_dry_run" | tr '[:upper:]' '[:lower:]')
    rdh=$(parse_config_section "$config_path" "general" "require_dry_run_hours")
    case "$rdr" in
        ""|true|false|yes|no|1|0|on|off) ;;
        *) errors+=("require_dry_run: '$rdr' is not true or false") ;;
    esac
    if [[ -n "$rdh" ]] && { [[ ! "$rdh" =~ ^[0-9]{1,5}$ ]] || [[ "$((10#$rdh))" -lt 1 ]]; }; then
        errors+=("require_dry_run_hours: '$rdh' is not a whole number of hours (1 or more)")
    fi

    # import_sql_mode, import_report, report_keep
    local ism irp rpk ism_why
    ism=$(parse_config_section "$config_path" "general" "import_sql_mode")
    if declare -F import_sql_mode_validate >/dev/null 2>&1 && ! ism_why=$(import_sql_mode_validate "$ism"); then
        errors+=("$ism_why")
    fi
    irp=$(parse_config_section "$config_path" "general" "import_report" | tr '[:upper:]' '[:lower:]')
    case "$irp" in
        ""|true|false|yes|no|1|0|on|off) ;;
        *) errors+=("import_report: '$irp' is not true or false") ;;
    esac
    rpk=$(parse_config_section "$config_path" "general" "report_keep")
    if [[ -n "$rpk" && ! "$rpk" =~ ^[0-9]+$ ]]; then
        errors+=("report_keep: '$rpk' is not a whole number (0 keeps every report)")
    fi

    # Custom URL mappings: report every invalid entry
    if declare -F dm_load >/dev/null 2>&1; then
        local dm_line
        dm_load "$config_path" "domain_mappings" || while IFS= read -r dm_line; do [[ -n "$dm_line" ]] && errors+=("[domain_mappings] $dm_line"); done <<< "$DM_ERRORS"
        dm_load "$config_path" "site_domain_mappings" || while IFS= read -r dm_line; do [[ -n "$dm_line" ]] && errors+=("[site_domain_mappings] $dm_line"); done <<< "$DM_ERRORS"
    fi

    [[ -z "$sql_file" ]] && errors+=("Missing or empty sql_file setting")
    [[ -z "$old_domain" ]] && errors+=("Missing or empty old_domain setting")
    [[ -z "$new_domain" ]] && errors+=("Missing or empty new_domain setting")

    # Output errors if any
    if [[ ${#errors[@]} -gt 0 ]]; then
        printf "${RED}❌ Configuration validation failed:${RESET}\n"
        for error in "${errors[@]}"; do
            printf "   - %s\n" "$error"
        done
        return 1
    fi

    printf "${GREEN}✅ Configuration file is valid${RESET}\n"
    return 0
}

# ===============================================
# Show Config
# ===============================================
#
# Description: Displays the config file contents in a colorized, user-friendly format.
#
# Parameters:
#	- $1: Path to the config file.
#
# Returns:
#	- 0 (Success) on successful display
#	- 1 (Failure) if the config file is not found
#
show_config() {
    local config_path="$1"

    if [[ ! -f "$config_path" ]]; then
        printf "${RED}❌ Config file not found: %s${RESET}\n" "$config_path"
        return 1
    fi

    printf "${CYAN}${BOLD}📋 Current Configuration${RESET}\n"
    printf "==========================\n"
    printf "Config file: ${YELLOW}%s${RESET}\n\n" "$config_path"

    # Display general settings
    printf "${BOLD}General Settings:${RESET}\n"
    local sql_file old_domain new_domain all_tables dry_run clear_revisions setup_stage_proxy auto_proceed
    sql_file=$(parse_config_section "$config_path" "general" "sql_file")
    old_domain=$(parse_config_section "$config_path" "general" "old_domain")
    new_domain=$(parse_config_section "$config_path" "general" "new_domain")
    all_tables=$(parse_config_section "$config_path" "general" "all_tables")
    dry_run=$(parse_config_section "$config_path" "general" "dry_run")
    clear_revisions=$(parse_config_section "$config_path" "general" "clear_revisions")
    setup_stage_proxy=$(parse_config_section "$config_path" "general" "setup_stage_proxy")
    auto_proceed=$(parse_config_section "$config_path" "general" "auto_proceed")

    printf "  SQL File:          ${GREEN}%s${RESET}\n" "${sql_file:-not set}"
    printf "  Old Domain:        ${YELLOW}%s${RESET}\n" "${old_domain:-not set}"
    printf "  New Domain:        ${GREEN}%s${RESET}\n" "${new_domain:-not set}"
    printf "  All Tables:        ${CYAN}%s${RESET}\n" "${all_tables:-false}"
    printf "  Dry Run:           ${CYAN}%s${RESET}\n" "${dry_run:-false}"
    printf "  Clear Revisions:   ${CYAN}%s${RESET}\n" "${clear_revisions:-true}"
    printf "  Setup Stage Proxy: ${CYAN}%s${RESET}\n" "${setup_stage_proxy:-true}"
    printf "  Auto Proceed:      ${CYAN}%s${RESET}\n" "${auto_proceed:-false}"
    printf "  Skip Tables:       ${CYAN}%s${RESET}\n" "$(parse_config_section "$config_path" "general" "skip_tables" | grep . || echo none)"
    printf "  Precise:           ${CYAN}%s${RESET}\n" "$(parse_config_section "$config_path" "general" "precise" | grep . || echo false)"
    printf "  Import SQL Mode:   ${CYAN}%s${RESET}\n" "$(parse_config_section "$config_path" "general" "import_sql_mode" | grep . || echo auto)"
    printf "  Import Report:     ${CYAN}%s${RESET} (keep %s)\n" "$(parse_config_section "$config_path" "general" "import_report" | grep . || echo true)" "$(parse_config_section "$config_path" "general" "report_keep" | grep . || echo 5)"
    printf "  Require Dry Run:   ${CYAN}%s${RESET}\n" "$(parse_config_section "$config_path" "general" "require_dry_run" | grep . || echo false) ($(parse_config_section "$config_path" "general" "require_dry_run_hours" | grep . || echo 24) h)"

    # Display site mappings
    if declare -F dm_load >/dev/null 2>&1; then
        local dm_old dm_new
        if dm_load "$config_path" "domain_mappings" && [[ -n "$DM_ENTRIES" ]]; then
            printf "\n${BOLD}Custom URL Mappings ([domain_mappings]):${RESET}\n"
            while IFS=$'\t' read -r dm_old dm_new; do
                [[ -n "$dm_old" ]] && printf "  ${YELLOW}%s${RESET} → ${GREEN}%s${RESET}\n" "$dm_old" "$dm_new"
            done <<< "$DM_ENTRIES"
        elif [[ -n "$DM_ERRORS" ]]; then
            printf "\n${BOLD}Custom URL Mappings ([domain_mappings]):${RESET}\n"
            dm_print_problems "[domain_mappings]"
        fi
    fi

    printf "\n${BOLD}Site Mappings:${RESET}\n"
    local mappings
    mappings=$(get_site_mappings "$config_path")

    if [[ -n "$mappings" ]]; then
        printf "  %-8s %-30s → %s\n" "Blog ID" "Old Domain" "New Domain"
        printf "  %-8s %-30s   %s\n" "-------" "-----------" "-----------"
        while IFS=':' read -r blog_id old_dom new_dom; do
            printf "  %-8s %-30s → ${GREEN}%s${RESET}\n" "$blog_id" "$old_dom" "$new_dom"
        done <<< "$mappings"
    else
        printf "  ${YELLOW}No site mappings configured${RESET}\n"
    fi

    printf "\n"
}

# ===============================================
# Get Config Value
# ===============================================
#
# Description: Retrieves a config value, falling back to a default value if not found.
#
# Parameters:
#	- $1: Path to the config file.
#	- $2: The section name.
#	- $3: The key name.
#	- $4: Optional. The default value to use if the key is missing or empty.
#
# Returns:
#	- The config value or the default value (echoed)
#
get_config_value() {
    local config_path="$1"
    local section="$2"
    local key="$3"
    local default_value="${4:-}"

    local value
    if [[ -f "$config_path" ]]; then
        value=$(parse_config_section "$config_path" "$section" "$key")
    fi

    echo "${value:-$default_value}"
}

# ===============================================
# Prompt and Save Config
# ===============================================
#
# Description: Prompts the user for missing required configuration values and saves them.
#
# Parameters:
#	- $1: Path to the config file.
#	- $2: The WordPress root directory path.
#
# Returns:
#	- 0 (Success) on successful configuration
#	- 1 (Failure) on error creating/updating the config file
#
prompt_and_save_config() {
    local config_path="$1"
    local wp_root="$2"

    printf "${CYAN}${BOLD}🔧 Configuration Setup${RESET}\n"
    printf "======================\n\n"

    # Create config file if it doesn't exist
    if [[ ! -f "$config_path" ]]; then
        printf "${YELLOW}📝 Config file not found. Creating new configuration...${RESET}\n\n"

        # Prompt for basic settings
        local sql_file old_domain new_domain all_tables dry_run clear_revisions setup_stage_proxy auto_proceed

        printf "📦 Enter SQL file name (default: vip-db.sql): "
        wpdb_read_required sql_file "The SQL file name (sql_file)" || return 1
        sql_file=${sql_file:-vip-db.sql}

        printf "🌍 Enter the OLD (production) domain to search for: "
        wpdb_read_required old_domain "The old (production) domain (old_domain)" || return 1

        printf "🏠 Enter the NEW (local) domain/base URL to replace with: "
        wpdb_read_required new_domain "The new (local) domain (new_domain)" || return 1

        printf "Include --all-tables? (Y/n): "
        wpdb_read all_tables
        all_tables=${all_tables:-y}
        [[ "$all_tables" == [Yy]* ]] && all_tables="true" || all_tables="false"

        printf "Run in dry-run mode by default? (y/N): "
        wpdb_read dry_run
        dry_run=${dry_run:-n}
        [[ "$dry_run" == [Yy]* ]] && dry_run="true" || dry_run="false"

        printf "Clear post revisions by default? (Y/n): "
        wpdb_read clear_revisions
        clear_revisions=${clear_revisions:-y}
        [[ "$clear_revisions" == [Yy]* ]] && clear_revisions="true" || clear_revisions="false"

        printf "Setup stage file proxy by default? (Y/n): "
        wpdb_read setup_stage_proxy
        setup_stage_proxy=${setup_stage_proxy:-y}
        [[ "$setup_stage_proxy" == [Yy]* ]] && setup_stage_proxy="true" || setup_stage_proxy="false"

        printf "Auto-proceed without confirmations? (y/N): "
        wpdb_read auto_proceed
        auto_proceed=${auto_proceed:-n}
        [[ "$auto_proceed" == [Yy]* ]] && auto_proceed="true" || auto_proceed="false"        # Create the config file
        if ! create_config_file "$config_path" "$sql_file" "$old_domain" "$new_domain"; then
            return 1
        fi

        # Update all general settings
        update_config_general "$config_path" "sql_file" "$sql_file"
        update_config_general "$config_path" "old_domain" "$old_domain"
        update_config_general "$config_path" "new_domain" "$new_domain"
        update_config_general "$config_path" "all_tables" "$all_tables"
        update_config_general "$config_path" "dry_run" "$dry_run"
        update_config_general "$config_path" "clear_revisions" "$clear_revisions"
        update_config_general "$config_path" "setup_stage_proxy" "$setup_stage_proxy"
        update_config_general "$config_path" "auto_proceed" "$auto_proceed"

        printf "\n${GREEN}✅ Basic configuration saved!${RESET}\n"
        printf "${YELLOW}💡 You can edit ${config_path} to add site mappings and customize options.${RESET}\n\n"
    fi

    return 0
}

# ===============================================
# Is Config True
# ===============================================
#
# Description: Checks if a configuration value represents a boolean 'true' state.
#
# Parameters:
#	- $1: The value to check (case-insensitive: 'true', 'yes', '1', 'on').
#
# Returns:
#	- 0 (Success) if the value is true
#	- 1 (Failure) if the value is false
#
is_config_true() {
    local value="$1"
    # Convert to lowercase using tr for compatibility
    local lower_value
    lower_value=$(echo "$value" | tr '[:upper:]' '[:lower:]')
    [[ "$lower_value" =~ ^(true|yes|1|on)$ ]]
}

# Export functions for use in other modules
export -f find_wp_root
export -f get_config_file_path
export -f config_file_exists
export -f create_config_file
export -f parse_config_section
export -f get_site_mappings
export -f get_site_mapping
export -f update_site_mapping
export -f update_config_general
export -f validate_config_file
export -f show_config
export -f get_config_value
export -f prompt_and_save_config
export -f is_config_true
