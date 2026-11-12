#!/bin/bash
# Usage: source bin/setup-env.sh
#
# The GitHub token is never stored in this repo. It is taken from, in order:
#   1. GIT_TOKEN already set in the environment
#   2. the file $GIT_TOKEN_FILE (default: ~/.config/argocd-k8s/git-token, chmod 600)
#   3. an interactive prompt

export GIT_REPO="https://github.com/galthran/argocd-k8s.git"
export GIT_USER="galthran"

GIT_TOKEN_FILE="${GIT_TOKEN_FILE:-$HOME/.config/argocd-k8s/git-token}"

if [ -z "${GIT_TOKEN:-}" ] && [ -r "$GIT_TOKEN_FILE" ]; then
  GIT_TOKEN="$(tr -d '[:space:]' < "$GIT_TOKEN_FILE")"
fi

if [ -z "${GIT_TOKEN:-}" ]; then
  read -r -s -p "GitHub token for $GIT_USER: " GIT_TOKEN
  echo
fi

if [ -z "${GIT_TOKEN:-}" ]; then
  echo "setup-env.sh: no GitHub token found (set GIT_TOKEN or create $GIT_TOKEN_FILE)" >&2
  return 1 2>/dev/null || exit 1
fi

export GIT_TOKEN
