#!/usr/bin/env bash
# Replays claude-plugin/skills/spoolway-repair/repair.sh offline against a fixture: the incident
# task document of 2026-10-07 (`smoke-implement-spec`) cut back to the moment it stood on
# `blocked`, a synthetic scratch space and synthetic command logs. `spoolway` and `gh` are stubs on
# PATH; every call is logged, so the test can show what the script never touched. The roads
# (choose, advance, retreat, record) are replayed the same way: the stub answers `--help` from the
# help text of spoolway 0.19.0 (captured from the binary's own `--help`, not written by hand) and
# refuses a real resume or unqueue, and the unqueue is simulated by hand, as the release notes and
# the issue's probe describe it: worktree and local branch deleted, with no commit first.
# The assertions are on conclusions and on files, never on wording.
# Usage: tests/spoolway-repair.test.sh   (needs bash, jq, git)

set -u

repo="$(cd "$(dirname "$0")/.." && pwd)"
script="$repo/claude-plugin/skills/spoolway-repair/repair.sh"
fixture="$repo/tests/fixtures/spoolway-repair"
work="$(mktemp -d)"
trap 'chmod -R u+rwX "$work" 2>/dev/null; rm -rf "$work"; kill "${dispatcher_pid:-0}" 2>/dev/null' EXIT

failures=0
pass() { printf 'ok   %s\n' "$1"; }
fail() { printf 'FAIL %s\n' "$1"; [ -n "${2:-}" ] && printf '     %s\n' "$2"; failures=$((failures + 1)); }
expect() { # expect <name> <jq filter> — true on $out
  jq -e "$2" <<<"$out" >/dev/null 2>&1 && pass "$1" || fail "$1" "filter: $2"
}

TASK=smoke-implement-spec

# --- Fixture project: a main checkout with the task's branch, a remote that holds only its first
# commit, and a worktree with one untracked file.
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.com GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.com
checkout="$work/checkout"
git init -q -b develop "$checkout"
printf '.scratch/\n' >"$checkout/.gitignore"
git -C "$checkout" add .gitignore && git -C "$checkout" commit -q -m "chore: base"
base_commit=$(git -C "$checkout" rev-parse HEAD)
git init -q --bare "$work/remote.git"
git -C "$checkout" remote add origin "$work/remote.git"
git -C "$checkout" worktree add -q -b "task/$TASK" "$work/wt" "$base_commit"
printf 'one\n' >"$work/wt/one.txt"
git -C "$work/wt" add one.txt && git -C "$work/wt" commit -q -m "feat: one"
git -C "$work/wt" push -q origin "task/$TASK"
printf 'two\n' >"$work/wt/two.txt"
git -C "$work/wt" add two.txt && git -C "$work/wt" commit -q -m "feat: two"
printf 'loose\n' >"$work/wt/untracked.txt"

# --- Fixture spoolway home, task documents and stubs.
cp -R "$fixture/state" "$work/home"
sed -e "s#@STATE@#$work/home#g" -e "s#@WORKTREE@#$work/wt#g" -e "s#@BASE_COMMIT@#$base_commit#g" \
  "$fixture/blocked-task.md" >"$work/task-$TASK.md"
sed -e "s#^id: $TASK#id: empty-task#" -e "s#^branch: .*#branch: task/empty-task#" "$work/task-$TASK.md" >"$work/task-empty-task.md"
printf '{"dispatcher_pid": null, "tasks": []}' >"$work/queue-list.json"
printf 'false' >"$work/unattended"
cp "$fixture/resume-help.txt" "$fixture/unqueue-help.txt" "$fixture/pause-help.txt" "$work/"

mkdir -p "$work/bin"
cat >"$work/bin/spoolway" <<EOF
#!/usr/bin/env bash
# Stub: answers the read-only calls the script may make, and logs every call.
echo "\$*" >>"$work/spoolway.calls"
[ "\${1:-}" = -C ] && shift 2
[ "\${1:-}" = --version ] && { echo "spoolway 0.19.0"; exit 0; }
case "\$1 \$2" in
  "task contract") printf '{"output": {"dir": "$work/home/pending"}}' ;;
  "queue show") [ -f "$work/task-\$3.md" ] && cat "$work/task-\$3.md" || { echo "no such task" >&2; exit 1; } ;;
  "pipeline show") cat "$fixture/pipeline-show.txt" ;;
  "queue list") cat "$work/queue-list.json" ;;
  "config get") cat "$work/unattended" ;;
  "resume --help") cat "$work/resume-help.txt" ;;
  "queue pause") [ "\${3:-}" = --help ] && cat "$work/pause-help.txt" || { echo "stub: refused: \$*" >&2; exit 64; } ;;
  "queue unqueue") [ "\${3:-}" = --help ] && cat "$work/unqueue-help.txt" || { echo "stub: refused: \$*" >&2; exit 64; } ;;
  *) echo "stub: unexpected call: \$*" >&2; exit 64 ;;
esac
EOF
cat >"$work/bin/gh" <<EOF
#!/usr/bin/env bash
echo "\$*" >>"$work/gh.calls"
exit 1
EOF
chmod +x "$work/bin/spoolway" "$work/bin/gh"

run() { # run <command> <task> [args...]; sets out, status, err
  err="$work/err"
  out="$(PATH="$work/bin:$PATH" REPAIR_REPO="$checkout" bash "$script" "$@" 2>"$err")"
  status=$?
}
# Every spoolway call that could change something. Reading a command's help changes nothing.
mutating_calls() { grep -E 'resume|unqueue|queue add|queue pause|task edit|report|dispatch|override|set ' "$work/spoolway.calls" | grep -v -- '--help$' || true; }
snapshot() { find "$work/home" "$checkout" "$work/wt" -path '*/.git' -prune -o -type f -printf '%p %s %T@\n' | LC_ALL=C sort; }

# =============================== diagnose ==================================
before="$(snapshot)"; : >"$work/spoolway.calls"
run diagnose "$TASK"
[ "$status" = 0 ] && pass "diagnose: exits 0" || fail "diagnose: exits 0" "exit=$status $(cat "$err")"

expect "diagnose: the cause is a spent loop on implement-spec" \
  '.cause.kind == "spent-loop" and .cause.step == "implement-spec" and .cause.loop == 3 and .cause.arrivals == 3 and .cause.from == "implement"'
expect "diagnose: the cause is one sentence with its evidence" \
  '(.cause.sentence | type == "string" and length > 0 and (contains("\n") | not)) and (.cause.evidence | contains("may not send this to"))'
expect "diagnose: stage and the step it stopped from" '.stage == "blocked" and .blocked_from == "implement"'
expect "diagnose: arrivals against each loop (both implementers over their loop, others not)" \
  '([.loops[] | select(.spent) | .step] | sort) == ["implement", "implement-spec"] and ([.loops[] | select(.step == "implement-spec")][0].arrivals == 3)'
expect "diagnose: the last refusal line is carried" '.last_refusal | contains("`implement-spec` has `loop: 3`")'
expect "diagnose: a plain resume lands on the pass-through implement step and bounces" \
  '.plain_resume.step == "implement" and .plain_resume.passes_at_once == ["implement"] and .plain_resume.outcome == "bounces" and .plain_resume.refused_at == "implement-spec"'
expect "diagnose: exactly one criterion is unpassable, the first" \
  '([.criteria[] | select(.passable | not) | .n] == [1]) and (.criteria | length == 3)'
expect "diagnose: handoff notes addressed to a person are listed, with what they ask" \
  '(.handoff.to_person | length) > 0 and (.handoff.to_person | all(.n and .step and .text)) and ([.handoff.to_person[] | select(.asks | length > 0)] | length) > 0'
expect "diagnose: branch commits since base" '.git.commits_since_base | length == 2'
expect "diagnose: working tree state" '.git.worktree.present and (.git.worktree.changes | any(contains("untracked.txt")))'
expect "diagnose: whether the remote has the commits" '.git.remote.branch == "present" and .git.remote.commits_not_on_remote == 1'
expect "diagnose: scratch files by name and size" \
  '[.scratch[] | "\(.name):\(.size)"] == ["empty.txt:0","nested/table.md:52","one-byte.txt:1","t229-notes.md:121"]'
expect "diagnose: command-step logs of this task only" \
  '[.commands[].name] == ["smoke-implement-spec · checks.log","smoke-implement-spec · extra-worktree.log","smoke-implement-spec · handover.env"]'
expect "diagnose: no dispatcher running" '.dispatcher.running == false'
expect "diagnose: a task bound to a spec carries the keep-open marker" \
  '.spec.bound and .spec.close_on_merge == "false" and .spec.keep_open_marker == "present"'

after="$(snapshot)"
[ "$before" = "$after" ] && pass "diagnose: writes nothing (fixture tree, checkout and worktree unchanged)" || fail "diagnose: writes nothing" "$(diff <(echo "$before") <(echo "$after"))"
[ -z "$(git -C "$checkout" status --short)" ] && pass "diagnose: leaves the main checkout clean" || fail "diagnose: leaves the main checkout clean"
mutating=$(mutating_calls)
[ -z "$mutating" ] && pass "diagnose: makes no mutating spoolway call" || fail "diagnose: makes no mutating spoolway call" "$mutating"
[ ! -e "$work/gh.calls" ] && pass "diagnose: makes no gh call" || fail "diagnose: makes no gh call" "$(cat "$work/gh.calls")"

# Dispatcher: running and unattended by flag, attended by flag, then by config.
bash -c 'exec 0<&- 1>/dev/null 2>&1; sleep 60; :' spoolway dispatch --unattended & dispatcher_pid=$!
printf '{"dispatcher_pid": %s, "tasks": []}' "$dispatcher_pid" >"$work/queue-list.json"
run diagnose "$TASK"; expect "dispatcher: running and unattended by its flag" '.dispatcher.running and .dispatcher.mode == "unattended" and .dispatcher.source == "flag"'
kill "$dispatcher_pid"; wait "$dispatcher_pid" 2>/dev/null
bash -c 'exec 0<&- 1>/dev/null 2>&1; sleep 60; :' spoolway dispatch --attended & dispatcher_pid=$!
printf '{"dispatcher_pid": %s, "tasks": []}' "$dispatcher_pid" >"$work/queue-list.json"
run diagnose "$TASK"; expect "dispatcher: running and attended by its flag" '.dispatcher.mode == "attended" and .dispatcher.source == "flag"'
kill "$dispatcher_pid"; wait "$dispatcher_pid" 2>/dev/null
bash -c 'exec 0<&- 1>/dev/null 2>&1; sleep 60; :' spoolway dispatch & dispatcher_pid=$!
printf '{"dispatcher_pid": %s, "tasks": []}' "$dispatcher_pid" >"$work/queue-list.json"
printf 'true' >"$work/unattended"
run diagnose "$TASK"; expect "dispatcher: no flag, the config decides" '.dispatcher.mode == "unattended" and .dispatcher.source == "config"'
kill "$dispatcher_pid"; wait "$dispatcher_pid" 2>/dev/null
printf '{"dispatcher_pid": null, "tasks": []}' >"$work/queue-list.json"; printf 'false' >"$work/unattended"

# A task spoolway does not know fails loudly.
run diagnose nope; [ "$status" != 0 ] && pass "diagnose: an unknown task exits non-zero" || fail "diagnose: an unknown task exits non-zero"

# A task that is not parked on blocked is not doomed, whatever its log says.
sed -e 's/^stage: blocked/stage: done/' -e '/^blocked_from:/d' "$work/task-$TASK.md" >"$work/task-finished.md"
out="$(PATH="$work/bin:$PATH" REPAIR_REPO="$checkout" bash "$script" diagnose finished 2>/dev/null)"
expect "diagnose: a task past blocked is reported as not blocked" '.cause.kind == "not-blocked" and .plain_resume == null'

# A dispatcher pid that no longer exists is reported as stale, not as a running dispatcher.
printf '{"dispatcher_pid": 4194999, "tasks": []}' >"$work/queue-list.json"
run diagnose "$TASK"; expect "dispatcher: a pid that is gone is not a running dispatcher" '.dispatcher.running == false and .dispatcher.stale_pid == true'
printf '{"dispatcher_pid": null, "tasks": []}' >"$work/queue-list.json"

# An id that is not a task id (glob characters) is refused before anything is read.
run diagnose 'a*b'; [ "$status" = 2 ] && pass "diagnose: an id with glob characters is refused" || fail "diagnose: an id with glob characters is refused" "exit=$status"

# A handoff note that wraps onto a second line is one note.
{ cat "$work/task-$TASK.md"; printf -- '- `review` — For a person: please\n  post the wrapped table on #229 before the task ends.\n'; } >"$work/task-wrapped.md"
sed -i 's/^id: .*/id: wrapped/' "$work/task-wrapped.md"
out="$(PATH="$work/bin:$PATH" REPAIR_REPO="$checkout" bash "$script" diagnose wrapped 2>/dev/null)"
expect "diagnose: a wrapped handoff note is read whole" \
  '[.handoff.to_person[] | select(.text | contains("wrapped table on #229"))] | length == 1 and (.[0].asks == ["post"])'

# =============================== the skill file ============================
skill="$repo/claude-plugin/skills/spoolway-repair/SKILL.md"
front="$(awk 'NR == 1 && $0 == "---" {on = 1; next} on && $0 == "---" {exit} on' "$skill")"
grep -qx 'disable-model-invocation: true' <<<"$front" && pass "skill: only a person can start it" || fail "skill: only a person can start it"
! grep -q '^description:' <<<"$front" && pass "skill: carries no description for the model" || fail "skill: carries no description for the model"
[ "$(grep -c 'smoke-implement-spec' "$skill")" = 1 ] && pass "skill: the worked example is behind one pointer, not inlined" || fail "skill: the worked example is behind one pointer, not inlined"
[ -f "$repo/claude-plugin/skills/spoolway-repair/smoke-implement-spec.md" ] && pass "skill: the pointer's target exists" || fail "skill: the pointer's target exists"
grep -q 'A worked example.*\[smoke-implement-spec.md\](smoke-implement-spec.md)' "$skill" && pass "skill: the pointer says when to read the example" || fail "skill: the pointer says when to read the example"

# =============================== salvage ===================================
dest="$checkout/.scratch/spoolway/$TASK"
: >"$work/spoolway.calls"
run salvage "$TASK"
[ "$status" = 0 ] && pass "salvage: exits 0" || fail "salvage: exits 0" "exit=$status $(cat "$err")"
expect "salvage: reports success under the main checkout's scratch directory" ".ok and .destination == \"$dest\""

# Every fixture file, compared by name and size, from the fixture itself.
expected="$( (cd "$fixture/state/scratch/$TASK" && find . -type f -printf 'scratch/%P %s\n'; cd "$fixture/state/commands" && find . -maxdepth 1 -type f -name "$TASK · *" -printf 'commands/%P %s\n') | LC_ALL=C sort)"
listed="$(jq -r --arg dest "$dest" '.files[] | . as $f | "\($f.kind)/\($f.destination | ltrimstr($dest + "/" + $f.kind + "/")) \($f.size)"' <<<"$out" | LC_ALL=C sort)"
landed="$( (cd "$dest" && find scratch commands -type f -printf '%p %s\n') | LC_ALL=C sort)"
[ "$expected" = "$listed" ] && pass "salvage: the list holds every fixture file with its size" || fail "salvage: the list holds every fixture file" "$(diff <(echo "$expected") <(echo "$listed"))"
[ "$expected" = "$landed" ] && pass "salvage: the folder holds every fixture file, by name and size" || fail "salvage: the folder holds every fixture file" "$(diff <(echo "$expected") <(echo "$landed"))"
expect "salvage: each listed copy matches its source" '.files | length > 0 and all(.match)'
[ ! -e "$dest/scratch/keep-out.md" ] && ! find "$dest" -name 'other-task*' | grep -q . && pass "salvage: another task's files are left alone" || fail "salvage: another task's files are left alone"
[ -z "$(git -C "$checkout" status --short)" ] && pass "salvage: the destination is git-ignored" || fail "salvage: the destination is git-ignored"

# Drafts: one per note addressed to a person that asks to post or open something.
# Read off the fixture by hand: notes 8, 10, 13, 26, 27, 34 and 46 ask a person to open or post
# something. A finding that merely says an issue is OPEN, or leaves one open, does not.
[ "$(jq -c '[.drafts[].note]' <<<"$out")" = "[8,10,13,26,27,34,46]" ] && pass "salvage: one draft per post-or-open note, and no other" || fail "salvage: one draft per post-or-open note, and no other" "$(jq -c '[.drafts[].note]' <<<"$out")"
on_disk=$(find "$dest/drafts" -type f | wc -l)
[ "$on_disk" = 7 ] && pass "salvage: the drafts are on disk" || fail "salvage: the drafts are on disk" "$on_disk"
draft8="$dest/drafts/08-implement-spec.md"
head -1 "$draft8" | grep -q '^DRAFT' && pass "salvage: a draft says it is a draft" || fail "salvage: a draft says it is a draft"
grep -qF -- "- $dest/scratch/t229-notes.md" "$draft8" \
  && pass "salvage: a draft points at the salvaged copy of the file its note names" || fail "salvage: a draft points at the salvaged copy of the file its note names"
[ ! -e "$work/gh.calls" ] && pass "salvage: posts nothing (no gh call)" || fail "salvage: posts nothing (no gh call)" "$(cat "$work/gh.calls")"
mutating=$(mutating_calls)
[ -z "$mutating" ] && pass "salvage: makes no mutating spoolway call" || fail "salvage: makes no mutating spoolway call" "$mutating"

# Idempotent: a second run lists the same copies.
first="$(jq -S -c '[.files[] | {kind, destination, size}]' <<<"$out")"
run salvage "$TASK"
[ "$status" = 0 ] && [ "$first" = "$(jq -S -c '[.files[] | {kind, destination, size}]' <<<"$out")" ] && pass "salvage: a second run changes nothing" || fail "salvage: a second run changes nothing"

# An empty scratch space passes.
run salvage empty-task
[ "$status" = 0 ] && pass "salvage: an empty scratch space passes" || fail "salvage: an empty scratch space passes" "exit=$status $(cat "$err")"
expect "salvage: an empty scratch space lists nothing" '.ok and .empty and (.files | length == 0)'

# A symlink in the scratch space is copied as the file it points at.
mkdir -p "$work/home/scratch/empty-task"
printf 'target body\n' >"$work/target.md"
ln -s "$work/target.md" "$work/home/scratch/empty-task/link.md"
run salvage empty-task
expect "salvage: a symlink is copied as its target, and listed" '.ok and (.files | length == 1) and (.files[0].size == 12) and (.files[0].match)'
rm -rf "$work/home/scratch/empty-task"

# A rerun after the source changed keeps the earlier copy as a numbered backup.
printf 'changed after the first salvage\n' >"$work/home/scratch/$TASK/one-byte.txt"
run salvage "$TASK"
[ "$status" = 0 ] && [ "$(cat "$dest/scratch/one-byte.txt")" = "changed after the first salvage" ] && ls "$dest/scratch" | grep -q '^one-byte.txt.~1~$' \
  && pass "salvage: a changed source replaces the copy and keeps the earlier one" || fail "salvage: a changed source replaces the copy and keeps the earlier one"
printf 'x' >"$work/home/scratch/$TASK/one-byte.txt"

# A destination that is not git-ignored stops before any write.
git init -q -b develop "$work/checkout-noignore"
out="$(PATH="$work/bin:$PATH" REPAIR_REPO="$work/checkout-noignore" bash "$script" salvage "$TASK" 2>"$err")"; status=$?
[ "$status" != 0 ] && [ ! -e "$work/checkout-noignore/.scratch" ] && pass "salvage: stops when the destination is not git-ignored, writing nothing" || fail "salvage: stops when the destination is not git-ignored" "exit=$status"

# A copy failure stops the step and names the file (unreadable source; skipped as root).
if [ "$(id -u)" != 0 ]; then
  rm -rf "$dest"
  chmod 000 "$work/home/scratch/$TASK/nested/table.md"
  run salvage "$TASK"
  chmod 644 "$work/home/scratch/$TASK/nested/table.md"
  [ "$status" != 0 ] && pass "salvage: a copy failure exits non-zero" || fail "salvage: a copy failure exits non-zero"
  expect "salvage: a copy failure is reported against the file, and nothing is drafted" \
    '(.ok | not) and (.failed | length == 1) and (.failed[0] | endswith("nested/table.md")) and (.drafts | length == 0)'
else
  printf 'skip salvage: a copy failure (running as root, chmod 000 cannot stop a copy)\n'
fi


# =============================== choose ====================================
run salvage "$TASK"   # the roads start from a complete salvage
before="$(snapshot)"; : >"$work/spoolway.calls"
run choose "$TASK"
[ "$status" = 0 ] && pass "choose: exits 0" || fail "choose: exits 0" "exit=$status $(cat "$err")"
expect "choose: the recommended road is advance, with its reason" \
  '.recommendation.road == "advance" and (.recommendation.reason | type == "string" and length > 0) and .recommendation.otherwise == "retreat"'
expect "choose: on condition that the unpassable criterion is amended" \
  '[.recommendation.conditions[].amend_criterion] == [1] and .criteria_unpassable == [1]'
expect "choose: the resume step is checks, derived from the pipeline" '.resume_step == "checks"'
expect "choose: seven findings are open, six repairable in the worktree and one for a person" \
  '(.findings.open | length) == 7 and .findings.repairable == [1,2,3,4,5,6] and .findings.for_person == [7]'
expect "choose: checks passed and review did not, since the implementer last worked" \
  '[.judgments[] | "\(.step):\(.status)"] == ["checks:passed","review:failed"]'
expect "choose: the ruling is the person's" '.ruled_by == "the person"'
[ "$before" = "$(snapshot)" ] && pass "choose: writes nothing" || fail "choose: writes nothing"
[ -z "$(mutating_calls)" ] && pass "choose: makes no mutating spoolway call" || fail "choose: makes no mutating spoolway call" "$(mutating_calls)"

# No worktree to repair in: retreat.
sed -e 's/^id: .*/id: noworktree/' -e "s#^worktree_path: .*#worktree_path: $work/gone#" "$work/task-$TASK.md" >"$work/task-noworktree.md"
run choose noworktree; expect "choose: a task whose worktree is gone is recommended to retreat" '.recommendation.road == "retreat" and (.recommendation.conditions | length == 0)'
# A finding for a person that rests on no criterion cannot be repaired or amended away: retreat.
{ sed 's/^id: .*/id: stuck/' "$work/task-$TASK.md"; printf -- '- `review` — Finding 8 (scope), for a person and not the implementer — it needs a licence nobody holds.\n'; } >"$work/task-stuck.md"
run choose stuck; expect "choose: a finding only a person can act on, with no criterion to amend, is recommended to retreat" '.recommendation.road == "retreat" and .findings.for_person == [7,8]'
run choose finished; expect "choose: a task that is not blocked gets no road" '.recommendation.road == null'

# =============================== advance ===================================
: >"$work/spoolway.calls"
run advance "$TASK"
[ "$status" = 0 ] && pass "advance: exits 0" || fail "advance: exits 0" "exit=$status $(cat "$err")"
expect "advance: the recommended resume names its step, checks" \
  '.kind == "recommended" and .step == "checks" and .command[0:5] == ["spoolway","resume","smoke-implement-spec","--stage","checks"]'
expect "advance: the command carries its status-log message, shown beside it" \
  '(.message | length > 0) and .command[5:] == ["--message", .message] and (.shown | contains("--stage"))'
expect "advance: it says beforehand that a judgment failing again parks the task and starts no lane" \
  '(.warnings | index("a-judgment-failing-again-parks-the-task") != null) and ([.on_failure[].step] == ["checks","review"]) and (.on_failure | all(.parks and (.starts_a_lane | not)))'
expect "advance: the extra implementer lap is counted, and not proposed unless named" \
  '.extra_lap == {step: "implement-spec", loop: 3, arrivals: 3, arrival_would_be: 4, named: false}'
grep -q 'resume --help$' "$work/spoolway.calls" && pass "advance: the resume flags are read from the binary's help" || fail "advance: the resume flags are read from the binary's help"
[ -z "$(mutating_calls)" ] && pass "advance: resumes nothing" || fail "advance: resumes nothing" "$(mutating_calls)"

run advance "$TASK" implement-spec
expect "advance: the extra lap is a named choice with its count" \
  '.kind == "extra-lap" and .extra_lap.named and .extra_lap.arrival_would_be == 4 and .command[3:5] == ["--stage","implement-spec"]'
run advance "$TASK" review
expect "advance: a step past a judgment that passed is flagged, not refused" '.kind == "skips-judgment" and [.skipped_judgments[].step] == ["checks"] and .command != null'
run advance "$TASK" nope; [ "$status" = 2 ] && pass "advance: an unknown step is refused" || fail "advance: an unknown step is refused" "exit=$status"

# The one-way door: a resume at the handover is past the review, which has not passed.
pr_draft="$dest/drafts/pull-request-repair.md"
run advance "$TASK" handover
[ "$status" = 1 ] && pass "door: proposing the handover exits 1" || fail "door: proposing the handover exits 1" "exit=$status"
expect "door: proposing the handover yields the warning and no command" \
  '.kind == "one-way-door" and .door.crossed and .door.past == ["review"] and (.warnings | index("one-way-door") != null) and .command == null and .shown == null and .refused == ["not-confirmed"]'
run advance "$TASK" extra-handover; expect "door: so does the step before it" '.kind == "one-way-door" and .command == null'
printf 'written after the salvage\n' >"$work/home/scratch/$TASK/late.txt"
run advance "$TASK" handover --confirmed "yes, leave by the door"
expect "door: the person's word is not enough while salvage is incomplete" '.command == null and .refused == ["salvage-incomplete"] and (.door.open | not)'
[ ! -e "$pr_draft" ] && pass "door: a refusal drafts nothing" || fail "door: a refusal drafts nothing"
rm "$work/home/scratch/$TASK/late.txt"
run advance "$TASK" handover --confirmed "yes, leave by the door"
[ "$status" = 0 ] && pass "door: salvage complete and the person's word open it" || fail "door: salvage complete and the person's word open it" "exit=$status $(cat "$err")"
expect "door: the command then names the handover step" '.door.open and .command[3:5] == ["--stage","handover"] and (.message | contains("yes, leave by the door"))'
[ "$(grep -c '^- \[ \] ' "$pr_draft" 2>/dev/null)" = 7 ] && pass "door: the open findings travel as a checklist of seven" || fail "door: the open findings travel as a checklist of seven"
grep -qi 'repair' "$pr_draft" && grep -qi 'one-way door' "$pr_draft" && pass "door: the pull request section says it came out of a repair, by that door" || fail "door: the pull request section says it came out of a repair, by that door"
[ -z "$(mutating_calls)" ] && pass "door: resumes nothing" || fail "door: resumes nothing" "$(mutating_calls)"

# A task bound to a spec with no keep-open marker gets no resume command at all.
sed -e 's/^id: .*/id: nomarker/' -e '/^close_on_merge:/d' "$work/task-$TASK.md" >"$work/task-nomarker.md"
run diagnose nomarker; expect "keep-open: a bound task without the marker is diagnosed as missing it" '.spec.bound and .spec.keep_open_marker == "missing"'
run advance nomarker
expect "keep-open: no handover is reachable while the marker is missing" '.command == null and (.refused | index("keep-open-marker-missing") != null)'
run choose nomarker; expect "keep-open: restoring the marker is a condition of the advance" '[.recommendation.conditions[] | select(.restore_keep_open_marker)] | length == 1'

# A binary whose help no longer offers the flag gets no command.
grep -v -- '--stage' "$fixture/resume-help.txt" >"$work/resume-help.txt"
run advance "$TASK"; expect "advance: a flag the binary's help does not offer yields no command" '.command == null and .refused == ["resume-flags-not-in-help"]'
cp "$fixture/resume-help.txt" "$work/resume-help.txt"

# =============================== retreat ===================================
retreat_draft="$dest/drafts/retreat-built-and-left.md"
: >"$work/spoolway.calls"
bash -c 'exec 0<&- 1>/dev/null 2>&1; sleep 60; :' spoolway dispatch & dispatcher_pid=$!
printf '{"dispatcher_pid": %s, "tasks": []}' "$dispatcher_pid" >"$work/queue-list.json"
run retreat "$TASK"
[ "$status" = 1 ] && pass "retreat: exits 1 while a dispatcher runs" || fail "retreat: exits 1 while a dispatcher runs" "exit=$status"
expect "retreat: refuses while a dispatcher runs, with no step" '.refused == ["dispatcher-running"] and .steps == [] and .dispatcher.running'
[ ! -e "$retreat_draft" ] && pass "retreat: a refusal drafts nothing" || fail "retreat: a refusal drafts nothing"
kill "$dispatcher_pid"; wait "$dispatcher_pid" 2>/dev/null
printf '{"dispatcher_pid": null, "tasks": []}' >"$work/queue-list.json"

printf 'written after the salvage\n' >"$work/home/scratch/$TASK/late.txt"
run retreat "$TASK"; expect "retreat: refuses while the scratch space holds an unsalvaged file" '.refused == ["salvage-incomplete"] and .steps == []'
rm "$work/home/scratch/$TASK/late.txt"
! grep -q -- '--force' "$fixture/unqueue-help.txt" && pass "fixture: 0.19.0's unqueue help offers no --force" || fail "fixture: 0.19.0's unqueue help offers no --force"
printf '      --force\n          Interrupt any live agent lane\n' >>"$work/unqueue-help.txt"
run retreat "$TASK"; expect "retreat: a binary whose unqueue help still offers --force is not the one observed: no step" '.refused == ["unqueue-help-not-0-19"] and .steps == []'
cp "$fixture/unqueue-help.txt" "$work/unqueue-help.txt"

tip_before=$(git -C "$checkout" rev-parse "refs/heads/task/$TASK")
run retreat "$TASK"
[ "$status" = 0 ] && pass "retreat: exits 0 with the dispatcher stopped" || fail "retreat: exits 0 with the dispatcher stopped" "exit=$status $(cat "$err")"
expect "retreat: comment, commit of the loose work, push, check, plain unqueue, check, label by hand" \
  '[.steps[].do] == ["comment","commit","push","check-remote","unqueue","verify","unlabel"]'
expect "retreat: the unqueue is spoolway's own and plain: no --force" '[.steps[] | select(.do == "unqueue")][0].command == ["spoolway","queue","unqueue","smoke-implement-spec"]'
expect "retreat: no step is a pause or carries --force" '[.steps[] | select(.command) | .command | map(select(. == "--force" or . == "pause"))] | all(length == 0)'
expect "retreat: the commit step stages and commits the worktree's loose work, in the project's commit type" \
  '[.steps[] | select(.do == "commit")][0] | .files == 1 and (.command | join(" ") | contains("add -A") and contains("commit -m")) and (.command[-1] | test("^chore\\(smoke-implement-spec\\): "))'
expect "retreat: the push names the task's branch" '[.steps[] | select(.do == "push")][0].command[-2:] == ["origin","task/smoke-implement-spec"]'
expect "retreat: what to expect — the loose file is committed by the retreat, the local branch is deleted by the unqueue" \
  '.expect.observed_with == "spoolway 0.19.0" and .expect.uncommitted.files == 1 and .expect.uncommitted.committed_by_the_retreat and .expect.worktree.removed and .expect.branch.local == "deleted by the unqueue"'
! jq -e '.. | strings | select(test("kept-with-wip|wip\\("))' <<<"$out" >/dev/null && pass "retreat: none of 0.6.0's kept-with-wip fates remains" || fail "retreat: none of 0.6.0's kept-with-wip fates remains"
grep -qF 'chore(smoke-implement-spec): keep the work' "$retreat_draft" && grep -qi 'pushes them before the unqueue' "$retreat_draft" \
  && pass "retreat: the draft names the retreat's commit and says it precedes the unqueue" || fail "retreat: the draft names the retreat's commit and says it precedes the unqueue"
expect "retreat: what to expect — scratch is deleted, the command logs stay" \
  '.expect.scratch == {files: 4, deleted: true} and .expect.commands == {files: 3, deleted: false}'
expect "retreat: what to expect — the label stays, the counts are kept in pending and a re-queue drops them" \
  '.expect.tracker.in_progress_label == "stays" and .expect.document.keeps_arrivals["implement-spec"] == 3 and .expect.document.a_requeue_keeps_them == false and .expect.unverified == []'
[ -s "$retreat_draft" ] && pass "retreat: what was built and what was left is drafted" || fail "retreat: what was built and what was left is drafted"
grep -q 'unqueue --help$' "$work/spoolway.calls" && pass "retreat: the unqueue's help is read from the binary" || fail "retreat: the unqueue's help is read from the binary"
! grep -q 'queue pause' "$work/spoolway.calls" && pass "retreat: no queue pause is called" || fail "retreat: no queue pause is called"
[ -z "$(mutating_calls)" ] && pass "retreat: unqueues nothing" || fail "retreat: unqueues nothing" "$(mutating_calls)"
[ ! -e "$work/gh.calls" ] && pass "retreat: posts nothing (no gh call)" || fail "retreat: posts nothing (no gh call)" "$(cat "$work/gh.calls")"
retreat_out=$out
mapfile -t push_command < <(jq -r '.steps[] | select(.do == "push") | .command[]' <<<"$out")
[ "$(git -C "$checkout" rev-parse "refs/heads/task/$TASK")" = "$tip_before" ] && pass "retreat: the branch's tip is untouched" || fail "retreat: the branch's tip is untouched"

# Before anything: one commit is unpushed and one file is uncommitted.
run pushed "$TASK"
[ "$status" = 1 ] && pass "pushed: exits 1 while the remote lacks a commit" || fail "pushed: exits 1 while the remote lacks a commit" "exit=$status"
expect "pushed: one commit is not on the remote, and the worktree is not clean" '(.ok | not) and .remote.commits_not_on_remote == 1 and (.worktree.changes | length == 1)'

# The retreat's first steps, by hand: the loose work is committed (here under the step's own
# message), pushed, and the check passes while the local branch still exists.
keep_msg=$(jq -r '[.steps[] | select(.do == "commit")][0].command[-1]' <<<"$retreat_out")
git -C "$work/wt" add -A && git -C "$work/wt" commit -q -m "$keep_msg"
keep_full=$(git -C "$checkout" rev-parse "refs/heads/task/$TASK")
run pushed "$TASK"
expect "pushed: after the commit the remote lacks two commits" '(.ok | not) and .remote.commits_not_on_remote == 2'
"${push_command[@]}" >/dev/null 2>&1
run pushed "$TASK"
[ "$status" = 0 ] && pass "pushed: exits 0 after the push the retreat names, before the unqueue" || fail "pushed: exits 0 after the push the retreat names, before the unqueue" "exit=$status $(cat "$err")"
expect "pushed: the remote branch holds every commit of the local one" '.ok and .remote.commits_not_on_remote == 0 and .local_branch == "kept"'
# The unqueue, by hand, as the release notes describe it: worktree and local branch deleted with no
# commit first, scratch deleted, the document in pending without its run keys.
git -C "$checkout" worktree remove "$work/wt"; git -C "$checkout" branch -q -D "task/$TASK"
grep -vE '^(stage|run|branch|base_commit|cut_from|worktree_path|workspace_id|pane_id|tab_id):' "$work/task-$TASK.md" >"$work/home/pending/$TASK.md"
rm "$work/task-$TASK.md"; rm -rf "$work/home/scratch/$TASK"
run pushed "$TASK"
[ "$status" = 0 ] && pass "pushed: exits 0 after the unqueue, the remote standing past the first diagnosis's tip" || fail "pushed: exits 0 after the unqueue" "exit=$status $out"
expect "pushed: the branch is read from the salvaged document, and the document is in pending" '.ok and .document_source == "salvage" and .pending_document.present and (.worktree.present | not) and (.local_branch | startswith("deleted"))'
[ "$(git -C "$work/remote.git" rev-parse "refs/heads/task/$TASK")" = "$keep_full" ] && git -C "$work/remote.git" log -1 --format=%s "refs/heads/task/$TASK" | grep -q '^chore(' \
  && pass "pushed: the remote's tip is the retreat's own commit of the loose work" || fail "pushed: the remote's tip is the retreat's own commit of the loose work"

# =============================== record ====================================
: >"$work/spoolway.calls"
run record "$TASK" retreat
[ "$status" = 0 ] && pass "record: exits 0 after the retreat, from the salvaged document" || fail "record: exits 0 after the retreat" "exit=$status $(cat "$err")"
expect "record: one comment for the bound issue" \
  '[.drafts[] | select(.kind == "issue-comment")] | length == 1 and .[0].on == "https://github.com/example/app/issues/217"'
comment="$(jq -r '.drafts[] | select(.kind == "issue-comment") | .path' <<<"$out")"
grep -qF "$dest" "$comment" && grep -qF 'may not send this to `implement-spec`' "$comment" && grep -qi 'retreat' "$comment" \
  && pass "record: the comment carries the cause's evidence, the road and the salvage location" || fail "record: the comment carries the cause's evidence, the road and the salvage location"
expect "record: a task-document defect and a pipeline defect each go to the findings channel" \
  '[.drafts[] | select(.kind == "finding") | .defect] == ["task-document","pipeline"] and ([.defects[].kind] == ["task-document","pipeline"])'
all_there=true; while IFS= read -r f; do [ -s "$f" ] && head -1 "$f" | grep -q '^DRAFT' || all_there=false; done < <(jq -r '.drafts[].path' <<<"$out")
[ "$all_there" = true ] && pass "record: every draft is on disk and says it is a draft" || fail "record: every draft is on disk and says it is a draft"
expect "record: a retreat drafts no pull request section" '[.drafts[] | select(.kind == "pull-request")] | length == 0'
expect "record: names no commit of the unqueue" 'has("wip_commit") | not'
[ "$(git -C "$work/remote.git" rev-parse "refs/heads/task/$TASK")" = "$keep_full" ] \
  && pass "record: the remote keeps the retreat's commit untouched" || fail "record: the remote keeps the retreat's commit untouched"
run record "$TASK" door
expect "record: the door drafts a pull request section with every open finding" '[.drafts[] | select(.kind == "pull-request")][0].findings == 7'
[ "$(grep -c '^- \[ \] ' "$pr_draft")" = 7 ] && pass "record: the section on disk is a checklist of seven" || fail "record: the section on disk is a checklist of seven"
run record "$TASK" advance
expect "record: an advance drafts a pull request section that says it came out of a repair, with no checklist" '[.drafts[] | select(.kind == "pull-request")][0].findings == 0'
grep -qi 'repair' "$pr_draft" && [ "$(grep -c '^- \[ \] ' "$pr_draft")" = 0 ] && pass "record: the advance's section is on disk" || fail "record: the advance's section is on disk"
[ ! -e "$work/gh.calls" ] && pass "record: posts nothing (no gh call)" || fail "record: posts nothing (no gh call)" "$(cat "$work/gh.calls")"
[ -z "$(mutating_calls)" ] && pass "record: makes no mutating spoolway call" || fail "record: makes no mutating spoolway call" "$(mutating_calls)"
run record nope advance; [ "$status" != 0 ] && pass "record: a task with no document anywhere exits non-zero" || fail "record: a task with no document anywhere exits non-zero"

# The skill names every subcommand it runs.
missing_step=""; for sub in choose advance retreat pushed record; do grep -q "repair.sh $sub" "$skill" || missing_step="$missing_step $sub"; done
[ -z "$missing_step" ] && pass "skill: every road's subcommand is named in the skill" || fail "skill: every road's subcommand is named in the skill" "$missing_step"

# =============================== a Developing task, as its template writes it ===============
# Two more tasks, synthetic, with the shape of two live runs:
# `dev-advance`, parked by a refused route out of the failed command step `checks`,
# its criteria plain bullets, replayed while an override puts `implement` at `loop=1`; and
# `dev-retreat`, parked by its own implementer lane after `checks` had failed twice.
cp "$fixture/state-developing/commands/"* "$work/home/commands/"
for t in dev-advance dev-retreat; do git -C "$checkout" worktree add -q -b "task/$t" "$work/wt-$t" "$base_commit"; done
sed -e "s#@STATE@#$work/home#g" -e "s#@WORKTREE@#$work/wt-dev-advance#g" -e "s#@BASE_COMMIT@#$base_commit#g" \
  "$fixture/developing-blocked-task.md" >"$work/task-dev-advance.md"
sed -e "s#@STATE@#$work/home#g" -e "s#@WORKTREE@#$work/wt-dev-retreat#g" -e "s#@BASE_COMMIT@#$base_commit#g" \
  "$fixture/developing-lane-blocked-task.md" >"$work/task-dev-retreat.md"
sed -e 's/^id: .*/id: dev-checkboxes/' -e '/^## Acceptance criteria/,/^## References/s/^- /- [ ] /' "$work/task-dev-advance.md" >"$work/task-dev-checkboxes.md"
# The pipeline as an override leaves it: the stub now answers from a copy this test rewrites.
sed -i "s#$fixture/pipeline-show.txt#$work/pipeline-show.txt#" "$work/bin/spoolway"
sed '/^  implement  agent/s/loop=3/loop=1/' "$fixture/pipeline-show.txt" >"$work/pipeline-show.txt"

# The first task's worktree is gone by now (its retreat was replayed above), so snapshot's find complains.
before="$(snapshot 2>/dev/null)"; : >"$work/spoolway.calls"
run diagnose dev-advance
[ "$status" = 0 ] && pass "developing: diagnose exits 0" || fail "developing: diagnose exits 0" "exit=$status $(cat "$err")"
expect "developing: every plain-bullet criterion is listed, each passable" \
  '(.criteria | length == 3) and ([.criteria[].n] == [1,2,3]) and (.criteria | all(.passable and (.text | length > 0)))'
expect "developing: a criterion that wraps onto a second line is read whole" \
  '.criteria[0].text | (contains("src/devAdvance.ts") and contains("Conventional Commits subject"))'
plain="$(jq -c '[.criteria[].text]' <<<"$out")"
run diagnose dev-checkboxes
[ "$plain" = "$(jq -c '[.criteria[].text]' <<<"$out")" ] && pass "developing: the same criteria are read when they are checkboxes" || fail "developing: the same criteria are read when they are checkboxes" "$plain"
run diagnose dev-advance
expect "developing: the loop in force and the loop of the refusal line are both given, and which the dispatcher applied" \
  '[.loops[] | select(.step == "implement")][0] | .loop_in_force == 1 and .loop_in_refusal == 3 and .dispatcher_applied == 3 and .loop == 3 and .arrivals == 3 and .spent'
expect "developing: a step no refusal line names keeps the loop in force" \
  '[.loops[] | select(.step == "implement-spec")][0] | .loop_in_force == 3 and .loop_in_refusal == null and .dispatcher_applied == null and .loop == 3'
expect "developing: the cause uses the loop of the refusal line" \
  '.cause.kind == "spent-loop" and .cause.step == "implement" and .cause.from == "checks" and .cause.loop == 3 and .cause.arrivals == 3'
expect "developing: a plain resume lands on the step the task was blocked from" '.plain_resume.step == "checks" and .plain_resume.outcome == "runs"'
[ "$before" = "$(snapshot 2>/dev/null)" ] && pass "developing: diagnose writes nothing" || fail "developing: diagnose writes nothing"

run choose dev-advance
[ "$status" = 0 ] && pass "developing: choose exits 0" || fail "developing: choose exits 0" "exit=$status $(cat "$err")"
expect "developing: the failed command step is one open finding, repairable in the worktree" \
  '(.findings.open | length) == 1 and .findings.repairable == ["checks"] and .findings.for_person == [] and (.findings.open[0] | .kind == "command-step" and .step == "checks" and (.for_person | not))'
expect "developing: the finding names the step's log, and its exit code" \
  ".findings.open[0] | .exit == 2 and .log == \"$work/home/commands/dev-advance · checks.log\""
expect "developing: checks failed and review never ran" '[.judgments[] | "\(.step):\(.status)"] == ["checks:failed","review:not-run"]'
expect "developing: the road is advance, resuming at checks" '.recommendation.road == "advance" and .resume_step == "checks"'
[ -z "$(mutating_calls)" ] && pass "developing: diagnose and choose make no mutating spoolway call" || fail "developing: diagnose and choose make no mutating spoolway call" "$(mutating_calls)"

run advance dev-advance
expect "developing: the extra lap counts against the loop of the refusal line" \
  '.kind == "recommended" and .extra_lap == {step: "implement", loop: 3, arrivals: 3, arrival_would_be: 4, named: false}'
expect "developing: a judgment failing again parks the task, by that loop" '.on_failure | length == 2 and all(.parks)'

# With no refusal line there is one loop to give, the one in force.
cp "$fixture/pipeline-show.txt" "$work/pipeline-show.txt"
run diagnose dev-retreat
expect "developing: a task parked by its own lane has no refused route, and a plain resume lands on that lane's step" \
  '.cause.kind == "stopped-by-step" and .cause.step == "implement" and .plain_resume.step == "implement" and .plain_resume.outcome == "runs"'
expect "developing: with no refusal line the loop in force is the loop" \
  '[.loops[] | select(.step == "implement")][0] | .loop == 3 and .loop_in_force == 3 and .dispatcher_applied == null'
expect "developing: its plain-bullet criteria are listed too" '.criteria | length == 3'
run choose dev-retreat
expect "developing: a judgment that failed before the implementer's last visit, which ended on blocked, has failed" \
  '[.judgments[] | "\(.step):\(.status)"] == ["checks:failed","review:not-run"]'
expect "developing: and it is one open finding with its log" \
  "(.findings.open | length) == 1 and .findings.repairable == [\"checks\"] and .findings.open[0].log == \"$work/home/commands/dev-retreat · checks.log\""
# A pass is stale once the implementer has been visited again, even on a visit that ended on blocked.
sed -e 's/^id: .*/id: dev-stale/' -e '/01:12 `checks` exited 2/d' -e 's/^- 2026-10-09 01:12 → `implement`$/- 2026-10-09 01:12 → `review`\n- 2026-10-09 01:13 → `implement`: one finding/' \
  "$work/task-dev-retreat.md" >"$work/task-dev-stale.md"
run choose dev-stale
expect "developing: a judgment that passed before the implementer's last visit must run again" \
  '[.judgments[] | "\(.step):\(.status)"] == ["checks:not-run","review:failed"]'

# The retreat's draft of what was left names the failed command step.
run salvage dev-retreat
run retreat dev-retreat
[ "$status" = 0 ] && pass "developing: retreat exits 0" || fail "developing: retreat exits 0" "exit=$status $(cat "$err")"
grep -qF "dev-retreat · checks.log" "$checkout/.scratch/spoolway/dev-retreat/drafts/retreat-built-and-left.md" \
  && pass "developing: the retreat's draft lists the failed command step with its log" || fail "developing: the retreat's draft lists the failed command step with its log"
[ -z "$(mutating_calls)" ] && pass "developing: the roads make no mutating spoolway call" || fail "developing: the roads make no mutating spoolway call" "$(mutating_calls)"

# =============================== the first diagnosis =====================
# The fixture task again under another id, with a branch and a worktree of its own: the one above
# is used up by the retreat. It is moved on by hand, as a resume and then `done` would move it.
MOVED=moved-on
first_name=first-diagnosis.json
mdest="$checkout/.scratch/spoolway/$MOVED"
git -C "$checkout" worktree add -q -b "task/$MOVED" "$work/wt-moved" "$base_commit"
printf 'built\n' >"$work/wt-moved/built.txt"
git -C "$work/wt-moved" add built.txt && git -C "$work/wt-moved" commit -q -m "feat: built"
mkdir -p "$work/home/scratch/$MOVED"; printf 'notes\n' >"$work/home/scratch/$MOVED/notes.md"
sed -e "s#@STATE@#$work/home#g" -e "s#@WORKTREE@#$work/wt-moved#g" -e "s#@BASE_COMMIT@#$base_commit#g" \
  -e "s#^id: .*#id: $MOVED#" -e "s#^branch: .*#branch: task/$MOVED#" "$fixture/blocked-task.md" >"$work/blocked-$MOVED.md"
cp "$work/blocked-$MOVED.md" "$work/task-$MOVED.md"
move_on() { # move_on <stage> — the document on <stage>, with the lines of $work/moved.log ending its status log
  awk -v f="$work/moved.log" '/^## Handoff/ { while ((getline l < f) > 0) print l; print "" } { print }' "$work/blocked-$MOVED.md" \
    | sed -e "s/^stage: .*/stage: $1/" -e '/^blocked_from:/d' >"$work/task-$MOVED.md"
}

: >"$work/spoolway.calls"
run diagnose "$MOVED"; blocked_cause="$(jq -c '.cause' <<<"$out")"
[ ! -e "$mdest/$first_name" ] && pass "first diagnosis: diagnose keeps nothing" || fail "first diagnosis: diagnose keeps nothing"
run salvage "$MOVED"
expect "first diagnosis: a salvage on blocked writes it, under its fixed name beside the copies" \
  ".ok and .first_diagnosis.state == \"written\" and .first_diagnosis.path == \"$mdest/$first_name\""
[ "$(jq -c '.cause' "$mdest/$first_name" 2>/dev/null)" = "$blocked_cause" ] && jq -e '.stage == "blocked" and .cause.kind == "spent-loop"' "$mdest/$first_name" >/dev/null \
  && pass "first diagnosis: the file holds the cause as diagnosed on blocked" || fail "first diagnosis: the file holds the cause as diagnosed on blocked"
cp "$mdest/$first_name" "$work/first.kept"
run salvage "$MOVED"
expect "first diagnosis: a second salvage on blocked keeps it" '.ok and .first_diagnosis.state == "kept"'
[ -z "$(git -C "$checkout" status --short)" ] && pass "first diagnosis: it is git-ignored with the folder" || fail "first diagnosis: it is git-ignored with the folder"

# The repair: one commit in the worktree. The resume that `advance` proposes names it.
printf 'repaired\n' >"$work/wt-moved/built.txt"
git -C "$work/wt-moved" commit -q -am "fix: repair the finding"
repair_commit=$(git -C "$work/wt-moved" rev-parse --short HEAD)
run advance "$MOVED"
expect "advance: the branch's commits since the first diagnosis are the repair's" \
  ".repair.readable and (.repair.commits | length == 1) and (.repair.commits[0] | startswith(\"$repair_commit \"))"
expect "advance: the status-log message of the resume names the repair's commit" ".command != null and (.message | contains(\"$repair_commit\"))"
resume_message="$(jq -r '.message' <<<"$out")"

# Resumed at checks, and on review now. A salvage made here must not replace the first diagnosis.
printf -- '- 2026-10-07 09:00 → `checks`: %s\n- 2026-10-07 09:04 → `review`\n' "$resume_message" >"$work/moved.log"
move_on review
printf 'written by the review\n' >"$work/home/scratch/$MOVED/notes.md"
run diagnose "$MOVED"; expect "moved on: the task is diagnosed afresh as not blocked" '.cause.kind == "not-blocked"'
run salvage "$MOVED"
expect "moved on: a later salvage copies what changed and keeps the first diagnosis" '.ok and .first_diagnosis.state == "kept" and (.files | all(.match))'
cmp -s "$mdest/$first_name" "$work/first.kept" && [ "$(find "$mdest" -maxdepth 1 -name "$first_name*" | wc -l)" = 1 ] \
  && pass "moved on: the first diagnosis is byte for byte what it was" || fail "moved on: the first diagnosis is byte for byte what it was"

record_keeps_the_cause() { # <name> — $out is a record: the cause is the first one, with its evidence, on disk too
  expect "$1: the record carries the first cause and its evidence" \
    '(.refused | length == 0) and .cause.source == "first-diagnosis" and .cause.kind == "spent-loop" and (.cause.evidence | contains("may not send this to `implement-spec`"))'
  comment="$(jq -r '.drafts[] | select(.kind == "issue-comment") | .path' <<<"$out")"
  grep -qF "$(jq -r '.cause.sentence' "$work/first.kept")" "$comment" 2>/dev/null && grep -qF "$(jq -r '.cause.evidence | ltrimstr("- ")' "$work/first.kept")" "$comment" \
    && pass "$1: the comment on disk holds the first diagnosis's sentence and evidence line" || fail "$1: the comment on disk holds the first diagnosis's sentence and evidence line"
}
run record "$MOVED" advance
[ "$status" = 0 ] && pass "record after a resume: exits 0" || fail "record after a resume: exits 0" "exit=$status $(cat "$err")"
record_keeps_the_cause "record after a resume"
expect "record after a resume: the outcome is the resume line and the stage reached" \
  '.outcome.resume.step == "checks" and (.outcome.resume.line | contains("→ `checks`")) and .outcome.stage == "review" and .document_source == "spoolway"'
expect "record after a resume: the repair's commit is named" ".repair.commits == [\"$repair_commit\"]"
grep -qF "$repair_commit" "$comment" && grep -qF "$(jq -r '.outcome.resume.line' <<<"$out")" "$comment" \
  && pass "record after a resume: the comment on disk names the commit and quotes the resume line" || fail "record after a resume: the comment on disk names the commit and quotes the resume line"
expect "record after a resume: the pipeline defect of the block still goes to the findings channel" '[.defects[].kind] == ["task-document","pipeline"]'
grep -qF "$(jq -r '.cause.sentence' "$work/first.kept")" "$mdest/drafts/pull-request-repair.md" \
  && pass "record after a resume: the pull request section holds the first cause" || fail "record after a resume: the pull request section holds the first cause"

# A resume whose message is the person's own names no commit: the branch is read instead.
printf -- '- 2026-10-07 09:00 → `checks`: unblocked by hand\n- 2026-10-07 09:04 → `review`\n' >"$work/moved.log"
move_on review
run record "$MOVED" advance
expect "record after a resume: with no commit in the resume line, the repair's commits are read from the branch" \
  ".repair.read_from == \"branch\" and (.repair.commits | length == 1) and (.repair.commits[0] | startswith(\"$repair_commit \"))"

# After done: the document is archived on `done`, and the worktree, the branch, the scratch space
# and the command logs are gone. Only the status log still names the repair's commit.
printf -- '- 2026-10-07 09:00 → `checks`: %s\n- 2026-10-07 09:04 → `review`\n- 2026-10-07 09:09 → `extra-handover`\n- 2026-10-07 09:09 → `handover`\n- 2026-10-07 09:10 → `signals`\n- 2026-10-07 09:10 → `report`\n- 2026-10-07 09:11 → `extra-cleanup`\n- 2026-10-07 09:11 → `done`\n' "$resume_message" >"$work/moved.log"
move_on done
git -C "$checkout" worktree remove --force "$work/wt-moved"; git -C "$checkout" branch -q -D "task/$MOVED"
rm -rf "$work/home/scratch/$MOVED"
run record "$MOVED" advance
[ "$status" = 0 ] && pass "record after done: exits 0" || fail "record after done: exits 0" "exit=$status $(cat "$err")"
record_keeps_the_cause "record after done"
expect "record after done: the stage reached is done, and the commit comes from the resume line" \
  ".outcome.stage == \"done\" and .outcome.resume.step == \"checks\" and .repair == {commits: [\"$repair_commit\"], read_from: \"resume-line\"}"
run record "$MOVED" door
record_keeps_the_cause "record after done, by the door"
printf -- '- 2026-10-07 09:00 → `checks`: unblocked by hand\n- 2026-10-07 09:11 → `done`\n' >"$work/moved.log"
move_on done
run record "$MOVED" advance
expect "record after done: commits no line names and no branch holds are reported as not readable, never as none" '.repair == {commits: [], read_from: null}'

# Spoolway holds the document no longer: the record is written from the salvaged copy.
rm "$work/task-$MOVED.md"
run record "$MOVED" advance
[ "$status" = 0 ] && pass "record with the document gone from spoolway: exits 0" || fail "record with the document gone from spoolway: exits 0" "exit=$status $(cat "$err")"
record_keeps_the_cause "record with the document gone from spoolway"
expect "record with the document gone from spoolway: the stage reached is not claimed from an older copy" '.document_source == "salvage" and .outcome.stage == null and .outcome.resume.step == "checks"'
[ -z "$(mutating_calls)" ] && [ ! -e "$work/gh.calls" ] && pass "first diagnosis: no mutating spoolway call and no gh call" || fail "first diagnosis: no mutating spoolway call and no gh call" "$(mutating_calls)"

# A task that moved on before any salvage has no first diagnosis: the record is refused, not invented.
sed -e 's/^id: .*/id: late/' -e 's/^stage: .*/stage: review/' -e '/^blocked_from:/d' "$work/blocked-$MOVED.md" >"$work/task-late.md"
run salvage late
expect "no first diagnosis: a salvage of a task that has moved on writes none" '.ok and .first_diagnosis.state == "absent"'
[ ! -e "$checkout/.scratch/spoolway/late/$first_name" ] && pass "no first diagnosis: none is on disk" || fail "no first diagnosis: none is on disk"
run record late advance
[ "$status" = 1 ] && pass "no first diagnosis: the record exits 1" || fail "no first diagnosis: the record exits 1" "exit=$status"
expect "no first diagnosis: the record is refused and drafts nothing" '.refused == ["no-first-diagnosis"] and .drafts == []'
[ ! -e "$checkout/.scratch/spoolway/late/drafts/record-comment.md" ] && pass "no first diagnosis: no comment says the task is not on blocked" || fail "no first diagnosis: no comment says the task is not on blocked"

# The same id blocked again in another run: its diagnosis is a new first one, and the old is kept aside.
sed -e 's/^id: .*/id: late/' -e 's/^run: .*/run: r1111111111111111/' "$work/blocked-$MOVED.md" >"$work/task-late.md"
run salvage late; expect "another run: a first diagnosis is written on blocked" '.first_diagnosis.state == "written"'
sed -i 's/^run: .*/run: r2222222222222222/' "$work/task-late.md"
run salvage late
expect "another run: the diagnosis of an earlier run is not taken for this one's" '.first_diagnosis.state == "written"'
[ "$(jq -r .run "$checkout/.scratch/spoolway/late/$first_name")" = r2222222222222222 ] && [ "$(jq -r .run "$checkout/.scratch/spoolway/late/$first_name.~1~")" = r1111111111111111 ] \
  && pass "another run: the earlier run's diagnosis is kept as a numbered backup" || fail "another run: the earlier run's diagnosis is kept as a numbered backup"

# =============================== a task spoolway does not hold ==============
# Every subcommand answers it as the skill says a refusal is answered: one JSON object, exit 1.
for sub in diagnose salvage choose advance retreat pushed "record advance"; do
  set -- $sub
  if [ $# = 2 ]; then run "$1" no-such-task "$2"; else run "$1" no-such-task; fi
  [ "$status" = 1 ] && jq -e '.task == "no-such-task" and .refused == ["unknown-task"]' <<<"$out" >/dev/null 2>&1 \
    && pass "unknown task: $1 answers one refusal object and exits 1" || fail "unknown task: $1 answers one refusal object and exits 1" "exit=$status out=$out"
done
[ ! -e "$checkout/.scratch/spoolway/no-such-task" ] && pass "unknown task: nothing is written" || fail "unknown task: nothing is written"
grep -q 'unknown-task' "$skill" && grep -q 'exits 2' "$skill" && pass "skill: it names the refusal of an unknown task, and the exit of a call that cannot be read" || fail "skill: it names the refusal of an unknown task, and the exit of a call that cannot be read"

# =============================== a retreat with nothing to list ============
# The shape of a live retreat: the lane reported the block itself, checks had
# failed twice, review never ran, no numbered finding, a clean tree, an empty scratch space.
LANE=live-401-retreat
ldest="$checkout/.scratch/spoolway/$LANE"
git -C "$checkout" worktree add -q -b "task/$LANE" "$work/wt-lane" "$base_commit"
printf 'x\n' >"$work/wt-lane/probe.txt"
git -C "$work/wt-lane" add probe.txt && git -C "$work/wt-lane" commit -q -m "chore(probe): one file"
sed -e "s#@STATE@#$work/home#g" -e "s#@WORKTREE@#$work/wt-lane#g" -e "s#@BASE_COMMIT@#$base_commit#g" \
  "$fixture/lane-blocked-task.md" >"$work/task-$LANE.md"
# No list of a draft is left empty: a line that ends a heading with a colon has an item under it.
sections_filled() { awk 'prev ~ /:$/ && $0 !~ /^- / { bad = 1 } { prev = $0 } END { exit (bad || prev ~ /:$/) }' "$1"; }

run salvage "$LANE"
expect "lane block: the first diagnosis is a stop from the step itself" '.ok and .empty and .first_diagnosis.state == "written"'
run retreat "$LANE"
[ "$status" = 0 ] && pass "lane block: the retreat exits 0" || fail "lane block: the retreat exits 0" "exit=$status $(cat "$err")"
expect "lane block: nothing is uncommitted, and the one open finding is the failed command step, none numbered" \
  '.expect.uncommitted.files == 0 and .left.findings == ["checks"] and .left.criteria == []'
expect "lane block: what is left is the judgment that failed, checks, with its log line" \
  '.left.judgment.step == "checks" and .left.judgment.fail_to == "implement" and (.left.judgment.log_line | contains("exited 2"))'
ldraft="$(jq -r '.drafts[0].path' <<<"$out")"
sections_filled "$ldraft" && pass "lane block: no section of the retreat draft is empty" || fail "lane block: no section of the retreat draft is empty" "$(cat "$ldraft")"
awk '/^Left:$/ { on = 1; next } on && /^$/ { exit } on' "$ldraft" | grep -qF '`checks`' \
  && pass "lane block: the draft's Left section names checks" || fail "lane block: the draft's Left section names checks"
expect "lane block: a clean tree has no commit step, and the push and the check still precede the unqueue" \
  '([.steps[].do] == ["comment","push","check-remote","unqueue","verify","unlabel"]) and .expect.uncommitted.committed_by_the_retreat == false and .expect.uncommitted.commit == null'
! grep -qiE 'wip\(|one more commit|rewritten' "$ldraft" && pass "lane block: a clean tree's draft mentions no commit of the unqueue" || fail "lane block: a clean tree's draft mentions no commit of the unqueue" "$(cat "$ldraft")"
sections_filled "$retreat_draft" && pass "retreat: the first fixture's draft has no empty section either" || fail "retreat: the first fixture's draft has no empty section either"

# The unqueue, by hand: the tree was clean, so no commit is added; the document in pending
# has lost its run keys, and spoolway shows that stripped document.
git -C "$checkout" worktree remove "$work/wt-lane"
grep -vE '^(stage|run|branch|base_commit|cut_from|worktree_path|workspace_id|pane_id|tab_id):' "$work/task-$LANE.md" >"$work/home/pending/$LANE.md"
cp "$work/home/pending/$LANE.md" "$work/task-$LANE.md"
run record "$LANE" retreat
[ "$status" = 0 ] && pass "record after an unqueue: exits 0" || fail "record after an unqueue: exits 0" "exit=$status $(cat "$err")"
expect "record after an unqueue: the first cause and its evidence, from the first diagnosis" \
  '.cause.source == "first-diagnosis" and .cause.kind == "stopped-by-step" and (.cause.evidence | contains("→ `blocked`")) and .document_source == "salvage"'
expect "record after an unqueue: a retreat names no repair commit" '.repair == null'
comment="$(jq -r '.drafts[] | select(.kind == "issue-comment") | .path' <<<"$out")"
grep -qF "$(jq -r '.cause.evidence | ltrimstr("- ")' "$ldest/$first_name")" "$comment" \
  && pass "record after an unqueue: the comment on disk holds the evidence line" || fail "record after an unqueue: the comment on disk holds the evidence line"
! grep -qiE 'wip\(|rewrite' "$comment" && pass "record after an unqueue: the comment mentions no unqueue commit" || fail "record after an unqueue: the comment mentions no unqueue commit"

# =============================== a retreat the remote already holds =========
# The shape of probe-10-b: a clean tree, every commit already pushed. The forced
# unqueue deletes the local branch, so there is nothing to push, and the check reads the remote.
HELD=remote-holds
hdest="$checkout/.scratch/spoolway/$HELD"
git -C "$checkout" worktree add -q -b "task/$HELD" "$work/wt-held" "$base_commit"
printf 'held\n' >"$work/wt-held/held.txt"
git -C "$work/wt-held" add held.txt && git -C "$work/wt-held" commit -q -m "chore(probe): held"
git -C "$work/wt-held" push -q origin "task/$HELD"
held_tip=$(git -C "$checkout" rev-parse "refs/heads/task/$HELD")
sed -e "s#@STATE@#$work/home#g" -e "s#@WORKTREE@#$work/wt-held#g" -e "s#@BASE_COMMIT@#$base_commit#g" \
  -e "s#^id: .*#id: $HELD#" -e "s#^branch: .*#branch: task/$HELD#" "$fixture/lane-blocked-task.md" >"$work/task-$HELD.md"
: >"$work/spoolway.calls"
run salvage "$HELD"
run retreat "$HELD"
[ "$status" = 0 ] && pass "remote holds it: the retreat exits 0" || fail "remote holds it: the retreat exits 0" "exit=$status $(cat "$err")"
expect "remote holds it: the unqueue deletes the local branch, and the push is still a step" \
  '.expect.branch.local == "deleted by the unqueue" and [.steps[].do] == ["comment","push","check-remote","unqueue","verify","unlabel"]'
! grep -qiE 'wip\(|one more commit' "$(jq -r '.drafts[0].path' <<<"$out")" && pass "remote holds it: the draft mentions no commit of the unqueue" || fail "remote holds it: the draft mentions no commit of the unqueue"
# The unqueue, by hand, as probe-10-b observed it: worktree removed, local branch deleted.
git -C "$checkout" worktree remove "$work/wt-held"; git -C "$checkout" branch -q -D "task/$HELD"
grep -vE '^(stage|run|branch|base_commit|cut_from|worktree_path|workspace_id|pane_id|tab_id):' "$work/task-$HELD.md" >"$work/home/pending/$HELD.md"
cp "$work/home/pending/$HELD.md" "$work/task-$HELD.md"
run pushed "$HELD"
[ "$status" = 0 ] && pass "remote holds it: pushed exits 0 with no local branch" || fail "remote holds it: pushed exits 0 with no local branch" "exit=$status $out"
expect "remote holds it: the remote stands at the first diagnosis's tip" '.ok and (.local_branch_exists | not) and (.local_branch | startswith("deleted"))'
git -C "$work/remote.git" update-ref "refs/heads/task/$HELD" "$base_commit"
run pushed "$HELD"
[ "$status" = 1 ] && expect "remote holds it: a remote at another commit is not taken for the branch" '(.ok | not) and .local_branch == "missing"' \
  || fail "remote holds it: a remote at another commit is not taken for the branch" "exit=$status"
git -C "$work/remote.git" update-ref "refs/heads/task/$HELD" "$held_tip"
run record "$HELD" retreat
[ "$status" = 0 ] && pass "remote holds it: record exits 0" || fail "remote holds it: record exits 0" "exit=$status $(cat "$err")"
grep -qF "deleted locally by the unqueue; the remote holds it at ${held_tip:0:7}" "$(jq -r '.drafts[] | select(.kind == "issue-comment") | .path' <<<"$out")" \
  && pass "remote holds it: the comment says where the branch is" || fail "remote holds it: the comment says where the branch is"
[ -z "$(mutating_calls)" ] && [ ! -e "$work/gh.calls" ] && pass "remote holds it: no mutating spoolway call and no gh call" || fail "remote holds it: no mutating spoolway call and no gh call" "$(mutating_calls)"
[ -z "$(mutating_calls)" ] && [ ! -e "$work/gh.calls" ] && pass "lane block: no mutating spoolway call and no gh call" || fail "lane block: no mutating spoolway call and no gh call" "$(mutating_calls)"

# The skill and the README name the file by its fixed name.
grep -qF "$first_name" "$skill" && grep -qF "$first_name" "$repo/README.md" && pass "skill: the first diagnosis has one name, in the skill and in the README" || fail "skill: the first diagnosis has one name, in the skill and in the README"

printf '\n%d failure(s)\n' "$failures"
[ "$failures" = 0 ]
