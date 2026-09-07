#!/bin/bash
# ==============================================================================
# envault Test Suite
# ==============================================================================
set -euo pipefail

# ANSI color codes
GREEN="\033[0;32m"
RED="\033[0;31m"
BLUE="\033[0;34m"
YELLOW="\033[0;33m"
BOLD="\033[1m"
RESET="\033[0m"

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
ENVAULT="$REPO_DIR/envault"

# Verify binary exists
if [ ! -f "$ENVAULT" ]; then
    echo -e "${RED}Error: envault executable not found at $ENVAULT${RESET}"
    exit 1
fi

# Sandbox isolation setup
TEST_TMP="$(mktemp -d)"
trap 'rm -rf "$TEST_TMP"' EXIT

MOCK_BIN="$TEST_TMP/bin"
MOCK_STORE="$TEST_TMP/mock_keychain"
TEST_CONFIG="$TEST_TMP/config"
mkdir -p "$MOCK_BIN" "$MOCK_STORE" "$TEST_CONFIG"

# Mock macOS Keychain `security` command
cat << 'EOF' > "$MOCK_BIN/security"
#!/bin/bash
STORE_DIR="${MOCK_KEYCHAIN_DIR:-/tmp/mock_keychain}"
mkdir -p "$STORE_DIR"

action="$1"
shift

account=""
service=""
secret=""

while [ $# -gt 0 ]; do
    case "$1" in
        -a) account="$2"; shift 2 ;;
        -s) service="$2"; shift 2 ;;
        -w) 
            if [ -n "${2:-}" ] && [[ "$2" != -* ]]; then
                secret="$2"
                shift 2
            else
                shift 1
            fi
            ;;
        -U) shift ;;
        *) shift ;;
    esac
done

case "$action" in
    add-generic-password)
        echo "$secret" > "$STORE_DIR/$service"
        exit 0
        ;;
    find-generic-password)
        if [ -f "$STORE_DIR/$service" ]; then
            cat "$STORE_DIR/$service"
            exit 0
        else
            exit 44
        fi
        ;;
    delete-generic-password)
        if [ -f "$STORE_DIR/$service" ]; then
            rm -f "$STORE_DIR/$service"
            exit 0
        else
            exit 44
        fi
        ;;
    unlock-keychain)
        exit 0
        ;;
    *)
        exit 1
        ;;
esac
EOF
chmod +x "$MOCK_BIN/security"

export PATH="$MOCK_BIN:$PATH"
export MOCK_KEYCHAIN_DIR="$MOCK_STORE"
export TRACKING_DIR="$TEST_CONFIG"

# Test assertions and counters
PASSED_COUNT=0
FAILED_COUNT=0

assert_equals() {
    local test_name="$1"
    local expected="$2"
    local actual="$3"
    if [ "$expected" = "$actual" ]; then
        echo -e "  ${GREEN}✓ PASS:${RESET} $test_name"
        PASSED_COUNT=$((PASSED_COUNT + 1))
    else
        echo -e "  ${RED}✗ FAIL:${RESET} $test_name"
        echo -e "    Expected: '$expected'"
        echo -e "    Actual:   '$actual'"
        FAILED_COUNT=$((FAILED_COUNT + 1))
    fi
}

assert_contains() {
    local test_name="$1"
    local needle="$2"
    local haystack="$3"
    if [[ "$haystack" == *"$needle"* ]]; then
        echo -e "  ${GREEN}✓ PASS:${RESET} $test_name"
        PASSED_COUNT=$((PASSED_COUNT + 1))
    else
        echo -e "  ${RED}✗ FAIL:${RESET} $test_name"
        echo -e "    Expected to contain: '$needle'"
        echo -e "    Actual content:     '$haystack'"
        FAILED_COUNT=$((FAILED_COUNT + 1))
    fi
}

assert_exit_code() {
    local test_name="$1"
    local expected_code="$2"
    local actual_code="$3"
    if [ "$expected_code" -eq "$actual_code" ]; then
        echo -e "  ${GREEN}✓ PASS:${RESET} $test_name (exit code $actual_code)"
        PASSED_COUNT=$((PASSED_COUNT + 1))
    else
        echo -e "  ${RED}✗ FAIL:${RESET} $test_name (expected exit code $expected_code, got $actual_code)"
        FAILED_COUNT=$((FAILED_COUNT + 1))
    fi
}

# ------------------------------------------------------------------------------
# Test Suites
# ------------------------------------------------------------------------------
suite_router() {
    echo -e "\n${YELLOW}Running Suite: Router & Usage${RESET}"
    local output
    output=$("$ENVAULT" 2>&1 || true)
    assert_contains "No args displays usage" "Usage: envault <command> [args]" "$output"
    assert_contains "Usage lists check command" "check <name>" "$output"
    assert_contains "Usage lists export command" "export [opts]" "$output"

    output=$("$ENVAULT" unknown_cmd 2>&1 || true)
    assert_contains "Unknown command displays usage" "Usage: envault <command> [args]" "$output"

    output=$("$ENVAULT" shx 2>&1 || true)
    assert_contains "Removed shx displays usage" "Usage: envault <command> [args]" "$output"

    output=$("$ENVAULT" fx 2>&1 || true)
    assert_contains "Removed fx displays usage" "Usage: envault <command> [args]" "$output"

    output=$("$ENVAULT" xp 2>&1 || true)
    assert_contains "Unbound alias xp displays usage" "Usage: envault <command> [args]" "$output"

    output=$("$ENVAULT" usage 2>&1 || true)
    assert_contains "Explicit usage displays commands" "Commands:" "$output"
}

suite_check() {
    echo -e "\n${YELLOW}Running Suite: check Subcommand${RESET}"
    local output code

    set +e
    output=$("$ENVAULT" check 2>&1)
    code=$?
    set -e
    assert_exit_code "check without args exits 1" 1 "$code"
    assert_contains "check without args shows usage" "Usage: envault check" "$output"

    set +e
    output=$("$ENVAULT" check non_existent_key 2>&1)
    code=$?
    set -e
    assert_exit_code "check on missing key exits 1" 1 "$code"
    assert_contains "check on missing key displays not found message" "does not exist in tracking list" "$output"

    set +e
    output=$("$ENVAULT" check non_existent_key --silent 2>&1)
    code=$?
    set -e
    assert_exit_code "check --silent on missing key exits 1" 1 "$code"
    assert_equals "check --silent produces empty output" "" "$output"

    set +e
    output=$("$ENVAULT" check non_existent_key -s 2>&1)
    code=$?
    set -e
    assert_exit_code "check -s on missing key exits 1" 1 "$code"
    assert_equals "check -s produces empty output" "" "$output"

    # Seed tracked key
    echo "seeded_key" > "$TEST_CONFIG/.keys_list"

    set +e
    output=$("$ENVAULT" check seeded_key 2>&1)
    code=$?
    set -e
    assert_exit_code "check on tracked key exits 0" 0 "$code"
    assert_contains "check on tracked key displays tracked message" "is currently tracked" "$output"

    set +e
    output=$("$ENVAULT" check seeded_key --silent 2>&1)
    code=$?
    set -e
    assert_exit_code "check --silent on tracked key exits 0" 0 "$code"
    assert_equals "check --silent on tracked key produces empty output" "" "$output"

    set +e
    output=$("$ENVAULT" check seeded_key -s 2>&1)
    code=$?
    set -e
    assert_exit_code "check -s on tracked key exits 0" 0 "$code"
    assert_equals "check -s on tracked key produces empty output" "" "$output"
}

suite_ls() {
    echo -e "\n${YELLOW}Running Suite: ls Subcommand${RESET}"
    rm -f "$TEST_CONFIG/.keys_list"
    touch "$TEST_CONFIG/.keys_list"

    local output
    output=$("$ENVAULT" ls 2>&1)
    assert_contains "Empty catalog displays no keys tracked message" "No keys tracked yet" "$output"

    echo "api_key_alpha" >> "$TEST_CONFIG/.keys_list"
    echo "db_password_beta" >> "$TEST_CONFIG/.keys_list"

    output=$("$ENVAULT" ls 2>&1)
    assert_contains "Populated catalog displays header" "Vault Keys Catalog:" "$output"
    assert_contains "Catalog formats keys lowercase snake_case with bullets" "• api_key_alpha" "$output"
    assert_contains "Catalog formats second key lowercase snake_case" "• db_password_beta" "$output"
}

suite_add() {
    echo -e "\n${YELLOW}Running Suite: add Subcommand${RESET}"
    local output code

    set +e
    output=$("$ENVAULT" add 2>&1)
    code=$?
    set -e
    assert_exit_code "add without args exits 1" 1 "$code"
    assert_contains "add without args shows usage" "Usage: envault add <service_name>" "$output"

    set +e
    output=$(echo "" | ENVAULT_TTY=/dev/stdin "$ENVAULT" add empty_secret_key 2>&1)
    code=$?
    set -e
    assert_exit_code "add with empty secret exits 1" 1 "$code"
    assert_contains "add with empty secret displays error" "Secret cannot be empty" "$output"

    output=$(echo "secret_val_123" | ENVAULT_TTY=/dev/stdin "$ENVAULT" add new_service_one 2>&1)
    assert_contains "add stores secret successfully" "Successfully stored 'new_service_one'!" "$output"
    assert_contains "add records service in .keys_list" "new_service_one" "$(cat "$TEST_CONFIG/.keys_list")"
    assert_equals "add stores secret in keychain" "secret_val_123" "$(cat "$MOCK_STORE/new_service_one")"

    # Overwrite abort
    local input_abort
    input_abort=$(printf "n\nnew_secret_val\n")
    output=$(echo "$input_abort" | ENVAULT_TTY=/dev/stdin "$ENVAULT" add new_service_one 2>&1)
    assert_contains "add prompts overwrite and aborts on n" "Aborted." "$output"
    assert_equals "aborted add does not overwrite keychain" "secret_val_123" "$(cat "$MOCK_STORE/new_service_one")"

    # Overwrite confirm
    local input_confirm
    input_confirm=$(printf "y\nupdated_secret_val_456\n")
    output=$(echo "$input_confirm" | ENVAULT_TTY=/dev/stdin "$ENVAULT" add new_service_one 2>&1)
    assert_contains "add confirms overwrite and updates" "Successfully stored 'new_service_one'!" "$output"
    assert_equals "confirmed add updates keychain" "updated_secret_val_456" "$(cat "$MOCK_STORE/new_service_one")"
}

suite_export() {
    echo -e "\n${YELLOW}Running Suite: export Subcommand${RESET}"
    rm -f "$TEST_CONFIG/.keys_list"
    touch "$TEST_CONFIG/.keys_list"

    local workdir="$TEST_TMP/workdir"
    rm -rf "$workdir"
    mkdir -p "$workdir"

    # Empty catalog tests
    local output
    output=$(cd "$workdir" && "$ENVAULT" export 2>&1)
    assert_equals "export on empty catalog outputs nothing" "" "$output"
    if [ ! -f "$workdir/.env" ]; then
        echo -e "  ${GREEN}✓ PASS:${RESET} export on empty catalog does not create .env"
        PASSED_COUNT=$((PASSED_COUNT + 1))
    else
        echo -e "  ${RED}✗ FAIL:${RESET} export on empty catalog should not create .env"
        FAILED_COUNT=$((FAILED_COUNT + 1))
    fi

    output=$("$ENVAULT" export -s 2>&1)
    assert_equals "export -s on empty catalog outputs nothing" "" "$output"

    output=$("$ENVAULT" export --stdout 2>&1)
    assert_equals "export --stdout on empty catalog outputs nothing" "" "$output"

    # Seed tracking and keychain secrets
    echo "aws_access_key" > "$TEST_CONFIG/.keys_list"
    echo "stripe_secret" >> "$TEST_CONFIG/.keys_list"
    echo "special_secret" >> "$TEST_CONFIG/.keys_list"
    echo "my_aws_key" > "$MOCK_STORE/aws_access_key"
    echo "sk_test_999" > "$MOCK_STORE/stripe_secret"
    echo 'p@ss"w$ord'\''123' > "$MOCK_STORE/special_secret"

    # Test 1: Default export to .env
    output=$(cd "$workdir" && "$ENVAULT" export 2>&1)
    assert_contains "export reports success message" "Exported credentials to '.env'" "$output"
    if [ -f "$workdir/.env" ]; then
        echo -e "  ${GREEN}✓ PASS:${RESET} export creates .env file"
        PASSED_COUNT=$((PASSED_COUNT + 1))
        local env_content
        env_content=$(cat "$workdir/.env")
        assert_contains "export .env has AWS_ACCESS_KEY" 'AWS_ACCESS_KEY="my_aws_key"' "$env_content"
        assert_contains "export .env has STRIPE_SECRET" 'STRIPE_SECRET="sk_test_999"' "$env_content"
        assert_contains "export .env escapes special secret" 'SPECIAL_SECRET="p@ss\"w$ord'\''123"' "$env_content"
    else
        echo -e "  ${RED}✗ FAIL:${RESET} export did not create .env file"
        FAILED_COUNT=$((FAILED_COUNT + 1))
    fi

    # Test 2: Overwrite guard aborts on n
    output=$(cd "$workdir" && echo "n" | ENVAULT_TTY=/dev/stdin "$ENVAULT" export 2>&1)
    assert_contains "export prompts overwrite and aborts on n" "Aborted." "$output"

    # Test 3: Overwrite guard confirms on y
    output=$(cd "$workdir" && echo "y" | ENVAULT_TTY=/dev/stdin "$ENVAULT" export 2>&1)
    assert_contains "export prompts overwrite and updates on y" "Exported credentials to '.env'" "$output"

    # Test 4: -f / --force bypasses prompt
    output=$(cd "$workdir" && "$ENVAULT" export -f 2>&1)
    assert_contains "export -f forces overwrite without prompt" "Exported credentials to '.env'" "$output"

    # Test 5: Custom destination -o / --output
    output=$(cd "$workdir" && "$ENVAULT" export -o "$workdir/custom.env" 2>&1)
    assert_contains "export -o reports custom destination" "Exported credentials to '$workdir/custom.env'" "$output"
    assert_contains "custom.env has AWS_ACCESS_KEY" 'AWS_ACCESS_KEY="my_aws_key"' "$(cat "$workdir/custom.env")"

    # Test 6: --stdout and -c streams dotenv syntax directly without writing
    rm -f "$workdir/.env"
    output=$(cd "$workdir" && "$ENVAULT" export --stdout)
    assert_contains "export --stdout outputs AWS_ACCESS_KEY" 'AWS_ACCESS_KEY="my_aws_key"' "$output"
    assert_contains "export --stdout outputs STRIPE_SECRET" 'STRIPE_SECRET="sk_test_999"' "$output"
    if [ ! -f "$workdir/.env" ]; then
        echo -e "  ${GREEN}✓ PASS:${RESET} export --stdout does not create .env file"
        PASSED_COUNT=$((PASSED_COUNT + 1))
    else
        echo -e "  ${RED}✗ FAIL:${RESET} export --stdout should not create .env file"
        FAILED_COUNT=$((FAILED_COUNT + 1))
    fi

    output=$(cd "$workdir" && "$ENVAULT" export -c)
    assert_contains "export -c streams dotenv syntax" 'AWS_ACCESS_KEY="my_aws_key"' "$output"

    # Test 7: -s / --shell exports bash syntax silently
    output=$(cd "$workdir" && "$ENVAULT" export -s)
    assert_contains "export -s formats export AWS_ACCESS_KEY" 'export AWS_ACCESS_KEY=' "$output"
    assert_contains "export -s formats export STRIPE_SECRET" 'export STRIPE_SECRET=' "$output"
    assert_contains "export -s safely escapes special characters" 'export SPECIAL_SECRET=' "$output"
    if [[ "$output" != *"Exported credentials"* ]]; then
        echo -e "  ${GREEN}✓ PASS:${RESET} export -s is silent without log messages"
        PASSED_COUNT=$((PASSED_COUNT + 1))
    else
        echo -e "  ${RED}✗ FAIL:${RESET} export -s should be silent without log messages"
        FAILED_COUNT=$((FAILED_COUNT + 1))
    fi

    # Test that eval executes cleanly on export -s output
    eval "$output"
    assert_equals "eval ingestion sets AWS_ACCESS_KEY" "my_aws_key" "$AWS_ACCESS_KEY"
    assert_equals "eval ingestion sets STRIPE_SECRET" "sk_test_999" "$STRIPE_SECRET"
    assert_equals "eval ingestion sets SPECIAL_SECRET with quotes and dollar signs intact" 'p@ss"w$ord'\''123' "$SPECIAL_SECRET"

    # Test 8: Filtered export
    output=$("$ENVAULT" export --stdout aws_access_key)
    assert_contains "export filtered includes requested key" 'AWS_ACCESS_KEY="my_aws_key"' "$output"
    if [[ "$output" != *"STRIPE_SECRET"* ]]; then
        echo -e "  ${GREEN}✓ PASS:${RESET} export filtered excludes unrequested key"
        PASSED_COUNT=$((PASSED_COUNT + 1))
    else
        echo -e "  ${RED}✗ FAIL:${RESET} export filtered should not include unrequested key"
        FAILED_COUNT=$((FAILED_COUNT + 1))
    fi

    # Test 9: Warning on missing keychain entry
    echo "missing_key_in_vault" >> "$TEST_CONFIG/.keys_list"
    output=$("$ENVAULT" export -s 2>&1)
    assert_contains "export warns on missing keychain entry" "Warning: Key 'missing_key_in_vault' not found in Keychain." "$output"
}

suite_rm() {
    echo -e "\n${YELLOW}Running Suite: rm Subcommand${RESET}"
    local output code

    set +e
    output=$("$ENVAULT" rm 2>&1)
    code=$?
    set -e
    assert_exit_code "rm without args exits 1" 1 "$code"
    assert_contains "rm without args shows usage" "Usage: envault rm <service_name>" "$output"

    output=$("$ENVAULT" rm untracked_service 2>&1)
    assert_contains "rm on untracked service prints not tracked info" "was not tracked in list" "$output"

    echo "secret_to_remove" > "$MOCK_STORE/service_to_remove"
    echo "service_to_remove" >> "$TEST_CONFIG/.keys_list"

    assert_contains "Service exists in tracking before rm" "service_to_remove" "$(cat "$TEST_CONFIG/.keys_list")"
    assert_equals "Secret exists in keychain before rm" "secret_to_remove" "$(cat "$MOCK_STORE/service_to_remove")"

    output=$("$ENVAULT" rm service_to_remove 2>&1)
    assert_contains "rm displays success message" "Removed 'service_to_remove' from vault tracking list and Keychain." "$output"

    if ! grep -Fxq "service_to_remove" "$TEST_CONFIG/.keys_list"; then
        echo -e "  ${GREEN}✓ PASS:${RESET} rm purged entry from .keys_list"
        PASSED_COUNT=$((PASSED_COUNT + 1))
    else
        echo -e "  ${RED}✗ FAIL:${RESET} Entry still found in .keys_list after rm"
        FAILED_COUNT=$((FAILED_COUNT + 1))
    fi

    if [ ! -f "$MOCK_STORE/service_to_remove" ]; then
        echo -e "  ${GREEN}✓ PASS:${RESET} rm purged entry from Keychain"
        PASSED_COUNT=$((PASSED_COUNT + 1))
    else
        echo -e "  ${RED}✗ FAIL:${RESET} Entry still exists in Keychain after rm"
        FAILED_COUNT=$((FAILED_COUNT + 1))
    fi
}

suite_env() {
    echo -e "\n${YELLOW}Running Suite: CURRENT_USER Environment Fallback${RESET}"
    local output
    echo "fallback_secret_999" | env -u USER ENVAULT_TTY=/dev/stdin "$ENVAULT" add fallback_user_test >/dev/null 2>&1
    output=$(env -u USER "$ENVAULT" export -s fallback_user_test 2>&1)
    assert_contains "Fetch succeeds with export when USER env var is unset" 'export FALLBACK_USER_TEST=' "$output"
}

suite_validation() {
    echo -e "\n${YELLOW}Running Suite: Key Name Validation${RESET}"
    local output code

    # Reject hyphenated keys
    set +e
    output=$(echo "val" | ENVAULT_TTY=/dev/stdin "$ENVAULT" add stripe-secret-key 2>&1)
    code=$?
    set -e
    assert_exit_code "add with hyphen exits 1" 1 "$code"
    assert_contains "add with hyphen outputs invalid key error" "Invalid key name 'stripe-secret-key'" "$output"
    assert_contains "add error mentions underscores" "alphanumeric characters and underscores" "$output"

    # Reject special characters
    set +e
    output=$(echo "val" | ENVAULT_TTY=/dev/stdin "$ENVAULT" add "api.key" 2>&1)
    code=$?
    set -e
    assert_exit_code "add with dot exits 1" 1 "$code"

    set +e
    output=$(echo "val" | ENVAULT_TTY=/dev/stdin "$ENVAULT" add "stripe@key" 2>&1)
    code=$?
    set -e
    assert_exit_code "add with @ exits 1" 1 "$code"

    set +e
    output=$(echo "val" | ENVAULT_TTY=/dev/stdin "$ENVAULT" add "stripe key" 2>&1)
    code=$?
    set -e
    assert_exit_code "add with space exits 1" 1 "$code"

    # Check and rm validation
    set +e
    output=$("$ENVAULT" check "invalid-key" 2>&1)
    code=$?
    set -e
    assert_exit_code "check with invalid key exits 1" 1 "$code"
    assert_contains "check with invalid key displays error" "Invalid key name" "$output"

    set +e
    output=$("$ENVAULT" rm "invalid-key" 2>&1)
    code=$?
    set -e
    assert_exit_code "rm with invalid key exits 1" 1 "$code"
    assert_contains "rm with invalid key displays error" "Invalid key name" "$output"
}

suite_case_insensitivity() {
    echo -e "\n${YELLOW}Running Suite: Case-Insensitivity & Normalization${RESET}"
    local output code

    # 1. Add key using UPPERCASE input -> stored as lowercase in .keys_list and keychain
    output=$(echo "case_secret_123" | ENVAULT_TTY=/dev/stdin "$ENVAULT" add MY_CASE_SERVICE 2>&1)
    assert_contains "add with uppercase stores successfully" "Successfully stored 'my_case_service'!" "$output"
    assert_contains "stored key in .keys_list is lowercase" "my_case_service" "$(cat "$TEST_CONFIG/.keys_list")"
    assert_equals "stored key in keychain is lowercase" "case_secret_123" "$(cat "$MOCK_STORE/my_case_service")"

    # 2. Check using lowercase, uppercase, and mixed case
    set +e
    output=$("$ENVAULT" check my_case_service 2>&1)
    code=$?
    set -e
    assert_exit_code "check with lowercase exits 0" 0 "$code"
    assert_contains "check lowercase matches" "is currently tracked" "$output"

    set +e
    output=$("$ENVAULT" check MY_CASE_SERVICE 2>&1)
    code=$?
    set -e
    assert_exit_code "check with uppercase exits 0" 0 "$code"
    assert_contains "check uppercase matches" "is currently tracked" "$output"

    set +e
    output=$("$ENVAULT" check My_Case_Service 2>&1)
    code=$?
    set -e
    assert_exit_code "check with mixed case exits 0" 0 "$code"
    assert_contains "check mixed case matches" "is currently tracked" "$output"

    # 3. Add lowercase key then attempt to add UPPERCASE variant -> triggers overwrite prompt instead of duplicate
    local input_abort
    input_abort=$(printf "n\n")
    output=$(echo "$input_abort" | ENVAULT_TTY=/dev/stdin "$ENVAULT" add my_case_service 2>&1)
    assert_contains "add uppercase variant prompts overwrite" "already exists. Overwrite?" "$output"
    assert_contains "add uppercase variant aborts" "Aborted." "$output"

    # Verify no duplicate entries in .keys_list
    local match_count
    match_count=$(grep -cx "my_case_service" "$TEST_CONFIG/.keys_list")
    assert_equals "no duplicate entry created in .keys_list" "1" "$match_count"

    # 4. Export with case-insensitive argument
    output=$("$ENVAULT" export --stdout MY_CASE_SERVICE)
    assert_contains "export finds key with uppercase argument" 'MY_CASE_SERVICE="case_secret_123"' "$output"

    # 5. Remove using uppercase argument
    output=$("$ENVAULT" rm MY_CASE_SERVICE 2>&1)
    assert_contains "rm with uppercase argument succeeds" "Removed 'my_case_service' from vault tracking list" "$output"
    if ! grep -Fxq "my_case_service" "$TEST_CONFIG/.keys_list"; then
        echo -e "  ${GREEN}✓ PASS:${RESET} rm purged lowercase entry from .keys_list"
        PASSED_COUNT=$((PASSED_COUNT + 1))
    else
        echo -e "  ${RED}✗ FAIL:${RESET} Entry still found in .keys_list after case-insensitive rm"
        FAILED_COUNT=$((FAILED_COUNT + 1))
    fi
}

# ------------------------------------------------------------------------------
# Dispatcher / Main Runner
# ------------------------------------------------------------------------------
echo -e "\n${BLUE}${BOLD}================================================${RESET}"
echo -e "${BLUE}${BOLD}            envault Test Suite                  ${RESET}"
echo -e "${BLUE}${BOLD}================================================${RESET}"

TARGET="${1:-all}"
case "$TARGET" in
    router)      suite_router ;;
    check)       suite_check ;;
    ls)          suite_ls ;;
    add)         suite_add ;;
    export)      suite_export ;;
    rm)          suite_rm ;;
    env)         suite_env ;;
    validation)  suite_validation ;;
    case)        suite_case_insensitivity ;;
    all)
        suite_router
        suite_check
        suite_ls
        suite_add
        suite_export
        suite_rm
        suite_env
        suite_validation
        suite_case_insensitivity
        ;;
    *)
        echo -e "${RED}Unknown suite: '$TARGET'. Available: router, check, ls, add, export, rm, env, validation, case, all${RESET}"
        exit 1
        ;;
esac

echo -e "\n${BLUE}${BOLD}================================================${RESET}"
echo -e "${BLUE}${BOLD}                 Test Summary                   ${RESET}"
echo -e "${BLUE}${BOLD}================================================${RESET}"
echo -e "  ${GREEN}Assertions passed: $PASSED_COUNT${RESET}"
if [ "$FAILED_COUNT" -gt 0 ]; then
    echo -e "  ${RED}Assertions failed: $FAILED_COUNT${RESET}"
    exit 1
else
    echo -e "  ${GREEN}All tests passed successfully!${RESET}"
    exit 0
fi
