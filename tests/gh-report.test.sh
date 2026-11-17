#!/usr/bin/env bash
# Drives claude-plugin/skills/gh-report/gh-report.js with a stub `gh` and fixture issues.
# Usage: tests/gh-report.test.sh
set -u
repo="$(cd "$(dirname "$0")/.." && pwd)"
script="$repo/claude-plugin/skills/gh-report/gh-report.js"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
failures=0
pass() { printf 'ok   %s\n' "$1"; }
fail() { printf 'FAIL %s\n' "$1"; [ -n "${2:-}" ] && printf '     %s\n' "$2"; failures=$((failures + 1)); }
check() { if eval "$2"; then pass "$1"; else fail "$1" "$2"; fi; }

if ! command -v node > /dev/null; then echo "gh-report: node is not on PATH, skipped"; exit 0; fi

# Stub gh: prints $FIX/<owner>__<repo>.json for `issue list -R <owner>/<repo>`; FAIL=<repo> fails it.
cat > "$work/gh" <<'STUB'
#!/usr/bin/env bash
if [ "$1 $2" = "repo view" ]; then
  r="$3"; [ "${FAILVIEW:-}" = "$r" ] && { echo "boom" >&2; exit 1; }
  cat "$FIX/${r/\//__}.view"; exit 0
fi
while [ $# -gt 0 ]; do [ "$1" = "-R" ] && r="$2"; shift; done
[ "${FAIL:-}" = "$r" ] && { echo "boom" >&2; exit 1; }
cat "$FIX/${r/\//__}.json"
STUB
chmod +x "$work/gh"
mkdir -p "$work/fix"
# today 2026-11-17: a open since long before the window; b closed inside it; c reopened shape (closed).
cat > "$work/fix/o__a.json" <<'J'
[{"number":1,"state":"OPEN","createdAt":"2026-01-05T10:00:00Z","closedAt":null},
 {"number":2,"state":"CLOSED","createdAt":"2026-01-06T10:00:00Z","closedAt":"2026-11-10T09:00:00Z"},
 {"number":3,"state":"OPEN","createdAt":"2026-11-16T23:00:00Z","closedAt":null}]
J
echo '[]' > "$work/fix/o__empty.json"
for n in a empty; do echo '{"createdAt":"2020-01-01T00:00:00Z"}' > "$work/fix/o__$n.view"; done
echo '[]' > "$work/fix/o__new.json"
echo '{"createdAt":"2026-11-10T08:00:00Z"}' > "$work/fix/o__new.view"
export GH_REPORT_GH="$work/gh" FIX="$work/fix"
run() { node "$script" --today 2026-11-17 --out "$work/r.html" "$@"; }

out=$(run o/a o/empty 2>&1); st=$?
run --out "$work/n.html" o/a o/new > /dev/null 2>&1
check "writes the page" "[ $st -eq 0 ] && [ -s $work/r.html ]"
check "four charts and four tables" "[ \$(grep -c '<section class=\"card\"' $work/r.html) -eq 4 ] && [ \$(grep -c '<table>' $work/r.html) -eq 4 ]"
check "open today matches the open issues" "grep -qx 'open today o/a: 2' <<<\"\$out\""
check "empty repository still has a series" "grep -q 'open today o/empty: 0' <<<\"\$out\" && grep -q 'class=\"line s2\"' $work/r.html"
check "issue created before the window counts as open" "grep -q 'o/a · 17/11: 2 open' $work/r.html"
check "closed issue stops counting after its close day" "grep -q 'o/a · 09/11: 2 open' $work/r.html && grep -q 'o/a · 10/11: 1 open' $work/r.html"
check "days before creation have no dot and a blank cell" "! grep -q 'o/new · 09/11' $work/n.html && grep -q 'o/new · 10/11: 0 open' $work/n.html && grep -q '<tr><td>09/11</td><td>2</td><td></td>' $work/n.html"
check "days from creation on are drawn at zero" "grep -q 'o/new · 17/11: 0 created' $work/n.html"
check "no Other series" "! grep -qi 'other' $work/r.html"

FAILVIEW=o/a run o/a > /dev/null 2>&1; check "repo view failure exits non-zero" "[ $? -ne 0 ]"
FAIL=o/a run o/a > /dev/null 2>&1; check "gh failure exits non-zero" "[ $? -ne 0 ]"
run --limit 3 o/a > /dev/null 2>&1; check "limit reached exits non-zero" "[ $? -ne 0 ]"
run > /dev/null 2>&1; check "no repository exits non-zero" "[ $? -ne 0 ]"
run o/a o/a > /dev/null 2>&1; check "duplicate repository refused" "[ $? -ne 0 ]"
run a/1 a/2 a/3 a/4 a/5 a/6 a/7 a/8 a/9 > /dev/null 2>&1; check "nine repositories refused" "[ $? -ne 0 ]"

[ -f "$repo/claude-plugin/skills/gh-report/SKILL.md" ] && grep -q '^name: gh-report$' "$repo/claude-plugin/skills/gh-report/SKILL.md" \
  && pass "skill has its name" || fail "skill has its name"

[ "$failures" -eq 0 ]
