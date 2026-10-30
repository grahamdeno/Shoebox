#!/bin/sh
# Fetches the two OFL fonts into Shared/Resources/Fonts if they aren't there yet.
set -e
dir="$(cd "$(dirname "$0")/.." && pwd)/Shared/Resources/Fonts"
mkdir -p "$dir"
base=https://raw.githubusercontent.com/google/fonts/main/ofl
[ -f "$dir/DMSerifDisplay-Regular.ttf" ] || curl -fsSL "$base/dmserifdisplay/DMSerifDisplay-Regular.ttf" -o "$dir/DMSerifDisplay-Regular.ttf"
[ -f "$dir/Archivo.ttf" ] || curl -fsSL "$base/archivo/Archivo%5Bwdth%2Cwght%5D.ttf" -o "$dir/Archivo.ttf"
ls -l "$dir"
