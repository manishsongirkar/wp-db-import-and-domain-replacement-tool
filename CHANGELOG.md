# Changelog

## [Unreleased]

### Added
- **Real dry run** ([#20](https://github.com/manishsongirkar/wp-db-import-and-domain-replacement-tool/issues/20)): `--dry-run` (also `dry_run=true`, `WPDB_DRY_RUN=1`, or answering `y` at the prompt) previews the whole import **without changing the database**. The dump is imported into a temporary database that is dropped afterwards; the tool reports the tables and rows it would import, whether the compatibility filter is needed, and the occurrences of the old domain (and of every site-mapping domain) per table, with a clear summary. A missing mysql client or `CREATE DATABASE` privilege, and a dump that cannot be imported, are explained and nothing is changed. `CREATE/USE/DROP/ALTER DATABASE` lines are removed from the preview stream so a dump can never reach another database. New module `lib/database/db_dry_run.sh`, `--dry-run` in `--help` and the completions, unit suite `test_dry_run.sh`, and real-server scenarios in `test_real_import.sh` (table checksums and the database list are identical before and after; counts match independent counts from the dump).
- **Unattended mode** ([#19](https://github.com/manishsongirkar/wp-db-import-and-domain-replacement-tool/issues/19)): `--yes`, `-y`, `--non-interactive` (any position) or `WPDB_ASSUME_YES=1`, for `wp-db-import` and `import_wp_db.sh`.
  - Every prompt takes its default, exactly as if Enter was pressed. Confirmations are skipped and show the reason (`--yes` or `from config`).
  - Nothing is read from stdin or the terminal, and stdin is closed for the whole run, so a script cannot hang (also with a stdin pipe that never ends).
  - A prompt with no safe default fails with a clear message and exit code 1: SQL file name, old/new domain, the config-vs-database domain choice, "MySQL commands executed manually?", Stage File Proxy domain questions, and the `config-create` wizard values.
  - Backups still run when `backup_before_import=ask`. `wp-db-import update` answers "no" to its uncommitted-changes question.
  - New helpers `wpdb_assume_yes`, `wpdb_auto_proceed_reason`, `wpdb_read`, `wpdb_read_required` in `lib/core/utils.sh`; every prompt in the tool now uses them (a test rejects a raw `read -r`).
  - `--help`, README, USAGE, CONTRIBUTING and the Bash/Zsh completions document the new options and the exit codes.
- Unit test suite `test_yes_flag.sh`.
- A warning when the mysql client and the server are different products (MariaDB client with a MySQL server, or the reverse), with the client path and how to fix it.
- `WPDB_VERBOSE=1` prints which mysql client is used for the import.
- Table cleanup and listing use the same mysql client and socket as the import, with `wp db query` (then `--defaults`) as fallback, because `wp db query` cannot connect in Local.
- Server matrix fixture `dump_nodrop_mariadb11.sql` and unit tests for both fixes.
- **Real end-to-end import test** ([#13](https://github.com/manishsongirkar/wp-db-import-and-domain-replacement-tool/issues/13)): `./run_tests.sh real-import` starts a throw-away MySQL, installs real WordPress sites with WP-CLI, runs the real tool and checks the database. Six scenarios: single site, `use_socket=false`, `.gz` dump, compatibility retry, multisite subdirectory and subdomain. Also checks the backup, cache flush, no leftover temp files and a clean console. Skipped with a reason when php, WP-CLI, a server binary or the network is missing.
- `lib/tests/server_helpers.sh`: shared throw-away server code (falls back to a short socket path when the temp path is too long); the server matrix now uses it.
- Unit tests for database domain detection, `execute_with_timeout` and a guard against `printf` formats that start with a dash.

### Changed
- **`dry_run=true` no longer imports the dump.** Before, a dry run still replaced your real database with the dump and only previewed the search-replace, which contradicted "no data will be changed". The question "Run in dry-run mode?" is now asked **before** the import.
- Exit code of an unknown command or option is now **2** (usage error) instead of 1. Exit codes are `0` success, `1` failure, `2` usage error.
- Tests that printed "function not available" and skipped were rewritten against the real functions (`load_import_config`, `validate_config_file`, `run_search_replace`, ...) with real assertions: config loading and validation, the exact search-replace commands (two passes, `guid` skipped, `--dry-run`, `--network`/`--url`), the cleanup. A missing core function is now a **failure**. `./run_tests.sh --verbose` has zero "not available" warnings. Environment notes for optional tools (mysql client, git, curl) are shown as information.

### Fixed
- **The environment's own mysql client is used again** ([#16](https://github.com/manishsongirkar/wp-db-import-and-domain-replacement-tool/issues/16)). The tool put `/opt/homebrew/bin` and `/usr/local/bin` **before** the user's `PATH`, so a Homebrew client could replace the right one (for example Local's MySQL client), which once caused a false "import successful". These directories are now only a fallback after the user's `PATH` (override with `WPDB_FALLBACK_PATH`). This applies to the import, WP-CLI calls, socket detection and the WP-CLI lookup.
- **Retry is safe for dumps without `DROP TABLE IF EXISTS`** ([#27](https://github.com/manishsongirkar/wp-db-import-and-domain-replacement-tool/issues/27)). For such dumps the table list is saved before the import. Before any retry or fallback, only the tables (and views) created by the failed attempt are removed; tables that existed before are never touched. If the list cannot be saved, the tool does not retry and says why. Dumps that drop their own tables are unaffected.
- `get_wp_db_credentials` returned the first value for every constant when several `define()` calls were on one line of `wp-config.php`.
- **Console errors when colors are off** (CI, pipes, `NO_COLOR`): `printf: --: invalid option` in the revision cleanup and Stage File Proxy output. Formats that can start with `--` now use `printf --`.
- **"Failed to flush rewrite rule" on every multisite import**: `wp rewrite flush --network` is not a valid option. On a network each site is now flushed by its URL.
- **Multisite detection broke on Linux and with GNU coreutils**: `execute_with_timeout` passed a shell function to the external `timeout`, which cannot run functions, so detection fell back to defaults with "WP-CLI not responding". Functions now run directly (no new time limits).
- **Domain validation was skipped for multisite imports**: right after an import `wp option get siteurl` cannot start (wp-config names the local network domain, the database still has the production one). The domain is now read from the database (`wp_site`, then `wp_options`) with a table-prefix safety check.

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
