#!/usr/bin/env bash
#
# Bumps version numbers across the repo in one shot:
#   - Backend/VERSION                              (backend, e.g. 1.1.0)
#   - StashApp/Stash.xcodeproj/project.pbxproj      (MARKETING_VERSION, e.g. 1.1)
#   - Extension/manifest.json                       (version, derived from the app version)
#
# Usage:
#   Script/bump-version.sh --backend 1.1.0 --app 1.1
#
# CURRENT_PROJECT_VERSION (the Xcode build number) is intentionally left
# untouched — it's bumped independently of the marketing version.

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
pbxproj="$repo_root/StashApp/Stash.xcodeproj/project.pbxproj"
manifest="$repo_root/Extension/manifest.json"

extension_version="${app_version}.0"

echo "Backend:   $(cat "$backend_version_file") -> $backend_version"
echo "App:       $(grep -m1 'MARKETING_VERSION' "$pbxproj" | sed -E 's/.*= (.*);/\1/') -> $app_version"
echo "Extension: $(grep -m1 '"version"' "$manifest" | sed -E 's/.*: *"(.*)".*/\1/') -> $extension_version"

echo "$backend_version" > "$backend_version_file"

sed -i '' -E "s/MARKETING_VERSION = [0-9]+(\.[0-9]+)*;/MARKETING_VERSION = ${app_version};/g" "$pbxproj"

sed -i '' -E "s/\"version\": \"[0-9]+(\.[0-9]+)*\"/\"version\": \"${extension_version}\"/" "$manifest"

echo "Done."
