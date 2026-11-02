#!/bin/zsh
# Builds build/Drink Reminder.app
set -euo pipefail
cd "$(dirname "$0")"
APP="build/Drink Reminder.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp Info.plist "$APP/Contents/Info.plist"
swiftc -O -swift-version 5 -target arm64-apple-macos13.0 \
    -o "$APP/Contents/MacOS/DrinkReminder" Sources/main.swift
codesign --force --sign - "$APP" >/dev/null
echo "Built: $APP"
