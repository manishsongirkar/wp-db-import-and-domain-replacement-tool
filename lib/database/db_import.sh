#!/usr/bin/env bash

# ================================================================
# Database Import Module
# ================================================================
#
# Description:
#   Handles the core database import functionality. Supports two
#   import paths:
#
#     1. Socket Import (preferred for local dev):
#        Connects via Unix socket directly to the mysql binary,
#        bypassing PHP/WP-CLI overhead entirely. Significantly
#        faster for large SQL files on local environments.
#
#     2. WP-CLI Import (fallback / remote / restricted envs):
#        Uses `wp db import` which reads credentials from
#        wp-config.php via PHP mysqli. Always available when
#        WP-CLI is installed.
#
#   The `perform_db_import()` function automatically selects the
#   fastest available method based on the environment.
#
# ================================================================

# Load SQL source helpers (compressed dumps, compatibility filter, size estimates)
if ! declare -F sql_open_stream >/dev/null 2>&1; then
    # shellcheck source=/dev/null
    source "$(dirname "${BASH_SOURCE[0]}")/sql_source.sh"
fi

# ===============================================
# Is truthy config value
# ===============================================
_is_truthy() {
    local value="$1"
    local lower
    lower=$(printf "%s" "$value" | tr '[:upper:]' '[:lower:]')
    [[ "$lower" =~ ^(true|yes|1|on)$ ]]
}

# ===============================================
# Should optimize mysql import session
# ===============================================
should_enable_optimized_import_session() {
    local mode="${1:-auto}"
    local import_method="${2:-wp-cli}"

    # Session flags only apply to direct mysql client imports.
    if [[ "$import_method" != "socket" && "$import_method" != "mysql-cli" ]]; then
        return 1
    fi

    local mode_lc
    mode_lc=$(printf "%s" "$mode" | tr '[:upper:]' '[:lower:]')

    case "$mode_lc" in
        true|yes|1|on)
            return 0
            ;;
        false|no|0|off)
            return 1
            ;;
        auto|"")
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

# ================================================================
# Perform Database Import via Unix Socket
# ================================================================
#
# Description:
#   Imports a SQL file using the mysql CLI binary.
#   This method is faster than WP-CLI for local environments because:
#     - No PHP or WP-CLI bootstrap overhead
#     - Unix socket I/O bypasses the TCP/IP network stack when available
#     - Direct streaming of the SQL file into mysql
#
# Parameters:
#   $1: Path to the SQL file
#   $2: Path to the log file
#   $3: Unix socket path (e.g. /opt/homebrew/var/mysql/mysql.sock), optional
#   $4: Database host (from wp-config.php DB_HOST, used when socket unavailable)
#   $5: Database user (from wp-config.php DB_USER)
#   $6: Database password (from wp-config.php DB_PASSWORD)
#   $7: Database name (from wp-config.php DB_NAME)
#   $8: Enable optimized import session (true/false)
#
# Returns:
#   0 on success, 1 on failure
#
perform_db_import_via_socket() {
    local sql_file="$1"
    local log_file="$2"
    local socket_path="$3"
    local db_host="$4"
    local db_user="$5"
    local db_pass="$6"
    local db_name="$7"
    local use_optimized_session="${8:-false}"

    local use_compat_filter="${9:-false}"

    # Locate mysql binary with Homebrew paths
    local mysql_bin
    mysql_bin=$(_find_mysql_bin) || return 1

    _build_mysql_args "$socket_path" "$db_host" "$db_user" "$db_name" 10
    local -a mysql_args=("${_WPDB_MYSQL_ARGS[@]}")
    if [[ -n "$socket_path" && -S "$socket_path" ]]; then
        printf "${CYAN}🔌 Socket:${RESET} %s\n" "$socket_path"
    fi

    # Pass password via environment variable to avoid shell history / ps exposure.
    # MYSQL_PWD is the official mysql client env var for password.
    _emit_import_stream "$sql_file" "$use_optimized_session" "$use_compat_filter" \
        | MYSQL_PWD="$db_pass" "$mysql_bin" "${mysql_args[@]}" &> "$log_file"

    # Exit status of the pipeline is mysql's; archive integrity was verified up front
    local rc=$?
    if [[ "$rc" -eq 0 ]] && import_log_has_errors "$log_file"; then
        rc=1
    fi
    cap_log_file "$log_file"
    [[ "$rc" -eq 0 ]]
}

# ================================================================
# Emit the SQL stream sent to the importer
# ================================================================
#
# Parameters:
#   $1: SQL file (plain, .gz, .zip or .bz2)
#   $2: Wrap with session optimizations (true/false)
#   $3: Apply the compatibility filter (true/false)
#
_emit_import_stream() {
    local sql_file="$1" optimized="${2:-false}" compat="${3:-false}"

    if [[ "$optimized" == "true" ]]; then
        printf "SET AUTOCOMMIT = 0;\nSET FOREIGN_KEY_CHECKS = 0;\nSET UNIQUE_CHECKS = 0;\n"
    fi
    if [[ "$compat" == "true" ]]; then
        sql_open_stream "$sql_file" | sql_compat_filter
    else
        sql_open_stream "$sql_file"
    fi
    if [[ "$optimized" == "true" ]]; then
        printf "\nCOMMIT;\nSET FOREIGN_KEY_CHECKS = 1;\nSET UNIQUE_CHECKS = 1;\nSET AUTOCOMMIT = 1;\n"
    fi
}

# ================================================================
# Perform Database Import via WP-CLI (stream form)
# ================================================================
#
# Description:
#   Imports through `wp db import -` (stdin). Used for compressed dumps and
#   for the compatibility-filter retry; plain files use `wp db import <file>`.
#
# Parameters:
#   $1: SQL file   $2: log file   $3: apply compatibility filter (true/false)
#   $4: WP-CLI command (default: wp)   $5: "direct" to use execute_wp_cli
#
perform_db_import_via_wpcli() {
    local sql_file="$1" log_file="$2" compat="${3:-false}" wp_cmd="${4:-wp}" mode="${5:-}"

    local rc
    if [[ "$mode" == "direct" ]]; then
        if [[ "$compat" != "true" && "$(sql_file_kind "$sql_file")" == "plain" ]]; then
            execute_wp_cli db import "$sql_file" &> "$log_file"
        else
            _emit_import_stream "$sql_file" false "$compat" | execute_wp_cli db import - &> "$log_file"
        fi
        rc=$?
    else
        (
            export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
            if [[ "$compat" != "true" && "$(sql_file_kind "$sql_file")" == "plain" ]]; then
                "$wp_cmd" db import "$sql_file"
            else
                _emit_import_stream "$sql_file" false "$compat" | "$wp_cmd" db import -
            fi
        ) &> "$log_file"
        rc=$?
    fi

    # Some mysql clients exit 0 although statements failed: trust the log, not just the exit code
    if [[ "$rc" -eq 0 ]] && import_log_has_errors "$log_file"; then
        rc=1
    fi
    cap_log_file "$log_file"
    return "$rc"
}

# ================================================================
# Portable Millisecond Clock
# ================================================================
#
# Description:
#   Prints the current Unix time in milliseconds. Works on Bash 3.2 (macOS)
#   and Linux. `date +%s%N` is not used because older BSD/macOS `date`
#   prints a literal "N" instead of nanoseconds.
#
# Order: Bash 5 EPOCHREALTIME, GNU/new BSD `date +%s%N`, perl Time::HiRes,
#        then whole-second `date +%s` (millisecond part is zero).
#
_now_ms() {
    if [[ -n "${EPOCHREALTIME:-}" ]]; then
        local t="${EPOCHREALTIME/[.,]/}"
        printf "%d" $((10#${t} / 1000))
        return 0
    fi

    local ns
    ns=$(date +%s%N 2>/dev/null)
    if [[ "$ns" =~ ^[0-9]{16,}$ ]]; then
        printf "%d" $((10#${ns} / 1000000))
        return 0
    fi

    local ms
    ms=$(perl -MTime::HiRes=time -e 'printf "%d", time() * 1000' 2>/dev/null)
    if [[ "$ms" =~ ^[0-9]+$ ]]; then
        printf "%s" "$ms"
        return 0
    fi

    printf "%d" $(( $(date +%s) * 1000 ))
}

# ================================================================
# Estimate Import Duration via Sample Benchmark
# ================================================================
#
# Description:
#   Benchmarks a small sample of the SQL file to estimate full import time.
#   Tests the fastest available method (socket or mysql CLI) to project
#   realistic throughput on the user's machine and database configuration.
#
# Parameters:
#   $1: Path to the SQL file
#   $2: Unix socket path (optional)
#   $3: Database host
#   $4: Database user
#   $5: Database password
#   $6: Database name
#   $7: Optimization mode (for session flags)
#
# Returns:
#   Echoes three space-separated values: min_minutes likely_minutes max_minutes
#   (values like "2 5 15" for small files or "30 45 120" for 20GB)
#
# Behavior:
#   - Files under 100 MB, or when no benchmark is possible: size-based estimate
#   - Otherwise takes a sample (first 5%, max 50 MB, cut at a line boundary)
#   - Imports the sample into a throw-away database (never the real one), then drops it
#   - Falls back to the size-based estimate if the sample has no INSERT rows, the
#     account cannot create databases, or the sample fails to import
#   - Projects full time from throughput; multipliers: min=0.7x, likely=1.0x, max=2.0x
#   - Uncompressed size is used for .gz/.zip/.bz2 dumps
#
estimate_import_duration() {
    local sql_file="$1"
    local socket_path="$2"
    local db_host="$3"
    local db_user="$4"
    local db_pass="$5"
    local db_name="$6"

    local total_bytes total_mb
    total_bytes=$(sql_uncompressed_size_bytes "$sql_file")
    total_mb=$((total_bytes / 1048576))

    # Small files: size-based estimate, no benchmark
    if [[ "$total_bytes" -le 0 || "$total_mb" -lt 100 ]]; then
        estimate_heuristic "$total_mb"
        return 0
    fi

    local mysql_bin
    mysql_bin=$(_find_mysql_bin)
    if [[ -z "$mysql_bin" || -z "$db_user" ]]; then
        estimate_heuristic "$total_mb"
        return 0
    fi

    local tmp_dir
    tmp_dir=$(secure_tmpdir) || { estimate_heuristic "$total_mb"; return 0; }

    # Sample: first 5% of the SQL (max 50 MB), cut at a line boundary so it ends on a
    # complete statement; otherwise mysql always exits with a syntax error.
    local sample_size_mb=$((total_mb / 20))
    sample_size_mb=$((sample_size_mb > 50 ? 50 : sample_size_mb))
    local temp_sample="$tmp_dir/bench_sample.sql"
    local bench_log="$tmp_dir/bench.log"
    if ! sql_open_stream "$sql_file" 2>/dev/null | head -c $((sample_size_mb * 1048576)) | sed '$d' > "$temp_sample" 2>/dev/null; then
        rm -f "$temp_sample"
        estimate_heuristic "$total_mb"
        return 0
    fi

    # A single INSERT line larger than the sample leaves only schema statements, which
    # would make the speed look far better than it is: use the size-based estimate.
    if ! LC_ALL=C grep -qE '^(INSERT|REPLACE)[[:space:]]' "$temp_sample"; then
        rm -f "$temp_sample"
        estimate_heuristic "$total_mb"
        return 0
    fi
    local sample_bytes
    sample_bytes=$(_sql_file_size_bytes "$temp_sample")

    # Benchmark in a throw-away database so the real target database is never touched.
    # If the account cannot create databases, skip the benchmark.
    local scratch_db="wpdb_bench_$$"
    _build_mysql_args "$socket_path" "$db_host" "$db_user" "" 5
    local -a admin_args=("${_WPDB_MYSQL_ARGS[@]}")
    if ! MYSQL_PWD="$db_pass" "$mysql_bin" "${admin_args[@]}" -e "CREATE DATABASE \`${scratch_db}\`" &> "$bench_log"; then
        rm -f "$temp_sample" "$bench_log"
        estimate_heuristic "$total_mb"
        return 0
    fi

    _build_mysql_args "$socket_path" "$db_host" "$db_user" "$scratch_db" 5
    local -a bench_args=("${_WPDB_MYSQL_ARGS[@]}")
    local bench_start bench_end bench_success=false
    bench_start=$(_now_ms)
    if MYSQL_PWD="$db_pass" "$mysql_bin" "${bench_args[@]}" < "$temp_sample" &> "$bench_log"; then
        bench_success=true
    fi
    bench_end=$(_now_ms)

    MYSQL_PWD="$db_pass" "$mysql_bin" "${admin_args[@]}" -e "DROP DATABASE IF EXISTS \`${scratch_db}\`" &>/dev/null
    rm -f "$temp_sample" "$bench_log"

    local bench_elapsed_ms=$((bench_end - bench_start))
    # Clock resolution can be 1s; never divide by zero on very fast samples
    [[ "$bench_elapsed_ms" -lt 1 ]] && bench_elapsed_ms=1

    if [[ "$bench_success" != "true" || "$sample_bytes" -le 0 ]]; then
        estimate_heuristic "$total_mb"
        return 0
    fi

    # full_sec = total_bytes / (sample_bytes / elapsed_s), in integer ms math
    local full_import_sec=$((total_bytes * bench_elapsed_ms / (sample_bytes * 1000)))
    local full_import_min=$((full_import_sec / 60))

    # Apply safety multipliers
    local min_min=$((full_import_min * 7 / 10))    # 70% of estimate
    local likely_min=$full_import_min                # 100% of estimate

    min_min=$((min_min > 1 ? min_min : 1))
    likely_min=$((likely_min > 1 ? likely_min : 1))
    local max_min=$((likely_min * 2))                # 200% of estimate (after 1m floor)

    printf "%d %d %d" "$min_min" "$likely_min" "$max_min"
    return 0
}

# ================================================================
# Perform Database Import
# ================================================================
#
# Description:
#   Main import function. Automatically selects the fastest available
#   import method:
#
#     Priority 1 — Unix socket + direct mysql binary
#       Fastest for local dev. Auto-detects the socket path unless
#       CONFIG_MYSQL_SOCKET or CONFIG_USE_SOCKET=false overrides.
#
#     Priority 2 — Direct mysql binary via DB_HOST (TCP)
#       Faster than WP-CLI in many environments when socket is unavailable
#       but mysql client + DB credentials are available.
#
#     Priority 3 — WP-CLI in subshell (enhanced PATH)
#       Standard method. Works on all environments with WP-CLI.
#
#     Priority 4 — WP-CLI direct (restricted env fallback)
#       For environments where sh subshell is unavailable.
#
# Parameters:
#   $1: Path to the SQL file
#   $2: Path to the log file (optional, defaults to $DB_LOG or /tmp/wp_db_import.log)
#
# Returns:
#   0 on success, 1 on failure
#
perform_db_import() {
    local sql_file="$1"
    local log_file="${2:-${DB_LOG:-$(secure_tmpdir)/db_import.log}}"

    if [[ -z "$sql_file" ]]; then
        printf "${RED}❌ Error: No SQL file specified for import.${RESET}\n"
        return 1
    fi

    # --------------------------------------------------------
    # Print file size and estimate import duration
    # --------------------------------------------------------
    local verify_error
    if ! verify_error=$(sql_verify_source "$sql_file" 2>&1); then
        printf "${RED}❌ %s${RESET}\n" "$verify_error"
        return 1
    fi

    local file_size_mb=0
    local file_size_bytes
    file_size_bytes=$(sql_uncompressed_size_bytes "$sql_file")
    file_size_mb=$((file_size_bytes / 1048576))
    if [[ "$file_size_mb" -ge 1024 ]]; then
        printf "\n${CYAN}📊 SQL File: %d GB (~%.1f GB)${RESET}\n" $((file_size_mb / 1024)) "$(echo "scale=1; $file_size_mb / 1024" | bc 2>/dev/null || echo $((file_size_mb / 1024)))"
    else
        printf "\n${CYAN}📊 SQL File: %d MB${RESET}\n" "$file_size_mb"
    fi
    local sql_kind
    sql_kind=$(sql_file_kind "$sql_file")
    if [[ "$sql_kind" != "plain" ]]; then
        printf "${CYAN}🗜️  Compressed dump (%s): streaming without extracting to disk${RESET}\n" "$sql_kind"
    fi

    printf "\n${CYAN}⏳ Importing database...${RESET}\n"
    local import_start_time=$(date +%s)
    local import_success=false
    local import_method=""
    local compat_used=false
    local optimization_mode="${CONFIG_IMPORT_OPTIMIZATIONS:-auto}"
    local use_parallel_import="${CONFIG_PARALLEL_IMPORT:-false}"

    if _is_truthy "$use_parallel_import"; then
        printf "${YELLOW}⚠️  parallel_import=true requested, but generic SQL files are order-sensitive.${RESET}\n"
        printf "${YELLOW}⚠️  Continuing with safe single-stream import for compatibility across environments.${RESET}\n"
    fi

    # --------------------------------------------------------
    # Determine whether to attempt socket import
    # --------------------------------------------------------
    # Respect explicit user opt-out via config: use_socket=false
    local use_socket="${CONFIG_USE_SOCKET:-auto}"
    local socket_path=""

    if [[ "$use_socket" != "false" ]]; then
        # Try to detect a socket (uses cached config override if set)
        local wp_root="${WP_ROOT:-$(find_wordpress_root 2>/dev/null || true)}"
        local config_socket="${CONFIG_MYSQL_SOCKET:-}"

        # Load socket detector if not already loaded
        if ! command -v detect_mysql_socket &>/dev/null; then
            local loader_dir="${LIB_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
            local detector_path="$loader_dir/database/socket_detector.sh"
            if [[ -f "$detector_path" ]]; then
                # shellcheck source=/dev/null
                source "$detector_path"
            fi
        fi

        if command -v detect_mysql_socket &>/dev/null; then
            socket_path=$(detect_mysql_socket "$wp_root" "$config_socket" || true)
        fi
    fi

    # --------------------------------------------------------
    # Method 1: Unix socket via direct mysql binary (fastest)
    # --------------------------------------------------------
    local wp_cli_reason=""

    if [[ "$use_socket" == "false" ]]; then
        wp_cli_reason="socket import disabled in config"
    elif ! command -v detect_mysql_socket &>/dev/null; then
        wp_cli_reason="socket detector unavailable"
    else
        local wp_root="${WP_ROOT:-$(find_wordpress_root 2>/dev/null || true)}"

        # Only proceed if mysql binary is available
        local mysql_available=false
        if _find_mysql_bin >/dev/null 2>&1; then
            mysql_available=true
        else
            wp_cli_reason="mysql client not available for socket import"
        fi

        if [[ "$mysql_available" == "true" ]]; then
            # Get DB credentials from wp-config.php
            local db_host="" db_name="" db_user="" db_pass=""

            if [[ -n "$wp_root" ]] && command -v get_wp_db_credentials &>/dev/null; then
                if get_wp_db_credentials "$wp_root" >/dev/null 2>&1; then
                    db_host="${WP_DB_HOST:-}"
                    db_name="${WP_DB_NAME:-}"
                    db_user="${WP_DB_USER:-}"
                    db_pass="${WP_DB_PASSWORD:-}"
                fi
            fi

            # Run benchmark to estimate import duration
            if [[ -n "$db_name" && -n "$db_user" && "$file_size_mb" -ge 100 ]]; then
                printf "\n${CYAN}⏱️  Benchmarking import speed (this takes 5-10 seconds)...${RESET}\n"
                local estimate_output
                estimate_output=$(estimate_import_duration "$sql_file" "$socket_path" "$db_host" "$db_user" "$db_pass" "$db_name" "$optimization_mode")
                IFS=' ' read -r est_min est_likely est_max <<< "$estimate_output"
                if [[ -n "$est_min" ]]; then
                    printf "${CYAN}📈 Import time estimate:${RESET} ~${est_likely}m (±${est_min}m to ${est_max}m)\n"
                    if [[ "$est_max" -gt 60 ]]; then
                        printf "   ${DIM}(${est_max}m ≈ $(( (est_max + 30) / 60 ))h in worst case)${RESET}\n"
                    fi
                fi
                printf "\n"
            fi

            if [[ -z "$db_name" || -z "$db_user" ]]; then
                if [[ "$use_socket" == "true" ]]; then
                    printf "${RED}❌ Socket import required by config, but database credentials could not be read from wp-config.php.${RESET}\n"
                    return 1
                fi
                wp_cli_reason="database credentials unavailable for socket import"
            else
                local mysql_cli_mode=""

                if [[ -n "$socket_path" ]]; then
                    mysql_cli_mode="socket"
                    printf "${GREEN}⚡ Import method:${RESET} ${CYAN}mysql via Unix socket${RESET}\n"
                    printf "${CYAN}🔌 Found MySQL socket:${RESET} %s\n" "$socket_path"
                elif [[ "$use_socket" == "true" ]]; then
                    printf "${RED}❌ Socket import required by config, but no MySQL socket was detected.${RESET}\n"
                    return 1
                else
                    mysql_cli_mode="mysql-cli"
                    wp_cli_reason="no MySQL socket detected"
                    printf "${GREEN}⚡ Import method:${RESET} ${CYAN}mysql via DB_HOST (TCP)${RESET}\n"
                fi

                local use_optimized_session="false"
                if should_enable_optimized_import_session "$optimization_mode" "$mysql_cli_mode"; then
                    use_optimized_session="true"
                    printf "${CYAN}🚀 Import optimization:${RESET} session checks disabled during load (autocommit/foreign_key/unique)\n"
                fi

                (
                    perform_db_import_via_socket \
                        "$sql_file" "$log_file" \
                        "$socket_path" "$db_host" \
                        "$db_user" "$db_pass" "$db_name" \
                        "$use_optimized_session"
                ) &
                local socket_pid=$!
                show_spinner "$socket_pid" "Importing"
                if wait "$socket_pid"; then
                    import_success=true
                    import_method="$mysql_cli_mode"
                else
                    # Version-specific SQL (collations, DEFINER, ...): retry once with the filter.
                    # Safe to re-run: dumps drop and recreate their tables.
                    if import_error_is_compat_related "$log_file"; then
                        printf "${YELLOW}⚠️  Import hit an SQL compatibility error; retrying with the compatibility filter...${RESET}\n"
                        (
                            perform_db_import_via_socket \
                                "$sql_file" "$log_file" \
                                "$socket_path" "$db_host" \
                                "$db_user" "$db_pass" "$db_name" \
                                "$use_optimized_session" "true"
                        ) &
                        socket_pid=$!
                        show_spinner "$socket_pid" "Importing"
                        if wait "$socket_pid"; then
                            import_success=true
                            import_method="$mysql_cli_mode"
                            compat_used=true
                        fi
                    fi
                    if [[ "$import_success" == "false" ]]; then
                        if [[ "$mysql_cli_mode" == "socket" ]]; then
                            printf "${YELLOW}⚠️  Socket import failed, falling back to WP-CLI...${RESET}\n"
                            wp_cli_reason="socket import failed"
                        else
                            printf "${YELLOW}⚠️  Direct mysql import failed, falling back to WP-CLI...${RESET}\n"
                            wp_cli_reason="direct mysql import failed"
                        fi
                    fi
                fi
            fi
        elif [[ "$use_socket" == "true" ]]; then
            printf "${RED}❌ Socket import required by config, but mysql client is not available.${RESET}\n"
            return 1
        else
            wp_cli_reason="mysql client not available for direct import"
        fi
    fi

    # --------------------------------------------------------
    # Method 2: WP-CLI in subshell (standard / fallback)
    # --------------------------------------------------------
    local wp_cmd="${WP_COMMAND:-wp}"

    if [[ "$import_success" == "false" ]]; then
        if [[ -n "$wp_cli_reason" ]]; then
            printf "${CYAN}ℹ️  Import method:${RESET} WP-CLI ${DIM}(%s)${RESET}\n" "$wp_cli_reason"
        else
            printf "${CYAN}ℹ️  Import method:${RESET} WP-CLI\n"
        fi

        perform_db_import_via_wpcli "$sql_file" "$log_file" false "$wp_cmd" &
        local spinner_pid=$!
        show_spinner "$spinner_pid" "Importing"
        if wait "$spinner_pid"; then
            import_success=true
            import_method="wp-cli"
        elif import_error_is_compat_related "$log_file"; then
            printf "${YELLOW}⚠️  Import hit an SQL compatibility error; retrying with the compatibility filter...${RESET}\n"
            perform_db_import_via_wpcli "$sql_file" "$log_file" true "$wp_cmd" &
            spinner_pid=$!
            show_spinner "$spinner_pid" "Importing"
            if wait "$spinner_pid"; then
                import_success=true
                import_method="wp-cli"
                compat_used=true
            fi
        fi
    fi

    # --------------------------------------------------------
    # Method 3: WP-CLI direct (restricted env)
    # --------------------------------------------------------
    if [[ "$import_success" == "false" ]]; then
        printf "${YELLOW}Fallback: Direct WP-CLI execution...${RESET}\n"
        if perform_db_import_via_wpcli "$sql_file" "$log_file" "$compat_used" "$wp_cmd" direct; then
            import_success=true
            import_method="wp-cli-direct"
        fi
    fi

    # --------------------------------------------------------
    # Result
    # --------------------------------------------------------
    if [[ "$import_success" == "false" ]]; then
        printf "${RED}❌ Database import failed.${RESET}\n"
        # The log lives in a private temp directory removed on exit, so show the cause here
        if [[ -f "$log_file" ]]; then
            LC_ALL=C grep -E '^(ERROR|Error)' "$log_file" 2>/dev/null | head -3 | cut -c1-300 | sed 's/^/   /'
        fi
        return 1
    fi

    local import_end_time=$(date +%s)
    local import_elapsed=$((import_end_time - import_start_time))
    local import_minutes=$((import_elapsed / 60))
    local import_seconds=$((import_elapsed % 60))

    local method_label=""
    case "$import_method" in
        socket)       method_label=" ${CYAN}via socket${RESET}" ;;
        mysql-cli)    method_label=" ${CYAN}via mysql client${RESET}" ;;
        wp-cli*)      method_label=" ${GRAY}via WP-CLI${RESET}" ;;
    esac

    printf "${GREEN}✅ Database import successful!%s ${CYAN}[Completed in %02d:%02d]${RESET}\n" \
        "$method_label" "$import_minutes" "$import_seconds"
    if [[ "$compat_used" == "true" ]]; then
        printf "${YELLOW}ℹ️  Imported with the SQL compatibility filter (collations/DEFINER/engine options adjusted for this server).${RESET}\n"
    fi
    printf "\n"
    return 0
}

# Export functions
export -f _is_truthy
export -f should_enable_optimized_import_session
export -f _now_ms
export -f estimate_import_duration
export -f perform_db_import_via_socket
export -f perform_db_import_via_wpcli
export -f _emit_import_stream
export -f perform_db_import
