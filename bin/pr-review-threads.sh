#!/usr/bin/env bash
# Fetches PR review threads with resolution status via GitHub GraphQL API.
# Read-only query — no mutations.
#
# Usage: pr-review-threads.sh <owner> <repo> <pr_number>
# Output: Raw JSON from GitHub GraphQL API
# Exit 1 on missing args or API failure.

set -euo pipefail

if [ $# -ne 3 ]; then
  echo "Usage: pr-review-threads.sh <owner> <repo> <pr_number>" >&2
  exit 1
fi

owner="$1"
repo="$2"
pr_number="$3"

if ! [[ "$pr_number" =~ ^[0-9]+$ ]]; then
  echo "Error: pr_number must be a positive integer, got '$pr_number'" >&2
  exit 1
fi

gh api graphql -f query='
{
  repository(owner: "'"$owner"'", name: "'"$repo"'") {
    pullRequest(number: '"$pr_number"') {
      reviewThreads(first: 100) {
        nodes {
          id
          isResolved
          isOutdated
          comments(first: 10) {
            nodes {
              author { login }
              body
              path
              line
              originalLine
              createdAt
            }
          }
        }
      }
    }
  }
}'
