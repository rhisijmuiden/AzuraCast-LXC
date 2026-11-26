#!/usr/bin/env bash
#
# AzuraCast-LXC installer: AzuraCast natively on Debian 13, without Docker.
#
#   curl -fsSL https://raw.githubusercontent.com/rhisijmuiden/azuracast-lxc/main/native/install.sh | sudo bash
#   curl -fsSL https://raw.githubusercontent.com/rhisijmuiden/azuracast-lxc/test/native/install.sh | sudo bash -s -- --channel test
#
# Options:
#   --channel main|test     main = production releases (default), test = test releases
#   --tag vX.Y.Z            install this exact release instead of the newest one
#   --release-file FILE     install from a local release tarball (for testing builds)
#   --repo owner/name       GitHub repository with the releases (default rhisijmuiden/azuracast-lxc)
#
# Requirements: Debian 13 (trixie), amd64. In a Proxmox LXC container enable "nesting".
#
set -euo pipefail

REPO="rhisijmuiden/azuracast-lxc"
CHANNEL="main"
TAG=""
RELEASE_FILE=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --channel) CHANNEL="$2"; shift 2 ;;
        --tag) TAG="$2"; shift 2 ;;
        --release-file) RELEASE_FILE="$2"; shift 2 ;;
        --repo) REPO="$2"; shift 2 ;;
        -h|--help) sed -n '2,17p' "$0" 2>/dev/null || true; exit 0 ;;
        *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
done

[[ $EUID -eq 0 ]] || { echo "Run this as root (sudo)." >&2; exit 1; }
[[ "$CHANNEL" == "main" || "$CHANNEL" == "test" ]] || { echo "--channel must be main or test." >&2; exit 1; }

. /etc/os-release
if [[ "${ID:-}" != "debian" || "${VERSION_ID:-}" != "13" ]]; then
    echo "AzuraCast-LXC needs Debian 13 (trixie); this is ${PRETTY_NAME:-unknown}." >&2
    exit 1
fi

if [[ -f /var/azuracast/.native && -x /usr/local/sbin/azuracast-ctl ]]; then
    echo "AzuraCast-LXC is already installed. To update, run: azuracast-ctl update" >&2
    exit 1
fi

echo "==> Preparing"
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq --no-install-recommends ca-certificates curl jq tar gzip >/dev/null

WORK=/var/azuracast/staging/install
rm -rf "$WORK"
mkdir -p "$WORK/release"

if [[ -n "$RELEASE_FILE" ]]; then
    echo "==> Using local release $RELEASE_FILE"
    tar -xzf "$RELEASE_FILE" -C "$WORK/release"
    [[ -n "$TAG" ]] || TAG="v$(cat "$WORK/release/native/VERSION")"
else
    api() { curl -fsSL --retry 3 -H 'Accept: application/vnd.github+json' -H 'User-Agent: AzuraCast-LXC installer' "https://api.github.com/repos/$REPO/$1"; }
    if [[ -z "$TAG" ]]; then
        if [[ "$CHANNEL" == "test" ]]; then
            TAG="$(api 'releases?per_page=50' | jq -r '[.[] | select(.draft == false and .prerelease == true)] | sort_by(.published_at) | last | .tag_name // empty')"
        else
            TAG="$(api 'releases/latest' | jq -r '.tag_name // empty')"
        fi
    fi
    [[ -n "$TAG" ]] || { echo "No release found on the $CHANNEL channel of $REPO." >&2; exit 1; }

    NAME="azuracast-lxc-${TAG#v}.tar.gz"
    BASE="https://github.com/$REPO/releases/download/$TAG"
    echo "==> Downloading $TAG"
    curl -fsSL --retry 3 -o "$WORK/$NAME" "$BASE/$NAME"
    curl -fsSL --retry 3 -o "$WORK/$NAME.sha256" "$BASE/$NAME.sha256"
    (cd "$WORK" && sha256sum -c "$NAME.sha256" >/dev/null) || { echo "Checksum mismatch." >&2; exit 1; }
    tar -xzf "$WORK/$NAME" -C "$WORK/release"
    rm -f "$WORK/$NAME" "$WORK/$NAME.sha256"
fi

export AZ_REPOSITORY="$REPO"
bash "$WORK/release/native/sbin/azuracast-native" install "$WORK/release" --channel "$CHANNEL" --tag "$TAG"
rm -rf "$WORK"

IP="$(hostname -I 2>/dev/null | awk '{print $1}')"
cat <<EOF

AzuraCast-LXC $TAG is installed ($CHANNEL channel).

  Open http://${IP:-<this-server>}/ to create the first administrator account.

  Manage it with:  azuracast-ctl status | update | channel main|test | logs | backup
  Settings:        /etc/azuracast/azuracast.env  (then: azuracast-ctl restart)

EOF
