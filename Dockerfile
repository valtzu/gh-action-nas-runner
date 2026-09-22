# Self-hosted GitHub Actions runner for a small x86-64 NAS (QNAP HS-264 under
# Container Station). Same Ubuntu as the hosted `ubuntu-26.04` image, so the
# tools below come in the same versions as there.
FROM ubuntu:26.04

ARG RUNNER_VERSION=2.337.0
ARG RUNNER_SHA256=70920811a4f8ad4328818682bca5c6469c1c942fab52448868071d0063816613

ENV DEBIAN_FRONTEND=noninteractive

# The runner's own (.NET) dependencies, then the build tools jobs expect:
#   build-essential, pkg-config    compilers and linkers (cargo links with cc)
#   git                            actions/checkout
#   zstd                           actions/cache compresses with it when present;
#                                  without it the cache keys differ from the hosted runs'
#   mtools, e2fsprogs, fdisk       disk images without root: FAT, ext4, partition tables
#   openssl, python3               signing and scripting
#   qemu-user                      running binaries built for other architectures
# No sudo: apt steps in workflows must be skipped on this runner.
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      ca-certificates curl libicu78 libssl3t64 libgssapi-krb5-2 zlib1g \
      build-essential pkg-config git zstd xz-utils \
      mtools e2fsprogs fdisk openssl python3 qemu-user \
 && rm -rf /var/lib/apt/lists/*

# Only the tarball goes in the image: entrypoint.sh unpacks it into the volume,
# where the runner can update itself in place.
RUN curl -fsSL -o /opt/actions-runner.tar.gz \
      "https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz" \
 && echo "${RUNNER_SHA256}  /opt/actions-runner.tar.gz" | sha256sum -c -

# 1001 like the hosted runner's user; the image's own `ubuntu` user has 1000.
RUN useradd --create-home --uid 1001 --shell /bin/bash runner

# The mount point of the cache the runners share (compose.yaml). It is in the
# image, and owned by the runner, so that Docker gives a freshly created volume
# those permissions: the runner has no root and cannot chown it afterwards.
RUN mkdir /cache && chown runner:runner /cache

# dtolnay/rust-toolchain installs rustup into $CARGO_HOME when it is missing,
# and both live on the volume, so a toolchain is downloaded once.
ENV CARGO_HOME=/home/runner/.cargo \
    RUSTUP_HOME=/home/runner/.rustup \
    PATH=/home/runner/.cargo/bin:$PATH

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod 755 /usr/local/bin/entrypoint.sh

USER runner
WORKDIR /home/runner
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
