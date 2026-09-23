# IWMI deployment controller

This repository is IWMI's deployment controller for the Manuscript Review Tracker.
It contains no application source. The application source lives in a private IWMI
repository; this controller only ever reads a specific, allowlisted release tag from
it.

This repository is public. Its Actions logs are public. The workflows here are
written to print only stage status (`stage <name>: ok` / `stage <name>: FAIL (exit N)`
and a small, fixed set of failure codes) — never secret values, never source content,
never tool or migration output.

## How promotion works

Promotion is manual: it runs only on `workflow_dispatch`, never on a push, pull
request, or schedule. The single input is a `release_tag`, e.g. `v1.2.0-rc.1`.

A promotion run:

1. Confirms the person who triggered the run is the configured release promoter.
2. Fetches the requested tag from the source repository over SSH, using a read-only
   deploy key held as an **environment** secret (`naga-pilot`, or `controller-dry-run`
   for the dry-run workflow) — no promotion secret is ever stored at the repository
   level, only inside the protected environments that gate these workflows.
3. Verifies the tag against `releases/naga-pilot.json`: the tag must be an allowlisted
   entry, and its tag object, commit, and tree must match the recorded values exactly.
   Only tags listed in that file, pinned this way, can ever be promoted — an
   unlisted tag, or a listed tag whose commit or tree has since changed, is refused.
4. Confirms the deployment configuration (database and hosting credentials) is
   present.
5. Installs dependencies, links and migrates the database, deploys the notification
   worker, and builds and deploys the application.
6. Verifies that the deployed site's public routes respond, and records the tag,
   commit, tree, and deployment URL to the run's job summary.

The `promote` job runs under the protected `naga-pilot` GitHub Environment, which
requires a review before the job is allowed to run. `.github/workflows/dry-run.yml`
is a temporary companion workflow used to rehearse the pipeline (checkout, fetch,
verify, install, build) against a disposable environment before promotion is
enabled for real; it is removed once that rehearsal is complete.

Both workflows share the concurrency group `promote-naga-pilot`. GitHub keeps at
most one pending run per concurrency group, so dispatching either workflow while
another run in that group is already queued replaces the older pending run rather
than queueing behind it. Check the Actions run queue before dispatching.

## Operations note

Reviewers approve only runs whose head commit is the current `main` of this repository.
Re-running an older run does not pick up later fixes: GitHub re-executes that run's
older workflow file and allowlist as they existed at that commit, not the versions on
`main` today. Dispatch a fresh run instead of re-running an old one.

## Adding a release

A release is added to the allowlist by opening a pull request that adds exactly one
entry to `releases/naga-pilot.json`, giving the tag's tag object, commit, and tree
hashes. The entry is reviewed like any other change (see `.github/CODEOWNERS`) before
merge; only entries present on `main` can ever be promoted.

## Tests

```sh
bash tests/run.sh
```

This exercises the verification and fetch scripts against local fixtures; it does
not touch GitHub or any live infrastructure.
