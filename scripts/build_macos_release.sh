#!/bin/bash
# Builds a release Hoopix.app for this Mac's architecture and packages it as a
# .zip and a .dmg under build/dist, with a SHA256SUMS file.
#
# The app is signed ad hoc, not with a Developer ID, and is not notarized:
# macOS will refuse to open a downloaded copy until the user allows it (see
# the README). That is deliberate for now; nothing here needs a certificate.
#
# Why one architecture per build: Xcode 27's `lipo` accepts a single
# architecture per `-verify_arch`, while Flutter 3.38 asks it to verify all of
# them in one call, so any multi-architecture release build fails in
# `release_unpack_macos`. Building for one architecture at a time sidesteps
# that without changing Flutter or Xcode. A universal build would need an
# Intel build too, which needs Rosetta on an Apple Silicon Mac (Flutter runs
# the x86_64 AOT compiler under it) and a `lipo -create` of the two results.
#
# Usage: scripts/build_macos_release.sh

set -euo pipefail

cd "$(dirname "$0")/.."

arch="$(uname -m)" # arm64 or x86_64
version="$(sed -n 's/^version: *\([0-9][0-9.]*\).*/\1/p' pubspec.yaml)"
if [ -z "$version" ]; then
  echo "Could not read the version from pubspec.yaml" >&2
  exit 1
fi

echo "Building Hoopix $version for $arch..."
rm -rf build/macos/Build/Products/Release
FLUTTER_XCODE_ARCHS="$arch" flutter build macos --release

app="build/macos/Build/Products/Release/hoopix.app"
if [ ! -d "$app" ]; then
  echo "Build finished but $app is missing" >&2
  exit 1
fi

# The binary must really be the architecture asked for, and the signature
# must be intact, before anything is packaged.
built="$(lipo -archs "$app/Contents/MacOS/hoopix")"
if [ "$built" != "$arch" ]; then
  echo "Expected a $arch binary, got: $built" >&2
  exit 1
fi
codesign --verify --deep --strict "$app"

dist="build/dist"
name="Hoopix-$version-macos-$arch"
rm -rf "$dist"
mkdir -p "$dist/stage"

ditto -c -k --keepParent "$app" "$dist/$name.zip"

# A disk image with an Applications shortcut, so the app can be dragged in.
ditto "$app" "$dist/stage/hoopix.app"
ln -s /Applications "$dist/stage/Applications"
hdiutil create -volname "Hoopix" -srcfolder "$dist/stage" -ov -format UDZO \
  "$dist/$name.dmg" > /dev/null
rm -rf "$dist/stage"

(cd "$dist" && shasum -a 256 "$name.zip" "$name.dmg" > SHA256SUMS)

echo
echo "Done:"
ls -lh "$dist" | tail -n +2
