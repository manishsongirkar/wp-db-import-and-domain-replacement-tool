#!/usr/bin/env bash

# ================================================================
# Watch and Test Script
# ================================================================
#
# Description:
#   Automatically runs the test suite whenever code changes.
#   Useful during development for instant feedback.
#
# Installation:
#   ./watch_and_test.sh
#
# Requirements:
#   - fswatch (macOS: brew install fswatch)
#   - On Linux: inotify-tools (apt install inotify-tools)
#
# Usage:
#   ./watch_and_test.sh               # Watch all changes
#   ./watch_and_test.sh unit          # Watch only unit tests
#   ./watch_and_test.sh socket        # Watch only socket tests
#   ./watch_and_test.sh performance   # Watch only performance tests
#
# ================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$SCRIPT_DIR"

# Determine test filter
TEST_FILTER="${1:-all}"

# Detect available file watcher
WATCHER=""
if command -v fswatch >/dev/null 2>&1; then
    WATCHER="fswatch"
elif command -v inotifywait >/dev/null 2>&1; then
    WATCHER="inotifywait"
else
    printf "\n\033[31m❌ Neither fswatch nor inotify-tools found.\033[0m\n"
    printf "Install one of:\n"
    printf "  macOS: brew install fswatch\n"
    printf "  Linux: apt install inotify-tools\n"
    exit 1
fi

printf "\n\033[36m👀 Watch and Test Mode\033[0m\n"
printf "\033[36mTest Filter: \033[0m\033[1m%s\033[0m\n" "$TEST_FILTER"
printf "\033[36mWatcher: \033[0m\033[1m%s\033[0m\n" "$WATCHER"
printf "\033[33mWatching for changes... (Ctrl+C to stop)\033[0m\n\n"

# Function to run tests
run_tests() {
    printf "\n\033[36m🧪 Running test suite (%s)...\033[0m\n\n" "$TEST_FILTER"
    cd "$PROJECT_ROOT"
    
    if ./run_tests.sh "$TEST_FILTER" 2>&1; then
        printf "\n\033[32m✅ Tests passed!\033[0m\n"
    else
        printf "\n\033[31m❌ Tests failed!\033[0m\n"
    fi
    
    printf "\n\033[33mWatching for changes... (Ctrl+C to stop)\033[0m\n"
}

# Initial test run
run_tests

# Watch for changes
if [[ "$WATCHER" == "fswatch" ]]; then
    # macOS fswatch
    fswatch -o lib/ import_wp_db.sh run_tests.sh \
        | while read; do run_tests; done
else
    # Linux inotifywait
    while inotifywait -r -e modify lib/ import_wp_db.sh run_tests.sh; do
        run_tests
    done
fi
