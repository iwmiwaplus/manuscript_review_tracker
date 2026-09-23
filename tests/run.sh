#!/usr/bin/env bash
#
# Self-contained test suite for scripts/verify-release.sh, scripts/fetch-source.sh
# and scripts/quiet.sh. Builds fixture repositories under mktemp -d, runs every
# required case, prints PASS/FAIL per case, and exits non-zero if any case fails.

set -u

HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/.." && pwd)
VERIFY="$ROOT/scripts/verify-release.sh"
FETCH="$ROOT/scripts/fetch-source.sh"
QUIET="$ROOT/scripts/quiet.sh"
ALLOWLIST_REAL="$ROOT/releases/naga-pilot.json"

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

PASS_COUNT=0
FAIL_COUNT=0

ok() {
  printf 'PASS %s\n' "$1"
  PASS_COUNT=$((PASS_COUNT + 1))
}

bad() {
  printf 'FAIL %s: %s\n' "$1" "$2"
  FAIL_COUNT=$((FAIL_COUNT + 1))
}

git_fx() {
  repo=$1
  shift
  git -C "$repo" -c user.name="Fixture" -c user.email=fixture "$@"
}

make_allowlist() {
  out=$1
  tag=$2
  tagobj=$3
  commit=$4
  tree=$5
  jq -n --arg tag "$tag" --arg tagobj "$tagobj" --arg commit "$commit" --arg tree "$tree" \
    '{source_repository: "acme/example", releases: {($tag): {tag_object: $tagobj, commit: $commit, tree: $tree}}}' \
    >"$out"
}

fetch_src() {
  tag=$1
  url=$2
  dest=$(mktemp -d "$WORK/src.XXXXXX")
  out=$(FETCH_URL_OVERRIDE="$url" "$FETCH" "$tag" "$dest" 2>&1)
  status=$?
  if [ "$status" -ne 0 ]; then
    printf 'SETUP FAILURE: fetch %s from %s failed: %s\n' "$tag" "$url" "$out" >&2
    exit 1
  fi
  printf '%s' "$dest"
}

run_verify() {
  VERIFY_STDOUT=$("$VERIFY" "$1" "$2" "$3" 2>"$WORK/stderr.tmp")
  VERIFY_EXIT=$?
  VERIFY_STDERR=$(cat "$WORK/stderr.tmp")
}

check_case() {
  name=$1
  expected_out=$2
  expected_exit=$3
  if [ "$VERIFY_STDOUT" = "$expected_out" ] && [ "$VERIFY_EXIT" -eq "$expected_exit" ] && [ -z "$VERIFY_STDERR" ]; then
    ok "$name"
  else
    bad "$name" "stdout=[$VERIFY_STDOUT] exit=$VERIFY_EXIT stderr=[$VERIFY_STDERR] expected_out=[$expected_out] expected_exit=$expected_exit"
  fi
}

## --- Build the fixture upstream repository ---------------------------------

UPSTREAM="$WORK/upstream"
git -c init.defaultBranch=main init --quiet "$UPSTREAM"

printf 'one\n' >"$UPSTREAM/file.txt"
git_fx "$UPSTREAM" add file.txt
git_fx "$UPSTREAM" commit --quiet -m "commit 1"

printf 'two\n' >"$UPSTREAM/file.txt"
git_fx "$UPSTREAM" add file.txt
git_fx "$UPSTREAM" commit --quiet -m "commit 2"

git_fx "$UPSTREAM" tag -a v9.9.9-rc.1 -m "release 9.9.9-rc.1"
git_fx "$UPSTREAM" tag v9.9.8

git_fx "$UPSTREAM" checkout --quiet -b side
printf 'side\n' >"$UPSTREAM/side.txt"
git_fx "$UPSTREAM" add side.txt
git_fx "$UPSTREAM" commit --quiet -m "side commit"
git_fx "$UPSTREAM" tag -a v9.9.7 -m "release 9.9.7 (side)"
git_fx "$UPSTREAM" checkout --quiet main

git_fx "$UPSTREAM" tag -a v9.9.6-inner -m "inner tag"
INNER_TAG_OBJ=$(git -C "$UPSTREAM" rev-parse refs/tags/v9.9.6-inner)
git_fx "$UPSTREAM" -c advice.nestedTag=false tag -a v9.9.6 "$INNER_TAG_OBJ" -m "outer tag pointing at a tag"

V999_TAG_OBJ=$(git -C "$UPSTREAM" rev-parse refs/tags/v9.9.9-rc.1)
V999_COMMIT=$(git -C "$UPSTREAM" rev-parse "refs/tags/v9.9.9-rc.1^{commit}")
V999_TREE=$(git -C "$UPSTREAM" rev-parse "refs/tags/v9.9.9-rc.1^{tree}")

V998_OBJ=$(git -C "$UPSTREAM" rev-parse refs/tags/v9.9.8)

V997_TAG_OBJ=$(git -C "$UPSTREAM" rev-parse refs/tags/v9.9.7)
V997_COMMIT=$(git -C "$UPSTREAM" rev-parse "refs/tags/v9.9.7^{commit}")
V997_TREE=$(git -C "$UPSTREAM" rev-parse "refs/tags/v9.9.7^{tree}")

V996_TAG_OBJ=$(git -C "$UPSTREAM" rev-parse refs/tags/v9.9.6)

export CONTROLLER_TEST_MODE=1
export SOURCE_REPOSITORY="acme/example"
RUNNER_TEMP_DIR="$WORK/runner-temp"
mkdir -p "$RUNNER_TEMP_DIR"
export RUNNER_TEMP="$RUNNER_TEMP_DIR"

## --- Case 1: correct entry --------------------------------------------------

A1="$WORK/allow1.json"
make_allowlist "$A1" "v9.9.9-rc.1" "$V999_TAG_OBJ" "$V999_COMMIT" "$V999_TREE"
S1=$(fetch_src "v9.9.9-rc.1" "$UPSTREAM") || exit 1
run_verify "$A1" "v9.9.9-rc.1" "$S1"
check_case "case1-correct-entry" "verify: ok" 0

HEAD_SHA=$(git -C "$S1" rev-parse HEAD)
if git -C "$S1" symbolic-ref -q HEAD >/dev/null 2>&1; then
  DETACHED=no
else
  DETACHED=yes
fi
if [ "$DETACHED" = "yes" ] && [ "$HEAD_SHA" = "$V999_COMMIT" ]; then
  ok "case1-head-detached"
else
  bad "case1-head-detached" "detached=$DETACHED head=$HEAD_SHA expected=$V999_COMMIT"
fi

## --- Case 2: tag absent from allowlist --------------------------------------

A2="$WORK/allow2.json"
make_allowlist "$A2" "v9.9.8" "$V998_OBJ" "$V998_OBJ" "$V998_OBJ"
S2=$(fetch_src "v9.9.9-rc.1" "$UPSTREAM") || exit 1
run_verify "$A2" "v9.9.9-rc.1" "$S2"
check_case "case2-not-allowlisted" "verify: FAIL not-allowlisted" 1

## --- Cases 3-5: invalid tag shapes -------------------------------------------

S3=$(fetch_src "v9.9.9-rc.1" "$UPSTREAM") || exit 1

run_verify "$A1" "main" "$S3"
check_case "case3-invalid-tag-main" "verify: FAIL invalid-tag" 1

run_verify "$A1" "$V999_COMMIT" "$S3"
check_case "case4-invalid-tag-sha" "verify: FAIL invalid-tag" 1

run_verify "$A1" "v1.2.0-rc.1;id" "$S3"
check_case "case5-invalid-tag-injection" "verify: FAIL invalid-tag" 1

## --- Case 6: lightweight tag -------------------------------------------------

A6="$WORK/allow6.json"
make_allowlist "$A6" "v9.9.8" "$V998_OBJ" "$V998_OBJ" "$V998_OBJ"
S6=$(fetch_src "v9.9.8" "$UPSTREAM") || exit 1
run_verify "$A6" "v9.9.8" "$S6"
check_case "case6-not-annotated" "verify: FAIL not-annotated" 1

## --- Case 7: tag object altered in allowlist ---------------------------------

A7="$WORK/allow7.json"
BAD_OBJ="0000000000000000000000000000000000000000"
make_allowlist "$A7" "v9.9.9-rc.1" "$BAD_OBJ" "$V999_COMMIT" "$V999_TREE"
S7=$(fetch_src "v9.9.9-rc.1" "$UPSTREAM") || exit 1
run_verify "$A7" "v9.9.9-rc.1" "$S7"
check_case "case7-tag-object-mismatch" "verify: FAIL tag-object-mismatch" 1

## --- Case 8: tag re-created after allowlisting -------------------------------

UPSTREAM8="$WORK/upstream8"
cp -R "$UPSTREAM" "$UPSTREAM8"
git_fx "$UPSTREAM8" tag -d v9.9.9-rc.1 >/dev/null
git_fx "$UPSTREAM8" tag -a v9.9.9-rc.1 -m "recreated release 9.9.9-rc.1" main >/dev/null

A8="$WORK/allow8.json"
make_allowlist "$A8" "v9.9.9-rc.1" "$V999_TAG_OBJ" "$V999_COMMIT" "$V999_TREE"
S8=$(fetch_src "v9.9.9-rc.1" "$UPSTREAM8") || exit 1
run_verify "$A8" "v9.9.9-rc.1" "$S8"
check_case "case8-tag-recreated-mismatch" "verify: FAIL tag-object-mismatch" 1

## --- Case 9: correct tag object, wrong commit --------------------------------

A9="$WORK/allow9.json"
WRONG_COMMIT="1111111111111111111111111111111111111111"
make_allowlist "$A9" "v9.9.9-rc.1" "$V999_TAG_OBJ" "$WRONG_COMMIT" "$V999_TREE"
S9=$(fetch_src "v9.9.9-rc.1" "$UPSTREAM") || exit 1
run_verify "$A9" "v9.9.9-rc.1" "$S9"
check_case "case9-commit-mismatch" "verify: FAIL commit-mismatch" 1

## --- Case 10: correct tag object and commit, wrong tree ----------------------

A10="$WORK/allow10.json"
WRONG_TREE="2222222222222222222222222222222222222222"
make_allowlist "$A10" "v9.9.9-rc.1" "$V999_TAG_OBJ" "$V999_COMMIT" "$WRONG_TREE"
S10=$(fetch_src "v9.9.9-rc.1" "$UPSTREAM") || exit 1
run_verify "$A10" "v9.9.9-rc.1" "$S10"
check_case "case10-tree-mismatch" "verify: FAIL tree-mismatch" 1

## --- Case 11: tag not on main -------------------------------------------------

A11="$WORK/allow11.json"
make_allowlist "$A11" "v9.9.7" "$V997_TAG_OBJ" "$V997_COMMIT" "$V997_TREE"
S11=$(fetch_src "v9.9.7" "$UPSTREAM") || exit 1
run_verify "$A11" "v9.9.7" "$S11"
check_case "case11-not-on-main" "verify: FAIL not-on-main" 1

## --- Case 12: tag of a tag -----------------------------------------------------

A12="$WORK/allow12.json"
make_allowlist "$A12" "v9.9.6" "$V996_TAG_OBJ" "$V999_COMMIT" "$V999_TREE"
S12=$(fetch_src "v9.9.6" "$UPSTREAM") || exit 1
run_verify "$A12" "v9.9.6" "$S12"
check_case "case12-tag-target-not-commit" "verify: FAIL tag-target-not-commit" 1

## --- Case 13: allowlist with non-hex commit ------------------------------------

A13="$WORK/allow13.json"
jq -n --arg tag "v9.9.9-rc.1" --arg tagobj "$V999_TAG_OBJ" --arg tree "$V999_TREE" \
  '{source_repository: "acme/example", releases: {($tag): {tag_object: $tagobj, commit: "not-a-sha", tree: $tree}}}' \
  >"$A13"
S13=$(fetch_src "v9.9.9-rc.1" "$UPSTREAM") || exit 1
run_verify "$A13" "v9.9.9-rc.1" "$S13"
check_case "case13-allowlist-invalid-nonhex" "verify: FAIL allowlist-invalid" 1

## --- Case 14: allowlist file not JSON -------------------------------------------

A14="$WORK/allow14.json"
printf 'not json at all {' >"$A14"
S14=$(fetch_src "v9.9.9-rc.1" "$UPSTREAM") || exit 1
run_verify "$A14" "v9.9.9-rc.1" "$S14"
check_case "case14-allowlist-invalid-notjson" "verify: FAIL allowlist-invalid" 1

## --- Case 14b: allowlist file empty -----------------------------------------------

A14B="$WORK/allow14b.json"
printf '' >"$A14B"
S14B=$(fetch_src "v9.9.9-rc.1" "$UPSTREAM") || exit 1
run_verify "$A14B" "v9.9.9-rc.1" "$S14B"
check_case "case14b-allowlist-invalid-empty" "verify: FAIL allowlist-invalid" 1

## --- Case 14c: .releases is not an object -----------------------------------------

A14C="$WORK/allow14c.json"
jq -n '{source_repository: "acme/example", releases: "nope"}' >"$A14C"
S14C=$(fetch_src "v9.9.9-rc.1" "$UPSTREAM") || exit 1
run_verify "$A14C" "v9.9.9-rc.1" "$S14C"
check_case "case14c-allowlist-invalid-releases-not-object" "verify: FAIL allowlist-invalid" 1

## --- Case 15: quiet.sh success ---------------------------------------------------

MARKER15="marker-quiet-success-$$"
Q_OUT=$("$QUIET" demo sh -c "printf '%s' \"$MARKER15\"" 2>"$WORK/q15err.tmp")
Q_EXIT=$?
Q_ERR=$(cat "$WORK/q15err.tmp")
LOG15="$RUNNER_TEMP/controller-logs/demo.log"
if [ "$Q_OUT" = "stage demo: ok" ] && [ "$Q_EXIT" -eq 0 ] && [ -z "$Q_ERR" ] \
  && ! printf '%s%s' "$Q_OUT" "$Q_ERR" | grep -q "$MARKER15" \
  && [ -f "$LOG15" ] && grep -q "$MARKER15" "$LOG15"; then
  ok "case15-quiet-success"
else
  bad "case15-quiet-success" "out=[$Q_OUT] exit=$Q_EXIT err=[$Q_ERR]"
fi

## --- Case 16: quiet.sh failure ----------------------------------------------------

MARKER16="marker-quiet-fail-$$"
Q_OUT=$("$QUIET" demo sh -c "printf '%s' \"$MARKER16\"; exit 7" 2>"$WORK/q16err.tmp")
Q_EXIT=$?
Q_ERR=$(cat "$WORK/q16err.tmp")
LOG16="$RUNNER_TEMP/controller-logs/demo.log"
if [ "$Q_OUT" = "stage demo: FAIL (exit 7)" ] && [ "$Q_EXIT" -eq 7 ] && [ -z "$Q_ERR" ] \
  && ! printf '%s%s' "$Q_OUT" "$Q_ERR" | grep -q "$MARKER16" \
  && [ -f "$LOG16" ] && grep -q "$MARKER16" "$LOG16"; then
  ok "case16-quiet-failure"
else
  bad "case16-quiet-failure" "out=[$Q_OUT] exit=$Q_EXIT err=[$Q_ERR]"
fi

## --- Case 17: quiet.sh bad stage name ----------------------------------------------

Q_OUT=$("$QUIET" "Bad Name" true 2>"$WORK/q17err.tmp")
Q_EXIT=$?
Q_ERR=$(cat "$WORK/q17err.tmp")
if [ "$Q_OUT" = "stage invalid: FAIL (exit 2)" ] && [ "$Q_EXIT" -eq 2 ] && [ -z "$Q_ERR" ]; then
  ok "case17-quiet-bad-stage"
else
  bad "case17-quiet-bad-stage" "out=[$Q_OUT] exit=$Q_EXIT err=[$Q_ERR]"
fi

## --- Case 18: fetch-source leaves no remote and no key file ------------------------

RUNNER_TEMP18="$WORK/runner-temp-18"
mkdir -p "$RUNNER_TEMP18"
DEST18="$WORK/dest18"
F18_OUT=$(CONTROLLER_TEST_MODE=1 FETCH_URL_OVERRIDE="$UPSTREAM" SOURCE_REPOSITORY="acme/example" \
  SOURCE_DEPLOY_KEY="dummy-test-key-$$" RUNNER_TEMP="$RUNNER_TEMP18" \
  "$FETCH" "v9.9.9-rc.1" "$DEST18" 2>"$WORK/f18err.tmp")
F18_EXIT=$?
REMOTE_CFG=$(git -C "$DEST18" config --get-regexp '^remote\.' 2>/dev/null)
LEFTOVER_KEYS=$(find "$RUNNER_TEMP18" -type f 2>/dev/null)
if [ "$F18_EXIT" -eq 0 ] && [ "$F18_OUT" = "fetch: ok" ] && [ -z "$REMOTE_CFG" ] && [ -z "$LEFTOVER_KEYS" ]; then
  ok "case18-fetch-no-remote-no-key"
else
  bad "case18-fetch-no-remote-no-key" "exit=$F18_EXIT out=[$F18_OUT] remote=[$REMOTE_CFG] leftover=[$LEFTOVER_KEYS]"
fi

## --- Case 19: real allowlist validates ----------------------------------------------

RTAGOBJ=$(jq -r '.releases["v1.2.0-rc.1"].tag_object // empty' "$ALLOWLIST_REAL")
RCOMMIT=$(jq -r '.releases["v1.2.0-rc.1"].commit // empty' "$ALLOWLIST_REAL")
RTREE=$(jq -r '.releases["v1.2.0-rc.1"].tree // empty' "$ALLOWLIST_REAL")
HEX_RE='^[0-9a-f]{40}$'
if [[ "$RTAGOBJ" =~ $HEX_RE ]] && [[ "$RCOMMIT" =~ $HEX_RE ]] && [[ "$RTREE" =~ $HEX_RE ]] \
  && [ "$RTAGOBJ" = "ace5cbf6cc78542cb5ab3400c5c499a8cecb109b" ] \
  && [ "$RCOMMIT" = "a7509f476347d80a280097172c2a816f20dc8a6b" ] \
  && [ "$RTREE" = "4082ff1ce152c224b74d5d195c5e6d58cb63d6f6" ]; then
  ok "case19-real-allowlist"
else
  bad "case19-real-allowlist" "tagobj=$RTAGOBJ commit=$RCOMMIT tree=$RTREE"
fi

## --- Summary --------------------------------------------------------------------------

printf '\n%d passed, %d failed\n' "$PASS_COUNT" "$FAIL_COUNT"
if [ "$FAIL_COUNT" -gt 0 ]; then
  exit 1
fi
exit 0
