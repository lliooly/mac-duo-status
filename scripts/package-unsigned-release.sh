#!/bin/zsh

set -euo pipefail

script_dir="${0:A:h}"
workspace_dir="${script_dir:h}"
release_dir="${workspace_dir}/build/release"
archive_path="${release_dir}/DuoStatus.xcarchive"
app_path="${archive_path}/Products/Applications/mac-duo-status.app"
zip_path="${release_dir}/DuoStatus-v1.1.0-macos-arm64-unsigned.zip"

mkdir -p "$release_dir"

if [[ -e "$archive_path" ]]; then
  rm -rf "$archive_path"
fi

if [[ -e "$zip_path" ]]; then
  rm -f "$zip_path" "$zip_path.sha256"
fi

xcodebuild \
  -project "$workspace_dir/mac-duo-status.xcodeproj" \
  -scheme mac-duo-status \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -archivePath "$archive_path" \
  ARCHS=arm64 \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  archive

if [[ ! -d "$app_path" ]]; then
  print -u2 "Release archive did not contain mac-duo-status.app"
  exit 1
fi

ditto -c -k --sequesterRsrc --keepParent "$app_path" "$zip_path"
shasum -a 256 "$zip_path" > "$zip_path.sha256"

print "Created: $zip_path"
print "Created: $zip_path.sha256"
