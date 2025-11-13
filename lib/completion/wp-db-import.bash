#!/bin/bash

# ===============================================
# Bash Completion for wp-db-import command
# ===============================================
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
    complete -W "config-show config-create config-validate config-edit show-links setup-proxy show-cleanup update version --help" wp-db-import
    return 0
fi

# Main completion function for wp-db-import (Bash 4.0+)
_wp_db_import_completion() {
    local cur prev opts
    COMPREPLY=()
    cur="${COMP_WORDS[COMP_CWORD]}"
    prev="${COMP_WORDS[COMP_CWORD-1]}"

    # Define all available wp-db-import commands
    opts="config-show config-create config-validate config-edit show-links setup-proxy show-cleanup update version --help"

    # Generate completions based on current input
    case "$prev" in
        "wp-db-import")
            # Complete main commands
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
