# !/bin/bash
set -e

#
#  xresign.sh
#  XReSign
#
#  Copyright © 2017 xndrs. All rights reserved.
#

usage="Usage: $(basename "$0") -s APP_PATH -c CERT_NAME [-e ENTITLEMENTS_PATH_PATH] [-p PROV_PATH] [-b ID]

-s  path to input app to sign
-c  Common Name of signing certificate in Keychain
-e  new entitlements to use for app (Optional)
-p  path to mobile provisioning file (Optional)
-b  new bundle identifier (Optional)
-a  allow app installation on all devices (Optional)"

while getopts s:c:e:p:b:a option; do
    case "${option}" in
    s)
        SOURCEIPA=${OPTARG}
        ;;
    c)
        DEVELOPER=${OPTARG}
        ;;
    e)
        ENTITLEMENTS=${OPTARG}
        ;;
    p)
        MOBILEPROV=${OPTARG}
        ;;
    b)
        BUNDLEID=${OPTARG}
        ;;
    a)
        ALL_DEVICES=1
        ;;
    \?)
        echo "Invalid option: -$OPTARG" >&2
        echo "$usage" >&2
        exit 1
        ;;
    :)
        echo "Missing argument for -$OPTARG" >&2
        echo "$usage" >&2
        exit 1
        ;;
    esac
done

if [ -z "$SOURCEIPA" ] || [ -z "$DEVELOPER" ]; then
    echo "$usage" >&2
    exit 1
fi

echo "XReSign started"

OUTDIR=$(dirname "${SOURCEIPA}")
OUTDIR="$PWD/$OUTDIR"
TMPDIR="$OUTDIR/tmp"
APPDIR="$TMPDIR/app"

mkdir -p "$APPDIR"
if command -v 7z &>/dev/null; then
    echo "Extracting app using 7zip"
    7z x "$SOURCEIPA" -o"$APPDIR" >/dev/null 2>&1
else
    echo "Extracting app using unzip"
    unzip -qo "$SOURCEIPA" -d "$APPDIR"
fi

APPLICATION=$(ls "$APPDIR/Payload/")

if [ -z "${MOBILEPROV}" ]; then
    echo "Signing using app's existing provisioning profile"
else
    echo "Signing using user-provided provisioning profile"
    cp "$MOBILEPROV" "$APPDIR/Payload/$APPLICATION/embedded.mobileprovision"
fi

echo "Extracting entitlements from provisioning profile"
if [ -z "${ENTITLEMENTS}" ]; then
    security cms -D -i "$APPDIR/Payload/$APPLICATION/embedded.mobileprovision" >"$TMPDIR/provisioning.plist"
    /usr/libexec/PlistBuddy -x -c 'Print:Entitlements' "$TMPDIR/provisioning.plist" >"$TMPDIR/entitlements.plist"
else
    cp ${ENTITLEMENTS} "$TMPDIR/entitlements.plist"
    echo "${ENTITLEMENTS}"
fi

APP_ID=$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$APPDIR/Payload/$APPLICATION/Info.plist")
TEAM_ID=$(/usr/libexec/PlistBuddy -c 'Print com.apple.developer.team-identifier' "$TMPDIR/entitlements.plist")

echo "Building list of app components"
find -d "$APPDIR" \( -name "*.app" -o -name "*.appex" -o -name "*.framework" -o -name "*.dylib" \) >"$TMPDIR/components.txt"

var=$((0))
while IFS='' read -r line || [[ -n "$line" ]]; do
    echo "Processing component $line"

    if [[ "$line" == *".app" ]] || [[ "$line" == *".appex" ]]; then
        cp "$TMPDIR/entitlements.plist" "$TMPDIR/entitlements$var.plist"
        if [[ -n "${BUNDLEID}" ]]; then
            if [[ "$line" == *".app" ]]; then
                EXTRA_ID="$BUNDLEID"
            else
                EXTRA_ID="$BUNDLEID.extra$var"
            fi
            echo "Setting bundle ID to $EXTRA_ID"
            /usr/libexec/PlistBuddy -c "Set:CFBundleIdentifier $EXTRA_ID" "$line/Info.plist"
        fi

        if [[ -n "$ALL_DEVICES" ]]; then
            echo "Patching supported devices"
            /usr/libexec/PlistBuddy -c "Delete :UISupportedDevices" "$line/Info.plist" || true
            # https://developer.apple.com/library/archive/documentation/General/Reference/InfoPlistKeyReference/Articles/iPhoneOSKeys.html
            /usr/libexec/PlistBuddy -c "Delete :UIDeviceFamily" "$line/Info.plist" || true
            /usr/libexec/PlistBuddy -c "Add :UIDeviceFamily array" "$line/Info.plist"
            /usr/libexec/PlistBuddy -c "Add :UIDeviceFamily:0 integer 1" "$line/Info.plist"
            /usr/libexec/PlistBuddy -c "Add :UIDeviceFamily:1 integer 2" "$line/Info.plist"
        fi

        EXTRA_ID=$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$line/Info.plist")
        echo "Signing with application ID $TEAM_ID.$EXTRA_ID"
        /usr/libexec/PlistBuddy -c "Set :application-identifier $TEAM_ID.$EXTRA_ID" "$TMPDIR/entitlements$var.plist"
        /usr/bin/codesign --continue -f -s "$DEVELOPER" --entitlements "$TMPDIR/entitlements$var.plist" "$line"
    else
        echo "Signing with original entitlements"
        /usr/bin/codesign --continue -f -s "$DEVELOPER" "$line"
    fi

    var=$((var + 1))
done <"$TMPDIR/components.txt"

echo "Creating signed IPA"
cd "$APPDIR"
filename=$(basename "$APPLICATION")
filename="${filename%.*}-xresign.ipa"
zip -qr "../$filename" *
cd ..
mv "$filename" "$OUTDIR"

echo "Cleaning temporary files"
rm -rf "$APPDIR"
rm "$TMPDIR/components.txt"
rm "$TMPDIR/provisioning.plist" || true
rm "$TMPDIR/entitlements"*".plist"
if [ -z "$(ls -A "$TMPDIR")" ]; then
    rm -d "$TMPDIR"
fi

echo "XReSign finished"
