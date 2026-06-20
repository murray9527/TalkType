#!/bin/bash
set -euo pipefail

# ─────────────────────────────────────────────────────────
# TalkType release build script
# Produces TalkType.app + TalkType.dmg (unsigned, no Developer ID)
# ─────────────────────────────────────────────────────────

PRODUCT="TalkType"
SCHEME="release"
ARCH=$(uname -m)
BUILD_DIR=".build/${ARCH}-apple-macosx/${SCHEME}"
APP_BUNDLE="${PRODUCT}.app"
APP_PATH="${APP_BUNDLE}/Contents/MacOS/${PRODUCT}"
INFO_PLIST_SRC="Supporting/Info.plist"
DMG_NAME="${PRODUCT}.dmg"

echo "==> Building ${PRODUCT} (${SCHEME}, ${ARCH})…"
swift build -c ${SCHEME}

echo "==> Creating .app bundle…"
rm -rf "${APP_BUNDLE}"
mkdir -p "${APP_BUNDLE}/Contents/MacOS"
mkdir -p "${APP_BUNDLE}/Contents/Resources"

echo "==> Copying binary…"
cp "${BUILD_DIR}/${PRODUCT}" "${APP_BUNDLE}/Contents/MacOS/"

echo "==> Copying Info.plist…"
cp "${INFO_PLIST_SRC}" "${APP_BUNDLE}/Contents/"

echo "==> Copying GRDB privacy bundle…"
if [ -d "${BUILD_DIR}/GRDB_GRDB.bundle" ]; then
    cp -R "${BUILD_DIR}/GRDB_GRDB.bundle" "${APP_BUNDLE}/Contents/Resources/"
fi

echo "==> Creating DMG…"
rm -f "${DMG_NAME}"
hdiutil create -volname "${PRODUCT}" -srcfolder "${APP_BUNDLE}" \
    -ov -format UDZO -fs HFS+ "${DMG_NAME}" >/dev/null

echo ""
echo "✅ Done!"
echo "   App:  ${APP_BUNDLE}"
echo "   DMG:  ${DMG_NAME}"
echo ""
echo "To run without DMG:   open ${APP_BUNDLE}"
echo "To run from terminal: ${APP_BUNDLE}/Contents/MacOS/${PRODUCT}"
