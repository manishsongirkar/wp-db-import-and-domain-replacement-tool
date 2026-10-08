#!/usr/bin/env bash

# ================================================================
# WordPress Database Import Tool - Uninstaller
# ================================================================
#
# Description:
#   This script is designed to safely and completely remove all installation
#   artifacts of the `wp-db-import` command from the system. It checks common
#   user-local and system-wide binary paths for the executable, prompts for
#   confirmation, and removes associated shell completion files for Bash and Zsh.
#
# Key Features:
# - Searches multiple common installation locations ($HOME/.local/bin, /usr/local/bin, etc.).
# - Prompts the user for confirmation before removing files.
# - Attempts system-level removal using `sudo` if the executable is in a restricted path.
# - Automatically removes symlinks for Bash and Zsh tab completion.
# - Provides a clear summary of removed and failed installations.
# - Prints the actual cause of every problem (the error from rm/sudo, the path, its
#   owner and permissions) and exits non-zero when anything could not be removed.
# - Removes stale private temp directories left by crashed runs (wpdb-import-<uid>-<pid>).
# - Never deletes saved database backups (~/.wp-db-import) unless you say so explicitly.
#
# Usage:
#   ./uninstall.sh                    # interactive
#   ./uninstall.sh --yes              # remove the command without asking (backups are kept)
#   ./uninstall.sh --delete-backups   # also delete ~/.wp-db-import (backups) without asking
#   ./uninstall.sh --keep-backups     # never ask about backups; keep them
#
# Dependencies:
# - rm, find (Standard utilities)
# - lib/core/utils.sh (For colors and init_colors function)
#
# ================================================================

# Load utilities for colors and common functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UTILS_FILE="$SCRIPT_DIR/lib/core/utils.sh"
if [[ -f "$UTILS_FILE" ]]; then
    source "$UTILS_FILE"
    init_colors
else
    # Fallback colors if utils not available
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    CYAN='\033[0;36m'
    BOLD='\033[1m'
    RESET='\033[0m'
fi

# Command line flags
ASSUME_YES=false
BACKUPS_MODE="ask"      # ask | delete | keep
for arg in "$@"; do
    case "$arg" in
        -y|--yes)          ASSUME_YES=true ;;
        --delete-backups)  BACKUPS_MODE="delete" ;;
        --keep-backups)    BACKUPS_MODE="keep" ;;
        -h|--help)
            printf "Usage: ./uninstall.sh [--yes] [--delete-backups | --keep-backups]\n"
            exit 0
            ;;
        *)
            printf "${RED}❌ Unknown option: %s${RESET}\n" "$arg" >&2
            printf "Usage: ./uninstall.sh [--yes] [--delete-backups | --keep-backups]\n" >&2
            exit 2
            ;;
    esac
done

# Problems are collected with their cause and printed in the summary
PROBLEMS=()

# ===============================================
# Describe why a path could not be removed
# ===============================================
#
# Parameters: $1 = path, $2 = error text from the failed command
# Prints a short, indented explanation: the error, owner/permissions and the parent folder.
#
describe_failure() {
    local path="$1" err="$2"
    [[ -n "$err" ]] && printf "      Error:       %s\n" "$err"
    printf "      Path:        %s\n" "$path"
    printf "      Details:     %s\n" "$(ls -ld "$path" 2>&1 | head -1)"
    printf "      Parent dir:  %s\n" "$(ls -ldH "$(dirname "$path")" 2>&1 | head -1)"
    printf "      You are:     %s\n" "$(id -un 2>/dev/null) (uid $(id -u 2>/dev/null))"
    if [[ "$err" == *"Operation not permitted"* ]]; then
        printf "      Hint:        the file has a protection flag; try: chflags nouchg \"%s\"\n" "$path"
    elif [[ "$err" == *"Permission denied"* ]]; then
        printf "      Hint:        you lack write permission on the parent folder; try with sudo\n"
    elif [[ "$err" == *"Read-only file system"* ]]; then
        printf "      Hint:        the file system is read-only\n"
    fi
}

# ===============================================
# Remove one path and report the cause on failure
# ===============================================
#
# Parameters: $1 = path, $2 = label for messages, $3 = "sudo" to retry with sudo
# Returns: 0 if the path is gone, 1 otherwise (the cause is printed and recorded).
#
remove_path() {
    local path="$1" label="$2" use_sudo="${3:-}" err
    if err=$(rm -f "$path" 2>&1); then
        return 0
    fi
    if [[ "$use_sudo" == "sudo" ]]; then
        printf "\n   ${YELLOW}Requires sudo for system location...${RESET}\n"
        if err=$(sudo rm -f "$path" 2>&1); then
            return 0
        fi
    fi
    printf "${RED}❌ Failed${RESET}\n"
    describe_failure "$path" "$err"
    PROBLEMS+=("$label: ${err:-unknown error} ($path)")
    return 1
}

printf "${CYAN}${BOLD}WordPress Database Import Tool - Uninstaller${RESET}\n"
printf "======================================================\n\n"

# Find all possible installation locations
INSTALL_LOCATIONS=(
    "$HOME/.local/bin/wp-db-import"
    "$HOME/bin/wp-db-import"
    "/usr/local/bin/wp-db-import"
)

FOUND_INSTALLATIONS=()

printf "${CYAN}🔍 Searching for wp-db-import installations...${RESET}\n"

# Check each location
for location in "${INSTALL_LOCATIONS[@]}"; do
    if [[ -L "$location" || -f "$location" ]]; then
        printf "${YELLOW}   Found: $location${RESET}\n"
        FOUND_INSTALLATIONS+=("$location")
    fi
done

if [[ ${#FOUND_INSTALLATIONS[@]} -eq 0 ]]; then
    printf "${GREEN}✅ No wp-db-import installations found${RESET}\n"
    printf "   Tool is already uninstalled\n"
    if [[ -d "$HOME/.wp-db-import" ]]; then
        printf "   ${YELLOW}Saved database backups remain in %s (delete that folder manually if not needed).${RESET}\n" "$HOME/.wp-db-import"
    fi
    exit 0
fi

printf "\n${CYAN}📋 Found ${#FOUND_INSTALLATIONS[@]} installation(s)${RESET}\n"
printf "Do you want to remove all installations? (y/N): "
if [[ "$ASSUME_YES" == "true" ]]; then
    confirm_removal="y"
    printf "y (--yes)\n"
else
    read -r confirm_removal
fi

if [[ "$confirm_removal" != [Yy]* ]]; then
    printf "${YELLOW}⚠️  Uninstallation cancelled${RESET}\n"
    exit 0
fi

printf "\n${CYAN}🗑️  Removing wp-db-import installations...${RESET}\n"

REMOVED_COUNT=0
FAILED_COUNT=0

# ===============================================
# Removal Loop
# ===============================================
#
# Description: Iterates through all found installation locations and attempts to
#              remove the executable file. It includes fallback logic to use `sudo`
#              if removal from a system directory (`/usr/local/bin`) fails.
#
# Parameters:
#   - None (Operates on global array `FOUND_INSTALLATIONS`).
#
# Returns:
#   - Updates global counters `REMOVED_COUNT` and `FAILED_COUNT`.
#
# Behavior:
#   - Uses `rm -f` for removal.
#   - Checks the installation path for `/usr/local/bin/` to determine if `sudo` might be needed.
#
for installation in "${FOUND_INSTALLATIONS[@]}"; do
    printf "   Removing: $installation... "

    sudo_flag=""
    [[ "$installation" == "/usr/local/bin/"* ]] && sudo_flag="sudo"
    if remove_path "$installation" "Executable" "$sudo_flag"; then
        printf "${GREEN}✅ Removed${RESET}\n"
        ((REMOVED_COUNT++))
    else
        ((FAILED_COUNT++))
    fi
done

# Remove shell completions
printf "\n${CYAN}🔧 Removing shell completions...${RESET}\n"

# Remove bash completion
BASH_COMPLETION_SYMLINK="$HOME/.local/share/bash-completion/completions/wp-db-import"
if [[ -L "$BASH_COMPLETION_SYMLINK" || -f "$BASH_COMPLETION_SYMLINK" ]]; then
    printf "   Removing: $BASH_COMPLETION_SYMLINK... "
    if remove_path "$BASH_COMPLETION_SYMLINK" "Bash completion"; then
        printf "${GREEN}✅ Bash completion removed${RESET}\n"
    else
        ((FAILED_COUNT++))
    fi
fi

# Remove zsh completion
ZSH_COMPLETION_SYMLINK="$HOME/.local/share/zsh/site-functions/_wp-db-import"
if [[ -L "$ZSH_COMPLETION_SYMLINK" || -f "$ZSH_COMPLETION_SYMLINK" ]]; then
    printf "   Removing: $ZSH_COMPLETION_SYMLINK... "
    if remove_path "$ZSH_COMPLETION_SYMLINK" "Zsh completion"; then
        printf "${GREEN}✅ Zsh completion removed${RESET}\n"
    else
        ((FAILED_COUNT++))
    fi
fi

if [[ ! -L "$BASH_COMPLETION_SYMLINK" && ! -f "$BASH_COMPLETION_SYMLINK" &&
      ! -L "$ZSH_COMPLETION_SYMLINK" && ! -f "$ZSH_COMPLETION_SYMLINK" ]]; then
    printf "${CYAN}   No shell completions found${RESET}\n"
fi

# ===============================================
# Stale private temp directories
# ===============================================
#
# The tool keeps logs and scratch files in "<tmp>/wpdb-import-<uid>-<pid>" (mode 700) and
# removes it on exit. A crashed run can leave one behind; only directories owned by the
# current user (and not symlinks) are removed.
#
printf "\n${CYAN}🧹 Removing stale temporary files...${RESET}\n"
TMP_BASE="${TMPDIR:-/tmp}"
TMP_BASE="${TMP_BASE%/}"
STALE_REMOVED=0
for stale in "$TMP_BASE"/wpdb-import-"$(id -u)"-*; do
    [[ -e "$stale" || -L "$stale" ]] || continue
    if [[ -L "$stale" || ! -d "$stale" || ! -O "$stale" ]]; then
        printf "   ${YELLOW}⚠️  Skipped (not a directory owned by you): %s${RESET}\n" "$stale"
        continue
    fi
    if err=$(rm -rf "$stale" 2>&1); then
        ((STALE_REMOVED++))
    else
        printf "   ${RED}❌ Could not remove %s${RESET}\n" "$stale"
        describe_failure "$stale" "$err"
        PROBLEMS+=("Temp directory: ${err:-unknown error} ($stale)")
        ((FAILED_COUNT++))
    fi
done
if [[ "$STALE_REMOVED" -gt 0 ]]; then
    printf "${GREEN}✅ Removed %d stale temp director%s${RESET}\n" "$STALE_REMOVED" "$([[ $STALE_REMOVED -eq 1 ]] && echo y || echo ies)"
else
    printf "${CYAN}   No stale temp files found${RESET}\n"
fi

# ===============================================
# Saved database backups (your data: never removed without an explicit yes)
# ===============================================
BACKUP_ROOT="$HOME/.wp-db-import"
if [[ -d "$BACKUP_ROOT" ]]; then
    BACKUP_COUNT=$(find "$BACKUP_ROOT" -type f -name '*.sql.gz' 2>/dev/null | wc -l | tr -d ' ')
    BACKUP_SIZE=$(du -sh "$BACKUP_ROOT" 2>/dev/null | awk '{print $1}')
    printf "\n${CYAN}💾 Saved database backups:${RESET} %s (%s backup(s), %s)\n" "$BACKUP_ROOT" "$BACKUP_COUNT" "${BACKUP_SIZE:-unknown size}"
    delete_backups=false
    case "$BACKUPS_MODE" in
        delete) delete_backups=true ;;
        keep)   delete_backups=false ;;
        *)
            if [[ "$ASSUME_YES" == "true" ]]; then
                delete_backups=false    # --yes never deletes data
            else
                printf "   Delete these backups too? They cannot be recovered. (y/N): "
                read -r answer_backups
                [[ "$answer_backups" == [Yy]* ]] && delete_backups=true
            fi
            ;;
    esac
    if [[ "$delete_backups" == "true" ]]; then
        if err=$(rm -rf "$BACKUP_ROOT" 2>&1); then
            printf "${GREEN}✅ Backups deleted${RESET}\n"
        else
            printf "${RED}❌ Could not delete %s${RESET}\n" "$BACKUP_ROOT"
            describe_failure "$BACKUP_ROOT" "$err"
            PROBLEMS+=("Backups: ${err:-unknown error} ($BACKUP_ROOT)")
            ((FAILED_COUNT++))
        fi
    else
        printf "${GREEN}✅ Backups kept${RESET} in %s\n" "$BACKUP_ROOT"
    fi
fi

printf "\n${CYAN}${BOLD}📋 Uninstallation Summary${RESET}\n"
printf "============================\n"

if [[ $REMOVED_COUNT -gt 0 ]]; then
    printf "${GREEN}✅ Successfully removed $REMOVED_COUNT installation(s)${RESET}\n"
fi

if [[ $FAILED_COUNT -gt 0 ]]; then
    printf "${RED}❌ %d item(s) could not be removed${RESET}\n" "$FAILED_COUNT"
    printf "   You may need to manually remove remaining files.\n"
    printf "\n${RED}${BOLD}Problems found:${RESET}\n"
    for problem in "${PROBLEMS[@]}"; do
        printf "   - %s\n" "$problem"
    done
fi

# Note about PATH modifications
printf "\n${YELLOW}📝 Note:${RESET}\n"
printf "   Per-project wpdb-import.conf files in your WordPress folders and the\n"
printf "   cloned repository folder (%s) are not removed.\n" "$SCRIPT_DIR"
printf "   PATH modifications in shell config files (.zshrc, .bashrc, etc.)\n"
printf "   have not been automatically removed. You may want to clean them up manually\n"
printf "   if you no longer need user bin directories in your PATH.\n"

if [[ $REMOVED_COUNT -gt 0 && $FAILED_COUNT -eq 0 ]]; then
    printf "\n${GREEN}${BOLD}🎉 Uninstallation complete!${RESET}\n"
else
    printf "\n${YELLOW}⚠️  Uninstallation completed with some issues${RESET}\n"
fi

# Non-zero exit code when anything failed, so scripts and CI can detect it
[[ $FAILED_COUNT -eq 0 ]]
