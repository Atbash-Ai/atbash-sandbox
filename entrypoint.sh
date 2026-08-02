#!/bin/sh
# Atbash sandbox entrypoint — generates agent key on first run

CONFIG_DIR="$HOME/.config/atbash"
CONFIG_FILE="$CONFIG_DIR/config.json"
TELEMETRY_FILE="$CONFIG_DIR/telemetry.json"
TELEMETRY_SEED="/opt/atbash/telemetry.json"
ATBASH_CLI_BIN="${ATBASH_CLI_BIN:-/usr/local/bin/atbash-safe}"

if [ -z "$ATBASH_CLI_BIN" ] || [ ! -x "$ATBASH_CLI_BIN" ]; then
  echo "Hardened Atbash CLI launcher is not installed or executable." >&2
  exit 2
fi

# Newly created files must be private even before the explicit chmod calls.
umask 077

# Ensure the config dir exists with the right perms. When docker-compose
# mounts $CONFIG_DIR as a fresh tmpfs (read-only root FS pattern), this
# directory starts empty on every boot.
mkdir -p "$CONFIG_DIR" 2>/dev/null
chmod 700 "$CONFIG_DIR" 2>/dev/null

# Seed telemetry.json from the shipped template if not already present.
# The SDK only honors opt-out from this file (env vars cannot disable it);
# seeding it guarantees the path exists and that the file is mode 0600.
if [ ! -f "$TELEMETRY_FILE" ] && [ -f "$TELEMETRY_SEED" ]; then
  cp "$TELEMETRY_SEED" "$TELEMETRY_FILE"
fi
chmod 600 "$TELEMETRY_FILE" 2>/dev/null

# Platform secret stores commonly inject the private agent key as an
# environment variable. Persist it into the mode-0600 config and remove it
# from the environment before starting the user's shell so child processes do
# not inherit a reusable credential.
if [ -n "${ATBASH_AGENT_KEY:-}" ]; then
  case "$ATBASH_AGENT_KEY" in
    *[!0-9a-fA-F]*|'')
      echo "ATBASH_AGENT_KEY must contain exactly 64 hexadecimal characters." >&2
      exit 2
      ;;
  esac
  if [ "${#ATBASH_AGENT_KEY}" -ne 64 ]; then
    echo "ATBASH_AGENT_KEY must contain exactly 64 hexadecimal characters." >&2
    exit 2
  fi

  TMP_CONFIG="$CONFIG_DIR/config.json.tmp.$$"
  if [ -f "$CONFIG_FILE" ]; then
    if ! jq --arg key "$ATBASH_AGENT_KEY" '.agentKey = ($key | ascii_downcase)' \
      "$CONFIG_FILE" > "$TMP_CONFIG"; then
      rm -f "$TMP_CONFIG"
      echo "Existing Atbash config is not valid JSON; refusing to overwrite it." >&2
      exit 2
    fi
  else
    if ! jq -n --arg key "$ATBASH_AGENT_KEY" '{agentKey: ($key | ascii_downcase)}' \
      > "$TMP_CONFIG"; then
      rm -f "$TMP_CONFIG"
      echo "Could not create Atbash config." >&2
      exit 2
    fi
  fi
  chmod 600 "$TMP_CONFIG"
  mv "$TMP_CONFIG" "$CONFIG_FILE"
  unset ATBASH_AGENT_KEY
fi

# Generate an agent keypair only if none is available — either via env var
# (ATBASH_AGENT_KEY, set by docker-compose .env or the cloud platform's
# secret store) or already-written ~/.config/atbash/config.json.
if [ ! -f "$CONFIG_FILE" ] || ! jq -e '.agentKey | strings | length == 64' "$CONFIG_FILE" >/dev/null 2>&1; then
  echo "Generating agent keypair..."
  "$ATBASH_CLI_BIN" keygen
  echo ""
  echo "Agent key generated. Onboard this agent at https://atbash.ai/"
  echo "  1. Create or select an organization"
  echo "  2. Add the agent using the public key above"
  echo "  3. Attach a policy pack"
  echo "  4. Set the org tier to Audit+ or Enforcement"
  echo ""
fi

# Verify permissions
chmod 600 "$CONFIG_FILE" 2>/dev/null

echo "Atbash sandbox ready. Run ./test-suite.sh or use atbash commands."
echo ""

exec "$@"
