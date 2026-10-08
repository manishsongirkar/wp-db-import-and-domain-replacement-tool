#!/usr/bin/env bash

# ================================================================
# Setup Pre-Commit Hook
# ================================================================
#
# Description:
#   Sets up the pre-commit git hook to automatically run tests
#   before allowing code commits.
#
# Usage:
#   ./install_pre_commit_hook.sh
#
# ================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GIT_HOOKS_DIR="$SCRIPT_DIR/.git/hooks"
HOOK_SOURCE="$SCRIPT_DIR/hooks/pre-commit"
HOOK_TARGET="$GIT_HOOKS_DIR/pre-commit"

# Check if in a git repository
if [[ ! -d ".git" ]]; then
    printf "\033[31m❌ Not in a git repository. Run this from your project root.\033[0m\n"
    exit 1
fi

# Check if hook source exists
if [[ ! -f "$HOOK_SOURCE" ]]; then
    printf "\033[31m❌ Hook source not found: %s\033[0m\n" "$HOOK_SOURCE"
    exit 1
fi

# Create hooks directory if needed
mkdir -p "$GIT_HOOKS_DIR"

# Copy and make executable
cp "$HOOK_SOURCE" "$HOOK_TARGET"
chmod +x "$HOOK_TARGET"

printf "\n\033[32m✅ Pre-commit hook installed!\033[0m\n"
printf "\033[36mLocation:\033[0m %s\n" "$HOOK_TARGET"
printf "\033[36mBehavior:\033[0m Tests will run before each commit\n"
printf "\033[36mSkip tests:\033[0m git commit --no-verify\n\n"
