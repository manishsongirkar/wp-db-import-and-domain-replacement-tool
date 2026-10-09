#!/usr/bin/env bash

# ================================================================
# Throw-away MySQL / MariaDB servers for tests
# ================================================================
#
# Description:
#   Shared helpers used by the opt-in integration tests (server matrix, real import).
#   A server runs on a temporary data directory, listens on a Unix socket only (no network),
#   and is stopped and deleted by srv_cleanup. Nothing outside the temp directory is touched.
#
# Servers are found automatically (Local by Flywheel, Homebrew) or listed in
#   WPDB_MATRIX_SERVERS="/path/to/bin /another/bin"   (directories containing mysqld/mariadbd)
#
# Functions:
#   srv_find_servers          prints candidate bin directories, one per line
#   srv_label BINDIR          prints "MySQL x.y.z" or "MariaDB x.y.z"
#   srv_start BINDIR INDEX    starts a server in the CURRENT shell (its PID is tracked);
#                             sets SRV_CLIENT and SRV_SOCKET; needs SRV_WORK (a temp directory)
#   srv_cleanup               stops all started servers and removes SRV_WORK
#
# ================================================================

SRV_WORK="${SRV_WORK:-}"
SRV_PIDS="${SRV_PIDS:-}"
SRV_EXTRA_DIRS="${SRV_EXTRA_DIRS:-}"
SRV_CLIENT=""
SRV_SOCKET=""

srv_find_servers() {
    local d
    if [[ -n "${WPDB_MATRIX_SERVERS:-}" ]]; then
        for d in $WPDB_MATRIX_SERVERS; do printf "%s\n" "$d"; done
        return
    fi
    for d in "$HOME"/Library/Application\ Support/Local/lightning-services/mysql-*/bin/*/bin \
             /opt/homebrew/opt/mariadb*/bin /opt/homebrew/opt/mysql*/bin /usr/local/opt/mariadb*/bin \
             /usr/sbin /usr/libexec; do
        [[ -x "$d/mysqld" || -x "$d/mariadbd" ]] && printf "%s\n" "$d"
    done
}

srv_cleanup() {
    local pid
    for pid in $SRV_PIDS; do kill "$pid" 2>/dev/null; done
    for pid in $SRV_PIDS; do wait "$pid" 2>/dev/null; done
    SRV_PIDS=""
    local d
    for d in $SRV_EXTRA_DIRS; do rm -rf "$d"; done
    SRV_EXTRA_DIRS=""
    [[ -n "$SRV_WORK" ]] && rm -rf "$SRV_WORK"
    declare -F secure_tmpdir_cleanup >/dev/null 2>&1 && secure_tmpdir_cleanup 2>/dev/null
    return 0
}

srv_label() {
    local bindir="$1" daemon out ver
    if [[ -x "$bindir/mariadbd" ]]; then daemon="$bindir/mariadbd"; else daemon="$bindir/mysqld"; fi
    out=$("$daemon" --version 2>/dev/null)
    ver=$(printf "%s" "$out" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
    if [[ "$out" == *MariaDB* ]]; then printf "MariaDB %s" "$ver"; else printf "MySQL %s" "$ver"; fi
}

srv_start() {
    local bindir="$1" idx="$2"
    local base daemon client datadir sock log label
    base="$(cd "$bindir/.." && pwd)"
    if [[ -x "$bindir/mariadbd" ]]; then daemon="$bindir/mariadbd"; else daemon="$bindir/mysqld"; fi
    # Debian/Ubuntu keep the daemon in /usr/sbin and the clients in /usr/bin: fall back to PATH
    for client in "$bindir/mariadb" "$bindir/mysql" "$(command -v mariadb)" "$(command -v mysql)"; do [[ -x "$client" ]] && break; done
    [[ -x "$client" ]] || return 1
    label=$(srv_label "$bindir")
    datadir="$SRV_WORK/data$idx"; sock="$SRV_WORK/s$idx.sock"; log="$SRV_WORK/s$idx.log"
    # A Unix socket path is limited to about 100 characters: use a short directory when needed
    if [[ ${#sock} -gt 100 ]]; then
        local short
        short=$(mktemp -d /tmp/wpdbs.XXXXXX) || return 1
        SRV_EXTRA_DIRS="$SRV_EXTRA_DIRS $short"
        sock="$short/s$idx.sock"
    fi

    if [[ "$label" == MariaDB* ]]; then
        local inst=""
        for inst in "$bindir/mariadb-install-db" "$bindir/mysql_install_db" "$base/scripts/mariadb-install-db" "$base/scripts/mysql_install_db" "$(command -v mariadb-install-db)" "$(command -v mysql_install_db)"; do [[ -x "$inst" ]] && break; done
        [[ -x "$inst" ]] || return 1
        "$inst" --no-defaults --datadir="$datadir" --basedir="$base" --auth-root-authentication-method=normal >"$log" 2>&1 || return 1
    else
        "$daemon" --no-defaults --initialize-insecure --datadir="$datadir" --basedir="$base" >"$log" 2>&1 || return 1
    fi
    "$daemon" --no-defaults --datadir="$datadir" --basedir="$base" --socket="$sock" \
        --pid-file="$SRV_WORK/s$idx.pid" --skip-networking >>"$log" 2>&1 &
    SRV_PIDS="$SRV_PIDS $!"
    local i
    for i in $(seq 1 60); do
        [[ -S "$sock" ]] && "$client" --no-defaults -uroot --socket="$sock" -e "SELECT 1" >/dev/null 2>&1 && break
        sleep 0.5
    done
    "$client" --no-defaults -uroot --socket="$sock" -e "SELECT 1" >/dev/null 2>&1 || return 1
    SRV_CLIENT="$client"
    SRV_SOCKET="$sock"
    return 0
}
