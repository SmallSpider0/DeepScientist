#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
REMOTE="${DEEPSCIENTIST_UPDATE_REMOTE:-origin}"
REQUESTED_BRANCH="${DEEPSCIENTIST_UPDATE_BRANCH:-}"

print_step() {
  printf '[update] %s\n' "$1"
}

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 1
  fi
}

resolve_base_dir() {
  if [ -n "${DEEPSCIENTIST_BASE_DIR:-}" ]; then
    printf '%s\n' "$DEEPSCIENTIST_BASE_DIR"
    return
  fi
  if [ -n "${DEEPSCIENTIST_HOME:-}" ]; then
    printf '%s\n' "$DEEPSCIENTIST_HOME"
    return
  fi

  local repo_name repo_parent source_sibling
  repo_name="$(basename "$REPO_ROOT")"
  repo_parent="$(dirname "$REPO_ROOT")"
  if [[ "$repo_name" == *-source ]]; then
    source_sibling="${repo_name%-source}"
    printf '%s\n' "$repo_parent/$source_sibling"
    return
  fi

  printf '%s\n' "$HOME/DeepScientist"
}

resolve_bin_dir() {
  if [ -n "${DEEPSCIENTIST_BIN_DIR:-}" ]; then
    printf '%s\n' "$DEEPSCIENTIST_BIN_DIR"
    return
  fi

  # Source checkouts should not discover an unrelated global/npm wrapper via
  # `command -v ds`. Keep the local source launcher beside the runtime home by
  # default so it always points back at this checkout.
  printf '%s\n' "$BASE_DIR/bin"
}

resolve_update_branch() {
  if [ -n "$REQUESTED_BRANCH" ]; then
    printf '%s\n' "$REQUESTED_BRANCH"
    return
  fi

  local current_branch remote_head
  current_branch="$(git branch --show-current 2>/dev/null || true)"
  if [ -n "$current_branch" ]; then
    printf '%s\n' "$current_branch"
    return
  fi

  remote_head="$(git symbolic-ref --quiet --short "refs/remotes/$REMOTE/HEAD" 2>/dev/null || true)"
  if [ -n "$remote_head" ]; then
    printf '%s\n' "${remote_head#"$REMOTE/"}"
    return
  fi

  printf '%s\n' "main"
}

write_source_wrapper() {
  local target_path="$1"
  local command_name="$2"
  cat >"$target_path" <<EOF_WRAPPER
#!/usr/bin/env bash
set -euo pipefail
if [ -z "\${DEEPSCIENTIST_HOME:-}" ]; then
  export DEEPSCIENTIST_HOME="$BASE_DIR"
fi
if [ -z "\${DEEPSCIENTIST_REPO_ROOT:-}" ] || [ ! -f "\${DEEPSCIENTIST_REPO_ROOT}/bin/ds.js" ]; then
  export DEEPSCIENTIST_REPO_ROOT="$REPO_ROOT"
fi
NODE_BIN="\${DEEPSCIENTIST_NODE:-node}"
exec "\$NODE_BIN" "\$DEEPSCIENTIST_REPO_ROOT/bin/ds.js" "\$@"
EOF_WRAPPER
  chmod +x "$target_path"
}

write_source_wrappers() {
  mkdir -p "$BIN_DIR"
  write_source_wrapper "$BIN_DIR/ds" "ds"
  write_source_wrapper "$BIN_DIR/ds-cli" "ds-cli"
  write_source_wrapper "$BIN_DIR/research" "research"
  write_source_wrapper "$BIN_DIR/resear" "resear"
}

require_command git
require_command node
require_command npm

cd "$REPO_ROOT"

if [ ! -d .git ]; then
  echo "This script must run from a DeepScientist git checkout." >&2
  exit 1
fi

BASE_DIR="$(resolve_base_dir)"
BIN_DIR="$(resolve_bin_dir)"
BRANCH="$(resolve_update_branch)"

if [ -n "$(git status --porcelain)" ]; then
  print_step "Local changes detected; git will autostash tracked edits during pull"
fi

print_step "Fetching latest source from $REMOTE/$BRANCH"
git fetch "$REMOTE" "$BRANCH"

print_step "Fast-forwarding checkout"
# Older Git builds reject `git pull --ff-only --autostash` unless rebase is used.
# We already fetched above, so perform the fast-forward merge directly.
git merge --ff-only "$REMOTE/$BRANCH"

print_step "Installing latest source checkout"
DEEPSCIENTIST_BASE_DIR="$BASE_DIR" \
DEEPSCIENTIST_BIN_DIR="$BIN_DIR" \
  bash "$REPO_ROOT/install.sh" "$@"

print_step "Rewriting local launcher wrappers to use the source checkout"
write_source_wrappers

print_step "Done"
printf 'DeepScientist source repo: %s\n' "$REPO_ROOT"
printf 'DeepScientist source command: %s/ds\n' "$BIN_DIR"
