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

# Validate API responses
if echo "$remote_latest" | jq -e '.message' >/dev/null 2>&1; then
  api_message=$(echo "$remote_latest" | jq -r '.message')
  echo "Warning: GitHub API returned an error for latest release: $api_message"
fi

if echo "$remote_all" | jq -e '.message' >/dev/null 2>&1; then
  api_message=$(echo "$remote_all" | jq -r '.message')
  echo "Warning: GitHub API returned an error for all releases: $api_message"
fi

get_tag() {
  tag=$(echo "$remote_latest" | jq -r '.tag_name // empty' 2>/dev/null)
  if [ -z "$tag" ] || [ "$tag" = "null" ]; then
    echo ""
  else
    echo "$tag"
  fi
}

get_prerelease_tag() {
  # Check if remote_all is an array
  if ! echo "$remote_all" | jq -e 'type == "array"' >/dev/null 2>&1; then
    echo ""
    return
  fi

  tag=$(echo "$remote_all" | jq -r '[.[] | select(.prerelease == true)][0].tag_name // empty' 2>/dev/null)
  if [ -z "$tag" ] || [ "$tag" = "null" ]; then
    echo ""
  else
    echo "$tag"
  fi
}

commit_targets=""
commit_version=""
release_version=""
release_notes=""

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

  # Check if remote version is valid
  if [ -z "$remote" ] || [ "$remote" = "null" ]; then
    echo "Warning: Could not fetch remote version from GitHub API, skipping this update"
    return
  fi

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

  # Try to download and verify the files exist
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
    # Set release version only for stable channel
    if [ "$channel" = "stable" ]; then
      release_version="$remote"
    fi
  else
    commit_targets="$commit_targets && $channel/$arch"
  fi
}

main() {
  # Don't exit on error for update_version calls - they handle errors internally
  update_version "stable" "x86_64" "linux" || true
  update_version "stable" "aarch64" "linux" || true
  update_version "prerelease" "x86_64" "linux" || true
  update_version "prerelease" "aarch64" "linux" || true
  # update_version "stable" "aarch64" "darwin" || true
  # update_version "prerelease" "aarch64" "darwin" || true

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

    if [ -n "$release_version" ]; then
      echo "release_version=$release_version" >>"$GITHUB_OUTPUT"
      release_body=$(echo "$remote_latest" | jq -r '.body // ""')
      release_notes="$release_body

https://github.com/imputnet/helium-linux/releases/tag/$release_version"
      echo "release_notes<<EOF" >>"$GITHUB_OUTPUT"
      echo "$release_notes" >>"$GITHUB_OUTPUT"
      echo "EOF" >>"$GITHUB_OUTPUT"
    fi
  fi
}

main
