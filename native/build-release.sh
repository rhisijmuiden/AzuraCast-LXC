#!/usr/bin/env bash
#
# Build an AzuraCast-LXC release tarball (run by GitHub Actions, see .github/workflows/native-release.yml).
#
#   native/build-release.sh <version> <output-dir>
#
# Needs PHP 8.5 + composer, Node.js (LTS) + npm, Docker (only to copy the pinned Icecast-KH and
# built-in docs files out of the same images the upstream Dockerfile uses; nothing runs in Docker
# on the target machine) and zstd/tar.
#
set -euo pipefail

VERSION="${1:?version}"
OUT="${2:?output dir}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

export APPLICATION_ENV=testing
export NODE_ENV=production

echo "==> PHP dependencies (with dev tools for the build steps)"
composer install --no-interaction --no-progress --ignore-platform-reqs
chmod a+x backend/bin/*

echo "==> Frontend and translations"
rm -rf web/static/vite_dist
npm ci --include=dev --no-audit --no-fund
backend/bin/console locale:import
npm run build

echo "==> OpenAPI docs and version info"
backend/bin/console azuracast:api:docs
bash util/write_git_info.sh

echo "==> Production PHP dependencies"
composer install --no-dev --no-interaction --no-progress --no-autoloader --ignore-platform-reqs
composer dump-autoload --optimize --classmap-authoritative

echo "==> Icecast-KH and built-in docs from the pinned upstream images"
ICECAST_IMAGE="$(grep -E '^FROM .*icecast-ac' Dockerfile | awk '{print $2}')"
DOCS_IMAGE="$(grep -E '^FROM .*azuracast.com:builtin' Dockerfile | awk '{print $2}')"
rm -rf native-bin
mkdir -p native-bin/icecast/bin

cid="$(docker create "$ICECAST_IMAGE" /bin/true)"
docker cp "$cid:/usr/local/bin/icecast" native-bin/icecast/bin/icecast
docker cp "$cid:/usr/local/share/icecast" native-bin/icecast/share
docker rm "$cid" >/dev/null

cid="$(docker create "$DOCS_IMAGE" /bin/true)"
docker cp "$cid:/dist" native-bin/docs
docker rm "$cid" >/dev/null

echo "==> Packing"
mkdir -p "$OUT"
NAME="azuracast-lxc-${VERSION}.tar.gz"
# The release VERSION shown in the app is the tag (vX.Y.Z or vX.Y.Z-test.N).
echo "${VERSION}" >native/VERSION
tar --exclude='./.git' --exclude='./node_modules' --exclude='./.github' --exclude='./tests' \
    -czf "$OUT/$NAME" .
(cd "$OUT" && sha256sum "$NAME" >"$NAME.sha256")
git checkout -- native/VERSION 2>/dev/null || true

echo "==> Built $OUT/$NAME"
