#!/bin/sh
# Type-checks the app sources against the Mac Catalyst SDK. Useful without a full Xcode install.
set -e
cd "$(dirname "$0")/.."
SDK=$(xcrun --show-sdk-path --sdk macosx)
IOS="$SDK/System/iOSSupport"
swiftc -typecheck -swift-version 5 \
  -target arm64-apple-ios17.0-macabi \
  -sdk "$SDK" \
  -Fsystem "$IOS/System/Library/Frameworks" \
  -I "$IOS/usr/lib/swift" -L "$IOS/usr/lib/swift" \
  -module-name Fislik -parse-as-library \
  $(find Fislik -name '*.swift' | sort) "$@"
