# spoolway-companion

The pipeline types, hooks and skills a repository takes to run coding agents through spoolway,
generic to any one project.

## Companion

**Consumer**:
A repository that takes the companion's types and fills in its extension points.
_Avoid_: client, host project

**Types**:
The pipelines, prompts, templates and shared step scripts the companion writes into a consumer,
listed path by path in its manifest.
_Avoid_: templates (those are copied once and owned by the consumer)

**Extension point**:
A named behaviour a pipeline calls and the consumer provides: a script of fixed name, a
`companion.env` key or a catalogue entry.
_Avoid_: hook, plugin point

**Pipeline**:
An ordered set of steps a task runs through: Developing, Materializing, Architecting or
Feeding-back.

**Run**:
One pass of a task through its pipeline, identified by a run id; a task queued again starts a new
run.

## Repositories

**Repository**:
A hosted repository, named `[HOST/]OWNER/REPO`, never a path or a URL.
_Avoid_: repo, project

**Checkout**:
A local directory holding a repository, a worktree included; named by its path.
_Avoid_: repository, clone

**Run repository**:
The repository whose checkout a run works in, the one its task was queued for.
_Avoid_: home repo, main repo, own repo

**Extra repository**:
A repository other than the run repository that a multi-repo task also changes, named in its
`repos`.
_Avoid_: sibling repo, secondary repo

## Run reports

**Run report**:
An issue a run files when a signal crosses its threshold, or when a lane names an urgent finding;
at most one per run.
_Avoid_: retro issue, incident

**Signal**:
An objective measure of a run, compared with a threshold the pipeline sets.
_Avoid_: metric, smell

**Repaired-lap run**:
A run that arrived at `implement` more than once and passed the final `review`, so every later lap
repaired the finding the return was for. It is not a spent loop: it raises no arrivals signal,
and its spend is not compared with the median, which the extra laps inflate.
_Avoid_: return run, rework run

**Verdict**:
What measuring a run's signals leaves: the body of the run report to file, or nothing.

**Report repository**:
The repository run reports are filed in and read from: the one the consumer names, else the run
repository, never an extra repository.
_Avoid_: target repo, tracker repo, run-report repo

**Intake**:
The Feeding-back step that reads the open run reports of the report repository.

## Spoolway updates

**As-Is**:
The spoolway release installed on the machine, read from `spoolway --version`.

**To-Be**:
The spoolway release an update moves to: the one the person names, else the latest.

**Gap**:
Everything a consumer holds that the To-Be changes, found by running the To-Be against it.

**Probe**:
A hash-checked copy of the To-Be binary kept under `./.scratch/`, never installed, that the review
of a gap runs against the consumer.
