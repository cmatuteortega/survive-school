#!/usr/bin/env bash
# Adds the rewarded-ads bridge (android/love-ads) to a love-android checkout.
# The purchases half is love-iap's own action, run beside this in the workflow.
#
#   android/ads.sh <love-android dir> <AdMob app id> [rewarded unit id]
#
# Four edits, each checked, failing loudly when one does not hold: a
# love-android bump that moved what this edits should break the build here,
# not ship an APK that crashes on launch (the ads SDK aborts without an app id).
#
# 1. Copies android/love-ads into app/src/main/cpp/lua-modules/, which
#    love-android builds (libliads.so) and whose Java (LoveAds.java) it compiles.
# 2. Adds the Google Mobile Ads SDK and the User Messaging Platform (consent).
# 3. Adds the liads target to the CMake targets gradle packages.
# 4. Puts the AdMob app id and the rewarded unit in the manifest. With no unit,
#    LoveAds falls back to Google's test unit, so an unconfigured build can only
#    ever show test ads.

set -euo pipefail

LA=${1:?usage: ads.sh <love-android dir> <admob app id> [rewarded unit id]}
APP_ID=${2:?usage: ads.sh <love-android dir> <admob app id> [rewarded unit id]}
UNIT=${3:-}
ADS_VERSION=24.4.0
UMP_VERSION=3.2.0

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
GRADLE="$LA/app/build.gradle"
MANIFEST="$LA/app/src/main/AndroidManifest.xml"
MODULES="$LA/app/src/main/cpp/lua-modules"

[ -f "$GRADLE" ] || { echo "ads: $GRADLE not found" >&2; exit 1; }
[ -f "$MANIFEST" ] || { echo "ads: $MANIFEST not found" >&2; exit 1; }
[ -d "$MODULES" ] || { echo "ads: $MODULES not found -- no lua-modules support" >&2; exit 1; }

# 1. The module
rm -rf "$MODULES/love-ads"
cp -R "$HERE/love-ads" "$MODULES/love-ads"

# 2. The SDKs, replacing any earlier version rather than duplicating it.
perl -ni -e 'print unless /com\.google\.android\.(gms:play-services-ads|ump:user-messaging-platform):/' "$GRADLE"
ADS="$ADS_VERSION" UMP="$UMP_VERSION" perl -0pi -e 's/^dependencies \{\n/dependencies {\n    implementation \x27com.google.android.gms:play-services-ads:$ENV{ADS}\x27\n    implementation \x27com.google.android.ump:user-messaging-platform:$ENV{UMP}\x27\n/m' "$GRADLE"
grep -q "play-services-ads:$ADS_VERSION" "$GRADLE" \
    || { echo "ads: could not add the ads SDK to $GRADLE" >&2; exit 1; }

# 3. The CMake target
grep -q 'targets "love_android"' "$GRADLE" \
    || { echo "ads: no CMake targets line in $GRADLE" >&2; exit 1; }
grep -q '"liads"' "$GRADLE" || perl -pi -e 's/targets "love_android"/targets "love_android", "liads"/' "$GRADLE"
grep -q '"liads"' "$GRADLE" || { echo "ads: could not add the liads target" >&2; exit 1; }

# 4. The manifest, inside <application>.
perl -0pi -e 's/\s*<meta-data android:name="com\.(google\.android\.gms\.ads\.APPLICATION_ID|cmatute\.loveads\.REWARDED_ID)"[^>]*\/>//g' "$MANIFEST"
APP_ID="$APP_ID" UNIT="$UNIT" perl -0pi -e 's#</application>#    <meta-data android:name="com.google.android.gms.ads.APPLICATION_ID" android:value="$ENV{APP_ID}" />\n        <meta-data android:name="com.cmatute.loveads.REWARDED_ID" android:value="$ENV{UNIT}" />\n    </application>#' "$MANIFEST"
grep -q 'com.google.android.gms.ads.APPLICATION_ID' "$MANIFEST" \
    || { echo "ads: could not add the AdMob app id to $MANIFEST" >&2; exit 1; }

echo "ads: love-ads module, ads $ADS_VERSION, UMP $UMP_VERSION, app id $APP_ID, unit ${UNIT:-<test unit>}"
