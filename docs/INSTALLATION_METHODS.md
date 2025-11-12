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
- ✅ Still gets global command installation
- ⚠️ Manual update process required

## 🌐 Can wp-db-import Run from Any Directory?

**YES!** Once installed via `./install.sh`, the `wp-db-import` command is available globally from any directory:

```bash
cd ~/Desktop
wp-db-import --help  # ✅ Works

cd ~/Documents/Projects
wp-db-import version  # ✅ Works

cd /tmp
wp-db-import show-cleanup  # ✅ Works
```

### How It Works
- Installation creates a symlink in `~/.local/bin/wp-db-import` (or `~/bin/wp-db-import`)
- The symlink points to the actual script in the repository directory
- Shell PATH is updated to include the symlink directory
- Global access works regardless of current working directory

## 🔄 Update Scenarios

### Git Installation Updates

**Automatic Updates:**
```bash
wp-db-import update
```
This command:
- Detects it's a git repository
- Shows current version/commit
- Runs `git pull` automatically
- Reports what was updated
- Changes are immediately available (symlink magic!)

**Manual Git Updates:**
```bash
cd /path/to/wp-db-import-and-domain-replacement-tool
git pull
# Changes immediately available via symlink
```

### ZIP Installation Updates

**Manual Process:**
```bash
# 1. Download latest ZIP from GitHub
# 2. Extract to same location, replacing files
# 3. No need to re-run install.sh (symlink still works)
# 4. Or re-run install.sh if needed
```

**Update Detection:**
```bash
wp-db-import update
```
Output for ZIP installations:
```
❌ Error: Not in a git repository
This tool was likely downloaded as a ZIP archive.
To enable auto-updates, please:
  1. Clone the repository instead:
     git clone https://github.com/manishsongirkar/wp-db-import-and-domain-replacement-tool.git
  2. Run the installer from the cloned repository:
     cd wp-db-import-and-domain-replacement-tool && ./install.sh

For manual updates:
  1. Download the latest release from GitHub
  2. Extract and replace your current installation
  3. Run ./install.sh again if needed
```

## 📋 Installation Type Detection

The tool automatically detects how it was installed:

### Git Installation
```bash
wp-db-import version
```
```
Installation:
  Installed as symlink: ✅
  Symlink: /Users/name/.local/bin/wp-db-import
  Target: /Users/name/wp-db-import-and-domain-replacement-tool/wp-db-import
  Auto-updates: Available (git repository)
```

### ZIP Installation
```bash
wp-db-import version
```
```
Installation:
  Installed as symlink: ✅
  Symlink: /Users/name/.local/bin/wp-db-import
  Target: /Users/name/wp-db-import-and-domain-replacement-tool/wp-db-import
  Auto-updates: Limited (not a git repository)
```

### Direct Execution (Not Installed)
```bash
./wp-db-import version
```
```
Installation:
  Running directly from: /path/to/wp-db-import-and-domain-replacement-tool/wp-db-import
  Auto-updates: Available (git repository)
  💡 Tip: Run ./install.sh to make this command globally available
```

## 🎯 Recommendation

For most users, **Git Clone installation** is recommended because:

1. **Easy updates**: `wp-db-import update` keeps you current
2. **Global access**: Works from any directory after `./install.sh`
3. **Zero friction**: Updates are immediate due to symlink architecture
4. **Version tracking**: Always know what version and commit you're running

ZIP installation is perfect for:
- Users who don't want git dependency
- Corporate environments with restricted git access
- One-time usage scenarios
- Air-gapped systems
