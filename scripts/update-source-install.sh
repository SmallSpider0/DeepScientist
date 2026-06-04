#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
REMOTE="${DEEPSCIENTIST_UPDATE_REMOTE:-origin}"
BRANCH="${DEEPSCIENTIST_UPDATE_BRANCH:-main}"

print_step() {
  printf '[update] %s\n' "$1"
}

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 1
  fi
}

resolve_bin_dir() {
  if [ -n "${DEEPSCIENTIST_BIN_DIR:-}" ]; then
    printf '%s\n' "$DEEPSCIENTIST_BIN_DIR"
    return
  fi

  local existing_ds=""
  existing_ds="$(command -v ds 2>/dev/null || true)"
  if [ -n "$existing_ds" ]; then
    dirname "$existing_ds"
    return
  fi

  printf '%s\n' "$HOME/.local/bin"
}

require_command git
require_command node
require_command npm

cd "$REPO_ROOT"

if [ ! -d .git ]; then
  echo "This script must run from a DeepScientist git checkout." >&2
  exit 1
fi

if [ -n "$(git status --porcelain)" ]; then
  print_step "Local changes detected; git will autostash tracked edits during pull"
fi

BIN_DIR="$(resolve_bin_dir)"

print_step "Fetching latest source from $REMOTE/$BRANCH"
git fetch "$REMOTE" "$BRANCH"

print_step "Fast-forwarding checkout"
# Older Git builds reject `git pull --ff-only --autostash` unless rebase is used.
# We already fetched above, so perform the fast-forward merge directly.
git merge --ff-only "$REMOTE/$BRANCH"

print_step "Installing latest source checkout"
bash "$REPO_ROOT/install.sh" --bin-dir "$BIN_DIR" "$@"

print_step "Done"
printf 'DeepScientist command: %s/ds\n' "$BIN_DIR"
