#!/usr/bin/env bash
# Prints a JSON array of {package, version, ref, sha, latest} for every extension
# release published upstream but not yet published to Docker Hub, excluding
# anything listed in ignored-releases.txt (see that file for why it exists
# and why it's a manually-curated list rather than a version-comparison rule).
#
# Set REBUILD_NEWEST=true to also include each package's newest release when
# it is already published (see step 3).
#
# Used by .github/workflows/main.yml's `prepare` job, which has no native way
# to trigger off tags in a *different* repo, so it polls instead.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IGNORE_FILE="${SCRIPT_DIR}/ignored-releases.txt"

UPSTREAM_REPO="https://github.com/owncloud/web-extensions.git"
DOCKER_REPO="owncloud/web-extensions"

# 1. List every non-ignored upstream tag matching <package>-v<version>, as
#    "<package>\t<version>\t<tagname>\t<sha>". Every tagged release is a
#    candidate here - there's no "keep only the highest version" reduction,
#    since that can permanently drop a legitimate release (two patch releases
#    in one polling window, or a backport to an older still-maintained line).
UPSTREAM=$(git ls-remote --tags "$UPSTREAM_REPO" | grep -v '\^{}$' | while IFS="$(printf '\t')" read -r sha ref; do
  name="${ref#refs/tags/}"
  if [[ "$name" =~ ^(.+)-v([0-9].*)$ ]] && ! grep -qxF "$name" "$IGNORE_FILE"; then
    printf '%s\t%s\t%s\t%s\n' "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}" "$name" "$sha"
  fi
done)

# 2. List every tag already published under owncloud/web-extensions
#    on Docker Hub (paginated).
EXISTING=""
url="https://hub.docker.com/v2/repositories/${DOCKER_REPO}/tags?page_size=100"
while [ -n "$url" ] && [ "$url" != "null" ]; do
  response=$(curl -sf --retry 5 --retry-delay 5 --retry-all-errors "$url")
  EXISTING="${EXISTING}$(echo "$response" | jq -r '.results[].name')"$'\n'
  url=$(echo "$response" | jq -r '.next')
done

# 3. Diff: keep upstream package-version combos missing from Docker Hub.
#    With REBUILD_NEWEST=true, also keep each package's highest release even if
#    it is already published, so base-image CVE fixes reach published images
#    (the tags are re-pushed over the existing ones). Older releases are never
#    force-rebuilt.
MATRIX=$(printf '%s\n' "$UPSTREAM" | while IFS=$'\t' read -r package version ref sha; do
  [ -z "$package" ] && continue
  dockerTag="${package}-${version}"
  # `latest` is true only for the highest plain-numeric release of the
  # package, so a patch to an older line never takes <package>-latest.
  highest=$(printf '%s\n' "$UPSTREAM" | awk -F'\t' -v p="$package" '$1 == p && $2 ~ /^[0-9]+(\.[0-9]+)*$/ {print $2}' | sort -V | tail -1)
  latest=false
  [ "$version" = "$highest" ] && latest=true
  published=false
  printf '%s\n' "$EXISTING" | grep -qxF "$dockerTag" && published=true
  if [ "$published" = false ] || { [ "${REBUILD_NEWEST:-false}" = true ] && [ "$latest" = true ]; }; then
    jq -n --arg package "$package" --arg version "$version" --arg ref "$ref" --arg sha "$sha" --argjson latest "$latest" \
      '{package: $package, version: $version, ref: $ref, sha: $sha, latest: $latest}'
  fi
done | jq -s -c .)

echo "Pending builds: ${MATRIX}" >&2
echo "${MATRIX}"
