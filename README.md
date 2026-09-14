# gh-action-nas-runner

Self-hosted GitHub Actions runners for a QNAP HS-264 NAS (Celeron N5105,
4 cores, 8 GB), in Docker under Container Station. Self-hosted minutes don't
count against the Actions quota.

The image, `ghcr.io/valtzu/gh-action-nas-runner`, is `ubuntu:26.04` with the
runner and a set of build tools (see the `Dockerfile`). It is the same Ubuntu
as the hosted `ubuntu-26.04` runners, so the tool versions match theirs.
`.github/workflows/publish.yml` builds it on every push to `main`, and weekly
for security fixes. Each runner keeps its registration, the runner itself
(which updates in place) and anything installed under its home directory, such
as a Rust toolchain, on its own volume.

`compose.yaml` runs two pools, told apart by label:

| label | runners | limits | for |
|---|---|---|---|
| `nas-large` | 2 | 3 CPUs, 3 GB | compile-heavy jobs |
| `nas-small` | 6 | 1 CPU, 1 GB | single-threaded, low-memory jobs |

## Setup

1. Put `compose.yaml` on the NAS, e.g. in `/share/Container/gh-action-nas-runner`.
2. Next to it, write a `.env` with the repository to serve and a registration
   token (valid for one hour, registers every runner):

   ```bash
   printf 'REPO_URL=https://github.com/OWNER/REPO\nRUNNER_TOKEN=%s\n' "$(gh api -X POST repos/OWNER/REPO/actions/runners/registration-token --jq .token)" > .env
   ```

3. Over SSH on the NAS, in that directory:

   ```bash
   docker compose up -d
   ```

4. Once `nas-large-1`, `nas-large-2` and `nas-small-1` to `nas-small-6` show
   as Idle under the repository's Settings > Actions > Runners, empty
   `RUNNER_TOKEN` in `.env` and run `docker compose up -d` again. That
   recreates the containers without the token; the volumes, and with them the
   registrations, stay.

## The registration token

It is the only secret, and it is never in this repository or the image: it
lives in `.env` on the NAS (ignored by git), `config.sh` reads it once, and the
entrypoint unsets it before the runner starts, so no job sees it. It expires
after an hour. From then on each runner authenticates with its own key, kept
on its volume.

## Workflow side

Actions schedules by label only: a job goes to any idle runner that has every
label in its `runs-on`. Naming the pool through a repository variable keeps
the hosted runners as the fallback, for as long as the variable is unset:

```yaml
jobs:
  build:
    runs-on: ${{ vars.RUNNER_LARGE || 'ubuntu-latest' }}
  check:
    runs-on: ${{ vars.RUNNER_SMALL || 'ubuntu-latest' }}
```

```bash
gh variable set RUNNER_LARGE --body nas-large -R OWNER/REPO
```

The image has no sudo, so `apt-get install` steps need
`if: runner.environment == 'github-hosted'`, and the packages they install
belong in the `Dockerfile`.

## Maintenance

- Update to the latest image: `docker compose pull && docker compose up -d`.
- Build it yourself instead:
  `docker build -t ghcr.io/valtzu/gh-action-nas-runner:latest .`
- Removing a runner: delete it under Settings > Actions > Runners, then
  `docker compose down -v`.

## Security

A job can run anything as the `runner` user inside its container. The
containers mount nothing from the NAS, have no Docker socket, and drop all
capabilities. Only register them to private repositories: on a public one,
anyone who can open a pull request can run code here.
