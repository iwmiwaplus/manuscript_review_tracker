#!/usr/bin/env bash
#
# check-run.sh
#
# Refuses a run that is not a fresh dispatch by the release promoter from the
# current main of this controller:
#   - RELEASE_PROMOTER must be non-empty and equal both GITHUB_ACTOR and
#     GITHUB_TRIGGERING_ACTOR, else "verify: FAIL actor-not-promoter";
#   - GITHUB_RUN_ATTEMPT must be 1 and refs/heads/main of GITHUB_REPOSITORY
#     (read anonymously) must be exactly GITHUB_SHA, else
#     "verify: FAIL stale-run". A re-run would replay an older workflow file
#     and allowlist; a run from a non-main or superseded commit likewise.
# Prints exactly "run: ok" and exits 0 on success. All git output suppressed.
#
# Test mode: CONTROLLER_TEST_MODE=1 and MAIN_URL_OVERRIDE=<local path> read
# main from a local fixture repository instead of github.com.

fail() {
  printf 'verify: FAIL %s\n' "$1"
  exit 1
}

if [ -z "${RELEASE_PROMOTER:-}" ] \
  || [ "$RELEASE_PROMOTER" != "${GITHUB_ACTOR:-}" ] \
  || [ "$RELEASE_PROMOTER" != "${GITHUB_TRIGGERING_ACTOR:-}" ]; then
  fail actor-not-promoter
fi

if [ "${GITHUB_RUN_ATTEMPT:-}" != "1" ]; then
  fail stale-run
fi

REPO_RE='^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$'
if [ -z "${GITHUB_REPOSITORY:-}" ] || ! [[ "$GITHUB_REPOSITORY" =~ $REPO_RE ]]; then
  fail stale-run
fi

if [ "${CONTROLLER_TEST_MODE:-}" = "1" ] && [ -n "${MAIN_URL_OVERRIDE:-}" ]; then
  MAIN_URL="$MAIN_URL_OVERRIDE"
else
  MAIN_URL="https://github.com/${GITHUB_REPOSITORY}.git"
fi

# Anonymous read: no user/system git config (so no credential helper or
# persisted auth header), no prompt, run outside any repository.
MAIN_LINE=$(GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 GIT_TERMINAL_PROMPT=0 \
  git -C / ls-remote "$MAIN_URL" refs/heads/main 2>/dev/null) || fail stale-run

if [ -z "${GITHUB_SHA:-}" ] || [ "$MAIN_LINE" != "${GITHUB_SHA}"$'\t'"refs/heads/main" ]; then
  fail stale-run
fi

printf 'run: ok\n'
exit 0
