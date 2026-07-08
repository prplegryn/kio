#!/usr/bin/env bash
set -euo pipefail

git init
if ! git config user.email >/dev/null; then
  git config user.email "kio@example.local"
fi
if ! git config user.name >/dev/null; then
  git config user.name "kio builder"
fi
git add .
git commit -m "Initial kio Flutter prototype" || true
