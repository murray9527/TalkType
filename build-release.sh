#!/bin/bash
set -euo pipefail

# ─────────────────────────────────────────────────────────
# TalkType release build script
# App bundle always named "TalkType.app"
# DMG files named TalkType-<arch>.dmg
# ─────────────────────────────────────────────────────────

PRODUCT="TalkType"
SCHEME="release"
ARCHS=("arm64" "x86_64")
INFO_PLIST_SRC="Supporting/Info.plist"
BUILD_ROOT=".build"
APP_BUNDLE="${PRODUCT}.app"

echo "============================================"
echo " TalkType Release Build"
echo " Host arch: $(uname -m)"
echo "============================================"

for ARCH in "${ARCHS[@]}"; do
    echo ""
    echo "────────────────────────────────────────────"
    echo " Building ${PRODUCT} for ${ARCH}…"
    echo "────────────────────────────────────────────"

    BUILD_DIR="${BUILD_ROOT}/${ARCH}-apple-macosx/${SCHEME}"
    DMG_NAME="${PRODUCT}-${ARCH}.dmg"

    # Build
    swift build -c ${SCHEME} --arch ${ARCH} 2>&1 | grep -E "^(Build|error|warning:)" || true

    if [ ! -f "${BUILD_DIR}/${PRODUCT}" ]; then
        echo "❌ Binary not found: ${BUILD_DIR}/${PRODUCT}"
        exit 1
    fi

    echo "==> Packaging ${APP_BUNDLE} (${ARCH})…"
    rm -rf "${APP_BUNDLE}"
    mkdir -p "${APP_BUNDLE}/Contents/MacOS"
    mkdir -p "${APP_BUNDLE}/Contents/Resources"

    cp "${BUILD_DIR}/${PRODUCT}" "${APP_BUNDLE}/Contents/MacOS/"
    cp "${INFO_PLIST_SRC}" "${APP_BUNDLE}/Contents/"

    if [ -d "${BUILD_DIR}/GRDB_GRDB.bundle" ]; then
        cp -R "${BUILD_DIR}/GRDB_GRDB.bundle" "${APP_BUNDLE}/Contents/Resources/"
    fi

    echo "==> Creating ${DMG_NAME}…"
    rm -f "${DMG_NAME}"
    hdiutil create -volname "${PRODUCT} (${ARCH})" \
        -srcfolder "${APP_BUNDLE}" \
        -ov -format UDZO -fs HFS+ \
        "${DMG_NAME}" >/dev/null

    echo "✅ ${DMG_NAME} ($(du -h "${DMG_NAME}" | cut -f1))"
done

# Clean up the last .app bundle
rm -rf "${APP_BUNDLE}"

echo ""
echo "============================================"
echo " Done!"
for ARCH in "${ARCHS[@]}"; do
    echo "   ${PRODUCT}-${ARCH}.dmg"
done
echo "============================================"
