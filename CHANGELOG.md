# Changelog

## [1.2.0] - 2026-10-08

### Added
- **Pre-import backup.** Saves a compressed copy of the current database (`mysqldump --add-drop-table`) to `~/.wp-db-import/backups` (or `backup_dir`) before it is replaced. The new `backup_before_import` setting is `ask` (default: prompts, Yes is the default answer), `true` or `false`. Answering `n` at the prompt saves `backup_before_import=false` to the config file. Unattended runs (`auto_proceed=true`) back up without asking. If a requested backup fails, the import is cancelled.
- **Backup rotation.** `backup_keep` (default 5, `0` = keep all) keeps the newest backups per database and deletes older ones after each backup. Only files named `<db>-YYYYMMDD-HHMMSS[-n].sql.gz` are deleted. Stale `.partial` files are cleaned up.
- **Compressed dumps.** `.sql.gz`, `.zip` and `.sql.bz2` files are verified and streamed into the import without extracting to disk.
- **Cross-version SQL compatibility filter.** If an import fails with a known compatibility error, it is retried once with a filter for collations (`utf8mb4_0900_*`, `utf8mb4_uca1400_*`, `utf8mb3_uca1400_*`), `utf8mb3`, `ENGINE=Aria`, `DEFINER`, `NO_AUTO_CREATE_USER`, `GTID_PURGED` and the MariaDB sandbox-mode line. Row data is never modified. Works on the socket, mysql-client and WP-CLI paths.
- **`uninstall.sh`**: removes stale private temp directories, never deletes saved backups without an explicit yes, new flags `--yes`, `--delete-backups`, `--keep-backups`, prints the exact cause (error, path, permissions, hint) of every failure, lists problems in the summary and exits non-zero on failure.
- **`wp-db-import update`**: fast-forward-only pull, shows the version change, verifies the updated files and explains failures (deleted remote branch, diverged history, network, local changes) with a fix.
- New modules `lib/database/sql_source.sh` and `lib/database/db_backup.sh`.
- Tests: `test_import_hardening.sh`, `test_import_security.sh` (penetration-style), `test_update_uninstall.sh`, `test_server_matrix.sh` (real MySQL/MariaDB servers, opt-in via `./run_tests.sh matrix`) and SQL fixtures.
- `WPDB_MYSQL_BIN` selects a specific mysql client.

### Security
- Logs and scratch files are kept in a private per-run temp directory (mode 700) instead of predictable `/tmp` file names. Symlinked or foreign-owned directories are refused.
- The Stage File Proxy plugin is installed only after its download matches a pinned SHA-256. The unverified `wp plugin install <url>` path was removed.
- The import time benchmark runs in a temporary scratch database that is dropped afterwards. The real database is never written to.
- File names, passwords, database names and config values are never evaluated by the shell (covered by the new security tests).

### Fixed
- **Temporary logs were never removed after a successful run.** `import_wp_db.sh` cleared the EXIT trap at the end of a run instead of running cleanup first. Cleanup now runs on success and failure.
- **False "import successful".** Some mysql/mariadb clients exit 0 although statements failed. The import output is now scanned for `ERROR nnnn` lines and such imports count as failed.
- **Unbounded import logs.** A failing import could echo hundreds of thousands of lines. Logs are size-capped, and the first error lines are printed on screen because the log is removed when the run ends.
- `wp-db-import update` and `--version` no longer report false "uncommitted changes" after a file is only touched (`git status` instead of `git diff-index`).
- A benchmark sample with no `INSERT` rows (for example one huge `INSERT` line) no longer gives an over-optimistic estimate. A size-based estimate is used instead.
- The fixed 30/60/120 minute fallback estimate was replaced by a size-based estimate. Estimates never show 0 minutes.
- A failed backup can no longer delete an earlier backup made in the same second. Backups are written to a `.partial` file and renamed only after they verify.
- `DIM` (dim text colour) is now defined by `init_colors`; it was only defined in the test framework.
- `reports/test_sessions/` is ignored by git.

### Changed
- `backup_before_import`, `backup_dir` and `backup_keep` are added to the example configs, the config template and the automatic migration of older configs.

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
