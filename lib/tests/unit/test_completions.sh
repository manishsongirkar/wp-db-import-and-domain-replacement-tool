#!/usr/bin/env bash

# ================================================================
# Shell Completions - Tests
# ================================================================
#
# Description:
#   Tests for issue #26. The completion files must stay in step with the tool:
#     - syntax: Bash 3.2 and the running Bash (bash -n), zsh -n (skipped when zsh is missing)
#     - every command and option in `wp-db-import --help` is in both files
#     - every command the dispatcher handles is in both files (hidden ones are listed here)
#     - the suite names equal the ones run_tests.sh accepts; uninstall.sh options are covered
#     - the Bash function really completes (run in Bash 3.2 and the running Bash): commands,
#       options, a global option before the command, restore files, test suites and --format,
#       detect, show-cleanup, no hidden alias (--quite), and uninstall.sh
#     - the Zsh file offers the same things (mocked _arguments/_describe)
#
# Usage:
#   ./lib/tests/unit/test_completions.sh
#
# ================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../test_framework.sh"

_CP_ROOT="$PROJECT_ROOT_DIR"
_CP_BASH="$_CP_ROOT/lib/completion/wp-db-import.bash"
_CP_ZSH="$_CP_ROOT/lib/completion/_wp-db-import"
_CP_WORK=""
# Commands the dispatcher handles that are private (not in --help) and so not completed
_CP_HIDDEN="validate"

_chk() {
    local desc="$1"; shift
    if "$@" >/dev/null 2>&1; then
        printf "  ✅ %s\n" "$desc"
    else
        printf "  ❌ %s\n" "$desc"
        ((errors++))
    fi
}
_finish() { if [[ "$errors" -eq 0 ]]; then pass_test "$1"; else fail_test "$errors check(s) failed"; fi; }
_strip() { sed 's/\x1b\[[0-9;]*[a-zA-Z]//g'; }

# Completes a command line in the given Bash. Parameters: bash binary, command line (the cursor is at
# the end; a trailing space means a new word), optional directory to run in. Prints one candidate per line.
_cp_complete() {
    local bin="$1" line="$2" dir="${3:-$_CP_WORK}"
    ( cd "$dir" && "$bin" -c '
        source "$1"
        line="$2"
        set -f; read -r -a COMP_WORDS <<< "$line"; set +f
        if [[ "$line" == *" " ]]; then COMP_WORDS+=(""); fi
        COMP_CWORD=$(( ${#COMP_WORDS[@]} - 1 ))
        COMP_LINE="$line"; COMP_POINT=${#line}
        fn=$(complete -p "${COMP_WORDS[0]##*/}" | sed -n "s/.*-F \([^ ]*\) .*/\1/p")
        [[ -n "$fn" ]] || exit 3
        "$fn"
        printf "%s\n" "${COMPREPLY[@]}"
    ' _ "$_CP_BASH" "$line" ) 2>&1
}

_cp_has()  { grep -qxF -- "$2" <<< "$1"; }
_cp_none() { ! grep -qxF -- "$2" <<< "$1"; }

# ----------------------------------------------------------------
test_syntax() {
    start_test "Syntax" "both files parse in every shell they are used in"
    local errors=0
    _chk "Bash completion: bash -n (running Bash)"      bash -n "$_CP_BASH"
    _chk "Bash completion: Bash 3.2 (/bin/bash) -n"      /bin/bash -n "$_CP_BASH"
    if command -v zsh >/dev/null 2>&1; then
        _chk "Zsh completion: zsh -n"                    zsh -n "$_CP_ZSH"
    else
        printf "  ℹ️  zsh not installed: zsh -n skipped\n"
    fi
    _chk "no Bash 4 only feature (mapfile, associative arrays, \${var,,})" bash -c '! grep -nE "mapfile|readarray|declare -A|\$\{[A-Za-z_]+(,,|\^\^)\}" "$0" | grep -v "^[0-9]*:#"' "$_CP_BASH"
    _chk "sourcing the Bash file prints nothing"         bash -c '[[ -z "$(source "$0" 2>&1)" ]]' "$_CP_BASH"
    _chk "sourcing it in Bash 3.2 prints nothing"        /bin/bash -c '[[ -z "$(source "$0" 2>&1)" ]]' "$_CP_BASH"
    _finish "syntax is valid"
}

# ----------------------------------------------------------------
test_sync_with_tool() {
    start_test "Sync with the tool" "help, dispatcher, test suites and uninstall.sh options are all completed"
    local errors=0 help cmd flag suites u
    help=$(bash "$_CP_ROOT/wp-db-import" --help 2>&1 | _strip)

    # commands listed in --help: "  wp-db-import <command> ..." (not options, not the bare tool)
    local help_cmds
    help_cmds=$(sed -n 's/^  wp-db-import \([a-z][a-z-]*\).*/\1/p' <<< "$help" | sort -u)
    _chk "--help lists commands (sanity: more than 8)"   test "$(wc -l <<< "$help_cmds" | tr -d ' ')" -gt 8
    for cmd in $help_cmds; do
        _chk "Bash completes the help command: $cmd"      grep -qE "cmds=\"[^\"]*\b$cmd\b" "$_CP_BASH"
        _chk "Zsh completes the help command: $cmd"       grep -q "'$cmd:" "$_CP_ZSH"
    done

    # options listed in --help (global and per command)
    for flag in --yes -y --non-interactive --dry-run --help; do
        _chk "Bash knows $flag"                           grep -q -- "$flag" "$_CP_BASH"
        _chk "Zsh knows $flag"                            grep -q -- "$flag" "$_CP_ZSH"
    done

    # every command the dispatcher handles (case labels) is completed, except the private ones
    local labels
    labels=$(sed -n 's/^    \([a-z][a-z-]*\)\(|[-a-z|]*\)\{0,1\})$/\1/p' "$_CP_ROOT/wp-db-import" | sort -u)
    for cmd in $labels; do
        case " $_CP_HIDDEN help version update " in *" $cmd "*) [[ " $_CP_HIDDEN " == *" $cmd "* ]] && continue ;; esac
        _chk "dispatcher command '$cmd' is in the Bash list"  grep -qE "cmds=\"[^\"]*\b$cmd\b" "$_CP_BASH"
        _chk "dispatcher command '$cmd' is in the Zsh list"   grep -q "'$cmd:" "$_CP_ZSH"
    done

    # test suite names = what run_tests.sh accepts
    suites=$(sed -n 's/^ *all|\(.*\))$/all|\1/p' "$_CP_ROOT/run_tests.sh" | head -1 | tr '|' ' ')
    _chk "found the run_tests.sh suite list"             test -n "$suites"
    _chk "the Bash suite list equals run_tests.sh"       bash -c 'b=$(sed -n "s/^    local suites=\"\(.*\)\"/\1/p" "$1" | tr " " "\n" | sort | tr "\n" " "); r=$(printf "%s\n" $2 | sort | tr "\n" " "); [[ "$b" == "$r" ]]' _ "$_CP_BASH" "$suites"
    _chk "the Zsh suite list equals run_tests.sh"        bash -c 'b=$(sed -n "s/^ *suites=(\(.*\))$/\1/p" "$1" | tr " " "\n" | sort | tr "\n" " "); r=$(printf "%s\n" $2 | sort | tr "\n" " "); [[ "$b" == "$r" ]]' _ "$_CP_ZSH" "$suites"

    # uninstall.sh options
    for u in $(sed -n 's/^ *\(-y|--yes\|--[a-z-]*\)) .*/\1/p' "$_CP_ROOT/uninstall.sh" | tr '|' ' '); do
        _chk "uninstall.sh option $u is completed (Bash)" grep -q -- "$u" "$_CP_BASH"
        _chk "uninstall.sh option $u is completed (Zsh)"  grep -q -- "$u" "$_CP_ZSH"
    done

    # detect options from the dispatcher
    _chk "detect: --verbose and --quiet are offered, --quite is not (hidden alias)" bash -c 'grep -q -- "--quiet" "$0" && ! grep -q -- "--quite" "$0" && ! grep -q -- "--quite" "$1"' "$_CP_BASH" "$_CP_ZSH"
    _finish "the completion files match the tool"
}

# ----------------------------------------------------------------
test_bash_behavior() {
    start_test "Bash behavior" "the function completes correctly in Bash 3.2 and the running Bash"
    local errors=0 bin out
    mkdir -p "$_CP_WORK/dir_a" "$_CP_WORK/bk"
    : > "$_CP_WORK/bk/site-20261009.sql.gz"; : > "$_CP_WORK/bk/dump.sql"; : > "$_CP_WORK/bk/notes.txt"; : > "$_CP_WORK/bk/pack.zip"; : > "$_CP_WORK/bk/old.sql.bz2"; : > "$_CP_WORK/bk/site-20261009.sql.gz.gpg"

    for bin in /bin/bash "$BASH"; do
        local tag="[$(basename "$bin") $("$bin" -c 'echo ${BASH_VERSINFO[0]}.${BASH_VERSINFO[1]}')]"
        out=$(_cp_complete "$bin" "wp-db-import ")
        _chk "$tag all commands after the tool name"       bash -c 'for c in config-show config-create config-validate config-edit show-links setup-proxy show-cleanup detect doctor restore update version test; do grep -qxF "$c" <<< "$0" || exit 1; done' "$out"
        _chk "$tag no option is mixed into the commands"   bash -c '! grep -q "^-" <<< "$0"' "$out"
        out=$(_cp_complete "$bin" "wp-db-import re")
        _chk "$tag 're' completes to restore"              test "$out" = "restore"
        out=$(_cp_complete "$bin" "wp-db-import d")
        _chk "$tag 'd' offers detect and doctor"           bash -c 'grep -qx detect <<< "$0" && grep -qx doctor <<< "$0"' "$out"
        out=$(_cp_complete "$bin" "wp-db-import -")
        _chk "$tag a dash offers the global options"       bash -c 'for f in --yes -y --non-interactive --dry-run --help; do grep -qxF -- "$f" <<< "$0" || exit 1; done' "$out"
        out=$(_cp_complete "$bin" "wp-db-import --yes res")
        _chk "$tag an option before the command: 'res' -> restore" test "$out" = "restore"
        out=$(_cp_complete "$bin" "wp-db-import --dry-run ")
        _chk "$tag after an option the commands are offered" bash -c 'grep -qxF restore <<< "$0"' "$out"
        out=$(_cp_complete "$bin" "wp-db-import restore -")
        _chk "$tag restore: --list --last --all"           bash -c 'for f in --list --last --all; do grep -qxF -- "$f" <<< "$0" || exit 1; done' "$out"
        out=$(_cp_complete "$bin" "wp-db-import restore bk/")
        _chk "$tag restore: .sql .sql.gz .zip .sql.bz2 .gpg offered" bash -c 'for f in bk/site-20261009.sql.gz bk/dump.sql bk/pack.zip bk/old.sql.bz2 bk/site-20261009.sql.gz.gpg; do grep -qxF "$f" <<< "$0" || exit 1; done' "$out"
        _chk "$tag restore: other files are not offered"   bash -c '! grep -qF "notes.txt" <<< "$0"' "$out"
        out=$(_cp_complete "$bin" "wp-db-import restore --yes bk/s")
        _chk "$tag restore after an option still completes files" bash -c 'grep -qxF bk/site-20261009.sql.gz <<< "$0"' "$out"
        out=$(_cp_complete "$bin" "wp-db-import test ")
        _chk "$tag test: all suite names"                  bash -c 'for s in all compatibility bash system unit wordpress validation security matrix real-import; do grep -qxF "$s" <<< "$0" || exit 1; done' "$out"
        out=$(_cp_complete "$bin" "wp-db-import test --")
        _chk "$tag test: the runner options"               bash -c 'for f in --verbose --quick --parallel --ci --format --output --help; do grep -qxF -- "$f" <<< "$0" || exit 1; done' "$out"
        out=$(_cp_complete "$bin" "wp-db-import test --format ")
        _chk "$tag test --format: json html text all"      bash -c 'test "$(sort <<< "$0" | tr "\n" " ")" = "all html json text "' "$out"
        out=$(_cp_complete "$bin" "wp-db-import detect --")
        _chk "$tag detect: --verbose and --quiet, not --quite" bash -c 'grep -qxF -- --verbose <<< "$0" && grep -qxF -- --quiet <<< "$0" && ! grep -q -- "--quite" <<< "$0"' "$out"
        out=$(_cp_complete "$bin" "wp-db-import show-cleanup dir")
        _chk "$tag show-cleanup completes directories"     test "$out" = "dir_a/"
        out=$(_cp_complete "$bin" "wp-db-import doctor ")
        _chk "$tag doctor takes no further words"          test -z "$out"
        out=$(_cp_complete "$bin" "wp-db-import config-show ")
        _chk "$tag config-show takes no further words"     test -z "$out"
        out=$(_cp_complete "$bin" "wp-db-import version -")
        _chk "$tag a command with no options still offers the global ones" bash -c 'grep -qxF -- --yes <<< "$0"' "$out"
        out=$(_cp_complete "$bin" "./uninstall.sh -")
        _chk "$tag ./uninstall.sh options"                 bash -c 'for f in --yes -y --delete-backups --keep-backups --help; do grep -qxF -- "$f" <<< "$0" || exit 1; done' "$out"
        out=$(_cp_complete "$bin" "wp-db-import xyz")
        _chk "$tag an unknown prefix offers nothing"       test -z "$out"
    done
    _finish "Bash completion behaves"
}

# ----------------------------------------------------------------
# The Zsh file with _arguments / _describe / _files replaced by recorders: checks which words
# each context offers (it cannot check zsh's own matching).
_cp_zsh_ctx() {
    local service="$1" state="$2"; shift 2
    zsh -f -c '
        service="$1"; state_wanted="$2"; shift 2
        words=("$@")
        _arguments() { print -r -- "ARGS: $*"; if [[ "$1" == "-C" ]]; then state="$state_wanted"; return 1; fi; }
        _describe()  { shift 3; local a; for a in "${(P@)1}"; do print -r -- "DESC: $a"; done; }
        _files()       { print -r -- "FILES: $*"; }
        _directories() { print -r -- "DIRS"; }
        source "'"$_CP_ZSH"'"
    ' _ "$service" "$state" "$@" 2>&1
}

test_zsh_behavior() {
    start_test "Zsh behavior" "each context offers the right commands and options (mocked completion helpers)"
    local errors=0 out
    if ! command -v zsh >/dev/null 2>&1; then
        printf "  ℹ️  zsh not installed: skipped\n"
        skip_test "zsh not installed"
        return 0
    fi
    out=$(_cp_zsh_ctx wp-db-import command wp-db-import)
    _chk "commands: every command with a description"   bash -c 'for c in config-show config-create config-validate config-edit show-links setup-proxy show-cleanup detect doctor restore update version test; do grep -q "^DESC: $c:" <<< "$0" || exit 1; done' "$out"
    out=$(_cp_zsh_ctx wp-db-import "" wp-db-import)
    _chk "global options: --yes -y --non-interactive --dry-run --help" bash -c 'for f in --yes -y --non-interactive --dry-run --help; do grep -qF -- "$f" <<< "$0" || exit 1; done' "$out"
    out=$(_cp_zsh_ctx wp-db-import args restore)
    _chk "restore: --list --last --all and backup files" bash -c 'grep -q -- "--list" <<< "$0" && grep -q -- "--last" <<< "$0" && grep -q -- "--all" <<< "$0" && grep -q "sql|gz|zip|bz2|gpg" <<< "$0"' "$out"
    out=$(_cp_zsh_ctx wp-db-import args test)
    _chk "test: runner options, --format values, suites"  bash -c 'for f in --verbose --quick --parallel --ci --format --output "(json html text all)"; do grep -qF -- "$f" <<< "$0" || exit 1; done; grep -q "suite:" <<< "$0"' "$out"
    out=$(_cp_zsh_ctx wp-db-import args detect)
    _chk "detect: --verbose and --quiet"                  bash -c 'grep -q -- "--quiet" <<< "$0" && grep -q -- "--verbose" <<< "$0" && ! grep -q -- "--quite" <<< "$0"' "$out"
    out=$(_cp_zsh_ctx wp-db-import args show-cleanup)
    _chk "show-cleanup: directories"                      bash -c 'grep -q "_directories" <<< "$0"' "$out"
    out=$(_cp_zsh_ctx wp-db-import args doctor)
    _chk "doctor: no argument rules (only the global-options call)" test "$(grep -c '^ARGS:' <<< "$out")" -eq 1
    out=$(_cp_zsh_ctx uninstall.sh "" ./uninstall.sh)
    _chk "uninstall.sh options"                           bash -c 'for f in --yes --delete-backups --keep-backups --help; do grep -qF -- "$f" <<< "$0" || exit 1; done' "$out"
    _chk "the #compdef line names both commands"          bash -c 'head -1 "$0" | grep -q "^#compdef wp-db-import uninstall.sh$"' "$_CP_ZSH"
    _finish "Zsh completion offers the right words"
}

run_completion_tests() {
    printf "\n${CYAN}${BOLD}🧪 Completion Tests${RESET}\n"
    printf "%s\n\n" "$(printf '=%.0s' {1..50})"
    init_test_session "completions"
    _CP_WORK=$(mktemp -d "${TMPDIR:-/tmp}/wpdb-comp-test.XXXXXX")
    trap 'rm -rf "$_CP_WORK"' EXIT

    test_syntax
    test_sync_with_tool
    test_bash_behavior
    test_zsh_behavior

    finalize_test_session
    return $?
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    run_completion_tests
fi
