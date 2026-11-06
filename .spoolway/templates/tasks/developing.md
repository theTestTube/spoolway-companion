## Context

Three to five facts, one line each. The plan that produced this task is not something a lane can
read, so this is where its ground goes: what the code does today, the decision this task
implements, and the constraint that makes the obvious approach wrong. Facts and names, not
argument.

- [[what is true today that this task changes]]
- [[the decision it implements, in one line]]
- [[the constraint that would otherwise be discovered the hard way]]
- [[what this task waits on in another project, the value of `requires:` in the frontmatter; delete the line when it waits on nothing]]

## Intend

[[What this task achieves, in a sentence or two, for someone who has not read the issue.]]

## Non-goals

Out of scope. Doing any of these is a review failure, not a bonus.

- [[the adjacent thing this task must not do]]
- anything not required by the acceptance criteria below

## Risks

What could go wrong with this change, and what this task does about each. Drop
this heading if the task carries none.

- [[what could go wrong]]
  Mitigation: [[what this task does about it]]

## Acceptance criteria

- [[a statement that is checkably true or false the moment the task is done]]

## References

Read these before you start. A path here replaces a paragraph above.

- the input issue, named by `ticket:` in the frontmatter, read live
- [[path — why it matters]]

## Left for a person

A lane never attempts these. They stay open until a person has done each one; what the change
needs in particular is listed under `## Handoff` below. Delete a line only when it cannot apply.

- [ ] Merge order, when the task names extra repositories: theirs merge first, then this one's
- [ ] Device checks, when the change reaches the UI or native code
- [ ] Updating the plugin install in the lane's worktree, when the task moves a plugin pin (set `gate_at` to the step that moves it)
- [ ] Deploys of any stage, when the change needs one
- [ ] Secrets and credentials, when the change needs one set or rotated
- [ ] Release steps: build, submit, store track
- [ ] Merge order, when the frontmatter carries `requires:`: merge this only after what it names
