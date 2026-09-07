# 🔐 envault

> Zero-dependency, single-file CLI environment credentials utility written in Bash. Backed by macOS Keychain.

`envault` provides a secure, friction-free alternative to storing raw developer secrets (API keys, database URLs, tokens) in plaintext project files. It keeps secrets encrypted in the macOS Keychain and generates project `.env` files or shell runtime environments on-demand.

---

## ✨ Features

* **🛡️ Security First**: Secret values are encrypted and stored in macOS native storage (`login.keychain-db`). No plaintext secrets committed or permanently stored in local repositories.
* **⚡ Zero Dependencies**: Pure Bash script. No Python, Node, Go, or Rust runtimes required. Instant startup (<10ms).
* **🧹 No `$HOME` Clutter**: Metadata catalog tracking is cleanly isolated in `~/.config/envault/.keys_list`.
* **🧩 Clean Separation of Concerns**: Decoupled from terminal automation (like `direnv`) and version control (Git). Workflow orchestration lives in your shell.
* **🔁 Universal Export Engine**:
  * Default one-command `.env` workspace file creation with overwrite protection.
  * Silent, injection-safe shell exports (`printf '%q'`) for direct `eval`.
  * Direct stdout streaming for pipes, clipboard (`pbcopy`), and containers.
* **🧪 100% Hermetic Test Suite**: Fully automated test harness with mock Keychain implementation.

---

## 🚀 Quick Start

### 1. Installation

Clone the repository and run the installer:

```bash
git clone https://github.com/cbzxtream/envault.git
cd envault
./install.sh
```

This symlinks `envault` into `~/.local/bin/envault`. Ensure `~/.local/bin` is in your `$PATH`:

```bash
export PATH="$HOME/.local/bin:$PATH"
```

---

## 💻 CLI Usage

```text
Usage: envault <command> [args]

Commands:
  add <name>      Securely store/update a key in macOS Keychain
  rm <name>       Remove a key from both the tracking list and Keychain
  export [opts]   Export credentials to .env file or shell format
                  Options: -s|--shell, -o|--output <file>, -f|--force, --stdout|-c
  ls              List all currently tracked service names
  check <name>    Check if a service name is tracked in catalog [--silent|-s]
```

### Examples

```bash
# 1. Add secrets (input is hidden with stty restore trap)
envault add stripe-secret-key
envault add aws-access-key-id

# 2. List tracked credentials
envault ls

# 3. Export to .env file (default behavior, safe overwrite prompt)
envault export

# 4. Force overwrite without prompt
envault export -f

# 5. Export specific secrets to a custom file
envault export -o .env.production stripe-secret-key

# 6. Ingest directly into current terminal session
eval "$(envault export -s)"

# 7. Pipe dotenv format to clipboard or another tool
envault export --stdout | pbcopy

# 8. Check if a key is registered
envault check stripe-secret-key
```

---

## 🐚 Recommended Shell Integration (`~/.zshrc`)

Add the following to your `~/.zshrc` or `~/.bashrc`:

```zsh
# ==============================================================================
# envault Aliases & Functions
# ==============================================================================
export PATH="$HOME/.local/bin:$PATH"

# Core Subcommand Aliases
alias eva="envault add"
alias evl="envault ls"
alias eve="envault check"
alias evr="envault rm"

# [evx] Default export -> writes to .env
alias evx="envault export"

# [evst] Stream dotenv format to stdout (pipes, pbcopy, container injection)
alias evst="envault export --stdout"

# [evsh] Dynamic Shell Runtime Ingestion (silent, zero-log eval)
evsh() {
    eval "$(envault export -s "$@")"
}

# [evxf] Export to custom file followed by optional keys
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

## 🧪 Testing

Run the hermetic test suite (uses a mock `security` binary without touching system Keychains):

```bash
./test.sh
```

Run specific test suites:
```bash
./test.sh export    # Run export command test suite
./test.sh router    # Test usage and command routing
./test.sh check     # Test check subcommand
```

---

## 📄 License

MIT License. Free for personal and commercial use.
