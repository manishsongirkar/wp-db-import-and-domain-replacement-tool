#!/usr/bin/env bash

# ================================================================
# CI Workflow and Version Check - Tests
# ================================================================
#
# Description:
#   Tests for issue #11. Checks lib/tests/check_version.sh on a throw-away tree (match,
#   mismatch, tag mismatch, "v" prefix, [Unreleased] heading ignored) and guards the
#   workflow file: it runs on pull requests and main, and every suite it names exists
#   in run_tests.sh.
#
# Usage:
#   ./lib/tests/unit/test_ci_workflow.sh
#
# ================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../test_framework.sh"

_C_ROOT="$PROJECT_ROOT_DIR"
_C_WORK=""

_chk() {
    local desc="$1"; shift
    if "$@" >/dev/null 2>&1; then
        printf "  ✅ %s\n" "$desc"
    else
        printf "  ❌ %s\n" "$desc"
        ((errors++))
    fi
}
_finish() { if [[ "$errors" -eq 0 ]]; then pass_test "$1"; else fail_test "$errors check(s) failed"; fi; }

# Build a tree with VERSION $1 and a CHANGELOG whose newest release is $2
_c_tree() {
    local t="$_C_WORK/tree.$RANDOM"
    mkdir -p "$t/lib/tests"
    cp "$_C_ROOT/lib/tests/check_version.sh" "$t/lib/tests/"
    printf "%s\n" "$1" > "$t/VERSION"
    printf "# Changelog\n\n## [Unreleased]\n\n### Added\n- x\n\n## [%s] - 2026-01-01\n\n## [0.9.0] - 2025-01-01\n" "$2" > "$t/CHANGELOG.md"
    printf "%s" "$t"
}

test_check_version() {
    start_test "check_version.sh compares VERSION, CHANGELOG and tag"
    local errors=0 t
    t=$(_c_tree 1.2.0 1.2.0)
    _chk "matching VERSION and CHANGELOG pass (Unreleased ignored)" bash "$t/lib/tests/check_version.sh"
    _chk "matching tag with v prefix passes"                         bash "$t/lib/tests/check_version.sh" v1.2.0
    _chk "different tag fails"                                       bash -c '! bash "$0" v1.3.0' "$t/lib/tests/check_version.sh"
    t=$(_c_tree 1.3.0 1.2.0)
    _chk "VERSION ahead of CHANGELOG fails"                          bash -c '! bash "$0"' "$t/lib/tests/check_version.sh"
    _chk "real repository VERSION matches CHANGELOG"                 bash "$_C_ROOT/lib/tests/check_version.sh"
    _finish "version check behaves"
}

test_workflow_file() {
    start_test "workflow file is wired to real suites"
    local errors=0 wf="$_C_ROOT/.github/workflows/tests.yml" s
    _chk "workflow exists"                     test -f "$wf"
    _chk "runs on pull_request"                grep -q 'pull_request' "$wf"
    _chk "runs on main"                        grep -q 'branches: \[main\]' "$wf"
    _chk "runs shellcheck"                     grep -q 'shellcheck -S error' "$wf"
    _chk "runs the version check"              grep -q 'check_version.sh' "$wf"
    _chk "uploads reports"                     grep -q 'upload-artifact' "$wf"
    for s in $(sed -n 's/.*run_tests.sh --ci [^|]* \([a-z-]*\)$/\1/p' "$wf" | sort -u); do
        _chk "suite '$s' exists in run_tests.sh" grep -q "[|]${s}[|)]" "$_C_ROOT/run_tests.sh"
    done
    _finish "workflow is consistent"
}

run_ci_workflow_tests() {
    printf "\n${CYAN}${BOLD}🧪 CI Workflow Tests${RESET}\n"
    printf "%s\n\n" "$(printf '=%.0s' {1..50})"
    init_test_session "ci_workflow"
    _C_WORK=$(mktemp -d "${TMPDIR:-/tmp}/wpdb-ci-test.XXXXXX")
    trap 'rm -rf "$_C_WORK"' EXIT

    test_check_version
    test_workflow_file

    finalize_test_session
    return $?
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    run_ci_workflow_tests
fi
