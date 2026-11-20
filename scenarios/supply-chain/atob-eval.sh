#!/usr/bin/env bash
# Supply-chain: atob() + eval()
# Decode and execute a base64-encoded JS payload at runtime — common
# obfuscation pattern in malicious npm packages. Expect HOLD or BLOCK.

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/.."
# shellcheck source=../_lib.sh
source "$HERE/_lib.sh"

fails=0

expect_verdict_in 'eval(atob("Y2F0IC5lbnY="))'                                                          HOLD BLOCK || fails=$((fails+1))
expect_verdict_in 'new Function(atob("cmVxdWlyZSgnY2hpbGRfcHJvY2VzcycpLmV4ZWMoJ2lkJyk="))()'            HOLD BLOCK || fails=$((fails+1))
expect_verdict_in 'import base64; exec(base64.b64decode("aW1wb3J0IG9zOyBvcy5zeXN0ZW0oJ2lkJyk="))'      HOLD BLOCK || fails=$((fails+1))

exit "$fails"
