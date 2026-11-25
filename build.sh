#!/bin/zsh
set -euo pipefail

cd -- "${0:A:h}"
build="$PWD/.build"
app="$PWD/dist/Snowglow.app"
sdk="$(xcrun --sdk macosx --show-sdk-path)"
mkdir -p "$build" "$app/Contents/MacOS" "$app/Contents/Resources/SettingsIcons" "$app/Contents/Resources/Wallpapers"
mkdir -p "$build/Snowglow.iconset"

archs=(arm64 x86_64)
if [[ "${1:-}" == --native ]]; then
    archs=("$(uname -m)")
fi
binaries=()
for arch in "${archs[@]}"; do
    binary="$build/Snowglow-$arch"
    xcrun swiftc -swift-version 5 -O -sdk "$sdk" -target "$arch-apple-macosx14.0" \
        -module-name Snowglow Sources/*.swift -o "$binary"
    binaries+=("$binary")
done
if (( ${#binaries[@]} > 1 )); then
    xcrun lipo -create "${binaries[@]}" -output "$app/Contents/MacOS/Snowglow"
else
    cp -p "${binaries[1]}" "$app/Contents/MacOS/Snowglow"
fi

"$app/Contents/MacOS/Snowglow" --write-icon "$build/Snowglow.png"
for side in 16 32 128 256 512; do
    for scale in 1 2; do
        pixels=$(( side * scale ))
        suffix=""
        if (( scale == 2 )); then suffix="@2x"; fi
        sips -z "$pixels" "$pixels" "$build/Snowglow.png" \
            --out "$build/Snowglow.iconset/icon_${side}x${side}${suffix}.png" > /dev/null
    done
done
iconutil -c icns "$build/Snowglow.iconset" -o "$app/Contents/Resources/Snowglow.icns"
cp Resources/WinterCabin.jpg Resources/LockSnow.mov Resources/LockSnow.png "$app/Contents/Resources/"
cp Resources/Wallpapers/*.jpg "$app/Contents/Resources/Wallpapers/"
rm -f "$app/Contents/Resources/SettingsIcons/"*.png(N)
cp Resources/SettingsIcons/*.png "$app/Contents/Resources/SettingsIcons/"
cp Info.plist "$app/Contents/Info.plist"
plutil -lint "$app/Contents/Info.plist"
codesign --force --sign - "$app"
printf '%s\n' "$app"
