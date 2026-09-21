#!/bin/sh
set -euo pipefail

usage() {
  echo "Usage: github-signed-commit.sh -r OWNER/REPO -b BRANCH -m MESSAGE" >&2
  echo "" >&2
  echo "Creates a signed commit via GitHub API from staged changes." >&2
  echo "Requires GH_TOKEN or /github-token/token to be available." >&2
  exit 1
}

BRANCH=""
MESSAGE=""
REPO=""

while getopts "r:b:m:" opt; do
  case "$opt" in
    r) REPO="$OPTARG" ;;
    b) BRANCH="$OPTARG" ;;
    m) MESSAGE="$OPTARG" ;;
    *) usage ;;
  esac
done

[ -z "$REPO" ] || [ -z "$MESSAGE" ] && usage

# GH_HOST is set when the caller goes through the in-cluster GitHub gateway
# (home-cluster #1038). The Pod then holds no GitHub credential at all: the
# token below is a caller key the gateway checks and swaps for the real
# installation token. `gh` switches to GHES layout for any GH_HOST, so the
# REST base is /api/v3 on that host — mirror it so this script and `gh`
# always talk to the same place. Without GH_HOST nothing changes.
if [ -n "${GH_HOST:-}" ]; then
  API="https://${GH_HOST}/api/v3"
  GH_TOKEN="${GH_TOKEN:-${GH_ENTERPRISE_TOKEN:-}}"
else
  API="https://api.github.com"
  if [ -z "${GH_TOKEN:-}" ] && [ -f /github-token/token ]; then
    GH_TOKEN=$(cat /github-token/token)
    export GH_TOKEN
  fi
fi

if [ -z "${GH_TOKEN:-}" ]; then
  echo "Error: No GitHub token available" >&2
  exit 1
fi

AUTH="Authorization: Bearer ${GH_TOKEN}"
ACCEPT="Accept: application/vnd.github+json"

if [ -z "$BRANCH" ]; then
  BRANCH=$(git rev-parse --abbrev-ref HEAD)
fi

HEAD_SHA=$(curl -sf -H "$AUTH" -H "$ACCEPT" \
  "$API/repos/$REPO/git/ref/heads/$BRANCH" | jq -r '.object.sha')

BASE_TREE=$(curl -sf -H "$AUTH" -H "$ACCEPT" \
  "$API/repos/$REPO/git/commits/$HEAD_SHA" | jq -r '.tree.sha')

TREE_ITEMS="[]"

for file in $(git diff --cached --diff-filter=d --name-only); do
  if git diff --cached --summary "$file" | grep -q 'mode change.*100755'; then
    MODE="100755"
  elif test -x "$file"; then
    MODE="100755"
  else
    MODE="100644"
  fi

  CONTENT=$(base64 < "$file" | tr -d '\n')
  BLOB_SHA=$(curl -sf -X POST -H "$AUTH" -H "$ACCEPT" \
    -d "{\"content\":\"$CONTENT\",\"encoding\":\"base64\"}" \
    "$API/repos/$REPO/git/blobs" | jq -r '.sha')

  TREE_ITEMS=$(printf '%s' "$TREE_ITEMS" | jq \
    --arg path "$file" --arg sha "$BLOB_SHA" --arg mode "$MODE" \
    '. + [{"path": $path, "mode": $mode, "type": "blob", "sha": $sha}]')
done

for file in $(git diff --cached --diff-filter=D --name-only); do
  TREE_ITEMS=$(printf '%s' "$TREE_ITEMS" | jq \
    --arg path "$file" \
    '. + [{"path": $path, "mode": "100644", "type": "blob", "sha": null}]')
done

if [ "$TREE_ITEMS" = "[]" ]; then
  echo "Error: No staged changes to commit" >&2
  exit 1
fi

TREE_SHA=$(curl -sf -X POST -H "$AUTH" -H "$ACCEPT" \
  -d "{\"base_tree\":\"$BASE_TREE\",\"tree\":$TREE_ITEMS}" \
  "$API/repos/$REPO/git/trees" | jq -r '.sha')

COMMIT_SHA=$(curl -sf -X POST -H "$AUTH" -H "$ACCEPT" \
  -d "{\"message\":$(printf '%s' "$MESSAGE" | jq -Rs .),\"tree\":\"$TREE_SHA\",\"parents\":[\"$HEAD_SHA\"]}" \
  "$API/repos/$REPO/git/commits" | jq -r '.sha')

# `git/refs/` (plural), not `git/ref/`. The singular form is the read-only
# endpoint — a PATCH to it returns 404, which `curl -sf` turns into exit 22
# with nothing on stderr, so the commit is built and then silently discarded.
curl -sf -X PATCH -H "$AUTH" -H "$ACCEPT" \
  -d "{\"sha\":\"$COMMIT_SHA\"}" \
  "$API/repos/$REPO/git/refs/heads/$BRANCH" > /dev/null

echo "Signed commit created: $COMMIT_SHA"

git fetch origin "$BRANCH"
git reset --hard "origin/$BRANCH"
