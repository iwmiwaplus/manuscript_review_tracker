#!/usr/bin/env bash
#
# verify-release.sh ALLOWLIST TAG SOURCE_DIR
#
# Verifies that TAG in SOURCE_DIR (a git repository already fetched by
# fetch-source.sh) matches the entry recorded for it in ALLOWLIST, and that
# it is an annotated tag on a commit reachable from refs/remotes/source/main.
#
# Prints exactly "verify: ok" and exits 0 on success. Prints exactly
# "verify: FAIL <code>" and exits 1 on failure. Never prints anything else;
# all git output is suppressed.

fail() {
  printf 'verify: FAIL %s\n' "$1"
  exit 1
}

if [ "$#" -ne 3 ]; then
  fail invalid-tag
fi

ALLOWLIST=$1
TAG=$2
SOURCE_DIR=$3

TAG_RE='^v[0-9]+\.[0-9]+\.[0-9]+(-rc\.[0-9]+)?$'
if ! [[ "$TAG" =~ $TAG_RE ]]; then
  fail invalid-tag
fi

if ! jq empty "$ALLOWLIST" >/dev/null 2>&1; then
  fail allowlist-invalid
fi

HAS_ENTRY=$(jq -r --arg tag "$TAG" \
  'if (.releases[$tag] // null) == null then "no" else "yes" end' \
  "$ALLOWLIST" 2>/dev/null)
if [ "$HAS_ENTRY" != "yes" ]; then
  fail not-allowlisted
fi

ALLOW_TAG_OBJECT=$(jq -r --arg tag "$TAG" '.releases[$tag].tag_object // empty' "$ALLOWLIST" 2>/dev/null)
ALLOW_COMMIT=$(jq -r --arg tag "$TAG" '.releases[$tag].commit // empty' "$ALLOWLIST" 2>/dev/null)
ALLOW_TREE=$(jq -r --arg tag "$TAG" '.releases[$tag].tree // empty' "$ALLOWLIST" 2>/dev/null)

HEX_RE='^[0-9a-f]{40}$'
if ! [[ "$ALLOW_TAG_OBJECT" =~ $HEX_RE ]] || ! [[ "$ALLOW_COMMIT" =~ $HEX_RE ]] || ! [[ "$ALLOW_TREE" =~ $HEX_RE ]]; then
  fail allowlist-invalid
fi

if ! git -C "$SOURCE_DIR" show-ref --verify --quiet "refs/tags/$TAG" 2>/dev/null; then
  fail tag-missing
fi

TAG_TYPE=$(git -C "$SOURCE_DIR" cat-file -t "refs/tags/$TAG" 2>/dev/null)
if [ "$TAG_TYPE" != "tag" ]; then
  fail not-annotated
fi

ACTUAL_TAG_OBJECT=$(git -C "$SOURCE_DIR" rev-parse "refs/tags/$TAG" 2>/dev/null)
if [ "$ACTUAL_TAG_OBJECT" != "$ALLOW_TAG_OBJECT" ]; then
  fail tag-object-mismatch
fi

TAG_TARGET_TYPE=$(git -C "$SOURCE_DIR" cat-file -p "$ALLOW_TAG_OBJECT" 2>/dev/null | awk '/^type /{print $2; exit}')
if [ "$TAG_TARGET_TYPE" != "commit" ]; then
  fail tag-target-not-commit
fi

TAG_OBJECT_HEADER=$(git -C "$SOURCE_DIR" cat-file -p "$ALLOW_TAG_OBJECT" 2>/dev/null | awk '/^object /{print $2; exit}')
if [ "$TAG_OBJECT_HEADER" != "$ALLOW_COMMIT" ]; then
  fail commit-mismatch
fi

ACTUAL_TREE=$(git -C "$SOURCE_DIR" rev-parse "${ALLOW_COMMIT}^{tree}" 2>/dev/null)
if [ "$ACTUAL_TREE" != "$ALLOW_TREE" ]; then
  fail tree-mismatch
fi

if ! git -C "$SOURCE_DIR" show-ref --verify --quiet refs/remotes/source/main 2>/dev/null; then
  fail main-missing
fi

if ! git -C "$SOURCE_DIR" merge-base --is-ancestor "$ALLOW_COMMIT" refs/remotes/source/main 2>/dev/null; then
  fail not-on-main
fi

if ! git -C "$SOURCE_DIR" checkout --quiet --detach "$ALLOW_COMMIT" >/dev/null 2>&1; then
  fail checkout-mismatch
fi

ACTUAL_HEAD=$(git -C "$SOURCE_DIR" rev-parse HEAD 2>/dev/null)
if [ "$ACTUAL_HEAD" != "$ALLOW_COMMIT" ]; then
  fail checkout-mismatch
fi

printf 'verify: ok\n'
exit 0
