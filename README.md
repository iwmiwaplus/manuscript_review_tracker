# IWMI Deployment Controller

Promotes accepted releases of the Manuscript Review Tracker to the Naga pilot.

This repository contains no application source. It reads one allow-listed, pinned release tag from the private
source repository and deploys exactly that tag.

**Target:** Naga pilot (production)\
**Trigger:** manual only\
**Organization:** IWMI

---

## Principles

- **Manual only.** Runs start from `workflow_dispatch`, never from a push, pull request or schedule.
- **Allow-listed and pinned.** A tag deploys only if [`releases/naga-pilot.json`](releases/naga-pilot.json) lists it,
  and its tag object, commit and tree match exactly. The commit must also be on the source repository's `main`.
- **Human approval.** The `promote` job runs in the protected `naga-pilot` environment and waits for a reviewer.
- **Fresh runs only.** A run must be a first attempt whose head commit is the current `main`. Re-runs are refused
  (`stale-run`), because they would replay an older workflow file and allow-list.
- **Public logs, no secrets.** This repository and its Actions logs are public. Steps print only
  `stage <name>: ok` or `stage <name>: FAIL (exit N)`, plus a small, fixed set of failure codes. They never print
  secret values, source, or tool or migration output.
- **Environment-scoped secrets.** Every secret lives in `naga-pilot`, never at repository level. Each is passed only
  to the step that needs it, as an environment variable, never on a command line.

## How a promotion runs

The only input is `release_tag`, e.g. `v1.2.0-rc.1`. Each run is titled `Promote Naga pilot <tag> by @<actor>`.

| # | Stage | What happens |
| --- | --- | --- |
| 1 | Preflight (no secrets, before approval) | `check-run.sh` confirms the dispatcher is the release promoter, the run is fresh and on current `main`, and the tag is listed. The tag, commit and tree go to the job summary for the reviewer. |
| 2 | Approval | A reviewer approves the `promote` job in `naga-pilot`. |
| 3 | Re-check | `promote` repeats `check-run.sh` itself and never trusts preflight's outputs. |
| 4 | Fetch and verify | The tag is fetched over SSH with a read-only deploy key and verified against the allow-list. |
| 5 | Tools | The Vercel CLI is installed from this repository's own lockfile (`tools/`), and its digest is recorded before any application code exists. |
| 6 | Database | The pinned, checksum-verified Supabase CLI links, previews and applies migrations, and deploys the notification worker. No application code is installed yet. |
| 7 | Application | `npm ci --ignore-scripts`, Vercel configuration pull, build (with no token), tool re-check, then deploy. |
| 8 | Identify and check | `deploy-identity.sh` fails closed unless the deploy produced exactly one `READY` production deployment. Then the public routes are checked, and the tag, commit, tree and deployment id are recorded. |

Runs share the concurrency group `promote-naga-pilot`. GitHub keeps at most one pending run per group, so a new
dispatch replaces an older pending one. Check the run queue before dispatching.

## Secrets (`naga-pilot` environment)

| Secret | Used for |
| --- | --- |
| `SOURCE_DEPLOY_KEY` | Read-only SSH access to the source tag |
| `PILOT_SUPABASE_ACCESS_TOKEN`, `PILOT_SUPABASE_DB_PASSWORD`, `PILOT_SUPABASE_PROJECT_REF` | Migrations and the notification worker |
| `PILOT_VERCEL_TOKEN`, `PILOT_VERCEL_ORG_ID`, `PILOT_VERCEL_PROJECT_ID` | The application deploy. The IDs are secrets so they are masked in the public log. |

## Security notes

`vercel build` runs application and dependency code as the same user, before the deploy step uses the Vercel token.
The workflow guards against this:
- The build cannot pass anything to later steps; its `GITHUB_ENV`, `GITHUB_PATH`, `GITHUB_OUTPUT` and summary files
  are emptied.
- `Verify tools` fails with `tool-integrity` if a loader or preload variable is set, or if the tool digest changed.
- Deploy runs from a separate, pre-installed copy of the CLI with an empty global configuration.

**Accepted residual risk.** A process started during the build could keep running into the deploy step on the same
VM. Hosted runners also grant passwordless sudo. The in-job checks stop accidental or untargeted tampering, not a
targeted attacker. This is mitigated by a short-lived Vercel token. Removing it entirely would need a separate
deploy job fed by build artifacts, which a public repository rules out.

## Adding a release

Open a pull request that adds exactly one entry to [`releases/naga-pilot.json`](releases/naga-pilot.json), with the
tag's `tag_object`, `commit` and `tree`. It is reviewed under [`CODEOWNERS`](.github/CODEOWNERS). Only entries on
`main` can be promoted.

## Layout

| Path | Contents |
| --- | --- |
| `.github/workflows/promote-naga-pilot.yml` | The promotion workflow |
| `releases/` | The release allow-list |
| `scripts/` | Run checks, source fetch, release verification, deploy identity, tool digest, quiet stage runner, pinned SSH host keys |
| `tools/` | The lockfile for the pinned Vercel CLI |
| `tests/` | Offline tests for the scripts |

## Tests

```sh
bash tests/run.sh
```

This runs the verification, fetch, run-check and log scripts against local fixtures. It touches neither GitHub nor
live infrastructure.
