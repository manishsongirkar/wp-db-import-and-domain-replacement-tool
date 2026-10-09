#!/usr/bin/env bash

# ================================================================
# Restore a Database Backup
# ================================================================
#
# Description:
#   `wp-db-import restore` puts a backup made by the pre-import backup (or any SQL dump)
#   back into the current WordPress database in one command.
#
# Usage (through wp-db-import):
#   wp-db-import restore --list            list backups of the current database (newest first)
#   wp-db-import restore --list --all      list backups of every database in the backup folder
#   wp-db-import restore --last            restore the newest backup of the current database
#   wp-db-import restore <file>            restore a specific file (.sql, .sql.gz, .zip, .sql.bz2)
#   wp-db-import --yes restore --last      no confirmation question (scripts, CI)
#
# Safety:
#   - the archive is checked for corruption before anything is changed
#   - a confirmation is asked (default No) unless --yes / WPDB_ASSUME_YES=1
#   - the current database is backed up first, so a restore can be undone (honors
#     backup_before_import=false); rotation (backup_keep) never deletes the file being restored
#   - the import goes through perform_db_import: socket path, error scan, compatibility retry
#   - tables that did not exist when the backup was made are removed after a successful import
#     (views and tables are never removed when the backup's table list cannot be read)
#
# ================================================================

# ===============================================
# Backup folder (config backup_dir, default ~/.wp-db-import/backups)
# ===============================================
restore_backup_dir() {
    local d="${CONFIG_BACKUP_DIR:-}"
    [[ -z "$d" ]] && d="$HOME/.wp-db-import/backups"
    d="${d/#\~/$HOME}"
    printf "%s" "$d"
}

# ===============================================
# Database name used in backup file names (same rule as db_backup.sh)
# ===============================================
restore_current_db_name() {
    local name=""
    if declare -F get_wp_db_credentials >/dev/null 2>&1 && get_wp_db_credentials "${1:-${WP_ROOT:-$(pwd)}}" >/dev/null 2>&1; then
        name="${WP_DB_NAME:-}"
    fi
    printf "%s" "$(printf "%s" "${name:-database}" | tr -c 'A-Za-z0-9._-' '_')"
}

# ===============================================
# List backup files, newest first
# ===============================================
# Parameters: $1 = backup dir, $2 = database name (empty = every database)
# Prints one path per line. Only files named <db>-YYYYMMDD-HHMMSS[-n].sql.gz are listed.
restore_list_files() {
    local dir="$1" db="${2:-}" base rest stamp n key
    [[ -d "$dir" ]] || return 0
    local -a keyed=()
    while IFS= read -r base; do
        [[ -n "$base" ]] || continue
        if [[ -n "$db" ]]; then
            [[ "$base" == "${db}-"* ]] || continue
            rest="${base#"${db}"-}"
            [[ "$rest" =~ ^([0-9]{8}-[0-9]{6})(-([0-9]+))?\.sql\.gz$ ]] || continue
        else
            [[ "$base" =~ ^.+-([0-9]{8}-[0-9]{6})(-([0-9]+))?\.sql\.gz$ ]] || continue
        fi
        stamp="${BASH_REMATCH[1]}"; n="${BASH_REMATCH[3]:-0}"
        key=$(printf "%s-%06d" "$stamp" "$n")
        keyed+=("$key|$dir/$base")
    done < <(ls -1 "$dir" 2>/dev/null)
    [[ ${#keyed[@]} -gt 0 ]] || return 0
    printf "%s\n" "${keyed[@]}" | sort -r | cut -d'|' -f2-
}

# ===============================================
# Human readable listing
# ===============================================
# Parameters: $1 = backup dir, $2 = database name (empty = all)
restore_print_list() {
    local dir="$1" db="${2:-}" f base stamp size_b size i=0 shown_db
    local -a files=()
    while IFS= read -r f; do [[ -n "$f" ]] && files+=("$f"); done < <(restore_list_files "$dir" "$db")

    if [[ ${#files[@]} -eq 0 ]]; then
        printf "${YELLOW}ℹ️  No backups found in %s%s.${RESET}\n" "$dir" "${db:+ for database '$db'}"
        return 0
    fi
    printf "${CYAN}${BOLD}💾 Backups in %s${RESET}\n\n" "$dir"
    printf "  %-3s %-19s %-9s %-22s %s\n" "#" "DATE" "SIZE" "DATABASE" "FILE"
    for f in "${files[@]}"; do
        i=$((i + 1))
        base="${f##*/}"
        [[ "$base" =~ ^(.+)-([0-9]{4})([0-9]{2})([0-9]{2})-([0-9]{2})([0-9]{2})([0-9]{2})(-[0-9]+)?\.sql\.gz$ ]]
        shown_db="${BASH_REMATCH[1]}"
        stamp="${BASH_REMATCH[2]}-${BASH_REMATCH[3]}-${BASH_REMATCH[4]} ${BASH_REMATCH[5]}:${BASH_REMATCH[6]}:${BASH_REMATCH[7]}"
        size_b=$(_sql_file_size_bytes "$f")
        if [[ "$size_b" -ge 1048576 ]]; then size="$((size_b / 1048576)) MB"; else size="$(( (size_b + 1023) / 1024 )) KB"; fi
        printf "  %-3s %-19s %-9s %-22s %s\n" "$i" "$stamp" "$size" "$shown_db" "$base"
    done
    printf "\n${DIM}Restore the newest with: wp-db-import restore --last   (or: wp-db-import restore <file>)${RESET}\n"
    return 0
}

# ===============================================
# Base tables that exist now but are not in the backup (candidates for removal)
# ===============================================
# Parameters: $1 = backup file. Prints table names, one per line; prints nothing (and
# returns 1) when the backup's table list cannot be read, so nothing is ever removed blindly.
restore_extra_tables() {
    local file="$1" backup_tables current name type
    backup_tables=$(sql_open_stream "$file" 2>/dev/null \
        | LC_ALL=C grep -E '^CREATE TABLE ' | LC_ALL=C sed -E 's/^CREATE TABLE (IF NOT EXISTS )?`([^`]+)`.*/\2/')
    [[ -n "$backup_tables" ]] || return 1
    current=$(_import_list_tables) || return 1
    while IFS=$'\t' read -r name type; do
        [[ "$type" == "BASE TABLE" && -n "$name" ]] || continue
        printf "%s\n" "$backup_tables" | grep -qxF -- "$name" || printf "%s\n" "$name"
    done <<< "$current"
    return 0
}

# ===============================================
# Restore one backup file
# ===============================================
# Parameters: $1 = file, $2 = WordPress root, $3 = config path (optional)
# Returns 0 on success or when the user cancels; 1 on failure.
restore_database() {
    local file="$1" wp_root="${2:-${WP_ROOT:-$(pwd)}}" config_path="${3:-}"
    local verify_error size_b db_name

    if [[ -z "$file" ]]; then
        printf "${RED}❌ No backup file given.${RESET}\n"
        return 1
    fi
    # Refuse a missing or corrupt archive before anything is changed
    if ! verify_error=$(sql_verify_source "$file" 2>&1); then
        printf "${RED}❌ %s${RESET}\n" "$verify_error"
        printf "${YELLOW}💡 Nothing was changed.${RESET}\n"
        return 1
    fi

    size_b=$(_sql_file_size_bytes "$file")
    db_name=$(restore_current_db_name "$wp_root")
    printf "\n${CYAN}${BOLD}♻️  Restore database${RESET}\n"
    printf "   Backup:   %s ${DIM}(%d KB)${RESET}\n" "$file" "$(( (size_b + 1023) / 1024 ))"
    printf "   Database: %s\n" "$db_name"
    printf "   ${YELLOW}This replaces the current contents of the database.${RESET}\n\n"

    local answer=""
    if wpdb_assume_yes; then
        printf "${GREEN}✅ Restoring without asking (--yes)${RESET}\n"
    else
        pause_script_timer 2>/dev/null
        printf "Restore this backup now? (y/N): "
        wpdb_read answer
        resume_script_timer 2>/dev/null
        if [[ "$answer" != [Yy]* ]]; then
            printf "${YELLOW}⚠️  Restore cancelled. Nothing was changed.${RESET}\n"
            return 0
        fi
    fi

    # Safety backup of the CURRENT database (so this restore can be undone). "ask" counts as
    # yes here because the user just confirmed a destructive action; "false" is honored.
    # Rotation must never delete the file being restored.
    local saved_mode="${CONFIG_BACKUP_BEFORE_IMPORT:-}" mode_lc
    mode_lc=$(printf "%s" "$saved_mode" | tr '[:upper:]' '[:lower:]')
    case "$mode_lc" in ""|ask) CONFIG_BACKUP_BEFORE_IMPORT="true" ;; esac
    WPDB_LAST_BACKUP_FILE=""
    if ! WPDB_BACKUP_PROTECT="$file" backup_database_before_import "$wp_root" "$config_path"; then
        CONFIG_BACKUP_BEFORE_IMPORT="$saved_mode"
        printf "${RED}❌ The safety backup of the current database failed; restore cancelled. Nothing was changed.${RESET}\n"
        return 1
    fi
    CONFIG_BACKUP_BEFORE_IMPORT="$saved_mode"
    local safety_backup="${WPDB_LAST_BACKUP_FILE:-}"

    # Import through the normal path (socket / mysql / WP-CLI, error scan, compatibility retry)
    local log_file
    log_file="$(secure_tmpdir)/restore.log" || return 1
    if ! perform_db_import "$file" "$log_file"; then
        printf "${RED}❌ Restore failed.${RESET}\n"
        [[ -n "$safety_backup" ]] && printf "${YELLOW}💡 The data from before the restore is saved in: %s${RESET}\n" "$safety_backup"
        return 1
    fi

    # Tables that did not exist when the backup was made
    local extras extra count=0 sql=""
    if extras=$(restore_extra_tables "$file") && [[ -n "$extras" ]]; then
        sql="SET FOREIGN_KEY_CHECKS=0;"
        while IFS= read -r extra; do
            [[ -n "$extra" ]] || continue
            sql+=" DROP TABLE IF EXISTS \`${extra//\`/\`\`}\`;"
            count=$((count + 1))
        done <<< "$extras"
        if _import_db_query "$sql" >/dev/null 2>&1; then
            printf "${GREEN}✅ Removed %d table(s) that did not exist when the backup was made.${RESET}\n" "$count"
        else
            printf "${YELLOW}⚠️  Could not remove %d table(s) that are not part of the backup.${RESET}\n" "$count"
        fi
    fi

    execute_wp_cli cache flush >/dev/null 2>&1
    printf "\n${GREEN}${BOLD}✅ Database restored from %s${RESET}\n" "${file##*/}"
    [[ -n "$safety_backup" ]] && printf "${DIM}   Undo with: wp-db-import restore \"%s\"${RESET}\n" "$safety_backup"
    return 0
}

# ===============================================
# Command line entry: wp-db-import restore ...
# ===============================================
restore_cli() {
    local mode="" target="" all=false arg
    for arg in "$@"; do
        case "$arg" in
            --list) mode="list" ;;
            --last) mode="last" ;;
            --all)  all=true ;;
            -*)
                printf "${RED}❌ Unknown option: %s${RESET}\n" "$arg" >&2
                restore_usage >&2
                return 2
                ;;
            *)
                if [[ -n "$target" ]]; then
                    printf "${RED}❌ Only one backup file can be restored at a time.${RESET}\n" >&2
                    return 2
                fi
                target="$arg"
                ;;
        esac
    done
    if [[ -z "$mode" && -z "$target" ]]; then
        restore_usage >&2
        return 2
    fi
    if [[ -n "$mode" && -n "$target" ]]; then
        printf "${RED}❌ Use either a file or --list/--last, not both.${RESET}\n" >&2
        return 2
    fi

    local wp_root="${WP_ROOT:-$(pwd)}" config_path="" dir db
    if declare -F get_config_file_path >/dev/null 2>&1 && config_path=$(get_config_file_path 2>/dev/null) && [[ -f "$config_path" ]]; then
        load_import_config "$config_path" >/dev/null 2>&1
    else
        config_path=""
    fi
    dir=$(restore_backup_dir)
    db=$(restore_current_db_name "$wp_root")

    case "$mode" in
        list)
            if [[ "$all" == "true" ]]; then restore_print_list "$dir" ""; else restore_print_list "$dir" "$db"; fi
            return 0
            ;;
        last)
            local newest
            newest=$(restore_list_files "$dir" "$db" | head -1)
            if [[ -z "$newest" ]]; then
                printf "${RED}❌ No backup found in %s for database '%s'.${RESET}\n" "$dir" "$db"
                printf "${YELLOW}💡 Backups are made before each import (backup_before_import). List all: wp-db-import restore --list --all${RESET}\n"
                return 1
            fi
            restore_database "$newest" "$wp_root" "$config_path"
            return $?
            ;;
        *)
            restore_database "$target" "$wp_root" "$config_path"
            return $?
            ;;
    esac
}

restore_usage() {
    printf "Usage: wp-db-import [--yes] restore --list [--all]\n"
    printf "       wp-db-import [--yes] restore --last\n"
    printf "       wp-db-import [--yes] restore <file.sql|.sql.gz|.zip|.sql.bz2>\n"
}

export -f restore_backup_dir restore_current_db_name restore_list_files restore_print_list \
    restore_extra_tables restore_database restore_cli restore_usage 2>/dev/null
