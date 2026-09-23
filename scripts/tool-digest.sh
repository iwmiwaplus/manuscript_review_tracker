#!/usr/bin/env bash
#
# tool-digest.sh DIR...
#
# Prints one line: a sha256 hex digest over every regular file (content) and
# symlink (target string) under each DIR, paths relative to that DIR, sorted
# with LC_ALL=C. Skips any `.git` path component and the `tools/node_modules`
# subtree. On no arguments, a missing DIR, or any read error it prints
# "verify: FAIL tool-integrity" and exits 1. Prints nothing else.

set -o pipefail
export LC_ALL=C

fail() {
  printf 'verify: FAIL tool-integrity\n'
  exit 1
}

if command -v sha256sum >/dev/null 2>&1; then
  HASH=(sha256sum)
else
  HASH=(shasum -a 256)
fi

[ "$#" -gt 0 ] || fail
for d in "$@"; do
  [ -d "$d" ] || fail
done

# entries: "f <sha256>  ./path" per regular file, then "l ./path -> target"
# per symlink, for the current directory.
entries() {
  find . \( -name .git -o -path ./tools/node_modules \) -prune -o -type f -print0 \
    | sort -z | xargs -0 "${HASH[@]}" | sed 's/^/f /' || return 1
  find . \( -name .git -o -path ./tools/node_modules \) -prune -o -type l -print0 \
    | sort -z | while IFS= read -r -d '' p; do
      t=$(readlink "$p") || exit 1
      printf 'l %s -> %s\n' "$p" "$t"
    done
}

manifest() {
  i=0
  for d in "$@"; do
    i=$((i + 1))
    printf 'dir %s\n' "$i"
    (cd "$d" && entries) || return 1
  done
}

OUT=$(manifest "$@" 2>/dev/null | "${HASH[@]}" 2>/dev/null) || fail
DIGEST=${OUT%% *}
[[ "$DIGEST" =~ ^[0-9a-f]{64}$ ]] || fail
printf '%s\n' "$DIGEST"
