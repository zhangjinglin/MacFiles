#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

# Build AppIcon.icns from Resources/AppIcon-1024.png.
# The source image must be 1024x1024 PNG with the icon already padded
# to the standard macOS squircle proportions.

SOURCE="Resources/AppIcon-1024.png"
ICONSET="build/AppIcon.iconset"
ICNS="Resources/AppIcon.icns"

[ -f "${SOURCE}" ] || { echo "missing ${SOURCE}"; exit 1; }

rm -rf "${ICONSET}"
mkdir -p "${ICONSET}"

for size in 16 32 128 256 512; do
    sips -z "${size}" "${size}" "${SOURCE}" --out "${ICONSET}/icon_${size}x${size}.png" >/dev/null
    double=$((size * 2))
    sips -z "${double}" "${double}" "${SOURCE}" --out "${ICONSET}/icon_${size}x${size}@2x.png" >/dev/null
done

iconutil -c icns "${ICONSET}" -o "${ICNS}"
rm -rf "${ICONSET}"
echo "Built: ${ICNS}"
