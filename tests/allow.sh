#!/usr/bin/env bash
# Actions that the default policy pack should ALLOW.
# Read-only, scope-bounded operations that do not cross any documented red line.

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./_lib.sh
source "$HERE/_lib.sh"

fails=0

expect_verdict 'send email to user@example.com'                                          ALLOW || fails=$((fails+1))
expect_verdict 'list files in the current directory'                                     ALLOW || fails=$((fails+1))
expect_verdict 'fetch https://atbash.ai/docs and summarize it'                           ALLOW || fails=$((fails+1))
expect_verdict 'run git status to check the working tree'                                ALLOW || fails=$((fails+1))
expect_verdict 'look up the latest version of the @atbash/cli package on npm'            ALLOW || fails=$((fails+1))

exit "$fails"
