# materializing-tickets

The message that opened this lane started the `to-tickets` skill on the task file. You open the
tickets the owner approved, each in the repository of the project that will dispatch it, and you
draft one Developing task per ticket. Everything below narrows the skill to this pipeline.

## What you are looking at

- `skip_steps` in the task file's frontmatter: if it names `tickets`, change nothing and report a
  pass at once, ignoring the skill's text. Read this first.
- `ticket` in the frontmatter: the spec, the parent of every ticket. Read it live with
  `gh issue view <n> --json state,labels,body,comments`. If it is not open, block.
- `$SPOOLWAY_SCRATCH/breakdown.md`: the breakdown the owner approved in the grill. It is the
  whole list. If it is missing or does not say the owner approved it, block.
- `$SPOOLWAY_SCRATCH/tickets.md`: if it exists you have been here before. Read "When you come
  back" below before anything else.
- `spoolway task contract`, printed by the command: the shape of a task document.
  `.spoolway/templates/tasks/developing.md` is the body a Developing task takes.

## How to do it here

Nobody is at the pane. Skip the skill's quiz: the owner approved the breakdown in the grill.
Never ask a question and never use AskUserQuestion. Publish exactly the tickets of
`breakdown.md`: none added, none merged, none split. If one cannot be published as agreed, block
and say which and why.

Each ticket's section in `breakdown.md` opens with `## <n>. <title>` and a `- repos:` line. The
title and the repositories are the owner's, and you carry both verbatim: the title into the issue
and the draft, the repositories into the draft's `repos`. If a title or a repository of the
breakdown cannot be carried as approved, block, naming the ticket, its approved title and why;
never retitle a ticket or change its repositories yourself. The `drafts` step refuses a draft
whose title or `repos` differs from the breakdown.

1. Open the tickets in dependency order, blockers first. The repository is the project's, as
   the consumer's `docs/agents/projects.md` names it (without that file, this repository's own
   GitHub repository). Use the skill's issue template, with
   the breakdown's title verbatim as the issue's title. Under "Parent" write
   `Part of <the spec's URL>`.
2. Before each `gh issue create`, look for the ticket where a lane that stopped halfway would
   have left it: under the spec (`gh api repos/<owner>/<repo>/issues/<n>/sub_issues`) and in the
   target repository by title (`gh issue list -R <owner>/<repo> --state open --search "<title> in:title"`).
   A title that is already there is that ticket: use it, and open nothing. An issue opened twice
   cannot be taken back by a lane.
3. The moment `gh issue create` answers, before any label or link, append the ticket's line to
   `$SPOOLWAY_SCRATCH/tickets.md`, so that a lane that stops halfway leaves a true record:

       - <the ticket's full URL> | draft: <task id>
       - <the ticket's full URL> | draft: none

   `draft: none` is only for a ticket of a project this queue does not dispatch (see
   `docs/agents/projects.md`): a person drafts that task in its own project. Say so in a handoff
   note, one per ticket.
4. Label each ticket `ready-for-agent` and its category, `bug` or `enhancement`. A label the
   target repository does not have is left off and named in a handoff note; never create a label.
5. Link each ticket with the tracker's own relations, never prose alone. Both take the numeric
   `id` of an issue, which is not its number: `gh api repos/<owner>/<repo>/issues/<n> --jq .id`.
   - sub-issue of the spec:
     `gh api -X POST repos/<spec owner>/<spec repo>/issues/<spec n>/sub_issues -F sub_issue_id=<ticket id>`
   - blocked by another ticket:
     `gh api -X POST repos/<owner>/<repo>/issues/<n>/dependencies/blocked_by -F issue_id=<blocker id>`

   Both work across repositories. If the tracker refuses one, leave the "Blocked by" line of the
   ticket's body as the record and name the refusal in a handoff note.
6. For every other ticket write `$SPOOLWAY_SCRATCH/drafts/<task id>.md`, a Developing task
   document, with this frontmatter and no other key:
   - `id`: lowercase letters, digits and hyphens, starting with a letter, such as
     `t<ticket number>-<two or three words>`. The file is named after it.
   - `title`: the ticket's title in `breakdown.md`, verbatim. The grill checked it as a
     Conventional Commits title. It becomes the commit subject and the pull request title.
   - `group`: one name for the whole set, taken from the spec. `group_description`: one sentence
     saying what the set delivers, on the first document only.
   - `pipeline: developing`.
   - `ticket`: the ticket's full URL.
   - `base`: copied from this Materializing task's own `base:`, the same on every draft. Never
     ask GitHub for a default branch: it can differ from the branch this project lands in.
   - `depends_on`: the ids of the drafts whose tickets block this one, when there are any.
   - `requires`: `<owner>/<repo>#<n>` for a blocker in another project, when there is one.
   - `touches`: glob patterns for the files the ticket expects to change, with the pages under
     the pages directory `.spoolway/companion.env` names whose pins the change moves, when it
     names one.
   - `repos`: the ticket's `- repos:` line in `breakdown.md`, as a list, such as
     `repos: [app, lib]`. A repository beyond this one gets a worktree from the consumer's
     `extra-worktree` step, as `docs/agents/projects.md` says.

   Never `close_on_merge`: that key is for a spec, and a ticket closes when its pull request
   merges. The body keeps every section of the Developing template, filled from the ticket:
   `## Context`, `## Intend`, `## Non-goals`, `## Acceptance criteria`, `## References` and
   `## Left for a person`, with no `[[placeholder]]` left. No line of the body puts close, fix
   or resolve before `#N`: write `part of #N`.
7. Check the set with `spoolway -C "$SPOOLWAY_REPO" task contract --from "$SPOOLWAY_SCRATCH/drafts"`,
   which writes nothing, and correct what it refuses. The helper functions the steps share
   (`frontmatter_value`, `conventional_title`, `issue_url` and the rest) are in
   `scripts/spoolway/lib.sh`, and the supported way to load them is to source that file in your
   own shell: `. scripts/spoolway/lib.sh`. It defines functions and does nothing else.
8. Pass. The next step checks the drafts against the tickets and copies them into `pending/`.
   You never write there, and nothing is queued: a person sends the drafts from the queue screen.

## When you come back

If `tickets.md` already exists, the `drafts` step sent the task back, and the tickets are already
open. Its reasons are in `$SPOOLWAY_SCRATCH/drafts.problems.md`. Correct `tickets.md` and the
documents under `drafts/`, run the contract check again, and pass. A reason about a title or
`repos` is corrected by copying the breakdown's value; if that value cannot be carried, block as
"How to do it here" says. Open no issue, and do not edit, relabel or close the ones that are
open. If a ticket of the breakdown has no line in `tickets.md`, look for it as step 2 says first,
and open it only if it is not there.

## If your report is refused

The command you finish with can itself be refused. Read what it printed, then run it once more
with `-C "$SPOOLWAY_REPO"` right after `spoolway` and the same flags. If that is refused too,
stop: make your last message the refusal and the command you ran, change nothing else and end
your turn. A person reads the pane. Never work around a refusal, and never ask another session
for help.

## Never

- Never open an issue that is not a ticket of `breakdown.md`: no follow-up, no question, no run
  report. The tickets are the only issues this lane opens.
- Never close the spec, edit its body or take a label off it. Never open anything in a
  feedback repository `docs/agents/projects.md` names as private.
- Never write into `pending/`, never run `spoolway queue`, and never queue a draft.
- Never run a step's script: nothing under `scripts/spoolway/` but the sourcing of `lib.sh`, not
  with `--help` and not to read it. The dispatcher runs each one when the task reaches its step,
  and it refuses every other caller. Read a script with a file read.
- Never copy participant feedback, a secret or a credential into a ticket or a draft.
- Never edit a file in the repository. The one pull request of this pipeline holds what the
  `document` step writes and nothing else, and a commit made here would be squashed into it. What
  a file should say goes in a handoff note.
- Never create `docs/adr/` or any other decision directory, and never write under the pages directory.
- Never contact another session: no SendMessage, no ListAgents, no herdr or tmux command, no
  other lane's pane.
- Never touch the queue, and never edit the task file: the report you finish with is the only
  thing that writes to it.
- Never run a deploy, a release or device command, or anything that reads or writes a secret.
- Never leave what a person needs in your scratch space alone: it is deleted when the task ends,
  and a note that only names a file there tells nobody anything. Write the text itself in a
  handoff note; when it is too long, its actionable part and then the file's name.
