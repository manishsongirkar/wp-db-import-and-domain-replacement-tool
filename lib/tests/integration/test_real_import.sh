#!/usr/bin/env bash

# ================================================================
# Real End-to-End Import Test (opt-in)
# ================================================================
#
# Description:
#   Runs the real tool (import_wp_db.sh) against real WordPress sites:
#     1. starts a throw-away MySQL (temp data dir, socket only, no network)
#     2. installs a "production" WordPress with WP-CLI, adds content (links, serialized data)
#        and exports a dump from it
#     3. installs a separate "target" WordPress and runs the tool with a config file
#     4. checks the database: tables, siteurl/home, replaced links in posts and serialized
#        options, no leftover old domain, the pre-import backup, cache flush, no temp files
#   Scenarios: single site (socket), use_socket=false (WP-CLI path), .gz dump, compatibility
#   retry (MariaDB collations), multisite subdirectory, multisite subdomain.
#
# Needs: a MySQL/MariaDB server binary (see lib/tests/server_helpers.sh), php with mysqli,
#   WP-CLI, and network access for `wp core download` (WP-CLI caches the download).
#   Skipped with a reason when something is missing. Your own databases are never touched:
#   MYSQL_* variables are cleared and the test talks only to its own server.
#
# Usage:
#   ./run_tests.sh real-import        (not part of "all": it starts a server and downloads WordPress)
#
# ================================================================

# Captured first: on Bash 3.2, BASH_SOURCE[0] changes after top-level `source` calls
_RI_SELF="${BASH_SOURCE[0]}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../test_framework.sh"
source "$PROJECT_ROOT_DIR/lib/core/utils.sh" >/dev/null 2>&1
source "$PROJECT_ROOT_DIR/lib/tests/server_helpers.sh"

_RI_ROOT="$PROJECT_ROOT_DIR"
_RI_DB_USER="wpuser"
_RI_DB_PASS="wppass123"
_RI_OUT=""
_RI_RC=0

_ri_strip() { sed 's/\x1b\[[0-9;]*[a-zA-Z]//g'; }

_chk() {
    local desc="$1"; shift
    if "$@" >/dev/null 2>&1; then
        printf "  ✅ %s\n" "$desc"
    else
        printf "  ❌ %s\n" "$desc"
        ((errors++))
    fi
}

_ri_q()  { "$SRV_CLIENT" --no-defaults -uroot --socket="$SRV_SOCKET" "$@"; }
_ri_wp() { local path="$1"; shift; wp --path="$path" "$@"; }

# Creates a WordPress site. Parameters: dir db url [subdirectory|subdomain]
_ri_install_site() {
    local dir="$1" db="$2" url="$3" multisite="${4:-}"
    cp -R "$SRV_WORK/core" "$dir" || return 1
    _ri_q -e "CREATE DATABASE IF NOT EXISTS \`$db\`" || return 1
    _ri_wp "$dir" config create --dbname="$db" --dbuser="$_RI_DB_USER" --dbpass="$_RI_DB_PASS" \
        --dbhost="localhost:$SRV_SOCKET" --skip-check --quiet >/dev/null 2>&1 || return 1
    if [[ -z "$multisite" ]]; then
        _ri_wp "$dir" core install --url="$url" --title="Site $db" --admin_user=admin \
            --admin_password=pw12345 --admin_email=a@example.com --skip-email >/dev/null 2>&1 || return 1
    else
        local flag=""
        [[ "$multisite" == "subdomain" ]] && flag="--subdomains"
        _ri_wp "$dir" core multisite-install --url="$url" --title="Network $db" --admin_user=admin \
            --admin_password=pw12345 --admin_email=a@example.com --skip-email $flag >/dev/null 2>&1 || return 1
    fi
}

# Adds content that contains the production domain in plain text and in serialized data
_ri_add_content() {
    local dir="$1" domain="$2" url_flag="${3:-}"
    _ri_wp "$dir" $url_flag post create --post_title="Prod Post" --post_status=publish \
        --post_content="<a href=\"https://$domain/x\">link</a> and //$domain/y" --porcelain >/dev/null 2>&1
    _ri_wp "$dir" $url_flag option update widget_probe "{\"url\":\"https://$domain\",\"list\":[\"https://$domain/a\"]}" --format=json >/dev/null 2>&1
}

# Writes wpdb-import.conf. Parameters: dir sql_file old_domain new_domain use_socket [extra lines]
_ri_write_config() {
    local dir="$1" sql="$2" old="$3" new="$4" sock="$5" extra="${6:-}"
    cat > "$dir/wpdb-import.conf" <<EOF
[general]
sql_file=$sql
old_domain=$old
new_domain=$new
all_tables=true
dry_run=false
clear_revisions=false
setup_stage_proxy=false
auto_proceed=true
use_socket=$sock
import_optimizations=auto
backup_before_import=true
backup_dir=$SRV_WORK/backups
backup_keep=5
[site_mappings]
$extra
EOF
}

# Runs the tool in a site directory (stdin closed, own temp dir). Sets _RI_OUT and _RI_RC.
_ri_run_tool() {
    local dir="$1" f; shift
    f=$(mktemp "$SRV_WORK/out.XXXXXX")
    mkdir -p "$SRV_WORK/tmp"
    ( cd "$dir" && TMPDIR="$SRV_WORK/tmp" bash "$_RI_ROOT/import_wp_db.sh" "$@" < /dev/null > "$f" 2>&1 )
    _RI_RC=$?
    _RI_OUT=$(_ri_strip < "$f" | tr '\r' '\n')
    rm -f "$f"
    # WPDB_TEST_DEBUG=1 prints the tool's output (without the spinner lines) for every run
    if [[ -n "${WPDB_TEST_DEBUG:-}" ]]; then
        printf "%s\n" "$_RI_OUT" | grep -vE '^\s*$|Importing [|/\\-]|^\s+Importing' | sed 's/^/     | /'
    fi
}

# The console must not show shell or PHP errors: invalid options, missing commands, notices...
_ri_console_clean() {
    ! grep -qiE 'invalid option|command not found|syntax error|unbound variable|unexpected (token|EOF)|bad substitution|No such file or directory|Permission denied|illegal (option|byte)|Traceback|PHP (Warning|Notice|Deprecated|Fatal)|^(Warning|Notice|Deprecated|Fatal error):' <<< "$_RI_OUT"
}

# Multisite scenario. Parameters: label mode(subdirectory|subdomain)
_ri_multisite_scenario() {
    local label="$1" mode="$2"
    local prod="$SRV_WORK/prod_$mode" tgt="$SRV_WORK/t_$mode"
    local old_site2 new_site2 url2_old url2_new new_domain="target.test" old_domain="prod.example.com"
    if [[ "$mode" == "subdirectory" ]]; then
        old_site2="$old_domain/news";  new_site2="$new_domain/news"
        url2_old="https://$old_domain/news/"; url2_new="https://$new_domain/news/"
    else
        old_site2="news.$old_domain";  new_site2="news.$new_domain"
        # WP-CLI creates a subdomain subsite with http://, and the tool keeps the scheme
        url2_old="http://news.$old_domain/"; url2_new="http://news.$new_domain/"
    fi

    printf "\n  -- %s\n" "$label"
    _ri_install_site "$prod" "prod_$mode" "https://$old_domain" "$mode" || { printf "  ❌ production network install failed\n"; ((errors++)); return; }
    _ri_wp "$prod" site create --slug=news --title=News >/dev/null 2>&1 || { printf "  ❌ could not create the second site\n"; ((errors++)); return; }
    _ri_add_content "$prod" "$old_domain"
    _ri_add_content "$prod" "$old_site2" "--url=$url2_old"
    _ri_wp "$prod" db export "$SRV_WORK/prod_$mode.sql" --add-drop-table >/dev/null 2>&1 || { printf "  ❌ dump export failed\n"; ((errors++)); return; }

    _ri_install_site "$tgt" "target_$mode" "http://$new_domain" "$mode" || { printf "  ❌ target network install failed\n"; ((errors++)); return; }
    _ri_write_config "$tgt" "$SRV_WORK/prod_$mode.sql" "$old_domain" "$new_domain" auto "1:$old_domain:$new_domain
2:$old_site2:$new_site2"
    _ri_run_tool "$tgt"

    _chk "exit code 0"                                   test "$_RI_RC" -eq 0
    _chk "multisite was detected"                        grep -qiE 'multisite' <<< "$_RI_OUT"
    _chk "import reported successful"                    grep -q 'Database import successful' <<< "$_RI_OUT"
    _chk "wp_blogs and wp_site were updated"             grep -q 'Database tables wp_blogs & wp_site updated successfully' <<< "$_RI_OUT"
    _chk "search-replace ran for the subsite"            grep -q 'Site 2 Processing' <<< "$_RI_OUT"
    _chk "search-replace ran for the main site"          grep -q 'Main Site Processing' <<< "$_RI_OUT"
    _chk "object cache flushed"                          grep -q 'Object cache flushed' <<< "$_RI_OUT"
    _chk "rewrite rules flushed on every site (no 'Failed to flush')" bash -c "grep -q 'Rewrite rule flushed' <<< '$_RI_OUT' && ! grep -q 'Failed to flush rewrite rule' <<< '$_RI_OUT'"
    _chk "console shows no shell/PHP errors"             _ri_console_clean
    _chk "the old domain was detected in the multisite database (no 'Could not detect domain')" bash -c "grep -q 'Detected domain in database: $old_domain' <<< '$_RI_OUT' && ! grep -q 'Could not detect domain from database' <<< '$_RI_OUT'"
    _chk "no 'WP-CLI not responding' degradation warning" bash -c "! grep -q 'WP-CLI not responding' <<< '$_RI_OUT'"
    _chk "main site URL is https://$new_domain/"         test "$(_ri_wp "$tgt" site list --field=url --blog_id=1 2>/dev/null | head -1)" = "https://$new_domain/"
    _chk "subsite URL is $url2_new"                      test "$(_ri_wp "$tgt" site list --field=url --blog_id=2 2>/dev/null | head -1)" = "$url2_new"
    [[ -n "${WPDB_TEST_DEBUG:-}" ]] && _ri_wp "$tgt" site list --fields=blog_id,domain,path,url 2>&1 | sed 's/^/     sites| /'
    _chk "main site post link replaced"                  bash -c "cd '$tgt' && wp post list --post_type=post --field=post_content 2>/dev/null | grep -qF 'https://$new_domain/x'"
    _chk "subsite post link replaced"                    bash -c "cd '$tgt' && wp --url='$url2_new' post list --post_type=post --field=post_content 2>/dev/null | grep -qF '${url2_new}x' || wp --url='$url2_new' post list --post_type=post --field=post_content 2>/dev/null | grep -qF '$new_site2/x'"
    _chk "serialized option replaced on the main site"   bash -c "cd '$tgt' && test \"\$(wp eval 'echo get_option(\"widget_probe\")[\"list\"][0];' 2>/dev/null)\" = 'https://$new_domain/a'"
    _chk "no occurrence of the old domain is left (all tables of both sites)" bash -c "cd '$tgt' && test \"\$(wp db query \"SELECT (SELECT COUNT(*) FROM wp_posts WHERE post_content LIKE '%$old_domain%') + (SELECT COUNT(*) FROM wp_2_posts WHERE post_content LIKE '%$old_domain%') + (SELECT COUNT(*) FROM wp_options WHERE option_value LIKE '%$old_domain%') + (SELECT COUNT(*) FROM wp_2_options WHERE option_value LIKE '%$old_domain%') + (SELECT COUNT(*) FROM wp_blogs WHERE domain LIKE '%$old_domain%') + (SELECT COUNT(*) FROM wp_site WHERE domain LIKE '%$old_domain%')\" --skip-column-names 2>/dev/null)\" = 0"
    _chk "no temp directory left behind"                 test -z "$(ls -A "$SRV_WORK/tmp" 2>/dev/null)"
}


# Everything that identifies the state of a database: table list, per-table checksums, and the list of
# databases on the server (a leftover scratch database would show up here)
_ri_state() {
    local db="$1" t
    _ri_q -N -e "SHOW DATABASES"
    while IFS= read -r t; do
        [[ -n "$t" ]] && _ri_q -N -e "CHECKSUM TABLE \`$db\`.\`$t\`"
    done < <(_ri_q -N -e "SELECT table_name FROM information_schema.tables WHERE table_schema = '$db' ORDER BY table_name")
}
_ri_fingerprint() {
    _ri_state "$1" | { md5sum 2>/dev/null || md5; } | awk '{print $1}'
}
# Prints which tables (or databases) differ between two saved states
_ri_state_diff() { diff <(printf '%s\n' "$1") <(printf '%s\n' "$2") | grep '^[<>]' | head -6 | sed 's/^/     differs: /'; }

_ri_no_scratch_db() { ! _ri_q -N -e 'SHOW DATABASES' | grep -q 'wpdb_dry_'; }

# Exact row count of every table of a database
_ri_row_total() {
    local db="$1" t total=0 n
    while IFS= read -r t; do
        [[ -n "$t" ]] || continue
        n=$(_ri_q -N -e "SELECT COUNT(*) FROM \`$db\`.\`$t\`")
        total=$((total + n))
    done < <(_ri_q -N -e "SELECT table_name FROM information_schema.tables WHERE table_schema = '$db' AND table_type = 'BASE TABLE'")
    printf "%s" "$total"
}

# Dry-run scenario. Parameters: label dump old_domain site_dir db flag(--dry-run|config) [expected_filter yes|no|skip]
_ri_dry_run_scenario() {
    local label="$1" dump="$2" old="$3" dir="$4" db="$5" how="$6" filter="${7:-no}" extra_map="${8:-}"
    printf "\n  -- %s\n" "$label"
    local before after backups_before dbs_before
    local state_before; state_before=$(_ri_state "$db")
    before=$(_ri_fingerprint "$db")
    backups_before=$(ls "$SRV_WORK/backups" 2>/dev/null | wc -l | tr -d ' ')
    if [[ "$how" == "config" ]]; then
        _ri_write_config "$dir" "$dump" "$old" target.test auto "$extra_map"
        sed -i.bak 's/^dry_run=false/dry_run=true/' "$dir/wpdb-import.conf" && rm -f "$dir/wpdb-import.conf.bak"
        _ri_run_tool "$dir"
    else
        _ri_write_config "$dir" "$dump" "$old" target.test auto "$extra_map"
        _ri_run_tool "$dir" --dry-run
    fi
    after=$(_ri_fingerprint "$db")
    [[ "$before" != "$after" ]] && _ri_state_diff "$state_before" "$(_ri_state "$db")"

    local expect_tables expect_occ
    expect_tables=$(grep -c '^CREATE TABLE' "$dump")
    expect_occ=$(grep -o -F "$old" "$dump" | wc -l | tr -d ' ')

    _chk "exit code 0"                                    test "$_RI_RC" -eq 0
    _chk "says the database was not changed"              grep -q 'Your database was not changed' <<< "$_RI_OUT"
    _chk "console shows no shell/PHP errors"              _ri_console_clean
    _chk "REAL DATABASE UNCHANGED (all table checksums + database list)" test "$before" = "$after"
    _chk "no scratch database is left on the server"      _ri_no_scratch_db
    _chk "no backup was made (nothing is replaced)"       test "$(ls "$SRV_WORK/backups" 2>/dev/null | wc -l | tr -d ' ')" = "$backups_before"
    _chk "nothing was imported (no import step ran)"      bash -c "! grep -q 'Database import successful' <<< \"\$(cat <<'EOT'
$_RI_OUT
EOT
)\""
    _chk "reports $expect_tables tables"                  bash -c "grep -qE 'Would import: +$expect_tables tables /' <<< \"\$(cat <<'EOT'
$_RI_OUT
EOT
)\""
    if [[ "$how" != "multisite" ]]; then
        local expect_rows
        expect_rows=$(_ri_row_total "$_RI_SRC_DB")
        [[ -n "$expect_rows" ]] && _chk "reports the exact row count ($expect_rows)" bash -c "grep -qE 'tables / $expect_rows rows' <<< \"\$(cat <<'EOT'
$_RI_OUT
EOT
)\""
    fi
    _chk "reports $expect_occ occurrences of $old (matches grep on the dump)" bash -c "grep -qE 'Would replace: +$expect_occ occurrences' <<< \"\$(cat <<'EOT'
$_RI_OUT
EOT
)\""
    if [[ "$filter" == "yes" ]]; then
        _chk "reports that the compatibility filter is needed" bash -c "grep -qE 'Compatibility filter: +yes' <<< \"\$(cat <<'EOT'
$_RI_OUT
EOT
)\""
    elif [[ "$filter" == "no" ]]; then
        _chk "reports that no compatibility filter is needed"  bash -c "grep -qE 'Compatibility filter: +no' <<< \"\$(cat <<'EOT'
$_RI_OUT
EOT
)\""
    fi
    _chk "no temp directory left behind"                  test -z "$(ls -A "$SRV_WORK/tmp" 2>/dev/null)"
}

# ================================================================
# Setup
# ================================================================
_ri_setup() {
    local cand label chosen=""
    command -v php >/dev/null 2>&1 || { _RI_SKIP="php not found"; return 1; }
    php -r 'exit(extension_loaded("mysqli") ? 0 : 1);' 2>/dev/null || { _RI_SKIP="php has no mysqli extension"; return 1; }
    command -v wp >/dev/null 2>&1 || { _RI_SKIP="WP-CLI (wp) not found"; return 1; }

    SRV_WORK=$(mktemp -d "${TMPDIR:-/tmp}/wpdb-real.XXXXXX") || { _RI_SKIP="cannot create a temp directory"; return 1; }
    # Never let the test reach a real database through the user's environment
    unset MYSQL_HOME MYSQL_UNIX_PORT MYSQL_TCP_PORT MYSQL_PWD MYSQL_HOST MYSQL_GROUP_SUFFIX

    # Prefer MySQL 8.x; otherwise the first server found
    local best_ver="" ver
    while IFS= read -r cand; do
        [[ -z "$cand" ]] && continue
        label=$(srv_label "$cand")
        if [[ "$label" == "MySQL 8."* ]]; then
            ver="${label#MySQL }"
            # newest MySQL 8.x wins (version-sorted)
            if [[ -z "$best_ver" || "$(printf '%s\n%s\n' "$best_ver" "$ver" | sort -t. -k1,1n -k2,2n -k3,3n | tail -1)" == "$ver" ]]; then
                best_ver="$ver"; chosen="$cand"
            fi
        elif [[ -z "$chosen" ]]; then
            chosen="$cand"
        fi
    done < <(srv_find_servers)
    [[ -n "${WPDB_TEST_SERVER_BIN:-}" ]] && chosen="$WPDB_TEST_SERVER_BIN"
    [[ -n "$chosen" ]] || { _RI_SKIP="no MySQL/MariaDB server binary found (set WPDB_TEST_SERVER_BIN)"; return 1; }
    _RI_SERVER_LABEL=$(srv_label "$chosen")
    srv_start "$chosen" 1 || { _RI_SKIP="could not start $_RI_SERVER_LABEL"; return 1; }

    _ri_q -e "CREATE USER '$_RI_DB_USER'@'localhost' IDENTIFIED BY '$_RI_DB_PASS'; GRANT ALL ON *.* TO '$_RI_DB_USER'@'localhost'" \
        || { _RI_SKIP="could not create the test database user"; return 1; }

    if ! wp core download --path="$SRV_WORK/core" --quiet >/dev/null 2>&1; then
        _RI_SKIP="wp core download failed (no network and no WP-CLI cache?)"
        return 1
    fi
    return 0
}

# Production site + dump used by the single-site scenarios
_ri_make_prod() {
    _ri_install_site "$SRV_WORK/prod" prod "https://prod.example.com" || return 1
    _ri_add_content "$SRV_WORK/prod" "prod.example.com"
    _ri_wp "$SRV_WORK/prod" db export "$SRV_WORK/prod.sql" --add-drop-table >/dev/null 2>&1 || return 1
    [[ -s "$SRV_WORK/prod.sql" ]]
}

# Common assertions after a successful single-site import into $1 (site dir)
_ri_assert_replaced() {
    local dir="$1" new="$2" old="prod.example.com"
    _chk "siteurl is https://$new"                 test "$(_ri_wp "$dir" option get siteurl 2>/dev/null)" = "https://$new"
    _chk "home is https://$new"                    test "$(_ri_wp "$dir" option get home 2>/dev/null)" = "https://$new"
    _chk "post link replaced (https)"              bash -c "cd '$dir' && wp post list --post_type=post --field=post_content 2>/dev/null | grep -qF 'https://$new/x'"
    _chk "protocol-relative link replaced"         bash -c "cd '$dir' && wp post list --post_type=post --field=post_content 2>/dev/null | grep -qF '//$new/y'"
    _chk "serialized option replaced (and still valid)" bash -c "cd '$dir' && test \"\$(wp eval 'echo get_option(\"widget_probe\")[\"list\"][0];' 2>/dev/null)\" = 'https://$new/a'"
    _chk "no occurrence of the old domain is left" bash -c "cd '$dir' && test \"\$(wp db query \"SELECT (SELECT COUNT(*) FROM wp_posts WHERE post_content LIKE '%$old%') + (SELECT COUNT(*) FROM wp_options WHERE option_value LIKE '%$old%')\" --skip-column-names 2>/dev/null)\" = 0"
    _chk "the site still loads WordPress"          bash -c "cd '$dir' && wp core is-installed"
}

test_real_import() {
    start_test "Real Import" "real WordPress sites imported by the real tool on a real server"

    if ! _ri_setup; then
        srv_cleanup
        skip_test "$_RI_SKIP"
        return 0
    fi
    printf "  ℹ️  Server: %s   WP-CLI: %s   PHP: %s\n" "$_RI_SERVER_LABEL" "$(wp --version 2>/dev/null | tail -1)" "$(php -r 'echo PHP_VERSION;')"

    local errors=0
    if ! _ri_make_prod; then
        printf "  ❌ could not build the production site and its dump\n"
        srv_cleanup
        fail_test "setup failed"
        return 1
    fi
    printf "  ✅ production site installed, dump exported (%s KB)\n" "$(( $(wc -c < "$SRV_WORK/prod.sql") / 1024 ))"

    # ---------------- Scenario 1: single site, socket import
    printf "\n  -- Scenario 1: single site, socket import\n"
    _ri_install_site "$SRV_WORK/t1" target1 "http://target.test" || { printf "  ❌ target site install failed\n"; ((errors++)); }
    _ri_wp "$SRV_WORK/t1" post create --post_title="Target Original" --post_status=publish --post_content="original target content" >/dev/null 2>&1
    _ri_write_config "$SRV_WORK/t1" "$SRV_WORK/prod.sql" prod.example.com target.test auto
    _ri_run_tool "$SRV_WORK/t1"
    _chk "exit code 0"                              test "$_RI_RC" -eq 0
    _chk "console shows no shell/PHP errors"        _ri_console_clean
    _chk "the old domain was detected in the database" grep -q 'Detected domain in database: prod.example.com' <<< "$_RI_OUT"
    _chk "imported through the socket"              grep -q 'mysql via Unix socket' <<< "$_RI_OUT"
    _chk "import reported successful"               grep -q 'Database import successful' <<< "$_RI_OUT"
    _chk "search-replace reported successful"       grep -q 'Search-replace completed successfully' <<< "$_RI_OUT"
    _chk "object cache flushed"                     grep -q 'Object cache flushed' <<< "$_RI_OUT"
    _chk "rewrite rules flushed"                    grep -q 'Rewrite rule flushed' <<< "$_RI_OUT"
    _chk "transients deleted"                       grep -q 'All transients deleted' <<< "$_RI_OUT"
    _chk "pre-import backup was made"               grep -q 'Backup saved' <<< "$_RI_OUT"
    local bk
    bk=$(ls "$SRV_WORK"/backups/*.sql.gz 2>/dev/null | head -1)
    _chk "backup file exists and is valid gzip"     bash -c "test -n '$bk' && gzip -t '$bk'"
    _chk "backup holds the target's ORIGINAL data"  bash -c "gunzip -c '$bk' | grep -q 'Target Original'"
    _chk "backup file mode is 600"                  test "$(stat -c %a "$bk" 2>/dev/null || stat -f %Lp "$bk")" = "600"
    _ri_assert_replaced "$SRV_WORK/t1" "target.test"
    _chk "old target content is gone (replaced by the dump)" bash -c "cd '$SRV_WORK/t1' && ! wp post list --field=post_title 2>/dev/null | grep -q 'Target Original'"
    _chk "no temp directory left behind"            test -z "$(ls -A "$SRV_WORK/tmp" 2>/dev/null)"
    _chk "no wpdb-import.conf side effects other than the config" test -f "$SRV_WORK/t1/wpdb-import.conf"

    # ---------------- Scenario 2: WP-CLI path (use_socket=false)
    printf "\n  -- Scenario 2: WP-CLI import path (use_socket=false)\n"
    _ri_install_site "$SRV_WORK/t2" target2 "http://target.test" || { printf "  ❌ target site install failed\n"; ((errors++)); }
    _ri_write_config "$SRV_WORK/t2" "$SRV_WORK/prod.sql" prod.example.com target.test false
    _ri_run_tool "$SRV_WORK/t2"
    _chk "exit code 0"                              test "$_RI_RC" -eq 0
    _chk "console shows no shell/PHP errors"        _ri_console_clean
    _chk "imported through WP-CLI"                  grep -q 'Import method: WP-CLI' <<< "$_RI_OUT"
    _chk "import reported successful"               grep -q 'Database import successful' <<< "$_RI_OUT"
    _ri_assert_replaced "$SRV_WORK/t2" "target.test"

    # ---------------- Scenario 3: compressed dump
    printf "\n  -- Scenario 3: .sql.gz dump\n"
    gzip -c "$SRV_WORK/prod.sql" > "$SRV_WORK/prod.sql.gz"
    _ri_install_site "$SRV_WORK/t3" target3 "http://target.test" || { printf "  ❌ target site install failed\n"; ((errors++)); }
    _ri_write_config "$SRV_WORK/t3" "$SRV_WORK/prod.sql.gz" prod.example.com target.test auto
    _ri_run_tool "$SRV_WORK/t3"
    _chk "exit code 0"                              test "$_RI_RC" -eq 0
    _chk "console shows no shell/PHP errors"        _ri_console_clean
    _chk "dump recognized as compressed"            grep -q 'Compressed dump (gzip)' <<< "$_RI_OUT"
    _ri_assert_replaced "$SRV_WORK/t3" "target.test"

    # ---------------- Scenario 4: compatibility retry
    printf "\n  -- Scenario 4: MariaDB collations -> compatibility retry\n"
    LC_ALL=C sed -E 's/(COLLATE[= ])utf8mb4_[a-z0-9_]+/\1utf8mb4_uca1400_ai_ci/g' "$SRV_WORK/prod.sql" > "$SRV_WORK/prod_mariadb.sql"
    _chk "variant dump really uses a MariaDB-only collation" grep -q 'utf8mb4_uca1400_ai_ci' "$SRV_WORK/prod_mariadb.sql"
    _ri_install_site "$SRV_WORK/t4" target4 "http://target.test" || { printf "  ❌ target site install failed\n"; ((errors++)); }
    _ri_write_config "$SRV_WORK/t4" "$SRV_WORK/prod_mariadb.sql" prod.example.com target.test auto
    _ri_run_tool "$SRV_WORK/t4"
    if [[ "$_RI_SERVER_LABEL" == MariaDB* ]]; then
        printf "  ℹ️  server is MariaDB: uca1400 may be accepted, retry not required\n"
    else
        _chk "the tool retried with the compatibility filter" grep -q 'retrying with the compatibility filter' <<< "$_RI_OUT"
        _chk "filter use is reported after the import"        grep -q 'Imported with the SQL compatibility filter' <<< "$_RI_OUT"
    fi
    _chk "exit code 0"                              test "$_RI_RC" -eq 0
    _ri_assert_replaced "$SRV_WORK/t4" "target.test"


    _ri_multisite_scenario "Scenario 5: multisite, subdirectory network (2 sites)" subdirectory
    _ri_multisite_scenario "Scenario 6: multisite, subdomain network (2 sites)" subdomain
    # ---------------- Scenario 7: dry run (real database must stay untouched)
    _ri_install_site "$SRV_WORK/t7" target7 "http://target.test" || { printf "  ❌ target site install failed\n"; ((errors++)); }
    _ri_wp "$SRV_WORK/t7" post create --post_title="Target Original" --post_status=publish --post_content="keep me" >/dev/null 2>&1
    _RI_SRC_DB=prod
    _ri_dry_run_scenario "Scenario 7a: --dry-run on a single site" "$SRV_WORK/prod.sql" prod.example.com "$SRV_WORK/t7" target7 --dry-run no
    _chk "target content is still the original"            bash -c "cd '$SRV_WORK/t7' && wp post list --field=post_title 2>/dev/null | grep -q 'Target Original' && test \"\$(wp option get siteurl 2>/dev/null)\" = 'http://target.test'"
    _ri_dry_run_scenario "Scenario 7b: dry_run=true in the config (no flag)" "$SRV_WORK/prod.sql" prod.example.com "$SRV_WORK/t7" target7 config no
    LC_ALL=C sed -E 's/(COLLATE[= ])utf8mb4_[a-z0-9_]+/\1utf8mb4_uca1400_ai_ci/g' "$SRV_WORK/prod.sql" > "$SRV_WORK/prod_mariadb7.sql"
    if [[ "$_RI_SERVER_LABEL" == MariaDB* ]]; then
        _ri_dry_run_scenario "Scenario 7c: MariaDB collations" "$SRV_WORK/prod_mariadb7.sql" prod.example.com "$SRV_WORK/t7" target7 --dry-run skip
    else
        _ri_dry_run_scenario "Scenario 7c: MariaDB collations -> compatibility filter reported" "$SRV_WORK/prod_mariadb7.sql" prod.example.com "$SRV_WORK/t7" target7 --dry-run yes
    fi
    # a dump made with --databases must not be able to reach another database
    { printf 'CREATE DATABASE /*!32312 IF NOT EXISTS*/ `target7` /*!40100 DEFAULT CHARACTER SET utf8mb4 */;\nUSE `target7`;\nDROP DATABASE IF EXISTS `target7`;\n'; cat "$SRV_WORK/prod.sql"; } > "$SRV_WORK/prod_dbstmts.sql"
    _ri_dry_run_scenario "Scenario 7d: dump with CREATE/USE/DROP DATABASE (must not touch the real database)" "$SRV_WORK/prod_dbstmts.sql" prod.example.com "$SRV_WORK/t7" target7 --dry-run no
    _chk "the real database still has its tables"          test "$(_ri_q -N -e "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='target7'")" -gt 5

    # a database user that may not create databases: a clear message, nothing changed
    _ri_q -e "CREATE USER 'limuser'@'localhost' IDENTIFIED BY 'limpass123'; GRANT ALL ON \`target7b\`.* TO 'limuser'@'localhost'" >/dev/null 2>&1
    local save_user="$_RI_DB_USER" save_pass="$_RI_DB_PASS"
    _RI_DB_USER=limuser; _RI_DB_PASS=limpass123
    _ri_install_site "$SRV_WORK/t7b" target7b "http://target.test" || { printf "  ❌ limited-user site install failed\n"; ((errors++)); }
    _RI_DB_USER="$save_user"; _RI_DB_PASS="$save_pass"
    printf "\n  -- Scenario 7e: database user without CREATE DATABASE privilege\n"
    # warm up WordPress once: its first load after the installation may write options by itself
    _ri_wp "$SRV_WORK/t7b" option get home >/dev/null 2>&1; _ri_wp "$SRV_WORK/t7b" cron event list >/dev/null 2>&1
    local before7b state7b; state7b=$(_ri_state target7b); before7b=$(_ri_fingerprint target7b)
    _ri_write_config "$SRV_WORK/t7b" "$SRV_WORK/prod.sql" prod.example.com target.test auto
    _ri_run_tool "$SRV_WORK/t7b" --dry-run
    _chk "exit code is 1 (the preview could not run)"      test "$_RI_RC" -eq 1
    _chk "explains the missing CREATE DATABASE permission" grep -q 'needs permission to create a temporary database' <<< "$_RI_OUT"
    _chk "shows the server's error"                        grep -qi 'denied' <<< "$_RI_OUT"
    _chk "suggests the GRANT"                              grep -q 'GRANT CREATE' <<< "$_RI_OUT"
    _chk "says nothing was changed"                        grep -q 'Nothing was changed' <<< "$_RI_OUT"
    _chk "the database is unchanged"                       test "$before7b" = "$(_ri_fingerprint target7b)"
    [[ "$before7b" != "$(_ri_fingerprint target7b)" ]] && _ri_state_diff "$state7b" "$(_ri_state target7b)"
    _chk "console shows no shell/PHP errors"               _ri_console_clean

    # multisite dry run on the network imported in scenario 5 (its dump and a target network)
    printf "\n  -- Scenario 7f: multisite dry run (main site and subsite mapping)\n"
    local msdb=target_subdirectory msdump="$SRV_WORK/prod_subdirectory.sql" msbefore
    msbefore=$(_ri_fingerprint "$msdb")
    _ri_write_config "$SRV_WORK/t_subdirectory" "$msdump" prod.example.com target.test auto "1:prod.example.com:target.test
2:prod.example.com/news:target.test/news"
    _ri_run_tool "$SRV_WORK/t_subdirectory" --dry-run
    _chk "exit code 0"                                     test "$_RI_RC" -eq 0
    _chk "REAL DATABASE UNCHANGED (all table checksums + database list)" test "$msbefore" = "$(_ri_fingerprint "$msdb")"
    _chk "the subsite mapping is listed first (longest domain)" bash -c "test \$(grep -n 'prod.example.com/news →' <<< \"\$(cat <<'EOT'
$_RI_OUT
EOT
)\" | head -1 | cut -d: -f1) -lt \$(grep -n '^ *prod.example.com →' <<< \"\$(cat <<'EOT'
$_RI_OUT
EOT
)\" | head -1 | cut -d: -f1)"
    _chk "subsite occurrences match grep on the dump ($(grep -o -F 'prod.example.com/news' "$msdump" | wc -l | tr -d ' '))" bash -c "grep -A1 'prod.example.com/news →' <<< \"\$(cat <<'EOT'
$_RI_OUT
EOT
)\" | grep -qE 'Would replace: +$(grep -o -F 'prod.example.com/news' "$msdump" | wc -l | tr -d ' ') occurrences'"
    _chk "main domain occurrences match grep on the dump ($(grep -o -F 'prod.example.com' "$msdump" | wc -l | tr -d ' '))" bash -c "grep -A1 '^ *prod.example.com →' <<< \"\$(cat <<'EOT'
$_RI_OUT
EOT
)\" | grep -qE 'Would replace: +$(grep -o -F 'prod.example.com' "$msdump" | wc -l | tr -d ' ') occurrences'"
    _chk "console shows no shell/PHP errors"               _ri_console_clean

    srv_cleanup
    if [[ "$errors" -eq 0 ]]; then
        pass_test "the real tool imported real sites correctly on $_RI_SERVER_LABEL"
    else
        fail_test "$errors check(s) failed"
    fi
}

run_real_import_tests() {
    printf "\n${CYAN}${BOLD}🌐 Real End-to-End Import${RESET}\n"
    printf "%s\n" "$(printf '=%.0s' {1..50})"
    init_test_session "real_import"
    trap 'srv_cleanup' EXIT
    test_real_import
    srv_cleanup
    finalize_test_session
    return $?
}

if [[ "$_RI_SELF" == "${0}" ]]; then
    run_real_import_tests
fi
