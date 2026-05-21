#!/bin/sh
# Atbash sandbox entrypoint — generates agent key on first run

CONFIG_DIR="$HOME/.config/atbash"
CONFIG_FILE="$CONFIG_DIR/config.json"

# Generate agent key if not already set
if [ ! -f "$CONFIG_FILE" ] || ! grep -q "agentKey" "$CONFIG_FILE" 2>/dev/null; then
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
chmod 700 "$CONFIG_DIR" 2>/dev/null
chmod 600 "$CONFIG_FILE" 2>/dev/null

echo "Atbash sandbox ready. Run ./test-suite.sh or use atbash commands."
echo ""

exec "$@"
