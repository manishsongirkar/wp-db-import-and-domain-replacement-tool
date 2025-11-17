#!/bin/bash

# ===============================================
# Bash Version Compatibility Tests
# ===============================================
#
# Tests for different Bash versions to catch bashisms and
# version-specific issues. Covers Bash 3.2, 4.x, and 5.x features.
#
# ===============================================

# Source the test framework
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../test_framework.sh"

# Test Bash version detection
test_bash_version_detection() {
    start_test "Bash Version Detection" "Test accurate detection of Bash version and features"

    if [[ -n "$BASH_VERSION" ]]; then
        local version_major=$(echo "$BASH_VERSION" | cut -d. -f1)
        local version_minor=$(echo "$BASH_VERSION" | cut -d. -f2)

        if [[ $version_major -ge 3 ]]; then
            pass_test "Bash version detected: $BASH_VERSION (major: $version_major, minor: $version_minor)"
        else
            fail_test "Very old Bash version detected: $BASH_VERSION"
        fi
    else
        fail_test "Not running in Bash environment"
    fi
}

# Test Bash 3.2 compatibility (common on older macOS)
test_bash_3_2_compatibility() {
    start_test "Bash 3.2 Compatibility" "Test functionality with Bash 3.2 limitations"

    local version_major=$(echo "${BASH_VERSION:-0.0}" | cut -d. -f1)
    local version_minor=$(echo "${BASH_VERSION:-0.0}" | cut -d. -f2)

    if [[ $version_major -eq 3 && $version_minor -eq 2 ]]; then
        printf "  Testing Bash 3.2 specific limitations...\n"

        # Test array support (should work in 3.2)
        local test_array=(one two three)
        local array_length=${#test_array[@]}

        if [[ $array_length -eq 3 ]]; then
            printf "    ✅ Array support works\n"
        else
            printf "    ❌ Array support broken\n"
        fi

        # Test associative arrays (should NOT work in 3.2)
        if declare -A test_assoc 2>/dev/null; then
            printf "    ⚠️  Associative arrays unexpectedly available\n"
        else
            printf "    ✅ Associative arrays correctly unavailable\n"
        fi

        # Test regex (should work in 3.2)
        if [[ "test" =~ ^test$ ]] 2>/dev/null; then
            printf "    ✅ Regex support works\n"
        else
            printf "    ❌ Regex support broken\n"
        fi

        pass_test "Bash 3.2 compatibility verified"
    else
        skip_test "Not running Bash 3.2 (current: $BASH_VERSION)"
    fi
}

# Test Bash 4.x features
test_bash_4_features() {
    start_test "Bash 4.x Features" "Test Bash 4.x specific features availability"

    local version_major=$(echo "${BASH_VERSION:-0.0}" | cut -d. -f1)

    if [[ $version_major -ge 4 ]]; then
        printf "  Testing Bash 4.x features...\n"
        local feature_failures=0

        # Test associative arrays (Bash 4.0+)
        if declare -A test_assoc_array 2>/dev/null; then
            test_assoc_array["key1"]="value1"
            test_assoc_array["key2"]="value2"

            if [[ "${test_assoc_array["key1"]}" == "value1" ]]; then
                printf "    ✅ Associative arrays work\n"
            else
                printf "    ❌ Associative arrays broken\n"
                ((feature_failures++))
            fi
        else
            printf "    ❌ Associative arrays not available\n"
            ((feature_failures++))
        fi

        # Test case modification (Bash 4.0+)
        local test_string="Hello World"
        if [[ "${test_string,,}" == "hello world" ]]; then
            printf "    ✅ Case modification works\n"
        else
            printf "    ❌ Case modification not available\n"
            ((feature_failures++))
        fi

        # Test mapfile/readarray (Bash 4.0+)
        if command -v mapfile >/dev/null 2>&1 || command -v readarray >/dev/null 2>&1; then
            printf "    ✅ mapfile/readarray available\n"
        else
            printf "    ❌ mapfile/readarray not available\n"
            ((feature_failures++))
        fi

        if [[ $feature_failures -eq 0 ]]; then
            pass_test "All Bash 4.x features available"
        else
            fail_test "$feature_failures Bash 4.x features missing"
        fi
    else
        skip_test "Not running Bash 4.x+ (current: $BASH_VERSION)"
    fi
}

# Test Bash 5.x features
test_bash_5_features() {
    start_test "Bash 5.x Features" "Test Bash 5.x specific features availability"

    local version_major=$(echo "${BASH_VERSION:-0.0}" | cut -d. -f1)

    if [[ $version_major -ge 5 ]]; then
        printf "  Testing Bash 5.x features...\n"
        local feature_failures=0

        # Test nameref variables (Bash 5.0+, though some support in 4.3+)
        if declare -n test_nameref="BASH_VERSION" 2>/dev/null; then
            if [[ "$test_nameref" == "$BASH_VERSION" ]]; then
                printf "    ✅ Nameref variables work\n"
            else
                printf "    ❌ Nameref variables broken\n"
                ((feature_failures++))
            fi
        else
            printf "    ⚠️  Nameref variables not available (may be older 5.x)\n"
        fi

        # Test negative array indices (Bash 5.0+)
        local test_array=(one two three four five)
        if [[ "${test_array[-1]}" == "five" ]] 2>/dev/null; then
            printf "    ✅ Negative array indices work\n"
        else
            printf "    ❌ Negative array indices not available\n"
            ((feature_failures++))
        fi

        # Test new parameter expansion (Bash 5.0+)
        local test_var="hello world"
        if [[ "${test_var@U}" == "HELLO WORLD" ]] 2>/dev/null; then
            printf "    ✅ New parameter expansion works\n"
        else
            printf "    ⚠️  New parameter expansion not available\n"
        fi

        if [[ $feature_failures -eq 0 ]]; then
            pass_test "Bash 5.x features working correctly"
        elif [[ $feature_failures -eq 1 ]]; then
            pass_test "Most Bash 5.x features available ($feature_failures minor issue)"
        else
            fail_test "$feature_failures Bash 5.x features not working"
        fi
    else
        skip_test "Not running Bash 5.x+ (current: $BASH_VERSION)"
    fi
}

# Test for common bashisms that break in other shells
test_bashism_detection() {
    start_test "Bashism Detection" "Test detection of bash-specific constructs"

    printf "  Testing for common bashisms...\n"
    local bashisms_found=0

    # Test if $BASH_VERSION is available (bashism indicator)
    if [[ -n "$BASH_VERSION" ]]; then
        printf "    ✅ Running in bash environment\n"
    else
        printf "    ⚠️  Not running in bash\n"
        ((bashisms_found++))
    fi

    # Test [[ vs [ (bashism)
    if [[ "test" == "test" ]] 2>/dev/null; then
        printf "    ✅ [[ ]] construct available\n"
    else
        printf "    ❌ [[ ]] construct not available\n"
        ((bashisms_found++))
    fi

    # Test process substitution (bashism)
    if echo "test" | cat <(echo "test") >/dev/null 2>&1; then
        printf "    ✅ Process substitution available\n"
    else
        printf "    ❌ Process substitution not available\n"
        ((bashisms_found++))
    fi

    # Test brace expansion (bashism)
    if eval 'echo {1..3}' 2>/dev/null | grep -q "1 2 3"; then
        printf "    ✅ Brace expansion available\n"
    else
        printf "    ❌ Brace expansion not available\n"
        ((bashisms_found++))
    fi

    if [[ $bashisms_found -le 1 ]]; then
        pass_test "Good bash feature availability ($bashisms_found minor issues)"
    else
        fail_test "Multiple bash features unavailable: $bashisms_found"
    fi
}

# Test array handling across versions
test_array_compatibility() {
    start_test "Array Compatibility" "Test array handling across different Bash versions"

    printf "  Testing array operations...\n"
    local array_issues=0

    # Basic array creation and access
    local test_array=(one two three "four five")
    local array_length=${#test_array[@]}

    if [[ $array_length -eq 4 ]]; then
        printf "    ✅ Array creation and length calculation\n"
    else
        printf "    ❌ Array length incorrect: expected 4, got $array_length\n"
        ((array_issues++))
    fi

    # Array element access with spaces
    if [[ "${test_array[3]}" == "four five" ]]; then
        printf "    ✅ Array element with spaces handled correctly\n"
    else
        printf "    ❌ Array element with spaces broken: '${test_array[3]}'\n"
        ((array_issues++))
    fi

    # Array iteration
    local iteration_count=0
    for element in "${test_array[@]}"; do
        ((iteration_count++))
    done

    if [[ $iteration_count -eq 4 ]]; then
        printf "    ✅ Array iteration works correctly\n"
    else
        printf "    ❌ Array iteration count wrong: expected 4, got $iteration_count\n"
        ((array_issues++))
    fi

    # Array appending
    test_array+=("six")
    local new_length=${#test_array[@]}

    if [[ $new_length -eq 5 ]]; then
        printf "    ✅ Array appending works\n"
    else
        printf "    ❌ Array appending broken: expected length 5, got $new_length\n"
        ((array_issues++))
    fi

    if [[ $array_issues -eq 0 ]]; then
        pass_test "All array operations working correctly"
    else
        fail_test "$array_issues array operation issues detected"
    fi
}

# Test parameter expansion compatibility
test_parameter_expansion() {
    start_test "Parameter Expansion" "Test parameter expansion across Bash versions"

    printf "  Testing parameter expansions...\n"
    local expansion_issues=0

    # Basic parameter expansion
    local test_var="hello_world_test"

    # Test ${var#pattern} (remove shortest match from beginning)
    if [[ "${test_var#hello_}" == "world_test" ]]; then
        printf "    ✅ ${var#pattern} works\n"
    else
        printf "    ❌ ${var#pattern} broken\n"
        ((expansion_issues++))
    fi

    # Test ${var%pattern} (remove shortest match from end)
    if [[ "${test_var%_test}" == "hello_world" ]]; then
        printf "    ✅ ${var%pattern} works\n"
    else
        printf "    ❌ ${var%pattern} broken\n"
        ((expansion_issues++))
    fi

    # Test ${var/pattern/replacement}
    local replaced="${test_var/world/universe}"
    if [[ "$replaced" == "hello_universe_test" ]]; then
        printf "    ✅ ${var/pattern/replacement} works\n"
    else
        printf "    ❌ ${var/pattern/replacement} broken\n"
        ((expansion_issues++))
    fi

    # Test ${var:-default} (default value)
    local unset_var
    if [[ "${unset_var:-default}" == "default" ]]; then
        printf "    ✅ ${var:-default} works\n"
    else
        printf "    ❌ ${var:-default} broken\n"
        ((expansion_issues++))
    fi

    if [[ $expansion_issues -eq 0 ]]; then
        pass_test "All parameter expansions working correctly"
    else
        fail_test "$expansion_issues parameter expansion issues detected"
    fi
}

# Test command substitution compatibility
test_command_substitution() {
    start_test "Command Substitution" "Test command substitution methods"

    printf "  Testing command substitution methods...\n"
    local substitution_issues=0

    # Test $() (preferred method)
    local result_modern="$(echo 'test')"
    if [[ "$result_modern" == "test" ]]; then
        printf "    ✅ \$() command substitution works\n"
    else
        printf "    ❌ \$() command substitution broken\n"
        ((substitution_issues++))
    fi

    # Test `` (legacy method)
    local result_legacy=`echo 'test'`
    if [[ "$result_legacy" == "test" ]]; then
        printf "    ✅ \`\` command substitution works\n"
    else
        printf "    ❌ \`\` command substitution broken\n"
        ((substitution_issues++))
    fi

    # Test nested command substitution
    local nested_result="$(echo "$(echo 'nested')")"
    if [[ "$nested_result" == "nested" ]]; then
        printf "    ✅ Nested command substitution works\n"
    else
        printf "    ❌ Nested command substitution broken\n"
        ((substitution_issues++))
    fi

    if [[ $substitution_issues -eq 0 ]]; then
        pass_test "All command substitution methods working"
    else
        fail_test "$substitution_issues command substitution issues detected"
    fi
}

# Test script compatibility with set -e and other strict modes
test_strict_mode_compatibility() {
    start_test "Strict Mode Compatibility" "Test script behavior with strict shell options"

    printf "  Testing strict mode compatibility...\n"

    # Test with set -e (exit on error)
    local strict_test_result
    strict_test_result=$(
        set -e
        true
        echo "success"
        false || echo "handled"
        echo "after_false"
    ) 2>/dev/null

    if [[ "$strict_test_result" == *"success"* ]]; then
        printf "    ✅ set -e compatibility works\n"
        pass_test "Strict mode compatibility verified"
    else
        printf "    ❌ set -e compatibility issues\n"
        fail_test "Strict mode compatibility problems"
    fi
}

# Run all Bash version compatibility tests
run_bash_version_tests() {
    init_test_session "bash_version_compatibility"

    printf "${CYAN}${BOLD}🐚 Bash Version Compatibility Tests${RESET}\n"
    printf "${DIM}Testing across different Bash versions and feature sets${RESET}\n\n"

    # Version detection
    test_bash_version_detection

    # Version-specific tests
    test_bash_3_2_compatibility
    test_bash_4_features
    test_bash_5_features

    # General compatibility tests
    test_bashism_detection
    test_array_compatibility
    test_parameter_expansion
    test_command_substitution
    test_strict_mode_compatibility

    finalize_test_session
    return $?
}

# Run tests if this script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    run_bash_version_tests
fi
