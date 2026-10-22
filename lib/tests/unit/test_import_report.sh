#!/usr/bin/env bash

# ================================================================
# Post-Import Report - Tests
# ================================================================
#
# Description:
#   Tests for issue #21. WP-CLI is replaced by a stub that prints the tab separated rows WP-CLI prints, so
#   the whole report can be checked without a server: the parser (replacements per table, PHP and SQL
#   types, skipped tables, Error/Warning lines, noise ignored), the leftover check (read-only, same table
#   flags as the real run, a failing call prints nothing), the old-host list, the rotation (report_keep),
#   the printed and saved report (mode 600, single site and multisite text, import_report=false, an
#   unwritable folder, a report that never fails the import) and the wiring in the import script.
#   (lib/tests/integration/test_real_import.sh checks the report of real imports.)
#
# Usage:
#   ./lib/tests/unit/test_import_report.sh
#
# ================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../test_framework.sh"

_P_ROOT="$PROJECT_ROOT_DIR"
_P_WORK=""

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
_mode() { stat -c %a "$1" 2>/dev/null || stat -f %Lp "$1"; }

_p_load() {
    source "$_P_ROOT/lib/core/utils.sh" >/dev/null 2>&1
    source "$_P_ROOT/lib/config/config_manager.sh" >/dev/null 2>&1
    source "$_P_ROOT/lib/database/import_report.sh" >/dev/null 2>&1
    WPDB_REPORT_STEPS=""; WPDB_IMPORT_NOTES=""
    unset CONFIG_IMPORT_REPORT CONFIG_REPORT_KEEP CONFIG_SKIP_TABLES CONFIG_PRECISE
    all_tables_flag="--all-tables"; skip_tables_flag=""; precise_flag=""; dry_run_flag=""; network_flag=""
}

# The WP-CLI output of one search-replace pass: header, rows (tab separated), summary
_p_wp_out() {
    printf 'Table\tColumn\tReplacements\tType\n'
    printf '%s\n' "$@" | sed 's/  */\t/g'
    printf 'Success: Made 9 replacements.\n'
}

# A private temp folder with the logs of a finished single-site run
_p_logs() {
    local tmp; tmp=$(secure_tmpdir)
    rm -f "$tmp"/replace_single.log "$tmp"/replace_custom.log "$tmp"/wp_replace_*.log "$tmp"/wp_custom_*.log
    { _p_wp_out "wp_posts post_content 8 SQL" "wp_options option_value 4 PHP"
      _p_wp_out "wp_posts post_content 2 SQL" "wp_postmeta meta_value 3 PHP"
      printf 'wp_nopk\t\tskipped\t\n'
      printf 'Warning: Skipping column x\n'; } > "$tmp/replace_single.log"
    printf '%s' "$tmp"
}

# ----------------------------------------------------------------
test_parser() {
    start_test "Parser" "replacements per table, PHP and SQL, skipped tables, notes; noise ignored"
    _p_load
    local errors=0 tmp out
    tmp=$(_p_logs)
    printf 'Table\tColumn\tReplacements\tType\nwp_nopk\t\tskipped\t\nSuccess: Made 1 replacements.\nDeprecated: Case statements followed by a semicolon (;) are deprecated\nPHP Warning:  x\nWarning: Skipping column x\nWarning: Skipping column x\nError: something broke\n' > "$tmp/wp_custom_2.log"
    out=$(report_parse_logs "$tmp/replace_single.log" "$tmp/wp_custom_2.log" "$tmp/does-not-exist.log")
    _chk "wp_posts: 8 + 2 over two passes = 10, all SQL"      bash -c 'awk -F"\t" "\$1==\"R\" && \$2==\"wp_posts\" && \$3==10 && \$4==0 && \$5==10" <<< "$0" | grep -q .' "$out"
    _chk "wp_posts total is 10 (passes are added up)"         bash -c 'awk -F"\t" "\$1==\"R\" && \$2==\"wp_posts\" {print \$3}" <<< "$0" | grep -qx 10' "$out"
    _chk "wp_options: 4, all PHP"                             bash -c 'awk -F"\t" "\$1==\"R\" && \$2==\"wp_options\" && \$3==4 && \$4==4 && \$5==0" <<< "$0" | grep -q .' "$out"
    _chk "wp_postmeta: 3, all PHP"                            bash -c 'awk -F"\t" "\$1==\"R\" && \$2==\"wp_postmeta\" && \$3==3 && \$4==3" <<< "$0" | grep -q .' "$out"
    _chk "a skipped table is reported once"                   test "$(grep -c '^S' <<< "$out")" = 1
    _chk "the skipped table is wp_nopk"                       grep -q "^S"$'\t'"wp_nopk" <<< "$out"
    _chk "Warning lines are notes, repeated lines only once"  test "$(grep -c '^N.*Skipping column x' <<< "$out")" = 1
    _chk "an Error line is a note"                            grep -q "^N"$'\t'"Error: something broke" <<< "$out"
    _chk "the header row, Success lines, PHP deprecations are not records" bash -c '! grep -qE "^R.*(Table|Success|Deprecated)|^N.*(Deprecated|PHP Warning)" <<< "$0"' "$out"
    _chk "no logs: no output and no error"                    bash -c 'test -z "$(report_parse_logs "$0/nope.log")"' "$tmp"
    printf 'wp_x\tc\t5\tWEIRD\n' > "$tmp/odd.log"
    _chk "an unknown type is ignored, not counted"            bash -c 'test -z "$(report_parse_logs "$0")"' "$tmp/odd.log"
    _finish "the parser reads WP-CLI logs"
}

# ----------------------------------------------------------------
test_leftovers() {
    start_test "Leftovers" "read-only dry run per host, same table flags, a failing call prints nothing"
    _p_load
    local errors=0 calls="$_P_WORK/calls" out
    : > "$calls"
    execute_wp_cli() {
        local IFS='|'; printf '%s\n' "$*" >> "$calls"
        case "$2" in
            prod.example.com) printf 'Table\tColumn\tReplacements\tType\nwp_users\tuser_email\t2\tSQL\nwp_posts\tpost_content\t5\tSQL\nwp_options\toption_value\t1\tPHP\nSuccess: 8 replacements to be made.\n' ;;
            bad.example.com)  return 1 ;;
            *)                printf 'Success: 0 replacements to be made.\n' ;;
        esac
    }
    out=$(report_leftovers prod.example.com)
    _chk "one call per host"                                  test "$(grep -c '^search-replace' "$calls")" = 1
    _chk "the call is a dry run of the bare host (no //)"     grep -q '^search-replace|prod.example.com|__wpdb_report__|' "$calls"
    _chk "the call can only read: --dry-run is on"            grep -q '|--dry-run' "$calls"
    _chk "same flags as the real run (guid skipped, --all-tables)" bash -c 'grep -q "|--skip-columns=guid" "$0" && grep -q "|--all-tables" "$0"' "$calls"
    _chk "counts per table, most first"                       test "$(cut -f2,3 <<< "$out" | tr '\n' ' ')" = "wp_posts	5 wp_users	2 wp_options	1 "
    _chk "each record starts with the host"                   bash -c 'cut -f1 <<< "$0" | sort -u | grep -qx prod.example.com' "$out"

    : > "$calls"; skip_tables_flag="--skip-tables=wp_logs_*"; precise_flag="--precise"; network_flag="--network"
    report_leftovers prod.example.com >/dev/null
    _chk "skip_tables, precise and --network reach the check" bash -c 'grep -q "|--skip-tables=wp_logs_\*" "$0" && grep -q "|--precise" "$0" && grep -q "|--network" "$0"' "$calls"
    _chk "the caller's dry_run_flag is not changed by the check" test -z "$dry_run_flag"
    skip_tables_flag=""; precise_flag=""; network_flag=""; all_tables_flag=""
    : > "$calls"; report_leftovers prod.example.com >/dev/null
    _chk "all_tables=false: no --all-tables"                  bash -c '! grep -q "|--all-tables" "$0"' "$calls"
    all_tables_flag="--all-tables"

    : > "$calls"
    out=$(report_leftovers bad.example.com prod.example.com other.example.com)
    _chk "a failing host prints nothing, the others still run" bash -c 'test "$(grep -c "^search-replace" "$1")" = 3 && cut -f1 <<< "$0" | sort -u | grep -qx prod.example.com && ! grep -q bad.example.com <<< "$0"' "$out" "$calls"
    _chk "a host with no leftovers prints nothing"            bash -c '! grep -q other.example.com <<< "$0"' "$out"
    _chk "no write command is ever called"                    bash -c '! grep -qE "db query|db import|option update|post update|--dry-run.*false" "$0"' "$calls"
    _chk "no hosts: no call"                                  bash -c ': > "$0"; test -z "$(report_leftovers)" && ! test -s "$0"' "$calls"
    unset -f execute_wp_cli
    _finish "the leftover check is read-only"
}

# ----------------------------------------------------------------
test_hosts_and_rotation() {
    start_test "Hosts and rotation" "old host list; report_keep keeps the latest N reports"
    _p_load
    local errors=0 w="$_P_WORK" d out n f
    _chk "main host only"                                     test "$(report_old_hosts prod.example.com | tr '\n' ' ')" = "prod.example.com "
    out=$(report_old_hosts prod.example.com prod.example.com news.prod.example.com/news www.prod.example.com other.com/blog shop.other.com | tr '\n' ' ')
    _chk "duplicates, paths and subdomains of another host are dropped" test "$out" = "prod.example.com other.com "
    out=$(report_old_hosts "https://a.com/x" "b.com" | tr '\n' ' ')
    _chk "a scheme and a path are removed"                    test "$out" = "a.com b.com "
    _chk "notexample.com is not a subdomain of example.com"   test "$(report_old_hosts example.com notexample.com | tr '\n' ' ')" = "example.com notexample.com "
    _chk "empty input: nothing"                               test -z "$(report_old_hosts)"

    d="$w/rot dir"; mkdir -p "$d"
    printf 'other\n' > "$d/notes.txt"; printf 'x\n' > "$d/wpdb-import.conf"
    for n in 20260101-000001 20260101-000002 20260101-000003 20260101-000004 20260101-000005; do printf '%s\n' "$n" > "$d/wpdb-import-report.$n.txt"; done
    printf 'latest\n' > "$d/wpdb-import-report.txt"
    report_rotate "$d" 3
    _chk "keep=3: the latest report is renamed with a date"   bash -c '! test -e "$0/wpdb-import-report.txt" && ls "$0" | grep -c "^wpdb-import-report\.[0-9]" | grep -qx 2' "$d"
    _chk "keep=3: the 2 newest rotated reports stay (the new report is the 3rd)" bash -c 'ls "$0" | grep -c "^wpdb-import-report\.[0-9]" | grep -qx 2' "$d"
    _chk "keep=3: the renamed latest report is one of them"  bash -c 'grep -lx latest "$0"/wpdb-import-report.*.txt | grep -q .' "$d"
    _chk "keep=3: other files are never touched"             bash -c 'test -f "$0/notes.txt" && test -f "$0/wpdb-import.conf"' "$d"
    _chk "keep=3: the oldest dated reports are gone"         bash -c '! test -e "$0/wpdb-import-report.20260101-000001.txt" && ! test -e "$0/wpdb-import-report.20260101-000002.txt"' "$d"

    d="$w/rot2"; mkdir -p "$d"
    for n in 1 2 3 4 5 6 7; do printf '%s\n' "$n" > "$d/wpdb-import-report.2026010$n-000000.txt"; done
    printf 'latest\n' > "$d/wpdb-import-report.txt"
    report_rotate "$d" 0
    _chk "keep=0: every report is kept"                      bash -c 'ls "$0" | grep -c "^wpdb-import-report\." | grep -qx 8' "$d"
    report_rotate "$d" 1
    _chk "keep=1: only the new report will exist (all dated ones deleted)" bash -c '! ls "$0" | grep -q "^wpdb-import-report\.[0-9]"' "$d"
    printf 'again\n' > "$d/wpdb-import-report.txt"; report_rotate "$d" 5; report_rotate "$d" 5
    _chk "two rotations in one second do not overwrite each other" bash -c 'ls "$0" | grep -c "^wpdb-import-report\." | grep -qx 1' "$d"
    printf 'a\n' > "$d/wpdb-import-report.txt"; report_rotate "$d" 5; printf 'b\n' > "$d/wpdb-import-report.txt"; report_rotate "$d" 5
    _chk "two reports rotated in the same second both stay"  bash -c 'ls "$0" | grep -c "^wpdb-import-report\.[0-9]" | grep -qx 3' "$d"
    d="$w/rot3"; mkdir -p "$d"; report_rotate "$d" 5
    _chk "no reports yet: nothing happens"                   bash -c 'test -z "$(ls -A "$0")"' "$d"
    _chk "an invalid keep keeps everything (never deletes by mistake)" bash -c 'd="$0/rot4"; mkdir -p "$d"; for n in 1 2 3; do echo x > "$d/wpdb-import-report.2026010$n-000000.txt"; done; report_rotate "$d" abc; ls "$d" | grep -c . | grep -qx 3' "$w"
    _finish "hosts and rotation are correct"
}

# ----------------------------------------------------------------
test_generate() {
    start_test "Report" "printed and saved (mode 600), off switch, unwritable folder, never fails the import"
    _p_load
    local errors=0 w="$_P_WORK" tmp d out rc file
    tmp=$(_p_logs)
    execute_wp_cli() {
        case "$2" in
            prod.example.com) printf 'Table\tColumn\tReplacements\tType\nwp_users\tuser_email\t1\tSQL\nwp_posts\tpost_content\t2\tSQL\nSuccess: 3 replacements to be made.\n' ;;
            *) printf 'Success: 0 replacements to be made.\n' ;;
        esac
    }
    d="$w/site"; mkdir -p "$d"
    WPDB_REPORT_STEPS=$'Database import|75\nSearch-replace|5\nCache flush|1\n'
    WPDB_IMPORT_NOTES="method: socket"
    out=$(import_report_generate "$d" prod.example.com target.test "single site" -- prod.example.com 2>&1 </dev/null); rc=$?; out=$(printf '%s' "$out" | _strip)
    file="$d/wpdb-import-report.txt"
    _chk "returns 0, and no 'could not save' warning"         bash -c 'test "$1" -eq 0 && ! grep -q "Could not save" <<< "$0"' "$out" "$rc"
    _chk "the report file exists, mode 600"                   bash -c 'test -f "$0" && test "$(stat -c %a "$0" 2>/dev/null || stat -f %Lp "$0")" = 600' "$file"
    _chk "the file is next to the config (not in a temp folder)" test "$(dirname "$file")" = "$d"
    _chk "the console shows the report and the path"          bash -c 'grep -q "Post-import report" <<< "$0" && grep -q "Report saved:.*wpdb-import-report.txt" <<< "$0"' "$out"
    _chk "header: tool version, site type, replacement"       bash -c 'grep -q "^Tool version: " "$0" && grep -q "^Site type:    single site" "$0" && grep -q "^Replacement:  prod.example.com -> target.test" "$0"' "$file"
    _chk "import notes are included"                          grep -q '^Import notes: method: socket' "$file"
    _chk "replacements per table, biggest first"              bash -c 'a=$(grep -n "wp_posts " "$0" | head -1 | cut -d: -f1); b=$(grep -n "wp_options " "$0" | head -1 | cut -d: -f1); test "$a" -lt "$b"' "$file"
    _chk "totals and the PHP / SQL split"                     bash -c 'grep -q "Total: 17 replacements in 3 tables" "$0" && grep -q "Serialized-aware (PHP) replacer: 7 replacements; plain SQL: 10" "$0"' "$file"
    _chk "the skipped table (no primary key) is named"        grep -q 'Skipped by WP-CLI (no primary key.*): wp_nopk' "$file"
    _chk "the warning of the log is listed"                   grep -q 'Warning: Skipping column x' "$file"
    _chk "the old domain still in the database, with tables"  bash -c 'grep -q "prod.example.com: 3 reference(s)" "$0" && grep -qE "wp_posts +2" "$0" && grep -qE "wp_users +1" "$0"' "$file"
    _chk "time per step is formatted mm:ss"                   bash -c 'grep -qE "Database import +01:15" "$0" && grep -qE "Search-replace +00:05" "$0"' "$file"
    _chk "no password or credential text in the report"       bash -c '! grep -qiE "password|DB_PASSWORD|MYSQL_PWD" "$0"' "$file"

    # rotation on the second run
    import_report_generate "$d" prod.example.com target.test "single site" -- prod.example.com >/dev/null 2>&1
    _chk "a second run keeps the first report under a dated name" bash -c 'ls "$0" | grep -c "^wpdb-import-report\.[0-9]" | grep -qx 1 && test -f "$0/wpdb-import-report.txt"' "$d"
    CONFIG_REPORT_KEEP=2
    import_report_generate "$d" prod.example.com target.test "single site" -- prod.example.com >/dev/null 2>&1
    import_report_generate "$d" prod.example.com target.test "single site" -- prod.example.com >/dev/null 2>&1
    _chk "report_keep=2: the latest and one older report"     bash -c 'ls "$0" | grep -c "^wpdb-import-report" | grep -qx 2' "$d"
    unset CONFIG_REPORT_KEEP

    # the console list is short; the file lists all tables
    local big="$w/big"; mkdir -p "$big"
    { printf 'Table\tColumn\tReplacements\tType\n'; for n in $(seq 1 15); do printf 'wp_t%02d\tc\t%d\tSQL\n' "$n" "$n"; done; } > "$tmp/replace_single.log"
    out=$(import_report_generate "$big" a.com b.test "single site" -- a.com 2>&1 </dev/null); out=$(printf '%s' "$out" | _strip)
    _chk "console: 10 tables and a note for the rest"        bash -c 'test "$(grep -cE "^ +wp_t[0-9]+ " <<< "$0")" = 10 && grep -q "and 5 more tables" <<< "$0"' "$out"
    _chk "file: all 15 tables"                                bash -c 'test "$(grep -cE "^ +wp_t[0-9]+ " "$0")" = 15' "$big/wpdb-import-report.txt"

    # no replacements, no leftovers, no steps
    rm -f "$tmp"/*.log; WPDB_REPORT_STEPS=""
    execute_wp_cli() { printf 'Success: 0 replacements to be made.\n'; }
    import_report_generate "$w/empty" a.com b.test "single site" -- a.com >/dev/null 2>&1
    mkdir -p "$w/empty2"; out=$(import_report_generate "$w/empty2" a.com b.test "single site" -- a.com 2>&1 </dev/null)
    _chk "nothing replaced: the report says so, and still works" bash -c 'grep -q "No replacements were reported" "$0/wpdb-import-report.txt" && grep -q "None found" "$0/wpdb-import-report.txt" && grep -q "Not recorded" "$0/wpdb-import-report.txt"' "$w/empty2"

    # off switch
    CONFIG_IMPORT_REPORT=false
    local off="$w/off"; mkdir -p "$off"; : > "$w/offcalls"
    execute_wp_cli() { echo called >> "$w/offcalls"; }
    out=$(import_report_generate "$off" a.com b.test "single site" -- a.com 2>&1 </dev/null); rc=$?
    _chk "import_report=false: no output, no file, no WP-CLI call" bash -c 'test "$1" -eq 0 && test -z "$0" && test -z "$(ls -A "$2")" && ! test -s "$3"' "$out" "$rc" "$off" "$w/offcalls"
    for out in FALSE no 0 off; do
        CONFIG_IMPORT_REPORT="$out"
        import_report_generate "$off" a.com b.test x -- a.com >/dev/null 2>&1
        _chk "import_report=$out also turns it off"           test -z "$(ls -A "$off")"
    done
    CONFIG_IMPORT_REPORT=true
    execute_wp_cli() { printf 'Success: 0 replacements to be made.\n'; }
    import_report_generate "$off" a.com b.test x -- a.com >/dev/null 2>&1
    _chk "import_report=true writes the report"               test -f "$off/wpdb-import-report.txt"
    unset CONFIG_IMPORT_REPORT

    # an unwritable or missing folder: a warning, never a failure
    out=$(import_report_generate "$w/does-not-exist" a.com b.test "single site" -- a.com 2>&1 </dev/null); rc=$?; out=$(printf '%s' "$out" | _strip)
    _chk "a missing folder: rc 0 and a warning"               bash -c 'test "$1" -eq 0 && grep -q "Could not save the report" <<< "$0"' "$out" "$rc"
    mkdir -p "$w/ro"; chmod 555 "$w/ro"
    if [[ ! -w "$w/ro" ]]; then
        out=$(import_report_generate "$w/ro" a.com b.test "single site" -- a.com 2>&1 </dev/null); rc=$?; out=$(printf '%s' "$out" | _strip)
        _chk "a read-only folder: rc 0, the report is still printed, a warning" bash -c 'test "$1" -eq 0 && grep -q "Post-import report" <<< "$0" && grep -q "Could not save the report" <<< "$0"' "$out" "$rc"
    else
        printf "  ℹ️  running as a user that can write anywhere: read-only folder check skipped\n"
    fi
    chmod 755 "$w/ro"

    # a failing WP-CLI must not fail anything
    execute_wp_cli() { return 1; }
    out=$(import_report_generate "$w/failwp" a.com b.test "single site" -- a.com 2>&1 </dev/null); rc=$?
    mkdir -p "$w/failwp2"; out=$(import_report_generate "$w/failwp2" a.com b.test "single site" -- a.com 2>&1 </dev/null); rc=$?
    _chk "WP-CLI failing in the leftover check: rc 0, the report is written" bash -c 'test "$1" -eq 0 && test -f "$0/wpdb-import-report.txt"' "$w/failwp2" "$rc"
    unset -f execute_wp_cli
    _finish "the report is complete and safe"
}

# ----------------------------------------------------------------
test_config() {
    start_test "Config" "upgrade, load, validate, show, new config, examples"
    _p_load
    source "$_P_ROOT/lib/config/integration.sh" >/dev/null 2>&1
    local errors=0 old="$_P_WORK/old.conf" run="$_P_WORK/run.conf" a out
    printf '%s\n' '[general]' 'sql_file=dump.sql' 'old_domain=prod.com' 'new_domain=local.test' '[site_mappings]' '1:prod.com:local.test' > "$old"
    cp "$old" "$run"
    ensure_socket_config_settings "$run" >/dev/null 2>&1
    _chk "the upgrade names both keys"                       bash -c '[[ "$0" == *"import_report, report_keep"* ]]' "$CONFIG_SETTINGS_MIGRATED_ITEMS"
    _chk "defaults: true and 5, each with its comment"       bash -c 'source "'"$_P_ROOT"'/lib/core/utils.sh" >/dev/null 2>&1; source "'"$_P_ROOT"'/lib/config/config_manager.sh" >/dev/null 2>&1; t=$(cat "$0"); grep -qx "import_report=true" "$0" && grep -qx "report_keep=5" "$0" && for k in import_report report_keep; do [[ -n "$(config_key_comment $k)" && "$t" == *"$(config_key_comment $k)"*"${k}="* ]] || exit 1; done' "$run"
    _chk "no line of the old file changed or was removed"    bash -c '! diff "$0" "$1" | grep -q "^<"' "$old" "$run"
    a=$(cksum < "$run"); ensure_socket_config_settings "$run" >/dev/null 2>&1
    _chk "a second run changes nothing"                      test "$a" = "$(cksum < "$run")"
    printf '%s\n' '[general]' 'sql_file=a.sql' 'import_report=false' 'report_keep=9' '' '[site_mappings]' > "$run"
    ensure_socket_config_settings "$run" >/dev/null 2>&1
    _chk "existing values are kept"                          bash -c 'grep -qx "import_report=false" "$0" && grep -qx "report_keep=9" "$0" && test "$(grep -c "^report_keep" "$0")" = 1' "$run"
    load_import_config "$run" >/dev/null 2>&1
    _chk "load_import_config reads false and 9"              test "$CONFIG_IMPORT_REPORT" = false -a "$CONFIG_REPORT_KEEP" = 9
    cp "$old" "$_P_WORK/nokeys.conf"; load_import_config "$_P_WORK/nokeys.conf" >/dev/null 2>&1
    _chk "a config without the keys loads true and 5"        test "$CONFIG_IMPORT_REPORT" = true -a "$CONFIG_REPORT_KEEP" = 5
    printf '%s\n' '[general]' 'sql_file=a.sql' 'import_report=' 'report_keep=' '[site_mappings]' > "$_P_WORK/empty.conf"
    load_import_config "$_P_WORK/empty.conf" >/dev/null 2>&1
    _chk "empty values load the defaults"                    test "$CONFIG_IMPORT_REPORT" = true -a "$CONFIG_REPORT_KEEP" = 5

    create_config_file "$_P_WORK/fresh.conf" a.sql a.com b.test >/dev/null 2>&1
    _chk "a new config has both keys and validates"          bash -c 'source "'"$_P_ROOT"'/lib/core/utils.sh" >/dev/null 2>&1; source "'"$_P_ROOT"'/lib/config/config_manager.sh" >/dev/null 2>&1; grep -qx "import_report=true" "$0" && grep -qx "report_keep=5" "$0" && validate_config_file "$0"' "$_P_WORK/fresh.conf"
    printf '%s\n' '[general]' 'sql_file=a.sql' 'old_domain=a.com' 'new_domain=b.test' 'import_report=maybe' 'report_keep=-1' '[site_mappings]' > "$run"
    out=$(validate_config_file "$run" 2>&1); a=$?
    _chk "validate: bad values fail with a message each"     bash -c 'test "$1" -ne 0 && grep -q "import_report: .maybe." <<< "$0" && grep -q "report_keep: .-1." <<< "$0"' "$out" "$a"
    printf '%s\n' '[general]' 'sql_file=a.sql' 'old_domain=a.com' 'new_domain=b.test' 'import_report=false' 'report_keep=0' '[site_mappings]' > "$run"
    _chk "validate: false and 0 pass"                        validate_config_file "$run"
    out=$(show_config "$run" 2>&1 | _strip)
    _chk "config-show prints the report settings"            grep -q 'Import Report: *false (keep 0)' <<< "$out"
    printf '%s\n' '[general]' 'sql_file=a.sql' '[site_mappings]' > "$run"
    out=$(show_config "$run" 2>&1 | _strip)
    _chk "config-show defaults: true (keep 5)"               grep -q 'Import Report: *true (keep 5)' <<< "$out"
    local f
    for f in single multisite; do
        _chk "example $f config has both keys"               bash -c 'grep -qx "import_report=true" "$0" && grep -qx "report_keep=5" "$0"' "$_P_ROOT/wpdb-import-example-$f.conf"
    done
    _finish "config handling is complete"
}

# ----------------------------------------------------------------
test_wiring() {
    start_test "Wiring" "the report is made after the replacement and the flush, only in a live run, and never stops the import"
    local errors=0 f="$_P_ROOT/import_wp_db.sh" a b c d
    a=$(grep -n 'decide_dry_run_mode "\$config_path"' "$f" | head -1 | cut -d: -f1)
    b=$(grep -n 'import_report_generate "\$report_dir"' "$f" | head -1 | cut -d: -f1)
    c=$(grep -n 'All transients deleted' "$f" | head -1 | cut -d: -f1)
    d=$(grep -n '🎉 All done' "$f" | head -1 | cut -d: -f1)
    _chk "the report comes after the cache flush and before 'All done'" test -n "$b" -a -n "$c" -a -n "$d" -a "$c" -lt "$b" -a "$b" -lt "$d"
    _chk "the dry run returns before the report can run"      bash -c 'r=$(grep -n "return \$dry_run_rc" "$0" | head -1 | cut -d: -f1); g=$(grep -n "import_report_generate" "$0" | head -1 | cut -d: -f1); test "$r" -lt "$g"' "$f"
    _chk "a failing report cannot fail the import (|| true)"  grep -q 'import_report_generate .* || true' "$f"
    _chk "the report is only called when the module is loaded" grep -q 'declare -F import_report_generate' "$f"
    _chk "the steps are timed: import, revisions, search-replace, flush" bash -c 'for s in "Database import" "Revision cleanup" "Search-replace" "Cache flush"; do grep -q "report_step_add \"$s\"" "$0" || exit 1; done' "$f"
    _chk "the module is loaded by the module loader"          grep -q 'import_report.sh' "$_P_ROOT/lib/module_loader.sh"
    _chk "the report logs are read before the temp folder is cleaned" bash -c 'g=$(grep -n "import_report_generate \"\$report_dir\"" "$0" | head -1 | cut -d: -f1); c=$(grep -n "^  cleanup$" "$0" | tail -1 | cut -d: -f1); test "$g" -lt "$c"' "$f"
    _finish "wiring is complete"
}

run_import_report_tests() {
    printf "\n${CYAN}${BOLD}🧪 Import Report Tests${RESET}\n"
    printf "%s\n\n" "$(printf '=%.0s' {1..50})"
    init_test_session "import_report"
    _P_WORK=$(mktemp -d "${TMPDIR:-/tmp}/wpdb-report-test.XXXXXX")
    trap 'chmod -R u+w "$_P_WORK" 2>/dev/null; rm -rf "$_P_WORK"; secure_tmpdir_cleanup 2>/dev/null' EXIT

    test_parser
    test_leftovers
    test_hosts_and_rotation
    test_generate
    test_config
    test_wiring

    finalize_test_session
    return $?
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    run_import_report_tests
fi
