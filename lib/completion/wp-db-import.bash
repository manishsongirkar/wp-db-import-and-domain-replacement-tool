#!/usr/bin/env bash

# ===============================================
# Bash Completion for wp-db-import command
# ===============================================
#
# Description:
#   Provides command-line tab completion for the `wp-db-import` tool in Bash.
#   It lists available subcommands when the user hits <TAB> after the main command.
#
# Compatible with Bash 4.0+ and modern completion systems
# Gracefully degrades on older systems
#
# Installation:
#   This file is automatically sourced when wp-db-import is installed
#
# Usage:
#   wp-db-import <TAB>  # Shows all available commands
#   wp-db-import conf<TAB>  # Completes to config-* commands
#

# Check bash version compatibility
if [[ ${BASH_VERSINFO[0]} -lt 4 ]]; then
    # Minimal completion for Bash 3.x
    complete -W "config-show config-create config-validate config-edit show-links setup-proxy show-cleanup update version test --help --yes -y --non-interactive" wp-db-import
    return 0
fi

# ===============================================
# WP-DB-Import Completion
# ===============================================
#
# Description: Main completion function for Bash 4.0+ environments.
#
# Parameters:
#	- Uses global COMP_WORDS and COMP_CWORD provided by the Bash completion system.
#
# Returns:
#	- 0 (Success) after setting the COMPREPLY array.
#
# Behavior:
#	- Defines all available subcommands in the 'opts' variable.
#	- Uses 'compgen -W' to filter the list based on the user's current input ('$cur').
#	- Only provides completions immediately after 'wp-db-import'.
#
_wp_db_import_completion() {
    local cur prev opts
    COMPREPLY=()
    cur="${COMP_WORDS[COMP_CWORD]}"
    prev="${COMP_WORDS[COMP_CWORD-1]}"

    # Define all available wp-db-import commands
    opts="config-show config-create config-validate config-edit show-links setup-proxy show-cleanup update version test --help"
    # Global options (accepted in any position): unattended mode for scripts and CI
    local flags="--yes -y --non-interactive"

    # Typing a dash: offer the options
    if [[ "$cur" == -* ]]; then
        COMPREPLY=($(compgen -W "$flags --help" -- "$cur"))
        return 0
    fi

    # Generate completions based on current input
    case "$prev" in
        "wp-db-import")
            # Complete main commands
            COMPREPLY=($(compgen -W "$opts" -- "$cur"))
            return 0
            ;;
        --yes|-y|--non-interactive)
            # An option was already typed: the command can follow
            COMPREPLY=($(compgen -W "$opts" -- "$cur"))
            return 0
            ;;
        *)
            # No further completion needed for most commands
            return 0
            ;;
    esac
}

# Register the completion function
complete -F _wp_db_import_completion wp-db-import
