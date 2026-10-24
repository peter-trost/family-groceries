#!/usr/bin/env bash
# Lands a PR on main as one commit authored with the required noreply email.
# GitHub's squash merge authors the commit with the account's default email
# and rejects the noreply address as --author-email, so the squash happens
# here and the single commit is rebase-merged, which keeps its author.
#
# Usage: scripts/merge-pr.sh <pr-number>
#   1st run: if the PR is not yet one well-formed commit, squashes it,
#            force-pushes the PR branch and exits 2 (wait for ci-ok, rerun).
#   2nd run: checks ci-ok on the head and rebase-merges it.
set -euo pipefail
source "$(dirname "$0")/lib.sh"

PR="${1:?usage: scripts/merge-pr.sh <pr-number>}"
AUTHOR_NAME="petertrost-bot"
AUTHOR_EMAIL="341616691+petertrost-bot@users.noreply.github.com"
# COMMON.md: every commit message ends with Peter's trailer.
PETER_TRAILER='Co-authored-by: Peter Trost <peter@petertrost.com>'
TRAILERS=$'Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>\n'"$PETER_TRAILER"

cd "$REPO_ROOT"
branch="$(gh pr view "$PR" --json headRefName -q .headRefName)"
head="$(gh pr view "$PR" --json headRefOid -q .headRefOid)"
title="$(gh pr view "$PR" --json title -q .title)"
subject="$title (#$PR)"
git fetch -q origin main "$branch"

commits="$(git rev-list --count "origin/main..$head")"
author="$(git log -1 --format=%ae "$head")"
actual_subject="$(git log -1 --format=%s "$head")"
last_line="$(git log -1 --format=%B "$head" | sed '/^$/d' | tail -n 1)"
if [[ "$(git merge-base origin/main "$head")" != "$(git rev-parse origin/main)" ]]; then
  echo "$branch is behind main; rebase it first" >&2
  exit 1
fi
if [[ "$commits" != 1 || "$author" != "$AUTHOR_EMAIL" || "$actual_subject" != "$subject" || "$last_line" != "$PETER_TRAILER" ]]; then
  log "squashing $branch into one commit: $subject"
  body="$(git log --reverse --format='%b' "origin/main..$head" | grep -v -e '^Co-authored-by:' -e '^Co-Authored-By:' | sed '/./,$!d')"
  tree="$(git rev-parse "$head^{tree}")"
  squashed="$(printf '%s\n\n%s\n\n%s\n' "$subject" "$body" "$TRAILERS" | sed '/^$/N;/^\n$/D' \
    | GIT_AUTHOR_NAME="$AUTHOR_NAME" GIT_AUTHOR_EMAIL="$AUTHOR_EMAIL" \
      GIT_COMMITTER_NAME="$AUTHOR_NAME" GIT_COMMITTER_EMAIL="$AUTHOR_EMAIL" \
      git commit-tree "$tree" -p origin/main)"
  git push -q --force-with-lease="$branch:$head" origin "$squashed:refs/heads/$branch"
  log "pushed $squashed; rerun once ci-ok passes on it"
  exit 2
fi

ci_ok="$(gh pr checks "$PR" --json name,bucket -q '.[] | select(.name=="ci-ok") | .bucket')"
if [[ "$ci_ok" != "pass" ]]; then
  echo "ci-ok is '${ci_ok:-pending or missing}' on $head; not merging" >&2
  exit 1
fi
gh pr merge "$PR" --rebase --match-head-commit "$head"
log "merged #$PR as $head ($AUTHOR_EMAIL)"
