# Changelog

## [1.1.0] - 2026-10-08

### Added
- Fast database import through the MySQL Unix socket, or the `mysql` client over `DB_HOST` (TCP). WP-CLI stays as the fallback, and the tool prints why it was chosen.
- `lib/database/socket_detector.sh`: socket auto-detection for Homebrew, MAMP, XAMPP, DBngin, Valet, Local, Debian/RHEL/Arch, and WSL. Lando and DDEV are skipped because their sockets are not on the host.
- Session import optimizations (`AUTOCOMMIT`, `FOREIGN_KEY_CHECKS`, `UNIQUE_CHECKS`) for direct mysql and socket imports.
- Import time estimate from a benchmark sample for SQL files of 100 MB or more.
- `get_wp_db_credentials` to read database credentials from `wp-config.php`.
- New config keys: `use_socket`, `mysql_socket`, `import_optimizations`, `parallel_import`. Existing config files are updated automatically.
- Unit tests for socket detection and import performance.
- Developer tools: `hooks/pre-commit`, `install_pre_commit_hook.sh`, `watch_and_test.sh`.

### Changed
- `parallel_import=true` prints a warning and keeps a single-stream import, because SQL dumps are order-sensitive.
- The WP-CLI import runs only when the socket or mysql import was not used or failed.
- The rewrite flush after import is now a soft flush. It no longer writes `.htaccess` or `web.config`.

### Fixed
- Benchmark timing no longer depends on `date +%s%N`, which older macOS does not support.
- The benchmark sample is cut at a line boundary. A sample ending mid-statement always failed and forced the fallback estimate.
- Estimate output no longer shows a maximum lower than the likely value.
- `Failed to flush rewrite rule` on single sites: the `NA` network placeholder was passed to WP-CLI.
- New unit tests wrote results to `/test_results.json` because they did not start a test session.
- WP-CLI version check in the integration test failed on multi-line `wp --version` output.
