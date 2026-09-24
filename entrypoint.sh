#!/bin/sh
# Unpack the runner into the persistent home on first start, register it once,
# then run it. The runner updates itself in place, so it has to live on the
# volume rather than in the image.
set -eu

dir="$HOME/actions-runner"
if [ ! -d "$dir" ]; then
  # Into a scratch directory first, so an unpack that fails halfway is redone
  # on the next start instead of being taken for a runner.
  rm -rf "$dir.new"
  mkdir "$dir.new"
  tar -xzf /opt/actions-runner.tar.gz -C "$dir.new"
  mv "$dir.new" "$dir"
fi
cd "$dir"

if [ ! -f .runner ]; then
  : "${URL:?set URL}"
  : "${RUNNER_TOKEN:?the first start needs RUNNER_TOKEN, see README.md}"
  set -- --unattended --replace \
    --url "$URL" \
    --token "$RUNNER_TOKEN" \
    --name "${RUNNER_NAME:-$(hostname)}" \
    --labels "${RUNNER_LABELS:-nas}" \
    --work _work
  if [ -n "${RUNNER_GROUP:-}" ]; then
    set -- "$@" --runnergroup "$RUNNER_GROUP"
  fi
  ./config.sh "$@"
fi

# The token is only for config.sh; keep it out of every job's environment.
unset RUNNER_TOKEN
exec ./run.sh
