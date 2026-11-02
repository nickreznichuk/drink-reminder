# CLAUDE.md

Guidance for Claude Code when working in this repository.

## What this is

A tiny native macOS menu-bar app (Swift, AppKit + SwiftUI) that reminds the user to drink water.
Every hour from 10:00 to 18:00 a black "Dynamic Island"-style toast drops down from the MacBook notch,
above all windows (including full-screen apps and every Space), plays a synthesized chime and stays
until the user clicks "Я попив" ("I drank") or presses Return. While unacknowledged, the sound repeats every 5 minutes.

UI strings are in Ukrainian; everything else (code comments, docs, commit messages) is in English.

## Layout

- `Sources/main.swift`: the whole app, in one file, split by `// MARK:` sections:
  - `Config` / `Layout`: working hours, sound repeat interval, toast geometry
  - `Store`: `UserDefaults` persistence (last shown hour slot, glasses per day, "paused today")
  - `Chime`: synthesizes the sound (two water drops + a bell) into an in-memory WAV played via `NSSound`
  - Toast UI: `ToastModel`, `NotchShape` (outward top flares that blend into the menu bar), `WaterBadge` (animated wave), `ProgressDrops`, `DrankButton`, `ToastView`
  - `ToastController`: borderless non-activating `NSPanel` at `.screenSaver` level, placed at the top-center of the notched screen; spring-expands from notch size, collapses back after confirmation
  - `AppDelegate`: status-bar item + menu, 15 s ticker that shows the toast once per hour slot, wake-from-sleep handling
- `Info.plist`: bundle metadata, `LSUIElement` (no Dock icon)
- `build.sh`: compiles with `swiftc` into `build/Drink Reminder.app` and ad-hoc signs it (no Xcode project)
- `install.sh` / `uninstall.sh`: copy the app to `~/Applications` and register/remove the LaunchAgent `com.kolya.drinkreminder` (start at login, restart on crash, not after "Вийти")

## Commands

```bash
./build.sh                                                        # build only
"build/Drink Reminder.app/Contents/MacOS/DrinkReminder" --preview # run and show the toast immediately
./install.sh                                                      # build + install + enable autostart (restarts the running instance)
./uninstall.sh
```

## Notes

- Requires macOS 13+, Apple Silicon target (`arm64-apple-macos13.0` in `build.sh`). Compiled in Swift 5 language mode to avoid Swift 6 strict-concurrency errors.
- On launch mid-hour the current slot is marked as handled, so the first toast comes at the next full hour.
- On screens without a notch the toast slides out of the top edge instead.
- There are no tests; verify visually with `--preview`. Synthetic clicks (CGEvent) need Accessibility permission, which the terminal usually lacks, so ask the user to click the button.
- After changing code, run `./install.sh` so the autostarted copy in `~/Applications` is updated.
