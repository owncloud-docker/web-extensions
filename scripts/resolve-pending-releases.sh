#!/usr/bin/env bash
# Prints a JSON array of {package, version, ref, sha} for every extension
# release published upstream but not yet published to Docker Hub. Tracks only
# the newest version per extension - it does not backfill history.
#
# Used by .github/workflows/main.yml's `prepare` job, which has no native way
# to trigger off tags in a *different* repo, so it polls instead.
set -euo pipefail

UPSTREAM_REPO="https://github.com/owncloud/web-extensions.git"
DOCKER_REPO="owncloud/web-extensions"

# 1. List every upstream tag matching <package>-v<version>, as
#    "<package>\t<version>\t<tagname>\t<sha>".
ALL_TAGS=$(git ls-remote --tags "$UPSTREAM_REPO" | grep -v '\^{}$' | while IFS="$(printf '\t')" read -r sha ref; do
  name="${ref#refs/tags/}"
  if [[ "$name" =~ ^(.+)-v([0-9].*)$ ]]; then
    printf '%s\t%s\t%s\t%s\n' "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}" "$name" "$sha"
  fi
done)

# 2. Keep only the highest version per package (this repo tracks the
#    newest release per extension, it does not backfill history).
UPSTREAM=$(printf '%s\n' "$ALL_TAGS" | sort -t "$(printf '\t')" -k1,1 -k2,2V | awk -F'\t' '{last[$1]=$0} END {for (p in last) print last[p]}')

# 3. List every tag already published under owncloud/web-extensions
#    on Docker Hub (paginated).
EXISTING=""
url="https://hub.docker.com/v2/repositories/${DOCKER_REPO}/tags?page_size=100"
while [ -n "$url" ] && [ "$url" != "null" ]; do
  response=$(curl -sf --retry 5 --retry-delay 5 --retry-all-errors "$url")
  EXISTING="${EXISTING}$(echo "$response" | jq -r '.results[].name')"$'\n'
  url=$(echo "$response" | jq -r '.next')
done

# 4. Diff: keep upstream package-version combos missing from Docker Hub.
MATRIX=$(printf '%s\n' "$UPSTREAM" | while IFS=$'\t' read -r package version ref sha; do
  [ -z "$package" ] && continue
  dockerTag="${package}-${version}"
  if ! printf '%s\n' "$EXISTING" | grep -qxF "$dockerTag"; then
    jq -n --arg package "$package" --arg version "$version" --arg ref "$ref" --arg sha "$sha" \
      '{package: $package, version: $version, ref: $ref, sha: $sha}'
  fi
done | jq -s -c .)

echo "Pending builds: ${MATRIX}" >&2
echo "${MATRIX}"
