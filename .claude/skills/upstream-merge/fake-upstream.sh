#!/bin/bash
# Usage: fake-upstream.sh DIR — makes DIR a bare repo holding main's release tag and a fake next release tag.
set -euo pipefail

dir=${1:?usage: fake-upstream.sh DIR}
UPSTREAM=${UPSTREAM:-https://gitlab.xfce.org/xfce/thunar.git}

have=$(git show origin/main:configure.ac | sed -n 's/^XDT_VERSION_INIT(\[\([0-9.]*\)\].*/\1/p')
[[ $have =~ ^([0-9]+\.[0-9]+)\.([0-9]+)$ ]] || { echo "fake-upstream: no XDT_VERSION_INIT in origin/main:configure.ac" >&2; exit 1; }
next=${BASH_REMATCH[1]}.$((BASH_REMATCH[2] + 1))
old=thunar-$have
tag=thunar-$next

git fetch -q --no-tags "$UPSTREAM" "refs/tags/$old:refs/upstream-tags/$old"
[[ ! -e $dir || ( -f $dir/HEAD && -d $dir/objects ) ]] || { echo "fake-upstream: $dir exists and is not a bare repo" >&2; exit 1; }
rm -rf "$dir"
git init -q --bare "$dir"
wt=$(mktemp -d)
git worktree add -q --detach "$wt" "refs/upstream-tags/$old"
trap 'git worktree remove --force "$wt"' EXIT
sed -i "s/^XDT_VERSION_INIT(\[$have\]/XDT_VERSION_INIT([$next]/" "$wt/configure.ac"
{ printf '%s (test release, not from Xfce)\n=======\n- Test release for the upstream watcher (#30)\n\n' "$next"; cat "$wt/NEWS"; } > "$wt/NEWS.new"
mv "$wt/NEWS.new" "$wt/NEWS"
git -C "$wt" commit -q -am "Test release $tag for the upstream watcher (#30)"
git -c push.negotiate=false push -q "$dir" "refs/upstream-tags/$old:refs/tags/$old" "$(git -C "$wt" rev-parse HEAD):refs/tags/$tag"
echo "$tag"
