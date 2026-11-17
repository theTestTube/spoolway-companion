#!/usr/bin/env node
// gh-report: read the issues of a list of GitHub repositories with `gh` and write one
// self-contained HTML page: four line charts (created per day, open at the end of each day;
// last 2 weeks and last 3 months), one series per repository, a legend, hover tooltips and a
// data table under each chart. Read-only: it never writes to GitHub.
//
// Usage: node gh-report.js [--out FILE] [--limit N] [--today YYYY-MM-DD] owner/repo [owner/repo ...]
// Exit codes: 0 written; 1 a gh call failed, the limit was reached or the input is invalid; 2 usage.
// Environment: GH_REPORT_GH names the gh executable (default `gh`), for tests.
'use strict';
const fs = require('fs');
const { spawnSync } = require('child_process');

// Categorical slots 1-8 of the dataviz reference palette, in fixed order, light and dark.
// Validated with the dataviz skill's scripts/validate_palette.js (light surface #fcfcfb,
// dark surface #1a1a19). A ninth repository is refused, never folded into "Other".
const LIGHT = ['#2a78d6', '#eb6834', '#1baf7a', '#eda100', '#e87ba4', '#008300', '#6250d6', '#e34948'];
const DARK = ['#3987e5', '#d95926', '#199e70', '#c98500', '#d55181', '#0ca30c', '#9085e9', '#e66767'];

function die(msg, code = 1) { process.stderr.write(`gh-report: ${msg}\n`); process.exit(code); }

const args = process.argv.slice(2);
let out = 'gh-report.html', limit = 5000, todayArg = null;
const repos = [];
for (let i = 0; i < args.length; i++) {
  const a = args[i];
  if (a === '--out') out = args[++i];
  else if (a === '--limit') limit = Number(args[++i]);
  else if (a === '--today') todayArg = args[++i];
  else if (a.startsWith('-')) die(`unknown flag ${a}`, 2);
  else repos.push(a);
}
if (!out) die('--out needs a file', 2);
if (!Number.isInteger(limit) || limit < 1) die('--limit needs a positive integer', 2);
if (repos.length === 0) die('usage: gh-report.js [--out FILE] [--limit N] owner/repo [owner/repo ...]', 2);
for (const r of repos) if (!/^[\w.-]+\/[\w.-]+$/.test(r)) die(`not an owner/repo: ${r}`, 2);
if (new Set(repos).size !== repos.length) die('a repository is listed twice', 2);
if (repos.length > LIGHT.length) die(`${repos.length} repositories: the palette validates ${LIGHT.length} series; split the list`);
if (todayArg !== null && !/^\d{4}-\d{2}-\d{2}$/.test(todayArg)) die('--today needs YYYY-MM-DD', 2);

const gh = process.env.GH_REPORT_GH || 'gh';
function fetchIssues(repo) {
  const r = spawnSync(gh, ['issue', 'list', '-R', repo, '--state', 'all', '--limit', String(limit),
    '--json', 'number,state,createdAt,closedAt'], { encoding: 'utf8', maxBuffer: 1 << 28 });
  if (r.error) die(`cannot run ${gh}: ${r.error.message}`);
  if (r.status !== 0) die(`gh failed for ${repo} (exit ${r.status}): ${(r.stderr || '').trim()}`);
  let rows;
  try { rows = JSON.parse(r.stdout); } catch (e) { die(`gh gave invalid JSON for ${repo}`); }
  if (!Array.isArray(rows)) die(`gh gave no list for ${repo}`);
  if (rows.length >= limit) die(`${repo}: ${rows.length} issues reached --limit ${limit}; history would be cut. Raise --limit`);
  return rows;
}

function fetchBorn(repo) {
  const r = spawnSync(gh, ['repo', 'view', repo, '--json', 'createdAt'], { encoding: 'utf8' });
  if (r.error) die(`cannot run ${gh}: ${r.error.message}`);
  if (r.status !== 0) die(`gh repo view failed for ${repo} (exit ${r.status}): ${(r.stderr || '').trim()}`);
  let day;
  try { day = String(JSON.parse(r.stdout).createdAt).slice(0, 10); } catch (e) { die(`gh gave invalid JSON for ${repo}`); }
  if (!/^\d{4}-\d{2}-\d{2}$/.test(day)) die(`gh gave no creation date for ${repo}`);
  return day;
}

const series = repos.map((repo, i) => ({ repo, idx: i + 1, rows: fetchIssues(repo), born: fetchBorn(repo) }));

const DAY = 86400000;
const iso = d => d.toISOString().slice(0, 10);
const today = todayArg || iso(new Date());
const dayOf = s => (s ? s.slice(0, 10) : null);
function daysBetween(a, b) {
  const o = [];
  for (let d = new Date(a + 'T00:00:00Z'); iso(d) <= b; d = new Date(d.getTime() + DAY)) o.push(iso(d));
  return o;
}
function monthsBack(t, n) { const d = new Date(t + 'T00:00:00Z'); d.setUTCMonth(d.getUTCMonth() - n); return iso(d); }
const w14 = new Date(new Date(today + 'T00:00:00Z').getTime() - 14 * DAY);
const WIN = { short: [iso(w14), today], long: [monthsBack(today, 3), today] };

// Open at the end of day D: created on or before D and not closed on or before D.
// Issues created before the window count, which is why the full history is fetched.
function build(start, end) {
  const days = daysBetween(start, end);
  const created = {}, open = {};
  for (const s of series) {
    // null = the repository did not exist yet on that day; on or after creation it is a number.
    const c = Object.fromEntries(days.map(d => [d, d < s.born ? null : 0]));
    const o = Object.fromEntries(days.map(d => [d, d < s.born ? null : 0]));
    for (const row of s.rows) {
      const cd = dayOf(row.createdAt);
      if (c[cd] !== undefined && c[cd] !== null) c[cd]++;
      const cl = row.state === 'OPEN' ? null : dayOf(row.closedAt);
      for (const d of days) if (o[d] !== null && cd <= d && (cl === null || cl > d)) o[d]++;
    }
    created[s.repo] = c; open[s.repo] = o;
  }
  return { days, created, open };
}

const esc = s => String(s).replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
const fmtDay = d => { const [, m, dd] = d.split('-'); return `${dd}/${m}`; };
function niceStep(max) {
  const raw = Math.max(max / 5, 1), mag = Math.pow(10, Math.floor(Math.log10(raw))), f = raw / mag;
  return (f <= 1 ? 1 : f <= 2 ? 2 : f <= 5 ? 5 : 10) * mag;
}

function chart({ id, title, sub, win, xStep, mode }) {
  const { days, created, open } = build(win[0], win[1]);
  const data = mode === 'created' ? created : open;
  const max = Math.max(...series.flatMap(s => days.map(d => data[s.repo][d] ?? 0)), 1);
  const yStep = niceStep(max), yMax = Math.ceil(max / yStep) * yStep;
  const W = 560, H = 340, padL = 48, padR = 16, padT = 16, padB = 44;
  const iw = W - padL - padR, ih = H - padT - padB;
  const xAt = i => padL + (days.length === 1 ? iw / 2 : (i * iw) / (days.length - 1));
  const yAt = v => padT + ih - (v / yMax) * ih;
  let g = '';
  for (let v = 0; v <= yMax; v += yStep) {
    g += `<line class="grid" x1="${padL}" x2="${W - padR}" y1="${yAt(v)}" y2="${yAt(v)}"/>`;
    g += `<text class="axis" x="${padL - 6}" y="${yAt(v) + 4}" text-anchor="end">${v}</text>`;
  }
  days.forEach((d, i) => {
    if (i % xStep === 0 || i === days.length - 1)
      g += `<text class="axis" x="${xAt(i)}" y="${H - padB + 18}" text-anchor="middle">${fmtDay(d)}</text>`;
  });
  const unit = mode === 'created' ? 'created' : 'open';
  let lines = '', pts = '';
  for (const s of series) {
    const p = days.map((d, i) => [xAt(i), yAt(data[s.repo][d] ?? 0), d, data[s.repo][d]]).filter(q => q[3] !== null);
    // Break the polyline wherever days are missing (before the repository existed).
    const runs = [];
    for (const q of p) {
      const last = runs[runs.length - 1];
      if (last && days.indexOf(q[2]) === days.indexOf(last[last.length - 1][2]) + 1) last.push(q); else runs.push([q]);
    }
    for (const run of runs)
      lines += `<polyline class="line s${s.idx}" points="${run.map(q => q[0] + ',' + q[1]).join(' ')}"/>`;
    for (const [x, y, d, v] of p)
      pts += `<g class="pt"><circle class="hit" cx="${x}" cy="${y}" r="10"/><circle class="dot s${s.idx}" cx="${x}" cy="${y}" r="3.5"/><title>${esc(s.repo)} · ${fmtDay(d)}: ${v} ${unit}</title></g>`;
  }
  const legend = series.map(s => `<li><span class="swatch s${s.idx}"></span>${esc(s.repo)}</li>`).join('');
  const head = '<tr><th>Day</th>' + series.map(s => `<th>${esc(s.repo)}</th>`).join('') + '<th>Total</th></tr>';
  const body = days.map(d => {
    const v = series.map(s => data[s.repo][d]);
    return `<tr><td>${fmtDay(d)}</td>${v.map(x => `<td>${x === null ? '' : x}</td>`).join('')}<td>${v.reduce((a, b) => a + (b ?? 0), 0)}</td></tr>`;
  }).join('');
  const sums = series.map(s => mode === 'created' ? days.reduce((a, d) => a + (created[s.repo][d] ?? 0), 0) : (open[s.repo][win[1]] ?? 0));
  const foot = `<tr><th>${mode === 'created' ? 'Created in window' : 'Open today'}</th>${sums.map(x => `<th>${x}</th>`).join('')}<th>${sums.reduce((a, b) => a + b, 0)}</th></tr>`;
  return `<section class="card" id="${id}">
<h2>${esc(title)}</h2>
<p class="sub">${esc(sub)}</p>
<ul class="legend">${legend}</ul>
<svg viewBox="0 0 ${W} ${H}" role="img" aria-label="${esc(title)}: ${esc(sub)}">${g}${lines}${pts}</svg>
<details><summary>Data table</summary><div class="tablewrap"><table><thead>${head}</thead><tbody>${body}</tbody><tfoot>${foot}</tfoot></table></div></details>
</section>`;
}

const range = w => `${fmtDay(w[0])} – ${fmtDay(w[1])}`;
const charts = [
  chart({ id: 'created-2w', title: 'Created · last 2 weeks', sub: `${range(WIN.short)} · issues created per day`, win: WIN.short, xStep: 2, mode: 'created' }),
  chart({ id: 'created-3m', title: 'Created · last 3 months', sub: `${range(WIN.long)} · issues created per day`, win: WIN.long, xStep: 7, mode: 'created' }),
  chart({ id: 'open-2w', title: 'Open · last 2 weeks', sub: `${range(WIN.short)} · open at the end of each day`, win: WIN.short, xStep: 2, mode: 'open' }),
  chart({ id: 'open-3m', title: 'Open · last 3 months', sub: `${range(WIN.long)} · open at the end of each day`, win: WIN.long, xStep: 7, mode: 'open' }),
];

const vars = (arr, pad) => arr.map((c, i) => `${pad}--s${i + 1}:${c};`).join('');
const cls = LIGHT.map((_, i) => `.s${i + 1}{--c:var(--s${i + 1})}`).join('');
const html = `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>GitHub issues report</title>
<style>
:root{color-scheme:light;--surface:#fcfcfb;--text:#0b0b0b;--text-2:#52514e;--grid:#e4e3df;${vars(LIGHT, '')}}
@media (prefers-color-scheme:dark){:root:where(:not([data-theme="light"])){color-scheme:dark;--surface:#1a1a19;--text:#f0efec;--text-2:#c3c2b7;--grid:#2e2e2b;${vars(DARK, '')}}}
:root[data-theme="dark"]{color-scheme:dark;--surface:#1a1a19;--text:#f0efec;--text-2:#c3c2b7;--grid:#2e2e2b;${vars(DARK, '')}}
*{box-sizing:border-box}
body{margin:0;padding:16px;background:var(--surface);color:var(--text);font:14px/1.4 system-ui,sans-serif}
main{max-width:1280px;margin:0 auto}
h1{font-size:18px;margin:0 0 12px}
.row{display:grid;grid-template-columns:1fr 1fr;gap:16px;align-items:start;margin-bottom:16px}
@media (max-width:900px){.row{grid-template-columns:1fr}}
.card{border:1px solid var(--grid);border-radius:8px;padding:12px;min-width:0}
.card h2{font-size:15px;margin:0}
.sub{color:var(--text-2);margin:2px 0 8px;font-size:13px}
ul.legend{list-style:none;padding:0;margin:0 0 6px;display:flex;flex-wrap:wrap;gap:4px 12px;font-size:12px}
.swatch{display:inline-block;width:14px;height:4px;border-radius:2px;vertical-align:middle;margin-right:6px}
svg{width:100%;height:auto;display:block}
.grid{stroke:var(--grid);stroke-width:1}
.axis{fill:var(--text-2);font-size:11px}
.line{fill:none;stroke:var(--c);stroke-width:2;stroke-linejoin:round;stroke-linecap:round}
.dot{fill:var(--c);stroke:var(--surface);stroke-width:1.5}
.hit{fill:transparent}
.pt:hover .dot{r:5.5}
.swatch{background:var(--c)}
${cls}
details{margin-top:8px;color:var(--text-2);font-size:13px}
summary{cursor:pointer}
.tablewrap{overflow-x:auto}
table{border-collapse:collapse;margin-top:6px;width:100%;font-size:12px}
th,td{text-align:right;padding:3px 6px;border-bottom:1px solid var(--grid);white-space:nowrap}
th:first-child,td:first-child{text-align:left}
.note{color:var(--text-2);font-size:12px}
</style>
</head>
<body>
<main>
<h1>GitHub issues · ${series.map(s => esc(s.repo)).join(', ')}</h1>
<div class="row">${charts[0]}${charts[1]}</div>
<div class="row">${charts[2]}${charts[3]}</div>
<p class="note">Generated ${today} (UTC days). Open counts rebuild each day from created and closed dates; an issue that was reopened keeps only its last close date, so its earlier open span is miscounted. Pull requests are not counted.</p>
</main>
</body>
</html>
`;
fs.writeFileSync(out, html);
process.stdout.write(`gh-report: wrote ${out}\n`);
for (const s of series) {
  const n = s.rows.filter(r => r.state === 'OPEN').length;
  process.stdout.write(`open today ${s.repo}: ${n}\n`);
}
