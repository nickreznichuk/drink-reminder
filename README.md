# Drink Reminder 💧

A tiny native macOS menu-bar app that reminds you to drink water.

Every hour from 10:00 to 18:00 a toast drops down from the MacBook notch, above all windows (including full-screen apps), with a soft chime.
It stays on screen until you click "Я попив" ("I drank") or press Return. If you don't confirm it, the sound repeats every 5 minutes.

## Usage

- `./install.sh`: build, install to `~/Applications` and enable start at login (LaunchAgent)
- `./uninstall.sh`: disable autostart and remove the app
- `./build.sh`: just build `build/Drink Reminder.app`
- `"build/Drink Reminder.app/Contents/MacOS/DrinkReminder" --preview`: show the toast right away

The drop icon in the menu bar shows how many glasses you've had today and when the next reminder is, and has "Remind now", "Pause for the rest of the day" and "Quit".

Hours and the sound repeat interval live in `Config` at the top of `Sources/main.swift`.

Requires macOS 13+ on Apple Silicon. No Xcode project needed, only the Swift toolchain.
