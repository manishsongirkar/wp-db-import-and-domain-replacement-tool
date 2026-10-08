#!/usr/bin/env bash

# ================================================================
# Update and Uninstall - Tests
# ================================================================
#
# Description:
#   Tests `wp-db-import update` and `uninstall.sh` in a sandbox (throw-away HOME,
#   local git repositories). Nothing outside the sandbox is touched.
#     update:    fast-forward pull, version change shown, already-up-to-date, local
#                changes prompt, diverged history, deleted remote branch, no git repo
#     uninstall: removes command + completions + stale temp dirs, keeps backups unless
#                told otherwise, prints the cause of every failure, exit codes, flags
#
# Usage:
#   ./lib/tests/unit/test_update_uninstall.sh
#
# ================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../test_framework.sh"

_UU_ROOT="$PROJECT_ROOT_DIR"
_UU_WORK=""

_uu_work() { printf "%s" "$_UU_WORK"; }

_chk() {
    local desc="$1"; shift
    if "$@" >/dev/null 2>&1; then
        printf "  ✅ %s\n" "$desc"
    else
        printf "  ❌ %s\n" "$desc"
        ((errors++))
    fi
}

_finish() {
    if [[ "$errors" -eq 0 ]]; then pass_test "$1"; else fail_test "$errors check(s) failed"; fi
}

_strip() { sed 's/\x1b\[[0-9;]*[a-zA-Z]//g'; }

# Runs a command, stores colour-stripped output in $CAP_OUT and the exit code in $CAP_RC
_capture() {
    local f; f=$(mktemp "${TMPDIR:-/tmp}/wpdb-cap.XXXXXX")
    "$@" > "$f" 2>&1 < "${CAP_IN:-/dev/null}"
    CAP_RC=$?
    CAP_OUT=$(_strip < "$f")
    rm -f "$f"
}

# Copies the current working tree (including uncommitted changes) into a git repo
_uu_make_repo() {
    local dest="$1"
    mkdir -p "$dest"
    ( cd "$_UU_ROOT" && tar --exclude=.git --exclude=reports --exclude=graphify-out --exclude='*.bak' -cf - . ) | ( cd "$dest" && tar -xf - )
    ( cd "$dest" && git init -q -b main . && git add -A >/dev/null && git -c user.name=t -c user.email=t@t commit -q -m "base" )
}

# ================================================================
# wp-db-import update
# ================================================================
test_update_command() {
    start_test "Update Command" "fast-forward update shows version change and explains failures"
    local errors=0 w; w=$(_uu_work)
    command -v git >/dev/null 2>&1 || { skip_test "git not available"; return 0; }

    local origin="$w/origin.git" up="$w/upstream" tool="$w/tool"
    _uu_make_repo "$w/seed"
    git clone -q --bare "$w/seed" "$origin" 2>/dev/null
    git clone -q "$origin" "$tool" 2>/dev/null
    git clone -q "$origin" "$up" 2>/dev/null
    # clones hold the committed tree; overlay the working-tree wp-db-import under test
    cp "$_UU_ROOT/wp-db-import" "$tool/wp-db-import"
    ( cd "$tool" && git -c user.name=t -c user.email=t@t commit -qam "use tree under test" && git push -q origin main 2>/dev/null )
    ( cd "$up" && git pull -q origin main 2>/dev/null )

    local cur_version; cur_version=$(tr -d '\n' < "$tool/VERSION")
    _chk "sandbox tool starts at the current version"    test -n "$cur_version"

    # Already up to date
    local out rc
    _upd() { _capture bash -c 'cd "$1" && bash ./wp-db-import update' _ "$tool"; out="$CAP_OUT"; rc="$CAP_RC"; }
    _upd
    _chk "up to date: says so"                           grep -q 'Already up to date' <<< "$out"
    _chk "up to date: shows the version"                 grep -q "version $cur_version" <<< "$out"

    # Upstream publishes a new version
    ( cd "$up" && printf '9.9.9\n' > VERSION && git -c user.name=t -c user.email=t@t commit -qam "release 9.9.9" && git push -q origin main 2>/dev/null )
    _upd
    _chk "update: succeeds"                              grep -q 'Successfully updated' <<< "$out"
    _chk "update: shows commit change"                   grep -q 'main@' <<< "$out"
    _chk "update: shows version $cur_version -> 9.9.9"   grep -q "Version: $cur_version → 9.9.9" <<< "$out"
    _chk "update: files were actually updated"           test "$(tr -d '\n' < "$tool/VERSION")" = "9.9.9"
    _chk "update: verifies the updated files"            grep -q 'Updated files verified' <<< "$out"
    _chk "update: no merge commit (fast-forward only)"   test "$(git -C "$tool" rev-list --merges HEAD | wc -l | tr -d ' ')" = 0

    # Uncommitted changes: asks, and 'n' cancels without changing anything
    ( cd "$up" && printf '9.9.10\n' > VERSION && git -c user.name=t -c user.email=t@t commit -qam "release 9.9.10" && git push -q origin main 2>/dev/null )
    echo "# local edit" >> "$tool/README.md"
    CAP_IN=<(printf 'n\n') _capture bash -c 'cd "$1" && bash ./wp-db-import update' _ "$tool"; out="$CAP_OUT"
    _chk "local changes: warns and asks"                 grep -q 'uncommitted changes' <<< "$out"
    _chk "local changes: 'n' cancels the update"         grep -q 'Update cancelled' <<< "$out"
    _chk "local changes: nothing was changed"            test "$(tr -d '\n' < "$tool/VERSION")" = "9.9.9"
    ( cd "$tool" && git checkout -q -- README.md )

    # Diverged local history: refuses, explains, non-zero exit
    ( cd "$tool" && echo x > local-only.txt && git add local-only.txt && git -c user.name=t -c user.email=t@t commit -qm "local only" )
    _upd
    _chk "diverged: update fails"                        test "$rc" -ne 0
    _chk "diverged: prints 'Update failed'"              grep -q 'Update failed' <<< "$out"
    _chk "diverged: explains the cause"                  grep -q 'cannot fast-forward' <<< "$out"
    _chk "diverged: gives a fix"                         grep -q 'Fix:' <<< "$out"
    _chk "diverged: nothing was merged"                  test "$(git -C "$tool" rev-list --merges HEAD | wc -l | tr -d ' ')" = 0
    ( cd "$tool" && git reset -q --hard origin/main && git pull -q --ff-only origin main 2>/dev/null )

    # Branch deleted on the remote (the situation after a merged PR)
    ( cd "$tool" && git checkout -q -b feat/gone && git push -q origin feat/gone 2>/dev/null && git push -q origin --delete feat/gone 2>/dev/null )
    _upd
    _chk "deleted branch: update fails"                  test "$rc" -ne 0
    _chk "deleted branch: explains the cause"            grep -q "no longer exists on the remote" <<< "$out"
    _chk "deleted branch: tells how to get back to main" grep -q 'git checkout main' <<< "$out"
    ( cd "$tool" && git checkout -q main )

    # Not a git installation (downloaded ZIP)
    mkdir -p "$w/zip" && cp -R "$tool"/. "$w/zip/" && rm -rf "$w/zip/.git"
    _capture bash -c 'cd "$1" && bash ./wp-db-import update' _ "$w/zip"; out="$CAP_OUT"; rc="$CAP_RC"
    _chk "no git repo: fails with non-zero exit"         test "$rc" -ne 0
    _chk "no git repo: says it is not a git repository"  grep -q 'Not in a git repository' <<< "$out"
    _chk "no git repo: explains how to enable updates"   grep -q 'git clone' <<< "$out"
    _finish "update works and explains failures"
}

# ================================================================
# uninstall.sh
# ================================================================
_uu_sandbox_home() {
    local h="$1"
    rm -rf "$h"; mkdir -p "$h/.local/bin" "$h/.local/share/bash-completion/completions" "$h/.local/share/zsh/site-functions" "$h/tmp"
    ln -s "$_UU_ROOT/wp-db-import" "$h/.local/bin/wp-db-import"
    ln -s "$_UU_ROOT/lib/completion/wp-db-import.bash" "$h/.local/share/bash-completion/completions/wp-db-import"
    ln -s "$_UU_ROOT/lib/completion/_wp-db-import" "$h/.local/share/zsh/site-functions/_wp-db-import"
    mkdir -p "$h/.wp-db-import/backups"
    printf 'x' | gzip -c > "$h/.wp-db-import/backups/wp-20260101-000000.sql.gz"
}

_uu_run() {  # <home> <stdin-text> [args...]  -> output in $UU_OUT, exit code in $UU_RC
    local h="$1" input="$2"; shift 2
    local inf; inf=$(mktemp "${TMPDIR:-/tmp}/wpdb-in.XXXXXX"); printf '%s\n' "$input" > "$inf"
    CAP_IN="$inf" _capture bash -c 'cd "$1" && shift && HOME="$1" TMPDIR="$1/tmp" NO_COLOR=1 bash ./uninstall.sh "${@:2}"' _ "$_UU_ROOT" "$h" "$@"
    rm -f "$inf"
    UU_OUT="$CAP_OUT"; UU_RC="$CAP_RC"
}

test_uninstall() {
    start_test "Uninstall Script" "removes everything it installed, keeps backups, and prints failure causes"
    local errors=0 w; w=$(_uu_work)
    if [[ -e /usr/local/bin/wp-db-import ]]; then
        skip_test "a real /usr/local/bin/wp-db-import exists; not risking it in tests"
        return 0
    fi
    local h="$w/home"

    # --yes: removes command, completions, stale temp; KEEPS backups; exit 0
    _uu_sandbox_home "$h"
    mkdir -p "$h/tmp/wpdb-import-$(id -u)-99991"; echo log > "$h/tmp/wpdb-import-$(id -u)-99991/db_import.log"
    _uu_run "$h" "" --yes
    _chk "--yes: exit code 0"                          test "$UU_RC" -eq 0
    _chk "--yes: command removed"                      test ! -e "$h/.local/bin/wp-db-import" -a ! -L "$h/.local/bin/wp-db-import"
    _chk "--yes: bash completion removed"              test ! -L "$h/.local/share/bash-completion/completions/wp-db-import"
    _chk "--yes: zsh completion removed"               test ! -L "$h/.local/share/zsh/site-functions/_wp-db-import"
    _chk "--yes: stale private temp dir removed"       test ! -d "$h/tmp/wpdb-import-$(id -u)-99991"
    _chk "--yes: backups are KEPT (data is never deleted by --yes)" test -f "$h/.wp-db-import/backups/wp-20260101-000000.sql.gz"
    _chk "--yes: says backups were kept"               grep -q 'Backups kept' <<< "$UU_OUT"
    _chk "--yes: shows backup count and location"      grep -q '1 backup(s)' <<< "$UU_OUT"
    _chk "--yes: repository folder is not deleted"     test -f "$_UU_ROOT/wp-db-import"
    _chk "--yes: mentions per-project config files"    grep -q 'wpdb-import.conf' <<< "$UU_OUT"

    # --delete-backups
    _uu_sandbox_home "$h"
    _uu_run "$h" "" --yes --delete-backups
    _chk "--delete-backups: backups deleted"           test ! -d "$h/.wp-db-import"
    _chk "--delete-backups: says so"                   grep -q 'Backups deleted' <<< "$UU_OUT"

    # --keep-backups never asks
    _uu_sandbox_home "$h"
    _uu_run "$h" "y" --keep-backups
    _chk "--keep-backups: backups kept without asking" test -f "$h/.wp-db-import/backups/wp-20260101-000000.sql.gz"
    _chk "--keep-backups: no backup question shown"    bash -c "! grep -q 'Delete these backups' <<< '$UU_OUT'"

    # Interactive: 'n' at the first question changes nothing
    _uu_sandbox_home "$h"
    _uu_run "$h" "n"
    _chk "answer n: cancelled"                         grep -q 'Uninstallation cancelled' <<< "$UU_OUT"
    _chk "answer n: command still installed"           test -L "$h/.local/bin/wp-db-import"
    # y then n: command removed, backups kept
    _uu_sandbox_home "$h"
    _uu_run "$h" $'y\nn'
    _chk "answer y,n: command removed"                 test ! -L "$h/.local/bin/wp-db-import"
    _chk "answer y,n: backups kept"                    test -f "$h/.wp-db-import/backups/wp-20260101-000000.sql.gz"
    # y then y: both removed
    _uu_sandbox_home "$h"
    _uu_run "$h" $'y\ny'
    _chk "answer y,y: backups deleted"                 test ! -d "$h/.wp-db-import"
    # Empty answer to the backup question means NO (safe default)
    _uu_sandbox_home "$h"
    _uu_run "$h" $'y\n'
    _chk "Enter at the backup question keeps backups"  test -f "$h/.wp-db-import/backups/wp-20260101-000000.sql.gz"

    # Symlinked / foreign things in the temp area are never followed or deleted
    _uu_sandbox_home "$h"
    mkdir -p "$w/precious"; echo keep > "$w/precious/file"
    ln -s "$w/precious" "$h/tmp/wpdb-import-$(id -u)-4242"
    _uu_run "$h" "" --yes
    _chk "symlinked temp entry is skipped with a warning" grep -q 'Skipped (not a directory owned by you)' <<< "$UU_OUT"
    _chk "symlink target is untouched"                 test -f "$w/precious/file"

    # FAILURE: command cannot be removed -> cause is printed, exit code non-zero
    _uu_sandbox_home "$h"
    chmod 555 "$h/.local/bin"
    _uu_run "$h" "" --yes
    chmod 755 "$h/.local/bin"
    _chk "failure: exit code is non-zero"              test "$UU_RC" -ne 0
    _chk "failure: shows the real error text"          grep -q 'Permission denied' <<< "$UU_OUT"
    _chk "failure: shows the path"                     grep -q "Path: .*$h/.local/bin/wp-db-import" <<< "$UU_OUT"
    _chk "failure: shows owner/permissions details"    grep -q 'Details:' <<< "$UU_OUT"
    _chk "failure: shows parent folder permissions"    grep -q 'Parent dir:' <<< "$UU_OUT"
    _chk "failure: shows which user ran it"            grep -q 'You are:' <<< "$UU_OUT"
    _chk "failure: gives a hint"                       grep -q 'Hint:' <<< "$UU_OUT"
    _chk "failure: 'Problems found' summary lists it"  bash -c "grep -q 'Problems found' <<< '$UU_OUT' && grep -q 'Executable: .*Permission denied' <<< '$UU_OUT'"
    _chk "failure: no false success banner"           bash -c "! grep -q 'Uninstallation complete!' <<< '$UU_OUT'"
    _chk "failure: says it completed with issues"      grep -q 'completed with some issues' <<< "$UU_OUT"

    # FAILURE: completion link in a read-only folder
    _uu_sandbox_home "$h"
    chmod 555 "$h/.local/share/zsh/site-functions"
    _uu_run "$h" "" --yes
    chmod 755 "$h/.local/share/zsh/site-functions"
    _chk "completion failure: cause is printed"        grep -q 'Permission denied' <<< "$UU_OUT"
    _chk "completion failure: recorded in summary"     grep -q 'Zsh completion: ' <<< "$UU_OUT"
    _chk "completion failure: exit code non-zero"      test "$UU_RC" -ne 0
    _chk "completion failure: command itself still removed" test ! -L "$h/.local/bin/wp-db-import"

    # Nothing installed
    rm -rf "$h"; mkdir -p "$h/tmp"
    _uu_run "$h" "" --yes
    _chk "nothing installed: exit 0 and says so"       bash -c "test $UU_RC -eq 0 && grep -q 'already uninstalled' <<< '$UU_OUT'"

    # Bad option
    _uu_run "$h" "" --bogus
    _chk "unknown option: exit code 2"                 test "$UU_RC" -eq 2
    _chk "unknown option: usage shown"                 grep -q 'Usage:' <<< "$UU_OUT"
    _finish "uninstall is safe and explains problems"
}

run_update_uninstall_tests() {
    printf "\n${CYAN}${BOLD}🔄 Update & Uninstall Tests${RESET}\n"
    printf "%s\n\n" "$(printf '=%.0s' {1..50})"

    init_test_session "update_uninstall"
    _UU_WORK=$(mktemp -d "${TMPDIR:-/tmp}/wpdb-uu-test.XXXXXX")
    trap 'chmod -R u+w "$_UU_WORK" 2>/dev/null; rm -rf "$_UU_WORK"' EXIT

    test_update_command
    test_uninstall

    finalize_test_session
    return $?
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    run_update_uninstall_tests
fi
