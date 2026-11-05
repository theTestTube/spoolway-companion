#!/usr/bin/env bash
# Offline test for the `dod` step: the shipped pipelines, the developing-dod and
# developing-unblock prompts, and claude-plugin/spoolway/types/scripts/spoolway/dod.sh driven against a
# fake `gh` that keeps an issue in files. Nothing reaches GitHub or the network.
# Usage: tests/spoolway-dod.test.sh (needs bash, jq and awk)

set -u
unset "${!SPOOLWAY_@}"

repo="$(cd "$(dirname "$0")/.." && pwd)"
types="$repo/claude-plugin/spoolway/types"
dod="$types/scripts/spoolway/dod.sh"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

failures=0
pass() { printf 'ok   %s\n' "$1"; }
fail() { printf 'FAIL %s\n' "$1"; [ -n "${2:-}" ] && printf '     %s\n' "$2"; failures=$((failures + 1)); }
check() { if eval "$2"; then pass "$1"; else fail "$1" "${3:-}"; fi; }

# --- The pipelines ----------------------------------------------------------------------------

for p in developing developing-sonnet-review; do
  f="$types/setup/pipelines/$p.yml"
  step=$(awk '/^  - id: dod$/ { on = 1; print; next } on && /^  - id: / { exit } on && !/^[ \t]*#/ { print }' "$f")
  ids=$(grep -E '^  - id: ' "$f" | sed 's/^  - id: //' | tr '\n' ' ')
  check "$p: dod sits between ci and signals" 'case "$ids" in *"pin ci dod signals report"*) true ;; *) false ;; esac' "$ids"
  check "$p: dod is a Sonnet agent step at medium effort on developing-dod" \
    'grep -q "agent: claude" <<<"$step" && grep -q "prompt: developing-dod" <<<"$step" && grep -q "model: claude-sonnet-5-5" <<<"$step" && grep -q "effort: medium" <<<"$step"' "$step"
  check "$p: dod holds no concurrency slot" 'grep -qx "    slot: false" <<<"$step"'
  check "$p: dod has no on_fail, and ci none either" '! grep -q on_fail <<<"$step" && ! awk "/^  - id: ci\$/ {on=1;next} on && /^  - id: / {exit} on && !/^[ \t]*#/" "$f" | grep -q on_fail'
  check "$p: ci passes on to dod, dod to signals" \
    'awk "/^  - id: ci\$/ {on=1;next} on && /^  - id: / {exit} on" "$f" | grep -qx "    on_pass: dod" && grep -qx "    on_pass: signals" <<<"$step"'
done
check "developing is at 1.9 and the Sonnet variant at 1.2" \
  'grep -qx "version: \"1.9\"" "$types/setup/pipelines/developing.yml" && grep -qx "version: \"1.2\"" "$types/setup/pipelines/developing-sonnet-review.yml"'

# --- The prompts ------------------------------------------------------------------------------

dp="$types/setup/prompts/developing-dod/PROMPT.md"
check "the dod prompt waits for the person and never ends its turn on a question" 'grep -q "Never end your turn or report while a question is unanswered" "$dp"'
check "the dod prompt asks one batch question and reads the handoff notes" 'grep -q "needs a person:" "$dp" && grep -q "for a person:" "$dp" && grep -q "once" "$dp"'
up="$types/setup/prompts/developing-unblock/PROMPT.md"
check "the unblock prompt sends a dod code fix back through ci, never past dod" \
  'grep -q "stopped on \`ci\`, or on \`dod\` after a code fix, once it is pushed: name \`ci\` as the next step" "$up" && grep -q "\-\-stage ci" "$up"'
check "the unblock prompt pushes a ci or dod code fix, never force-pushes, before sending it back through ci" \
  'grep -q "After a code fix to a \`ci\` or \`dod\` block, push the branch as it is" "$up" && grep -q "never$" "$up" && grep -q "a force-push, never re-run \`handover\`" "$up" && grep -q "then commit, push the branch and send the task back through \`ci\`" "$up"'
# Offline evidence for the live criterion that nobody answering leaves the task in `dod`: in both shipped
# pipelines `dod` holds no slot, has no on_fail and no timeout, and the unblocker (prompt developing-unblock)
# belongs to the `blocked` step alone, which no step routes to by on_pass or on_fail.
for p in developing developing-sonnet-review; do
  f="$types/setup/pipelines/$p.yml"
  step=$(awk '/^  - id: dod$/ { on = 1; print; next } on && /^  - id: / { exit } on && !/^[ \t]*#/ { print }' "$f")
  check "$p: dod has slot: false, no on_fail and no timeout" \
    'grep -qx "    slot: false" <<<"$step" && ! grep -qE "^    (on_fail|timeout):" <<<"$step"' "$step"
  check "$p: the unblocker prompt is used by the blocked step alone, and nothing routes to blocked" \
    '[ "$(grep -c "prompt: developing-unblock" "$f")" = 1 ] && awk "/^  - id: blocked\$/ {on=1;next} on && /^  - id: / {exit} on" "$f" | grep -q "prompt: developing-unblock" && ! grep -qE "^    on_(pass|fail): blocked" "$f"'
done
check "the unblock prompt parks a dod block that needs the person and ticks nothing" \
  'grep -q "the \`dod\` step stopped" "$up" && grep -q "Tick nothing, answer nothing for the person" "$up" && grep -q "never send the task past \`dod\`" "$up"'

# --- dod.sh over a fake gh --------------------------------------------------------------------

mkdir -p "$work/bin" "$work/s"
export ISSUE="$work/s/body" COMMENTS="$work/s/comments" CALLS="$work/s/calls"
cat > "$work/bin/gh" <<'FAKE'
#!/bin/sh
# Answers like the real gh: `--json body` prints {"body": ...}; `--json body --jq .body` prints the
# body and then a newline (jq -r), which is what the real command adds.
echo "gh $*" >> "$CALLS"
case "$1 $2" in
  "issue view")
    json=0; jq=0; for a in "$@"; do [ "$a" = --json ] && json=1; [ "$a" = --jq ] && jq=1; done
    if [ $jq -eq 1 ]; then jq -Rs '{body: .}' "$ISSUE" | jq -r .body
    elif [ $json -eq 1 ]; then jq -Rs '{body: .}' "$ISSUE"
    else cat "$ISSUE"; fi ;;
  "issue edit") while [ $# -gt 0 ]; do [ "$1" = --body-file ] && { cp "$2" "$ISSUE"; [ -n "${TAMPER:-}" ] && echo "tampered" >> "$ISSUE"; }; shift; done ;;
  "issue comment") while [ $# -gt 0 ]; do [ "$1" = --body-file ] && cat "$2" >> "$COMMENTS" && echo "<<end>>" >> "$COMMENTS"; shift; done ;;
esac
exit 0
FAKE
chmod +x "$work/bin/gh"
export PATH="$work/bin:$PATH"

reset() {
  printf '## Why\n\nSome text with `- [ ]` inside code and a link.\n\n## Acceptance criteria\n\n- [ ] tests pass\n- [ ] gates pass\n- [ ] it looks right on a device\n\n## Notes\n\n- [x] already done\n' > "$ISSUE"
  cp "$ISSUE" "$work/s/original"; rm -f "$COMMENTS" "$CALLS"
}
reset
plan="$work/plan.json"; res="$work/res.json"
cat > "$plan" <<'J'
[{"n":1,"kind":"harness","text":"tests pass","command":"pnpm test","output":"Tests 12 passed"},
 {"n":2,"kind":"harness","text":"gates pass","command":"scripts/gates/run.sh","output":"all green"},
 {"n":3,"kind":"person","text":"it looks right on a device"}]
J

out=$(bash "$dod" criteria x); 
check "criteria lists the three open boxes and the ticked one, numbered" '[ "$(printf "%s\n" "$out" | cut -f1,2 | tr "\t" " " | paste -sd";")" = "1 [ ];2 [ ];3 [ ];4 [x]" ]' "$out"

q=$(bash "$dod" questions "$plan")
check "three criteria, two provable: one batch question and one individual question" \
  '[ "$(jq length <<<"$q")" -eq 2 ] && [ "$(jq "[.[]|select(.kind==\"batch\")]|length" <<<"$q")" -eq 1 ] && [ "$(jq "[.[]|select(.kind==\"individual\")]|length" <<<"$q")" -eq 1 ]' "$q"
check "the batch question shows each proven criterion with its command and deciding output" \
  'jq -e ".[0].question | contains(\"pnpm test\") and contains(\"Tests 12 passed\") and contains(\"scripts/gates/run.sh\") and contains(\"all green\")" <<<"$q" >/dev/null'
check "the batch offers accept all and one by one" 'jq -e ".[0].options == [\"Accept all\",\"Review them one by one\"]" <<<"$q" >/dev/null'
q2=$(jq '. + [{"kind":"note","text":"needs a person: run it on a device"}]' "$plan" > "$work/plan2.json"; bash "$dod" questions "$work/plan2.json")
check "a handoff note becomes a question of its own" '[ "$(jq length <<<"$q2")" -eq 3 ]'

cat > "$res" <<'J'
[{"n":1,"text":"tests pass","verdict":"met","by":"person","command":"pnpm test","output":"Tests 12 passed","answer":"Accept all"},
 {"n":2,"text":"gates pass","verdict":"met","by":"person","command":"scripts/gates/run.sh","output":"all green","answer":"Accept all"},
 {"n":3,"text":"it looks right on a device","verdict":"not-met","by":"person","answer":"Not met"}]
J
bash "$dod" apply x "$res" t1 r1 > "$work/out" 2> "$work/err"; rc=$?
check "a rejected criterion leaves the step failing, naming it" '[ $rc -eq 1 ] && grep -q "3. it looks right on a device" "$work/err"' "rc=$rc $(cat "$work/err")"
changed=$(diff "$work/s/original" "$ISSUE" | grep -c '^>' )
check "exactly the two accepted boxes are ticked" '[ "$changed" -eq 2 ] && grep -qx -- "- \[x\] tests pass" "$ISSUE" && grep -qx -- "- \[x\] gates pass" "$ISSUE" && grep -qx -- "- \[ \] it looks right on a device" "$ISSUE"' "$(diff "$work/s/original" "$ISSUE")"
check "the body differs from the original in those two lines and nothing else" \
  '[ "$(diff "$work/s/original" "$ISSUE" | grep -c "^<")" -eq 2 ] && diff <(sed -e "s/- \[x\] tests pass/- [ ] tests pass/;s/- \[x\] gates pass/- [ ] gates pass/" "$ISSUE") "$work/s/original" >/dev/null'
check "one new evidence comment, titled with the task and run, command and output verbatim" \
  '[ "$(grep -c "^<<end>>" "$COMMENTS")" -eq 1 ] && grep -qx "## Definition of done — t1 · r1" "$COMMENTS" && grep -q "pnpm test" "$COMMENTS" && grep -q "Tests 12 passed" "$COMMENTS" && grep -q "verified by: person" "$COMMENTS"' "$(cat "$COMMENTS")"
check "no existing comment is edited and nothing but view, edit and comment is called" \
  '! grep -qE "gh api|--edit-last|comment --edit" "$CALLS" && ! grep -vE "^gh issue (view|edit|comment) " "$CALLS" | grep -q .' "$(cat "$CALLS")"

# All accepted: the step passes.
reset
jq '.[2].verdict = "met" | .[2].answer = "Met"' "$res" > "$work/res2.json"
bash "$dod" apply x "$work/res2.json" t1 r1 > "$work/out" 2> "$work/err"; rc=$?
check "every criterion accepted: all ticked and the step passes" '[ $rc -eq 0 ] && ! grep -qE "^- \[ \]" "$ISSUE" && grep -q "every criterion is ticked" "$work/out"' "rc=$rc $(cat "$work/err")"

# Run twice on one issue: the body is edited once, one comment per run.
reset
bash "$dod" apply x "$work/res2.json" t1 r1 > /dev/null 2>&1
bash "$dod" apply x "$work/res2.json" t1 r1 > /dev/null 2>&1; rc=$?
check "apply run twice edits the body once and posts one comment per run" \
  '[ $rc -eq 0 ] && [ "$(grep -c "^gh issue edit" "$CALLS")" -eq 1 ] && [ "$(grep -c "^<<end>>" "$COMMENTS")" -eq 2 ]' "$(cat "$CALLS")"

# A raw read of the body differs from the one before only in the accepted boxes (trailing newline included).
reset
raw() { gh issue view x --json body | jq -j .body; }
raw > "$work/s/raw-before"
bash "$dod" apply x "$res" t1 r1 > /dev/null 2>&1
raw > "$work/s/raw-after"
check "a raw read after apply differs from the one before in the two accepted boxes alone" \
  '[ "$(diff "$work/s/raw-before" "$work/s/raw-after" | grep -c "^<")" -eq 2 ] && cmp -s <(sed -e "s/^- \[x\] tests pass/- [ ] tests pass/;s/^- \[x\] gates pass/- [ ] gates pass/" "$work/s/raw-after") "$work/s/raw-before"'

# A body GitHub stores without a final newline (web editor): apply adds no byte, and with nothing to tick it does not edit.
reset
printf '## AC\n\n- [ ] tests pass\n- [ ] gates pass' > "$ISSUE"; rm -f "$CALLS"
bash "$dod" apply x "$work/res2.json" t1 r1 > /dev/null 2>&1
check "no trailing newline, boxes to tick: the body gains no byte" \
  '[ "$(cat "$ISSUE")" = "$(printf "## AC\n\n- [x] tests pass\n- [x] gates pass")" ] && [ -n "$(tail -c1 "$ISSUE")" ]' "$(od -c "$ISSUE" | tail -3)"
reset
printf -- '- [x] a' > "$ISSUE"; rm -f "$CALLS"
echo '[{"n":1,"verdict":"met","by":"p"}]' > "$work/r1.json"
bash "$dod" apply x "$work/r1.json" t r > /dev/null 2>&1
check "no trailing newline, nothing to tick: no edit and the body is unchanged" \
  '! grep -q "^gh issue edit" "$CALLS" && [ "$(wc -c < "$ISSUE")" -eq 7 ]' "$(od -c "$ISSUE")"

# An edit that changes more than the boxes is refused.
reset
TAMPER=1 bash "$dod" apply x "$res" t1 r1 > "$work/out" 2> "$work/err"; rc=$?
check "a body that reads back differently fails the step and posts no comment" '[ $rc -eq 1 ] && grep -q "read back differs" "$work/err" && [ ! -f "$COMMENTS" ]' "rc=$rc $(cat "$work/err")"

[ "$failures" -eq 0 ] && { echo "all dod checks passed"; exit 0; }
echo "$failures dod check(s) failed"; exit 1
