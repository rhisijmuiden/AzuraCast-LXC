#!/usr/bin/env bash
# Shared helpers for the AzuraCast-LXC native tooling (installer, updater, azuracast-ctl).
# shellcheck disable=SC2034

AZ_ROOT=/var/azuracast
AZ_WWW="$AZ_ROOT/www"
AZ_ETC=/etc/azuracast
AZ_ENV_FILE="$AZ_ETC/azuracast.env"
AZ_RELEASE_FILE="$AZ_ETC/release.env"
AZ_LIB=/usr/local/lib/azuracast
AZ_STAGING="$AZ_ROOT/staging"
AZ_UPDATER_DIR="$AZ_ROOT/updater"
AZ_REPO_DEFAULT="rhisijmuiden/azuracast-lxc"
AZ_PHP_VERSION=8.5

if [[ -t 1 ]]; then
    C_BLUE=$'\e[1;34m'; C_GREEN=$'\e[1;32m'; C_YELLOW=$'\e[1;33m'; C_RED=$'\e[1;31m'; C_OFF=$'\e[0m'
else
    C_BLUE=''; C_GREEN=''; C_YELLOW=''; C_RED=''; C_OFF=''
fi

log()  { echo "${C_BLUE}==>${C_OFF} $*"; }
ok()   { echo "${C_GREEN} ✓${C_OFF} $*"; }
warn() { echo "${C_YELLOW} !${C_OFF} $*" >&2; }
die()  { echo "${C_RED} ✗ $*${C_OFF}" >&2; exit 1; }

require_root() {
    [[ $EUID -eq 0 ]] || die "Run this as root (sudo)."
}

# Load KEY=VALUE settings into the environment (and export them).
load_env() {
    local f
    for f in "$@"; do
        if [[ -r "$f" ]]; then
            set -a
            # shellcheck disable=SC1090
            . "$f"
            set +a
        fi
    done
}

# Read one key from an env file without sourcing it.
env_get() {
    local file="$1" key="$2"
    [[ -r "$file" ]] || return 0
    grep -E "^${key}=" "$file" | tail -n1 | cut -d= -f2-
}

# Set (add or replace) one key in an env file.
env_set() {
    local file="$1" key="$2" value="$3"
    touch "$file"
    if grep -qE "^${key}=" "$file"; then
        local tmp
        tmp=$(mktemp)
        awk -v k="$key" -v v="$value" 'BEGIN{FS=OFS="="} $1==k {print k "=" v; next} {print}' "$file" >"$tmp"
        cat "$tmp" >"$file"
        rm -f "$tmp"
    else
        echo "${key}=${value}" >>"$file"
    fi
}

# Map our branch channel to the upstream AZURACAST_VERSION value the app understands.
channel_to_release_channel() {
    case "$1" in
        test) echo "latest" ;;   # shown as "Rolling Release" in the app
        *) echo "stable" ;;
    esac
}

arch_name() {
    case "$(uname -m)" in
        x86_64) echo amd64 ;;
        aarch64) echo arm64 ;;
        *) uname -m ;;
    esac
}

github_api() {
    local path="$1"
    curl -fsSL --retry 3 \
        -H 'Accept: application/vnd.github+json' \
        -H 'User-Agent: AzuraCast-LXC installer' \
        "https://api.github.com/repos/${path}"
}

# Print the tag of the newest release for a channel: main = latest stable release, test = newest prerelease.
resolve_release_tag() {
    local repo="$1" channel="$2"
    if [[ "$channel" == "test" ]]; then
        github_api "${repo}/releases?per_page=50" \
            | jq -r '[.[] | select(.draft == false and .prerelease == true)] | sort_by(.published_at) | last | .tag_name // empty'
    else
        github_api "${repo}/releases/latest" | jq -r '.tag_name // empty'
    fi
}

# Download a release tarball and its checksum into a directory and unpack it there.
# Prints the path of the unpacked release.
download_release() {
    local repo="$1" tag="$2" dest="$3"
    local version="${tag#v}"
    local name="azuracast-lxc-${version}.tar.gz"
    local base="https://github.com/${repo}/releases/download/${tag}"

    mkdir -p "$dest"
    curl -fsSL --retry 3 -o "$dest/$name" "$base/$name" || die "Download failed: $base/$name"
    curl -fsSL --retry 3 -o "$dest/$name.sha256" "$base/$name.sha256" || die "Checksum download failed."
    (cd "$dest" && sha256sum -c "$name.sha256" >/dev/null) || die "Checksum mismatch for $name."

    rm -rf "$dest/release"
    mkdir -p "$dest/release"
    tar -xzf "$dest/$name" -C "$dest/release"
    rm -f "$dest/$name" "$dest/$name.sha256"
    echo "$dest/release"
}

wait_for_http() {
    local url="$1" timeout="${2:-300}" waited=0
    while ((waited < timeout)); do
        if curl -fsS -o /dev/null --max-time 5 "$url"; then
            return 0
        fi
        sleep 5
        waited=$((waited + 5))
    done
    return 1
}
