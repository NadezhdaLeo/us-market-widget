# Changelog

## 1.1.0 — 2026-10-07

- macOS version: a window on top of other windows and a menu bar item. One Swift file, no dependencies. Control script `widget.sh` builds `US Market Widget.app`. Autostart with a launch agent. One instance only. The window position is saved. Close hides the window; the menu bar item shows it again.
- The macOS version has the same calendar rules, the same self-test, and the same file for unscheduled closures as the other versions.

## 1.0.0 — 2026-09-23

First release.

- Windows version: a window on top of other windows and a tray icon. PowerShell 5.1, no dependencies. Start and Stop launchers. One instance only. The window position is saved. Close hides the window to the tray.
- Ubuntu version: an indicator in the GNOME top bar (Ayatana AppIndicator) with status text and a menu. Autostart with `~/.config/autostart`. Control script `widget.sh`. One instance only.
- Both versions calculate the NYSE holidays and early-close days from rules. The results for 2024 and 2025 are the same as the official NYSE calendars.
- Both versions have a manual list for unscheduled closures: a text file on Ubuntu, `$ExtraClosures` on Windows.
- Both versions have a self-test (`-Test` on Windows, `--test` on Ubuntu).
