#!/usr/bin/env bash

# ================================================================
# Pre-Import Database Backup
# ================================================================
#
# Description:
#   Saves a compressed copy of the current database before an import replaces it,
#   so a bad import can be undone. Backups go to ~/.wp-db-import/backups (or
#   backup_dir) as <dbname>-<timestamp>.sql.gz with mode 600 in a mode 700 folder.
#
# Config (from wpdb-import.conf [general]):
#   backup_before_import=ask|true|false   (default ask: prompts, Yes by default;
#                                          answering "n" saves false to the config)
#   backup_dir=<path>                 (default ~/.wp-db-import/backups)
#   backup_keep=<n>                   (default 5; newest n backups per database are kept, 0 = keep all)
#
# Restore:
#   gunzip -c <backup-file> | wp db import -
#
# ================================================================

# ===============================================
# Rotate Old Backups
# ===============================================
#
# Description:
#   Keeps only the newest N backups of ONE database and deletes the rest, so the backup
#   folder cannot grow forever. Only files named exactly <db>-YYYYMMDD-HHMMSS[-n].sql.gz
#   are ever touched; other files and other databases' backups are left alone.
#   Stale ".partial" files from crashed runs (older than 1 day) are removed too.
#
# Parameters:
#   $1: backup directory   $2: sanitized DB name   $3: keep count (0 = keep all)
#   $4: the backup just written (never deleted)
#
# Prints the number of deleted backups on stdout.
#
prune_old_backups() {
    local dir="$1" db="$2" keep="$3" current="$4"
    local f base kept=0 removed=0

    [[ "$keep" =~ ^[0-9]+$ ]] || keep=5

    # Stale partial files from interrupted runs
    find "$dir" -maxdepth 1 -type f -name "${db}-*.sql.gz.partial" -mtime +1 -exec rm -f {} + 2>/dev/null

    if [[ "$keep" -gt 0 ]]; then
        # Newest first (modification time); the current backup always counts and is kept
        while IFS= read -r base; do
            [[ -n "$base" ]] || continue
            f="$dir/$base"
            [[ "$base" == "${db}-"* ]] || continue
            [[ "${base#"${db}"-}" =~ ^[0-9]{8}-[0-9]{6}(-[0-9]+)?\.sql\.gz$ ]] || continue
            if [[ "$f" == "$current" ]] || [[ "$kept" -lt "$keep" ]]; then
                kept=$((kept + 1))
            elif rm -f "$f" 2>/dev/null; then
                removed=$((removed + 1))
            fi
        done < <(ls -1t "$dir" 2>/dev/null)
    fi
    printf "%d" "$removed"
}

# ===============================================
# Back Up the Current Database
# ===============================================
#
# Parameters:
#   $1: WordPress root (used to read the database name)
#   $2: Config file path (optional; where a "no" answer is saved)
#
# Returns:
#   0 if the backup was written, skipped by config, or there is nothing to back up.
#   1 if a backup was requested and failed (the caller must cancel the import).
#
backup_database_before_import() {
    local wp_root="${1:-${WP_ROOT:-}}"
    local config_path="${2:-}"
    local mode
    mode=$(printf "%s" "${CONFIG_BACKUP_BEFORE_IMPORT:-ask}" | tr '[:upper:]' '[:lower:]')

    case "$mode" in
        false|no|0|off)
            printf "${YELLOW}⚠️  Pre-import backup disabled in config (backup_before_import=false).${RESET}\n"
            return 0
            ;;
    esac

    # Nothing to back up on a fresh or empty database
    local first_table
    first_table=$(execute_wp_cli db tables --all-tables 2>/dev/null | head -1)
    if [[ -z "$first_table" ]]; then
        printf "${DIM}ℹ️  Database is empty or not reachable yet; nothing to back up.${RESET}\n"
        return 0
    fi

    # "ask" (default): let the user decide, unless running unattended (auto_proceed).
    # "true" always backs up. Any unknown value backs up too (fail safe).
    if [[ "$mode" == "ask" || -z "$mode" ]]; then
        local auto_proceed
        auto_proceed=$(printf "%s" "${CONFIG_AUTO_PROCEED:-}" | tr '[:upper:]' '[:lower:]')
        if [[ "$auto_proceed" == "true" || "$auto_proceed" == "yes" || "$auto_proceed" == "1" || "$auto_proceed" == "on" ]]; then
            printf "${DIM}ℹ️  Unattended run (auto_proceed): backing up before import.${RESET}\n"
        else
            local answer=""
            declare -F pause_script_timer >/dev/null 2>&1 && pause_script_timer
            printf "\n💾 Back up the current database before importing? (Y/n): "
            read -r answer || answer=""
            declare -F resume_script_timer >/dev/null 2>&1 && resume_script_timer
            answer="${answer:-y}"
            if [[ "$answer" != [Yy]* ]]; then
                CONFIG_BACKUP_BEFORE_IMPORT="false"
                printf "${YELLOW}⚠️  Skipping backup. The current database will be replaced without a copy.${RESET}\n"
                if [[ -n "$config_path" && -f "$config_path" ]] && declare -F update_config_general >/dev/null 2>&1; then
                    if update_config_general "$config_path" "backup_before_import" "false"; then
                        printf "${DIM}   Saved backup_before_import=false in %s (set it to ask or true to bring the backup back).${RESET}\n" "$config_path"
                    else
                        printf "${DIM}   Could not save the choice to %s.${RESET}\n" "$config_path"
                    fi
                fi
                return 0
            fi
        fi
    fi

    local backup_dir="${CONFIG_BACKUP_DIR:-}"
    local default_dir=false
    if [[ -z "$backup_dir" ]]; then
        backup_dir="$HOME/.wp-db-import/backups"
        default_dir=true
    fi
    backup_dir="${backup_dir/#\~/$HOME}"

    if ! (umask 077; mkdir -p "$backup_dir") 2>/dev/null; then
        printf "${RED}❌ Cannot create backup directory: %s${RESET}\n" "$backup_dir"
        printf "${YELLOW}💡 Fix backup_dir, or set backup_before_import=false to skip the backup.${RESET}\n"
        return 1
    fi
    [[ "$default_dir" == "true" ]] && chmod 700 "$HOME/.wp-db-import" "$backup_dir" 2>/dev/null

    local db_name=""
    if [[ -n "$wp_root" ]] && declare -F get_wp_db_credentials >/dev/null 2>&1; then
        get_wp_db_credentials "$wp_root" >/dev/null 2>&1 && db_name="${WP_DB_NAME:-}"
    fi
    db_name=$(printf "%s" "${db_name:-database}" | tr -c 'A-Za-z0-9._-' '_')

    # Unique name (two backups in the same second must never overwrite each other)
    local stamp backup_file n=0
    stamp="$(date +%Y%m%d-%H%M%S)"
    backup_file="$backup_dir/${db_name}-${stamp}.sql.gz"
    while [[ -e "$backup_file" ]]; do
        n=$((n + 1))
        backup_file="$backup_dir/${db_name}-${stamp}-${n}.sql.gz"
    done
    # Write to a .partial file and rename only after it verifies, so a failed run
    # can never leave a truncated file that looks like a good backup.
    local partial="${backup_file}.partial"
    local err_file
    err_file="$(secure_tmpdir)/backup.err" || return 1

    printf "\n${CYAN}💾 Backing up current database before import...${RESET}\n"
    (
        umask 077
        # --add-drop-table: the backup restores cleanly over a database that already has these tables
        execute_wp_cli db export - --add-drop-table 2>"$err_file" | gzip -c > "$partial"
        exit "${PIPESTATUS[0]}"
    )
    local rc=$?

    if [[ "$rc" -ne 0 ]] || [[ ! -s "$partial" ]] || ! gzip -t "$partial" 2>/dev/null; then
        rm -f "$partial"
        printf "${RED}❌ Database backup failed; import cancelled to protect your current data.${RESET}\n"
        [[ -s "$err_file" ]] && printf "${DIM}   %s${RESET}\n" "$(head -3 "$err_file" | tr '\n' ' ')"
        printf "${YELLOW}💡 Set backup_before_import=false in the config to import without a backup.${RESET}\n"
        return 1
    fi

    mv "$partial" "$backup_file" || { rm -f "$partial"; printf "${RED}❌ Could not finalize the backup file.${RESET}\n"; return 1; }

    local size_kb
    size_kb=$(( $(_sql_file_size_bytes "$backup_file") / 1024 ))
    printf "${GREEN}✅ Backup saved:${RESET} %s ${DIM}(%d KB)${RESET}\n" "$backup_file" "$size_kb"
    local pruned
    pruned=$(prune_old_backups "$backup_dir" "$db_name" "${CONFIG_BACKUP_KEEP:-5}" "$backup_file")
    if [[ "${pruned:-0}" -gt 0 ]]; then
        printf "${DIM}   Rotated: removed %d older backup(s), keeping the newest %s (backup_keep).${RESET}\n" "$pruned" "${CONFIG_BACKUP_KEEP:-5}"
    fi
    printf "${DIM}   Restore with: gunzip -c \"%s\" | wp db import -${RESET}\n" "$backup_file"
    return 0
}

export -f prune_old_backups backup_database_before_import 2>/dev/null
