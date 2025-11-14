# Bash Version Compatibility Guide

## Overview

The WordPress DB Import & Domain Replacement Tool now includes comprehensive bash version compatibility, supporting:

- **Bash 3.2** (macOS default)
- **Bash 4.x** (Linux default)
- **Bash 5.x** (Modern systems)
- **Zsh** (Enhanced compatibility)
- **POSIX sh** (Universal fallback)

## Compatibility Matrix

| Bash Version | Associative Arrays | Nameref Variables | Case Conversion | Mapfile | Status |
|--------------|-------------------|-------------------|-----------------|---------|--------|
| **3.2** | ❌ → ✅ Fallback | ❌ → ✅ Fallback | ❌ → ✅ Fallback | ❌ → ✅ Fallback | **Fully Compatible** |
| **4.0-4.2** | ✅ Native | ❌ → ✅ Fallback | ✅ Native | ✅ Native | **Fully Compatible** |
| **4.3+** | ✅ Native | ✅ Native | ✅ Native | ✅ Native | **Fully Compatible** |
| **5.x** | ✅ Native | ✅ Native | ✅ Native | ✅ Native | **Fully Compatible** |

## Features & Fallbacks

### 1. Associative Arrays

**Bash 4.0+**: Native `declare -A` support
```bash
declare -A CONFIG_MAP
CONFIG_MAP["key"]="value"
```

**Bash 3.2 Fallback**: Parallel arrays simulation
```bash
# Automatically managed by compatibility functions
init_associative_array "CONFIG_MAP"
set_associative_value "CONFIG_MAP" "key" "value"
value=$(get_associative_value "CONFIG_MAP" "key")
```

### 2. String Case Conversion

**Bash 4.0+**: Native parameter expansion
```bash
lowercase="${string,,}"
uppercase="${string^^}"
```

**Bash 3.2 Fallback**: External commands
```bash
lowercase=$(to_lowercase "$string")  # Uses tr internally
uppercase=$(to_uppercase "$string")  # Uses tr internally
```

### 3. Array Reading

**Bash 4.0+**: Native mapfile/readarray
```bash
mapfile -t array_name < file
```

**Bash 3.2 Fallback**: Manual line reading
```bash
read_lines_into_array "array_name" < file
```

### 4. Variable References

**Bash 4.3+**: Nameref variables
```bash
declare -n ref=original_var
ref="new_value"  # modifies original_var
```

**Bash 3.2 Fallback**: Global array access
```bash
# Functions access global arrays directly
# No nameref syntax used
```

## Automatic Detection

The system automatically detects your bash version and available features:

```bash
# Automatically called when modules load
detect_bash_version

# Check specific features
if has_bash_feature "associative_arrays"; then
    echo "Native associative arrays available"
else
    echo "Using compatibility fallbacks"
fi

# Get version info
get_bash_version_info
```

## Usage Examples

### Configuration Management

```bash
# Works across all bash versions
init_config_storage
set_config_value "database_host" "localhost"
set_config_value "database_name" "wordpress"

# Retrieve values
host=$(get_config_value "database_host")
name=$(get_config_value "database_name")
```

### Domain Mapping

```bash
# Initialize domain mappings (version-aware)
init_associative_array "DOMAIN_MAP"

# Set mappings
set_associative_value "DOMAIN_MAP" "prod.example.com" "local.test"
set_associative_value "DOMAIN_MAP" "www.example.com" "local.test"

# Retrieve mappings
local_domain=$(get_associative_value "DOMAIN_MAP" "prod.example.com")
```

### String Processing

```bash
# Case-insensitive comparisons
user_input="YES"
normalized=$(to_lowercase "$user_input")
if [[ "$normalized" == "yes" ]]; then
    echo "User confirmed"
fi

# Domain sanitization
domain="HTTP://Example.COM/"
clean_domain=$(to_lowercase "${domain#*://}")  # Works on all versions
clean_domain="${clean_domain%/}"              # Remove trailing slash
```

## Testing Compatibility

Run the compatibility test suite:

```bash
# Comprehensive test
./test_bash_compatibility.sh

# Simple validation
./test_simple_compat.sh
```

### Expected Output (Bash 3.2)

```
=== Bash Compatibility Quick Test ===
Bash Version: 3.2.57(1)-release
✅ Utils loaded successfully
✅ Version detection works: 3.2
Testing associative arrays...
✅ Array initialization works
✅ Set value works
✅ Get value works: test_value
✅ Case conversion works
✅ Module loader works
✅ All modules loaded
✅ Main script loads cleanly
✅ All functions available

🎉 ALL COMPATIBILITY TESTS PASSED!
WordPress DB Import Tool is fully compatible with Bash 3.2
```

## Implementation Details

### Version Detection Logic

```bash
detect_bash_version() {
    BASH_VERSION_MAJOR="${BASH_VERSION%%.*}"
    local version_remainder="${BASH_VERSION#*.}"
    BASH_VERSION_MINOR="${version_remainder%%.*}"

    # Feature detection based on version
    if [[ "$BASH_VERSION_MAJOR" -gt 4 ]] ||
       [[ "$BASH_VERSION_MAJOR" -eq 4 && "$BASH_VERSION_MINOR" -ge 0 ]]; then
        BASH_FEATURE_ASSOCIATIVE_ARRAYS="true"
        BASH_FEATURE_LOWERCASE="true"
        BASH_FEATURE_MAPFILE="true"
    else
        BASH_FEATURE_ASSOCIATIVE_ARRAYS="false"
        BASH_FEATURE_LOWERCASE="false"
        BASH_FEATURE_MAPFILE="false"
    fi

    # Nameref support (Bash 4.3+)
    if [[ "$BASH_VERSION_MAJOR" -gt 4 ]] ||
       [[ "$BASH_VERSION_MAJOR" -eq 4 && "$BASH_VERSION_MINOR" -ge 3 ]]; then
        BASH_FEATURE_NAMEREF="true"
    else
        BASH_FEATURE_NAMEREF="false"
    fi
}
```

### Associative Array Fallback

For Bash 3.2, associative arrays are simulated using parallel regular arrays:

```bash
# Storage structure for "CONFIG_MAP":
CONFIG_MAP_KEYS=("key1" "key2" "key3")
CONFIG_MAP_VALUES=("value1" "value2" "value3")

# Access via compatibility functions
set_associative_value "CONFIG_MAP" "key1" "new_value"
value=$(get_associative_value "CONFIG_MAP" "key1")
```

## Migration from Old System

### Before (Version-Specific Code)

```bash
# Old approach - would fail on Bash 3.2
if [[ ${BASH_VERSION%%.*} -ge 4 ]]; then
    declare -A MAPPINGS
    MAPPINGS["key"]="value"
else
    echo "Associative arrays not supported"
    exit 1
fi
```

### After (Compatible Approach)

```bash
# New approach - works on all versions
init_associative_array "MAPPINGS"
set_associative_value "MAPPINGS" "key" "value"
result=$(get_associative_value "MAPPINGS" "key")
```

## Performance Considerations

### Bash 4.0+ (Optimal)
- Native associative arrays: O(1) access
- Native case conversion: Fast parameter expansion
- Native mapfile: Efficient bulk reading

### Bash 3.2 (Good)
- Simulated associative arrays: O(n) access (acceptable for typical use)
- External tr commands: Minimal overhead
- Manual line reading: Comparable performance

### Recommendations

1. **Production**: Use Bash 4.0+ when possible for optimal performance
2. **Development**: Test with Bash 3.2 to ensure maximum compatibility
3. **macOS**: Default Bash 3.2 works perfectly with all features
4. **Linux**: Modern Bash versions provide best performance

## Troubleshooting

### Common Issues

1. **"declare: -g: invalid option"**
   - Fixed: Removed `-g` flag for Bash 3.2 compatibility

2. **"declare: -A: invalid option"**
   - Fixed: Automatic fallback to parallel arrays

3. **"local: -n: invalid option"**
   - Fixed: Removed nameref usage in favor of global array access

4. **Parameter expansion not working**
   - Fixed: Fallback to external commands for case conversion

### Debugging

Enable debug output:

```bash
export BASH_DEBUG_VERSION=true
export BASH_DEBUG_MODULES=true
```

This will show:
- Detected bash version and features
- Compatibility choices being made
- Module loading progress

## Best Practices

### For Contributors

1. **Always use compatibility functions** instead of version-specific syntax
2. **Test with Bash 3.2** (macOS default) before submitting
3. **Use the test suite** to validate changes
4. **Avoid bash 4+ specific features** in core functionality

### For Users

1. **No special setup required** - compatibility is automatic
2. **Use any supported shell** (bash, zsh, sh)
3. **Report compatibility issues** with version information
4. **Run test suite** if experiencing issues

## Future Enhancements

Planned improvements:

1. **Automatic bash upgrade suggestions** for optimal performance
2. **Performance profiling** across versions
3. **Extended shell support** (fish, dash)
4. **Compatibility analytics** and reporting

## Conclusion

The WordPress DB Import Tool now provides seamless compatibility across all major bash versions while maintaining optimal performance on modern systems. Users on any Unix-like system can use the tool without worrying about bash version limitations.
