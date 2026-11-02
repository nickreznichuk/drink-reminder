#!/bin/zsh
# Disables autostart and removes the app.
LABEL="com.kolya.drinkreminder"
launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
pkill -x DrinkReminder 2>/dev/null || true
rm -f "$HOME/Library/LaunchAgents/$LABEL.plist"
rm -rf "$HOME/Applications/Drink Reminder.app"
echo "Uninstalled"
