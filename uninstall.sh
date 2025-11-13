#!/bin/bash

# ===============================================
# WordPress Database Import Tool - Uninstaller
# ===============================================
#
# This script removes the wp-db-import command
# from your system.
#
# Usage: ./uninstall.sh
#
# ===============================================

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
    exit 0
fi

printf "\n${CYAN}📋 Found ${#FOUND_INSTALLATIONS[@]} installation(s)${RESET}\n"
printf "Do you want to remove all installations? (y/N): "
read -r confirm_removal

if [[ "$confirm_removal" != [Yy]* ]]; then
    printf "${YELLOW}⚠️  Uninstallation cancelled${RESET}\n"
    exit 0
fi

printf "\n${CYAN}🗑️  Removing wp-db-import installations...${RESET}\n"

REMOVED_COUNT=0
FAILED_COUNT=0

for installation in "${FOUND_INSTALLATIONS[@]}"; do
    printf "   Removing: $installation... "

    if rm -f "$installation" 2>/dev/null; then
        printf "${GREEN}✅ Removed${RESET}\n"
        ((REMOVED_COUNT++))
    else
        # Try with sudo if it's in system location
        if [[ "$installation" == "/usr/local/bin/"* ]]; then
            printf "\n   ${YELLOW}Requires sudo for system location...${RESET}\n"
            if sudo rm -f "$installation" 2>/dev/null; then
                printf "   ${GREEN}✅ Removed with sudo${RESET}\n"
                ((REMOVED_COUNT++))
            else
                printf "   ${RED}❌ Failed to remove${RESET}\n"
                ((FAILED_COUNT++))
            fi
        else
            printf "${RED}❌ Failed${RESET}\n"
            ((FAILED_COUNT++))
        fi
    fi
done

# Remove shell completions
printf "\n${CYAN}🔧 Removing shell completions...${RESET}\n"

# Remove bash completion
BASH_COMPLETION_SYMLINK="$HOME/.local/share/bash-completion/completions/wp-db-import"
if [[ -L "$BASH_COMPLETION_SYMLINK" || -f "$BASH_COMPLETION_SYMLINK" ]]; then
    if rm -f "$BASH_COMPLETION_SYMLINK" 2>/dev/null; then
        printf "${GREEN}✅ Bash completion removed${RESET}\n"
    else
        printf "${YELLOW}⚠️  Could not remove bash completion${RESET}\n"
    fi
fi

# Remove zsh completion
ZSH_COMPLETION_SYMLINK="$HOME/.local/share/zsh/site-functions/_wp-db-import"
if [[ -L "$ZSH_COMPLETION_SYMLINK" || -f "$ZSH_COMPLETION_SYMLINK" ]]; then
    if rm -f "$ZSH_COMPLETION_SYMLINK" 2>/dev/null; then
        printf "${GREEN}✅ Zsh completion removed${RESET}\n"
    else
        printf "${YELLOW}⚠️  Could not remove zsh completion${RESET}\n"
    fi
fi

if [[ ! -L "$BASH_COMPLETION_SYMLINK" && ! -f "$BASH_COMPLETION_SYMLINK" &&
      ! -L "$ZSH_COMPLETION_SYMLINK" && ! -f "$ZSH_COMPLETION_SYMLINK" ]]; then
    printf "${CYAN}   No shell completions found${RESET}\n"
fi

printf "\n${CYAN}${BOLD}📋 Uninstallation Summary${RESET}\n"
printf "============================\n"

if [[ $REMOVED_COUNT -gt 0 ]]; then
    printf "${GREEN}✅ Successfully removed $REMOVED_COUNT installation(s)${RESET}\n"
fi

if [[ $FAILED_COUNT -gt 0 ]]; then
    printf "${RED}❌ Failed to remove $FAILED_COUNT installation(s)${RESET}\n"
    printf "   You may need to manually remove remaining files\n"
fi

# Note about PATH modifications
printf "\n${YELLOW}📝 Note:${RESET}\n"
printf "   PATH modifications in shell config files (.zshrc, .bashrc, etc.)\n"
printf "   have not been automatically removed. You may want to clean them up manually\n"
printf "   if you no longer need user bin directories in your PATH.\n"

if [[ $REMOVED_COUNT -gt 0 && $FAILED_COUNT -eq 0 ]]; then
    printf "\n${GREEN}${BOLD}🎉 Uninstallation complete!${RESET}\n"
else
    printf "\n${YELLOW}⚠️  Uninstallation completed with some issues${RESET}\n"
fi
