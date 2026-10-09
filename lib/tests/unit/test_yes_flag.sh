#!/usr/bin/env bash

# ================================================================
# Unattended Mode (--yes / --non-interactive) - Tests
# ================================================================
#
# Description:
#   Tests for issue #19: `--yes`, `-y`, `--non-interactive` and WPDB_ASSUME_YES=1.
#     - helpers: wpdb_assume_yes, wpdb_auto_proceed_reason, wpdb_read, wpdb_read_required
#     - flag parsing in wp-db-import and import_wp_db.sh (any position, exit code 2 on bad input)
#     - nothing is read from stdin or the terminal (never-ending stdin pipe + hang watchdog)
#     - prompts without a safe default fail with a clear message
#     - a static guard: every prompt must use the helpers (no raw `read -r`)
#
# Usage:
#   ./lib/tests/unit/test_yes_flag.sh
#
# ================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../test_framework.sh"

_Y_ROOT="$PROJECT_ROOT_DIR"
_Y_WORK=""

_y_work() { printf "%s" "$_Y_WORK"; }

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

# Runs a command with a watchdog (no `timeout` on stock macOS). Output goes to $Y_OUT, exit code
# to $Y_RC (124 = killed after the limit). stdin is a pipe that never ends unless $Y_STDIN is set.
_y_run() {
    local secs="$1"; shift
    local f; f=$(mktemp "${TMPDIR:-/tmp}/wpdb-y.XXXXXX")
    if [[ -n "${Y_STDIN:-}" ]]; then
        "$@" > "$f" 2>&1 < "$Y_STDIN" &
    else
        "$@" > "$f" 2>&1 < <(sleep $((secs + 5))) &
    fi
    local pid=$!
    ( sleep "$secs"; kill "$pid" 2>/dev/null ) &
    local wd=$!
    wait "$pid" 2>/dev/null; local rc=$?
    kill "$wd" 2>/dev/null; wait "$wd" 2>/dev/null
    [[ $rc -ge 128 ]] && rc=124
    Y_OUT=$(_strip < "$f"); Y_RC=$rc
    export Y_OUT Y_RC
    rm -f "$f"
}

# ================================================================
# Helpers
# ================================================================
test_yes_helpers() {
    start_test "Unattended Helpers" "wpdb_assume_yes / wpdb_auto_proceed_reason / wpdb_read / wpdb_read_required"
    local errors=0 v

    for v in 1 true TRUE Yes on ON; do
        _chk "WPDB_ASSUME_YES=$v is on" bash -c "source '$_Y_ROOT/lib/core/utils.sh' >/dev/null 2>&1; WPDB_ASSUME_YES='$v' wpdb_assume_yes"
    done
    for v in "" 0 false no off abc; do
        _chk "WPDB_ASSUME_YES='$v' is off" bash -c "source '$_Y_ROOT/lib/core/utils.sh' >/dev/null 2>&1; ! WPDB_ASSUME_YES='$v' wpdb_assume_yes"
    done

    _chk "reason: --yes"                         bash -c "source '$_Y_ROOT/lib/core/utils.sh' >/dev/null 2>&1; test \"\$(WPDB_ASSUME_YES=1 wpdb_auto_proceed_reason)\" = '--yes'"
    _chk "reason: auto_proceed from config"      bash -c "source '$_Y_ROOT/lib/core/utils.sh' >/dev/null 2>&1; test \"\$(CONFIG_AUTO_PROCEED=true wpdb_auto_proceed_reason)\" = 'from config'"
    _chk "reason: --yes wins over config"        bash -c "source '$_Y_ROOT/lib/core/utils.sh' >/dev/null 2>&1; test \"\$(WPDB_ASSUME_YES=1 CONFIG_AUTO_PROCEED=true wpdb_auto_proceed_reason)\" = '--yes'"
    _chk "reason: none -> returns 1"             bash -c "source '$_Y_ROOT/lib/core/utils.sh' >/dev/null 2>&1; CONFIG_AUTO_PROCEED=false; ! wpdb_auto_proceed_reason >/dev/null"
    _chk "reason: config 'TRUE' (any case) works" bash -c "source '$_Y_ROOT/lib/core/utils.sh' >/dev/null 2>&1; CONFIG_AUTO_PROCEED=TRUE wpdb_auto_proceed_reason >/dev/null"

    # interactive: reads a line
    _chk "wpdb_read reads from stdin when interactive" bash -c "source '$_Y_ROOT/lib/core/utils.sh' >/dev/null 2>&1; wpdb_read x <<< 'typed'; test \"\$x\" = typed"
    _chk "wpdb_read_required reads when interactive"   bash -c "source '$_Y_ROOT/lib/core/utils.sh' >/dev/null 2>&1; wpdb_read_required x 'a value' <<< 'typed'; test \"\$x\" = typed"

    # unattended: never reads (stdin is a pipe that never ends, so a read would hang)
    Y_STDIN="" _y_run 8 bash -c "source '$_Y_ROOT/lib/core/utils.sh' >/dev/null 2>&1; export WPDB_ASSUME_YES=1; x=preset; wpdb_read x; echo \"x=[\$x]\""
    _chk "unattended wpdb_read returns at once without reading" bash -c "test $Y_RC -eq 0 && grep -qF 'x=[]' <<< \"\$Y_OUT\""
    Y_STDIN="" _y_run 8 bash -c "source '$_Y_ROOT/lib/core/utils.sh' >/dev/null 2>&1; export WPDB_ASSUME_YES=1; x=preset; wpdb_read x tty; echo \"x=[\$x]\""
    _chk "unattended wpdb_read (tty variant) does not touch the terminal" bash -c "test $Y_RC -eq 0 && grep -qF 'x=[]' <<< \"\$Y_OUT\""
    Y_STDIN="" _y_run 8 bash -c "source '$_Y_ROOT/lib/core/utils.sh' >/dev/null 2>&1; export WPDB_ASSUME_YES=1; wpdb_read_required x 'The SQL file name (sql_file)'; echo \"rc=\$?\""
    _chk "unattended required: returns 1 with a clear message" bash -c "grep -q 'rc=1' <<< \"\$Y_OUT\" && grep -q 'SQL file name (sql_file) is required' <<< \"\$Y_OUT\" && grep -q 'wpdb-import.conf' <<< \"\$Y_OUT\""
    _chk "unattended required: error goes to stderr"  bash -c "source '$_Y_ROOT/lib/core/utils.sh' >/dev/null 2>&1; export WPDB_ASSUME_YES=1; test -z \"\$(wpdb_read_required x 'v' 2>/dev/null)\""
    _finish "helpers behave correctly"
}

# ================================================================
# Static guard: every prompt goes through the helpers
# ================================================================
test_no_raw_prompts() {
    start_test "No Raw Prompts" "every prompt uses wpdb_read / wpdb_read_required so --yes can never hang"
    local errors=0
    local hits
    hits=$(grep -rnE '(^|[^a-zA-Z_])read( -[a-zA-Z]+)* [a-zA-Z_]+( <|$|;| \|\|)' \
        "$_Y_ROOT/import_wp_db.sh" "$_Y_ROOT/wp-db-import" "$_Y_ROOT"/lib/core "$_Y_ROOT"/lib/config "$_Y_ROOT"/lib/database "$_Y_ROOT"/lib/utilities "$_Y_ROOT/lib/module_loader.sh" 2>/dev/null \
        | grep -vE ':[0-9]+:\s*#|IFS=|<<<|wpdb_read|lib/core/utils.sh|lib/database/db_backup.sh')
    _chk "no raw 'read' prompts outside the helpers" test -z "$hits"
    [[ -n "$hits" ]] && printf "%s\n" "$hits" | sed 's/^/     /'
    # the backup prompt is the one allowed raw read: it is guarded by the unattended check right above it
    _chk "backup prompt is guarded by the unattended check" bash -c "awk '/WPDB_ASSUME_YES/{g=1} /read -r answer/{if(!g) exit 1}' '$_Y_ROOT/lib/database/db_backup.sh'"
    _finish "all prompts are unattended-safe"
}

# ================================================================
# Flag parsing
# ================================================================
test_yes_flag_parsing() {
    start_test "Flag Parsing" "--yes, -y, --non-interactive in any position; exit code 2 for usage errors"
    local errors=0
    local tool="$_Y_ROOT/wp-db-import"
    local f
    for f in --yes -y --non-interactive; do
        Y_STDIN=/dev/null _y_run 20 bash "$tool" $f version
        _chk "wp-db-import $f version works"           bash -c "test $Y_RC -eq 0 && grep -q 'Version:' <<< \"\$Y_OUT\""
        Y_STDIN=/dev/null _y_run 20 bash "$tool" version $f
        _chk "wp-db-import version $f (flag last) works" bash -c "test $Y_RC -eq 0 && grep -q 'Version:' <<< \"\$Y_OUT\""
    done
    Y_STDIN=/dev/null WPDB_ASSUME_YES=1 _y_run 20 bash "$tool" version
    _chk "WPDB_ASSUME_YES=1 alias works"               bash -c "test $Y_RC -eq 0 && grep -q 'Version:' <<< \"\$Y_OUT\""

    Y_STDIN=/dev/null _y_run 20 bash "$tool" --yes bogus
    _chk "unknown command: exit code 2"                test "$Y_RC" -eq 2
    _chk "unknown command: still says so"              grep -q 'Unknown command: bogus' <<< "$Y_OUT"
    _chk "--yes is not passed on as a command"         bash -c "! grep -q 'Unknown command: --yes' <<< \"\$Y_OUT\""
    Y_STDIN=/dev/null _y_run 20 bash "$tool" --help
    _chk "--help documents --yes / -y / --non-interactive" grep -qF -- '--yes, -y, --non-interactive' <<< "$Y_OUT"
    _chk "--help documents WPDB_ASSUME_YES"            grep -q 'WPDB_ASSUME_YES=1' <<< "$Y_OUT"
    _chk "--help documents exit codes 0/1/2"           grep -q '0 success   1 failure   2 usage error' <<< "$Y_OUT"

    Y_STDIN=/dev/null _y_run 20 bash "$_Y_ROOT/import_wp_db.sh" --bogus
    _chk "import_wp_db.sh: unknown option exits 2"     test "$Y_RC" -eq 2
    _chk "import_wp_db.sh: prints usage"               grep -qF 'Usage: import_wp_db.sh [--yes | -y | --non-interactive]' <<< "$Y_OUT"
    _finish "flags are parsed correctly"
}

# ================================================================
# Child processes cannot hang on stdin
# ================================================================
test_yes_closes_stdin() {
    start_test "stdin Closed" "under --yes a child process that reads stdin gets EOF, not a hang"
    local errors=0 w; w=$(_y_work)
    printf '#!/bin/sh\nif cat >/dev/null; then echo CHILD_GOT_EOF; fi\n' > "$w/reader"; chmod +x "$w/reader"
    # same code path as wp-db-import's flag handling
    cat > "$w/wrap.sh" <<WRAP_END
WPDB_ASSUME_YES=1
case "\$(printf "%s" "\${WPDB_ASSUME_YES:-}" | tr '[:upper:]' '[:lower:]')" in 1|true|yes|on) exec </dev/null ;; esac
"$w/reader"
WRAP_END
    _y_run 8 bash "$w/wrap.sh"
    _chk "child reading stdin returns immediately (EOF)" bash -c "test $Y_RC -eq 0 && grep -q CHILD_GOT_EOF <<< \"\$Y_OUT\""
    _chk "wp-db-import closes stdin in unattended mode" grep -q 'exec </dev/null' "$_Y_ROOT/wp-db-import"
    _chk "import_wp_db.sh closes stdin in unattended mode" grep -q 'wpdb_assume_yes && exec </dev/null' "$_Y_ROOT/import_wp_db.sh"
    _finish "stdin is closed in unattended mode"
}

# ================================================================
# Full flow in a sandbox: never reads stdin, fails clearly, no hang
# ================================================================
test_yes_sandbox_runs() {
    start_test "Unattended Runs" "no hang with a never-ending stdin pipe; missing required values fail with exit 1"
    local errors=0 w; w=$(_y_work)
    local site="$w/site"; mkdir -p "$site/bin"
    printf "<?php\ndefine('DB_NAME','x'); define('DB_USER','u'); define('DB_PASSWORD','p'); define('DB_HOST','localhost');\n\$table_prefix='wp_';\n" > "$site/wp-config.php"
    # stub wp: succeeds and records what its stdin is: 1 = end-of-file (closed), >128 = still open (timeout)
    cat > "$site/bin/wp" <<'WP_STUB_END'
#!/usr/bin/env bash
read -t 1 _wpdb_x
echo "$?" >> "${STUB_STDIN_LOG:-/dev/null}"
exit 0
WP_STUB_END
    chmod +x "$site/bin/wp"
    export STUB_STDIN_LOG="$w/stdin_rc.log"; : > "$STUB_STDIN_LOG"

    # 1) no config, no sql_file: must fail with a clear message, never prompt, never hang
    Y_STDIN="" _y_run 25 bash -c "cd '$site' && PATH='$site/bin:'\"\$PATH\" bash '$_Y_ROOT/import_wp_db.sh' --yes"
    _chk "no sql_file: finishes (no hang on a never-ending stdin)" test "$Y_RC" -ne 124
    _chk "no sql_file: exit code 1"                    test "$Y_RC" -eq 1
    _chk "no sql_file: names what is missing"          grep -q 'SQL file name (sql_file) is required' <<< "$Y_OUT"
    _chk "no sql_file: points to the config file"      grep -q 'wpdb-import.conf' <<< "$Y_OUT"

    # 2) same through the wp-db-import command, and through the environment variable
    Y_STDIN="" _y_run 25 bash -c "cd '$site' && PATH='$site/bin:'\"\$PATH\" bash '$_Y_ROOT/wp-db-import' --yes"
    _chk "wp-db-import --yes: no hang, exit 1, clear message" bash -c "test $Y_RC -eq 1 && grep -q 'is required' <<< \"\$Y_OUT\""
    Y_STDIN="" _y_run 25 bash -c "cd '$site' && PATH='$site/bin:'\"\$PATH\" WPDB_ASSUME_YES=1 bash '$_Y_ROOT/wp-db-import'"
    _chk "WPDB_ASSUME_YES=1 (no flag): same behavior"  bash -c "test $Y_RC -eq 1 && grep -q 'is required' <<< \"\$Y_OUT\""

    # 3) config wizard
    rm -f "$site/wpdb-import.conf"
    Y_STDIN="" _y_run 25 bash -c "cd '$site' && PATH='$site/bin:'\"\$PATH\" bash '$_Y_ROOT/wp-db-import' --yes config-create"
    _chk "config-create --yes: no hang"                test "$Y_RC" -ne 124
    _chk "config-create --yes: fails clearly (needs input)" bash -c "test $Y_RC -ne 0 && grep -qE 'is required' <<< \"\$Y_OUT\""
    _chk "config-create --yes: writes no half-made config" test ! -s "$site/wpdb-import.conf"

    # 4) a prompt with a default still works: auto_proceed=false, everything else default
    printf '[general]\nsql_file=dump.sql\nold_domain=a.example\nnew_domain=a.test\nauto_proceed=false\nbackup_before_import=false\n[site_mappings]\n' > "$site/wpdb-import.conf"
    printf 'SELECT 1;\n' > "$site/dump.sql"
    Y_STDIN="" _y_run 40 bash -c "cd '$site' && PATH='$site/bin:'\"\$PATH\" bash '$_Y_ROOT/import_wp_db.sh' --yes"
    _chk "defaults flow: no hang"                      test "$Y_RC" -ne 124
    _chk "defaults flow: confirmation skipped with the '--yes' reason" grep -q 'Auto-proceeding with database import (--yes)' <<< "$Y_OUT"
    _chk "defaults flow: never waited at 'Proceed with database import?'" bash -c "! grep -q 'Proceed with database import? (Y/n)' <<< \"\$Y_OUT\""
    _chk "defaults flow: WP-CLI was started (the stub saw a run)" test -s "$STUB_STDIN_LOG"
    _chk "defaults flow: no WP-CLI child was left reading an open stdin pipe" bash -c "! awk '\$1 >= 128 {bad=1} END {exit !bad}' '$STUB_STDIN_LOG'"

    # 5) without --yes the same prompt is shown (the flag really changes behavior)
    Y_STDIN=/dev/null _y_run 40 bash -c "cd '$site' && PATH='$site/bin:'\"\$PATH\" bash '$_Y_ROOT/import_wp_db.sh'"
    _chk "without --yes the confirmation prompt is still shown" grep -q 'Proceed with database import? (Y/n)' <<< "$Y_OUT"
    unset STUB_STDIN_LOG
    _finish "unattended runs never wait for input"
}

# ================================================================
# Completions know the new options
# ================================================================
test_yes_completions() {
    start_test "Completions" "Bash and Zsh completions offer --yes / -y / --non-interactive"
    local errors=0
    _chk "bash completion file has valid syntax"       bash -n "$_Y_ROOT/lib/completion/wp-db-import.bash"
    _chk "Bash completion lists the unattended options"          grep -q 'flags="--yes -y --non-interactive --dry-run"' "$_Y_ROOT/lib/completion/wp-db-import.bash"
    if command -v zsh >/dev/null 2>&1; then
        _chk "zsh completion file has valid syntax"    zsh -n "$_Y_ROOT/lib/completion/_wp-db-import"
    fi
    _chk "zsh completion lists the options"            bash -c "grep -q -e '{-y,--yes,--non-interactive}' '$_Y_ROOT/lib/completion/_wp-db-import' && grep -q -e '--dry-run\[' '$_Y_ROOT/lib/completion/_wp-db-import'"

    # Behavior of the Bash 4+ function (needs a Bash 4+ interpreter; stock macOS bash is 3.2)
    local b4=""
    local cand
    for cand in /opt/homebrew/bin/bash /usr/local/bin/bash /usr/bin/bash /bin/bash; do
        [[ -x "$cand" ]] && [[ "$("$cand" -c 'echo ${BASH_VERSINFO[0]}' 2>/dev/null)" -ge 4 ]] && { b4="$cand"; break; }
    done
    if [[ -n "$b4" ]]; then
        local out
        out=$("$b4" -c "source '$_Y_ROOT/lib/completion/wp-db-import.bash'; COMP_WORDS=(wp-db-import --); COMP_CWORD=1; _wp_db_import_completion; echo \"\${COMPREPLY[*]}\"")
        _chk "typing a dash offers --yes -y --non-interactive --help" bash -c "[[ '$out' == *--yes* && '$out' == *-y* && '$out' == *--non-interactive* && '$out' == *--help* ]]"
        out=$("$b4" -c "source '$_Y_ROOT/lib/completion/wp-db-import.bash'; COMP_WORDS=(wp-db-import --yes ''); COMP_CWORD=2; _wp_db_import_completion; echo \"\${COMPREPLY[*]}\"")
        _chk "after --yes the commands are still offered"  bash -c "[[ '$out' == *config-show* && '$out' == *update* ]]"
        out=$("$b4" -c "source '$_Y_ROOT/lib/completion/wp-db-import.bash'; COMP_WORDS=(wp-db-import ''); COMP_CWORD=1; _wp_db_import_completion; echo \"\${COMPREPLY[*]}\"")
        _chk "plain TAB still lists the commands"          bash -c "[[ '$out' == *config-show* && '$out' != *--yes* ]]"
    else
        printf "  ⚠️  no Bash 4+ interpreter found; completion behavior check skipped\n"
    fi
    _finish "completions are up to date"
}

run_yes_flag_tests() {
    printf "\n${CYAN}${BOLD}🤖 Unattended Mode Tests (--yes)${RESET}\n"
    printf "%s\n\n" "$(printf '=%.0s' {1..50})"

    init_test_session "yes_flag"
    _Y_WORK=$(mktemp -d "${TMPDIR:-/tmp}/wpdb-yes-test.XXXXXX")
    trap 'rm -rf "$_Y_WORK"' EXIT

    test_yes_helpers
    test_no_raw_prompts
    test_yes_flag_parsing
    test_yes_closes_stdin
    test_yes_completions
    test_yes_sandbox_runs

    finalize_test_session
    return $?
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    run_yes_flag_tests
fi
