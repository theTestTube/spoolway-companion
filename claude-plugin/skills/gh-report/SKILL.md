---
name: gh-report
description: Use when the user asks for a GitHub issue report or issue charts across several repositories. Takes a list of owner/repo and writes one HTML page of line charts (created and open issues, last 2 weeks and last 3 months), one series per repository.
---

# gh-report

Read-only: the script only calls `gh issue list` and `gh repo view`; it writes nothing to GitHub.

1. Get the repositories as `owner/repo` from the person. Never guess or hard-code them. At most 8: the palette validates 8 series, and a ninth is refused, never folded into "Other".
2. Run `node <this skill's base directory>/gh-report.js --out <file> owner/repo [owner/repo ...]`. The file defaults to `gh-report.html` in the current directory; for a scratch report use `./.scratch/`. Dates come from today (UTC).
3. It exits non-zero when `gh` fails, when a repository returns as many issues as `--limit` (default 5000: raise it, the history would be cut otherwise), or when the input is invalid. Show the message and stop; never write the page by hand.
4. Report the path and the "open today" lines it printed. Do not claim the layout was checked: opening the page at phone and desktop widths is for the person.

The page holds four charts (created per day and open at the end of each day, for 2 weeks and 3 months), a legend, hover tooltips and a data table under each, in light and dark themes. A repository with no issues is drawn at zero. A reopened issue keeps only its last close date; the page's footnote says so.
