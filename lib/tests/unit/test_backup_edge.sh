#!/usr/bin/env bash

# ================================================================
# Backup Edge Cases - Tests
# ================================================================
#
# Description:
#   Tests for issue #17. WP-CLI, df and (for failure cases) gpg are replaced by stubs; the gpg
#   round trip uses a throw-away key in a private GNUPGHOME (skipped when gpg is missing).
#     1. free disk space: ok, tight (warn), too little (cancel before anything is written),
#        unknown size or space (no check)
#     2. backup_keep_days: age rule, boundary, mixed with backup_keep, current and protected
#        files kept, other databases and other file names untouched, .gpg files, off values
#     3. encryption settings: off values, gpg missing, recipient missing or unknown, bad value
#     4. the encrypted backup: .sql.gz.gpg, mode 600, a valid OpenPGP file, decrypts to the
#        dump, no .partial left, never an unencrypted file when encryption fails
#     5. restore of an encrypted backup (decrypt once, temp file removed, wrong key = nothing changed)
#     6. progress output (only when enabled) and pipeline failures (export, gpg)
#     7. config: new keys migrated with comments and defaults, loaded, doctor row
#
# Usage:
#   ./lib/tests/unit/test_backup_edge.sh
#
# ================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../test_framework.sh"

_BE_ROOT="$PROJECT_ROOT_DIR"
_BE_WORK=""
_BE_ORIG_PATH="$PATH"

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

_be_load() {
    source "$_BE_ROOT/lib/core/utils.sh" >/dev/null 2>&1
    source "$_BE_ROOT/lib/config/config_manager.sh" >/dev/null 2>&1
    source "$_BE_ROOT/lib/config/integration.sh" >/dev/null 2>&1
    source "$_BE_ROOT/lib/database/sql_source.sh" >/dev/null 2>&1
    source "$_BE_ROOT/lib/database/db_backup.sh" >/dev/null 2>&1
    source "$_BE_ROOT/lib/database/db_restore.sh" >/dev/null 2>&1
    PATH="$_BE_ORIG_PATH"
    CONFIG_BACKUP_ENCRYPT=""; CONFIG_BACKUP_GPG_RECIPIENT=""; CONFIG_BACKUP_KEEP_DAYS=""
    CONFIG_BACKUP_BEFORE_IMPORT="true"; CONFIG_BACKUP_DIR=""; CONFIG_BACKUP_KEEP="5"
    unset WPDB_BACKUP_PROTECT WPDB_BACKUP_PROGRESS WPDB_BACKUP_PROGRESS_AFTER
}

# Runs a snippet, captures its output (colors removed) and exit status: sets _BE_OUT and _BE_RC
_be_cap() {
    local o
    o=$(eval "$1" 2>&1); _BE_RC=$?
    _BE_OUT=$(printf '%s\n' "$o" | _strip)
}

# Epoch seconds N seconds ago -> "touch -t" stamp (BSD and GNU date)
_be_stamp() {
    local epoch=$(( $(date +%s) - $1 ))
    date -r "$epoch" +%Y%m%d%H%M.%S 2>/dev/null || date -d "@$epoch" +%Y%m%d%H%M.%S
}
# _be_file <dir> <name> <age in seconds>
_be_file() { : > "$1/$2"; touch -t "$(_be_stamp "$3")" "$1/$2"; }

# A fake site (wp-config.php with a database name) and a stub WP-CLI
_be_site() {
    mkdir -p "$_BE_WORK/site"
    printf "<?php\ndefine( 'DB_NAME', 'sitedb' );\ndefine( 'DB_USER', 'u' );\ndefine( 'DB_PASSWORD', 'p' );\ndefine( 'DB_HOST', 'localhost' );\n" > "$_BE_WORK/site/wp-config.php"
}
_be_stub_wp() {
    : > "$_BE_WORK/wp.calls"
    execute_wp_cli() {
        printf "%s\n" "$*" >> "$_BE_WORK/wp.calls"
        case "$1 $2" in
            "db tables") echo "wp_options"; return 0 ;;
            "db export")
                [[ -n "${STUB_SLEEP:-}" ]] && sleep "$STUB_SLEEP"
                printf 'CREATE TABLE `wp_options` (id int);\nINSERT INTO `wp_options` VALUES (1);\n'
                return "${STUB_EXPORT_RC:-0}"
                ;;
        esac
        return 0
    }
}
# df stub: STUB_FREE_KB free
_be_stub_df() {
    mkdir -p "$_BE_WORK/stubbin"
    printf '#!/bin/sh\necho "Filesystem 1024-blocks Used Available Capacity Mounted on"\necho "x 9999999 1 ${STUB_FREE_KB:-9999999} 1%% /"\n' > "$_BE_WORK/stubbin/df"
    chmod +x "$_BE_WORK/stubbin/df"
}

# ----------------------------------------------------------------
test_disk_space() {
    start_test "Free disk space" "checked against the database size before anything is written"
    _be_load; _be_site; _be_stub_wp; _be_stub_df
    local errors=0 out rc dir="$_BE_WORK/bk1"
    mkdir -p "$dir"
    # 4 GB database -> about 2 GB backup -> needs about 2 GB + 1 MB
    _import_db_query() { printf "%s\n" "$M_DBSIZE"; }

    export STUB_FREE_KB=10485760   # 10 GB free
    M_DBSIZE=4294967296
    _be_cap 'PATH="$_BE_WORK/stubbin:$PATH" backup_check_space "$dir"'; out=$_BE_OUT; rc=$_BE_RC
    _chk "plenty of space: rc 0 and no message"           test "$rc" -eq 0 -a -z "$out"
    export STUB_FREE_KB=3145728    # 3 GB: more than 2 GB needed, less than twice
    _be_cap 'PATH="$_BE_WORK/stubbin:$PATH" backup_check_space "$dir"'; out=$_BE_OUT; rc=$_BE_RC
    _chk "tight: rc 0 with a warning"                     bash -c 'test "$1" -eq 0 && grep -q "Free space for the backup is tight" <<< "$0"' "$out" "$rc"
    export STUB_FREE_KB=1048576    # 1 GB free
    _be_cap 'PATH="$_BE_WORK/stubbin:$PATH" backup_check_space "$dir"'; out=$_BE_OUT; rc=$_BE_RC
    _chk "too little: rc 1"                               test "$rc" -eq 1
    _chk "the message has the needed and free sizes"      bash -c 'grep -q "about 2049 MB needed, 1024 MB free" <<< "$0"' "$out"
    _chk "the message names the database size and the fixes" bash -c 'grep -q "database size 4096 MB" <<< "$0" && grep -q "backup_dir" <<< "$0" && grep -q "backup_before_import=false" <<< "$0"' "$out"

    M_DBSIZE=""
    out=$(PATH="$_BE_WORK/stubbin:$PATH" backup_check_space "$dir" 2>&1); rc=$?
    _chk "unknown database size: no check (rc 0)"         test "$rc" -eq 0 -a -z "$out"
    M_DBSIZE=4294967296; export STUB_FREE_KB=""
    out=$(PATH="$_BE_WORK/stubbin:$PATH" backup_check_space "$dir" 2>&1); rc=$?
    _chk "unknown free space: no check (rc 0)"            test "$rc" -eq 0
    unset -f _import_db_query
    out=$(backup_check_space "$dir" 2>&1); rc=$?
    _chk "no query helper loaded: no check (rc 0)"        test "$rc" -eq 0 -a -z "$out"

    # the full flow: not enough space cancels BEFORE the export runs or a file is written
    _import_db_query() { printf "%s\n" "4294967296"; }
    export STUB_FREE_KB=1048576
    CONFIG_BACKUP_DIR="$_BE_WORK/bk_full"; : > "$_BE_WORK/wp.calls"
    _be_cap 'PATH="$_BE_WORK/stubbin:$PATH" backup_database_before_import "$_BE_WORK/site"'; out=$_BE_OUT; rc=$_BE_RC
    _chk "no space: the backup step returns 1 (the import is cancelled)" test "$rc" -eq 1
    _chk "no space: WP-CLI never exported"                bash -c '! grep -q "db export" "$0"' "$_BE_WORK/wp.calls"
    _chk "no space: no backup file, no partial file"      bash -c 'test -z "$(ls -A "$0" 2>/dev/null)"' "$_BE_WORK/bk_full"
    _chk "no space: the user is told what to do"          grep -q 'Not enough free disk space' <<< "$out"
    export STUB_FREE_KB=10485760
    _be_cap 'PATH="$_BE_WORK/stubbin:$PATH" backup_database_before_import "$_BE_WORK/site"'; out=$_BE_OUT; rc=$_BE_RC
    _chk "enough space: the backup is written"           bash -c 'test "$1" -eq 0 && ls "$0"/sitedb-*.sql.gz >/dev/null' "$_BE_WORK/bk_full" "$rc"
    unset -f _import_db_query; unset STUB_FREE_KB
    _finish "free space is checked"
}

# ----------------------------------------------------------------
test_keep_days() {
    start_test "backup_keep_days" "age rule next to backup_keep; the current and protected files are never deleted"
    _be_load
    local errors=0 d="$_BE_WORK/bk2" n day=86400
    mkdir -p "$d"
    _be_file "$d" "db-20260101-000001.sql.gz"      $((10 * day))
    _be_file "$d" "db-20260102-000001.sql.gz.gpg"  $((5 * day))
    _be_file "$d" "db-20260103-000001.sql.gz"      $((2 * day))
    _be_file "$d" "db-20260104-000001.sql.gz"      $((day / 2))
    _be_file "$d" "other-20260101-000001.sql.gz"   $((30 * day))
    _be_file "$d" "db-notes.txt"                   $((30 * day))
    _be_file "$d" "db-20260101-000001.sql.gz.partial" $((30 * day))
    : > "$d/db-20260105-000001.sql.gz"            # the current backup: newest, no age

    n=$(prune_old_backups "$d" db 0 "$d/db-20260105-000001.sql.gz" 3)
    _chk "keep=0 days=3: removes the 10-day and the 5-day (.gpg) backup" test "$n" -eq 2
    _chk "older files are gone"                            bash -c '! test -e "$0/db-20260101-000001.sql.gz" && ! test -e "$0/db-20260102-000001.sql.gz.gpg"' "$d"
    _chk "younger files stay (2 days, 12 hours, current)"  bash -c 'test -e "$0/db-20260103-000001.sql.gz" && test -e "$0/db-20260104-000001.sql.gz" && test -e "$0/db-20260105-000001.sql.gz"' "$d"
    _chk "another database and other names are untouched"  bash -c 'test -e "$0/other-20260101-000001.sql.gz" && test -e "$0/db-notes.txt"' "$d"
    _chk "a stale .partial of this database is removed"    bash -c '! test -e "$0/db-20260101-000001.sql.gz.partial"' "$d"

    # boundary: age >= N days is "older than N days"
    d="$_BE_WORK/bk3"; mkdir -p "$d"
    _be_file "$d" "db-20260101-000001.sql.gz" $((day + 3600))      # 25 h
    _be_file "$d" "db-20260102-000001.sql.gz" $((day - 3600))      # 23 h
    : > "$d/db-20260103-000001.sql.gz"
    n=$(prune_old_backups "$d" db 0 "$d/db-20260103-000001.sql.gz" 1)
    _chk "days=1: the 25 h backup goes, the 23 h backup stays" bash -c 'test "$1" -eq 1 && ! test -e "$0/db-20260101-000001.sql.gz" && test -e "$0/db-20260102-000001.sql.gz"' "$d" "$n"

    # a very old file is the one being restored: protected
    d="$_BE_WORK/bk4"; mkdir -p "$d"
    _be_file "$d" "db-20250101-000001.sql.gz" $((400 * day))
    _be_file "$d" "db-20250102-000001.sql.gz" $((399 * day))
    : > "$d/db-20260103-000001.sql.gz"
    n=$(WPDB_BACKUP_PROTECT="$d/db-20250101-000001.sql.gz" prune_old_backups "$d" db 0 "$d/db-20260103-000001.sql.gz" 30)
    _chk "the file being restored survives the age rule"   bash -c 'test "$1" -eq 1 && test -e "$0/db-20250101-000001.sql.gz" && ! test -e "$0/db-20250102-000001.sql.gz"' "$d" "$n"
    _chk "the newest backup always survives"               test -e "$d/db-20260103-000001.sql.gz"

    # the "current" backup is never deleted, even with an old timestamp (clock changes, copied files)
    d="$_BE_WORK/bk4b"; mkdir -p "$d"
    _be_file "$d" "db-20240101-000001.sql.gz" $((500 * day))
    n=$(prune_old_backups "$d" db 0 "$d/db-20240101-000001.sql.gz" 30)
    _chk "the current backup survives even when it looks old" bash -c 'test "$1" -eq 0 && test -e "$0/db-20240101-000001.sql.gz"' "$d" "$n"

    # backup_keep and backup_keep_days together: either rule deletes
    d="$_BE_WORK/bk5"; mkdir -p "$d"
    _be_file "$d" "db-20260101-000001.sql.gz" $((1 * day / 2))
    _be_file "$d" "db-20260102-000001.sql.gz" $((1 * day / 3))
    _be_file "$d" "db-20260103-000001.sql.gz" $((1 * day / 4))
    _be_file "$d" "db-20260104-000001.sql.gz" $((20 * day))
    : > "$d/db-20260105-000001.sql.gz"
    n=$(prune_old_backups "$d" db 3 "$d/db-20260105-000001.sql.gz" 7)
    _chk "keep=3 days=7: count rule drops the 3rd-newest; age rule drops the 20-day one" bash -c 'test "$1" -ge 2 && ! test -e "$0/db-20260104-000001.sql.gz" && test -e "$0/db-20260105-000001.sql.gz"' "$d" "$n"
    _chk "exactly 3 backups remain"                        test "$(ls "$d" | wc -l | tr -d ' ')" -eq 3

    # off values change nothing
    d="$_BE_WORK/bk6"; mkdir -p "$d"
    _be_file "$d" "db-20240101-000001.sql.gz" $((900 * day))
    : > "$d/db-20260101-000001.sql.gz"
    for v in 0 "" abc -3 1.5; do
        n=$(prune_old_backups "$d" db 0 "$d/db-20260101-000001.sql.gz" "$v")
        _chk "keep=0 days='$v': nothing is deleted"        bash -c 'test "$1" -eq 0 && test -e "$0/db-20240101-000001.sql.gz"' "$d" "$n"
    done
    n=$(prune_old_backups "$d" db 0 "$d/db-20260101-000001.sql.gz")
    _chk "no fifth argument: same as off"                  test "$n" -eq 0
    _finish "backup_keep_days works"
}

# ----------------------------------------------------------------
test_encryption_settings() {
    start_test "Encryption settings" "a requested encryption never silently becomes an unencrypted backup"
    _be_load
    local errors=0 out rc v nogpg="$_BE_WORK/nogpg"
    for v in "" false no 0 off none FALSE; do
        CONFIG_BACKUP_ENCRYPT="$v"
        out=$(backup_encryption_recipient 2>&1); rc=$?
        _chk "backup_encrypt='$v': off, no output, rc 0"   test "$rc" -eq 0 -a -z "$out"
    done
    CONFIG_BACKUP_ENCRYPT="aes"
    _be_cap 'backup_encryption_recipient'; out=$_BE_OUT; rc=$_BE_RC
    _chk "an unknown value is an error (not 'off')"        bash -c 'test "$1" -eq 1 && grep -q "Unknown backup_encrypt value" <<< "$0"' "$out" "$rc"

    # gpg missing: a private bin dir without gpg
    mkdir -p "$nogpg"
    for t in tr printf cat; do ln -sf "$(command -v $t)" "$nogpg/$t"; done
    CONFIG_BACKUP_ENCRYPT="gpg"; CONFIG_BACKUP_GPG_RECIPIENT="a@b.c"
    _be_cap 'PATH="$nogpg" backup_encryption_recipient'; out=$_BE_OUT; rc=$_BE_RC
    _chk "gpg not installed: rc 1, no unencrypted fallback" bash -c 'test "$1" -eq 1 && grep -q "gpg is not installed" <<< "$0" && grep -q "no unencrypted backup is made" <<< "$0"' "$out" "$rc"

    if command -v gpg >/dev/null 2>&1; then
        export GNUPGHOME; GNUPGHOME=$(mktemp -d /tmp/wpdbg.XXXXXX); chmod 700 "$GNUPGHOME"
        CONFIG_BACKUP_GPG_RECIPIENT=""
        _be_cap 'backup_encryption_recipient'; out=$_BE_OUT; rc=$_BE_RC
        _chk "no recipient: rc 1 and the setting is named"  bash -c 'test "$1" -eq 1 && grep -q "backup_gpg_recipient" <<< "$0"' "$out" "$rc"
        CONFIG_BACKUP_GPG_RECIPIENT="nobody@example.invalid"
        _be_cap 'backup_encryption_recipient'; out=$_BE_OUT; rc=$_BE_RC
        _chk "unknown key: rc 1 and the fix is shown"       bash -c 'test "$1" -eq 1 && grep -q "No gpg public key found" <<< "$0" && grep -q "gpg --list-keys" <<< "$0"' "$out" "$rc"
        gpg --batch --pinentry-mode loopback --passphrase '' --quick-generate-key "wpdb-test@example.invalid" default default never >/dev/null 2>&1
        CONFIG_BACKUP_GPG_RECIPIENT="wpdb-test@example.invalid"
        out=$(backup_encryption_recipient 2>&1); rc=$?
        _chk "a known key: rc 0 and the recipient is printed" test "$rc" -eq 0 -a "$out" = "wpdb-test@example.invalid"
        gpgconf --kill gpg-agent >/dev/null 2>&1; rm -rf "$GNUPGHOME"; unset GNUPGHOME
    else
        printf "  ℹ️  gpg not installed: key checks skipped\n"
    fi
    _finish "encryption settings are strict"
}

# ----------------------------------------------------------------
test_encrypted_backup() {
    start_test "Encrypted backup and restore" "a real gpg round trip, and every way it can fail leaves no unencrypted file"
    if ! command -v gpg >/dev/null 2>&1; then
        skip_test "gpg not installed"
        return 0
    fi
    _be_load; _be_site; _be_stub_wp
    local errors=0 out rc f dir="$_BE_WORK/bk_enc" mode
    export GNUPGHOME; GNUPGHOME=$(mktemp -d /tmp/wpdbg.XXXXXX); chmod 700 "$GNUPGHOME"
    gpg --batch --pinentry-mode loopback --passphrase '' --quick-generate-key "wpdb-test@example.invalid" default default never >/dev/null 2>&1
    CONFIG_BACKUP_DIR="$dir"; CONFIG_BACKUP_ENCRYPT="gpg"; CONFIG_BACKUP_GPG_RECIPIENT="wpdb-test@example.invalid"

    _be_cap 'backup_database_before_import "$_BE_WORK/site"'; out=$_BE_OUT; rc=$_BE_RC
    f=$(ls "$dir"/sitedb-*.sql.gz.gpg 2>/dev/null | head -1)
    _chk "the backup step succeeds"                        test "$rc" -eq 0
    _chk "the file ends in .sql.gz.gpg"                    test -n "$f"
    mode=$(stat -c %a "$f" 2>/dev/null || stat -f %Lp "$f")
    _chk "the file mode is 600"                            test "$mode" = "600"
    _chk "it is an OpenPGP message for the recipient"      bash -c 'gpg --batch --list-packets "$0" 2>/dev/null | grep -q "pubkey enc packet"' "$f"
    _chk "it is NOT readable as gzip (really encrypted)"   bash -c '! gzip -t "$0" 2>/dev/null' "$f"
    _chk "the SQL text is not visible in the file"         bash -c '! grep -aq "CREATE TABLE" "$0"' "$f"
    _chk "decrypting gives the dump back"                  bash -c 'gpg --batch --quiet --decrypt "$0" 2>/dev/null | gunzip -c | grep -q "INSERT INTO `wp_options`"' "$f"
    _chk "no .partial and no unencrypted file left"        bash -c 'test -z "$(ls "$0" | grep -v "\.sql\.gz\.gpg$")"' "$dir"
    _chk "the message says it is encrypted and how to restore" bash -c 'grep -q "encrypted for wpdb-test@example.invalid" <<< "$0" && grep -q "wp-db-import restore" <<< "$0"' "$out"

    # listing and rotation know the .gpg name
    _chk "restore --list includes the encrypted backup"    bash -c 'source "'"$_BE_ROOT"'/lib/core/utils.sh" >/dev/null 2>&1; source "'"$_BE_ROOT"'/lib/database/sql_source.sh" >/dev/null 2>&1; source "'"$_BE_ROOT"'/lib/database/db_restore.sh" >/dev/null 2>&1; restore_list_files "$0" sitedb | grep -q "\.sql\.gz\.gpg$"' "$dir"
    _chk "the listing marks it as encrypted"               bash -c 'source "'"$_BE_ROOT"'/lib/core/utils.sh" >/dev/null 2>&1; source "'"$_BE_ROOT"'/lib/database/sql_source.sh" >/dev/null 2>&1; source "'"$_BE_ROOT"'/lib/database/db_restore.sh" >/dev/null 2>&1; restore_print_list "$0" sitedb | grep -q "(encrypted)"' "$dir"

    # an encrypted file is never streamed or imported as plain SQL
    _chk "sql_file_kind: gpg"                              test "$(sql_file_kind "$f")" = "gpg"
    out=$(sql_verify_source "$f" 2>&1); rc=$?
    _chk "sql_verify_source refuses it and points to restore" bash -c 'test "$1" -eq 1 && grep -q "wp-db-import restore" <<< "$0"' "$out" "$rc"
    out=$(sql_open_stream "$f" 2>/dev/null); rc=$?
    _chk "sql_open_stream outputs nothing for it"          test "$rc" -ne 0 -a -z "$out"

    # restore: the plain restore gets the DECRYPTED temp file; the original is named and protected
    _restore_database_plain() { printf "%s|%s|%s|%s\n" "$1" "$2" "$3" "$4" > "$_BE_WORK/plain.args"; [[ -s "$1" ]] && gunzip -c "$1" > "$_BE_WORK/plain.sql"; return 0; }
    restore_database "$f" "$_BE_WORK/site" "" >/dev/null 2>&1; rc=$?
    local a1; a1=$(cut -d'|' -f1 "$_BE_WORK/plain.args"); local a4; a4=$(cut -d'|' -f4 "$_BE_WORK/plain.args")
    _chk "restore: rc 0"                                   test "$rc" -eq 0
    _chk "restore: the plain restore got a decrypted .sql.gz" bash -c 'grep -q "INSERT INTO `wp_options`" "$0"' "$_BE_WORK/plain.sql"
    _chk "restore: the original encrypted file is the shown/protected name" test "$a4" = "$f"
    _chk "restore: the decrypted temp file is removed afterwards" bash -c '! test -e "$0"' "$a1"
    _chk "restore: the temp file was not the original"     test "$a1" != "$f"

    # wrong key (a different, empty keyring): nothing is changed, no plain restore runs
    local other; other=$(mktemp -d /tmp/wpdbg.XXXXXX); chmod 700 "$other"
    rm -f "$_BE_WORK/plain.args"
    _be_cap 'GNUPGHOME="$other" restore_database "$f" "$_BE_WORK/site" ""'; out=$_BE_OUT; rc=$_BE_RC
    _chk "no secret key: rc 1, 'Nothing was changed'"      bash -c 'test "$1" -eq 1 && grep -q "Could not decrypt" <<< "$0" && grep -q "Nothing was changed" <<< "$0"' "$out" "$rc"
    _chk "no secret key: the restore never started"        bash -c '! test -e "$0"' "$_BE_WORK/plain.args"
    GNUPGHOME="$other" gpgconf --kill gpg-agent >/dev/null 2>&1; rm -rf "$other"
    unset -f _restore_database_plain; source "$_BE_ROOT/lib/database/db_restore.sh" >/dev/null 2>&1

    # --- failures leave NO file: gpg fails; gpg missing; export fails
    rm -rf "$dir"; : > "$_BE_WORK/wp.calls"
    mkdir -p "$_BE_WORK/badgpg"
    printf '#!/bin/sh\ncase "$*" in *--list-keys*) exit 0 ;; *--version*) echo "gpg stub" ;; *) cat >/dev/null; exit 2 ;; esac\n' > "$_BE_WORK/badgpg/gpg"; chmod +x "$_BE_WORK/badgpg/gpg"
    _be_cap 'PATH="$_BE_WORK/badgpg:$PATH" backup_database_before_import "$_BE_WORK/site"'; out=$_BE_OUT; rc=$_BE_RC
    _chk "gpg fails mid-pipeline: rc 1, import cancelled"  bash -c 'test "$1" -eq 1 && grep -q "import cancelled" <<< "$0"' "$out" "$rc"
    _chk "gpg fails: no file at all (not even unencrypted)" bash -c 'test -z "$(ls -A "$0" 2>/dev/null)"' "$dir"

    CONFIG_BACKUP_GPG_RECIPIENT="nobody@example.invalid"; : > "$_BE_WORK/wp.calls"
    _be_cap 'backup_database_before_import "$_BE_WORK/site"'; out=$_BE_OUT; rc=$_BE_RC
    _chk "unknown recipient: rc 1 before any export"       bash -c 'test "$1" -eq 1 && ! grep -q "db export" "$2"' _ "$rc" "$_BE_WORK/wp.calls"
    _chk "unknown recipient: no file"                      bash -c 'test -z "$(ls -A "$0" 2>/dev/null)"' "$dir"
    CONFIG_BACKUP_GPG_RECIPIENT="wpdb-test@example.invalid"

    STUB_EXPORT_RC=3
    _be_cap 'backup_database_before_import "$_BE_WORK/site"'; out=$_BE_OUT; rc=$_BE_RC
    unset STUB_EXPORT_RC
    _chk "the export fails (gpg still gets data): rc 1, no file" bash -c 'test "$1" -eq 1 && test -z "$(ls -A "$0" 2>/dev/null)"' "$dir" "$rc"

    gpgconf --kill gpg-agent >/dev/null 2>&1; rm -rf "$GNUPGHOME"; unset GNUPGHOME
    _finish "encrypted backups round-trip and fail safe"
}

# ----------------------------------------------------------------
test_progress_and_failures() {
    start_test "Progress and failures" "size written so far for long backups; every pipeline stage can fail the backup"
    _be_load; _be_site; _be_stub_wp
    local errors=0 out rc dir="$_BE_WORK/bk_prog"
    CONFIG_BACKUP_DIR="$dir"

    STUB_SLEEP=3
    out=$(WPDB_BACKUP_PROGRESS=1 WPDB_BACKUP_PROGRESS_AFTER=1 backup_database_before_import "$_BE_WORK/site" 2>&1 | _strip | tr '\r' '\n')
    unset STUB_SLEEP
    _chk "a slow backup shows 'Backing up... N written'"   bash -c 'grep -q "Backing up\.\.\. .* written (00:0" <<< "$0"' "$out"
    _chk "the backup is still saved"                       bash -c 'ls "$0"/sitedb-*.sql.gz >/dev/null' "$dir"
    _chk "the progress line is cleared at the end"         bash -c 'tail -n +1 <<< "$0" | grep -q "Backup saved"' "$out"

    rm -rf "$dir"; STUB_SLEEP=2
    out=$(backup_database_before_import "$_BE_WORK/site" 2>&1 | _strip | tr '\r' '\n')
    unset STUB_SLEEP
    _chk "not in a terminal (and not forced): no progress text" bash -c '! grep -q "written (" <<< "$0"' "$out"

    rm -rf "$dir"
    out=$(WPDB_BACKUP_PROGRESS=1 backup_database_before_import "$_BE_WORK/site" 2>&1 | _strip | tr '\r' '\n')
    _chk "a fast backup shows no progress line (under the delay)" bash -c '! grep -q "written (" <<< "$0"' "$out"

    # the pipeline status counts all stages (pipefail): a failing export fails the backup
    rm -rf "$dir"; STUB_EXPORT_RC=1
    _be_cap 'backup_database_before_import "$_BE_WORK/site"'; out=$_BE_OUT; rc=$_BE_RC
    unset STUB_EXPORT_RC
    _chk "export fails: rc 1, import cancelled, no file"   bash -c 'test "$1" -eq 1 && grep -q "import cancelled" <<< "$0" && test -z "$(ls -A "$2" 2>/dev/null)"' "$out" "$rc" "$dir"

    # an unwritable folder still fails early (existing behaviour)
    CONFIG_BACKUP_DIR="/proc/nope/bk"
    _be_cap 'backup_database_before_import "$_BE_WORK/site"'; out=$_BE_OUT; rc=$_BE_RC
    _chk "unwritable backup_dir: rc 1"                     test "$rc" -eq 1
    _finish "progress and failures behave"
}

# ----------------------------------------------------------------
test_config_keys() {
    start_test "Config keys" "new keys are migrated with comments and defaults, loaded, and shown by doctor"
    _be_load
    local errors=0 old="$_BE_WORK/old.conf" out
    printf '[general]\nsql_file=a.sql\nold_domain=a.com\nnew_domain=b.test\nbackup_before_import=true\nbackup_keep=7\n\n[site_mappings]\n1:a.com:b.test\n' > "$old"
    ensure_socket_config_settings "$old" >/dev/null 2>&1
    _chk "backup_keep_days=0 added with its comment"       bash -c 'source "'"$_BE_ROOT"'/lib/core/utils.sh" >/dev/null 2>&1; source "'"$_BE_ROOT"'/lib/config/config_manager.sh" >/dev/null 2>&1; t=$(cat "$0"); [[ "$t" == *"$(config_key_comment backup_keep_days)"*"backup_keep_days=0"* && "$(parse_config_section "$0" general backup_keep_days)" == 0 ]]' "$old"
    _chk "backup_encrypt=false added with its comment"     bash -c 'source "'"$_BE_ROOT"'/lib/core/utils.sh" >/dev/null 2>&1; source "'"$_BE_ROOT"'/lib/config/config_manager.sh" >/dev/null 2>&1; t=$(cat "$0"); [[ "$t" == *"$(config_key_comment backup_encrypt)"*"backup_encrypt=false"* && "$(parse_config_section "$0" general backup_encrypt)" == false ]]' "$old"
    _chk "backup_gpg_recipient= added (blank)"             bash -c 'source "'"$_BE_ROOT"'/lib/core/utils.sh" >/dev/null 2>&1; source "'"$_BE_ROOT"'/lib/config/config_manager.sh" >/dev/null 2>&1; grep -qx "backup_gpg_recipient=" "$0" && [[ -z "$(parse_config_section "$0" general backup_gpg_recipient)" ]]' "$old"
    _chk "the user's own values are untouched"             bash -c 'source "'"$_BE_ROOT"'/lib/core/utils.sh" >/dev/null 2>&1; source "'"$_BE_ROOT"'/lib/config/config_manager.sh" >/dev/null 2>&1; [[ "$(parse_config_section "$0" general backup_before_import)" == true && "$(parse_config_section "$0" general backup_keep)" == 7 ]]' "$old"
    _chk "the comments explain gpg and 'never unencrypted'" bash -c 'grep -q "never falls back" "$0" || grep -q "never falls back" <(sed -n "1,400p" "'"$_BE_ROOT"'/lib/config/config_manager.sh")' "$old"
    local a; a=$(cksum < "$old")
    ensure_socket_config_settings "$old" >/dev/null 2>&1
    _chk "a second migration changes nothing"              test "$a" = "$(cksum < "$old")"

    # loading
    load_import_config "$old" >/dev/null 2>&1
    _chk "load_import_config: defaults 0, false, blank"    test "$CONFIG_BACKUP_KEEP_DAYS" = "0" -a "$CONFIG_BACKUP_ENCRYPT" = "false" -a -z "$CONFIG_BACKUP_GPG_RECIPIENT"
    sed -i.bak 's/^backup_keep_days=.*/backup_keep_days=30/; s/^backup_encrypt=.*/backup_encrypt=gpg/; s/^backup_gpg_recipient=.*/backup_gpg_recipient=me@example.com/' "$old" && rm -f "$old.bak"
    load_import_config "$old" >/dev/null 2>&1
    _chk "load_import_config: reads 30, gpg, recipient"    test "$CONFIG_BACKUP_KEEP_DAYS" = "30" -a "$CONFIG_BACKUP_ENCRYPT" = "gpg" -a "$CONFIG_BACKUP_GPG_RECIPIENT" = "me@example.com"
    printf '[general]\nsql_file=a.sql\nold_domain=a.com\nnew_domain=b.test\n\n[site_mappings]\n' > "$_BE_WORK/bare.conf"
    load_import_config "$_BE_WORK/bare.conf" >/dev/null 2>&1
    _chk "a config without the keys loads the defaults"    test "$CONFIG_BACKUP_KEEP_DAYS" = "0" -a "$CONFIG_BACKUP_ENCRYPT" = "false"

    # fresh config has the keys
    create_config_file "$_BE_WORK/fresh.conf" a.sql a.com b.test >/dev/null 2>&1
    _chk "a new config contains the three keys"            bash -c 'grep -qx "backup_keep_days=0" "$0" && grep -qx "backup_encrypt=false" "$0" && grep -qx "backup_gpg_recipient=" "$0"' "$_BE_WORK/fresh.conf"
    ensure_socket_config_settings "$_BE_WORK/fresh.conf" >/dev/null 2>&1
    _chk "a new config needs no migration"                 test "$CONFIG_SOCKET_SETTINGS_MIGRATED" = "false"

    # doctor row (only when encryption is on)
    _chk "doctor reports backup encryption problems"       grep -q 'Backup encryption' "$_BE_ROOT/lib/utilities/doctor.sh"
    _chk "example configs show the new keys"               bash -c 'for f in single multisite; do grep -q "backup_keep_days" "'"$_BE_ROOT"'/wpdb-import-example-$f.conf" || exit 1; done'
    _finish "config keys are complete"
}

run_backup_edge_tests() {
    printf "\n${CYAN}${BOLD}🧪 Backup Edge Case Tests${RESET}\n"
    printf "%s\n\n" "$(printf '=%.0s' {1..50})"
    init_test_session "backup_edge"
    _BE_WORK=$(mktemp -d "${TMPDIR:-/tmp}/wpdb-be-test.XXXXXX")
    trap 'rm -rf "$_BE_WORK"; secure_tmpdir_cleanup 2>/dev/null' EXIT

    test_disk_space
    test_keep_days
    test_encryption_settings
    test_encrypted_backup
    test_progress_and_failures
    test_config_keys

    finalize_test_session
    return $?
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    run_backup_edge_tests
fi
