#!/bin/bash
set -euo pipefail
project_dir="$(cd "$(dirname "$0")" && pwd)"
build_root="${DASHLINK_BUILD_ROOT:-$project_dir/.build-local}"
app_path="${DASHLINK_APP_PATH:-$project_dir/../DashLink.app}"
java_root="${JAVA_HOME:?Set JAVA_HOME to a JDK 21 directory.}"
mkdir -p "$build_root/swift-cache"
staging_root="$(mktemp -d "${TMPDIR:-/tmp/}dashlink-build.XXXXXX")"
staged_app="$staging_root/DashLink.app"
mkdir -p "$staged_app/Contents/MacOS" "$staged_app/Contents/Resources/engine/web"

if [ "${DASHLINK_REUSE_RECEIVER:-0}" != 1 ]; then
    (cd "$project_dir/Receiver" && ./gradlew build :server:installDist --no-daemon)
    (cd "$project_dir/Receiver/web" && npm ci --ignore-scripts && npm test && npm run build)
fi

swiftc -swift-version 6 -target arm64-apple-macos15.0 -O -parse-as-library \
    -module-cache-path "$build_root/swift-cache" -o "$staged_app/Contents/MacOS/DashLink" \
    "$project_dir"/Sources/DashLink/*.swift \
    -framework SwiftUI -framework AppKit -framework WebKit -framework CryptoKit -framework IOBluetooth -framework Network
swiftc -O -module-cache-path "$build_root/swift-cache" \
    -o "$staged_app/Contents/Resources/bt-bridge" \
    "$project_dir/Receiver/macos/bt-bridge/main.swift" -framework IOBluetooth
cp "$project_dir/Resources/Info.plist" "$staged_app/Contents/Info.plist"
cp "$project_dir/Resources/AppIcon.icns" "$staged_app/Contents/Resources/AppIcon.icns"
cp "$project_dir/Receiver/LICENSE" "$staged_app/Contents/Resources/PLAYPORT-LICENSE.txt"
cp "$project_dir/NOTICE.txt" "$project_dir/README.md" "$project_dir/RELEASING.md" "$staged_app/Contents/Resources/"
rsync -a "$project_dir/Receiver/server/build/install/server/lib/" "$staged_app/Contents/Resources/engine/lib/"
rsync -a "$project_dir/Receiver/web/dist/" "$staged_app/Contents/Resources/engine/web/dist/"
"$java_root/bin/jlink" \
    --add-modules java.base,java.desktop,java.logging,java.management,java.naming,java.net.http,java.security.jgss,java.instrument,jdk.unsupported,jdk.crypto.ec,jdk.zipfs,jdk.net,jdk.jfr,java.sql \
    --strip-debug --no-header-files --no-man-pages --compress=zip-6 \
    --output "$staged_app/Contents/Resources/engine/runtime"
# Never copy Install.json, a state directory, or an accessory identity into a release.
# Clear only signing-incompatible Finder metadata, never quarantine attributes.
xattr -r -d com.apple.FinderInfo "$staged_app" 2>/dev/null || true
codesign --force --deep --sign - "$staged_app"
codesign --verify --deep --strict "$staged_app"
mkdir -p "$(dirname "$app_path")"
if [ -e "$app_path" ]; then
    backup_root="$(mktemp -d "$build_root/previous-app.XXXXXX")"
    mv "$app_path" "$backup_root/DashLink.app"
fi
ditto --norsrc "$staged_app" "$app_path"
xattr -d com.apple.FinderInfo "$app_path" 2>/dev/null || true
codesign --verify --deep --strict "$app_path"
printf 'Built test app: %s\nClean signed staging copy: %s\n' "$app_path" "$staged_app"
