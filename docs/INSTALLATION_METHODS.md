# Installation Methods & Update Scenarios

This document explains the different ways users can install and update the WordPress Database Import Tool.

## 📥 Installation Methods

### 1. Git Clone (Recommended)
```bash
git clone https://github.com/manishsongirkar/wp-db-import-and-domain-replacement-tool.git
cd wp-db-import-and-domain-replacement-tool
./install.sh
```

**Benefits:**
- ✅ Auto-updates available via `wp-db-import update`
- ✅ Easy to stay current with latest features
- ✅ Git history and version tracking
- ✅ Can contribute back to the project

### 2. ZIP Download
```bash
# Download ZIP from GitHub releases or repository
# Extract to desired location
cd wp-db-import-and-domain-replacement-tool
./install.sh
```

**Benefits:**
- ✅ No git dependency required
- ✅ Lightweight download
- ✅ Global command installation
- ⚠️ Manual update process required

## 🌐 Can wp-db-import Run from Any Directory?

**YES!** After running `./install.sh`, the `wp-db-import` command is available globally from any directory:

```bash
wp-db-import --help
wp-db-import version
wp-db-import show-cleanup
```

### How It Works
- Installation creates a symlink in `~/.local/bin/wp-db-import` (or `~/bin/wp-db-import`)
- The symlink points to the main script in the repository
- Shell PATH is updated if needed
- Global access works from any directory

## 🔄 Update Scenarios

### Git Installation Updates

**Automatic Updates:**
```bash
wp-db-import update
```
This command:
- Detects git repository
- Runs `git pull` automatically
- Updates are available globally

**Manual Git Updates:**
```bash
cd /path/to/wp-db-import-and-domain-replacement-tool
git pull
# Changes available globally
```

### ZIP Installation Updates

**Manual Process:**
```bash
# Download latest ZIP from GitHub
# Extract and replace files
# Re-run ./install.sh if needed
```

**Update Detection:**
```bash
wp-db-import update
```
If not a git repository, you will be prompted to use manual update steps.

## 📋 Installation Type Detection

The tool automatically detects installation type:

### Git Installation
```bash
wp-db-import version
# Shows: Installed as symlink, auto-updates available
```

### ZIP Installation
```bash
wp-db-import version
# Shows: Installed as symlink, manual updates required
```

### Direct Execution
```bash
./wp-db-import version
# Shows: Running directly, auto-updates if git repo
# Tip: Run ./install.sh for global access
```

## 🎯 Recommendation

For most users, **Git Clone installation** is recommended:

1. Easy updates: `wp-db-import update` keeps you current
2. Global access: Works from any directory
3. Immediate updates: Symlink architecture
4. Version tracking: Know your version and commit

ZIP installation is suitable for:
- No git dependency
- Restricted environments
- One-time use
- Air-gapped systems
