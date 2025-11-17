#!/bin/bash

# ===============================================
# WordPress Database Import Tool - Validation Module
# ===============================================
#
# This module provides validation functions for testing the tool's
# functionality and environment compatibility. It's used by the
# private 'wp-db-import validate' command for automated testing.
#
# ===============================================

# Validate tool functionality for testing purposes
validate_tool_functionality() {
    local validation_mode="${1:-basic}"
    local test_type="${2:-}"

    printf "${CYAN}🔍 Validating tool functionality...${RESET}\n"
    printf "${DIM}Mode: $validation_mode${RESET}\n\n"

    local validation_passed=0
    local validation_total=0

    case "$validation_mode" in
        "basic"|"validate")
            validate_basic_functionality
            ;;
        "environment")
            validate_environment_compatibility
            ;;
        "dependencies")
            validate_dependencies
            ;;
        "modules")
            validate_modules
            ;;
        "config")
            validate_configuration_system
            ;;
        "all")
            validate_basic_functionality
            validate_environment_compatibility
            validate_dependencies
            validate_modules
            validate_configuration_system
            ;;
        *)
            printf "${RED}❌ Unknown validation mode: $validation_mode${RESET}\n"
            return 1
            ;;
    esac

    # Return appropriate exit code
    if [[ $validation_passed -eq $validation_total && $validation_total -gt 0 ]]; then
        printf "\n${GREEN}✅ All validations passed ($validation_passed/$validation_total)${RESET}\n"
        return 0
    else
        printf "\n${RED}❌ Some validations failed ($validation_passed/$validation_total)${RESET}\n"
        return 1
    fi
}

# Validate basic tool functionality
validate_basic_functionality() {
    printf "${BOLD}🔧 Basic Functionality Validation${RESET}\n"

    # Check if script can be loaded
    printf "  Checking script loading... "
    if [[ -f "$SCRIPT_DIR/import_wp_db.sh" ]]; then
        printf "${GREEN}✅${RESET}\n"
        ((validation_passed++))
    else
        printf "${RED}❌ Main script not found${RESET}\n"
    fi
    ((validation_total++))

    # Check module loader
    printf "  Checking module loader... "
    if [[ -f "$SCRIPT_DIR/lib/module_loader.sh" ]]; then
        printf "${GREEN}✅${RESET}\n"
        ((validation_passed++))
    else
        printf "${RED}❌ Module loader not found${RESET}\n"
    fi
    ((validation_total++))

    # Check version file
    printf "  Checking version file... "
    if [[ -f "$SCRIPT_DIR/VERSION" && -s "$SCRIPT_DIR/VERSION" ]]; then
        local version=$(cat "$SCRIPT_DIR/VERSION" 2>/dev/null | tr -d '\n\r' | head -1)
        if [[ -n "$version" ]]; then
            printf "${GREEN}✅ (v$version)${RESET}\n"
            ((validation_passed++))
        else
            printf "${YELLOW}⚠️ Version file empty${RESET}\n"
        fi
    else
        printf "${RED}❌ Version file missing or empty${RESET}\n"
    fi
    ((validation_total++))

    # Check function definitions after loading
    printf "  Checking core functions... "
    local core_functions="import_wp_db show_revision_cleanup_if_needed setup_stage_file_proxy"
    local functions_found=0
    local functions_total=0

    for func in $core_functions; do
        ((functions_total++))
        if declare -F "$func" >/dev/null 2>&1; then
            ((functions_found++))
        fi
    done

    if [[ $functions_found -eq $functions_total ]]; then
        printf "${GREEN}✅ ($functions_found/$functions_total)${RESET}\n"
        ((validation_passed++))
    else
        printf "${RED}❌ ($functions_found/$functions_total)${RESET}\n"
    fi
    ((validation_total++))

    printf "\n"
}

# Validate environment compatibility
validate_environment_compatibility() {
    printf "${BOLD}🌍 Environment Compatibility Validation${RESET}\n"

    # Check OS compatibility
    printf "  Checking OS compatibility... "
    local os_type="$(uname -s)"
    case "$os_type" in
        "Darwin"|"Linux"|"FreeBSD"|"OpenBSD"|"NetBSD")
            printf "${GREEN}✅ ($os_type)${RESET}\n"
            ((validation_passed++))
            ;;
        *)
            printf "${YELLOW}⚠️ Untested OS: $os_type${RESET}\n"
            ;;
    esac
    ((validation_total++))

    # Check shell compatibility
    printf "  Checking shell compatibility... "
    if [[ -n "$BASH_VERSION" ]]; then
        local bash_major=$(echo "$BASH_VERSION" | cut -d. -f1)
        if [[ $bash_major -ge 4 ]]; then
            printf "${GREEN}✅ (Bash $BASH_VERSION)${RESET}\n"
            ((validation_passed++))
        elif [[ $bash_major -eq 3 ]]; then
            printf "${YELLOW}⚠️ Old Bash version: $BASH_VERSION${RESET}\n"
            ((validation_passed++))
        else
            printf "${RED}❌ Very old Bash version: $BASH_VERSION${RESET}\n"
        fi
    else
        printf "${RED}❌ Not running in Bash${RESET}\n"
    fi
    ((validation_total++))

    # Check for POSIX compatibility indicators
    printf "  Checking POSIX compatibility... "
    if command -v /bin/sh >/dev/null 2>&1; then
        # Test basic POSIX features
        if /bin/sh -c 'test -n "$HOME" && test -d "$HOME"' >/dev/null 2>&1; then
            printf "${GREEN}✅${RESET}\n"
            ((validation_passed++))
        else
            printf "${RED}❌ POSIX shell issues${RESET}\n"
        fi
    else
        printf "${RED}❌ /bin/sh not found${RESET}\n"
    fi
    ((validation_total++))

    printf "\n"
}

# Validate dependencies
validate_dependencies() {
    printf "${BOLD}📦 Dependencies Validation${RESET}\n"

    local required_commands="wp mysql sed awk grep find"
    local optional_commands="git curl jq bc"

    # Check required dependencies
    for cmd in $required_commands; do
        printf "  Checking $cmd (required)... "
        if command -v "$cmd" >/dev/null 2>&1; then
            local version=""
            case "$cmd" in
                "wp")
                    version=$(wp --version 2>/dev/null | grep -o '[0-9]\+\.[0-9]\+[0-9.]*' || echo "unknown")
                    ;;
                "mysql")
                    version=$(mysql --version 2>/dev/null | grep -o '[0-9]\+\.[0-9]\+[0-9.]*' | head -1 || echo "unknown")
                    ;;
                *)
                    version=$($cmd --version 2>/dev/null | head -1 | grep -o '[0-9]\+\.[0-9]\+[0-9.]*' | head -1 || echo "found")
                    ;;
            esac
            printf "${GREEN}✅ ($version)${RESET}\n"
            ((validation_passed++))
        else
            printf "${RED}❌ Not found${RESET}\n"
        fi
        ((validation_total++))
    done

    # Check optional dependencies
    for cmd in $optional_commands; do
        printf "  Checking $cmd (optional)... "
        if command -v "$cmd" >/dev/null 2>&1; then
            printf "${GREEN}✅${RESET}\n"
        else
            printf "${YELLOW}⚠️ Not found${RESET}\n"
        fi
    done

    printf "\n"
}

# Validate modules
validate_modules() {
    printf "${BOLD}🧩 Modules Validation${RESET}\n"

    local module_dirs="lib/config lib/core lib/database lib/utilities"

    for module_dir in $module_dirs; do
        printf "  Checking $module_dir... "
        local full_path="$SCRIPT_DIR/$module_dir"
        if [[ -d "$full_path" ]]; then
            local module_count=$(find "$full_path" -name "*.sh" | wc -l)
            printf "${GREEN}✅ ($module_count modules)${RESET}\n"
            ((validation_passed++))
        else
            printf "${RED}❌ Directory not found${RESET}\n"
        fi
        ((validation_total++))
    done

    # Check specific important modules
    local important_modules=(
        "lib/config/config_manager.sh"
        "lib/core/utils.sh"
        "lib/database/search_replace.sh"
        "lib/utilities/site_links.sh"
    )

    for module in "${important_modules[@]}"; do
        printf "  Checking $(basename "$module")... "
        if [[ -f "$SCRIPT_DIR/$module" ]]; then
            printf "${GREEN}✅${RESET}\n"
            ((validation_passed++))
        else
            printf "${RED}❌ Not found${RESET}\n"
        fi
        ((validation_total++))
    done

    printf "\n"
}

# Validate configuration system
validate_configuration_system() {
    printf "${BOLD}⚙️ Configuration System Validation${RESET}\n"

    # Check for config examples
    printf "  Checking config examples... "
    local config_examples=(
        "wpdb-import-example-single.conf"
        "wpdb-import-example-multisite.conf"
    )
    local examples_found=0

    for example in "${config_examples[@]}"; do
        if [[ -f "$SCRIPT_DIR/$example" ]]; then
            ((examples_found++))
        fi
    done

    if [[ $examples_found -eq ${#config_examples[@]} ]]; then
        printf "${GREEN}✅ ($examples_found/${#config_examples[@]})${RESET}\n"
        ((validation_passed++))
    else
        printf "${YELLOW}⚠️ ($examples_found/${#config_examples[@]})${RESET}\n"
    fi
    ((validation_total++))

    # Check config functions availability
    printf "  Checking config functions... "
    local config_functions="get_config_file_path validate_config_file"
    local config_functions_found=0
    local config_functions_total=0

    for func in $config_functions; do
        ((config_functions_total++))
        if declare -F "$func" >/dev/null 2>&1; then
            ((config_functions_found++))
        fi
    done

    if [[ $config_functions_found -eq $config_functions_total ]]; then
        printf "${GREEN}✅ ($config_functions_found/$config_functions_total)${RESET}\n"
        ((validation_passed++))
    else
        printf "${RED}❌ ($config_functions_found/$config_functions_total)${RESET}\n"
    fi
    ((validation_total++))

    printf "\n"
}

# Test-specific validation function
validate_for_testing() {
    local test_environment="${1:-development}"

    printf "${CYAN}🧪 Testing Environment Validation${RESET}\n"
    printf "${DIM}Environment: $test_environment${RESET}\n\n"

    # Validate test framework is available
    printf "  Checking test framework... "
    if [[ -f "$SCRIPT_DIR/lib/tests/test_framework.sh" ]]; then
        printf "${GREEN}✅${RESET}\n"
    else
        printf "${RED}❌ Test framework not found${RESET}\n"
        return 1
    fi

    # Check if we can create test directories
    printf "  Checking test directory access... "
    local test_dir="/tmp/wp-db-import-test-$$"
    if mkdir -p "$test_dir" 2>/dev/null; then
        rmdir "$test_dir"
        printf "${GREEN}✅${RESET}\n"
    else
        printf "${RED}❌ Cannot create test directories${RESET}\n"
        return 1
    fi

    # Validate all required functions for testing
    validate_tool_functionality "all" "testing"

    return $?
}

# Quick validation for CI/CD environments
validate_ci_environment() {
    printf "${CYAN}🚀 CI/CD Environment Validation${RESET}\n\n"

    # Basic non-interactive validation
    validate_dependencies
    validate_modules

    # Check if we're in a non-interactive environment
    if [[ ! -t 0 || ! -t 1 ]]; then
        printf "${YELLOW}⚠️ Non-interactive environment detected${RESET}\n"
    fi

    # Check for CI environment variables
    local ci_indicators="CI GITHUB_ACTIONS TRAVIS JENKINS_URL GITLAB_CI"
    for indicator in $ci_indicators; do
        if [[ -n "${!indicator}" ]]; then
            printf "${CYAN}ℹ️ CI Environment detected: $indicator${RESET}\n"
            break
        fi
    done

    return 0
}

# Export validation functions for use by test framework
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    # Being sourced, export functions
    export -f validate_tool_functionality
    export -f validate_basic_functionality
    export -f validate_environment_compatibility
    export -f validate_dependencies
    export -f validate_modules
    export -f validate_configuration_system
    export -f validate_for_testing
    export -f validate_ci_environment
fi
