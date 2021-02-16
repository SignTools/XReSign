# !/bin/bash
set -e

#
#  xresign.sh
#  XReSign
#
#  Copyright © 2017 xndrs. All rights reserved.
#

usage="Usage example:
$(basename "$0") -s path -c certificate [-e entitlements] [-p path] [-b identifier]

where:
-s  path to ipa file which you want to sign/resign
-c  signing certificate Common Name from Keychain
-e  new entitlements to change (Optional)
-p  path to mobile provisioning file (Optional)
-b  bundle identifier (Optional)"

while getopts s:c:e:p:b: option; do
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
    \?)
        echo "invalid option: -$OPTARG" >&2
        echo "$usage" >&2
        exit 1
        ;;
    :)
        echo "missing argument for -$OPTARG" >&2
        echo "$usage" >&2
        exit 1
        ;;
    esac
done

echo "Start resign the app..."

OUTDIR=$(dirname "${SOURCEIPA}")
OUTDIR="$PWD/$OUTDIR"
TMPDIR="$OUTDIR/tmp"
APPDIR="$TMPDIR/app"

mkdir -p "$APPDIR"
if command -v 7z &>/dev/null; then
    echo "Extract app using 7zip"
    7z x "$SOURCEIPA" -o"$APPDIR" >/dev/null 2>&1
else
    echo "Extract app using unzip"
    unzip -qo "$SOURCEIPA" -d "$APPDIR"
fi

APPLICATION=$(ls "$APPDIR/Payload/")

if [ -z "${MOBILEPROV}" ]; then
    echo "Sign process using existing provisioning profile from payload"
else
    echo "Copying provisioning profile into application payload"
    cp "$MOBILEPROV" "$APPDIR/Payload/$APPLICATION/embedded.mobileprovision"
fi

echo "Extract entitlements from mobileprovisioning"
if [ -z "${ENTITLEMENTS}" ]; then
    security cms -D -i "$APPDIR/Payload/$APPLICATION/embedded.mobileprovision" >"$TMPDIR/provisioning.plist"
    /usr/libexec/PlistBuddy -x -c 'Print:Entitlements' "$TMPDIR/provisioning.plist" >"$TMPDIR/entitlements.plist"
else
    cp ${ENTITLEMENTS} "$TMPDIR/entitlements.plist"
    echo "${ENTITLEMENTS}"
fi

if [ -z "${BUNDLEID}" ]; then
    echo "Sign process using existing bundle identifier from payload"
else
    echo "Changing BundleID with : $BUNDLEID"
    /usr/libexec/PlistBuddy -c "Set:CFBundleIdentifier $BUNDLEID" "$APPDIR/Payload/$APPLICATION/Info.plist"
fi

APP_ID=$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$APPDIR/Payload/$APPLICATION/Info.plist")
TEAM_ID=$(/usr/libexec/PlistBuddy -c 'Print com.apple.developer.team-identifier' "$TMPDIR/entitlements.plist")

echo "Get list of components and resign with certificate: $DEVELOPER"
find -d "$APPDIR" \( -name "*.app" -o -name "*.appex" -o -name "*.framework" -o -name "*.dylib" \) >"$TMPDIR/components.txt"

var=$((0))
while IFS='' read -r line || [[ -n "$line" ]]; do
    if [[ ! -z "${BUNDLEID}" ]] && [[ "$line" == *".appex"* ]]; then
        echo "Changing .appex BundleID with : $BUNDLEID.extra$var"
        /usr/libexec/PlistBuddy -c "Set:CFBundleIdentifier $BUNDLEID.extra$var" "$line/Info.plist"
    fi
    cp "$TMPDIR/entitlements.plist" "$TMPDIR/entitlements$var.plist"
    if [[ -f "$line/Info.plist" ]]; then
        EXTRA_ID=$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$line/Info.plist")
    else
        EXTRA_ID="$APP_ID.extra$var"
    fi
    /usr/libexec/PlistBuddy -c "Set:application-identifier $TEAM_ID.$EXTRA_ID" "$TMPDIR/entitlements$var.plist"
    /usr/bin/codesign --continue -f -s "$DEVELOPER" --entitlements "$TMPDIR/entitlements$var.plist" "$line"
    var=$((var + 1))
done <"$TMPDIR/components.txt"

echo "Creating the signed ipa"
cd "$APPDIR"
filename=$(basename "$APPLICATION")
filename="${filename%.*}-xresign.ipa"
zip -qr "../$filename" *
cd ..
mv "$filename" "$OUTDIR"

echo "Clear temporary files"
rm -rf "$APPDIR"
rm "$TMPDIR/components.txt"
rm "$TMPDIR/provisioning.plist"
rm "$TMPDIR/entitlements"*".plist"
if [ -z "$(ls -A "$TMPDIR")" ]; then
    rm -d "$TMPDIR"
fi

echo "XReSign FINISHED"
