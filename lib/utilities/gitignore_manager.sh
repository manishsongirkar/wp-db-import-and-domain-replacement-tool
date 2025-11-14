#!/usr/bin/env bash

# ================================================================
# GitIgnore Manager Utilities Module
# ================================================================
#
# This module provides functions for managing .gitignore entries
# specifically for WordPress development environments.
#
# Key Features:
# - Cross-platform Unix compatibility (macOS, Linux, Flywheel)
# - Robust error handling and validation
# - WordPress root directory auto-detection
# - Safe file operations with proper permission checks
# - Integration with existing project color/messaging standards
#
# Functions provided:
# - add_stage_file_proxy_to_gitignore    Main function to prevent accidental commits
# - find_wordpress_root_gitignore        WordPress root detection helper
# - validate_wp_content_access           Permission validation helper
# - add_gitignore_entry_safe             Generic safe gitignore entry addition
#

# -----------------------------------------------
# Enhanced WordPress root detection for gitignore operations
# -----------------------------------------------
find_wordpress_root_gitignore() {
    local start_dir="${1:-$(pwd)}"
    local wp_root="$start_dir"

    # Traverse up directory tree to find wp-config.php
    while [[ "$wp_root" != "/" && ! -f "$wp_root/wp-config.php" ]]; do
        wp_root="${wp_root%/*}"
        # Handle edge case where wp_root becomes empty
        [[ -z "$wp_root" ]] && wp_root="/"
    done

    # Validate WordPress installation
    if [[ -f "$wp_root/wp-config.php" && -d "$wp_root/wp-content" ]]; then
        echo "$wp_root"
        return 0
    fi

    return 1
}

# -----------------------------------------------
# Validate wp-content directory access and permissions
# -----------------------------------------------
validate_wp_content_access() {
    local wp_root="$1"
    local wp_content_dir="$wp_root/wp-content"

    # Check if wp-content exists
    if [[ ! -d "$wp_content_dir" ]]; then
        printf "${RED}❌ Error: 'wp-content' directory not found in WordPress root.${RESET}\n"
        printf "${YELLOW}💡 Expected location: %s${RESET}\n" "$wp_content_dir"
        return 1
    fi

    # Check if wp-content is writable
    if [[ ! -w "$wp_content_dir" ]]; then
        printf "${RED}❌ Error: 'wp-content' directory is not writable.${RESET}\n"
        printf "${YELLOW}💡 Check file permissions or hosting restrictions.${RESET}\n"
        printf "${YELLOW}💡 You may need to run: chmod 755 '%s'${RESET}\n" "$wp_content_dir"
        return 1
    fi

    return 0
}

# -----------------------------------------------
# Check for semantic duplicate gitignore entries
# Handles variations like ./plugins vs /plugins vs plugins
# -----------------------------------------------
check_gitignore_semantic_duplicate() {
    local gitignore_file="$1"
    local new_entry="$2"

    if [[ ! -f "$gitignore_file" ]]; then
        return 1  # No duplicates if file doesn't exist
    fi

    # Normalize the new entry for comparison
    local normalized_new
    normalized_new=$(normalize_gitignore_entry "$new_entry")

    # Check each line in gitignore for semantic matches
    while IFS= read -r line || [[ -n "$line" ]]; do
        # Skip empty lines and comments
        [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue

        # Normalize existing entry
        local normalized_existing
        normalized_existing=$(normalize_gitignore_entry "$line")

        # Compare normalized entries
        if [[ "$normalized_new" == "$normalized_existing" ]]; then
            return 0  # Found semantic duplicate (silent)
        fi
    done < "$gitignore_file"

    return 1  # No semantic duplicates found
}

# -----------------------------------------------
# Normalize gitignore entry for semantic comparison
# Handles ./plugins vs /plugins vs plugins variations
# -----------------------------------------------
normalize_gitignore_entry() {
    local entry="$1"

    # Remove leading/trailing whitespace
    while [[ "$entry" =~ ^[[:space:]] ]]; do
        entry="${entry#[[:space:]]}"
    done
    while [[ "$entry" =~ [[:space:]]$ ]]; do
        entry="${entry%[[:space:]]}"
    done

    # Skip if empty after trimming
    [[ -z "$entry" ]] && return 1

    # Remove leading ./ if present (relative current directory notation)
    entry="${entry#./}"

    # Ensure leading slash (absolute path from git root)
    if [[ "$entry" != /* ]]; then
        entry="/$entry"
    fi

    # Remove trailing slash for consistent comparison
    entry="${entry%/}"

    # Special case: if we end up with just "/" (empty path), that's invalid
    if [[ "$entry" == "/" ]]; then
        return 1
    fi

    echo "$entry"
    return 0
}

# -----------------------------------------------
# Safely add entry to .gitignore with comprehensive validation
# -----------------------------------------------
add_gitignore_entry_safe() {
    local gitignore_file="$1"
    local entry="$2"
    local description="${3:-entry}"

    # Validate inputs
    if [[ -z "$gitignore_file" || -z "$entry" ]]; then
        printf "${RED}❌ Error: Invalid parameters for gitignore entry addition.${RESET}\n"
        return 1
    fi

    # Handle broken symlinks
    if [[ -L "$gitignore_file" && ! -e "$gitignore_file" ]]; then
        printf "${RED}❌ Error: '%s' is a broken symlink.${RESET}\n" "$(basename "$gitignore_file")"
        printf "${YELLOW}💡 Fix or remove the symlink and run again.${RESET}\n"
        printf "${YELLOW}💡 Command: rm '%s'${RESET}\n" "$gitignore_file"
        return 1
    fi

    # Create .gitignore if it doesn't exist
    if [[ ! -f "$gitignore_file" ]]; then
        if ! printf "%s\n" "$entry" > "$gitignore_file" 2>/dev/null; then
            printf "${RED}❌ Error: Could not create '%s'.${RESET}\n" "$(basename "$gitignore_file")"
            printf "${YELLOW}💡 Possible causes: permissions or read-only filesystem.${RESET}\n"
            local parent_dir="${gitignore_file%/*}"
            if [[ ! -w "$parent_dir" ]]; then
                printf "${YELLOW}💡 Parent directory not writable: %s${RESET}\n" "$parent_dir"
            fi
            return 1
        fi
        # Silent success for new file creation
        return 0
    fi

    # Validate existing file permissions
    if [[ ! -r "$gitignore_file" ]]; then
        printf "${RED}❌ Error: Cannot read '%s'.${RESET}\n" "$(basename "$gitignore_file")"
        printf "${YELLOW}💡 Check file permissions: ls -la '%s'${RESET}\n" "$gitignore_file"
        return 1
    fi

    if [[ ! -w "$gitignore_file" ]]; then
        printf "${RED}❌ Error: Cannot write to '%s'.${RESET}\n" "$(basename "$gitignore_file")"
        printf "${YELLOW}💡 Check permissions or hosting write restrictions.${RESET}\n"
        printf "${YELLOW}💡 You may need to run: chmod 644 '%s'${RESET}\n" "$gitignore_file"
        return 1
    fi

    # Enhanced duplicate checking with semantic equivalence
    if check_gitignore_semantic_duplicate "$gitignore_file" "$entry"; then
        return 0  # Found semantic duplicate, no need to add
    fi

    # Append entry safely with error handling
    # First ensure the file ends with a newline if it's not empty
    if [[ -s "$gitignore_file" ]]; then
        # Check if file ends with newline
        if [[ "$(tail -c1 "$gitignore_file" 2>/dev/null)" != "" ]]; then
            # File doesn't end with newline, add one
            printf "\n" >> "$gitignore_file" 2>/dev/null
        fi
    fi

    # Now add our entry
    if ! printf "%s\n" "$entry" >> "$gitignore_file" 2>/dev/null; then
        printf "${RED}❌ Error: Failed to append to '%s'.${RESET}\n" "$(basename "$gitignore_file")"
        printf "${YELLOW}💡 Possible causes: permissions, read-only filesystem, or disk space.${RESET}\n"

        # Check disk space if possible (Unix-compatible)
        if command -v df >/dev/null 2>&1; then
            local disk_usage
            disk_usage=$(df -h "${gitignore_file%/*}" 2>/dev/null | tail -1 | awk '{print $5}' 2>/dev/null || echo "unknown")
            if [[ "$disk_usage" != "unknown" ]]; then
                printf "${YELLOW}💡 Disk usage: %s${RESET}\n" "$disk_usage"
            fi
        fi
        return 1
    fi

    # Silent success for entry addition
    return 0
}

# -----------------------------------------------
# Main function: Add Stage File Proxy to .gitignore
# Enhanced for maximum Unix compatibility and integration
# -----------------------------------------------
add_stage_file_proxy_to_gitignore() {
    # Initialize colors if not already done
    if [[ -z "${GREEN:-}" ]]; then
        if command -v init_colors >/dev/null 2>&1; then
            init_colors
        else
            # Fallback color initialization
            if [[ -t 1 ]]; then
                RED=$'\033[0;31m'; GREEN=$'\033[0;32m'; YELLOW=$'\033[1;33m'
                BLUE=$'\033[0;34m'; CYAN=$'\033[0;36m'; RESET=$'\033[0m'
            else
                RED=""; GREEN=""; YELLOW=""; BLUE=""; CYAN=""; RESET=""
            fi
        fi
    fi



    # Auto-detect WordPress root directory
    local wp_root
    if ! wp_root=$(find_wordpress_root_gitignore); then
        printf "${RED}❌ Error: WordPress installation not found.${RESET}\n"
        printf "${YELLOW}💡 Please run this command from within a WordPress directory.${RESET}\n"
        printf "${YELLOW}💡 Expected files: wp-config.php, wp-content/${RESET}\n"
        return 1
    fi

    # Validate wp-content access
    if ! validate_wp_content_access "$wp_root"; then
        return 1
    fi

    local wp_content_dir="$wp_root/wp-content"
    local gitignore_file="$wp_content_dir/.gitignore"

    # Define the gitignore entry (using leading slash for exact path match from wp-content root)
    local gitignore_entry="/plugins/stage-file-proxy/"

    # Add the entry safely
    if add_gitignore_entry_safe "$gitignore_file" "$gitignore_entry" "stage-file-proxy plugin exclusion" >/dev/null 2>&1; then
        printf "${GREEN}✅ The Stage File Proxy plugin will now be ignored by Git.${RESET}\n"
        return 0
    else
        printf "\n${RED}❌ Failed to add Stage File Proxy to .gitignore${RESET}\n"
        printf "${YELLOW}💡 You may need to add it manually:${RESET}\n"
        printf "${YELLOW}   echo '%s' >> '%s'${RESET}\n" "$gitignore_entry" "$gitignore_file"
        return 1
    fi
}

# -----------------------------------------------
# Additional utility: Remove Stage File Proxy from .gitignore
# -----------------------------------------------
remove_stage_file_proxy_from_gitignore() {
    # Initialize colors if not already done
    if [[ -z "${GREEN:-}" ]] && command -v init_colors >/dev/null 2>&1; then
        init_colors
    fi

    printf "${CYAN}${BOLD:-}=== Removing Stage File Proxy from GitIgnore ===${RESET}\n"

    local wp_root
    if ! wp_root=$(find_wordpress_root_gitignore); then
        printf "${RED}❌ Error: WordPress installation not found.${RESET}\n"
        return 1
    fi

    local gitignore_file="$wp_root/wp-content/.gitignore"
    local gitignore_entry="/plugins/stage-file-proxy/"

    if [[ ! -f "$gitignore_file" ]]; then
        printf "${YELLOW}ℹ️  No .gitignore file found, nothing to remove.${RESET}\n"
        return 0
    fi

    # Check if entry exists
    if ! grep -qxF "$gitignore_entry" "$gitignore_file" 2>/dev/null; then
        printf "${YELLOW}ℹ️  Stage File Proxy entry not found in .gitignore.${RESET}\n"
        return 0
    fi

    # Create temporary file and remove the entry
    local temp_file
    temp_file=$(mktemp) || {
        printf "${RED}❌ Error: Could not create temporary file.${RESET}\n"
        return 1
    }

    if grep -vxF "$gitignore_entry" "$gitignore_file" > "$temp_file" 2>/dev/null &&
       mv "$temp_file" "$gitignore_file" 2>/dev/null; then
        printf "${GREEN}✅ Removed '%s' from .gitignore.${RESET}\n" "$gitignore_entry"
        return 0
    else
        rm -f "$temp_file" 2>/dev/null
        printf "${RED}❌ Error: Failed to remove entry from .gitignore.${RESET}\n"
        return 1
    fi
}

# -----------------------------------------------
# Additional utility: Show current gitignore status
# -----------------------------------------------
show_stage_file_proxy_gitignore_status() {
    # Initialize colors if not already done
    if [[ -z "${GREEN:-}" ]] && command -v init_colors >/dev/null 2>&1; then
        init_colors
    fi

    printf "${CYAN}${BOLD:-}=== Stage File Proxy GitIgnore Status ===${RESET}\n"

    local wp_root
    if ! wp_root=$(find_wordpress_root_gitignore); then
        printf "${RED}❌ Error: WordPress installation not found.${RESET}\n"
        return 1
    fi

    local gitignore_file="$wp_root/wp-content/.gitignore"
    local gitignore_entry="/plugins/stage-file-proxy/"

    printf "${BLUE}WordPress root: %s${RESET}\n" "$wp_root"
    printf "${BLUE}GitIgnore file: %s${RESET}\n" "$gitignore_file"

    if [[ ! -f "$gitignore_file" ]]; then
        printf "${YELLOW}📄 Status: No .gitignore file exists${RESET}\n"
        printf "${YELLOW}💡 Run add_stage_file_proxy_to_gitignore to create one${RESET}\n"
        return 1
    fi

    if grep -qxF "$gitignore_entry" "$gitignore_file" 2>/dev/null; then
        printf "${GREEN}✅ Status: Stage File Proxy is properly ignored${RESET}\n"
        printf "${GREEN}🛡️  Plugin commits are prevented${RESET}\n"
    else
        printf "${RED}❌ Status: Stage File Proxy is NOT ignored${RESET}\n"
        printf "${YELLOW}⚠️  Plugin might be accidentally committed${RESET}\n"
        printf "${YELLOW}💡 Run add_stage_file_proxy_to_gitignore to fix this${RESET}\n"
    fi

    # Show relevant gitignore content
    if [[ -r "$gitignore_file" ]]; then
        printf "\n${CYAN}📋 Current .gitignore entries (plugin-related):${RESET}\n"
        printf "${GRAY:-}────────────────────────────────────────${RESET}\n"
        grep -n "plugin" "$gitignore_file" 2>/dev/null | sed 's/^/  /' || printf "${GRAY:-}  (no plugin-related entries found)${RESET}\n"
        printf "${GRAY:-}────────────────────────────────────────${RESET}\n"
    fi
}

# -----------------------------------------------
# Export functions for external use
# -----------------------------------------------
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    {
        export -f add_stage_file_proxy_to_gitignore
        export -f remove_stage_file_proxy_from_gitignore
        export -f show_stage_file_proxy_gitignore_status
        export -f find_wordpress_root_gitignore
        export -f validate_wp_content_access
        export -f add_gitignore_entry_safe
        export -f check_gitignore_semantic_duplicate
        export -f normalize_gitignore_entry
    } >/dev/null 2>&1
fi
