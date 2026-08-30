#!/usr/bin/env bash
# Next free rubocop/rubocop PR number, for the changelog entry.
# GitHub numbers issues and PRs in one sequence, so the next number is
# one past the highest existing of either.
set -euo pipefail

latest=$(gh api 'repos/rubocop/rubocop/issues?state=all&per_page=1' --jq '.[0].number' 2>/dev/null) ||
  latest=$(curl -sf 'https://api.github.com/repos/rubocop/rubocop/issues?state=all&per_page=1' |
    ruby -rjson -e 'puts JSON.parse($stdin.read)[0]["number"]')

echo $((latest + 1))
