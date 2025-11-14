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
            # Check for multiple zsh config files in order of preference
            ZSH_CONFIG_FILES=("$HOME/.zshrc" "$HOME/.zprofile" "$HOME/.zshenv")
            for config_file in "${ZSH_CONFIG_FILES[@]}"; do
                if [[ -f "$config_file" ]]; then
                    echo "export PATH=\"$CHOSEN_INSTALL_PATH:\$PATH\"" >> "$config_file"
                    printf "${GREEN}✅ Added to $(basename "$config_file")${RESET}\n"
                    printf "${YELLOW}🔄 Run: source $(basename "$config_file") (or restart terminal) to update PATH${RESET}\n"
                    break
                fi
            done
        elif [[ "$SHELL" == *"bash"* ]]; then
            # Check for multiple bash config files in order of preference (Linux vs macOS)
            BASH_CONFIG_FILES=("$HOME/.bash_profile" "$HOME/.bashrc" "$HOME/.profile")
            for config_file in "${BASH_CONFIG_FILES[@]}"; do
                if [[ -f "$config_file" ]]; then
                    echo "export PATH=\"$CHOSEN_INSTALL_PATH:\$PATH\"" >> "$config_file"
                    printf "${GREEN}✅ Added to $(basename "$config_file")${RESET}\n"
                    printf "${YELLOW}🔄 Run: source $(basename "$config_file") (or restart terminal) to update PATH${RESET}\n"
                    break
                fi
            done
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

# Install bash/zsh completion
printf "\n${CYAN}🔧 Setting up shell completion...${RESET}\n"

# Detect shell and install appropriate completion
if [[ "$SHELL" == */zsh ]] || [[ -n "$ZSH_VERSION" ]]; then
    # Zsh completion setup
    ZSH_COMPLETION_FILE="$SCRIPT_DIR/lib/completion/_wp-db-import"
    ZSH_COMPLETION_DIR="$HOME/.local/share/zsh/site-functions"
    ZSH_COMPLETION_SYMLINK="$ZSH_COMPLETION_DIR/_wp-db-import"

    if [[ -f "$ZSH_COMPLETION_FILE" ]]; then
        mkdir -p "$ZSH_COMPLETION_DIR"

        if ln -sf "$ZSH_COMPLETION_FILE" "$ZSH_COMPLETION_SYMLINK" 2>/dev/null; then
            printf "${GREEN}✅ Zsh completion installed${RESET}\n"
            printf "   Location: $ZSH_COMPLETION_SYMLINK\n"

            # Add to fpath if not already there - try multiple config files
            ZSH_CONFIG_FILES=("$HOME/.zshrc" "$HOME/.zprofile" "$HOME/.zshenv")
            ZSH_CONFIG_FOUND=false

            for config_file in "${ZSH_CONFIG_FILES[@]}"; do
                if [[ -f "$config_file" ]] && ! grep -q "$ZSH_COMPLETION_DIR" "$config_file" 2>/dev/null; then
                    printf "\n# wp-db-import completion" >> "$config_file"
                    printf "\nfpath=($ZSH_COMPLETION_DIR \$fpath)" >> "$config_file"
                    printf "\nautoload -U compinit && compinit" >> "$config_file"
                    printf "${GREEN}✅ Added completion to $(basename "$config_file")${RESET}\n"
                    ZSH_CONFIG_FOUND=true
                    break
                elif [[ -f "$config_file" ]] && grep -q "$ZSH_COMPLETION_DIR" "$config_file" 2>/dev/null; then
                    printf "${GREEN}✅ Completion already configured in $(basename "$config_file")${RESET}\n"
                    ZSH_CONFIG_FOUND=true
                    break
                fi
            done

            if [[ "$ZSH_CONFIG_FOUND" == "true" ]]; then
                printf "${YELLOW}   Note: Restart terminal or run 'source ~/.zshrc' for tab completion${RESET}\n"
            else
                printf "${YELLOW}   Note: No zsh config file found. You may need to manually add:${RESET}\n"
                printf "${YELLOW}   fpath=($ZSH_COMPLETION_DIR \$fpath) && autoload -U compinit && compinit${RESET}\n"
            fi
        else
            printf "${YELLOW}⚠️  Could not install zsh completion (non-critical)${RESET}\n"
        fi
    else
        printf "${YELLOW}⚠️  Zsh completion file not found (skipping)${RESET}\n"
    fi
else
    # Bash completion setup (original code)
    COMPLETION_FILE="$SCRIPT_DIR/lib/completion/wp-db-import.bash"
    COMPLETION_DIR="$HOME/.local/share/bash-completion/completions"
    COMPLETION_SYMLINK="$COMPLETION_DIR/wp-db-import"

    if [[ -f "$COMPLETION_FILE" ]]; then
        mkdir -p "$COMPLETION_DIR"

        if ln -sf "$COMPLETION_FILE" "$COMPLETION_SYMLINK" 2>/dev/null; then
            printf "${GREEN}✅ Bash completion installed${RESET}\n"
            printf "   Location: $COMPLETION_SYMLINK\n"

            # Check if bash-completion is available
            if command -v brew >/dev/null 2>&1 && brew list bash-completion >/dev/null 2>&1; then
                printf "${GREEN}✅ bash-completion package detected${RESET}\n"
            elif [[ -f "/usr/share/bash-completion/bash_completion" ]] || [[ -f "/etc/bash_completion" ]]; then
                printf "${GREEN}✅ System bash-completion detected${RESET}\n"
            else
                printf "${YELLOW}💡 For tab completion to work, install bash-completion:${RESET}\n"
                printf "   ${BOLD}brew install bash-completion${RESET} (macOS)\n"
                printf "   ${BOLD}sudo apt install bash-completion${RESET} (Ubuntu/Debian)\n"
            fi
        else
            printf "${YELLOW}⚠️  Could not install bash completion (non-critical)${RESET}\n"
        fi
    else
        printf "${YELLOW}⚠️  Completion file not found (skipping)${RESET}\n"
    fi
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
printf "wp-db-import show-cleanup       # Generate database revision cleanup commands\n"
printf "wp-db-import setup-proxy        # Auto-setup stage file proxy (detects config)\n"
printf "wp-db-import update             # Update to latest version\n"
printf "wp-db-import version            # Show version and git info\n"
printf "wp-db-import --help             # Show help\n"
printf "\n${CYAN}💡 Tab Completion:${RESET} Type 'wp-db-import ' and press TAB to see all commands\n"

printf "\n${CYAN}${BOLD}🔍 Testing Installation${RESET}\n"
printf "======================\n"
printf "Run: ${BOLD}wp-db-import --help${RESET} to verify installation\n"

printf "\n${GREEN}${BOLD}🎉 Installation complete!${RESET}\n"
