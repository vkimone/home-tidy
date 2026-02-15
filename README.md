[한국어 버전 (Korean Version)](./README_ko.md)

# 🧹 Home-Tidy

**Home-Tidy** is a smart home folder (`~/`) cache cleanup tool for macOS users. It provides safe directory analysis and reports the reclaimed space results.

---

## ✨ Key Features

- **📊 Snapshot-based Analysis**: Records the filesystem state before and after execution to track changes.
- **🛡️ Safe Cleanup**: Supports a whitelist feature to protect essential system files and configuration folders.
- **🚀 High-performance Scanning**: Designed to analyze large-scale directories efficiently.
- **📝 Report Generation**: Records cleaned items and reclaimed space in detailed reports.

---

## 📂 Project Structure

```text
home-tidy/
├── home-tidy.sh      # Main execution script
├── config/           # Configuration files directory
│   ├── target.conf     # Target path configurations
│   └── whitelist.conf  # Deletion exclusion pattern settings
└── lib/              # Core logic (Bash libraries)

# Files generated during execution (macOS standard directories)
~/Library/Application Support/home-tidy/
  ├── snapshots/  # Snapshot files
  └── logs/       # Execution reports
```

> [!NOTE]
> Snapshots and reports are stored in macOS standard paths. This design prepares for Homebrew distribution.

---

## 🚀 Usage

### 1. Preparation
Grant execution permissions to the script.
```bash
chmod +x home-tidy.sh
```

### 2. Execution Options

| Option | Description |
| :--- | :--- |
| `--execute` | **(Default)** Performs actual deletion. |
| `--dry-run` | Shows which files would be deleted without actual deletion. |
| `--compare-only` | Analyzes only the differences between the previous snapshot and current state. |
| `--verbose` | Outputs detailed operation logs. |
| `--help` | Displays this help message. |

**Example:**
```bash
# Actual cleanup (Permanent deletion)
./home-tidy.sh

# Safe preview (No deletion)
./home-tidy.sh --dry-run

# Use sudo for permission issues
sudo ./home-tidy.sh
```

---

## 🛠️ Configuration Guide

### `config/target.conf`
List the cache folder paths you want to clean. You can use `~/` for home directory relative paths.

### `config/whitelist.conf`
Define specific file or folder patterns from the paths in `target.conf` that **must never be deleted** (e.g., `com.apple.*`, `settings.json`).

---

## ⚠️ Cautions

1. **Permanent Deletion**: For security reasons, files are permanently deleted (`rm -rf`) immediately without moving to the Trash. Please be careful as recovery is impossible.
2. **Permission Issues**: Some system caches or protected folders cannot be deleted with normal permissions. In this case, run with `sudo`.
3. **Dry-run Recommended**: Always check deletion targets with `--dry-run` before actual execution.
4. **Exclude Important Data**: Ensure that project source code or critical configuration files are not included in `target.conf`.
5. **OS Compatibility**: This tool is optimized for **macOS and Bash environments**.
6. **Data Storage**: Snapshots and reports are stored in `~/Library/Application Support/home-tidy`.

---

## 📦 Homebrew Distribution (Planned)

Installation via Homebrew will be supported in the future.

**Data Storage Location:** `~/Library/Application Support/home-tidy`
- Snapshots: `snapshots/`
- Reports: `logs/`

---

## 📜 License
This project was created as a personal management tool. We are not responsible for any data loss occurring during use, so please use it after sufficient testing.
