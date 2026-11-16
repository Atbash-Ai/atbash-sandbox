#!/bin/sh
# Atbash sandbox entrypoint — generates agent key on first run

CONFIG_DIR="$HOME/.config/atbash"
CONFIG_FILE="$CONFIG_DIR/config.json"
TELEMETRY_FILE="$CONFIG_DIR/telemetry.json"
TELEMETRY_SEED="/opt/atbash/telemetry.json"

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

# Generate an agent keypair only if none is available — either via env var
# (ATBASH_AGENT_KEY, set by docker-compose .env or the cloud platform's
# secret store) or already-written ~/.config/atbash/config.json.
if [ -z "${ATBASH_AGENT_KEY:-}" ] && { [ ! -f "$CONFIG_FILE" ] || ! grep -q "agentKey" "$CONFIG_FILE" 2>/dev/null; }; then
  echo "Generating agent keypair..."
  atbash keygen
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
