#!/bin/sh
set -eu
cd -- "$(dirname -- "$0")/.."
sdk="$(command -v dotnet || true)"
if [ -z "$sdk" ]; then sdk="$PWD/.build/windows-sdk/dotnet/dotnet"; fi
if [ ! -x "$sdk" ]; then
    printf '%s\n' 'Install the .NET 10 SDK and ensure dotnet is on PATH.' >&2
    exit 1
fi

mkdir -p .build dist/windows
stage="$(mktemp -d "$PWD/.build/windows-release.XXXXXX")"
for arch in arm64 x64; do
    "$sdk" publish Windows/Snowglow.csproj -c Release -r "win-$arch" --self-contained true \
        -p:PublishSingleFile=true -p:IncludeNativeLibrariesForSelfExtract=true \
        -p:EnableCompressionInSingleFile=true -p:DebugType=None -p:DebugSymbols=false \
        -o "$stage/$arch"
    test -s "$stage/$arch/Snowglow.exe"
done

mv -f "$stage/arm64/Snowglow.exe" dist/windows/Snowglow-Windows-ARM64.exe
mv -f "$stage/x64/Snowglow.exe" dist/windows/Snowglow-Windows-x64.exe
printf '%s\n' "$PWD/dist/windows/Snowglow-Windows-ARM64.exe" "$PWD/dist/windows/Snowglow-Windows-x64.exe"
