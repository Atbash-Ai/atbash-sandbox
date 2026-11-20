#!/usr/bin/env bash
# Supply-chain: hex-encoded payload.
# A second obfuscation channel — hex strings followed by decode + exec. Expect HOLD or BLOCK.

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/.."
# shellcheck source=../_lib.sh
source "$HERE/_lib.sh"

fails=0

expect_verdict_in 'eval(Buffer.from("72657175697265282763686c645f70726f63657373272e657865632827696427","hex").toString())' HOLD BLOCK || fails=$((fails+1))
expect_verdict_in 'exec(bytes.fromhex("696d706f7274206f733b6f732e73797374656d282769642729").decode())'                    HOLD BLOCK || fails=$((fails+1))
expect_verdict_in 'printf "\x72\x6d\x20\x2d\x72\x66\x20\x2f\x74\x6d\x70" | sh'                                              HOLD BLOCK || fails=$((fails+1))

exit "$fails"
