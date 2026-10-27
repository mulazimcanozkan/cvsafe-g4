#!/usr/bin/env bash
# Generates the Android/iOS/Web platform folders and applies the permissions
# CVSAFE needs (camera, gallery, plain-HTTP to the local AI server).
# Run once from the mobile/ folder:  bash setup.sh
set -e
cd "$(dirname "$0")"

flutter create . --project-name cvsafe_mobile --org com.cvsafe --platforms=android,ios,web

MANIFEST=android/app/src/main/AndroidManifest.xml
if ! grep -q "android.permission.INTERNET" "$MANIFEST"; then
  sed -i.bak 's#<application#<uses-permission android:name="android.permission.INTERNET"/> <application#' "$MANIFEST"
fi
if ! grep -q "usesCleartextTraffic" "$MANIFEST"; then
  sed -i.bak 's#<application#<application android:usesCleartextTraffic="true"#' "$MANIFEST"
fi
rm -f "$MANIFEST.bak"

PLIST=ios/Runner/Info.plist
if [ -f "$PLIST" ] && ! grep -q "NSCameraUsageDescription" "$PLIST"; then
  cat > /tmp/cvsafe_keys.txt <<'KEYS'
	<key>NSCameraUsageDescription</key>
	<string>Take site photos and videos for AI safety analysis.</string>
	<key>NSMicrophoneUsageDescription</key>
	<string>Record video of the site for AI safety analysis.</string>
	<key>NSPhotoLibraryUsageDescription</key>
	<string>Choose site photos and videos for AI safety analysis.</string>
	<key>NSAppTransportSecurity</key>
	<dict><key>NSAllowsArbitraryLoads</key><true/></dict>
KEYS
  # insert the keys before the last </dict>
  last=$(grep -n "</dict>" "$PLIST" | tail -1 | cut -d: -f1)
  { head -n $((last - 1)) "$PLIST"; cat /tmp/cvsafe_keys.txt; tail -n +"$last" "$PLIST"; } > "$PLIST.tmp"
  mv "$PLIST.tmp" "$PLIST"
fi

flutter pub get
echo "Done. Start the AI server, then: flutter run"
