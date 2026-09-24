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

Every runner also mounts one shared volume at `/cache`; see
[The shared cache](#the-shared-cache).

## Setup

The stack is driven from a workstation, through a Docker context that talks to
Container Station's Docker engine over TLS. Compose reads `compose.yaml` and
`.env` from your clone of this repository; the image, the volumes and the
containers are all on the NAS, and nothing has to be copied there.

1. In Container Station, download the Docker TLS certificate: a zip with
   `ca.pem`, `cert.pem` and `key.pem`. The server certificate has to list the
   host name you connect with. Regenerating it with that name also issues a new
   CA and client certificate, so download the zip after that.
2. Create the context. Docker copies the three files into its own context
   store, so the zip and the extracted files can be deleted afterwards:

   ```bash
   docker context create nas --docker "host=tcp://NAS_HOST:2376,ca=$PWD/ca.pem,cert=$PWD/cert.pem,key=$PWD/key.pem"
   ```

3. In your clone of this repository, write a `.env` with the repository to
   serve and a registration token (valid for one hour, registers every runner):

   ```bash
   printf 'URL=https://github.com/OWNER/REPO\nRUNNER_TOKEN=%s\n' "$(gh api -X POST repos/OWNER/REPO/actions/runners/registration-token --jq .token)" > .env
   ```

   or for organization:

   ```bash
   printf 'URL=https://github.com/ORG\nRUNNER_TOKEN=%s\nRUNNER_GROUP=YourRunnerGroupName\n' "$(gh api -X POST orgs/ORG/actions/runners/registration-token --jq .token)" > .env
   ```

4. Start the stack:

   ```bash
   docker --context nas compose up -d
   ```

5. Once `nas-large-1`, `nas-large-2` and `nas-small-1` to `nas-small-6` show
   as Idle under the repository's Settings > Actions > Runners, empty
   `RUNNER_TOKEN` in `.env` and run `docker --context nas compose up -d` again.
   That recreates the containers without the token; the volumes, and with them
   the registrations, stay.

`export DOCKER_CONTEXT=nas` saves typing `--context nas` in a shell that only
talks to the NAS.

Without a workstation, the same works over SSH on the NAS: put `compose.yaml`,
`seccomp.json` and `.env` in a directory there and run `docker compose up -d`
in it. The
registration token is also shown under Settings > Actions > Runners > New
self-hosted runner, in the `config.sh` command.

## The registration token

It is the only secret, and it is never in this repository or the image: it
lives in `.env` (ignored by git), `config.sh` reads it once, and the
entrypoint unsets it before the runner starts, so no job sees it. It expires
after an hour. From then on each runner authenticates with its own key, kept
on its volume.

## The seccomp profile

QNAP's 5.10 kernel answers `fchmodat2`, a system call from Linux 6.6, with
EFAULT where an older kernel says ENOSYS. glibc 2.39 and later changes a
symlink's mode through it and only falls back on ENOSYS, so in these
containers GNU tar would fail on every symlink it extracts ("Cannot change
mode to rwxr-xr-x: Bad address"), `actions/cache` restores included.
`seccomp.json` is Docker's default profile with that one call answered ENOSYS
before it reaches the kernel. `make-seccomp.py` writes it from the engine's own
default; rerun it with `MOBY_REF` bumped when Container Station's Docker
changes version.

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

## The shared cache

Every runner mounts the same volume at `/cache`, so a job can hand a file to a
later job in another pool directly, without the Actions cache service. That
matters here: the NAS is behind a domestic uplink, so a build's output goes to
the cloud once and comes back once per consuming job, and a few hundred
megabytes fanned out over ten jobs is enough for the restores to fail with
"The operation cannot be completed in timeout."

Name the directory through a repository variable too, so the same workflow
still works on hosted runners, where the jobs share nothing and the cache
service is the only way across:

```yaml
      - uses: actions/cache/save@v6
        if: vars.RUNNER_CACHE == ''
        with: { key: build-${{ github.run_id }}, path: out/ }
      - name: Save to the shared cache
        if: vars.RUNNER_CACHE != ''
        run: tar -cf "${{ vars.RUNNER_CACHE }}/build-$GITHUB_RUN_ID.tar" out/
```

```bash
gh variable set RUNNER_CACHE --body /cache -R OWNER/REPO
```

Set it only when every pool the workflow names runs on this host: a job on a
hosted runner cannot see `/cache`, and the fallback is chosen per workflow, not
per job.

Nothing prunes `/cache`. A workflow that writes there deletes its own files
when the run ends — and, because a cancelled run never gets that far, should
also drop what an earlier run left behind, e.g. `find /cache -maxdepth 1 -name
'build-*.tar' -mtime +1 -delete`.

## Maintenance

- Update to the latest image:
  `docker --context nas compose pull && docker --context nas compose up -d`.
- Build it yourself instead:
  `docker build -t ghcr.io/valtzu/gh-action-nas-runner:latest .`
- Removing a runner: delete it under Settings > Actions > Runners, then
  `docker --context nas compose down -v`.
- What the shared cache holds: `docker --context nas run --rm -v
  gh-action-nas-runner_cache:/cache ghcr.io/valtzu/gh-action-nas-runner ls -l
  /cache`.

## Security

A job can run anything as the `runner` user inside its container. The
containers mount nothing from the NAS, have no Docker socket, and drop all
capabilities. They do share `/cache`, so a job can read and overwrite what
another job put there — one more reason for the rule below. Only register them to private repositories: on a public one,
anyone who can open a pull request can run code here.

The context's client certificate is full control over the NAS's Docker engine,
which amounts to root on the NAS: keep it on machines you trust.
