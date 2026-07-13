#!/usr/bin/env bash
#
# gather_context.sh — deterministic context bundle for the pr-review skill.
#
# Usage:  gather_context.sh <PR-number-or-URL>
#
# Fetches, via the GitHub REST API (gh api — avoids the GraphQL
# project-card deprecation that breaks `gh issue view`), a single
# human-readable bundle containing:
#   - PR metadata (title, author, base/head, state, files, +/- counts)
#   - the file-by-file change list
#   - any linked issue(s) (parsed from "closes/resolves/fixes #N" in the
#     PR body and commit messages) with their full body text
#   - the complete PR diff
#
# The bundle is written to a temp file and the path is printed to stdout
# (so the caller can pass it to the reviewer subagent). All network
# failures degrade to an inline "(failed to fetch …)" note rather than
# aborting, so a partial bundle is still usable.

set -uo pipefail

if [ "$#" -lt 1 ] || [ -z "${1:-}" ]; then
  echo "usage: gather_context.sh <PR-number-or-URL>" >&2
  exit 2
fi

PR_ARG="$1"
# Resolve to a bare integer: strip URL/path prefixes, leading '#'.
PR_NUM="$(printf '%s' "$PR_ARG" \
  | sed -E 's@^.*/pull/([0-9]+).*@\1@; s/^#//; s/[^0-9]//g')"
if [ -z "$PR_NUM" ]; then
  echo "could not parse a PR number from: $PR_ARG" >&2
  exit 2
fi

# Resolve the "owner/repo" slug. Prefer gh, fall back to the origin remote.
REPO="$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null || true)"
if [ -z "$REPO" ]; then
  REPO="$(git remote get-url origin 2>/dev/null \
    | sed -E 's@.*github.com[:/]([^/]+/[^./]+).*@\1@' || true)"
fi
if [ -z "$REPO" ]; then
  echo "could not determine the GitHub repository (not in a repo / no origin)" >&2
  exit 1
fi

OUT="$(mktemp)"
trap 'rm -f "$OUT"' EXIT

api() { gh api "$@" 2>/dev/null || echo "(failed to fetch: gh api $*)"; }

{
  echo "# pr-review context bundle"
  echo
  echo "Repository: $REPO    PR: #$PR_NUM"
  echo
  echo "## PR metadata"
  api "repos/$REPO/pulls/$PR_NUM" --jq \
    '"**Title:** \(.title)\n**Author:** \(.user.login)\n**Base:** \(.base.ref)  ←  **Head:** \(.head.ref)\n**State:** \(.state) (merged: \(.merged_at // false))\n**Files changed:** \(.changed_files)  (+\(.additions)/-\(.deletions))  commits: \(.commits)\n\n**Body:**\n\(.body // "(no PR body)")"'
  echo
  echo "## Changed files"
  api "repos/$REPO/pulls/$PR_NUM/files" --jq \
    '.[] | "- [\(.status)] \(.filename)  (+\(.additions)/-\(.deletions))"' \
    | head -200
  echo

  # Linked issues: scan PR body + every commit message for the
  # closing-keyword pattern, dedupe, and fetch each issue's body.
  echo "## Linked issues"
  LINKED="$(
    {
      api "repos/$REPO/pulls/$PR_NUM" --jq '.body // ""'
      api "repos/$REPO/pulls/$PR_NUM/commits" --jq '.[].commit.message // ""'
    } | grep -oiE '(close[sd]?|resolve[sd]?|fix(es|ed)?|implement(s|ed)?|reference[sd]?|see)[[:space:]]+#[0-9]+' \
      | grep -oE '#[0-9]+' | tr -d '#' | sort -nu || true
  )"
  if [ -z "$LINKED" ]; then
    echo "(no linked issues detected in the PR body or commit messages)"
  else
    for i in $LINKED; do
      echo
      echo "### Issue #$i"
      api "repos/$REPO/issues/$i" --jq \
        '"**\(.title)**  (state: \(.state))\n\n\(.body // "(no issue body)")"'
    done
  fi
  echo

  echo "## Diff"
  gh pr diff "$PR_NUM" 2>/dev/null || echo "(failed to fetch diff)"
} > "$OUT"

# Print the path only (caller captures it); keep the bundle on disk
# so the subagent can read it. Caller is responsible for removing it.
echo "$OUT"
trap - EXIT