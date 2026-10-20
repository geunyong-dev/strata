#!/bin/bash
set -euo pipefail

# Local-only, ad-hoc signed release bundle. Never replaces an existing bundle.
project_root="$(cd "$(dirname "$0")/.." && pwd)"
output_path="${1:-$project_root/dist/Strata.app}"
if [[ "$output_path" != /* || "$output_path" != *.app ]]; then
    echo "Provide an absolute output path ending in .app." >&2
    exit 1
fi
if [[ -e "$output_path" || -L "$output_path" ]]; then
    echo "Output already exists; choose a new path: $output_path" >&2
    exit 1
fi
cd "$project_root"
test -f "$project_root/Packaging/AppIcon/Strata-v1.icns"
swift build -c release
binary_directory="$(swift build -c release --show-bin-path)"
test -x "$binary_directory/Strata"
test -x "$binary_directory/StrataReadOnlyScanner"
mkdir -p "$(dirname "$output_path")"
staging_directory="$(mktemp -d "$(dirname "$output_path")/.strata-package.XXXXXX")"
bundle_path="$staging_directory/Strata.app"
mkdir -p "$bundle_path/Contents/MacOS"
mkdir -p "$bundle_path/Contents/Helpers"
mkdir -p "$bundle_path/Contents/Resources"
cp "$binary_directory/Strata" "$bundle_path/Contents/MacOS/Strata"
cp "$binary_directory/StrataReadOnlyScanner" "$bundle_path/Contents/Helpers/StrataReadOnlyScanner"
cp "$project_root/Packaging/Info.plist" "$bundle_path/Contents/Info.plist"
cp "$project_root/Packaging/AppIcon/Strata-v1.icns" "$bundle_path/Contents/Resources/Strata.icns"
/usr/bin/plutil -lint "$bundle_path/Contents/Info.plist"
/usr/bin/codesign --force --sign - --identifier local.strata.read-only-scanner "$bundle_path/Contents/Helpers/StrataReadOnlyScanner"
/usr/bin/codesign --force --sign - --identifier local.strata.design-review "$bundle_path"
/usr/bin/codesign --verify --deep --strict --verbose=2 "$bundle_path"
# Recheck after the build to avoid unintentionally replacing a previous result.
if [[ -e "$output_path" || -L "$output_path" ]]; then
    echo "Output appeared during build; bundle retained at $bundle_path" >&2
    exit 1
fi
mv "$bundle_path" "$output_path"
rmdir "$staging_directory"
echo "Local app ready: $output_path"
echo "Ad-hoc signed for this Mac only; not notarized for external distribution."
