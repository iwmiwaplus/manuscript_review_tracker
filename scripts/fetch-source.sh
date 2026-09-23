#!/usr/bin/env bash
#
# fetch-source.sh ALLOWLIST TAG DEST
#
# Refuses (printing verify-release.sh's lookup failure, e.g.
# "verify: FAIL not-allowlisted") unless TAG has an entry in ALLOWLIST; this
# runs before the deploy key is written or anything is fetched. Then fetches
# exactly refs/heads/main and refs/tags/TAG from the private source repository
# over SSH into a fresh git repository at DEST, without saving a
# remote. Prints "fetch: ok" or "fetch: FAIL" and exits accordingly.
#
# Required env: SOURCE_DEPLOY_KEY (non-empty), SOURCE_REPOSITORY (owner/name).
# Test mode: set CONTROLLER_TEST_MODE=1 and FETCH_URL_OVERRIDE=<local path>
# to fetch from a local fixture instead of over SSH; SOURCE_DEPLOY_KEY is not
# required in test mode.

fail() {
  printf 'fetch: FAIL\n'
  exit 1
}

if [ "$#" -ne 3 ]; then
  fail
fi

ALLOWLIST=$1
TAG=$2
DEST=$3

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)

if ! LOOKUP=$(bash "$SCRIPT_DIR/verify-release.sh" "$ALLOWLIST" "$TAG" 2>/dev/null); then
  printf '%s\n' "$LOOKUP"
  exit 1
fi

TEST_MODE=0
if [ "${CONTROLLER_TEST_MODE:-}" = "1" ] && [ -n "${FETCH_URL_OVERRIDE:-}" ]; then
  TEST_MODE=1
fi

if [ "$TEST_MODE" -ne 1 ] && [ -z "${SOURCE_DEPLOY_KEY:-}" ]; then
  fail
fi

REPO_RE='^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$'
if [ -z "${SOURCE_REPOSITORY:-}" ] || ! [[ "$SOURCE_REPOSITORY" =~ $REPO_RE ]]; then
  fail
fi

KNOWN_HOSTS="$SCRIPT_DIR/known_hosts"

KEY_FILE=""
# shellcheck disable=SC2329 # invoked indirectly via the trap below
cleanup() {
  if [ -n "$KEY_FILE" ] && [ -f "$KEY_FILE" ]; then
    rm -f "$KEY_FILE"
  fi
}
trap cleanup EXIT

NEED_KEY=0
if [ "$TEST_MODE" -ne 1 ]; then
  NEED_KEY=1
elif [ -n "${SOURCE_DEPLOY_KEY:-}" ]; then
  NEED_KEY=1
fi

if [ "$NEED_KEY" -eq 1 ]; then
  RUNNER_TEMP_DIR="${RUNNER_TEMP:-$(mktemp -d)}"
  KEY_FILE=$(mktemp "$RUNNER_TEMP_DIR/deploy-key.XXXXXX")
  chmod 600 "$KEY_FILE"
  printf '%s\n' "$SOURCE_DEPLOY_KEY" > "$KEY_FILE"
fi

if [ "$TEST_MODE" -eq 1 ]; then
  REMOTE_URL="$FETCH_URL_OVERRIDE"
else
  REMOTE_URL="git@github.com:${SOURCE_REPOSITORY}.git"
fi

if [ -n "$KEY_FILE" ]; then
  SSH_CMD="ssh -F /dev/null -o BatchMode=yes -o IdentitiesOnly=yes -o StrictHostKeyChecking=yes -o GlobalKnownHostsFile=/dev/null -i \"$KEY_FILE\" -o UserKnownHostsFile=\"$KNOWN_HOSTS\""
else
  SSH_CMD="ssh -F /dev/null -o BatchMode=yes -o IdentitiesOnly=yes -o StrictHostKeyChecking=yes -o GlobalKnownHostsFile=/dev/null -o UserKnownHostsFile=\"$KNOWN_HOSTS\""
fi

if ! git init --quiet "$DEST" >/dev/null 2>&1; then
  fail
fi

if ! GIT_SSH_COMMAND="$SSH_CMD" git -C "$DEST" -c transfer.fsckObjects=true fetch --quiet --no-tags "$REMOTE_URL" \
  "+refs/heads/main:refs/remotes/source/main" \
  "+refs/tags/${TAG}:refs/tags/${TAG}" >/dev/null 2>&1; then
  fail
fi

printf 'fetch: ok\n'
exit 0
