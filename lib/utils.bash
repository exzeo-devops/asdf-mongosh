#!/usr/bin/env bash

set -euo pipefail

# TODO: Ensure this is the correct GitHub homepage where releases can be downloaded for mongosh.
TOOL_NAME="mongosh"

fail() {
	echo -e "asdf-$TOOL_NAME: $*"
	exit 1
}

curl_opts=(-fsSL)

# NOTE: You might want to remove this if mongosh is not hosted on GitHub releases.
if [ -n "${GITHUB_API_TOKEN:-}" ]; then
	curl_opts=("${curl_opts[@]}" -H "Authorization: token $GITHUB_API_TOKEN")
fi

sort_versions() {
	sed 'h; s/[+-]/./g; s/.p\([[:digit:]]\)/.z\1/; s/$/.z/; G; s/\n/ /' |
		LC_ALL=C sort -t. -k 1,1 -k 2,2n -k 3,3n -k 4,4n -k 5,5n | awk '{print $2}'
}

list_all_versions() {
  release_path="https://api.github.com/repos/mongodb-js/mongosh/releases"

  versions=$(curl "${curl_opts[@]}" "$release_path" | jq -r '.[].tag_name' | grep -vE '^v[0-9]+$' | sed 's/^v//')
  echo "$versions"
}

get_architecture() {
  ARCH="$(uname -m)"

  case $ARCH in
    x86_64) ARCH="x64";;
    arm64 | aarch64) ARCH="arm64";;
    armv7l) ARCH="armv7l";;
    *) fail "Unsupported architecture: $ARCH";;
  esac

  echo "$ARCH"
}

get_download_url() {
  local version="$1"
  local os_name="$(uname -s | tr '[:upper:]' '[:lower:]')"
  local arch="$(get_architecture)"

  local archive_extension="tgz"
  if [[ "$os_name" == "darwin" ]]; then
    archive_extension="zip"
  fi

  echo "https://github.com/mongodb-js/mongosh/releases/download/v${version}/mongosh-${version}-${os_name}-${arch}.${archive_extension}"
}

install_version() {
	local install_type="$1"
	local version="$2"
	local install_path="${3%/bin}/bin"

  local download_url=$(get_download_url "$version")
  local filename=$(basename "$download_url")

  local tmp_download_dir=$(mktemp -d -t mongosh_XXXXXX)

  local download_path="$tmp_download_dir/$filename"

  echo "Downloading mongosh from ${download_url} to ${download_path}"

  curl --retry 10 --retry-delay 2 -fLo $download_path $download_url 2> >(tee /tmp/curl_error >&2)
  ERROR=$(</tmp/curl_error)

  if [ $? -ne 0 ]; then
   echo $ERROR
   fail "Failed to download mongosh from ${download_url}"
  fi

  echo "Creating bin directory"
  mkdir -p "$install_path"

  echo "Copying binary"
  tar -zxf ${download_path} --directory $tmp_download_dir
  cp $tmp_download_dir/${filename%.*}/bin/* $install_path
}
