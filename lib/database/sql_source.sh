#!/usr/bin/env bash

# ================================================================
# SQL Source Helpers
# ================================================================
#
# Description:
#   Helpers that turn an SQL dump (plain, .gz, .zip or .bz2) into a clean SQL
#   stream for the importers in db_import.sh:
#     - sql_file_kind / sql_open_stream / sql_verify_source: compressed dumps
#     - sql_uncompressed_size_bytes: real SQL size for estimates
#     - sql_compat_filter: rewrites MariaDB/MySQL-version specific DDL that the
#       target server rejects (used only after a first import attempt failed)
#     - import_error_is_compat_related: decides when that retry is worthwhile
#     - estimate_heuristic: size-based import time estimate (no benchmark)
#
# Compatibility: Bash 3.2+, BSD (macOS) and GNU userland.
#
# ================================================================

# secure_tmpdir lives in core/utils.sh; load it when this file is sourced on its own
if ! declare -F secure_tmpdir >/dev/null 2>&1; then
    # shellcheck source=/dev/null
    source "$(dirname "${BASH_SOURCE[0]}")/../core/utils.sh" >/dev/null 2>&1
fi

# ===============================================
# File size in bytes (BSD stat, then GNU stat)
# ===============================================
_sql_file_size_bytes() {
    local size
    size=$(stat -f%z "$1" 2>/dev/null)
    [[ "$size" =~ ^[0-9]+$ ]] || size=$(stat -c%s "$1" 2>/dev/null)
    [[ "$size" =~ ^[0-9]+$ ]] || size=0
    printf "%s" "$size"
}

# ===============================================
# Detect dump type from the file extension
# ===============================================
# Prints: plain | gzip | zip | bzip2
sql_file_kind() {
    local lower
    lower=$(printf "%s" "$1" | tr '[:upper:]' '[:lower:]')
    case "$lower" in
        *.gz|*.gzip) printf "gzip" ;;
        *.zip)       printf "zip" ;;
        *.bz2)       printf "bzip2" ;;
        *.gpg|*.pgp|*.asc) printf "gpg" ;;
        *)           printf "plain" ;;
    esac
}

# ===============================================
# Stream the SQL text of a dump to stdout
# ===============================================
sql_open_stream() {
    local file="$1"
    case "$(sql_file_kind "$file")" in
        gzip)  gzip -dc -- "$file" ;;
        bzip2) bzip2 -dc -- "$file" ;;
        # Only .sql members; skips macOS __MACOSX folders and ._ resource-fork files
        zip)   unzip -p "$file" '*.sql' -x '*__MACOSX/*' '*/._*' '._*' ;;
        # Encrypted backups are decrypted once by "wp-db-import restore"; never stream ciphertext as SQL
        gpg)   return 1 ;;
        *)     cat -- "$file" ;;
    esac
}

# ===============================================
# Verify the dump exists and (if compressed) is intact
# ===============================================
# Returns 0 if usable. Prints the reason to stderr and returns 1 otherwise.
sql_verify_source() {
    local file="$1"
    local kind tool
    if [[ ! -f "$file" || ! -r "$file" ]]; then
        printf "%s\n" "SQL file not found or not readable: $file" >&2
        return 1
    fi
    kind=$(sql_file_kind "$file")
    case "$kind" in
        plain) return 0 ;;
        gpg)
            printf "%s\n" "This file is encrypted. Use: wp-db-import restore \"$file\" (gpg asks for your passphrase)" >&2
            return 1
            ;;
        gzip)  tool="gzip" ;;
        bzip2) tool="bzip2" ;;
        zip)   tool="unzip" ;;
    esac
    if ! command -v "$tool" >/dev/null 2>&1; then
        printf "%s\n" "'$tool' is required to read this $kind dump but was not found" >&2
        return 1
    fi
    case "$kind" in
        gzip)  gzip -t -- "$file" 2>/dev/null ;;
        bzip2) bzip2 -t -- "$file" 2>/dev/null ;;
        zip)
            unzip -tq "$file" >/dev/null 2>&1 \
                && unzip -Z1 "$file" 2>/dev/null | grep -iE '\.sql$' | grep -qvE '(^|/)__MACOSX/|(^|/)\._'
            ;;
    esac
    if [[ $? -ne 0 ]]; then
        printf "%s\n" "The $kind archive is corrupt or contains no .sql file: $file" >&2
        return 1
    fi
    return 0
}

# ===============================================
# Uncompressed SQL size in bytes
# ===============================================
# Plain files: file size. Archives: size from the archive index. If the index is
# missing or implausible (bzip2 stores none; gzip stores the size modulo 4 GB, so a
# value below the compressed size on a non-tiny file means it wrapped) assume 5x compressed.
sql_uncompressed_size_bytes() {
    local file="$1"
    local on_disk size=""
    on_disk=$(_sql_file_size_bytes "$file")
    case "$(sql_file_kind "$file")" in
        gzip)  size=$(gzip -l -- "$file" 2>/dev/null | awk 'NR==2 {print $2}') ;;
        zip)   size=$(unzip -l "$file" '*.sql' -x '*__MACOSX/*' '*/._*' '._*' 2>/dev/null | awk 'END {print $1}') ;;
        bzip2) size="" ;;
        *)     printf "%s" "$on_disk"; return 0 ;;
    esac
    if [[ ! "$size" =~ ^[0-9]+$ || "$size" -eq 0 ]] || [[ "$size" -lt "$on_disk" && "$on_disk" -gt 65536 ]]; then
        size=$((on_disk * 5))
    fi
    printf "%s" "$size"
}

# ===============================================
# Size-based estimate (no benchmark)
# ===============================================
# Parameters: $1 = SQL size in MB.  Prints "min likely max" in minutes (each >= 1).
estimate_heuristic() {
    local mb="${1:-0}"
    local likely=$((mb / 15))
    [[ "$likely" -lt 1 ]] && likely=1
    local min=$((likely / 2))
    [[ "$min" -lt 1 ]] && min=1
    printf "%d %d %d" "$min" "$likely" $((likely * 2))
}

# ===============================================
# Compatibility filter (stdin -> stdout)
# ===============================================
#
# Description:
#   Rewrites DDL that other MySQL/MariaDB versions reject:
#     - MySQL 8 / MariaDB 11.5+ collations (utf8mb4_0900_*, utf8mb4_uca1400_*,
#       utf8mb3_uca1400_*) -> utf8mb4_unicode_520_ci / utf8_unicode_520_ci / utf8mb4_bin
#     - utf8mb3 -> utf8 (older MySQL does not know the utf8mb3 name)
#     - MariaDB-only table options (ENGINE=Aria, TRANSACTIONAL, PAGE_CHECKSUM)
#     - DEFINER=... clauses (users that do not exist on the target)
#     - NO_AUTO_CREATE_USER in sql_mode (removed in MySQL 8)
#     - GTID_PURGED / SQL_LOG_BIN statements (need SUPER, not valid on MariaDB)
#     - the MariaDB "enable the sandbox mode" first line
#   Rules apply only to lines that look like DDL or session statements (start
#   with a backtick, ")", CREATE, ALTER, DROP, LOCK, SET or a /*! comment), so row
#   data inside INSERT statements is never modified.
#
_sql_compat_script() {
    cat <<'EOF'
/^\/\*M!999999[\\]?- enable the sandbox mode \*\/[[:space:]]*$/d
/^[[:space:]]*SET[[:space:]]+@@(GLOBAL|SESSION)\.(GTID_PURGED|SQL_LOG_BIN)/d
/^[[:space:]]*(`|\)|CREATE[[:space:]]|ALTER[[:space:]]|DROP[[:space:]]|LOCK[[:space:]]|SET[[:space:]]|\/\*)/{
s/utf8mb4_0900_bin/utf8mb4_bin/g
s/utf8mb4_(0900|uca1400)_[a-z0-9_]*/utf8mb4_unicode_520_ci/g
s/utf8(mb3)?_uca1400_[a-z0-9_]*/utf8_unicode_520_ci/g
s/utf8mb3/utf8/g
s/ENGINE=Aria/ENGINE=InnoDB/g
s/ TRANSACTIONAL=[01]//g
s/ PAGE_CHECKSUM=[01]//g
s/DEFINER[[:space:]]*=[[:space:]]*`[^`]*`@`[^`]*`[[:space:]]*//g
s/DEFINER[[:space:]]*=[[:space:]]*'[^']*'@'[^']*'[[:space:]]*//g
s/,NO_AUTO_CREATE_USER//g
s/NO_AUTO_CREATE_USER,//g
s/NO_AUTO_CREATE_USER//g
}
EOF
}

sql_compat_filter() {
    local script
    script="$(secure_tmpdir)/compat.sed" || return 1
    [[ -f "$script" ]] || _sql_compat_script > "$script" || return 1
    LC_ALL=C sed -E -f "$script"
}

# ===============================================
# Is this import failure worth a retry with the filter?
# ===============================================
# Parameters: $1 = import log file. Returns 0 if it shows a version-compatibility error.
import_error_is_compat_related() {
    local log="$1"
    [[ -f "$log" ]] || return 1
    grep -qiE 'Unknown collation|Unknown character set|Unknown storage engine|ERROR (1273|1115|1286|1227|1449)|GTID_PURGED|NO_AUTO_CREATE_USER|DEFINER|sandbox mode|COLLATION .* is not valid' "$log" 2>/dev/null
}

# ===============================================
# Does an import log contain MySQL errors?
# ===============================================
# Some mysql/mariadb clients exit 0 even when statements failed, so an exit code alone
# is not proof of success. Returns 0 if the log has an "ERROR nnnn" line.
import_log_has_errors() {
    [[ -f "$1" ]] && LC_ALL=C grep -qE '^ERROR [0-9]+' "$1" 2>/dev/null
}

# ===============================================
# Cap a log file's size (log rotation for per-run logs)
# ===============================================
# A failing import can echo every remaining statement (hundreds of thousands of lines).
# Keeps the first and last half of the budget with a marker in between.
# Parameters: $1 = file, $2 = max bytes (default 262144)
cap_log_file() {
    local file="$1" max="${2:-262144}" size half tmp
    [[ -f "$file" ]] || return 0
    size=$(_sql_file_size_bytes "$file")
    [[ "$size" -le "$max" ]] && return 0
    half=$((max / 2))
    tmp="${file}.cap"
    {
        head -c "$half" "$file"
        printf '\n... [log truncated: %s bytes omitted] ...\n' "$((size - max))"
        tail -c "$half" "$file"
    } > "$tmp" 2>/dev/null && mv "$tmp" "$file" || rm -f "$tmp"
    return 0
}

# ===============================================
# Does the dump drop tables before creating them?
# ===============================================
# Looks at the first 256 KB of the SQL. Dumps made with --skip-add-drop-table (or by tools
# that never emit DROP TABLE) cannot be re-run safely after a partly failed import.
# If the DROP statements appear only later, this returns 1: the caller then takes the
# safe path (snapshot tables, remove new ones before a retry).
sql_has_drop_table() {
    sql_open_stream "$1" 2>/dev/null | head -c 262144 2>/dev/null | LC_ALL=C grep -qiE '^[[:space:]]*(/\*![0-9]+[[:space:]]+)?DROP[[:space:]]+TABLE[[:space:]]+IF[[:space:]]+EXISTS'
}

# ===============================================
# Describe a mysql client: "<path> (<version line>)"
# ===============================================
_describe_mysql_client() {
    local bin="$1" ver
    ver=$("$bin" --version 2>/dev/null | head -1 | sed 's/^[[:space:]]*//')
    printf "%s (%s)" "$bin" "${ver:-unknown version}"
}

# ===============================================
# "mariadb" or "mysql" from any version text
# ===============================================
_mysql_flavor() {
    case "$(printf "%s" "$1" | tr '[:upper:]' '[:lower:]')" in
        *mariadb*) printf "mariadb" ;;
        *)         printf "mysql" ;;
    esac
}

# ===============================================
# Locate the mysql client
# ===============================================
# Honors WPDB_MYSQL_BIN (explicit path, also used by the tests), then PATH plus the
# usual Homebrew locations. Prints nothing and returns 1 if none is found.
_find_mysql_bin() {
    local bin="${WPDB_MYSQL_BIN:-}"
    if [[ -z "$bin" ]]; then
        bin=$(PATH="$PATH:${WPDB_FALLBACK_PATH:-/opt/homebrew/bin:/usr/local/bin}" command -v mysql 2>/dev/null)
    fi
    [[ -n "$bin" && -x "$bin" ]] || return 1
    printf "%s" "$bin"
}

# ===============================================
# Build mysql client arguments
# ===============================================
# Sets the global array _WPDB_MYSQL_ARGS (Bash 3.2 cannot return arrays).
# Parameters: $1 socket, $2 DB_HOST (host[:port]), $3 user, $4 database (optional), $5 connect timeout
_build_mysql_args() {
    local socket="$1" host="$2" user="$3" db="${4:-}" timeout="${5:-10}"
    _WPDB_MYSQL_ARGS=("--user=${user}" "--silent" "--connect-timeout=${timeout}")
    [[ -n "$db" ]] && _WPDB_MYSQL_ARGS+=("--database=${db}")
    if [[ -n "$socket" && -S "$socket" ]]; then
        _WPDB_MYSQL_ARGS+=("--socket=${socket}")
    elif [[ -n "$host" ]]; then
        local host_part="${host%%:*}"
        local port_part="${host##*:}"
        _WPDB_MYSQL_ARGS+=("--host=${host_part}")
        if [[ "$port_part" != "$host_part" && "$port_part" =~ ^[0-9]+$ ]]; then
            _WPDB_MYSQL_ARGS+=("--port=${port_part}")
        fi
    fi
}

export -f _sql_file_size_bytes sql_file_kind sql_open_stream sql_verify_source \
    sql_uncompressed_size_bytes estimate_heuristic _sql_compat_script sql_compat_filter \
    import_error_is_compat_related import_log_has_errors cap_log_file sql_has_drop_table _describe_mysql_client _mysql_flavor _find_mysql_bin _build_mysql_args 2>/dev/null
