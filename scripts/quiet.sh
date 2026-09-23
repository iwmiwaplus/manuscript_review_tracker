#!/usr/bin/env bash
#
# quiet.sh STAGE CMD [ARGS...]
#
# Runs CMD ARGS... with stdout and stderr captured to a log file under
# $RUNNER_TEMP/controller-logs/STAGE.log (never printed), and reports only
# "stage STAGE: ok" or "stage STAGE: FAIL (exit N)". Exits with CMD's status.

if [ "$#" -lt 2 ]; then
  printf 'stage invalid: FAIL (exit 2)\n'
  exit 2
fi

STAGE=$1
shift

STAGE_RE='^[a-z0-9-]+$'
if ! [[ "$STAGE" =~ $STAGE_RE ]]; then
  printf 'stage invalid: FAIL (exit 2)\n'
  exit 2
fi

RUNNER_TEMP_DIR="${RUNNER_TEMP:-$(mktemp -d)}"
LOG_DIR="$RUNNER_TEMP_DIR/controller-logs"
mkdir -p "$LOG_DIR"
chmod 700 "$LOG_DIR"
LOG_FILE="$LOG_DIR/$STAGE.log"
: > "$LOG_FILE"
chmod 600 "$LOG_FILE"

"$@" >"$LOG_FILE" 2>&1
STATUS=$?

if [ "$STATUS" -eq 0 ]; then
  printf 'stage %s: ok\n' "$STAGE"
else
  printf 'stage %s: FAIL (exit %s)\n' "$STAGE" "$STATUS"
fi

exit "$STATUS"
