#!/bin/bash
# ci_post_xcodebuild.sh — Xcode Cloud post-build script
# Patches the latest release note with version and build number.
#
# Xcode Cloud env vars:
#   CI_BUILD_NUMBER — auto-incrementing build number
#   CI_ARCHIVE_PATH — path to the .xcarchive
#   CI_XCODEBUILD_EXIT_CODE — 0 on success, non-zero on failure
#
# Custom env vars (set in Xcode Cloud workflow secrets):
#   RELEASE_API_KEY — static API key for write access

# Only patch on successful builds
if [ "$CI_XCODEBUILD_EXIT_CODE" != "0" ]; then
  echo "[Release] Build failed (exit code $CI_XCODEBUILD_EXIT_CODE), skipping release note patch"
  exit 0
fi

# Extract marketing version from the archived Info.plist
VERSION=$(/usr/libexec/PlistBuddy -c "Print :ApplicationProperties:CFBundleShortVersionString" "$CI_ARCHIVE_PATH/Info.plist" 2>/dev/null)

if [ -z "$VERSION" ]; then
  echo "[Release] Warning: Could not extract version from archive, skipping"
  exit 0
fi

API_URL="https://nl-api.lmnorg.workers.dev/v1/releases/latest"

echo "[Release] Patching with version=$VERSION build=$CI_BUILD_NUMBER"

RESPONSE=$(curl -s -w "\n%{http_code}" -X PATCH "$API_URL" \
  -H "x-api-key: $RELEASE_API_KEY" \
  -H "Content-Type: application/json" \
  -d "{\"version\": \"$VERSION\", \"buildNumber\": \"$CI_BUILD_NUMBER\"}")

HTTP_CODE=$(echo "$RESPONSE" | tail -1)
BODY=$(echo "$RESPONSE" | head -1)

echo "[Release] Response ($HTTP_CODE): $BODY"
