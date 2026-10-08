#!/usr/bin/env bash

# ================================================================
# MySQL Socket Detector
# ================================================================
#
# Description:
#   Auto-detects the MySQL Unix socket path for faster local database
#   imports. Unix socket connections bypass the TCP/IP stack entirely,
#   providing significantly faster I/O for local MySQL imports.
#
# Detection Strategy (in order of reliability):
#   1. Identify the active dev environment
#   2. Parse DB_HOST from wp-config.php if it embeds a socket path
#   3. Query the running MySQL server via mysqladmin
#   4. Query mysql --print-defaults (reads my.cnf files)
#   5. Inspect running mysqld process arguments
#   6. Probe environment-specific socket paths
#
# Supported environments:
#   - macOS: Homebrew, MySQL.app, MAMP, XAMPP, DBngin, Valet, Local
#   - Linux: Debian/Ubuntu, RHEL/CentOS/Fedora, MariaDB, Arch, Snap
#   - Containers: Lando, DDEV, generic Docker/Podman
#   - WSL: Linux socket paths inside WSL
#
# ================================================================

# ===============================================
# Check if a path is a valid, accessible socket
# ===============================================
_is_valid_socket() {
    local path="$1"
    [[ -z "$path" ]] && return 1
    [[ -S "$path" ]] || return 1
    [[ -w "$path" ]] || return 1
    return 0
}

# ===============================================
# Detect the active local development environment
# ===============================================
detect_dev_environment() {
    local wp_root="${1:-}"

    if [[ -n "${LANDO_INFO:-}" ]] || [[ -n "${LANDO_APP_ROOT:-}" ]]; then
        printf "%s" "lando_inside"
        return 0
    fi

    if [[ "${IS_DDEV_PROJECT:-}" == "true" ]] || [[ -n "${DDEV_SITENAME:-}" ]]; then
        printf "%s" "ddev_inside"
        return 0
    fi

    if [[ -f "/.dockerenv" ]] || [[ -f "/run/.containerenv" ]]; then
        printf "%s" "docker_inside"
        return 0
    fi

    if [[ -n "$wp_root" ]]; then
        if [[ -f "$wp_root/.lando.yml" ]] || [[ -f "$wp_root/.lando.yaml" ]]; then
            printf "%s" "lando_host"
            return 0
        fi

        if [[ -d "$wp_root/.ddev" ]]; then
            printf "%s" "ddev_host"
            return 0
        fi
    fi

    if [[ -f ".lando.yml" ]] || [[ -f ".lando.yaml" ]]; then
        printf "%s" "lando_host"
        return 0
    fi

    if [[ -d ".ddev" ]]; then
        printf "%s" "ddev_host"
        return 0
    fi

    if [[ -d "$HOME/Library/Application Support/Local/run" ]] || [[ -d "$HOME/.config/Local/run" ]]; then
        printf "%s" "local_flywheel"
        return 0
    fi

    if command -v valet >/dev/null 2>&1; then
        printf "%s" "valet"
        return 0
    fi

    if [[ -d "/Applications/MAMP" ]] || [[ -d "/Applications/MAMP PRO" ]]; then
        printf "%s" "mamp"
        return 0
    fi

    if [[ -d "$HOME/Library/Application Support/DBngin" ]]; then
        printf "%s" "dbngin"
        return 0
    fi

    if [[ -d "/opt/homebrew/var/mysql" ]] || [[ -d "/usr/local/var/mysql" ]]; then
        printf "%s" "homebrew"
        return 0
    fi

    if grep -qi "microsoft\|wsl" /proc/version 2>/dev/null; then
        printf "%s" "wsl"
        return 0
    fi

    if [[ -d "/var/run/mysqld" ]] || [[ -d "/var/lib/mysql" ]] || [[ -d "/run/mysqld" ]]; then
        printf "%s" "linux_system"
        return 0
    fi

    printf "%s" "unknown"
    return 0
}

# ===============================================
# Check whether socket probing is inaccessible
# ===============================================
_socket_inaccessible_from_host() {
    local environment="$1"

    case "$environment" in
        lando_host|ddev_host)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

# ===============================================
# Extract socket from DB_HOST in wp-config.php
# ===============================================
_extract_socket_from_wp_config() {
    local wp_config_path="$1"

    if [[ -d "$wp_config_path" ]]; then
        wp_config_path="$wp_config_path/wp-config.php"
    fi

    [[ -f "$wp_config_path" ]] || return 0

    local db_host
    db_host=$(grep -E "define[[:space:]]*\([[:space:]]*['\"]DB_HOST['\"]" "$wp_config_path" 2>/dev/null \
        | awk '
            {
                s = $0
                qc = 0
                start = 0
                for (i = 1; i <= length(s); i++) {
                    c = substr(s, i, 1)
                    if (c == "\"" || c == "\047") {
                        qc++
                        if (qc == 3) {
                            start = i + 1
                        } else if (qc == 4) {
                            print substr(s, start, i - start)
                            exit
                        }
                    }
                }
            }
        ' 2>/dev/null | head -1)

    if [[ "$db_host" == *":"* ]]; then
        local socket_part="${db_host#*:}"
        if [[ "$socket_part" == /* ]]; then
            printf "%s" "$socket_part"
            return 0
        fi
    fi

    return 0
}

# ===============================================
# Detect socket via mysqladmin (queries live server)
# ===============================================
_detect_socket_via_mysqladmin() {
    local mysql_admin_cmd
    mysql_admin_cmd=$(PATH="$PATH:${WPDB_FALLBACK_PATH:-/opt/homebrew/bin:/usr/local/bin}" command -v mysqladmin 2>/dev/null) || return 0

    local socket_path
    socket_path=$(
        "$mysql_admin_cmd" variables 2>/dev/null \
        | grep -E "^\|\s+socket\s+" \
        | awk -F'|' '{print $3}' \
        | tr -d ' '
    )

    if _is_valid_socket "$socket_path"; then
        printf "%s" "$socket_path"
    fi
    return 0
}

# ===============================================
# Detect socket via mysql --print-defaults
# ===============================================
_detect_socket_via_defaults() {
    local mysql_cmd
    mysql_cmd=$(PATH="$PATH:${WPDB_FALLBACK_PATH:-/opt/homebrew/bin:/usr/local/bin}" command -v mysql 2>/dev/null) || return 0

    local socket_path
    socket_path=$(
        "$mysql_cmd" --print-defaults 2>/dev/null \
        | tr ' ' '\n' \
        | grep -E "^--socket=" \
        | head -1 \
        | cut -d'=' -f2-
    )

    if _is_valid_socket "$socket_path"; then
        printf "%s" "$socket_path"
    fi
    return 0
}

# ===============================================
# Detect socket via running mysqld process
# ===============================================
_detect_socket_via_process() {
    local socket_path

    socket_path=$(
        ps aux 2>/dev/null \
        | grep -E '[m]ysqld' \
        | grep -oE '\-\-socket=[^ ]+' \
        | head -1 \
        | cut -d'=' -f2-
    )

    if _is_valid_socket "$socket_path"; then
        printf "%s" "$socket_path"
    fi
    return 0
}

# ===============================================
# Probe Local by Flywheel / Local socket paths
# ===============================================
_probe_local_socket_paths() {
    local base_dir
    local socket_path

    for base_dir in \
        "$HOME/Library/Application Support/Local/run" \
        "$HOME/.config/Local/run"; do
        if [[ -d "$base_dir" ]]; then
            for socket_path in "$base_dir"/*/mysql/mysqld.sock; do
                if _is_valid_socket "$socket_path"; then
                    printf "%s" "$socket_path"
                    return 0
                fi
            done
        fi
    done

    return 0
}

# ===============================================
# Probe DBngin socket paths
# ===============================================
_probe_dbngin_socket_paths() {
    local base_dir="$HOME/Library/Application Support/DBngin/mysql"
    local socket_path

    [[ -d "$base_dir" ]] || return 0

    for socket_path in "$base_dir"/*/data/mysql.sock; do
        if _is_valid_socket "$socket_path"; then
            printf "%s" "$socket_path"
            return 0
        fi
    done

    return 0
}

# ===============================================
# Probe environment-specific socket paths
# ===============================================
_probe_socket_for_environment() {
    local environment="${1:-unknown}"
    local -a candidate_paths=()
    local path

    case "$environment" in
        local_flywheel)
            _probe_local_socket_paths
            return 0
            ;;
        dbngin)
            _probe_dbngin_socket_paths
            return 0
            ;;
        lando_inside|ddev_inside)
            candidate_paths=(
                "/var/run/mysqld/mysqld.sock"
                "/var/lib/mysql/mysql.sock"
                "/tmp/mysql.sock"
            )
            ;;
        docker_inside)
            candidate_paths=(
                "/var/run/mysqld/mysqld.sock"
                "/var/lib/mysql/mysql.sock"
                "/var/run/mariadb/mariadb.sock"
                "/tmp/mysql.sock"
                "/tmp/mysqld.sock"
            )
            ;;
        mamp)
            candidate_paths=(
                "/Applications/MAMP/tmp/mysql/mysql.sock"
                "/Applications/MAMP PRO/tmp/mysql/mysql.sock"
                "/tmp/mysql.sock"
            )
            ;;
        valet|homebrew)
            candidate_paths=(
                "/opt/homebrew/var/mysql/mysql.sock"
                "/opt/homebrew/var/run/mysqld/mysqld.sock"
                "/usr/local/var/mysql/mysql.sock"
                "/usr/local/var/run/mysqld/mysqld.sock"
                "/tmp/mysql.sock"
            )
            ;;
        linux_system|wsl)
            candidate_paths=(
                "/var/run/mysqld/mysqld.sock"
                "/var/lib/mysql/mysql.sock"
                "/var/run/mariadb/mariadb.sock"
                "/var/lib/mysql/mariadb.sock"
                "/run/mysqld/mysqld.sock"
                "/var/snap/mysql/common/var/run/mysqld/mysqld.sock"
                "/tmp/mysql.sock"
                "/tmp/mysqld.sock"
                "/mnt/c/laragon/data/mysql/mysql.sock"
            )
            ;;
        *)
            candidate_paths=(
                "/opt/homebrew/var/mysql/mysql.sock"
                "/opt/homebrew/var/run/mysqld/mysqld.sock"
                "/usr/local/var/mysql/mysql.sock"
                "/usr/local/var/run/mysqld/mysqld.sock"
                "/tmp/mysql.sock"
                "/Applications/MAMP/tmp/mysql/mysql.sock"
                "/Applications/MAMP PRO/tmp/mysql/mysql.sock"
                "/Applications/XAMPP/xamppfiles/var/mysql/mysql.sock"
                "/var/run/mysqld/mysqld.sock"
                "/var/lib/mysql/mysql.sock"
                "/var/run/mariadb/mariadb.sock"
                "/var/lib/mysql/mariadb.sock"
                "/run/mysqld/mysqld.sock"
                "/var/snap/mysql/common/var/run/mysqld/mysqld.sock"
                "/tmp/mysqld.sock"
                "/mnt/c/laragon/data/mysql/mysql.sock"
            )
            ;;
    esac

    for path in "${candidate_paths[@]}"; do
        if _is_valid_socket "$path"; then
            printf "%s" "$path"
            return 0
        fi
    done

    return 0
}

# ===============================================
# Detect MySQL Socket (Primary Public Function)
# ===============================================
detect_mysql_socket() {
    local wp_root="${1:-}"
    local config_override="${2:-}"
    local detected_environment=""

    if [[ -n "$config_override" ]]; then
        if _is_valid_socket "$config_override"; then
            printf "%s" "$config_override"
            return 0
        else
            printf "${YELLOW:-}WARNING: Configured socket path is not accessible: %s${RESET:-}\n" \
                "$config_override" >&2
            printf "${YELLOW:-}WARNING: Falling back to auto-detection...${RESET:-}\n" >&2
        fi
    fi

    detected_environment=$(detect_dev_environment "$wp_root")

    if _socket_inaccessible_from_host "$detected_environment"; then
        if [[ "$detected_environment" == "lando_host" ]]; then
            printf "${CYAN:-}INFO: Lando project detected on host. MySQL socket is inside Docker; using WP-CLI fallback.${RESET:-}\n" >&2
        elif [[ "$detected_environment" == "ddev_host" ]]; then
            printf "${CYAN:-}INFO: DDEV project detected on host. MySQL socket is inside Docker; using WP-CLI fallback.${RESET:-}\n" >&2
        fi
        return 1
    fi

    if [[ -n "$wp_root" ]]; then
        local wp_config_socket
        wp_config_socket=$(_extract_socket_from_wp_config "$wp_root")
        if [[ -n "$wp_config_socket" ]] && _is_valid_socket "$wp_config_socket"; then
            printf "%s" "$wp_config_socket"
            return 0
        fi
    fi

    local admin_socket
    admin_socket=$(_detect_socket_via_mysqladmin)
    if [[ -n "$admin_socket" ]]; then
        printf "%s" "$admin_socket"
        return 0
    fi

    local defaults_socket
    defaults_socket=$(_detect_socket_via_defaults)
    if [[ -n "$defaults_socket" ]]; then
        printf "%s" "$defaults_socket"
        return 0
    fi

    local process_socket
    process_socket=$(_detect_socket_via_process)
    if [[ -n "$process_socket" ]]; then
        printf "%s" "$process_socket"
        return 0
    fi

    local probed_socket
    probed_socket=$(_probe_socket_for_environment "$detected_environment")
    if [[ -n "$probed_socket" ]]; then
        printf "%s" "$probed_socket"
        return 0
    fi

    return 1
}

# ===============================================
# Check if mysql binary is available
# ===============================================
is_mysql_binary_available() {
    local mysql_cmd
    mysql_cmd=$(PATH="$PATH:${WPDB_FALLBACK_PATH:-/opt/homebrew/bin:/usr/local/bin}" command -v mysql 2>/dev/null)
    if [[ -n "$mysql_cmd" && -x "$mysql_cmd" ]]; then
        return 0
    fi
    return 1
}

# ===============================================
# Get mysql binary path
# ===============================================
get_mysql_binary() {
    PATH="$PATH:${WPDB_FALLBACK_PATH:-/opt/homebrew/bin:/usr/local/bin}" command -v mysql 2>/dev/null || true
}

# Export public functions
export -f detect_dev_environment
export -f detect_mysql_socket
export -f is_mysql_binary_available
export -f get_mysql_binary
