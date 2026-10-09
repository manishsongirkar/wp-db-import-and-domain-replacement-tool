#!/usr/bin/env bash

# ================================================================
# Doctor: environment check
# ================================================================
#
# Description:
#   `wp-db-import doctor` checks the tools and the database connection BEFORE an import
#   and prints one row per item: status, name, detail and (when not OK) how to fix it.
#
# Status:
#   OK    works
#   WARN  a feature will not work (for example no unzip: .zip dumps), the import still can
#   FAIL  required: the tool cannot import. The exit code is 1 when any item fails.
#
# Safety:
#   - never prints passwords (they are passed to the client in MYSQL_PWD, never shown)
#   - never writes to the config file or the site; the only server write is a scratch
#     database `wpdb_doctor_<pid>` that is created and dropped at once (same permission
#     the dry run needs)
#   - works outside a WordPress directory: only the tool checks run then
#
# ================================================================

_DOC_OK=0
_DOC_WARN=0
_DOC_FAIL=0

# _doc_row STATUS NAME DETAIL [FIX]
_doc_row() {
    local status="$1" name="$2" detail="$3" fix="${4:-}" color
    case "$status" in
        OK)   color="$GREEN";  _DOC_OK=$((_DOC_OK + 1)) ;;
        WARN) color="$YELLOW"; _DOC_WARN=$((_DOC_WARN + 1)) ;;
        *)    color="$RED";    _DOC_FAIL=$((_DOC_FAIL + 1)) ;;
    esac
    printf -- "  ${color}%-5s${RESET} %-22s %s\n" "$status" "$name" "$detail"
    [[ -n "$fix" ]] && printf -- "        ${CYAN}fix:${RESET} %s\n" "$fix"
    return 0
}

# _doc_tool NAME COMMAND... WARN-FIX : optional tool, warns when missing
_doc_optional_tool() {
    local name="$1" needed_for="$2"; shift 2
    local c found=""
    for c in "$@"; do command -v "$c" >/dev/null 2>&1 && { found="$c"; break; }; done
    if [[ -n "$found" ]]; then
        _doc_row OK "$name" "$found"
    else
        _doc_row WARN "$name" "not found" "install $* (needed for $needed_for)"
    fi
    return 0
}

# Server query with the same connection the import uses. Prints the result; returns the client status.
# Uses globals set by doctor_site_checks: _DOC_BIN _DOC_SOCKET and WP_DB_*.
_doc_query() {
    local sql="$1" db="${2:-}"
    _build_mysql_args "$_DOC_SOCKET" "${WP_DB_HOST:-}" "$WP_DB_USER" "$db" 10
    MYSQL_PWD="${WP_DB_PASSWORD:-}" "$_DOC_BIN" "${_WPDB_MYSQL_ARGS[@]}" -N -B -e "$sql" 2>&1
}

doctor_tool_checks() {
    printf "\n${BOLD}Tools${RESET}\n"
    _doc_row OK "Bash" "${BASH_VERSION}"
    _doc_optional_tool "git" "wp-db-import update" git
    _doc_optional_tool "curl or wget" "downloading Stage File Proxy and updates" curl wget
    _doc_optional_tool "gzip" "backups and .sql.gz dumps" gzip
    _doc_optional_tool "unzip" ".zip dumps" unzip
    _doc_optional_tool "bzip2" ".sql.bz2 dumps" bzip2
    _doc_optional_tool "SHA-256 tool" "verifying downloads" sha256sum shasum openssl

    local wp ver out
    wp=$(PATH="$PATH:${WPDB_FALLBACK_PATH:-/opt/homebrew/bin:/usr/local/bin}" command -v wp 2>/dev/null)
    if [[ -z "$wp" ]]; then
        _doc_row FAIL "WP-CLI" "not found" "install WP-CLI: https://wp-cli.org/#installing"
    else
        out=$(WP_COMMAND="$wp" execute_wp_cli --version 2>&1)
        ver=$(printf "%s\n" "$out" | grep -m1 '^WP-CLI')
        if [[ -n "$ver" ]]; then
            _doc_row OK "WP-CLI" "$ver ($wp)"
        else
            _doc_row FAIL "WP-CLI" "does not run: $wp" "run '$wp --version' and fix the error it prints"
        fi
        if printf "%s" "$out" | grep -qiE 'deprecated|notice|warning'; then
            _doc_row WARN "PHP notices" "WP-CLI prints PHP deprecation/warning text" "use a PHP version your WP-CLI supports, or update WP-CLI (the tool hides this noise where it can)"
        fi
    fi

    local bin
    if bin=$(_find_mysql_bin); then
        _doc_row OK "mysql client" "$(_describe_mysql_client "$bin")"
        _DOC_BIN="$bin"
    else
        _DOC_BIN=""
        _doc_row FAIL "mysql client" "not found" "install a mysql/mariadb client, or set WPDB_MYSQL_BIN=/path/to/mysql"
    fi
    return 0
}

doctor_site_checks() {
    local wp_root="$1" config_path="$2"
    printf "\n${BOLD}Site${RESET}  %s\n" "$wp_root"

    if ! get_wp_db_credentials "$wp_root" >/dev/null 2>&1; then
        _doc_row FAIL "wp-config.php" "cannot read the database credentials" "check DB_NAME and DB_USER in $wp_root/wp-config.php"
        return 0
    fi
    _doc_row OK "wp-config.php" "database '$WP_DB_NAME', user '$WP_DB_USER'"

    # Settings from the config file, read only (no load_import_config: it can write the file)
    local cfg_socket="" cfg_use_socket="auto" cfg_backup_dir=""
    if [[ -n "$config_path" && -f "$config_path" ]]; then
        cfg_socket=$(parse_config_section "$config_path" "general" "mysql_socket" 2>/dev/null)
        cfg_use_socket=$(parse_config_section "$config_path" "general" "use_socket" 2>/dev/null)
        cfg_backup_dir=$(parse_config_section "$config_path" "general" "backup_dir" 2>/dev/null)
        [[ -z "$cfg_use_socket" ]] && cfg_use_socket="auto"
    fi

    local ver
    if ver=$(cd "$wp_root" && execute_wp_cli core is-installed 2>&1); then
        _doc_row OK "WordPress" "installed, WP-CLI can load it"
    else
        _doc_row FAIL "WordPress" "wp core is-installed failed" "run 'wp core is-installed' in $wp_root and fix the error it prints (database connection, PHP extension, wp-config)"
    fi

    _DOC_SOCKET=""
    if [[ "$cfg_use_socket" != "false" ]] && declare -F detect_mysql_socket >/dev/null 2>&1; then
        _DOC_SOCKET=$(detect_mysql_socket "$wp_root" "$cfg_socket" 2>/dev/null || true)
    fi
    if [[ -n "$_DOC_SOCKET" ]]; then
        _doc_row OK "MySQL socket" "$_DOC_SOCKET"
    else
        _doc_row OK "MySQL socket" "none found, the TCP host '${WP_DB_HOST:-localhost}' is used"
    fi

    if [[ -z "${_DOC_BIN:-}" ]]; then
        _doc_row FAIL "Database server" "skipped (no mysql client)" "install the mysql client first"
    else
        local server err
        if server=$(_doc_query "SELECT VERSION()" "$WP_DB_NAME") && [[ -n "$server" && "$server" != *ERROR* ]]; then
            _doc_row OK "Database server" "$server (connected as '$WP_DB_USER')"
            local cflavor sflavor
            cflavor=$(_mysql_flavor "$("$_DOC_BIN" --version 2>/dev/null)"); sflavor=$(_mysql_flavor "$server")
            if [[ "$cflavor" != "$sflavor" ]]; then
                _doc_row WARN "Client/server match" "$cflavor client with a $sflavor server" "put the right client first in PATH, or set WPDB_MYSQL_BIN"
            else
                _doc_row OK "Client/server match" "both $sflavor"
            fi

            local scratch="wpdb_doctor_$$" cerr
            if cerr=$(_doc_query "CREATE DATABASE \`${scratch}\`"); then
                _doc_query "DROP DATABASE IF EXISTS \`${scratch}\`" >/dev/null 2>&1
                _doc_row OK "CREATE DATABASE" "allowed (dry run and benchmark can work)"
            else
                _doc_row WARN "CREATE DATABASE" "refused" "GRANT CREATE ON \`wpdb_dry_%\`.* TO '$WP_DB_USER'@'...' (needed for --dry-run)"
            fi

            local mode
            mode=$(_doc_query "SELECT @@SESSION.sql_mode" "$WP_DB_NAME" 2>/dev/null | head -1)
            if [[ "$mode" == *NO_ZERO_DATE* || "$mode" == *STRICT_TRANS_TABLES* ]]; then
                _doc_row WARN "sql_mode" "strict (${mode:0:60})" "dumps with zero dates (0000-00-00) can fail; see issue #24"
            else
                _doc_row OK "sql_mode" "${mode:-empty}"
            fi
        else
            err=$(printf "%s" "$server" | grep -i 'error' | head -1 | cut -c1-160)
            _doc_row FAIL "Database server" "cannot connect: ${err:-no answer}" "start the database, check DB_HOST/DB_USER/DB_PASSWORD in wp-config.php, or set mysql_socket in wpdb-import.conf"
        fi
    fi

    # Backup folder and free space
    local bdir="${cfg_backup_dir:-$HOME/.wp-db-import/backups}" probe kb
    bdir="${bdir/#\~/$HOME}"
    probe="$bdir"; while [[ ! -d "$probe" && "$probe" != "/" ]]; do probe=$(dirname "$probe"); done
    if [[ -w "$probe" ]]; then
        _doc_row OK "Backup folder" "$bdir$([[ -d "$bdir" ]] || printf ' (created on first backup)')"
    else
        _doc_row FAIL "Backup folder" "$bdir is not writable" "chmod/chown the folder, or set backup_dir in wpdb-import.conf"
    fi
    kb=$(df -Pk "$probe" 2>/dev/null | awk 'NR==2 {print $4}')
    if [[ "$kb" =~ ^[0-9]+$ ]]; then
        if [[ "$kb" -lt 1048576 ]]; then
            _doc_row WARN "Free disk space" "$((kb / 1024)) MB free for backups" "free at least 1 GB, or set backup_before_import=false"
        else
            _doc_row OK "Free disk space" "$((kb / 1024)) MB free for backups"
        fi
    fi

    # Config file
    if [[ -n "$config_path" && -f "$config_path" ]]; then
        local out
        if out=$(validate_config_file "$config_path" 2>&1); then
            _doc_row OK "Config file" "$config_path"
        else
            _doc_row FAIL "Config file" "invalid: $(printf '%s' "$out" | LC_ALL=C grep -v '^$' | head -1 | cut -c1-120)" "run: wp-db-import config-validate"
        fi
    else
        _doc_row OK "Config file" "none (optional): wp-db-import config-create"
    fi
    return 0
}

doctor_cli() {
    local arg
    for arg in "$@"; do
        case "$arg" in
            -h|--help) printf "Usage: wp-db-import doctor\nChecks tools, WP-CLI, the database connection, backup folder and config. Exit 1 if a required item fails.\n"; return 0 ;;
            *) printf "${RED}❌ Unknown option: %s${RESET}\n" "$arg" >&2; return 2 ;;
        esac
    done
    _DOC_OK=0; _DOC_WARN=0; _DOC_FAIL=0
    printf "${CYAN}${BOLD}🩺 wp-db-import doctor${RESET}\n"
    doctor_tool_checks

    local wp_root="" config_path=""
    if declare -F find_wp_root >/dev/null 2>&1 && wp_root=$(find_wp_root 2>/dev/null); then
        declare -F get_config_file_path >/dev/null 2>&1 && config_path=$(get_config_file_path 2>/dev/null)
        doctor_site_checks "$wp_root" "$config_path"
    else
        printf "\n${BOLD}Site${RESET}  not in a WordPress directory: site checks skipped (cd into a site and run again)\n"
    fi

    printf "\n%d ok, %d warning(s), %d failed\n" "$_DOC_OK" "$_DOC_WARN" "$_DOC_FAIL"
    [[ "$_DOC_FAIL" -eq 0 ]]
}

export -f doctor_cli doctor_tool_checks doctor_site_checks _doc_row _doc_optional_tool _doc_query 2>/dev/null
