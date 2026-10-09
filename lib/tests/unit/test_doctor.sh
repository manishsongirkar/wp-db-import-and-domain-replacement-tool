#!/usr/bin/env bash

# ================================================================
# Doctor (environment check) - Tests
# ================================================================
#
# Description:
#   Tests for issue #22. Stub wp and mysql binaries in a private PATH check each outcome
#   without a real server: missing optional tools (WARN, exit 0), missing required tools
#   (FAIL, exit 1), connection failure, refused CREATE DATABASE, strict sql_mode, invalid
#   config, unwritable backup folder, no password in the output or in any argument, no
#   change to the config file, and the CLI wiring (help, completions, exit code 2).
#
# Usage:
#   ./lib/tests/unit/test_doctor.sh
#
# ================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../test_framework.sh"

_DC_ROOT="$PROJECT_ROOT_DIR"
_DC_WORK=""
_DC_PW='S3cr3t-Pw!9'

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

# A private bin dir: basic tools are linked, every other tool is absent unless added.
_dc_tools() {
    local d="$1" t p
    mkdir -p "$d"
    for t in awk sed df grep cat head tail tr cut uname mktemp dirname basename date sort wc rm mkdir tput stat find ls printf sleep id whoami env; do
        p=$(command -v "$t" 2>/dev/null) && [[ -x "$p" ]] && ln -sf "$p" "$d/$t"
    done
    return 0
}

_dc_add() { local d="$1" t p; shift; for t in "$@"; do p=$(command -v "$t" 2>/dev/null) && ln -sf "$p" "$d/$t"; done; return 0; }

# Stubs. Environment knobs: STUB_CONNECT=ok|fail, STUB_CREATE=ok|fail, STUB_MODE=..., STUB_ISINSTALLED=ok|fail
_dc_stubs() {
    local d="$1"
    cat > "$d/wp" <<'STUBEOF'
#!/bin/sh
case "$*" in
  *--version*)  echo "WP-CLI 2.12.0" ;;
  *core\ is-installed*) [ "${STUB_ISINSTALLED:-ok}" = ok ] || { echo "Error: database connection" >&2; exit 1; } ;;
esac
exit 0
STUBEOF
    cat > "$d/mysql" <<'STUBEOF'
#!/bin/sh
echo "$@" >> "${STUB_LOG:-/dev/null}"
case "$*" in *--version*) echo "mysql  Ver 8.4.0 for macos on arm64 (MySQL Community Server - GPL)"; exit 0 ;; esac
if [ "${STUB_CONNECT:-ok}" = fail ]; then echo "ERROR 1045 (28000): Access denied for user 'u'@'localhost' (using password: YES)" >&2; exit 1; fi
case "$*" in
  *"SELECT VERSION()"*)        echo "8.4.0" ;;
  *"CREATE DATABASE"*)         [ "${STUB_CREATE:-ok}" = ok ] || { echo "ERROR 1044 (42000): Access denied" >&2; exit 1; } ;;
  *"sql_mode"*)                echo "${STUB_MODE:-}" ;;
esac
exit 0
STUBEOF
    chmod +x "$d/wp" "$d/mysql"
}

_dc_site() {
    local s="$1"
    mkdir -p "$s"
    cat > "$s/wp-config.php" <<PHPEOF
<?php
define( 'DB_NAME', 'sitedb' );
define( 'DB_USER', 'siteuser' );
define( 'DB_PASSWORD', '$_DC_PW' );
define( 'DB_HOST', 'localhost' );
PHPEOF
}

# Runs doctor in directory $1 with the private PATH $2; prints output, returns doctor's status
_dc_run() {
    local dir="$1" bindir="$2"; shift 2
    local out rc
    out=$( cd "$dir" && env -i HOME="$_DC_WORK/home" PATH="$bindir" WPDB_FALLBACK_PATH="$_DC_WORK/none" \
        STUB_CONNECT="${STUB_CONNECT:-ok}" STUB_CREATE="${STUB_CREATE:-ok}" STUB_MODE="${STUB_MODE:-}" \
        STUB_ISINSTALLED="${STUB_ISINSTALLED:-ok}" STUB_LOG="${STUB_LOG:-}" "$BASH" -c '
        for f in core/utils config/config_manager database/sql_source database/socket_detector utilities/doctor; do
            source "'"$_DC_ROOT"'/lib/$f.sh" >/dev/null 2>&1
        done
        doctor_cli "$@"' _ "$@" 2>&1 )
    rc=$?
    printf "%s\n" "$out" | _strip
    return $rc
}

test_doctor_tools() {
    start_test "Tool checks" "optional tools warn, required tools fail, exit code follows"
    local errors=0 b="$_DC_WORK/bin_tools" out rc
    _dc_tools "$b"; _dc_stubs "$b"
    mkdir -p "$_DC_WORK/home" "$_DC_WORK/none" "$_DC_WORK/nowp"

    out=$(_dc_run "$_DC_WORK/nowp" "$b"); rc=$?
    _chk "exit 0 when only optional tools are missing"   test "$rc" -eq 0
    _chk "missing gzip is a WARN with a fix"             bash -c 'grep -q "WARN  gzip" <<< "$0" && grep -q "fix: install gzip" <<< "$0"' "$out"
    _chk "missing unzip, bzip2, git, curl/wget warn"     bash -c 'for t in unzip bzip2 git "curl or wget"; do grep -q "WARN  $t" <<< "$0" || exit 1; done' "$out"
    _chk "WP-CLI version is shown"                       grep -q 'OK    WP-CLI  *WP-CLI 2.12.0' <<< "$out"
    _chk "mysql client path and version are shown"       grep -q 'OK    mysql client .*Ver 8.4.0' <<< "$out"
    _chk "outside a site, site checks are skipped"       grep -q 'not in a WordPress directory' <<< "$out"

    _dc_add "$b" gzip unzip bzip2 git curl sha256sum shasum openssl
    out=$(_dc_run "$_DC_WORK/nowp" "$b"); rc=$?
    _chk "with the tools present there is no WARN"       bash -c '! grep -q "WARN" <<< "$0"' "$out"

    local b2="$_DC_WORK/bin_none"
    _dc_tools "$b2"
    out=$(_dc_run "$_DC_WORK/nowp" "$b2"); rc=$?
    _chk "exit 1 when WP-CLI and mysql are missing"      test "$rc" -eq 1
    _chk "WP-CLI missing is FAIL with the install link"  bash -c 'grep -q "FAIL  WP-CLI" <<< "$0" && grep -q "wp-cli.org" <<< "$0"' "$out"
    _chk "mysql missing is FAIL and names WPDB_MYSQL_BIN" bash -c 'grep -q "FAIL  mysql client" <<< "$0" && grep -q "WPDB_MYSQL_BIN" <<< "$0"' "$out"
    _chk "the summary counts the failures"               grep -q '2 failed' <<< "$out"
    _finish "tool checks behave"
}

test_doctor_site() {
    start_test "Site checks" "connection, CREATE DATABASE, sql_mode, config, backup folder, no secrets"
    local errors=0 b="$_DC_WORK/bin_site" site="$_DC_WORK/site" out rc
    _dc_tools "$b"; _dc_stubs "$b"; _dc_add "$b" gzip unzip bzip2 git curl sha256sum shasum openssl
    mkdir -p "$_DC_WORK/home" "$_DC_WORK/none"
    _dc_site "$site"
    export STUB_LOG="$_DC_WORK/argv.log"; : > "$STUB_LOG"

    out=$(_dc_run "$site" "$b"); rc=$?
    _chk "healthy site: exit 0, no FAIL"                 bash -c 'test "$1" -eq 0 && ! grep -q FAIL <<< "$0"' "$out" "$rc"
    _chk "credentials row names db and user"             grep -q "database 'sitedb', user 'siteuser'" <<< "$out"
    _chk "server version row"                            grep -q 'OK    Database server  *8.4.0' <<< "$out"
    _chk "CREATE DATABASE row is OK"                     grep -q 'OK    CREATE DATABASE' <<< "$out"
    _chk "backup folder row names the default folder"    grep -q "$_DC_WORK/home/.wp-db-import/backups" <<< "$out"
    _chk "free disk space is reported"                   grep -q 'Free disk space' <<< "$out"
    _chk "the password is not in the output"             bash -c '! grep -qF -- "$1" <<< "$0"' "$out" "$_DC_PW"
    _chk "the password is not in any client argument"    bash -c '! grep -qF -- "$1" "$0"' "$STUB_LOG" "$_DC_PW"
    _chk "the scratch database is dropped"               grep -q 'DROP DATABASE IF EXISTS `wpdb_doctor_' "$STUB_LOG"

    out=$(STUB_CONNECT=fail _dc_run "$site" "$b"); rc=$?
    _chk "connection failure: FAIL with the server error, exit 1" bash -c 'test "$1" -eq 1 && grep -q "FAIL  Database server.*Access denied" <<< "$0"' "$out" "$rc"
    _chk "connection failure: still no password shown"   bash -c '! grep -qF -- "$1" <<< "$0"' "$out" "$_DC_PW"

    out=$(STUB_CREATE=fail _dc_run "$site" "$b"); rc=$?
    _chk "CREATE refused: WARN with the GRANT, exit 0"   bash -c 'test "$1" -eq 0 && grep -q "WARN  CREATE DATABASE" <<< "$0" && grep -q "GRANT CREATE" <<< "$0"' "$out" "$rc"

    out=$(STUB_MODE="STRICT_TRANS_TABLES,NO_ZERO_DATE" _dc_run "$site" "$b")
    _chk "strict sql_mode is a WARN"                     grep -q 'WARN  sql_mode' <<< "$out"

    out=$(STUB_ISINSTALLED=fail _dc_run "$site" "$b"); rc=$?
    _chk "wp core is-installed failing is FAIL, exit 1"  bash -c 'test "$1" -eq 1 && grep -q "FAIL  WordPress" <<< "$0"' "$out" "$rc"

    # config file: valid is OK, invalid is FAIL, and doctor never changes it
    printf '[general]\nuse_socket=false\nbackup_dir=%s/bk\n' "$_DC_WORK" > "$site/wpdb-import.conf"
    local before after
    before=$(cksum < "$site/wpdb-import.conf")
    out=$(_dc_run "$site" "$b"); rc=$?
    after=$(cksum < "$site/wpdb-import.conf")
    _chk "config file is read, not changed"              test "$before" = "$after"
    _chk "backup_dir from the config is used"            grep -q "$_DC_WORK/bk" <<< "$out"
    printf 'this is not a valid config\n' > "$site/wpdb-import.conf"
    out=$(_dc_run "$site" "$b"); rc=$?
    _chk "invalid config: FAIL with the fix command"     bash -c 'test "$1" -eq 1 && grep -q "FAIL  Config file" <<< "$0" && grep -q "config-validate" <<< "$0"' "$out" "$rc"

    # unwritable backup folder
    mkdir -p "$_DC_WORK/ro"; chmod 555 "$_DC_WORK/ro"
    printf '[general]\nbackup_dir=%s/ro/sub\n' "$_DC_WORK" > "$site/wpdb-import.conf"
    if [[ ! -w "$_DC_WORK/ro" ]]; then
        out=$(_dc_run "$site" "$b"); rc=$?
        _chk "unwritable backup folder: FAIL"            bash -c 'test "$1" -eq 1 && grep -q "FAIL  Backup folder" <<< "$0"' "$out" "$rc"
    else
        printf "  ℹ️  running as a user that can write anywhere: unwritable-folder check skipped\n"
    fi
    chmod 755 "$_DC_WORK/ro"
    unset STUB_LOG
    _finish "site checks behave"
}

test_doctor_cli() {
    start_test "CLI wiring" "help text, completions, option errors"
    local errors=0 out rc b="$_DC_WORK/bin_cli"
    _dc_tools "$b"; _dc_stubs "$b"; mkdir -p "$_DC_WORK/nowp" "$_DC_WORK/home" "$_DC_WORK/none"
    out=$(_dc_run "$_DC_WORK/nowp" "$b" --bogus); rc=$?
    _chk "unknown option: exit 2"                        test "$rc" -eq 2
    out=$(_dc_run "$_DC_WORK/nowp" "$b" --help); rc=$?
    _chk "--help: usage, exit 0"                         bash -c 'test "$1" -eq 0 && grep -q "Usage: wp-db-import doctor" <<< "$0"' "$out" "$rc"
    _chk "main --help lists doctor"                      bash -c "bash '$_DC_ROOT/wp-db-import' --help 2>&1 | grep -q 'wp-db-import doctor'"
    _chk "Bash completion lists doctor"                  grep -q 'restore doctor' "$_DC_ROOT/lib/completion/wp-db-import.bash"
    _chk "Zsh completion lists doctor"                   grep -q "'doctor:" "$_DC_ROOT/lib/completion/_wp-db-import"
    _chk "module loader loads doctor.sh"                 grep -q 'doctor.sh' "$_DC_ROOT/lib/module_loader.sh"
    _finish "CLI wiring is complete"
}

run_doctor_tests() {
    printf "\n${CYAN}${BOLD}🧪 Doctor Tests${RESET}\n"
    printf "%s\n\n" "$(printf '=%.0s' {1..50})"
    init_test_session "doctor"
    _DC_WORK=$(mktemp -d "${TMPDIR:-/tmp}/wpdb-doctor-test.XXXXXX")
    trap 'chmod -R u+w "$_DC_WORK" 2>/dev/null; rm -rf "$_DC_WORK"' EXIT

    test_doctor_tools
    test_doctor_site
    test_doctor_cli

    finalize_test_session
    return $?
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    run_doctor_tests
fi
