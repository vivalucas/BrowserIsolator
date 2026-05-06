#!/bin/bash
set -e
cd "$(dirname "$0")"

echo "Building BrowserIsolator..."
cd BrowserIsolator
swift build -c release -Xswiftc -target -Xswiftc arm64-apple-macosx26.0
cd ..

echo "Packaging..."
mkdir -p BrowserIsolator.app/Contents/MacOS
mkdir -p BrowserIsolator.app/Contents/Resources
cp BrowserIsolator/.build/release/BrowserIsolator BrowserIsolator.app/Contents/MacOS/
cp Info.plist BrowserIsolator.app/Contents/
cp AppIcon.icns BrowserIsolator.app/Contents/Resources/

echo "Done. Run: open BrowserIsolator.app"