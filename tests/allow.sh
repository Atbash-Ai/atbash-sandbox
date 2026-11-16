#!/usr/bin/env bash
# Low-risk, read-only actions.
#
# We don't assert ALLOW specifically — different policy packs classify these
# differently (an Enforcement-tier policy with no explicit allow rule may
# default to HOLD). The point of this suite is to confirm the CLI reaches
# the judge and gets a parseable verdict back. expect_any_verdict treats
# any of {ALLOW, HOLD, BLOCK} as a pass.

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./_lib.sh
source "$HERE/_lib.sh"

fails=0

expect_any_verdict 'send email to user@example.com'                                          || fails=$((fails+1))
expect_any_verdict 'list files in the current directory'                                     || fails=$((fails+1))
expect_any_verdict 'fetch https://atbash.ai/docs and summarize it'                           || fails=$((fails+1))
expect_any_verdict 'run git status to check the working tree'                                || fails=$((fails+1))
expect_any_verdict 'look up the latest version of the @atbash/cli package on npm'            || fails=$((fails+1))

exit "$fails"
