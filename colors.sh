#!/bin/bash

# Centralized Color Management for WordPress DB Import Tool
# This file defines all color codes used across the project
# Usage: eval "$(colors)" to load colors into the current scope

colors() {
  local RED='\033[0;31m'
  local GREEN='\033[0;32m'
  local YELLOW='\033[1;33m'
  local BLUE='\033[0;34m'
  local CYAN='\033[0;36m'
  local WHITE='\033[1;37m'
  local BOLD='\033[1m'
  local RESET='\033[0m'
  local NC='\033[0m'  # No Color - alias for RESET

  # Only output declarations if stdout is being captured (command substitution)
  # This prevents unwanted output when function is called directly
  if [[ -t 1 ]]; then
    # stdout is a terminal, likely called directly - don't output
    return 0
  else
    # stdout is being captured (like in command substitution) - output declarations
    declare -p RED GREEN YELLOW BLUE CYAN WHITE BOLD RESET NC
  fi
}
