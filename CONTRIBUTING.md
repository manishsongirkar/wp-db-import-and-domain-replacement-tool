# 🤝 Contributing to WordPress Database Import & Domain Replacement Tool

Thank you for your interest in contributing to this project! This document provides guidelines and information for contributors.

## 📋 Table of Contents

- [🎯 Project Overview](#-project-overview)
- [🌟 Types of Contributions](#-types-of-contributions)
- [🚀 Getting Started](#-getting-started)
- [💻 Development Environment](#-development-environment)
- [📝 Coding Standards](#-coding-standards)
- [🧪 Testing Guidelines](#-testing-guidelines)
- [📖 Documentation Standards](#-documentation-standards)
- [🔄 Pull Request Process](#-pull-request-process)
- [🐛 Bug Reports](#-bug-reports)
- [💡 Feature Requests](#-feature-requests)
- [📁 Project Structure](#-project-structure)
- [🛡️ Security Guidelines](#-security-guidelines)
- [🏷️ Commit Message Guidelines](#-commit-message-guidelines)
- [📞 Getting Help](#-getting-help)

## 🎯 Project Overview

This is a robust bash utility for WordPress database imports and domain/URL replacements, designed for migrating environments (production to local/staging). The tool supports:

- **Single-site installations**
- **Multisite subdomain networks**
- **Multisite subdirectory networks**
- **High-speed bulk operations** via WP-CLI and xargs
- **Interactive configuration** with comprehensive validation
- **Modular architecture** with separate utility scripts

## 🌟 Types of Contributions

We welcome various types of contributions:

### 🔧 Code Contributions
- **Bug fixes** in existing functionality
- **New features** that enhance the tool's capabilities
- **Performance improvements** for large database operations
- **Cross-platform compatibility** enhancements
- **Error handling** improvements

### 📚 Documentation
- **README improvements** with clearer examples
- **Code comments** for complex functions
- **Usage tutorials** for specific scenarios
- **API documentation** for public functions

### 🧪 Testing & Quality Assurance
- **Manual testing** on different WordPress configurations
- **Edge case testing** with various database sizes
- **Cross-platform testing** (macOS/Linux)
- **Performance testing** with large datasets

### 🎨 User Experience
- **CLI interface improvements**
- **Better error messages** and user feedback
- **Progress indicators** for long operations
- **Accessibility improvements**

## 🚀 Getting Started

### 1. Fork the Repository

```bash
# Fork the repository on GitHub, then clone your fork
git clone https://github.com/YOUR_USERNAME/wp-db-import-and-domain-replacement-tool.git
cd wp-db-import-and-domain-replacement-tool
```

### 2. Set Up Development Environment

```bash
# Add upstream remote
git remote add upstream https://github.com/manishsongirkar/wp-db-import-and-domain-replacement-tool.git

# Create a feature branch
git checkout -b feature/your-feature-name
```

### 3. Make Your Changes

```bash
# Make your changes and test them
# Follow the coding standards outlined below
```

### 4. Submit Pull Request

```bash
# Push your changes
git push origin feature/your-feature-name

# Open a pull request on GitHub
```

## 💻 Development Environment

### Prerequisites

| Requirement | Version | Notes |
|-------------|---------|-------|
| **Bash** | 4.0+ | For advanced array handling |
| **WP-CLI** | Latest | WordPress command line tool |
| **Git** | 2.0+ | Version control |
| **Text Editor** | Any | VS Code, vim, nano, etc. |

### Development Setup

```bash
# Install WP-CLI (if not already installed)
curl -O https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar
chmod +x wp-cli.phar
sudo mv wp-cli.phar /usr/local/bin/wp

# Verify installation
wp --info

# Set up a test WordPress environment
# You'll need this for testing your changes
```

### Testing Environment

For testing, you should have:

1. **Local WordPress installation** (single-site and multisite)
2. **Sample SQL dumps** of various sizes
3. **Different domain configurations** to test
4. **Access to phpMyAdmin or MySQL CLI** for verification

## 📝 Coding Standards

### Bash Script Guidelines

#### 1. **Function Structure**

```bash
# ✅ Good: Well-documented function with error handling
my_function() {
    local param1="$1"
    local param2="$2"

    # Validate inputs
    if [[ -z "$param1" ]]; then
        printf "${RED}❌ Error: Parameter required${RESET}\n" >&2
        return 1
    fi

    # Function logic here
    return 0
}
```

#### 2. **Variable Naming**

```bash
# ✅ Good: Descriptive names with local scope
local sql_file_path="/path/to/file.sql"
local search_domain="example.com"
local replace_domain="local.test"

# ❌ Bad: Unclear or global variables
file="/path/to/file.sql"
s="example.com"
r="local.test"
```

#### 3. **Error Handling**

```bash
# ✅ Good: Comprehensive error handling
if ! command -v wp >/dev/null 2>&1; then
    printf "${RED}❌ WP-CLI not found. Please install WP-CLI first.${RESET}\n" >&2
    return 1
fi

# ✅ Good: Validate file existence
if [[ ! -f "$sql_file" ]]; then
    printf "${RED}❌ File '%s' not found.${RESET}\n" "$sql_file" >&2
    printf "${YELLOW}💡 Hint:${RESET} Place the file in current directory.\n" >&2
    return 1
fi
```

#### 4. **Output Formatting**

```bash
# ✅ Good: Consistent colored output
printf "${GREEN}✅ Operation successful${RESET}\n"
printf "${YELLOW}⚠️ Warning message${RESET}\n"
printf "${RED}❌ Error occurred${RESET}\n"
printf "${CYAN}ℹ️ Information${RESET}\n"

# ✅ Good: Use emojis and clear structure
printf "${CYAN}🔄 Starting domain replacement...${RESET}\n"
printf "  ${YELLOW}Step 1:${RESET} Validating inputs\n"
printf "  ${YELLOW}Step 2:${RESET} Processing database\n"
```

### 5. **Security Best Practices**

```bash
# ✅ Good: Use absolute paths
local wp_root
wp_root=$(cd "$(dirname "$0")" && pwd)

# ✅ Good: Validate inputs
sanitize_domain() {
    local domain="$1"
    # Remove protocols and validate
    domain="${domain#http://}"
    domain="${domain#https://}"
    echo "$domain"
}

# ✅ Good: Use proper quoting
execute_wp_cli() {
    "$WP_COMMAND" "$@"
}
```

## 🧪 Testing Guidelines

### Manual Testing Checklist

Before submitting a pull request, test your changes with:

#### Single Site Testing
- [ ] **Small database** (< 10MB)
- [ ] **Medium database** (10-100MB)
- [ ] **Large database** (> 100MB)
- [ ] **Domain with www** (www.example.com)
- [ ] **Domain without www** (example.com)
- [ ] **Subdirectory installation** (/blog/)
- [ ] **Dry-run mode** verification
- [ ] **Revision cleanup** (both accept/decline)

#### Multisite Testing
- [ ] **Subdomain multisite** (blog.example.com)
- [ ] **Subdirectory multisite** (/blog/, /shop/)
- [ ] **Mixed domain mapping** scenarios
- [ ] **Large multisite** (10+ sites)
- [ ] **Network admin** functionality
- [ ] **Stage file proxy** integration

#### Edge Cases
- [ ] **Empty SQL file**
- [ ] **Corrupted SQL file**
- [ ] **Non-existent domains**
- [ ] **Special characters** in domains
- [ ] **Very long domain names**
- [ ] **Permission errors**
- [ ] **Disk space limitations**

### Testing Commands

```bash
# Test basic functionality
cd /path/to/test/wordpress
source /path/to/import_wp_db.sh
import_wp_db

# Test individual functions
show_file_size "test.sql"
show_local_site_links
show_revision_cleanup_commands

# Test error conditions
show_file_size ""                    # Empty path
show_file_size "/nonexistent/file"   # Missing file
```

## 📖 Documentation Standards

### Function Documentation

```bash
# 📊 Display file size in human-readable format
# Usage: show_file_size "/path/to/file"
# Arguments:
#   $1 - File path (required)
# Returns:
#   0 on success, 1 on error
# Output:
#   Prints formatted file size (TB, GB, MB, KB)
show_file_size() {
    # Function implementation
}
```

### README Updates

When adding new features:

1. **Update features list** with clear descriptions
2. **Add usage examples** with terminal output
3. **Update configuration options** table
4. **Add troubleshooting** notes if needed
5. **Update requirements** if dependencies change

## 🔄 Pull Request Process

### Before Submitting

1. **✅ Test thoroughly** on multiple scenarios
2. **✅ Update documentation** as needed
3. **✅ Follow coding standards**
4. **✅ Add clear commit messages**
5. **✅ Ensure no debugging code** remains

### PR Template

```markdown
## Description
Brief description of changes made.

## Type of Change
- [ ] 🐛 Bug fix (non-breaking change which fixes an issue)
- [ ] ✨ New feature (non-breaking change which adds functionality)
- [ ] 💥 Breaking change (fix or feature that would cause existing functionality to not work as expected)
- [ ] 📚 Documentation update
- [ ] 🔧 Maintenance/refactoring

## Testing Performed
- [ ] Single site testing
- [ ] Multisite testing
- [ ] Edge case testing
- [ ] Cross-platform testing

## Checklist
- [ ] Code follows project style guidelines
- [ ] Self-review completed
- [ ] Documentation updated
- [ ] Changes tested thoroughly
```

## 🐛 Bug Reports

### Creating Effective Bug Reports

Use this template for bug reports:

```markdown
**Bug Description**
Clear description of the bug.

**Steps to Reproduce**
1. Navigate to WordPress directory
2. Run `import_wp_db`
3. Enter domain: example.com
4. See error

**Expected Behavior**
What should have happened.

**Actual Behavior**
What actually happened.

**Environment**
- OS: macOS 13.0 / Ubuntu 22.04
- Bash version: 5.1
- WP-CLI version: 2.8.1
- WordPress type: Single site / Multisite
- Database size: ~50MB

**Error Logs**
```bash
# Paste relevant error messages or log contents
```

**Additional Context**
Any other relevant information.
```

## 💡 Feature Requests

### Feature Request Template

```markdown
**Feature Description**
Clear description of the proposed feature.

**Problem It Solves**
What problem does this feature address?

**Proposed Solution**
How should this feature work?

**Alternatives Considered**
What other solutions did you consider?

**Additional Context**
Any other relevant information or mockups.
```

## 📁 Project Structure

Understanding the project structure helps with contributions:

```
wp-db-import-and-domain-replacement-tool/
├── import_wp_db.sh                    # Main script with core functionality
├── colors.sh                         # Centralized color management
├── setup-stage-file-proxy.sh         # Stage File Proxy plugin setup
├── show_local_site_links.sh          # Display local site access links
├── show_revision_cleanup_commands.sh # Generate MySQL cleanup commands
├── README.md                         # Comprehensive documentation
├── LICENSE                           # MIT license
├── .gitignore                        # Git ignore patterns
└── CONTRIBUTING.md                   # This file
```

### Core Files

- **`import_wp_db.sh`** - Main entry point, contains the primary `import_wp_db()` function
- **`colors.sh`** - Color definitions used across all scripts
- **Utility scripts** - Modular functions for specific tasks

### Adding New Features

1. **Small features** - Add to existing files with appropriate comments
2. **New utility functions** - Consider separate files for reusability
3. **Breaking changes** - Discuss in an issue first

## 🛡️ Security Guidelines

### Input Validation

```bash
# ✅ Always validate user inputs
validate_domain() {
    local domain="$1"

    # Check length
    if [[ ${#domain} -gt 253 ]]; then
        return 1
    fi

    # Check for invalid characters
    if [[ ! "$domain" =~ ^[a-zA-Z0-9.-]+$ ]]; then
        return 1
    fi

    return 0
}
```

### File Operations

```bash
# ✅ Use absolute paths
local temp_file="/tmp/wp_import_$$.log"

# ✅ Set proper permissions
touch "$temp_file"
chmod 600 "$temp_file"

# ✅ Clean up resources
trap 'rm -f "$temp_file"' EXIT
```

### SQL Safety

```bash
# ✅ Never execute user input directly
# ✅ Use WP-CLI for database operations
# ✅ Validate SQL file integrity before import
```

## 🏷️ Commit Message Guidelines

Follow the [Conventional Commits](https://www.conventionalcommits.org/) specification:

### Commit Types

- **feat:** New feature
- **fix:** Bug fix
- **docs:** Documentation changes
- **style:** Code style changes (no logic changes)
- **refactor:** Code refactoring
- **perf:** Performance improvements
- **test:** Adding or updating tests
- **chore:** Maintenance tasks

### Examples

```bash
# ✅ Good commit messages
feat(utils): add file size display utility function
fix(multisite): resolve domain mapping for subdirectories
docs(readme): update installation instructions
refactor(cleanup): extract revision cleanup to separate function
perf(import): optimize large database import process

# ❌ Bad commit messages
update stuff
fix bug
changes
work in progress
```

### Commit Message Format

```
<type>(<scope>): <description>

<body>

<footer>
```

Example:
```
feat(utils): add reusable file size display utility

- Add show_file_size() function with TB/GB/MB/KB formatting
- Refactor inline file size code to use new utility
- Add comprehensive error handling for missing files
- Support both macOS and Linux stat commands

Closes #123
```

## 📞 Getting Help

### Communication Channels

- **🐛 Issues** - For bug reports and feature requests
- **💬 Discussions** - For questions and general discussion
- **📧 Email** - For security issues: [maintainer email]

### Before Asking for Help

1. **📖 Read the documentation** - Check README.md thoroughly
2. **🔍 Search existing issues** - Your question might be answered already
3. **🧪 Test with minimal setup** - Isolate the problem
4. **📋 Gather information** - Environment details, error logs, etc.

### Getting Support

When asking for help:

1. **Be specific** about the problem
2. **Provide context** about your environment
3. **Include relevant logs** or error messages
4. **Explain what you've tried** already
5. **Be patient and respectful**

---

## 🎉 Thank You!

Thank you for contributing to the WordPress Database Import & Domain Replacement Tool! Your contributions help make this tool better for the entire WordPress community.

---

**Happy coding! 🚀**
