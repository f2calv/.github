#!/usr/bin/env sh
set -eu

git config --global --add safe.directory /src
exec pre-commit "$@"
