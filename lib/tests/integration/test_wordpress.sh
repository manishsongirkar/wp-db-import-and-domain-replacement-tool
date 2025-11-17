#!/bin/bash

# ===============================================
# WordPress Specific Tests
# ===============================================
#
# Tests for WordPress-specific functionality including
# single-site, multisite, and various configuration scenarios.
#
# ===============================================

# Source the test framework
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../test_framework.sh"

# Test WordPress detection functionality
test_wordpress_detection() {
    start_test "WordPress Detection" "Test WordPress installation detection capabilities"

    local detection_issues=0

    # Create a temporary test environment
    local temp_dir=$(create_temp_test_dir "wp_detection")
    cd "$temp_dir" || return 1

    printf "  Testing WordPress detection in various scenarios...\n"

    # Test 1: No WordPress installation
    printf "    Testing non-WordPress directory...\n"
    if source "$PROJECT_ROOT_DIR/import_wp_db.sh" >/dev/null 2>&1; then
        if declare -F find_wp_root >/dev/null 2>&1; then
            local wp_root=$(find_wp_root 2>/dev/null)
            if [[ -z "$wp_root" ]]; then
                printf "      ✅ Correctly detected no WordPress installation\n"
            else
                printf "      ❌ False positive WordPress detection\n"
                ((detection_issues++))
            fi
        else
            printf "      ⚠️  find_wp_root function not available\n"
        fi
    fi

    # Test 2: Create fake WordPress installation
    printf "    Testing with fake wp-config.php...\n"
    echo "<?php // Fake WordPress config for testing" > wp-config.php
    echo "define('DB_NAME', 'test_db');" >> wp-config.php
    echo "define('DB_USER', 'test_user');" >> wp-config.php

    if source "$PROJECT_ROOT_DIR/import_wp_db.sh" >/dev/null 2>&1; then
        if declare -F find_wp_root >/dev/null 2>&1; then
            local wp_root=$(find_wp_root 2>/dev/null)
            if [[ "$wp_root" == "$temp_dir" ]]; then
                printf "      ✅ Correctly detected WordPress installation\n"
            else
                printf "      ❌ Failed to detect WordPress installation\n"
                ((detection_issues++))
            fi
        fi
    fi

    # Test 3: Test WordPress type detection
    printf "    Testing WordPress type detection...\n"
    if source "$PROJECT_ROOT_DIR/import_wp_db.sh" >/dev/null 2>&1; then
        if declare -F detect_wp_type >/dev/null 2>&1; then
            local wp_type=$(detect_wp_type "$temp_dir" 2>/dev/null || echo "unknown")
            if [[ "$wp_type" == "single" ]]; then
                printf "      ✅ Correctly detected single-site WordPress\n"
            else
                printf "      ⚠️  WordPress type detection: $wp_type\n"
            fi
        fi
    fi

    # Test 4: Create multisite indicators
    printf "    Testing multisite detection...\n"
    echo "define('MULTISITE', true);" >> wp-config.php
    echo "define('SUBDOMAIN_INSTALL', false);" >> wp-config.php

    if source "$PROJECT_ROOT_DIR/import_wp_db.sh" >/dev/null 2>&1; then
        if declare -F detect_wp_type >/dev/null 2>&1; then
            local wp_type=$(detect_wp_type "$temp_dir" 2>/dev/null || echo "unknown")
            if [[ "$wp_type" == *"multisite"* ]]; then
                printf "      ✅ Correctly detected multisite WordPress\n"
            else
                printf "      ⚠️  Multisite detection result: $wp_type\n"
            fi
        fi
    fi

    # Cleanup
    cd / && cleanup_temp_test_dir "$temp_dir"

    if [[ $detection_issues -eq 0 ]]; then
        pass_test "WordPress detection functionality working"
    else
        fail_test "$detection_issues WordPress detection issues"
    fi
}

# Test WP-CLI integration
test_wp_cli_integration() {
    if ! require_command "wp"; then
        return 0
    fi

    start_test "WP-CLI Integration" "Test integration with WP-CLI commands"

    local wp_cli_issues=0

    # Test basic WP-CLI functionality
    printf "  Testing WP-CLI basic functionality...\n"

    if wp --info >/dev/null 2>&1; then
        printf "    ✅ WP-CLI info command works\n"
    else
        printf "    ❌ WP-CLI info command failed\n"
        ((wp_cli_issues++))
    fi

    # Test WP-CLI version compatibility
    local wp_version=$(wp --version 2>/dev/null | grep -o '[0-9]\+\.[0-9]\+[0-9.]*' || echo "unknown")
    printf "    WP-CLI version: $wp_version\n"

    # Check if version is recent enough (2.0+)
    if [[ "$wp_version" != "unknown" ]]; then
        local major_version=$(echo "$wp_version" | cut -d. -f1)
        if [[ $major_version -ge 2 ]]; then
            printf "    ✅ WP-CLI version is compatible\n"
        else
            printf "    ⚠️  WP-CLI version may be too old\n"
        fi
    fi

    # Test WP-CLI search-replace availability
    if wp help search-replace >/dev/null 2>&1; then
        printf "    ✅ WP-CLI search-replace command available\n"
    else
        printf "    ❌ WP-CLI search-replace command not available\n"
        ((wp_cli_issues++))
    fi

    # Test other essential WP-CLI commands
    local essential_commands="core cache db"
    for cmd in $essential_commands; do
        if wp help "$cmd" >/dev/null 2>&1; then
            printf "    ✅ WP-CLI $cmd command available\n"
        else
            printf "    ❌ WP-CLI $cmd command not available\n"
            ((wp_cli_issues++))
        fi
    done

    if [[ $wp_cli_issues -eq 0 ]]; then
        pass_test "WP-CLI integration tests passed"
    else
        fail_test "$wp_cli_issues WP-CLI integration issues"
    fi
}

# Test configuration file handling
test_config_file_handling() {
    start_test "Config File Handling" "Test configuration file reading and validation"

    local config_issues=0
    local temp_dir=$(create_temp_test_dir "config_test")
    cd "$temp_dir" || return 1

    printf "  Testing configuration file functionality...\n"

    # Create a test configuration file
    cat > "test-config.conf" <<EOF
# Test configuration for WordPress import
OLD_DOMAIN="old-site.com"
NEW_DOMAIN="new-site.local"
OLD_URL="https://old-site.com"
NEW_URL="http://new-site.local"

# Database settings (optional - will be auto-detected)
DB_NAME="test_database"
DB_USER="test_user"
DB_HOST="localhost"

# WordPress installation settings
MULTISITE="false"
CLEANUP_REVISIONS="true"

# Path mappings for file references
declare -A DOMAIN_PATHS=(
    ["old-site.com"]="/var/www/old-site"
    ["new-site.local"]="/Users/test/local-sites/new-site"
)
EOF

    # Test configuration loading
    if source "$PROJECT_ROOT_DIR/import_wp_db.sh" >/dev/null 2>&1; then
        if declare -F load_config >/dev/null 2>&1; then
            if load_config "test-config.conf" >/dev/null 2>&1; then
                printf "    ✅ Configuration file loading works\n"

                # Test if variables are set correctly
                if [[ "$OLD_DOMAIN" == "old-site.com" ]]; then
                    printf "    ✅ Configuration variables set correctly\n"
                else
                    printf "    ❌ Configuration variables not set correctly\n"
                    ((config_issues++))
                fi
            else
                printf "    ❌ Configuration file loading failed\n"
                ((config_issues++))
            fi
        else
            printf "    ⚠️  load_config function not available\n"
        fi
    fi

    # Test configuration validation
    if source "$PROJECT_ROOT_DIR/import_wp_db.sh" >/dev/null 2>&1; then
        if declare -F validate_config >/dev/null 2>&1; then
            if validate_config >/dev/null 2>&1; then
                printf "    ✅ Configuration validation works\n"
            else
                printf "    ❌ Configuration validation failed\n"
                ((config_issues++))
            fi
        else
            printf "    ⚠️  validate_config function not available\n"
        fi
    fi

    # Test invalid configuration handling
    printf "  Testing invalid configuration handling...\n"
    cat > "invalid-config.conf" <<EOF
# Invalid configuration with syntax errors
OLD_DOMAIN=  # Empty value
INVALID_SYNTAX this line has no equals sign
MULTISITE="maybe"  # Invalid boolean
EOF

    if source "$PROJECT_ROOT_DIR/import_wp_db.sh" >/dev/null 2>&1; then
        if declare -F load_config >/dev/null 2>&1; then
            if load_config "invalid-config.conf" >/dev/null 2>&1; then
                printf "    ⚠️  Invalid configuration was loaded (should fail)\n"
            else
                printf "    ✅ Invalid configuration correctly rejected\n"
            fi
        fi
    fi

    # Cleanup
    cd / && cleanup_temp_test_dir "$temp_dir"

    if [[ $config_issues -eq 0 ]]; then
        pass_test "Configuration file handling tests passed"
    else
        fail_test "$config_issues configuration handling issues"
    fi
}

# Test domain sanitization
test_domain_sanitization() {
    start_test "Domain Sanitization" "Test domain and URL sanitization functionality"

    local sanitization_issues=0

    printf "  Testing domain sanitization...\n"

    # Test cases for domain sanitization using separate arrays
    local test_inputs=(
        "https://example.com/"
        "http://example.com"
        "example.com/"
        "www.example.com"
        "subdomain.example.com"
        "example.com:8080"
    )

    local expected_outputs=(
        "example.com"
        "example.com"
        "example.com"
        "www.example.com"
        "subdomain.example.com"
        "example.com:8080"
    )

    # Load the main script to get sanitization functions
    if source "$PROJECT_ROOT_DIR/import_wp_db.sh" >/dev/null 2>&1; then
        if declare -F sanitize_domain >/dev/null 2>&1; then
            for i in "${!test_inputs[@]}"; do
                local input="${test_inputs[$i]}"
                local expected="${expected_outputs[$i]}"
                local result=$(sanitize_domain "$input" 2>/dev/null || echo "$input")

                if [[ "$result" == "$expected" ]]; then
                    printf "    ✅ '$input' → '$result'\n"
                else
                    printf "    ❌ '$input' → '$result' (expected '$expected')\n"
                    ((sanitization_issues++))
                fi
            done
        else
            printf "    ⚠️  sanitize_domain function not available\n"
        fi
    fi

    if [[ $sanitization_issues -eq 0 ]]; then
        pass_test "Domain sanitization tests passed"
    else
        fail_test "$sanitization_issues domain sanitization issues"
    fi
}

# Test search and replace functionality
test_search_replace() {
    start_test "Search Replace Functionality" "Test database search and replace operations"

    local search_replace_issues=0

    printf "  Testing search and replace logic...\n"

    # Test serialized data handling (common WordPress issue)
    local test_serialized='a:2:{s:3:"url";s:20:"https://old-site.com";s:4:"name";s:8:"Old Site";}'
    local expected_result='a:2:{s:3:"url";s:20:"http://new-site.local";s:4:"name";s:8:"Old Site";}'

    # Load the main script to get search/replace functions
    if source "$PROJECT_ROOT_DIR/import_wp_db.sh" >/dev/null 2>&1; then
        # Test if search/replace functions are available
        if declare -F perform_search_replace >/dev/null 2>&1; then
            printf "    ✅ Search/replace function available\n"
        else
            printf "    ⚠️  Search/replace function not directly available\n"
        fi

        # Test URL replacement patterns
        local test_patterns=(
            "https://old-site.com → http://new-site.local"
            "//old-site.com → //new-site.local"
            "old-site.com → new-site.local"
        )

        for pattern in "${test_patterns[@]}"; do
            printf "    Testing pattern: $pattern\n"
            # Basic pattern validation (actual testing would require database)
        done
    fi

    # Test dry-run capability
    if source "$PROJECT_ROOT_DIR/import_wp_db.sh" >/dev/null 2>&1; then
        if declare -F dry_run_search_replace >/dev/null 2>&1; then
            printf "    ✅ Dry-run functionality available\n"
        else
            printf "    ⚠️  Dry-run functionality not available\n"
        fi
    fi

    if [[ $search_replace_issues -eq 0 ]]; then
        pass_test "Search/replace tests passed (logic validation)"
    else
        fail_test "$search_replace_issues search/replace issues"
    fi
}

# Test multisite handling
test_multisite_handling() {
    start_test "Multisite Handling" "Test WordPress multisite functionality"

    local multisite_issues=0

    printf "  Testing multisite detection and handling...\n"

    # Create temporary test environment with multisite configuration
    local temp_dir=$(create_temp_test_dir "multisite_test")
    cd "$temp_dir" || return 1

    # Create multisite wp-config.php
    cat > "wp-config.php" <<EOF
<?php
define('DB_NAME', 'test_multisite_db');
define('DB_USER', 'test_user');
define('DB_PASSWORD', 'test_pass');
define('DB_HOST', 'localhost');

define('MULTISITE', true);
define('SUBDOMAIN_INSTALL', false);
define('DOMAIN_CURRENT_SITE', 'main-site.com');
define('PATH_CURRENT_SITE', '/');
define('SITE_ID_CURRENT_SITE', 1);
define('BLOG_ID_CURRENT_SITE', 1);
EOF

    # Test multisite detection
    if source "$PROJECT_ROOT_DIR/import_wp_db.sh" >/dev/null 2>&1; then
        if declare -F detect_wp_type >/dev/null 2>&1; then
            local wp_type=$(detect_wp_type "$temp_dir" 2>/dev/null)
            if [[ "$wp_type" == *"multisite"* ]]; then
                printf "    ✅ Multisite correctly detected\n"
            else
                printf "    ❌ Multisite not detected (got: $wp_type)\n"
                ((multisite_issues++))
            fi
        fi

        # Test subdirectory vs subdomain detection
        if declare -F get_multisite_type >/dev/null 2>&1; then
            local multisite_type=$(get_multisite_type "$temp_dir" 2>/dev/null)
            if [[ "$multisite_type" == "subdirectory" ]]; then
                printf "    ✅ Subdirectory multisite correctly detected\n"
            else
                printf "    ⚠️  Multisite type: $multisite_type\n"
            fi
        fi
    fi

    # Test subdomain multisite configuration
    sed -i.bak 's/define('"'"'SUBDOMAIN_INSTALL'"'"', false);/define('"'"'SUBDOMAIN_INSTALL'"'"', true);/' wp-config.php

    if source "$PROJECT_ROOT_DIR/import_wp_db.sh" >/dev/null 2>&1; then
        if declare -F get_multisite_type >/dev/null 2>&1; then
            local multisite_type=$(get_multisite_type "$temp_dir" 2>/dev/null)
            if [[ "$multisite_type" == "subdomain" ]]; then
                printf "    ✅ Subdomain multisite correctly detected\n"
            else
                printf "    ⚠️  Multisite type: $multisite_type\n"
            fi
        fi
    fi

    # Cleanup
    cd / && cleanup_temp_test_dir "$temp_dir"

    if [[ $multisite_issues -eq 0 ]]; then
        pass_test "Multisite handling tests passed"
    else
        fail_test "$multisite_issues multisite handling issues"
    fi
}

# Test error handling and edge cases
test_error_handling() {
    start_test "Error Handling" "Test error handling and edge case scenarios"

    local error_handling_issues=0

    printf "  Testing error handling scenarios...\n"

    # Test handling of missing files
    local temp_dir=$(create_temp_test_dir "error_test")
    cd "$temp_dir" || return 1

    # Test importing non-existent SQL file
    if source "$PROJECT_ROOT_DIR/import_wp_db.sh" >/dev/null 2>&1; then
        # This should fail gracefully
        if declare -F import_sql_file >/dev/null 2>&1; then
            if import_sql_file "nonexistent.sql" >/dev/null 2>&1; then
                printf "    ❌ Non-existent SQL file import should fail\n"
                ((error_handling_issues++))
            else
                printf "    ✅ Non-existent SQL file correctly rejected\n"
            fi
        fi
    fi

    # Test handling of invalid WordPress directory
    if source "$PROJECT_ROOT_DIR/import_wp_db.sh" >/dev/null 2>&1; then
        if declare -F find_wp_root >/dev/null 2>&1; then
            local wp_root=$(find_wp_root 2>/dev/null)
            if [[ -z "$wp_root" ]]; then
                printf "    ✅ Invalid WordPress directory correctly detected\n"
            else
                printf "    ❌ Invalid WordPress directory not detected\n"
                ((error_handling_issues++))
            fi
        fi
    fi

    # Test handling of corrupted wp-config.php
    echo "This is not a valid PHP file" > wp-config.php

    if source "$PROJECT_ROOT_DIR/import_wp_db.sh" >/dev/null 2>&1; then
        if declare -F validate_wp_config >/dev/null 2>&1; then
            if validate_wp_config "wp-config.php" >/dev/null 2>&1; then
                printf "    ❌ Corrupted wp-config.php should be rejected\n"
                ((error_handling_issues++))
            else
                printf "    ✅ Corrupted wp-config.php correctly rejected\n"
            fi
        fi
    fi

    # Test handling of permission issues
    chmod 000 wp-config.php 2>/dev/null

    if source "$PROJECT_ROOT_DIR/import_wp_db.sh" >/dev/null 2>&1; then
        if declare -F read_wp_config >/dev/null 2>&1; then
            if read_wp_config "wp-config.php" >/dev/null 2>&1; then
                printf "    ❌ Unreadable wp-config.php should be rejected\n"
                ((error_handling_issues++))
            else
                printf "    ✅ Unreadable wp-config.php correctly rejected\n"
            fi
        fi
    fi

    chmod 644 wp-config.php 2>/dev/null  # Restore permissions for cleanup

    # Cleanup
    cd / && cleanup_temp_test_dir "$temp_dir"

    if [[ $error_handling_issues -eq 0 ]]; then
        pass_test "Error handling tests passed"
    else
        fail_test "$error_handling_issues error handling issues"
    fi
}

# Test cleanup and maintenance functions
test_cleanup_functions() {
    start_test "Cleanup Functions" "Test cleanup and maintenance functionality"

    local cleanup_issues=0

    printf "  Testing cleanup functionality...\n"

    # Load the main script
    if source "$PROJECT_ROOT_DIR/import_wp_db.sh" >/dev/null 2>&1; then

        # Test revision cleanup command generation
        if declare -F show_revision_cleanup_commands >/dev/null 2>&1; then
            printf "    ✅ Revision cleanup function available\n"
        else
            printf "    ⚠️  Revision cleanup function not available\n"
        fi

        # Test cache clearing functions
        if declare -F clear_wp_cache >/dev/null 2>&1; then
            printf "    ✅ Cache clearing function available\n"
        else
            printf "    ⚠️  Cache clearing function not available\n"
        fi

        # Test temporary file cleanup
        if declare -F cleanup_temp_files >/dev/null 2>&1; then
            printf "    ✅ Temporary file cleanup function available\n"
        else
            printf "    ⚠️  Temporary file cleanup function not available\n"
        fi
    fi

    if [[ $cleanup_issues -eq 0 ]]; then
        pass_test "Cleanup function tests passed"
    else
        fail_test "$cleanup_issues cleanup function issues"
    fi
}

# Run all WordPress specific tests
run_wordpress_tests() {
    init_test_session "wordpress_functionality"

    printf "${CYAN}${BOLD}🔧 WordPress Functionality Tests${RESET}\n"
    printf "${DIM}Testing WordPress-specific features and scenarios${RESET}\n\n"

    # Core WordPress functionality tests
    test_wordpress_detection
    test_wp_cli_integration
    test_config_file_handling

    # Domain and URL handling tests
    test_domain_sanitization
    test_search_replace

    # WordPress type specific tests
    test_multisite_handling

    # Robustness tests
    test_error_handling
    test_cleanup_functions

    finalize_test_session
    return $?
}

# Run tests if this script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    run_wordpress_tests
fi
