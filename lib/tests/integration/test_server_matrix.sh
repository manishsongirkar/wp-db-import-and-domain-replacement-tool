#!/usr/bin/env bash

# ================================================================
# Server Version Matrix (opt-in)
# ================================================================
#
# Description:
#   Starts throw-away MySQL/MariaDB servers (temp data dir, socket only, no network)
#   and imports three fixture dumps (MariaDB 11, MySQL 8, plain legacy) into each one,
#   with and without the compatibility filter. Proves the filter makes foreign-version
#   dumps import everywhere and never breaks a dump that already worked.
#
# Servers are found automatically (Local by Flywheel, Homebrew) or listed in
#   WPDB_MATRIX_SERVERS="/path/to/bin /another/bin"   (dirs containing mysqld/mariadbd)
#
# Usage:
#   ./run_tests.sh matrix            (not part of "all": it starts real servers)
#
# ================================================================

# Captured first: on Bash 3.2, BASH_SOURCE[0] changes after top-level `source` calls
_MATRIX_SELF="${BASH_SOURCE[0]}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../test_framework.sh"
source "$PROJECT_ROOT_DIR/lib/core/utils.sh" >/dev/null 2>&1
source "$PROJECT_ROOT_DIR/lib/database/sql_source.sh" >/dev/null 2>&1
source "$PROJECT_ROOT_DIR/lib/database/db_import.sh" >/dev/null 2>&1

FIXTURES="$PROJECT_ROOT_DIR/lib/tests/fixtures"
MATRIX_WORK=""
MATRIX_PIDS=""
MATRIX_SEEN=""

_matrix_find_servers() {
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

_matrix_cleanup() {
    local pid
    for pid in $MATRIX_PIDS; do kill "$pid" 2>/dev/null; done
    for pid in $MATRIX_PIDS; do wait "$pid" 2>/dev/null; done
    [[ -n "$MATRIX_WORK" ]] && rm -rf "$MATRIX_WORK"
    secure_tmpdir_cleanup 2>/dev/null
}

# Prints "MySQL x.y.z" / "MariaDB x.y.z" for a bin directory
_matrix_label() {
    local bindir="$1" daemon out ver
    if [[ -x "$bindir/mariadbd" ]]; then daemon="$bindir/mariadbd"; else daemon="$bindir/mysqld"; fi
    out=$("$daemon" --version 2>/dev/null)
    ver=$(printf "%s" "$out" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
    if [[ "$out" == *MariaDB* ]]; then printf "MariaDB %s" "$ver"; else printf "MySQL %s" "$ver"; fi
}

# Start one server in the CURRENT shell (so its PID is tracked for cleanup).
# Sets MATRIX_CLIENT and MATRIX_SOCKET on success.
_matrix_start() {
    local bindir="$1" idx="$2"
    local base daemon client datadir sock log label
    base="$(cd "$bindir/.." && pwd)"
    if [[ -x "$bindir/mariadbd" ]]; then daemon="$bindir/mariadbd"; else daemon="$bindir/mysqld"; fi
    for client in "$bindir/mariadb" "$bindir/mysql"; do [[ -x "$client" ]] && break; done
    [[ -x "$client" ]] || return 1
    label=$(_matrix_label "$bindir")
    datadir="$MATRIX_WORK/data$idx"; sock="$MATRIX_WORK/s$idx.sock"; log="$MATRIX_WORK/s$idx.log"

    if [[ "$label" == MariaDB* ]]; then
        local inst=""
        for inst in "$bindir/mariadb-install-db" "$bindir/mysql_install_db" "$base/scripts/mariadb-install-db" "$base/scripts/mysql_install_db"; do [[ -x "$inst" ]] && break; done
        [[ -x "$inst" ]] || return 1
        "$inst" --no-defaults --datadir="$datadir" --basedir="$base" --auth-root-authentication-method=normal >"$log" 2>&1 || return 1
    else
        "$daemon" --no-defaults --initialize-insecure --datadir="$datadir" --basedir="$base" >"$log" 2>&1 || return 1
    fi
    "$daemon" --no-defaults --datadir="$datadir" --basedir="$base" --socket="$sock" \
        --pid-file="$MATRIX_WORK/s$idx.pid" --skip-networking >>"$log" 2>&1 &
    MATRIX_PIDS="$MATRIX_PIDS $!"
    local i
    for i in $(seq 1 60); do
        [[ -S "$sock" ]] && "$client" --no-defaults -uroot --socket="$sock" -e "SELECT 1" >/dev/null 2>&1 && break
        sleep 0.5
    done
    "$client" --no-defaults -uroot --socket="$sock" -e "SELECT 1" >/dev/null 2>&1 || return 1
    MATRIX_CLIENT="$client"
    MATRIX_SOCKET="$sock"
    return 0
}

# Real-server check of retry safety (issue #27) for a dump that has no DROP TABLE statements.
# Prints one table row. Returns 0 on success.
_matrix_nodrop_case() {
    local client="$1" sock="$2" label="$3" fx="$FIXTURES/dump_nodrop_mariadb11.sql"
    local plain filt rows control="n/a" ok=0
    q() { "$client" --no-defaults -uroot --socket="$sock" "$@"; }
    q -e "DROP DATABASE IF EXISTS wp; CREATE DATABASE wp" >/dev/null 2>&1

    # execute_wp_cli stand-in that runs the SQL on this server (what the tool would send through WP-CLI)
    execute_wp_cli() { [[ "$1 $2" == "db query" ]] || return 0; q wp -N -e "$3"; }

    local snapshot
    snapshot=$(import_snapshot_tables) || { printf "     ❌ could not snapshot tables on %s\n" "$label"; return 1; }

    perform_db_import_via_socket "$fx" "$MATRIX_WORK/nd1.log" "$sock" "" root "" wp false false >/dev/null 2>&1
    plain=$?
    if [[ $plain -ne 0 ]]; then
        import_error_is_compat_related "$MATRIX_WORK/nd1.log" || { printf "     ❌ %s: first failure is not retry-eligible\n" "$label"; ok=1; }
        # Control: retrying WITHOUT cleanup must fail (proves the scenario is real)
        perform_db_import_via_socket "$fx" "$MATRIX_WORK/nd2.log" "$sock" "" root "" wp false true >/dev/null 2>&1
        if [[ $? -eq 0 ]]; then control="no-failure"; printf "     ❌ %s: retry without cleanup unexpectedly worked (scenario not exercised)\n" "$label"; ok=1; else control="fails"; fi
        import_prepare_retry "$snapshot" >/dev/null 2>&1 || { printf "     ❌ %s: cleanup failed\n" "$label"; ok=1; }
        perform_db_import_via_socket "$fx" "$MATRIX_WORK/nd3.log" "$sock" "" root "" wp false true >/dev/null 2>&1
        filt=$?
    else
        filt=0
    fi
    rows=$(q -N -e "SELECT COUNT(*) FROM wp.wp_posts" 2>/dev/null)
    local tables; tables=$(q -N -e "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='wp'" 2>/dev/null)
    printf "  %-24s %-20s %-14s %-14s\n" "$label" "dump_nodrop (cleanup)" "$([[ $plain -eq 0 ]] && echo ok || echo "rejected")" "$([[ $filt -eq 0 && "$rows" == 2 && "$tables" == 2 ]] && echo ok || echo FAIL)"
    if [[ $filt -ne 0 || "$rows" != "2" || "$tables" != "2" ]]; then
        printf "     ❌ %s: no-DROP dump did not end with 2 tables / 2 rows (tables=%s rows=%s)\n" "$label" "$tables" "$rows"
        ok=1
    fi
    unset -f execute_wp_cli q
    return $ok
}

test_server_matrix() {
    start_test "Server Version Matrix" "fixtures import on every available MySQL/MariaDB version with the filter"
    local servers
    servers=$(_matrix_find_servers)
    if [[ -z "$servers" ]]; then
        skip_test "no MySQL/MariaDB server binaries found (set WPDB_MATRIX_SERVERS)"
        return 0
    fi

    MATRIX_WORK=$(mktemp -d "${TMPDIR:-/tmp}/wpdb-matrix.XXXXXX")
    trap _matrix_cleanup EXIT
    local errors=0 tested=0 idx=0 bindir info label client sock fx want
    local -a fixtures=("dump_legacy.sql" "dump_mariadb11.sql" "dump_mysql8.sql" "dump_nodrop_mariadb11.sql")

    printf "\n  %-24s %-20s %-14s %-14s\n" "SERVER" "FIXTURE" "UNFILTERED" "FILTERED"
    while IFS= read -r bindir; do
        [[ -z "$bindir" ]] && continue
        label=$(_matrix_label "$bindir")
        case " $MATRIX_SEEN " in *" $label "*) continue ;; esac     # same version found in two places
        MATRIX_SEEN="$MATRIX_SEEN $label"
        idx=$((idx + 1))
        _matrix_start "$bindir" "$idx"; local start_rc=$?
        if [[ $start_rc -ne 0 ]]; then
            printf "  ⚠️  %-22s could not start (skipped)\n" "$bindir"
            continue
        fi
        client="$MATRIX_CLIENT"; sock="$MATRIX_SOCKET"
        export WPDB_MYSQL_BIN="$client"
        "$client" --no-defaults -uroot --socket="$sock" -e "CREATE DATABASE wp" >/dev/null 2>&1
        tested=$((tested + 1))

        for fx in "${fixtures[@]}"; do
            local plain filt
            if [[ "$fx" == "dump_nodrop_mariadb11.sql" ]]; then
                # Dump without DROP TABLE: the retry needs the failed attempt's tables removed first.
                _matrix_nodrop_case "$client" "$sock" "$label"
                [[ $? -ne 0 ]] && ((errors++))
                continue
            fi
            # Unfiltered attempt (informational, plus: a failure must be retry-eligible)
            perform_db_import_via_socket "$FIXTURES/$fx" "$MATRIX_WORK/p.log" "$sock" "" root "" wp false false >/dev/null 2>&1
            plain=$?
            local retry_ok=true
            if [[ $plain -ne 0 ]] && ! import_error_is_compat_related "$MATRIX_WORK/p.log"; then retry_ok=false; fi

            perform_db_import_via_socket "$FIXTURES/$fx" "$MATRIX_WORK/f.log" "$sock" "" root "" wp false true >/dev/null 2>&1
            filt=$?
            local rows
            rows=$("$client" --no-defaults -uroot --socket="$sock" -N -e "SELECT COUNT(*) FROM wp.wp_posts" 2>/dev/null)
            printf "  %-24s %-20s %-14s %-14s\n" "$label" "$fx" "$([[ $plain -eq 0 ]] && echo ok || echo 'rejected')" "$([[ $filt -eq 0 && "$rows" == 2 ]] && echo ok || echo FAIL)"

            if [[ $filt -ne 0 || "$rows" != "2" ]]; then
                printf "     ❌ filtered import failed on %s with %s: %s\n" "$label" "$fx" "$(head -2 "$MATRIX_WORK/f.log" | tr '\n' ' ')"
                ((errors++))
            fi
            if [[ "$retry_ok" != "true" ]]; then
                printf "     ❌ unfiltered failure on %s/%s is not retry-eligible: %s\n" "$label" "$fx" "$(head -1 "$MATRIX_WORK/p.log")"
                ((errors++))
            fi
            # A dump that already imported must still import identically through the filter
            if [[ "$fx" == "dump_legacy.sql" && $plain -ne 0 ]]; then
                printf "     ❌ legacy dump must import without the filter on %s\n" "$label"
                ((errors++))
            fi
        done
        unset WPDB_MYSQL_BIN
    done <<< "$servers"

    if [[ "$tested" -eq 0 ]]; then
        skip_test "no server could be started"
    elif [[ "$errors" -eq 0 ]]; then
        pass_test "all fixtures import on $tested server version(s) with the filter"
    else
        fail_test "$errors matrix failure(s)"
    fi
}

run_server_matrix_tests() {
    printf "\n${CYAN}${BOLD}🧪 Server Version Matrix${RESET}\n"
    printf "%s\n" "$(printf '=%.0s' {1..50})"
    init_test_session "server_matrix"
    test_server_matrix
    _matrix_cleanup
    finalize_test_session
    return $?
}

if [[ "$_MATRIX_SELF" == "${0}" ]]; then
    run_server_matrix_tests
fi
