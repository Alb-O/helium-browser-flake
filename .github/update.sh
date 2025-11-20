#!/bin/sh
ci=false
if echo "$@" | grep -qoE '(--ci)'; then
  ci=true
fi

only_check=false
if echo "$@" | grep -qoE '(--only-check)'; then
  only_check=true
fi

remote_latest=$(curl 'https://api.github.com/repos/imputnet/helium-linux/releases/latest' -s)
remote_all=$(curl 'https://api.github.com/repos/imputnet/helium-linux/releases' -s)

get_tag() {
  echo "$remote_latest" | jq -r '.tag_name'
}

get_prerelease_tag() {
  echo "$remote_all" | jq -r '[.[] | select(.prerelease == true)][0].tag_name'
}

commit_targets=""
commit_version=""

update_version() {
  # "stable" or "prerelease"
  channel=$1
  # "x86_64" or "aarch64"
  arch=$2
  # "linux" or "darwin"
  os=$3

  meta=$(jq ".[\"$channel\"][\"$arch-$os\"]" <sources.json)

  local=$(echo "$meta" | jq -r '.version')

  if [ "$channel" = "prerelease" ]; then
    remote=$(get_prerelease_tag)
  else
    remote=$(get_tag)
  fi

  echo "Checking helium ($channel) @ $arch... local=$local remote=$remote"

  if [ "$local" = "$remote" ]; then
    echo "Local version is up to date"
    return
  fi

  echo "Local version mismatch with remote so we* assume it's outdated"

  if $only_check; then
    echo "should_update=true" >>"$GITHUB_OUTPUT"
    exit 0
  fi

  if [ "$arch" = "aarch64" ]; then
    appimage_download_url="https://github.com/imputnet/helium-linux/releases/download/$remote/helium-$remote-arm64.AppImage"
    tar_download_url="https://github.com/imputnet/helium-linux/releases/download/$remote/helium-$remote-arm64_linux.tar.xz"
  else
    appimage_download_url="https://github.com/imputnet/helium-linux/releases/download/$remote/helium-$remote-x86_64.AppImage"
    tar_download_url="https://github.com/imputnet/helium-linux/releases/download/$remote/helium-$remote-x86_64_linux.tar.xz"
  fi

  # Try to prefetch files, skip if they don't exist (e.g., 404 errors)
  if ! prefetch_output=$(nix store prefetch-file --hash-type sha256 --json "$tar_download_url" 2>&1); then
    echo "Warning: Failed to download $tar_download_url, skipping this update"
    return
  fi
  tar_sha256=$(echo "$prefetch_output" | jq -r '.hash')

  if ! prefetch_output=$(nix store prefetch-file --hash-type sha256 --json "$appimage_download_url" 2>&1); then
    echo "Warning: Failed to download $appimage_download_url, skipping this update"
    return
  fi
  appimage_sha256=$(echo "$prefetch_output" | jq -r '.hash')

  jq ".[\"$channel\"][\"$arch-$os\"] = {\"version\":\"$remote\",\"tar_url\":\"$tar_download_url\",\"tar_sha256\":\"$tar_sha256\",\"appimage_url\":\"$appimage_download_url\",\"appimage_sha256\":\"$appimage_sha256\"}" <sources.json >sources.json.tmp
  mv sources.json.tmp sources.json

  if ! $ci; then
    return
  fi

  if [ "$commit_targets" = "" ]; then
    commit_targets="$channel/$arch"
    commit_version="$remote"
  else
    commit_targets="$commit_targets && $channel/$arch"
  fi
}

main() {
  set -e

  update_version "stable" "x86_64" "linux"
  update_version "stable" "aarch64" "linux"
  update_version "prerelease" "x86_64" "linux"
  update_version "prerelease" "aarch64" "linux"
  # update_version "stable" "aarch64" "darwin"
  # update_version "prerelease" "aarch64" "darwin"

  if $only_check && $ci; then
    echo "should_update=false" >>"$GITHUB_OUTPUT"
  fi

  # Check if there are changes
  if ! git diff --exit-code >/dev/null; then
    # Prepare commit message
    init_message="update:"
    message="$init_message"

    message="$message helium @ $commit_targets to $commit_version"

    echo "commit_message=$message" >>"$GITHUB_OUTPUT"
  fi
}

main
