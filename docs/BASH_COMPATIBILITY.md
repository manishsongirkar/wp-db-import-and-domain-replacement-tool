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
| **3.2**      | Fallback (parallel arrays) | Fallback (global access) | Fallback (tr command) | Fallback (manual read) | Fully Compatible |
| **4.0-4.2**  | Native             | Fallback (global access) | Native         | Native  | Fully Compatible |
| **4.3+**     | Native             | Native             | Native         | Native  | Fully Compatible |
| **5.x**      | Native             | Native             | Native         | Native  | Fully Compatible |

## Features & Fallbacks

### 1. Associative Arrays

**Bash 4.0+**: Native associative arrays using `declare -A`.
```bash
declare -A CONFIG_MAP
CONFIG_MAP["key"]="value"
```

**Bash 3.2 Fallback**: Uses parallel arrays managed by compatibility functions.
```bash
init_associative_array "CONFIG_MAP"
set_associative_value "CONFIG_MAP" "key" "value"
value=$(get_associative_value "CONFIG_MAP" "key")
# Internally uses CONFIG_MAP_KEYS and CONFIG_MAP_VALUES arrays
```

### 2. String Case Conversion

**Bash 4.0+**: Native parameter expansion
```bash
lowercase="${string,,}"
uppercase="${string^^}"
```

**Bash 3.2 Fallback**: Uses compatibility functions that call `tr`.
```bash
lowercase=$(to_lowercase "$string")
uppercase=$(to_uppercase "$string")
```

### 3. Array Reading

**Bash 4.0+**: Native mapfile/readarray
```bash
mapfile -t array_name < file
```

**Bash 3.2 Fallback**: Uses compatibility function to read lines into array.
```bash
read_lines_into_array "array_name" < file
```

### 4. Variable References

**Bash 4.3+**: Nameref variables
```bash
declare -n ref=original_var
ref="new_value"  # modifies original_var
```

**Bash 3.2 Fallback**: Functions access global arrays directly, no nameref syntax used.
```bash
# Use compatibility functions, no declare -n
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

## Implementation Details

### Version Detection Logic

Compatibility functions automatically detect Bash version and set feature flags:
```bash
detect_bash_version() {
    # Sets BASH_FEATURE_ASSOCIATIVE_ARRAYS, BASH_FEATURE_NAMEREF, BASH_FEATURE_LOWERCASE, BASH_FEATURE_MAPFILE
    # Used by all compatibility functions
}
```

### Associative Array Fallback

For Bash 3.2, associative arrays are simulated using parallel arrays:
```bash
CONFIG_MAP_KEYS=("key1" "key2")
CONFIG_MAP_VALUES=("value1" "value2")
set_associative_value "CONFIG_MAP" "key1" "new_value"
value=$(get_associative_value "CONFIG_MAP" "key1")
```

## Usage Examples

### Configuration Management
```bash
# Works across all bash versions
init_config_storage
set_config_value "database_host" "localhost"
set_config_value "database_name" "wordpress"
host=$(get_config_value "database_host")
name=$(get_config_value "database_name")
```

### Domain Mapping
```bash
init_associative_array "DOMAIN_MAP"
set_associative_value "DOMAIN_MAP" "prod.example.com" "local.test"
set_associative_value "DOMAIN_MAP" "www.example.com" "local.test"
local_domain=$(get_associative_value "DOMAIN_MAP" "prod.example.com")
```

### String Processing
```bash
user_input="YES"
normalized=$(to_lowercase "$user_input")
if [[ "$normalized" == "yes" ]]; then
    echo "User confirmed"
fi
domain="HTTP://Example.COM/"
clean_domain=$(to_lowercase "${domain#*://}")
clean_domain="${clean_domain%/}"
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

```bash
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

## Troubleshooting

### Common Issues

1. **Associative arrays not available**
   - Fixed: Uses parallel arrays via compatibility functions in Bash 3.2

2. **Nameref variables not available**
   - Fixed: Uses global access in Bash 3.2/4.0-4.2

3. **Case conversion not available**
   - Fixed: Uses `tr` via compatibility functions in Bash 3.2

4. **mapfile/readarray not available**
   - Fixed: Uses manual line reading via compatibility functions in Bash 3.2

### Debugging
```bash
export BASH_DEBUG_VERSION=true
export BASH_DEBUG_MODULES=true
```
Shows detected bash version, feature flags, and compatibility choices.

## Migration from Old System

### Before (Version-Specific Code)
```bash
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
init_associative_array "MAPPINGS"
set_associative_value "MAPPINGS" "key" "value"
result=$(get_associative_value "MAPPINGS" "key")
```
