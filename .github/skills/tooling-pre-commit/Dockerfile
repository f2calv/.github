# syntax=docker/dockerfile:1
# Local, single-platform pre-commit fallback with Python, Node, and Git.
# The skill builds this image only when native pre-commit is unavailable.

# ------------------------------------------------------------------------------
# Stage 1 of 2: build
#
# Supplies the Node 22 runtime required by the pinned markdownlint hook.
# ------------------------------------------------------------------------------
FROM --platform=$BUILDPLATFORM node:22-bookworm-slim AS build

# ------------------------------------------------------------------------------
# Stage 2 of 2: final
#
# Python owns pre-commit; Node and Git support hook environments.
# ------------------------------------------------------------------------------
FROM python:3.12-slim AS final
WORKDIR /src
COPY --from=build /usr/local/ /usr/local/
ARG PRE_COMMIT_VERSION=4.6.2
RUN <<EOF
set -eux
apt-get update
apt-get install -y --no-install-recommends git
rm -rf /var/lib/apt/lists/*
pip install --no-cache-dir "pre-commit==${PRE_COMMIT_VERSION}"
EOF
COPY scripts/docker-entrypoint.sh /usr/local/bin/pre-commit-entrypoint
RUN chmod 0755 /usr/local/bin/pre-commit-entrypoint
LABEL org.opencontainers.image.title="pre-commit runner" \
    org.opencontainers.image.description="Pinned local fallback for repository pre-commit hooks" \
    org.opencontainers.image.source="https://github.com/f2calv/.github"
ENTRYPOINT ["pre-commit-entrypoint"]
