---
name: gh-report
description: Use when the user asks for a GitHub issue report or issue charts across several repositories. Takes a list of repos (owner/repo, or a bare name with a default owner) and writes one HTML page of line charts (created and open issues, last 2 weeks and last 3 months), one series per repository.
---

# gh-report

Read-only: the script only calls `gh issue list`, `gh repo view` and `gh api user`; it writes nothing to GitHub.

1. Get the repositories from the person, as `owner/repo` or as a bare name. Never guess or hard-code them. A bare name takes `--owner`, else `$GH_REPORT_OWNER`, else the login `gh` is authenticated as; say which owner was used. At most 8 repositories: the palette validates 8 series, and a ninth is refused, never folded into "Other".
2. Run `node <this skill's base directory>/gh-report.js [--owner OWNER] [--out FILE] repo [repo ...]`. The file defaults to `./.scratch/gh-report.html` (the directory is created); pass `--out` to name it. Dates come from today (UTC).
3. It exits non-zero when a repository does not exist, when `gh` fails, when a repository returns as many issues as `--limit` (default 5000: raise it, the history would be cut otherwise), or when the input is invalid. Show the message and stop; never write the page by hand.
4. Report the path and the "open today" lines it printed. Do not claim the layout was checked: opening the page at phone and desktop widths is for the person.

The page holds four charts (created per day and open at the end of each day, for 2 weeks and 3 months), a legend, hover tooltips and a data table under each, in light and dark themes. A repository with no issues is drawn at zero. A reopened issue keeps only its last close date; the page's footnote says so.
