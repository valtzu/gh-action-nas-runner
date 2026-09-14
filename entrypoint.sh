#!/bin/sh
# Unpack the runner into the persistent home on first start, register it once,
# then run it. The runner updates itself in place, so it has to live on the
# volume rather than in the image.
set -eu

dir="$HOME/actions-runner"
if [ ! -x "$dir/run.sh" ]; then
  mkdir -p "$dir"
  tar -xzf /opt/actions-runner.tar.gz -C "$dir"
fi
cd "$dir"

if [ ! -f .runner ]; then
  : "${REPO_URL:?set REPO_URL}"
  : "${RUNNER_TOKEN:?the first start needs RUNNER_TOKEN, see README.md}"
  ./config.sh --unattended --replace \
    --url "$REPO_URL" \
    --token "$RUNNER_TOKEN" \
    --name "${RUNNER_NAME:-$(hostname)}" \
    --labels "${RUNNER_LABELS:-nas}" \
    --work _work
fi

# The token is only for config.sh; keep it out of every job's environment.
unset RUNNER_TOKEN
exec ./run.sh
