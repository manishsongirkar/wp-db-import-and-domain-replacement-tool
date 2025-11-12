#!/bin/bash

# ===============================================
# WordPress Database Import Tool - Installation Script
# ===============================================
#
# This script installs the wp-db-import command globally
# so it can be used from any directory.
#
# Usage: ./install.sh
#
# ===============================================

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MAIN_EXECUTABLE="$SCRIPT_DIR/wp-db-import"

# Load utilities for colors and common functions
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

printf "${CYAN}${BOLD}WordPress Database Import Tool - Installation${RESET}\n"
printf "=====================================================\n\n"

# Detect installation type
if git -C "$SCRIPT_DIR" rev-parse --git-dir >/dev/null 2>&1; then
    printf "${GREEN}✅ Git repository detected${RESET}\n"
    printf "   Auto-updates will be available via 'wp-db-import update'\n\n"
else
    printf "${YELLOW}📦 ZIP archive installation detected${RESET}\n"
    printf "   For auto-updates, consider cloning the git repository instead:\n"
    printf "   ${BOLD}git clone https://github.com/manishsongirkar/wp-db-import-and-domain-replacement-tool.git${RESET}\n\n"
fi

# Check if main executable exists
if [[ ! -f "$MAIN_EXECUTABLE" ]]; then
    printf "${RED}❌ Error: Main executable not found at: $MAIN_EXECUTABLE${RESET}\n"
    exit 1
fi

# Check if executable has proper permissions
if [[ ! -x "$MAIN_EXECUTABLE" ]]; then
    printf "${CYAN}🔧 Making wp-db-import executable...${RESET}\n"
    chmod +x "$MAIN_EXECUTABLE"
fi

# Determine the best installation method (prioritizing user-local installation)
printf "${CYAN}� Installing wp-db-import command...${RESET}\n\n"

# Modern approach: Use user-local installation paths like npm, cargo, etc.
INSTALL_METHOD="user"

# Try multiple user-local installation paths in order of preference
USER_INSTALL_PATHS=(
    "$HOME/.local/bin"    # XDG Base Directory standard (preferred)
    "$HOME/bin"           # Traditional Unix user bin
)

# Check for existing user bin directories or create the preferred one
CHOSEN_INSTALL_PATH=""
for path in "${USER_INSTALL_PATHS[@]}"; do
    if [[ -d "$path" ]]; then
        CHOSEN_INSTALL_PATH="$path"
        printf "${CYAN}� Found existing user bin directory: $path${RESET}\n"
        break
    fi
done

# If no existing directory found, create the preferred one (.local/bin)
if [[ -z "$CHOSEN_INSTALL_PATH" ]]; then
    CHOSEN_INSTALL_PATH="${USER_INSTALL_PATHS[0]}"  # Use ~/.local/bin
    printf "${CYAN}📁 Creating user bin directory: $CHOSEN_INSTALL_PATH${RESET}\n"
    mkdir -p "$CHOSEN_INSTALL_PATH"
fi

printf "${CYAN}📦 Installing to $CHOSEN_INSTALL_PATH...${RESET}\n"

# Install to chosen user directory
if ln -sf "$MAIN_EXECUTABLE" "$CHOSEN_INSTALL_PATH/wp-db-import"; then
    printf "${GREEN}✅ Successfully installed to $CHOSEN_INSTALL_PATH/wp-db-import${RESET}\n"
    INSTALL_PATH="$CHOSEN_INSTALL_PATH/wp-db-import"

    # Check if the chosen path is in PATH and add it if necessary
    if [[ ":$PATH:" != *":$CHOSEN_INSTALL_PATH:"* ]]; then
        printf "\n${YELLOW}⚠️  $CHOSEN_INSTALL_PATH is not in your PATH${RESET}\n"
        printf "${CYAN}📝 Adding $CHOSEN_INSTALL_PATH to your shell configuration...${RESET}\n"

        # Determine shell and add to appropriate config file
        if [[ "$SHELL" == *"zsh"* ]]; then
            echo "export PATH=\"$CHOSEN_INSTALL_PATH:\$PATH\"" >> "$HOME/.zshrc"
            printf "${GREEN}✅ Added to ~/.zshrc${RESET}\n"
            printf "${YELLOW}🔄 Run: source ~/.zshrc (or restart terminal) to update PATH${RESET}\n"
        elif [[ "$SHELL" == *"bash"* ]]; then
            # Check for .bash_profile or .bashrc
            if [[ -f "$HOME/.bash_profile" ]]; then
                echo "export PATH=\"$CHOSEN_INSTALL_PATH:\$PATH\"" >> "$HOME/.bash_profile"
                printf "${GREEN}✅ Added to ~/.bash_profile${RESET}\n"
                printf "${YELLOW}🔄 Run: source ~/.bash_profile (or restart terminal) to update PATH${RESET}\n"
            else
                echo "export PATH=\"$CHOSEN_INSTALL_PATH:\$PATH\"" >> "$HOME/.bashrc"
                printf "${GREEN}✅ Added to ~/.bashrc${RESET}\n"
                printf "${YELLOW}🔄 Run: source ~/.bashrc (or restart terminal) to update PATH${RESET}\n"
            fi
        else
            printf "${YELLOW}💡 Manually add this to your shell config:${RESET}\n"
            printf "   export PATH=\"$CHOSEN_INSTALL_PATH:\$PATH\"\n"
        fi
    else
        printf "${GREEN}✅ $CHOSEN_INSTALL_PATH is already in your PATH${RESET}\n"
    fi
else
    printf "${RED}❌ Failed to install to $CHOSEN_INSTALL_PATH${RESET}\n"
    INSTALL_METHOD="failed"
fi

# Installation result
printf "\n${CYAN}${BOLD}📋 Installation Summary${RESET}\n"
printf "==========================\n"

if [[ "$INSTALL_METHOD" == "user" && -n "$INSTALL_PATH" ]]; then
    printf "${GREEN}✅ User-local installation successful${RESET}\n"
    printf "   Command available: ${BOLD}wp-db-import${RESET}\n"
    printf "   Location: $INSTALL_PATH\n"
    if [[ ":$PATH:" != *":$CHOSEN_INSTALL_PATH:"* ]]; then
        printf "   ${YELLOW}Note: Restart terminal or source shell config for PATH update${RESET}\n"
    fi
else
    printf "${RED}❌ Installation failed${RESET}\n"
    printf "${YELLOW}💡 Alternative: Run directly using the full path:${RESET}\n"
    printf "   $MAIN_EXECUTABLE\n"
    exit 1
fi

printf "\n${CYAN}${BOLD}🚀 Usage Examples${RESET}\n"
printf "================\n"
printf "cd ~/Local\\ Sites/mysite/app/public\n"
printf "wp-db-import                    # Main import wizard\n"
printf "wp-db-import show-links         # Show local site links\n"
printf "wp-db-import show-cleanup       # Show revision cleanup commands\n"
printf "wp-db-import setup-proxy        # Configure stage file proxy\n"
printf "wp-db-import update             # Update to latest version\n"
printf "wp-db-import version            # Show version and git info\n"
printf "wp-db-import --help             # Show help\n"

printf "\n${CYAN}${BOLD}🔍 Testing Installation${RESET}\n"
printf "======================\n"
printf "Run: ${BOLD}wp-db-import --help${RESET} to verify installation\n"

printf "\n${GREEN}${BOLD}🎉 Installation complete!${RESET}\n"
