#!/usr/bin/env bash
# The no-wiki stub of the page drift gate. A consumer that keeps no pages of prose citing its code
# still runs the page steps when it names a PAGES_DIR; one that has not written a gate of its own
# names this script as PAGES_GATE, and the steps then ask the record contract about an empty page
# set and pass.
#
# It reads the same environment as any PAGES_GATE (STALE_PAGES_RECORDS, STALE_PAGES_SCOPE,
# STALE_PAGES_BASE) and never reads the tree, never writes and never fails. In records mode it
# prints no page record and the closing line; without it, the prose closing line alone.
set -u

echo "=== GREEN — 0 red, no pages"
