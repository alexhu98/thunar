#!/bin/bash
# Publishes dist/*.deb as release v<upstream>+local<N> of $VERSION at $GITHUB_SHA.
# Skips a commit that is not newer than the highest +localN tag's, and re-uploads to an existing release.
# DRY_RUN=1 only prints what it would do.
set -euo pipefail

: "${VERSION:?}"
sha=${GITHUB_SHA:-$(git rev-parse HEAD)}
tag="v${VERSION%%-*}+local${VERSION##*+local}"

latest=$(.github/scripts/latest-tag.sh)

if [[ -n $latest ]]; then
  read -r latest_tag latest_sha <<<"$latest"
  status=$(gh api "repos/{owner}/{repo}/compare/${latest_sha}...${sha}" --jq .status)
  case $status in
    ahead) ;;
    identical)
      if [[ $latest_tag != "$tag" ]]; then
        echo "${sha::12} is already released as $latest_tag; not publishing $tag"
        exit 0
      fi ;;
    *)
      echo "${sha::12} is $status relative to $latest_tag; not publishing $tag"
      exit 0 ;;
  esac
fi

if [[ ${DRY_RUN:-0} == 1 ]]; then
  echo "would publish $tag at ${sha::12}"
  exit 0
fi

assets=(dist/thunar_*.deb dist/thunar-data_*.deb dist/libthunarx-3-0_*.deb)
if gh release view "$tag" >/dev/null 2>&1; then
  echo "re-uploading to existing $tag"
  gh release upload "$tag" "${assets[@]}" --clobber
  gh release edit "$tag" --draft=false
else
  gh release create "$tag" "${assets[@]}" \
    --target "$sha" \
    --title "$tag" --notes "Thunar $VERSION, built from ${sha::12}."
fi
