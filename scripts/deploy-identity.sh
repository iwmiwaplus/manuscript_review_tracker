#!/usr/bin/env bash
#
# deploy-identity.sh JSON_FILE
#
# JSON_FILE is the stdout (alone) of `vercel deploy --prebuilt --prod --format json`
# (vercel 59.25.4): exactly one JSON object with, among others, "id", "url",
# "readyState" and "target". On success prints exactly two lines:
#   deployment_id=<id>
#   url=https://<host>
# Anything else (missing/empty file, not exactly one JSON object, bad id or host,
# target not production, readyState not READY) prints only
# "stage vercel-deploy-identity: FAIL (exit 1)" and exits 1.
#
# All checks live in the one jq program below. \A and \z anchor the whole
# string: jq's ^/$ would also match around an embedded newline.

fail() {
  printf 'stage vercel-deploy-identity: FAIL (exit 1)\n'
  exit 1
}

[ "$#" -eq 1 ] && [ -f "$1" ] || fail

IDENTITY=$(jq -r -s '
  if length != 1 or (.[0] | type) != "object" then error("shape") else .[0] end
  | if (.id | type) == "string" and (.id | test("\\Adpl_[A-Za-z0-9]+\\z"))
      and (.url | type) == "string"
      and (.url | test("\\Ahttps://[a-z0-9-]+(\\.[a-z0-9-]+)*\\.vercel\\.app\\z"))
      and .target == "production"
      and .readyState == "READY"
    then "deployment_id=\(.id)\nurl=\(.url)"
    else error("identity") end
' "$1" 2>/dev/null) || fail

printf '%s\n' "$IDENTITY"
