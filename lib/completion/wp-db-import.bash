#!/usr/bin/env bash
# shellcheck disable=SC2207  # COMPREPLY=($(compgen ...)) is the portable form: mapfile needs Bash 4

# ===============================================
# Bash Completion for wp-db-import command
# ===============================================
#
# Description:
#   Tab completion for `wp-db-import` (and for ./uninstall.sh) in Bash 3.2 and newer.
#   One code path for all versions: no Bash 4 features are used.
#
# Completes:
#   wp-db-import <TAB>              the subcommands
#   wp-db-import -<TAB>             global options (--yes -y --non-interactive --dry-run --help)
#   wp-db-import --yes res<TAB>     a global option before the subcommand is fine
#   wp-db-import restore <TAB>      --list --last --all, and backup files (.sql .gz .zip .bz2 .gpg)
#   wp-db-import test <TAB>         test suite names, and the test runner options
#   wp-db-import test --format <TAB>  json html text all
#   wp-db-import detect -<TAB>      --verbose --quiet
#   wp-db-import show-cleanup <TAB> directories
#   ./uninstall.sh -<TAB>           --yes --delete-backups --keep-backups
#
# Keep in sync with: wp-db-import --help, the case list of run_tests.sh and uninstall.sh
# (a unit test, test_completions.sh, checks it).
#
# Installation:
#   This file is automatically sourced when wp-db-import is installed
#

# ===============================================
# wp-db-import
# ===============================================
#
# Description: Completion function. Reads COMP_WORDS / COMP_CWORD (set by Bash) and sets COMPREPLY.
#
# Behavior:
#   - The subcommand is the first word after the command that does not start with a dash,
#     so a global option can come before it.
#   - Without a subcommand: complete subcommands (or options when the word starts with a dash).
#   - With a subcommand: complete the arguments of that subcommand.
#
_wp_db_import_completion() {
    local cur prev cmd="" w i
    local cmds="config-show config-create config-validate config-edit show-links setup-proxy show-cleanup detect doctor restore update version test"
    local flags="--yes -y --non-interactive --dry-run"
    local suites="all compatibility bash system unit wordpress validation security matrix real-import"
    local IFS=$' \t\n'

    COMPREPLY=()
    cur="${COMP_WORDS[COMP_CWORD]}"
    prev=""
    [[ $COMP_CWORD -gt 0 ]] && prev="${COMP_WORDS[COMP_CWORD-1]}"

    for ((i = 1; i < COMP_CWORD; i++)); do
        w="${COMP_WORDS[i]}"
        case "$w" in
            -*) ;;
            *) cmd="$w"; break ;;
        esac
    done

    case "$cmd" in
        "")
            if [[ "$cur" == -* ]]; then
                COMPREPLY=($(compgen -W "$flags --help" -- "$cur"))
            else
                COMPREPLY=($(compgen -W "$cmds" -- "$cur"))
            fi
            ;;
        restore)
            if [[ "$cur" == -* ]]; then
                COMPREPLY=($(compgen -W "--list --last --all $flags" -- "$cur"))
            else
                # backup files (.sql, .sql.gz, .zip, .sql.bz2) and directories to browse
                # (a case filter, not compgen -X with extglob: extglob is off in most shells)
                local IFS=$'\n' f
                COMPREPLY=($(compgen -d -S / -- "$cur"))
                for f in $(compgen -f -- "$cur"); do
                    case "$f" in
                        *.sql|*.gz|*.zip|*.bz2|*.gpg) [[ -d "$f" ]] || COMPREPLY+=("$f") ;;
                    esac
                done
            fi
            ;;
        test)
            case "$prev" in
                --format) COMPREPLY=($(compgen -W "json html text all" -- "$cur")) ;;
                --output) local IFS=$'\n'; COMPREPLY=($(compgen -d -S / -- "$cur")) ;;
                *)
                    if [[ "$cur" == -* ]]; then
                        COMPREPLY=($(compgen -W "--verbose --quick --parallel --ci --format --output --help" -- "$cur"))
                    else
                        COMPREPLY=($(compgen -W "$suites" -- "$cur"))
                    fi
                    ;;
            esac
            ;;
        detect)
            if [[ "$cur" == -* ]]; then
                COMPREPLY=($(compgen -W "--verbose --quiet -v -q" -- "$cur"))
            else
                local IFS=$'\n'
                COMPREPLY=($(compgen -d -S / -- "$cur"))
            fi
            ;;
        show-cleanup)
            if [[ "$cur" == -* ]]; then
                COMPREPLY=($(compgen -W "$flags" -- "$cur"))
            else
                local IFS=$'\n'
                COMPREPLY=($(compgen -d -S / -- "$cur"))
            fi
            ;;
        *)
            # config-*, doctor, update, version, show-links, setup-proxy: only the global options
            if [[ "$cur" == -* ]]; then
                COMPREPLY=($(compgen -W "$flags --help" -- "$cur"))
            fi
            ;;
    esac
    return 0
}

# ===============================================
# uninstall.sh
# ===============================================
_wp_db_import_uninstall_completion() {
    local cur="${COMP_WORDS[COMP_CWORD]}"
    COMPREPLY=($(compgen -W "--yes -y --delete-backups --keep-backups --help" -- "$cur"))
    return 0
}

# Register (Bash looks up a path such as ./uninstall.sh by its last part)
complete -F _wp_db_import_completion wp-db-import
complete -F _wp_db_import_uninstall_completion uninstall.sh
