#!/usr/bin/env bash
set -euo pipefail

channel="${1:-release}"

if [[ "$channel" != "release" && "$channel" != "beta" ]]; then
	echo "Usage: release.sh [release|beta]" >&2
	exit 1
fi

if [[ -n "$(git status --porcelain)" ]]; then
	echo "Working tree is not clean." >&2
	exit 1
fi

branch="$(git rev-parse --abbrev-ref HEAD)"
if [[ "$branch" != "main" ]]; then
	echo "Not on main (on $branch)." >&2
	exit 1
fi

git fetch --tags --quiet origin

latest="$(git tag --list | grep -E '^[0-9]+\.[0-9]+\.[0-9]+$' | sort -t. -k1,1n -k2,2n -k3,3n | tail -n 1 || true)"
if [[ -z "$latest" ]]; then
	echo "No existing release tag found." >&2
	exit 1
fi

IFS=. read -r major minor patch <<< "$latest"
next="$major.$minor.$((patch + 1))"

if [[ "$channel" == "beta" ]]; then
	count="$(git tag --list "$next-beta*" | wc -l | tr -d ' ')"
	tag="$next-beta$((count + 1))"
else
	tag="$next"
fi

if git rev-parse -q --verify "refs/tags/$tag" > /dev/null; then
	echo "Tag $tag already exists." >&2
	exit 1
fi

echo "Latest release: $latest"
read -r -p "Tag and push $tag? [y/N] " answer
if [[ "$answer" != "y" && "$answer" != "Y" ]]; then
	echo "Aborted."
	exit 1
fi

git tag "$tag"
git push --atomic origin main "$tag"
