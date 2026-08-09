#!/usr/bin/env bash
#
# Bumps version numbers across the repo in one shot:
#   - Backend/VERSION                              (backend, e.g. 1.1.0)
#   - StashApp/Config/*-Info.plist                  (CFBundleShortVersionString, e.g. 1.1)
#   - Extension/manifest.json                       (version, derived from the app version)
#
# Usage:
#   Script/bump-version.sh --backend 1.1.0 --app 1.1
#
# CFBundleVersion (the build number) is intentionally left untouched; it's
# bumped independently of the short/marketing version.
#
# The Info.plist files, not the Xcode build settings, are the source of
# truth here: StashApp/Stash.xcodeproj sets GENERATE_INFOPLIST_FILE = NO for
# every target, so Xcode never synthesizes CFBundleShortVersionString /
# CFBundleVersion from MARKETING_VERSION / CURRENT_PROJECT_VERSION; it just
# uses the committed Info.plist as-is.

set -euo pipefail

usage() {
    echo "Usage: $0 --backend X.Y.Z --app X.Y" >&2
    exit 1
}

backend_version=""
app_version=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --backend)
            backend_version="$2"
            shift 2
            ;;
        --app)
            app_version="$2"
            shift 2
            ;;
        *)
            usage
            ;;
    esac
done

[[ -z "$backend_version" || -z "$app_version" ]] && usage

if [[ ! "$backend_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "error: --backend must be major.minor.patch (got '$backend_version')" >&2
    exit 1
fi

if [[ ! "$app_version" =~ ^[0-9]+\.[0-9]+$ ]]; then
    echo "error: --app must be major.minor (got '$app_version')" >&2
    exit 1
fi

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

backend_version_file="$repo_root/Backend/VERSION"
manifest="$repo_root/Extension/manifest.json"
info_plists=(
    "$repo_root/StashApp/Config/App-iOS-Info.plist"
    "$repo_root/StashApp/Config/App-macOS-Info.plist"
    "$repo_root/StashApp/Config/Ext-iOS-Info.plist"
    "$repo_root/StashApp/Config/Ext-macOS-Info.plist"
)

extension_version="${app_version}.0"

echo "Backend:   $(cat "$backend_version_file") -> $backend_version"
echo "App:       $(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "${info_plists[0]}") -> $app_version"
echo "Extension: $(grep -m1 '"version"' "$manifest" | sed -E 's/.*: *"(.*)".*/\1/') -> $extension_version"

echo "$backend_version" > "$backend_version_file"

# A targeted single-line sed, rather than PlistBuddy -c Set, since PlistBuddy
# rewrites (and alphabetizes) the whole file on save, turning a one-line
# version bump into a huge, unreviewable diff.
for plist in "${info_plists[@]}"; do
    sed -i '' -E '/<key>CFBundleShortVersionString<\/key>/{n;s#<string>[0-9]+(\.[0-9]+)*</string>#<string>'"${app_version}"'</string>#;}' "$plist"
done

sed -i '' -E "s/\"version\": \"[0-9]+(\.[0-9]+)*\"/\"version\": \"${extension_version}\"/" "$manifest"

echo "Done."
