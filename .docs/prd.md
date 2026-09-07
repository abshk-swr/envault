# 📋 Product Requirement Document (PRD) & Technical Specification

## 1. Executive Summary & Philosophy

**`envault`** is a zero-dependency, single-file CLI environment credentials utility written in Bash. It provides a secure, friction-free alternative to storing raw developer secrets (API keys, tokens, credentials) in plaintext files (like `.env`).

### Core Tenets

* **Strict Separation of Concerns**: The utility only manages secure credential storage, indexing, and format rendering. It is explicitly decoupled from terminal automation tools (like `direnv`) and version control systems (like Git). Workflow orchestration is delegated to the user's shell runtime configuration.
* **Security First**: Raw secret values are stored exclusively inside macOS native, hardware-encrypted storage (macOS Keychain). No plaintext credentials touch local project directories or shell history files.
* **Zero Dependency & Self-Contained**: Implemented as a single, portable executable script without external language runtime dependencies (Python, Node, Go, etc.).
* **No `$HOME` Clutter**: System catalog metadata is cleanly isolated into standard configuration paths (`~/.config/envault/.keys_list`).

---

## 2. System Architecture & Repository Layout

```
envault/                  # Root Repository Directory
├── envault               # Main self-contained executable entry point
├── install.sh            # Lightweight installer linking to ~/.local/bin/envault
├── test.sh               # Hermetic test suite with mock Keychain harness
├── .gitignore            # Blocks local developer test and OS metadata files
└── .docs/
    └── prd.md            # Product specification and technical architecture
```

### Host Storage Model

* **Global Executable Link**: `~/.local/bin/envault` (symlinked directly to repository executable).
* **Metadata Tracking Ledger**: `~/.config/envault/.keys_list` (stores plaintext service identifiers for fast indexed reference).
* **Encrypted Credential Vault**: macOS Keychain (`~/Library/Keychains/login.keychain-db`).

---

## 3. Subcommand Specifications

All subcommands are executed within `envault` via internal in-process function routing, ensuring fast startup (<10ms) and zero subshell overhead.

### `add` (`envault add <name>`)
* **Purpose**: Safely prompts and stores string credentials in macOS Keychain.
* **Overwrite Guard**: Checks `is_tracked` before prompt. If identifier exists, requests explicit confirmation (`y/N`).
* **Input Isolation**: Reads inputs invisibly (`read -s`) directly from `/dev/tty` (configurable via `ENVAULT_TTY`).
* **Terminal Safety**: Registers a `trap` to guarantee terminal echo is always restored even if interrupted (`Ctrl+C`).
* **Lock Recovery**: If Keychain is locked, prompts user to unlock via `security unlock-keychain` and retries automatically.

### `rm` (`envault rm <name>`)
* **Purpose**: Deletes secrets from Keychain and purges tracking ledger entries.
* **Atomic Deletion**: Removes key from Keychain via `security delete-generic-password` and uses `mktemp` to atomically filter `.keys_list`.

### `check` (`envault check <name> [--silent | -s]`)
* **Purpose**: Scans `.keys_list` to verify whether a key is currently tracked.
* **Dual Mode**:
  * **Public Mode**: Outputs status text (`✅ '<name>' is currently tracked.` / `🔍 '<name>' does not exist in tracking list.`) with exit codes `0` / `1`.
  * **Silent Mode (`-s` / `--silent`)**: Suppresses all stdout/stderr output; returns exit code `0` or `1`.

### `ls` (`envault ls`)
* **Purpose**: Prints catalog of tracked service names formatted in uppercase bullet points (`  • SERVICE_NAME`). Exits cleanly with empty notice if no keys are tracked.

### `export` (`envault export [options] [names...]`)
* **Purpose**: Secret retrieval and format rendering engine for local workspace files or shell runtime environments.
* **Default Behavior**: Renders secrets into `.env` file syntax (`KEY="val"`) and writes directly to `./.env` with overwrite protection.
* **Supported Options**:
  * `-s`, `--shell`: Emits bash variable export statements (`export KEY=val`). Streams cleanly and silently to `stdout` with zero log overhead, designed specifically for `eval "$(envault export -s)"`.
  * `-o`, `--output`, `--file <path>`: Specifies custom output file destination (defaults to `.env`).
  * `-f`, `--force`: Overwrites target file without confirmation prompt if it already exists.
  * `--stdout`, `-c`: Streams `.env` formatted content directly to `stdout` instead of writing to disk (for pipes, clipboard, or containers).
* **Identifier Sanitization**: Converts lowercase letters and hyphens to uppercase POSIX environment variable format (e.g. `stripe-secret-key` → `STRIPE_SECRET_KEY`).
* **Safe Quoting**:
  * File mode escapes backslashes and double quotes (`KEY="escaped\"val"`).
  * Shell mode uses `printf '%q'` for robust shell escaping (`export KEY=val` / `export KEY="complex\$val"`), ensuring safe `eval` ingestion with arbitrary special characters.
* **Filtering**: Supports querying specific subsets (e.g. `envault export -s KEY1 KEY2`) or all tracked keys if no positional names are provided.

---

## 4. User Workspace Interface Configuration (`~/.zshrc`)

The tool delegates workspace orchestration to the user's shell configuration:

```bash
export PATH="$HOME/.local/bin:$PATH"

# Core Subcommand Aliases
alias eva="envault add"
alias evl="envault ls"
alias eve="envault check"
alias evr="envault rm"

# [evx] Default export to .env
alias evx="envault export"

# [evst] Stream dotenv format to stdout (pipes, pbcopy, container injection)
alias evst="envault export --stdout"

# [evsh] Dynamic Shell Runtime Ingestion (silent, zero-log eval)
evsh() {
    eval "$(envault export -s "$@")"
}

# [evxf] Export to specific file name followed by keys if any
evxf() {
    if [ -z "${1:-}" ]; then
        echo "Usage: evxf <filename> [keys...]" >&2
        return 1
    fi
    local dest_file="$1"
    shift
    envault export -o "$dest_file" "$@"
}
```

---

## 5. Security Invariants & Robustness Architecture

1. **Keychain Path Resolution**: Targets `KEYCHAIN_PATH` (`~/Library/Keychains/login.keychain-db`) explicitly to prevent `<default>` / `<NULL>` errors on modern macOS releases.
2. **User Identity Persistence**: Resolves system accounts with `CURRENT_USER="${USER:-$(whoami)}"` to prevent unbound variable issues in subshell sessions.
3. **Escaping & Special Characters**: Secrets with dollar signs, backticks, spaces, or quotes are escaped using `%q` to avoid code injection during shell `eval`.
4. **Hermetic Automated Testing**: `test.sh` executes against a mock `security` binary and isolated temporary config directories to allow full test suite execution without touching live macOS Keychains.
