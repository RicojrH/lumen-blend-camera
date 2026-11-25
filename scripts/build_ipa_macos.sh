#!/usr/bin/env bash
set -euo pipefail

echo "=== 1. flutter pub get & test ==="
flutter pub get
flutter test

echo "=== 2. Build iOS Release (arm64, Swift Package Manager, no-codesign) ==="
flutter build ios --release --no-codesign

echo "=== 3. Package LumenBlend_iOS_unsigned.ipa ==="
rm -rf build/ipa_payload LumenBlend_iOS_unsigned.ipa
mkdir -p build/ipa_payload/Payload
cp -R build/ios/iphoneos/Runner.app build/ipa_payload/Payload/
(cd build/ipa_payload && zip -qry ../../LumenBlend_iOS_unsigned.ipa Payload)

echo "DONE: $(pwd)/LumenBlend_iOS_unsigned.ipa"
