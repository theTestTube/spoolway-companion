#!/usr/bin/env bash
# Drives the update-road subcommands of claude-plugin/skills/setup/setup.sh offline: `spoolway`,
# `gh` and `uname` are stubs on the PATH, the release record and the project homes are fixtures
# under a throwaway HOME. Each test asserts nothing outside the checkout's ./.scratch/ changed.
# Usage: tests/spoolway-update.test.sh (needs bash, git, jq, sha256sum, tar)

set -u
unset "${!SPOOLWAY_@}" RUN_REPORT_REPO FINDINGS_REPO MATERIALIZING_REPO PAGES_DIR PAGES_LOG PAGES_COMPILE_PATTERN EXTRA_REPOS EXTRA_WORKTREE_ROOT

repo="$(cd "$(dirname "$0")/.." && pwd)"
setup="$repo/claude-plugin/skills/setup/setup.sh"
work="$(mktemp -d)"
[ -n "${KEEP:-}" ] || trap 'rm -rf "$work"' EXIT

failures=0
pass() { printf 'ok   %s\n' "$1"; }
fail() { printf 'FAIL %s\n' "$1"; [ -n "${2:-}" ] && printf '     %s\n' "$2"; failures=$((failures + 1)); }
check() { if eval "$2"; then pass "$1"; else fail "$1" "${3:-}"; fi; }

export HOME="$work/home"
mkdir -p "$HOME" "$work/bin" "$work/asis" "$work/rel"
export PATH="$work/bin:$PATH"
export REL="$work/rel"

git config --global user.email t@example.com; git config --global user.name t
git config --global init.defaultBranch main

# uname: always a linux x86_64 machine.
cat > "$work/bin/uname" <<'STUB'
#!/usr/bin/env bash
case "${1:-}" in -s) echo Linux ;; -m) echo x86_64 ;; *) echo Linux ;; esac
STUB

# spoolway: the As-Is, version from $AS_IS; queue list --json from $HOME/.spoolway/<home>.json,
# found by -C <root>; the three probed commands succeed unless a marker file says otherwise.
mkdir -p "$work/asis"
cat > "$work/asis/spoolway" <<'STUB'
#!/usr/bin/env bash
v=${FAKE_VERSION:-0.17.0}
case "$1" in
  --version) echo "spoolway $v"; exit 0 ;;
  queue)
    [ "$2 $3" = "list --json" ] || exit 2
    [ "$4" = -C ] || exit 2
    f=$HOME/queue-json/$(basename "$5").json
    [ -f "$f" ] && cat "$f" || exit 1
    exit 0 ;;
esac
echo "ran $* v=$v keys=[${RUN_REPORT_REPO:-}${PAGES_DIR:-}] path=${PATH%%:*}"
[ -f "$HOME/fail-$v-$1" ] && exit 1
exit 0
STUB
chmod +x "$work/bin/uname" "$work/asis/spoolway"
cp "$work/asis/spoolway" "$work/bin/spoolway"
cp "$work/asis/spoolway" "$work/bin/spoolway-copy"

# release fixtures: a fake binary per version, its SHA256SUMS, notes and migrations.
mkrel() {
  local v=$1
  mkdir -p "$REL/v$v"
  sed "s/\${FAKE_VERSION:-0.17.0}/$v/" "$work/asis/spoolway" > "$REL/v$v/spoolway-linux-x64"
  (cd "$REL/v$v" && sha256sum spoolway-linux-x64 > SHA256SUMS)
}
for v in 0.17.0 0.18.0 0.19.0 0.20.0; do mkrel "$v"; done
printf '## Breaking changes\n- a key moved\n' > "$REL/v0.19.0/notes.md"
printf '## Fixes\n- a fix\n' > "$REL/v0.18.0/notes.md"
printf '## Fixes\n- one more\n' > "$REL/v0.20.0/notes.md"
printf '# migrations at 0.20.0\n' > "$REL/v0.20.0/migrations.md"
printf '# migrations at 0.17.0\n' > "$REL/v0.17.0/migrations.md"
printf '[{"tagName":"v0.20.0","publishedAt":"2026-11-20T10:00:00Z"},{"tagName":"v0.19.0","publishedAt":"2026-11-10T10:00:00Z"},{"tagName":"v0.18.0","publishedAt":"2026-11-01T10:00:00Z"},{"tagName":"v0.17.0","publishedAt":"2026-10-01T10:00:00Z"}]\n' > "$REL/list.json"

cat > "$work/bin/gh" <<'STUB'
#!/usr/bin/env bash
set -u
echo "$*" >> "$GH_LOG"
case "$1 $2" in
  "release list") cat "$REL/list.json" ;;
  "release view")
    if [[ "${3:-}" == --* ]]; then tag=v0.20.0; shift 2; else tag=$3; shift 3; fi
    [ -d "$REL/$tag" ] || { echo "release not found" >&2; exit 1; }
    case "$*" in
      *assets*) jq -n --arg a "$(ls "$REL/$tag" | grep -E '^(spoolway-|SHA256SUMS)' | tr '\n' ' ')" '{assets: ($a | split(" ") | map(select(. != "")) | map({name: .}))}' ;;
      *body*) jq -n --rawfile b "$REL/$tag/notes.md" '{body: $b}' ;;
      *) jq -n --arg t "$tag" '{tagName: $t}' ;;
    esac ;;
  "release download")
    tag=$3; dir=; pats=()
    shift 3
    while [ $# -gt 0 ]; do case $1 in --dir) dir=$2; shift 2 ;; --pattern) pats+=("$2"); shift 2 ;; *) shift ;; esac; done
    for p in "${pats[@]}"; do cp "$REL/$tag/$p" "$dir/$p"; done
    [ -z "${GH_CORRUPT:-}" ] || printf 'tampered\n' >> "$dir/spoolway-linux-x64" ;;
  "api -H")
    ref=${4##*ref=}
    [ -f "$REL/$ref/migrations.md" ] && cat "$REL/$ref/migrations.md" || { echo "404" >&2; exit 1; } ;;
  *) echo "fake gh: unexpected $*" >&2; exit 2 ;;
esac
STUB
chmod +x "$work/bin/gh"
export GH_LOG="$work/gh.log"; : > "$GH_LOG"

# consumer: a git checkout with a tracked companion.env and an ignored .scratch, with origin.
consumer() {
  local c=$work/$1
  mkdir -p "$c/.spoolway"; git init -q "$c"
  printf 'RUN_REPORT_REPO=acme/reports\n' > "$c/.spoolway/companion.env"
  echo ".scratch/" > "$c/.git/info/exclude"
  git -C "$c" add -A; git -C "$c" commit -q -m init
  git init -q --bare "$work/$1-origin.git"
  git -C "$c" remote add origin "$work/$1-origin.git"; git -C "$c" push -q origin main
  printf '%s\n' "$c"
}
# snapshot <dir>: every file outside .scratch, with its hash, plus git status.
snapshot() { (cd "$1" && find . -path ./.git -prune -o -path ./.scratch -prune -o -type f -print0 | sort -z | xargs -0 sha256sum; git status --short | grep -v '\.scratch'); }

c=$(consumer mono)
before=$(snapshot "$c")

# --- spoolway-version -----------------------------------------------------------------------
out=$(cd "$c" && bash "$setup" spoolway-version 2>&1)
check "spoolway-version: As-Is, every copy, the latest To-Be and the direction" \
  'grep -q "^as-is	0.17.0" <<<"$out" && grep -q "^copy	.*spoolway	0.17.0" <<<"$out" && grep -q "^to-be	0.20.0	latest" <<<"$out" && grep -q "^direction	forward" <<<"$out"' "$out"
out=$(cd "$c" && bash "$setup" spoolway-version v0.18.0 2>&1)
check "spoolway-version <v>: the named release, the v is optional" 'grep -q "^to-be	0.18.0	named" <<<"$out" && grep -q "^direction	forward" <<<"$out"' "$out"
out=$(cd "$c" && FAKE_VERSION=0.19.0 bash "$setup" spoolway-version 0.18.0 2>&1)
check "spoolway-version: a named release older than the As-Is is backward" 'grep -q "^direction	backward" <<<"$out"' "$out"
out=$(cd "$c" && bash "$setup" spoolway-version 9.9.9 2>&1); status=$?
check "spoolway-version: an unknown release stops" '[ $status -ne 0 ] && grep -q "no release v9.9.9" <<<"$out"' "$out"

# --- gap ------------------------------------------------------------------------------------
out=$(cd "$c" && bash "$setup" gap 0.20.0 2>&1); d=$c/.scratch/spoolway-0.17.0-to-0.20.0
check "gap: each release after the As-Is up to the To-Be, notes saved, breaking section found" \
  'grep -q "^release	v0.18.0	2026-11-01" <<<"$out" && grep -q "^release	v0.19.0.*breaking-changes section: present" <<<"$out" && grep -q "^release	v0.20.0" <<<"$out" && ! grep -q "^release	v0.17.0" <<<"$out" && [ -f "$d/notes/v0.19.0.md" ] && [ -f "$d/migrations/v0.20.0.md" ]' "$out"
check "gap: forward reads migrations at the To-Be tag only" '[ ! -f "$d/migrations/v0.17.0.md" ]'
out=$(cd "$c" && FAKE_VERSION=0.20.0 bash "$setup" gap 0.17.0 2>&1); d=$c/.scratch/spoolway-0.20.0-to-0.17.0
check "gap backward: the releases being undone, migrations at both tags" \
  'grep -q "^direction	backward" <<<"$out" && grep -q "^release	v0.20.0" <<<"$out" && ! grep -q "^release	v0.17.0" <<<"$out" && [ -f "$d/migrations/v0.17.0.md" ] && [ -f "$d/migrations/v0.20.0.md" ]' "$out"
out=$(cd "$c" && FAKE_VERSION=0.20.0 bash "$setup" gap 0.20.0 2>&1)
check "gap: equal versions say so and write nothing" 'grep -q "^equal" <<<"$out" || grep -q "equal: nothing" <<<"$out"' "$out"

# --- probe ----------------------------------------------------------------------------------
out=$(cd "$c" && bash "$setup" probe 0.20.0 2>&1); d=$c/.scratch/spoolway-0.17.0-to-0.20.0
check "probe: asset downloaded with its checksum file, hash ok, linked, prints the To-Be, installs nothing" \
  '[ -x "$d/bin/spoolway-linux-x64" ] && [ -f "$d/bin/SHA256SUMS" ] && grep -q "^checksum	ok" <<<"$out" && [ "$("$d/bin/spoolway" --version)" = "spoolway 0.20.0" ] && grep -q "installed nowhere" <<<"$out" && [ ! -e "$HOME/.local/bin/spoolway" ]' "$out"
rm -rf "$c/.scratch/spoolway-0.17.0-to-0.19.0"
out=$(cd "$c" && GH_CORRUPT=1 bash "$setup" probe 0.19.0 2>&1); status=$?; d=$c/.scratch/spoolway-0.17.0-to-0.19.0
check "probe: a checksum mismatch stops before any chmod or link and deletes the download" \
  '[ $status -ne 0 ] && grep -q "MISMATCH" <<<"$out" && [ ! -e "$d/bin/spoolway" ] && [ ! -e "$d/bin/spoolway-linux-x64" ]' "$out"
out=$(cd "$c" && bash "$setup" probe 0.99.0 2>&1); status=$?
check "probe: an unknown release stops" '[ $status -ne 0 ]' "$out"

# --- probe-run ------------------------------------------------------------------------------
rm -rf "$c/.scratch/spoolway-0.17.0-to-0.19.0"
d=$c/.scratch/spoolway-0.17.0-to-0.20.0
touch "$HOME/fail-0.17.0-doctor" "$HOME/fail-0.20.0-doctor" "$HOME/fail-0.20.0-pipeline" "$HOME/fail-0.17.0-sync"
export RUN_REPORT_REPO=machine/leak
out=$(cd "$c" && bash "$setup" probe-run 2>&1)
unset RUN_REPORT_REPO
check "probe-run: outputs saved under as-is/ and to-be/ for each command" \
  '[ -f "$d/as-is/sync-dry-run.out" ] && [ -f "$d/to-be/sync-dry-run.out" ] && [ -f "$d/as-is/pipeline-check.out" ] && [ -f "$d/to-be/doctor-no-live.out" ]' "$out"
check "probe-run: every difference classed new, pre-existing or fixed" \
  'grep -q "^pipeline-check	as-is exit 0	to-be exit 1	new" <<<"$out" && grep -q "^doctor-no-live	as-is exit 1	to-be exit 1	pre-existing" <<<"$out" && grep -q "^sync-dry-run	as-is exit 1	to-be exit 0	fixed" <<<"$out"' "$out"
check "probe-run: the probe first on the PATH and companion.env keys unset for both" \
  'grep -q "path=$d/bin" "$d/to-be/pipeline-check.out" && grep -q "keys=\[\]" "$d/to-be/pipeline-check.out" && grep -q "keys=\[\]" "$d/as-is/pipeline-check.out"' "$(cat "$d/to-be/pipeline-check.out")"
check "probe-run: ran spoolway with the To-Be's version, not the As-Is's" 'grep -q "v=0.20.0" "$d/to-be/pipeline-check.out" && grep -q "v=0.17.0" "$d/as-is/pipeline-check.out"'
rm -f "$HOME"/fail-*
out=$(cd "$(consumer bare)" && bash "$setup" probe-run 2>&1); status=$?
check "probe-run: without a probe it says to run probe first" '[ $status -ne 0 ] && grep -q "run probe" <<<"$out"' "$out"

# --- fresh-id -------------------------------------------------------------------------------
git -C "$c" push -q origin main:refs/heads/task/old-one
out=$(cd "$c" && bash "$setup" fresh-id old-one new-two 2>&1)
check "fresh-id: a branch on origin is taken, an absent one free" 'grep -q "^old-one	taken" <<<"$out" && grep -q "^new-two	free" <<<"$out"' "$out"

# --- queue-snapshot and salvage -------------------------------------------------------------
# A project home with one task whose worktree is ahead of origin and carries uncommitted work.
proj=$work/proj
mkdir -p "$proj"; git init -q "$proj"; git -C "$proj" commit -q --allow-empty -m base
git init -q --bare "$work/proj-origin.git"; git -C "$proj" remote add origin "$work/proj-origin.git"; git -C "$proj" push -q origin main
wt=$work/wt; git -C "$proj" worktree add -q "$wt" -b task/demo main
echo one > "$wt/a.txt"; git -C "$wt" add a.txt; git -C "$wt" commit -q -m "feat: a"
echo two > "$wt/b.txt"; git -C "$wt" add b.txt; git -C "$wt" commit -q -m "feat: b"
echo dirty >> "$wt/a.txt"; echo loose > "$wt/untracked.txt"
home=$HOME/.spoolway/proj-abc123
mkdir -p "$home/queue" "$home/commands" "$home/scratch/demo" "$HOME/queue-json"
printf 'id = "abc123"\nroot = "%s"\n' "$proj" > "$home/project.toml"
printf -- '---\nid: demo\nbranch: task/demo\nbase: main\nworktree_path: %s\n---\n\nbody\n' "$wt" > "$home/queue/demo.md"
printf 'log line\n' > "$home/commands/demo · checks.log"; printf 'note\n' > "$home/scratch/demo/n.md"
printf '{"dispatcher_pid":1,"tasks":[{"id":"demo","state":"running"},{"id":"idle","state":"queued"}]}\n' > "$HOME/queue-json/proj.json"
# a second home whose queue cannot be read
mkdir -p "$HOME/.spoolway/gone-zzz999"; printf 'id = "zzz999"\nroot = "%s"\n' "$work/gone" > "$HOME/.spoolway/gone-zzz999/project.toml"

before=$(snapshot "$c"); wtbefore=$(git -C "$wt" status --short; git -C "$wt" rev-parse HEAD)
out=$(cd "$c" && bash "$setup" queue-snapshot 2>&1)
check "queue-snapshot: each task with state, lane, branch and the commits origin lacks" \
  'grep -q "^project	$home	$proj" <<<"$out" && grep -q "^task	demo	running	lane yes	branch task/demo	unpushed commits 2" <<<"$out" && grep -q "^task	idle	queued	lane no	branch none	unpushed commits unknown" <<<"$out"' "$out"
check "queue-snapshot: an unreadable project home is named, not fatal" 'grep -q "^unreadable	.*gone-zzz999" <<<"$out"' "$out"
check "queue-snapshot: nothing outside ./.scratch/ changed" '[ "$(snapshot "$c")" = "$before" ] && [ "$wtbefore" = "$(git -C "$wt" status --short; git -C "$wt" rev-parse HEAD)" ] && [ -f "$c/.scratch/queue-snapshot.txt" ]'

out=$(cd "$c" && bash "$setup" salvage demo 2>&1); s=$c/.scratch/salvage-demo
check "salvage: the diff of uncommitted changes, the untracked files, the logs" \
  'grep -q "+dirty" "$s/diff.patch" && tar -tf "$s/untracked.tar" | grep -qx untracked.txt && [ -f "$s/logs/demo · checks.log" ] && [ -f "$s/logs/scratch/n.md" ] && [ -f "$s/task.md" ]' "$out"
check "salvage: the bundle verifies and holds the unpushed commits" \
  'git -C "$wt" bundle verify "$s/demo.bundle" > /dev/null 2>&1 && grep -q "^bundle	.*verified" <<<"$out" && git bundle list-heads "$s/demo.bundle" | grep -q . && git -C "$wt" rev-list --count origin/main..HEAD | grep -qx 2' "$out"
check "salvage: the bundle carries the commits and only them" 'git clone -q --bare "$work/proj-origin.git" "$work/verify.git" && git -C "$work/verify.git" fetch -q "$s/demo.bundle" HEAD:refs/heads/salv && [ "$(git -C "$work/verify.git" rev-list --count main..salv)" = 2 ]'
check "salvage: nothing outside ./.scratch/ changed, the worktree is as it was" '[ "$(snapshot "$c")" = "$before" ] && [ "$wtbefore" = "$(git -C "$wt" status --short; git -C "$wt" rev-parse HEAD)" ]'
out=$(cd "$c" && bash "$setup" salvage nosuch 2>&1); status=$?
check "salvage: an unknown task stops" '[ $status -ne 0 ] && grep -q "no task nosuch" <<<"$out"' "$out"

# --- the ignore guard and the whole-run check --------------------------------------------------
c2=$(consumer open); : > "$c2/.git/info/exclude"
out=$(cd "$c2" && bash "$setup" gap 0.20.0 2>&1); status=$?
check "a checkout that does not ignore ./.scratch/ is refused before anything is written" '[ $status -ne 0 ] && grep -q "not git-ignored" <<<"$out" && [ ! -e "$c2/.scratch" ]' "$out"
check "the tracked files of the checkout never changed" '[ "$(snapshot "$c")" = "$before" ]'
check "no project-specific name in this suite" '! grep -niE "$(printf "\x69[- ]?\x63\x68\x69\x6e\x67")" "$repo/tests/spoolway-update.test.sh"'

echo
[ $failures -eq 0 ] && echo "all passed" || echo "$failures failed"
[ $failures -eq 0 ]
