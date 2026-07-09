# Reproducible base image for running the APIOps pipeline locally.
# Bakes in pinned versions of every tool the pipeline uses, so demos are identical
# regardless of the host. Multi-arch: installs native binaries for amd64 and arm64
# (so it runs natively on Apple Silicon — no QEMU, no dependency on the repo's
# bundled custom-deck-linux-amd64).
FROM node:20-bookworm-slim

ARG DECK_VERSION=1.49.1
ARG YQ_VERSION=v4.44.3

RUN apt-get update && apt-get install -y --no-install-recommends \
      curl ca-certificates jq git \
    && rm -rf /var/lib/apt/lists/*

# Per-arch binaries: deck + yq
RUN set -eux; \
    arch="$(dpkg --print-architecture)"; \
    case "$arch" in \
      amd64) DARCH=amd64 ;; \
      arm64) DARCH=arm64 ;; \
      *) echo "unsupported arch: $arch" >&2; exit 1 ;; \
    esac; \
    curl -fsSL "https://github.com/kong/deck/releases/download/v${DECK_VERSION}/deck_${DECK_VERSION}_linux_${DARCH}.tar.gz" -o /tmp/deck.tgz; \
    tar -xzf /tmp/deck.tgz -C /usr/local/bin deck; \
    chmod +x /usr/local/bin/deck; \
    curl -fsSL "https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}/yq_linux_${DARCH}" -o /usr/local/bin/yq; \
    chmod +x /usr/local/bin/yq; \
    rm -f /tmp/deck.tgz

# oasdiff — REQUIRED for the breaking-change gate. Fail the build if it can't be installed.
# The install script may drop the binary in CWD; move it onto PATH, then verify.
RUN set -eux; \
    curl -fsSL https://raw.githubusercontent.com/oasdiff/oasdiff/main/install.sh | sh; \
    if [ -x ./oasdiff ]; then mv ./oasdiff /usr/local/bin/oasdiff; fi; \
    command -v oasdiff; \
    oasdiff --version

# Node CLIs
RUN npm i -g @redocly/cli@latest @stoplight/spectral-cli@latest

WORKDIR /work
ENTRYPOINT ["bash"]
