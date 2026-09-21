#!/bin/zsh

set -euo pipefail

script_dir="${0:A:h}"
workspace_dir="${script_dir:h}"
version="${1:-2.0.0}"
build_number="${BUILD_NUMBER:-3}"
release_dir="${workspace_dir}/dist"
archive_path="${workspace_dir}/build/DuoStatus-v${version}.xcarchive"
app_path="${archive_path}/Products/Applications/mac-duo-status.app"
zip_path="${release_dir}/DuoStatus-v${version}-macos-arm64-unsigned.zip"
dmg_path="${release_dir}/DuoStatus-v${version}-macos-arm64-unsigned.dmg"

remove_path() {
    local target_path="$1"
    if [[ -e "$target_path" ]]; then
        find "$target_path" -depth -delete
    fi
}

mkdir -p "$release_dir" "${workspace_dir}/build"

remove_path "$archive_path"
remove_path "$zip_path"
remove_path "$zip_path.sha256"
remove_path "$dmg_path"
remove_path "$dmg_path.sha256"

xcodebuild \
  -project "$workspace_dir/mac-duo-status.xcodeproj" \
  -scheme mac-duo-status \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -archivePath "$archive_path" \
  ARCHS=arm64 \
  ONLY_ACTIVE_ARCH=NO \
  MARKETING_VERSION="$version" \
  CURRENT_PROJECT_VERSION="$build_number" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  archive

if [[ ! -d "$app_path" ]]; then
  print -u2 "Release archive did not contain mac-duo-status.app"
  exit 1
fi

ditto -c -k --sequesterRsrc --keepParent "$app_path" "$zip_path"
hdiutil create \
  -volname "Duo Status ${version}" \
  -srcfolder "$app_path" \
  -ov \
  -format UDZO \
  "$dmg_path"

(cd "$release_dir" && shasum -a 256 "${zip_path:t}" > "${zip_path:t}.sha256")
(cd "$release_dir" && shasum -a 256 "${dmg_path:t}" > "${dmg_path:t}.sha256")

print "Created: $zip_path"
print "Created: $zip_path.sha256"
print "Created: $dmg_path"
print "Created: $dmg_path.sha256"
