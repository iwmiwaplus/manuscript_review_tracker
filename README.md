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

Each run is titled `Promote Naga pilot <tag> by @<actor>` (`run-name`), so the tag
and the person who dispatched it are visible in the run list and on the approval
screen.

A promotion run:

1. **Preflight (before approval, no secrets).** An un-gated `preflight` job with
   read-only permissions runs `scripts/check-run.sh` and the allowlist lookup, then
   writes the tag, commit and tree it is about to promote to the job summary for the
   reviewer. It stops a run unless:
   - the dispatcher is the configured release promoter (`RELEASE_PROMOTER`, both
     actor and triggering actor);
   - it is a fresh dispatch (`GITHUB_RUN_ATTEMPT` is 1) and its head commit is the
     current `main` of this repository, read anonymously — a re-run would replay an
     older workflow file and allowlist, so it is refused (`stale-run`);
   - the tag is well-formed and listed in `releases/naga-pilot.json`.
   A branch name, raw SHA or unlisted tag never reaches approval.
2. **Gated job.** After approval the `promote` job repeats `check-run.sh` itself (a
   "re-run failed jobs" reuses preflight's old result) and never reads preflight's
   outputs.
3. Fetches the tag from the source repository over SSH with a read-only deploy key.
   `scripts/fetch-source.sh` repeats the allowlist lookup before writing the key.
4. Verifies the tag against `releases/naga-pilot.json`: tag object, commit and tree
   must match the recorded values exactly, and the commit must be on source `main`.
5. Confirms the six environment secrets are present.
6. **Tools before the database.** Sets up Node.js, installs the Vercel CLI from this
   repository's own lockfile (`tools/`, `npm ci --ignore-scripts` with an empty user
   npm config), checks `vercel --version`, installs a second copy for the deploy step
   into the runner's temp directory (`deploy-tools`, fresh npm cache, not run before
   Deploy), and records the tool digest (below). No application or install-script code
   runs and no secret is in these steps. After the database is migrated no tool is
   downloaded again; the remaining network steps are the application install, the
   Vercel configuration pull, the deploy and the route checks.
7. **Database before any application code.** Installs the Supabase CLI release binary
   (version-pinned and checked against a recorded sha256), links, previews and applies
   migrations, deploys the notification worker, then deletes the link state. The
   application's dependencies are not installed yet, so no application code can run
   while a Supabase credential is in use.
8. Installs the application with `npm ci --ignore-scripts`, pulls the Vercel
   configuration, builds (no token in the build step), re-checks the tools and deploys.
9. Verifies that the deployed site's public routes respond and records tag, commit and
   tree to the job summary.

**Tool integrity around the build.** `vercel build` runs application and dependency
code as the same user before the deploy step uses the Vercel token. So: (a) right after
the tools are installed, before the application is, the system `sha256sum` hashes
`scripts/tool-digest.sh`, and that script hashes this checkout, the Node.js installation
and the `deploy-tools` copy (excluding `.git` and `tools/node_modules`); both values are
kept as step outputs, which the runner holds; (b) the build step then
empties its `GITHUB_ENV`, `GITHUB_PATH`, `GITHUB_OUTPUT` and step-summary files, so
nothing the build wrote there reaches later steps; (c) `Verify tools` fails with
`tool-integrity` if `BASH_ENV`, `ENV`, `LD_PRELOAD`, `LD_LIBRARY_PATH` or `NODE_OPTIONS`
is set, or if the digest script's sha256 (checked with the system `sha256sum` before the
script runs) or the recomputed digest differs — all local, no network; (d) the deploy
step uses the `deploy-tools` copy (installed before the database steps from
`tools/package-lock.json`, sha512-verified, fresh npm cache, empty user npm config) with
a fresh, empty Vercel global config directory (the token still comes from
`VERCEL_TOKEN`). Residual boundary: a
process started by build-time code that keeps running into the Deploy step (same uid,
same VM) can still observe that step's environment or race the checks; this cannot be
removed without moving deploy to a separate job/VM, which would need the build output
transferred via artifacts (excluded: public repo) — accepted residual; mitigated by a
Vercel token scoped to the pilot team/project and short-lived. GitHub-hosted runners
also grant the job passwordless sudo, so build-time code can alter any file on the VM,
including system tools; the in-job checks defend against accidental or untargeted
tampering only and do not stop a targeted attacker.

Secrets live only in the protected `naga-pilot` environment, never at repository
level, and each is passed only to the step that
needs it, by environment variable, never on a command line. Besides
`SOURCE_DEPLOY_KEY`, `naga-pilot` holds six deployment secrets:
`PILOT_SUPABASE_ACCESS_TOKEN`, `PILOT_SUPABASE_DB_PASSWORD`, `PILOT_SUPABASE_PROJECT_REF`,
`PILOT_VERCEL_TOKEN`, `PILOT_VERCEL_ORG_ID`, `PILOT_VERCEL_PROJECT_ID` (the Vercel IDs
are secrets so they are masked in the public log). The `promote` job requires a review before it runs.

Promotion runs use the concurrency group `promote-naga-pilot`. GitHub keeps at
most one pending run per concurrency group, so dispatching while another run is
already queued replaces the older pending run rather
than queueing behind it. Check the Actions run queue before dispatching. To retry a
failed run, dispatch a new one from `main`; re-runs are refused.

## Adding a release

A release is added to the allowlist by opening a pull request that adds exactly one
entry to `releases/naga-pilot.json`, giving the tag's tag object, commit, and tree
hashes. The entry is reviewed like any other change (see `.github/CODEOWNERS`) before
merge; only entries present on `main` can ever be promoted.

## Tests

```sh
bash tests/run.sh
```

This exercises the verification, fetch, run-check and log scripts against local fixtures; it does
not touch GitHub or any live infrastructure.
