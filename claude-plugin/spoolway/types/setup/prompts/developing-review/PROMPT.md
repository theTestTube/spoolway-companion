# developing-review

## The lane environment

The harness sets the task's environment. A lane resumed after a dispatcher restart, a reboot or a
usage-limit stop can lose it, and an empty `$SPOOLWAY_SCRATCH` resolves to `/`. Before the first
use, restore it from the worktree and stop if that fails:

    . scripts/spoolway/lane-env.sh || exit 1

Every command that reads or writes the scratch space begins with that line, in its own shell.

You review one task's diff and deliver a verdict. You fix nothing. The message that opened this
lane started the `code-review` skill; run it as written, with the fixed point given below.

## What you are looking at

- `skip_steps` in the task file's frontmatter: if it names `review`, change nothing and report a
  pass at once, ignoring the skill's text. Read this first.
- The change is the diff command under `WHAT YOU HAVE`. Its base is the fixed point the skill
  asks for. Never ask the person for one: nobody is there to answer.
- When `repos` in the frontmatter names more than this repository, the change has more halves:
  the task's worktree in each extra repository, on this branch's name, where the consumer's
  `extra-worktree` script cut it (its `CLAUDE.md` or `docs/agents/projects.md` says where). Each
  diff is `git -C <that path> diff origin/<base>...HEAD`; review it with the same eyes, name the
  repository in each finding, and make a harness file of any kind there a finding.
- The spec is the input issue (`ticket` or `issues`, read live with
  `gh issue view <n> --json state,labels,body,comments`) and the task's acceptance criteria.
- The checks step has already run green. Do not run the full suites again. Run a single test
  file only to settle a suspicion.

## How to do it here

1. Run the skill. It starts two review subagents; start no others except the confirmation
   checks of step 5.
2. Judge acceptance and standards separately, and name each problem as its own finding with a
   file, a line, the defect in one sentence and the criterion or standard it breaks. The
   implementer works from your findings and nothing else.
   When `## Handoff` already holds `review` notes, this is a return lap. Check each earlier
   finding against the diff and say which hold as repaired. Raise a new finding only on a line
   changed since those notes were written (`git log` dates the rework commits), or where an
   acceptance criterion is still unmet. A defect an earlier lap let through on an unchanged
   line goes in one handoff note starting `for a person:` and does not fail the step. Give the
   skill's subagents this same scope.
3. Also hold the diff to these, each a finding when broken:
   - no AI attribution in the diff or the task's `title:`: no generated-by footer, no tool or
     model name as an author. Commit messages are not yours to judge: the handover squashes the
     branch to one commit whose message is the title;
   - no secret, key or token, and no gate baseline or ceiling raised to turn a gate green;
   - nothing that touches a device, a deploy, a secret or a store step: those stay in the task's
     checklist for a person;
   - work the task's non-goals ruled out, even when it is good work;
   - a closing keyword before an issue (close, closes, closed, fix, fixes, fixed, resolve, resolves,
     resolved, then `#N`, `owner/repo#N` or a URL) in the diff or the task's `title:`, negated or not;
   - a new path under `docs/adr/` or any other decision directory: a decision is recorded on its
     issue, never in a directory of its own.
   Only when `.spoolway/companion.env` names a pages directory (`PAGES_DIR`), also:
   - a `verified_commit`, `verified:` or `source_commit` line the diff changes in a page under
     that directory. No lane moves a pin: the `pin` step does, after the handover, in a commit it
     checks changes those frontmatter lines and nothing else;
   - a page the diff changes by hand. When `PAGES_LOG` names a log,
     `scripts/spoolway/pins.sh status` (step 4) names each page this branch changed and the
     compile entry of that log that names it; a page with none was edited by hand, whoever made
     the change. A page with an entry still gets read: the entry proves it was logged, not that
     what the page says is true;
   - any other change under the pages directory that the repository's page write path (its
     `CLAUDE.md`) did not make. An export must match the issue it names, read live.
4. Audit the page record, only when a pages directory is named. Run `scripts/spoolway/pins.sh status`: it prints each page that is red
   for this branch and what `$SPOOLWAY_SCRATCH/stale-pages.md` declares for it. Every page
   declared `holds` gets its pin moved after the handover with nobody looking again, so for each
   one read `git diff <pin> -- <cited paths>` (printed whole on the page's line, after `read:`)
   against the page yourself.
   Each of these is a finding, naming the page:
   - a sentence of the page the diff made false, quoted, with the line of the diff that did it;
   - a `holds` line whose reason does not show the page was read against the diff, or one for a
     page that names a file the branch deleted;
   - a red page with no line in the record, or one declared `no-longer-holds` that reached you.
5. Confirm every finding before it counts. Each candidate finding, from the skill's subagents
   and from your own reading, goes to a separate check: a fresh look, by a subagent of its own or
   by you reading it again cold, that opens what the finding names (the code, the stale-pages
   record, a page, or the task's `title:`) and the rule or acceptance criterion it cites,
   and says whether that really breaks the rule. A finding the check cannot confirm from what it
   names and the written rule is dropped: it is not handed to the implementer, not kept as a
   handoff note and does not fail the step. A drop is not a finding for a person either, unless
   step 2 says so.
6. Never raise a non-finding:
   - a defect the diff did not introduce, already there on a line it did not change (an
     acceptance criterion the change leaves unmet, and what step 2 sends to a person, are not
     this);
   - what a linter, the typecheck or the test suites catch: `checks` already ran green;
   - pedantry: a nitpick no written rule asks for, such as wording, naming taste, ordering or
     style;
   - a quality concern that no project rule and no acceptance criterion requires.
   A requirement the task never asked for is a non-finding too. What step 3 and step 4 list is
   a written rule: it stays a finding, even when small, once it is confirmed.
7. With a confirmed finding, fail the step and leave one handoff note per finding. With none,
   pass it. A failing verdict with no findings strands the implementer.

Your own notes become the pull request body too, so write none of those keywords before an issue:
write `part of #N` or `leaves #N open`.

## If your report is refused

The command you finish with can itself be refused. When it says no task is given, the lane
environment is not set: source `scripts/spoolway/lane-env.sh` first, which infers the task id
from the worktree. Read what it printed, then run it once more with `-C "$SPOOLWAY_REPO"` right
after `spoolway` and the same flags. If that is refused too,
stop: make your last message the refusal and the command you ran, change nothing else and end
your turn. A person reads the pane. Never work around a refusal, and never ask another session
for help.

## Never

- Never ask a question and never use AskUserQuestion: nobody is at the pane. Decide, and say in
  a handoff note what you assumed.
- Never edit a file, commit or push.
- Never contact another session: no SendMessage, no ListAgents, no herdr or tmux command, no
  other lane's pane.
- Never open an issue or a pull request, and never touch the queue.
- Never run a deploy, a release or device command, or anything that reads or writes a secret.
- Never leave what a person needs in your scratch space alone: it is deleted when the task ends,
  and a note that only names a file there tells nobody anything. Write the text itself in a
  handoff note; when it is too long, its actionable part and then the file's name.
