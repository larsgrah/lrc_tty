#!/usr/bin/env bash
# Cut a release and update the downstream packaging repos.
#
#   scripts/release.sh 0.8
#
# Tags, pushes the tag, computes the tarball checksum and rewrites the AUR
# PKGBUILD and the void template. Stops there: building, committing and pushing
# the packaging repos stays manual so the diffs get looked at.
#
# Repo locations can be overridden:
#   AUR_REPO=/path/to/aur/lrc_tty VOID_REPO=/path/to/void-custom scripts/release.sh 0.8

set -euo pipefail

version="${1:-}"
if [ -z "$version" ]; then
    echo "usage: $0 <version>   e.g. $0 0.8" >&2
    exit 1
fi
version="${version#v}"

AUR_REPO="${AUR_REPO:-$HOME/code/aur/lrc_tty}"
VOID_REPO="${VOID_REPO:-$HOME/code/lars-void}"
void_template="$VOID_REPO/srcpkgs/lrc_tty/template"
aur_pkgbuild="$AUR_REPO/PKGBUILD"
tarball_url="https://github.com/larsgrah/lrc_tty/archive/refs/tags/v${version}.tar.gz"

step() { printf '\n\033[1m==> %s\033[0m\n' "$1"; }

step "Checking the working tree"
[ -z "$(git status --porcelain)" ] || { echo "working tree is dirty" >&2; exit 1; }
[ "$(git rev-parse --abbrev-ref HEAD)" = "master" ] || { echo "not on master" >&2; exit 1; }
git fetch --quiet origin
[ "$(git rev-parse HEAD)" = "$(git rev-parse origin/master)" ] || { echo "master and origin/master differ" >&2; exit 1; }

pinned=$(awk '/^zig /{print $2}' .tool-versions)
echo "zig pin: $pinned"

step "Building and testing before tagging"
zig build
zig build test

step "Tagging v${version}"
if git rev-parse "v${version}" >/dev/null 2>&1; then
    echo "tag v${version} already exists, skipping"
else
    git tag "v${version}"
    git push origin "v${version}"
fi

step "Fetching the tarball GitHub generated"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
# the tarball can lag the tag push by a moment
for attempt in 1 2 3 4 5; do
    if curl -sSfL -o "$tmp/src.tar.gz" "$tarball_url"; then break; fi
    echo "attempt $attempt failed, retrying"
    sleep 3
done
sum=$(sha256sum "$tmp/src.tar.gz" | cut -d' ' -f1)
echo "sha256: $sum"

step "Updating the AUR PKGBUILD"
if [ -f "$aur_pkgbuild" ]; then
    sed -i -e "s/^pkgver=.*/pkgver=${version}/" \
           -e "s/^sha256sums=.*/sha256sums=('${sum}')/" "$aur_pkgbuild"
    echo "updated $aur_pkgbuild"
else
    echo "skipped, no PKGBUILD at $aur_pkgbuild"
fi

step "Updating the void template"
if [ -f "$void_template" ]; then
    sed -i -e "s/^version=.*/version=${version}/" \
           -e "s/^checksum=.*/checksum=\"${sum}\"/" "$void_template"
    echo "updated $void_template"
else
    echo "skipped, no template at $void_template"
fi

cat <<EOF

Released v${version}. Remaining steps, in order:

  gh release create v${version} --generate-notes

  cd ${AUR_REPO} && make build          # regenerates .SRCINFO, verifies the build
  git -C ${AUR_REPO} add PKGBUILD .SRCINFO && git -C ${AUR_REPO} commit -m "Update to v${version}" && git -C ${AUR_REPO} push

  cd ${VOID_REPO} && ./xbps-src pkg lrc_tty
  git -C ${VOID_REPO} add srcpkgs/lrc_tty/template && git -C ${VOID_REPO} commit -m "lrc_tty: update to ${version}" && git -C ${VOID_REPO} push

If zig moved, bump srcpkgs/zig-bin/template in ${VOID_REPO} too.
EOF
