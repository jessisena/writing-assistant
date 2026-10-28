#!/usr/bin/env bash
# Tests scripts/release.sh against throwaway git repositories. macOS only (needs plutil).
# Usage: scripts/test_release.sh
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RELEASE="$REPO_DIR/scripts/release.sh"
WORK_DIR="$(mktemp -d)"
FAILURES=0

cleanup() {
  if command -v trash >/dev/null 2>&1; then
    trash "$WORK_DIR"
  fi
}
trap cleanup EXIT

# Creates a repo on branch "work" with Info.plist at $1 and a changelog, tagged v$1.
new_repo() {
  local dir
  dir="$(mktemp -d "$WORK_DIR/repo.XXXXXX")"
  (
    cd "$dir"
    git init -q -b main
    git config user.email test@example.com
    git config user.name Test
    git config commit.gpgsign false
    git config tag.gpgsign false
    mkdir Resources
    cp "$REPO_DIR/Resources/Info.plist" Resources/Info.plist
    plutil -replace CFBundleShortVersionString -string "$1" Resources/Info.plist
    plutil -replace CFBundleVersion -string 1 Resources/Info.plist
    printf '# Changelog\n\n## [%s] - 2026-01-01\n\n- First\n' "$1" >CHANGELOG.md
    git add -A
    git commit -q -m "chore: initial"
    git tag -a "v$1" -m "v$1"
    git switch -q -c work
  )
  echo "$dir"
}

# commit <dir> <message> [body]
commit() {
  git -C "$1" commit -q --allow-empty -m "$2" ${3:+-m "$3"}
}

check() {
  local name="$1" expected="$2" actual="$3"
  if [[ "$actual" == *"$expected"* ]]; then
    echo "ok   $name"
  else
    echo "FAIL $name"
    echo "     expected to contain: $expected"
    echo "     got: $actual"
    FAILURES=$((FAILURES + 1))
  fi
}

# Runs the release script in <dir> with the remaining args; prints output and exit status.
run() {
  local dir="$1" status=0 output
  shift
  output="$(cd "$dir" && "$RELEASE" "$@" 2>&1)" || status=$?
  printf '%s\nexit=%s' "$output" "$status"
}

test_bump_levels() {
  local dir
  dir="$(new_repo 1.0.0)"
  commit "$dir" "docs: readme"
  check "docs only releases nothing" "nothing to release" "$(run "$dir" --dry-run)"
  commit "$dir" "fix(NOJIRA-000): crash on empty input"
  check "fix bumps patch" "v1.0.0 -> v1.0.1 (patch)" "$(run "$dir" --dry-run)"
  commit "$dir" "feat(NOJIRA-000): add chips"
  check "feat bumps minor" "v1.0.0 -> v1.1.0 (minor)" "$(run "$dir" --dry-run)"
  commit "$dir" "refactor(NOJIRA-000)!: drop old format"
  check "bang bumps major" "v1.0.0 -> v2.0.0 (major)" "$(run "$dir" --dry-run)"

  dir="$(new_repo 1.4.2)"
  commit "$dir" "fix: keep data" "BREAKING CHANGE: history moves to a new folder"
  check "breaking footer bumps major" "v1.4.2 -> v2.0.0 (major)" "$(run "$dir" --dry-run)"
  commit "$dir" "not conventional at all"
  check "non-conventional commits are ignored" "v1.4.2 -> v2.0.0" "$(run "$dir" --dry-run)"
}

test_merge_commits_are_ignored() {
  local dir
  dir="$(new_repo 1.0.0)"
  git -C "$dir" switch -q -c topic
  commit "$dir" "docs: notes"
  git -C "$dir" switch -q work
  git -C "$dir" merge -q --no-ff topic -m "feat: merge looks like a feature"
  check "merge commits don't bump" "nothing to release" "$(run "$dir" --dry-run)"
}

test_release_writes_files() {
  local dir output
  dir="$(new_repo 1.0.0)"
  commit "$dir" "feat(NOJIRA-000): add chips"
  commit "$dir" "fix(NOJIRA-000): keep focus"
  output="$(run "$dir")"
  check "release succeeds" "exit=0" "$output"
  check "version written" "1.1.0" \
    "$(plutil -extract CFBundleShortVersionString raw "$dir/Resources/Info.plist")"
  check "build number incremented" "2" \
    "$(plutil -extract CFBundleVersion raw "$dir/Resources/Info.plist")"
  check "tag created" "v1.1.0" "$(git -C "$dir" tag --points-at HEAD)"
  check "release commit" "chore(NOJIRA-000): release v1.1.0" "$(git -C "$dir" log -1 --format=%s)"
  check "changelog entry above the previous one" \
    "$(printf '## [1.1.0] - %s\n\n### Features\n\n- add chips\n\n### Fixes\n\n- keep focus\n\n## [1.0.0]' \
      "$(date +%Y-%m-%d)")" \
    "$(cat "$dir/CHANGELOG.md")"
  check "next run finds nothing new" "nothing to release" "$(run "$dir" --dry-run)"
}

test_refusals() {
  local dir
  dir="$(mktemp -d "$WORK_DIR/untagged.XXXXXX")"
  git -C "$dir" init -q -b main
  git -C "$dir" -c user.email=t@e.com -c user.name=T commit -q --allow-empty -m "feat: x"
  check "no tag fails" "no vX.Y.Z tag found" "$(run "$dir" --dry-run)"

  dir="$(new_repo 1.0.0)"
  commit "$dir" "feat: x"
  git -C "$dir" switch -q main
  git -C "$dir" merge -q --ff-only work
  check "refuses on main" "releases go through a PR" "$(run "$dir")"
  git -C "$dir" switch -q work
  echo dirty >"$dir/dirty.txt"
  check "refuses with uncommitted changes" "uncommitted changes" "$(run "$dir")"
  check "dry run still works when dirty" "v1.0.0 -> v1.1.0" "$(run "$dir" --dry-run)"
  check "unknown argument fails" "unknown argument" "$(run "$dir" --major)"

  dir="$(new_repo 1.0.0)"
  plutil -replace CFBundleShortVersionString -string 1.2.0 "$dir/Resources/Info.plist"
  git -C "$dir" commit -q -am "feat: x"
  check "plist and tag mismatch fails" "Make them match first" "$(run "$dir" --dry-run)"
}

test_bump_levels
test_merge_commits_are_ignored
test_release_writes_files
test_refusals

if ((FAILURES > 0)); then
  echo "$FAILURES test(s) failed" >&2
  exit 1
fi
echo "All release tests passed"
