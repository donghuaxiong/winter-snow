#!/bin/sh
set -eu

cd -- "$(dirname -- "$0")/.."
app="$PWD/dist/Snowglow.app"
binary="$app/Contents/MacOS/Snowglow"
release="$PWD/dist/release"

if [ ! -x "$binary" ] || ! xcrun lipo "$binary" -verify_arch arm64 x86_64; then
    printf '%s\n' 'Run ./build.sh to build the universal application before packaging.' >&2
    exit 1
fi

mkdir -p "$release" .build
stage="$(mktemp -d "$PWD/.build/macos-release.XXXXXX")"
trap 'rm -rf -- "$stage"' EXIT
for edition in Universal Intel; do
    source="$stage/$edition"
    mkdir -p "$source"
    ditto "$app" "$source/Snowglow.app"
    ln -s /Applications "$source/Applications"
    cp LICENSE "$source/LICENSE.txt"
    if [ "$edition" = Intel ]; then
        target="$source/Snowglow.app/Contents/MacOS/Snowglow"
        xcrun lipo "$target" -thin x86_64 -output "$stage/intel-executable"
        mv -f "$stage/intel-executable" "$target"
        chmod 755 "$target"
        codesign --force --sign - "$source/Snowglow.app"
    fi
    codesign --verify --strict "$source/Snowglow.app"
    image="Snowglow-macOS-$edition.dmg"
    hdiutil create -srcfolder "$source" -volname "Snowglow $edition" -fs HFS+ \
        -format UDZO -imagekey zlib-level=9 "$stage/$image"
    hdiutil verify "$stage/$image"
done

for edition in Universal Intel; do
    image="Snowglow-macOS-$edition.dmg"
    mv -f "$stage/$image" "$release/$image"
    printf '%s\n' "$release/$image"
done
