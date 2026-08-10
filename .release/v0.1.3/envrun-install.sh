#!/bin/sh

set -eu
umask 077

release_repository="https://github.com/michaelshimeles/envrun-releases/releases"
release_signing_key="AAAAC3NzaC1lZDI1NTE5AAAAIDDUJyFA3KUo0HXdzKUDdNiKE3eNJgY9jwF/PtA+bemH"
requested_version="latest"
bin_directory=""
temporary_directory=""
staging_directory=""
platform=""

say() {
  printf '%s\n' "$*"
}

fail() {
  printf 'envrun installer: %s\n' "$*" >&2
  exit 1
}

sha256_digest() {
  if [ "$platform" = "linux" ]; then
    sha256sum "$1" | awk '{ print $1 }'
  else
    shasum -a 256 "$1" | awk '{ print $1 }'
  fi
}

verify_sha256_manifest() {
  if [ "$platform" = "linux" ]; then
    sha256sum --check --strict "$1"
  else
    shasum -a 256 --check "$1"
  fi
}

usage() {
  printf '%s\n' \
    'usage: install [--version VERSION] [--bin-dir /absolute/path]'
}

cleanup() {
  if [ -n "$staging_directory" ] && [ -e "$staging_directory" ]; then
    rm -rf -- "$staging_directory"
  fi
  if [ -n "$temporary_directory" ] && [ -e "$temporary_directory" ]; then
    rm -rf -- "$temporary_directory"
  fi
}

trap cleanup EXIT HUP INT TERM

while [ "$#" -gt 0 ]; do
  case "$1" in
    --version)
      [ "$#" -ge 2 ] || fail "--version requires a value"
      requested_version=${2#v}
      shift 2
      ;;
    --bin-dir)
      [ "$#" -ge 2 ] || fail "--bin-dir requires a value"
      bin_directory=$2
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      usage >&2
      fail "unknown option: $1"
      ;;
  esac
done

system_name=$(uname -s)
case "$system_name" in
  Linux)
    platform="linux"
    command -v flock >/dev/null 2>&1 || fail "flock is required"
    command -v sha256sum >/dev/null 2>&1 || fail "sha256sum is required"
    ;;
  Darwin)
    platform="macos"
    [ -x /usr/bin/lockf ] || fail "/usr/bin/lockf is required"
    command -v shasum >/dev/null 2>&1 || fail "shasum is required"
    ;;
  *) fail "this release supports Linux and macOS only" ;;
esac
for command_name in awk cmp curl cut find grep mkdir mktemp mv node rm rmdir \
  ssh-keygen tar tr uname wc; do
  command -v "$command_name" >/dev/null 2>&1 || fail "$command_name is required"
done

node_major=$(node -p 'process.versions.node.split(".")[0]')
[ "$node_major" = "24" ] || fail "Node 24 is required (found $(node --version))"

if [ "$requested_version" != "latest" ]; then
  printf '%s\n' "$requested_version" | grep -Eq \
    '^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?$' || \
    fail "invalid version: $requested_version"
  download_root="$release_repository/download/v$requested_version"
else
  download_root="$release_repository/latest/download"
fi

if [ -n "$bin_directory" ]; then
  case "$bin_directory" in
    /*) ;;
    *) fail "--bin-dir must be an absolute path" ;;
  esac
fi

temporary_directory=$(mktemp -d "${TMPDIR:-/tmp}/envrun-install.XXXXXXXX")
temporary_directory=$(cd "$temporary_directory" && pwd -P)
archive_name="envrun-$platform.tar.gz"
archive="$temporary_directory/$archive_name"
checksum_file="$temporary_directory/envrun-release.sha256"
signature_file="$temporary_directory/envrun-release.sha256.sig"

say "Downloading envrun ${requested_version}..."
curl --proto '=https' --proto-redir '=https' --tlsv1.2 \
  --fail --show-error --silent --location \
  "$download_root/$archive_name" --output "$archive"
curl --proto '=https' --proto-redir '=https' --tlsv1.2 \
  --fail --show-error --silent --location \
  "$download_root/envrun-release.sha256" --output "$checksum_file"
curl --proto '=https' --proto-redir '=https' --tlsv1.2 \
  --fail --show-error --silent --location \
  "$download_root/envrun-release.sha256.sig" --output "$signature_file"

allowed_signers="$temporary_directory/allowed_signers"
printf 'envrun-release namespaces="envrun-release" ssh-ed25519 %s\n' \
  "$release_signing_key" > "$allowed_signers"
ssh-keygen -Y verify -f "$allowed_signers" -I envrun-release \
  -n envrun-release -s "$signature_file" < "$checksum_file" >/dev/null 2>&1 || \
  fail "release signature verification failed"

[ "$(wc -l < "$checksum_file" | tr -d ' ')" = "5" ] || \
  fail "release checksum file is malformed"
for release_file in envrun-linux.tar.gz envrun-macos.tar.gz envrun-install.sh \
  envrun.spdx.json release-signing-key.pub; do
  [ "$(awk -v name="$release_file" '$2 == name { count++ } END { print count + 0 }' \
    "$checksum_file")" = "1" ] || fail "release checksum file is malformed"
done
expected_checksum=$(awk -v name="$archive_name" '$2 == name { print $1 }' "$checksum_file")
case "$expected_checksum" in
  ''|*[!0-9a-f]*) fail "release checksum is malformed" ;;
esac
[ "${#expected_checksum}" = "64" ] || fail "release checksum is malformed"
actual_checksum=$(sha256_digest "$archive")
[ "$actual_checksum" = "$expected_checksum" ] || fail "release checksum verification failed"

archive_listing="$temporary_directory/archive.list"
tar --list --gzip --file "$archive" > "$archive_listing"
archive_root=$(awk -F/ 'NR == 1 { print $1 }' "$archive_listing")
case "$archive_root" in
  envrun-*-$platform) ;;
  *) fail "release archive has an unexpected root" ;;
esac
awk -v root="$archive_root" '
  $0 == root || index($0, root "/") == 1 {
    if ($0 ~ /(^|\/)\.\.(\/|$)/) exit 1
    next
  }
  { exit 1 }
' "$archive_listing" || fail "release archive contains an unsafe path"

tar -xzf "$archive" -C "$temporary_directory"
extracted="$temporary_directory/$archive_root"
[ -d "$extracted" ] && [ ! -L "$extracted" ] || fail "release root is invalid"
[ -z "$(find "$extracted" -type l -print -quit)" ] || \
  fail "release archive contains a symbolic link"
[ -z "$(find "$extracted" ! -type d ! -type f -print -quit)" ] || \
  fail "release archive contains an unsupported file"

packaged_version=$(tr -d '\r\n' < "$extracted/VERSION")
printf '%s\n' "$packaged_version" | grep -Eq \
  '^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?$' || \
  fail "release contains an invalid version"
if [ "$requested_version" != "latest" ] && [ "$packaged_version" != "$requested_version" ]; then
  fail "downloaded release does not match requested version"
fi
[ "$archive_root" = "envrun-$packaged_version-$platform" ] || \
  fail "release archive platform or version does not match"
(cd "$extracted" && verify_sha256_manifest RELEASE-MANIFEST.sha256 >/dev/null) || \
  fail "release contents failed verification"

if [ -n "${XDG_DATA_HOME:-}" ]; then
  data_root=$XDG_DATA_HOME
else
  [ -n "${HOME:-}" ] || fail "HOME is required"
  data_root="$HOME/.local/share"
fi
case "$data_root" in
  /*) ;;
  *) fail "the envrun data directory must be absolute" ;;
esac

release_directory="$data_root/envrun/releases"
mkdir -p "$release_directory"
exec 9>"$release_directory/.install.lock"
if [ "$platform" = "linux" ]; then
  flock 9
else
  /usr/bin/lockf -s -t 30 9 || fail "timed out waiting for another envrun installation"
fi

digest_prefix=$(printf '%s' "$actual_checksum" | cut -c1-16)
destination="$release_directory/$packaged_version-$digest_prefix"
if [ -e "$destination" ]; then
  [ -d "$destination" ] && [ ! -L "$destination" ] || \
    fail "existing release path is invalid: $destination"
  [ -z "$(find "$destination" -type l -print -quit)" ] || \
    fail "existing release contains a symbolic link"
  cmp "$extracted/RELEASE-MANIFEST.sha256" \
    "$destination/RELEASE-MANIFEST.sha256" >/dev/null || \
    fail "existing release differs from the downloaded release"
  (cd "$destination" && verify_sha256_manifest RELEASE-MANIFEST.sha256 >/dev/null) || \
    fail "existing release contents failed verification"
else
  staging_directory=$(mktemp -d "$release_directory/.envrun-release.XXXXXXXX")
  rmdir "$staging_directory"
  mv "$extracted" "$staging_directory"
  (cd "$staging_directory" && verify_sha256_manifest RELEASE-MANIFEST.sha256 >/dev/null) || \
    fail "staged release contents failed verification"
  mv "$staging_directory" "$destination"
  staging_directory=""
fi

if [ -n "$bin_directory" ]; then
  node "$destination/scripts/install-local.mjs" \
    --release "$packaged_version" --bin-dir "$bin_directory"
else
  node "$destination/scripts/install-local.mjs" --release "$packaged_version"
fi

say "Installed envrun $packaged_version from a verified release."
say "Run: envrun setup --account YOUR_1PASSWORD_ACCOUNT"
