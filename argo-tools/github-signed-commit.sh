#!/bin/sh
set -euo pipefail

usage() {
  echo "Usage: github-signed-commit.sh -r OWNER/REPO -b BRANCH -m MESSAGE" >&2
  echo "" >&2
  echo "Creates a signed commit via GitHub API from staged changes." >&2
  echo "Requires gh to be authenticated (GH_TOKEN, GH_ENTERPRISE_TOKEN, or" >&2
  echo "/github-token/token)." >&2
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

if [ -z "${GH_TOKEN:-}" ] && [ -z "${GH_ENTERPRISE_TOKEN:-}" ] && [ -f /github-token/token ]; then
  GH_TOKEN=$(cat /github-token/token)
  export GH_TOKEN
fi

# Every call goes through `gh api`, not curl. `gh` already decides the base
# URL (api.github.com, or /api/v3 on GH_HOST), which token to send, and the
# header form — so a caller that routes GitHub through a gateway by setting
# GH_HOST (home-cluster #1038) needs nothing from this script, and one that
# still holds a token sees no change.

if [ -z "$BRANCH" ]; then
  BRANCH=$(git rev-parse --abbrev-ref HEAD)
fi

# A branch cut locally does not exist on GitHub yet, and a caller that
# cannot push has no other way to make it exist. Create the ref at the
# commit the working tree was cloned from — the remote default branch,
# which GitHub knows. An existing ref is only read, so the parent below
# still guards against overwriting someone else's commits.
if ! HEAD_SHA=$(gh api "repos/$REPO/git/ref/heads/$BRANCH" --jq '.object.sha' 2>/dev/null); then
  HEAD_SHA=$(git rev-parse --verify origin/HEAD)
  gh api -X POST "repos/$REPO/git/refs" \
    -f "ref=refs/heads/$BRANCH" -f "sha=$HEAD_SHA" > /dev/null
fi
BASE_TREE=$(gh api "repos/$REPO/git/commits/$HEAD_SHA" --jq '.tree.sha')

# File contents and the tree list go through files, not jq arguments: one
# argument is capped at 128 KiB (MAX_ARG_STRLEN), so a larger file or a long
# tree list would fail with "Argument list too long".
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM
echo '[]' > "$WORK/tree.json"

for file in $(git diff --cached --diff-filter=d --name-only); do
  if git diff --cached --summary "$file" | grep -q 'mode change.*100755'; then
    MODE="100755"
  elif test -x "$file"; then
    MODE="100755"
  else
    MODE="100644"
  fi

  base64 < "$file" | tr -d '\n' > "$WORK/blob.b64"
  BLOB_SHA=$(jq -n --rawfile c "$WORK/blob.b64" \
      '{content: $c, encoding: "base64"}' \
    | gh api -X POST "repos/$REPO/git/blobs" --input - --jq '.sha')

  jq --arg path "$file" --arg sha "$BLOB_SHA" --arg mode "$MODE" \
    '. + [{"path": $path, "mode": $mode, "type": "blob", "sha": $sha}]' \
    "$WORK/tree.json" > "$WORK/tree.next"
  mv "$WORK/tree.next" "$WORK/tree.json"
done

for file in $(git diff --cached --diff-filter=D --name-only); do
  jq --arg path "$file" \
    '. + [{"path": $path, "mode": "100644", "type": "blob", "sha": null}]' \
    "$WORK/tree.json" > "$WORK/tree.next"
  mv "$WORK/tree.next" "$WORK/tree.json"
done

if [ "$(jq length "$WORK/tree.json")" -eq 0 ]; then
  echo "Error: No staged changes to commit" >&2
  exit 1
fi

TREE_SHA=$(jq -n --arg base "$BASE_TREE" --slurpfile tree "$WORK/tree.json" \
    '{base_tree: $base, tree: $tree[0]}' \
  | gh api -X POST "repos/$REPO/git/trees" --input - --jq '.sha')

COMMIT_SHA=$(jq -n --arg msg "$MESSAGE" --arg tree "$TREE_SHA" --arg parent "$HEAD_SHA" \
    '{message: $msg, tree: $tree, parents: [$parent]}' \
  | gh api -X POST "repos/$REPO/git/commits" --input - --jq '.sha')

# `git/refs/` (plural), not `git/ref/`. The singular form is the read-only
# endpoint — a PATCH to it returns 404, so the commit is built and then
# discarded.
jq -n --arg sha "$COMMIT_SHA" '{sha: $sha}' \
  | gh api -X PATCH "repos/$REPO/git/refs/heads/$BRANCH" --input - > /dev/null

echo "Signed commit created: $COMMIT_SHA"

git fetch origin "$BRANCH"
git reset --hard "origin/$BRANCH"
