# Test Fixtures

This directory contains test fixtures, sample files, and test data used by the test suite.

## Directory Structure

```
fixtures/
├── configs/           # Sample configuration files for testing
├── wordpress/         # WordPress installation samples
├── sql/              # Sample SQL files for testing
└── environment/      # Environment setup files
```

## Usage

Test fixtures are used by various test suites to create realistic testing scenarios without requiring actual WordPress installations or databases.

### Configuration Fixtures

- `single-site.conf` - Configuration for single-site WordPress testing
- `multisite-subdomain.conf` - Multisite with subdomain configuration
- `multisite-subdirectory.conf` - Multisite with subdirectory configuration
- `invalid.conf` - Invalid configuration for error testing

### WordPress Fixtures

- `wp-config-single.php` - Sample wp-config.php for single-site
- `wp-config-multisite.php` - Sample wp-config.php for multisite
- `.htaccess` - Sample .htaccess files

### SQL Fixtures

- `small-database.sql` - Small test database for import testing
- `multisite-database.sql` - Sample multisite database structure

## Adding New Fixtures

When adding new test fixtures:

1. Keep files small and focused on specific test scenarios
2. Remove any sensitive information
3. Document the purpose of each fixture
4. Use descriptive filenames
5. Follow the existing directory structure
