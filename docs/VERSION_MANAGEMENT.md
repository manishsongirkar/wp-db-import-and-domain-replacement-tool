# Version Management

This project uses a centralized version management system to ensure consistency across all components.

## Version File

The current version is stored in the `VERSION` file at the project root:

```
VERSION
```

This file contains only the version number in semantic versioning format: `X.Y.Z`

## Usage

### Reading Version

**From command line:**
```bash
# Using the tool itself
wp-db-import version

# Using the version script
./lib/version.sh

# Reading the file directly
cat VERSION
```

**From shell scripts:**
```bash
# Using the utility function (if utils.sh is loaded)
version=$(get_tool_version)

# Reading directly
version=$(cat "$SCRIPT_DIR/VERSION" 2>/dev/null | tr -d '\n\r')
```

### Updating Version

**Using the version script (recommended):**
```bash
./lib/version.sh 1.2.0
```

**Direct file edit:**
```bash
echo "1.2.0" > VERSION
```

## Automatic Propagation

Once the VERSION file is updated, the new version is immediately available in:

- ✅ `wp-db-import version` command
- ✅ All help text and documentation that references version
- ✅ Any scripts that use the `get_tool_version()` function
- ✅ Any code that reads from the VERSION file

## Integration Points

The following components read from the centralized VERSION file:

1. **`wp-db-import`** - Main executable (via `get_version()` function)
2. **`lib/core/utils.sh`** - Core utilities (via `get_tool_version()` function)
3. **`lib/version.sh`** - Version management script
4. **Future components** - Should use `get_tool_version()` function

## Best Practices

1. **Always use semantic versioning**: `X.Y.Z` format
2. **Use the version script**: `./lib/version.sh 1.2.0` for validation
3. **Test after updating**: Run `wp-db-import version` to verify
4. **Document changes**: Update CHANGELOG or release notes when bumping version
5. **Git tag releases**: Tag releases with version numbers for tracking

## Example Workflow

```bash
# Check current version
./lib/version.sh
# Output: 1.0.0

# Update version
./lib/version.sh 1.1.0
# Output: Version updated to: 1.1.0

# Verify the change
wp-db-import version
# Output shows: Version: 1.1.0

# Commit and tag
git add VERSION
git commit -m "Bump version to 1.1.0"
git tag v1.1.0
```

This ensures consistent version management across the entire project without hardcoded version numbers scattered throughout the codebase.
