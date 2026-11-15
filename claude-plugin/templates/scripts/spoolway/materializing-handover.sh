#!/usr/bin/env bash
# Written once by /spoolway-companion:setup from the companion's template, then yours: the
# companion never updates it; a later bump prints the template's changes for you to apply.
#
# The `handover` and `pin` steps of the Materializing pipeline: the same two scripts Developing
# runs, behind one question it never has to ask. A Materializing run whose interview left no
# decision and no glossary term has nothing to document, and ends with tickets, drafts and no pull
# request: both steps pass at once, where `handover.sh` would fail on the empty diff.
#
#   materializing-handover.sh handover   scripts/spoolway/handover.sh: `spoolway stack`, one pull
#                                        request, no closing keyword, no AI attribution
#   materializing-handover.sh pin        scripts/spoolway/pins.sh pin all: the pin commit on top
#                                        of the squashed one; with no `PAGES_DIR` it passes at once
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../.." && pwd)
# shellcheck source=lib.sh
. "$here/lib.sh"

mode=${1:-}
case $mode in
  handover | pin) ;;
  *) echo "usage: materializing-handover.sh handover | pin" >&2; exit 64 ;;
esac
[ $# -eq 1 ] || { echo "usage: materializing-handover.sh handover | pin" >&2; exit 64; }
own_step "$mode" "$mode"

task_file=${SPOOLWAY_TASK_FILE:-}
if [ -n "$task_file" ] && [ -f "$task_file" ] && task_unchanged "$root" "$task_file"; then
  echo "$mode: the document step changed nothing; no pull request is opened for this run"
  exit 0
fi

if [ "$mode" = handover ]; then
  exec "$here/handover.sh"
fi
exec "$here/pins.sh" pin all
