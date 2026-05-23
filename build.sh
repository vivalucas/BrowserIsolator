#!/bin/bash
set -e
cd "$(dirname "$0")"

echo "Building BrowserIsolator..."
cd BrowserIsolator
swift build -c release -Xswiftc -target -Xswiftc arm64-apple-macosx13.0
cd ..

echo "Packaging..."
rm -rf BrowserIsolator.app
mkdir -p BrowserIsolator.app/Contents/MacOS
mkdir -p BrowserIsolator.app/Contents/Resources
mkdir -p BrowserIsolator.app/Contents/Frameworks
cp BrowserIsolator/.build/release/BrowserIsolator BrowserIsolator.app/Contents/MacOS/
cp -R BrowserIsolator/.build/arm64-apple-macosx/release/Sparkle.framework BrowserIsolator.app/Contents/Frameworks/
install_name_tool -add_rpath "@loader_path/../Frameworks" BrowserIsolator.app/Contents/MacOS/BrowserIsolator
cp Info.plist BrowserIsolator.app/Contents/
cp AppIcon.icns BrowserIsolator.app/Contents/Resources/
cp -R BrowserIsolator/Resources/*.lproj BrowserIsolator.app/Contents/Resources/
codesign --force --deep --sign - BrowserIsolator.app

echo "Done. Run: open BrowserIsolator.app"
