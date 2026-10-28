#!/usr/bin/env bash
# Cuts a release: works out the next semantic version from the conventional commits since the
# last vX.Y.Z tag, writes it to Resources/Info.plist, adds a CHANGELOG.md entry, commits, and
# tags the commit. Nothing is pushed.
#
# Bump rules: a `!` after the type or a "BREAKING CHANGE:" footer is major, `feat` is minor,
# `fix` and `perf` are patch. Other types (docs, chore, refactor, test, ...) don't release.
#
# Usage: scripts/release.sh [--dry-run]
#   --dry-run  print the next version and changelog entry without changing anything
set -euo pipefail

PLIST="Resources/Info.plist"
CHANGELOG="CHANGELOG.md"
COMMIT_PATTERN='^([a-z]+)(\([^)]*\))?(!)?: (.+)$'

fail() {
  echo "error: $*" >&2
  exit 1
}

latest_tag() {
  git describe --tags --abbrev=0 --match 'v[0-9]*.[0-9]*.[0-9]*' 2>/dev/null ||
    fail "no vX.Y.Z tag found. Tag the current release first, for example: git tag -a v1.0.0 -m v1.0.0"
}

# Prints one line per commit since $1: "<level>\t<description>", where level is
# major, minor, patch or none.
classify_commits() {
  local since="$1" hash subject body type bang description level
  while IFS= read -r hash; do
    subject="$(git log -1 --format=%s "$hash")"
    body="$(git log -1 --format=%b "$hash")"
    [[ "$subject" =~ $COMMIT_PATTERN ]] || continue
    type="${BASH_REMATCH[1]}"
    bang="${BASH_REMATCH[3]}"
    description="${BASH_REMATCH[4]}"
    case "$type" in
    feat) level=minor ;;
    fix | perf) level="patch" ;;
    *) level=none ;;
    esac
    if [[ -n "$bang" ]] || grep -q '^BREAKING[ -]CHANGE:' <<<"$body"; then
      level=major
    fi
    printf '%s\t%s\n' "$level" "$description"
  done < <(git rev-list --no-merges --reverse "$since..HEAD")
}

# Prints the highest level among the classified commits on stdin.
highest_level() {
  local highest=none level _
  while IFS=$'\t' read -r level _; do
    case "$level" in
    major) highest=major ;;
    minor) [[ "$highest" == major ]] || highest=minor ;;
    patch) [[ "$highest" != none ]] || highest="patch" ;;
    esac
  done
  echo "$highest"
}

# bump_version 1.4.2 minor -> 1.5.0
bump_version() {
  local major minor patch
  IFS=. read -r major minor patch <<<"$1"
  case "$2" in
  major) echo "$((major + 1)).0.0" ;;
  minor) echo "$major.$((minor + 1)).0" ;;
  patch) echo "$major.$minor.$((patch + 1))" ;;
  *) fail "unknown bump level: $2" ;;
  esac
}

# Prints the changelog section for version $1 from the classified commits on stdin.
changelog_entry() {
  local version="$1" lines heading level
  lines="$(cat)"
  echo "## [$version] - $(date +%Y-%m-%d)"
  for level in major minor patch; do
    case "$level" in
    major) heading="Breaking changes" ;;
    minor) heading="Features" ;;
    patch) heading="Fixes" ;;
    esac
    if grep -q "^$level"$'\t' <<<"$lines"; then
      printf '\n### %s\n\n' "$heading"
      grep "^$level"$'\t' <<<"$lines" | cut -f2- | sed 's/^/- /'
    fi
  done
}

# Inserts the entry on stdin above the first "## [" section, or at the end of the file.
prepend_to_changelog() {
  local entry
  entry="$(cat)"
  [[ -f "$CHANGELOG" ]] || fail "$CHANGELOG not found"
  ENTRY="$entry" awk '
    !done && /^## \[/ { print ENVIRON["ENTRY"]; print ""; done = 1 }
    { print }
    END { if (!done) { print ""; print ENVIRON["ENTRY"] } }
  ' "$CHANGELOG" >"$CHANGELOG.tmp"
  mv "$CHANGELOG.tmp" "$CHANGELOG"
}

check_ready() {
  [[ -z "$(git status --porcelain)" ]] || fail "the working tree has uncommitted changes"
  local branch
  branch="$(git branch --show-current)"
  [[ "$branch" != main ]] ||
    fail "releases go through a PR. Create a branch first: git switch -c chore/NOJIRA-000_release"
}

main() {
  local dry_run=false
  case "${1:-}" in
  "") ;;
  --dry-run) dry_run=true ;;
  *) fail "unknown argument: $1 (usage: scripts/release.sh [--dry-run])" ;;
  esac

  cd "$(git rev-parse --show-toplevel)"
  local tag commits level current version build entry
  tag="$(latest_tag)"
  commits="$(classify_commits "$tag")"
  level="$(highest_level <<<"$commits")"
  [[ "$level" != none ]] || {
    echo "No feat, fix, perf or breaking commits since $tag, so there is nothing to release."
    exit 0
  }

  current="$(plutil -extract CFBundleShortVersionString raw "$PLIST")"
  [[ "v$current" == "$tag" ]] ||
    fail "$PLIST says $current but the latest tag is $tag. Make them match first."
  version="$(bump_version "$current" "$level")"
  entry="$(changelog_entry "$version" <<<"$commits")"

  echo "$tag -> v$version ($level)"
  echo
  echo "$entry"
  [[ "$dry_run" == false ]] || exit 0

  check_ready
  build="$(plutil -extract CFBundleVersion raw "$PLIST")"
  plutil -replace CFBundleShortVersionString -string "$version" "$PLIST"
  plutil -replace CFBundleVersion -string "$((build + 1))" "$PLIST"
  prepend_to_changelog <<<"$entry"
  git add "$PLIST" "$CHANGELOG"
  git commit -q -m "chore(NOJIRA-000): release v$version"
  git tag -a "v$version" -m "v$version"

  echo
  echo "Committed and tagged v$version. Push the branch and the tag, then open a PR:"
  echo "  git push -u origin $(git branch --show-current) && git push origin v$version"
}

main "$@"
