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
#   backup_keep_days=<n>              (default 0 = off; also delete backups older than n days)
#   backup_encrypt=false|gpg          (default false; gpg = encrypt with backup_gpg_recipient)
#   backup_gpg_recipient=<key>        (key id, fingerprint or e-mail of the public key)
#
# Safety checks before a backup starts:
#   - free disk space in backup_dir against the database size (information_schema)
#   - with backup_encrypt=gpg: gpg and the recipient's key must exist, or the backup (and the
#     import) is cancelled. It never falls back to an unencrypted file.
# Long backups show the size written so far (only in a terminal).
#
# Restore:
#   wp-db-import restore --last       (also decrypts .sql.gz.gpg files)
#   gunzip -c <backup-file> | wp db import -
#
# ================================================================

# ===============================================
# Rotate Old Backups
# ===============================================
#
# Description:
#   Keeps only the newest N backups of ONE database (backup_keep) and, when backup_keep_days
#   is set, also deletes backups older than that many days. Only files named exactly
#   <db>-YYYYMMDD-HHMMSS[-n].sql.gz[.gpg] are ever touched; other files and other databases'
#   backups are left alone. The backup just written and a protected file are never deleted.
#   Stale ".partial" files from crashed runs (older than 1 day) are removed too.
#
# Parameters:
#   $1: backup directory   $2: sanitized DB name   $3: keep count (0 = keep all)
#   $4: the backup just written (never deleted)    $5: keep days (0 or empty = off)
#
# Prints the number of deleted backups on stdout.
#
prune_old_backups() {
    local dir="$1" db="$2" keep="$3" current="$4" days="${5:-0}"
    local f base kept=0 removed=0 drop

    [[ "$keep" =~ ^[0-9]+$ ]] || keep=5
    [[ "$days" =~ ^[0-9]+$ ]] || days=0

    # Stale partial files from interrupted runs
    find "$dir" -maxdepth 1 -type f \( -name "${db}-*.sql.gz.partial" -o -name "${db}-*.sql.gz.gpg.partial" \) -mtime +1 -exec rm -f {} + 2>/dev/null

    if [[ "$keep" -gt 0 || "$days" -gt 0 ]]; then
        # Newest first (modification time); the current backup always counts and is kept
        while IFS= read -r base; do
            [[ -n "$base" ]] || continue
            f="$dir/$base"
            [[ "$base" == "${db}-"* ]] || continue
            [[ "${base#"${db}"-}" =~ ^[0-9]{8}-[0-9]{6}(-[0-9]+)?\.sql\.gz(\.gpg)?$ ]] || continue
            # WPDB_BACKUP_PROTECT: a file that is being restored must survive the rotation
            if [[ "$f" == "$current" || "$f" == "${WPDB_BACKUP_PROTECT:-}" ]]; then
                kept=$((kept + 1))
                continue
            fi
            drop=false
            [[ "$keep" -gt 0 && "$kept" -ge "$keep" ]] && drop=true
            # older than N days: file age (in whole days) is at least N, so more than N-1
            if [[ "$days" -gt 0 && -n "$(find "$f" -maxdepth 0 -type f -mtime "+$((days - 1))" 2>/dev/null)" ]]; then
                drop=true
            fi
            if [[ "$drop" == "true" ]]; then
                rm -f "$f" 2>/dev/null && removed=$((removed + 1))
            else
                kept=$((kept + 1))
            fi
        done < <(ls -1t "$dir" 2>/dev/null)
    fi
    printf "%d" "$removed"
}

# ===============================================
# Helpers: size, free space, encryption, progress
# ===============================================

# "1234567" -> "1 MB" (KB below 1 MB)
backup_human_size() {
    local b="${1:-0}"
    if [[ "$b" -ge 1048576 ]]; then printf "%d MB" "$((b / 1048576))"; else printf "%d KB" "$(( (b + 1023) / 1024 ))"; fi
}

# Free space (KB) of the filesystem that holds (or will hold) a directory. Prints nothing if unknown.
backup_free_kb() {
    local p="$1"
    while [[ ! -d "$p" && "$p" != "/" && "$p" != "." ]]; do p=$(dirname "$p"); done
    df -Pk "$p" 2>/dev/null | awk 'NR == 2 { print $4 }'
}

# Size of the current database in bytes (data + indexes). Prints nothing if it cannot be read.
backup_estimate_bytes() {
    declare -F _import_db_query >/dev/null 2>&1 || return 0
    _import_db_query "SELECT COALESCE(SUM(data_length + index_length), 0) FROM information_schema.tables WHERE table_schema = DATABASE()" 2>/dev/null \
        | LC_ALL=C grep -E '^[0-9]+$' | head -1
}

# Is there room for the backup in $1? The compressed file is assumed to be at most half the
# database size. Unknown size or free space: no check (returns 0). Returns 1 when it will not fit.
backup_check_space() {
    local dir="$1" est free_kb need_kb
    est=$(backup_estimate_bytes)
    free_kb=$(backup_free_kb "$dir")
    [[ "$est" =~ ^[0-9]+$ && "$free_kb" =~ ^[0-9]+$ ]] || return 0
    need_kb=$(( est / 2048 + 1024 ))
    if [[ "$free_kb" -lt "$need_kb" ]]; then
        printf "${RED}❌ Not enough free disk space for the backup: about %s needed, %s free in %s.${RESET}\n" \
            "$(backup_human_size $((need_kb * 1024)))" "$(backup_human_size $((free_kb * 1024)))" "$dir"
        printf "${DIM}   (database size %s; the backup is estimated at half of it, compressed)${RESET}\n" "$(backup_human_size "$est")"
        printf "${YELLOW}💡 Free some space, set backup_dir to a bigger disk, or set backup_before_import=false. The import was not started.${RESET}\n"
        return 1
    fi
    if [[ "$free_kb" -lt $(( need_kb * 2 )) ]]; then
        printf "${YELLOW}⚠️  Free space for the backup is tight: %s free in %s, about %s needed.${RESET}\n" \
            "$(backup_human_size $((free_kb * 1024)))" "$dir" "$(backup_human_size $((need_kb * 1024)))"
    fi
    return 0
}

# Prints the recipient when encryption is on, nothing when it is off. Returns 1 (with a message)
# when encryption is requested but cannot be done: a backup is never silently left unencrypted.
backup_encryption_recipient() {
    local mode recipient="${CONFIG_BACKUP_GPG_RECIPIENT:-}"
    mode=$(printf "%s" "${CONFIG_BACKUP_ENCRYPT:-false}" | tr '[:upper:]' '[:lower:]')
    case "$mode" in
        ""|false|no|0|off|none) return 0 ;;
        gpg) ;;
        *)
            printf "${RED}❌ Unknown backup_encrypt value '%s' (use false or gpg); import cancelled.${RESET}\n" "$mode" >&2
            return 1
            ;;
    esac
    if ! command -v gpg >/dev/null 2>&1; then
        printf "${RED}❌ backup_encrypt=gpg but gpg is not installed; import cancelled (no unencrypted backup is made).${RESET}\n" >&2
        printf "${YELLOW}💡 Install GnuPG, or set backup_encrypt=false.${RESET}\n" >&2
        return 1
    fi
    if [[ -z "$recipient" ]]; then
        printf "${RED}❌ backup_encrypt=gpg needs backup_gpg_recipient (key id, fingerprint or e-mail); import cancelled.${RESET}\n" >&2
        return 1
    fi
    if ! gpg --batch --list-keys -- "$recipient" >/dev/null 2>&1; then
        printf "${RED}❌ No gpg public key found for '%s' (backup_gpg_recipient); import cancelled.${RESET}\n" "$recipient" >&2
        printf "${YELLOW}💡 List keys: gpg --list-keys   Import one: gpg --import <file>${RESET}\n" >&2
        return 1
    fi
    printf "%s" "$recipient"
    return 0
}

# Progress is shown in a terminal, or when WPDB_BACKUP_PROGRESS=1 (tests, logs)
backup_progress_enabled() { [[ -t 1 || "${WPDB_BACKUP_PROGRESS:-}" == "1" ]]; }

# Writes the backup stream to $1 (the .partial file). Parameters: partial, error file, recipient ("" = no encryption).
# Runs in the background and prints "size written so far" after WPDB_BACKUP_PROGRESS_AFTER seconds (default 3).
# Returns the status of the whole pipeline (export, gzip and gpg).
_backup_run_pipeline() {
    local partial="$1" err_file="$2" recipient="$3" pid rc start elapsed shown=false
    local after="${WPDB_BACKUP_PROGRESS_AFTER:-3}"
    (
        umask 077
        set -o pipefail
        # --add-drop-table: the backup restores cleanly over a database that already has these tables
        if [[ -n "$recipient" ]]; then
            execute_wp_cli db export - --add-drop-table 2>"$err_file" | gzip -c 2>>"$err_file" \
                | gpg --batch --yes --quiet --encrypt --recipient "$recipient" --output "$partial" 2>>"$err_file"
        else
            execute_wp_cli db export - --add-drop-table 2>"$err_file" | gzip -c 2>>"$err_file" > "$partial"
        fi
    ) &
    pid=$!
    start=$SECONDS
    if backup_progress_enabled; then
        while kill -0 "$pid" 2>/dev/null; do
            elapsed=$((SECONDS - start))
            if [[ "$elapsed" -ge "$after" ]]; then
                printf "\r   ⏳ Backing up... %s written (%02d:%02d)   " \
                    "$(backup_human_size "$(_sql_file_size_bytes "$partial" 2>/dev/null || echo 0)")" "$((elapsed / 60))" "$((elapsed % 60))"
                shown=true
            fi
            sleep 1
        done
    fi
    wait "$pid"; rc=$?
    [[ "$shown" == "true" ]] && printf "\r%72s\r" ""
    return "$rc"
}

# ===============================================
# Back Up the Current Database
# ===============================================
#
# Parameters:
#   $1: WordPress root (used to read the database name)
#   $2: Config file path (optional; where a "no" answer is saved)
#
# Sets WPDB_LAST_BACKUP_FILE to the new backup file. WPDB_BACKUP_PROTECT (a file path) is
# never deleted by the rotation.
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
        local assume_yes
        assume_yes=$(printf "%s" "${WPDB_ASSUME_YES:-}" | tr '[:upper:]' '[:lower:]')
        if [[ "$auto_proceed" == "true" || "$auto_proceed" == "yes" || "$auto_proceed" == "1" || "$auto_proceed" == "on" \
           || "$assume_yes" == "1" || "$assume_yes" == "true" || "$assume_yes" == "yes" || "$assume_yes" == "on" ]]; then
            printf "${DIM}ℹ️  Unattended run (auto_proceed / --yes): backing up before import.${RESET}\n"
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

    # Checks BEFORE anything is written: encryption possible? enough free space?
    local recipient=""
    if ! recipient=$(backup_encryption_recipient); then
        return 1
    fi
    if ! backup_check_space "$backup_dir"; then
        return 1
    fi
    local ext=".sql.gz"
    [[ -n "$recipient" ]] && ext=".sql.gz.gpg"

    # Unique name (two backups in the same second must never overwrite each other)
    local stamp backup_file n=0
    stamp="$(date +%Y%m%d-%H%M%S)"
    backup_file="$backup_dir/${db_name}-${stamp}${ext}"
    while [[ -e "$backup_file" ]]; do
        n=$((n + 1))
        backup_file="$backup_dir/${db_name}-${stamp}-${n}${ext}"
    done
    # Write to a .partial file and rename only after it verifies, so a failed run
    # can never leave a truncated file that looks like a good backup.
    local partial="${backup_file}.partial"
    local err_file
    err_file="$(secure_tmpdir)/backup.err" || return 1

    if [[ -n "$recipient" ]]; then
        printf "\n${CYAN}💾 Backing up current database before import (encrypted for %s)...${RESET}\n" "$recipient"
    else
        printf "\n${CYAN}💾 Backing up current database before import...${RESET}\n"
    fi
    _backup_run_pipeline "$partial" "$err_file" "$recipient"
    local rc=$?

    local intact=false
    if [[ "$rc" -eq 0 && -s "$partial" ]]; then
        if [[ -n "$recipient" ]]; then
            # an encrypted file can only be checked for being a valid OpenPGP message (no secret key needed)
            gpg --batch --list-packets "$partial" 2>/dev/null | grep -q 'pubkey enc packet' && intact=true
        else
            gzip -t "$partial" 2>/dev/null && intact=true
        fi
    fi
    if [[ "$intact" != "true" ]]; then
        rm -f "$partial"
        printf "${RED}❌ Database backup failed; import cancelled to protect your current data.${RESET}\n"
        [[ -s "$err_file" ]] && printf "${DIM}   %s${RESET}\n" "$(head -3 "$err_file" | tr '\n' ' ')"
        printf "${YELLOW}💡 Set backup_before_import=false in the config to import without a backup.${RESET}\n"
        return 1
    fi

    mv "$partial" "$backup_file" || { rm -f "$partial"; printf "${RED}❌ Could not finalize the backup file.${RESET}\n"; return 1; }
    WPDB_LAST_BACKUP_FILE="$backup_file"

    printf "${GREEN}✅ Backup saved:${RESET} %s ${DIM}(%s)${RESET}\n" "$backup_file" "$(backup_human_size "$(_sql_file_size_bytes "$backup_file")")"
    local pruned keep_days="${CONFIG_BACKUP_KEEP_DAYS:-0}"
    pruned=$(prune_old_backups "$backup_dir" "$db_name" "${CONFIG_BACKUP_KEEP:-5}" "$backup_file" "$keep_days")
    if [[ "${pruned:-0}" -gt 0 ]]; then
        local rule="keeping the newest ${CONFIG_BACKUP_KEEP:-5} (backup_keep)"
        [[ "$keep_days" =~ ^[0-9]+$ && "$keep_days" -gt 0 ]] && rule="${rule}, none older than ${keep_days} days (backup_keep_days)"
        printf "${DIM}   Rotated: removed %d older backup(s), %s.${RESET}\n" "$pruned" "$rule"
    fi
    if [[ -n "$recipient" ]]; then
        printf "${DIM}   Restore with: wp-db-import restore \"%s\"   (gpg asks for your passphrase)${RESET}\n" "$backup_file"
    else
        printf "${DIM}   Restore with: gunzip -c \"%s\" | wp db import -${RESET}\n" "$backup_file"
    fi
    return 0
}

export -f prune_old_backups backup_human_size backup_free_kb backup_estimate_bytes backup_check_space \
    backup_encryption_recipient backup_progress_enabled _backup_run_pipeline backup_database_before_import 2>/dev/null
