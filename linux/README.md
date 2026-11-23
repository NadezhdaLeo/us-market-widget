# US Market Widget for Linux (Ubuntu and KDE Plasma)

On GNOME, the widget is an indicator in the top bar. It shows a colored dot and a short status text. On KDE Plasma, the widget is an icon in the system tray. It shows a colored dot. The status text is in the tooltip. On both desktops, a menu shows the details. The widget shows the current session of the US stock market (NYSE and Nasdaq) and the time to the next session change.

The widget calculates the NYSE holiday calendar from the official rules. You do not update the calendar each year.

## Sessions

All times are New York time (ET).

| Session     | Time            | Color  |
|-------------|-----------------|--------|
| Pre-market  | 04:00 – 09:30   | Yellow |
| Open        | 09:30 – 16:00   | Green  |
| After-hours | 16:00 – 20:00   | Blue   |
| Closed      | All other times | Gray   |

On early-close days, the market closes at 13:00 and after-hours ends at 17:00. Early-close days are the day after Thanksgiving, 3 July, and 24 December, when these dates are weekdays. The market is closed all day on weekends and on NYSE holidays. The system applies daylight saving time automatically.

The dot flashes during the last 5 minutes before the regular open.

## Installation

The widget operates on Ubuntu 22.04 and 24.04 (GNOME) and on KDE Plasma 5 and 6 (for example Kubuntu, Fedora KDE, or Arch Linux).

1. Open a terminal in this folder.
2. Run this command:

```bash
chmod +x widget.sh && ./widget.sh install
```

The command does three things:

- It installs the dependencies: PyGObject, GTK 3, and Ayatana AppIndicator 3. The command asks for your sudo password. The command uses `apt-get` (Ubuntu, Kubuntu, Debian), `dnf` (Fedora), or `pacman` (Arch Linux). On other distributions, install the packages manually.
- It enables autostart at sign-in.
- It starts the widget.

Ubuntu has the GNOME extension "AppIndicator and KStatusNotifierItem Support" enabled by default. Standard GNOME (for example on Fedora or Debian) does not. On these systems, enable the extension first. Without the extension, the indicator is not visible.

KDE Plasma shows the indicator in the system tray. You do not install an extension. If the dot is not visible, click the arrow in the system tray to show the hidden icons.

## Start and stop

Use these commands:

```bash
./widget.sh start
./widget.sh stop
./widget.sh restart
./widget.sh status
```

You can also stop the widget from the menu. Click the dot in the top bar or in the system tray, then click **Quit**.

To enable or disable autostart, run `./widget.sh autostart-on` or `./widget.sh autostart-off`.

To remove the widget, run `./widget.sh uninstall`. Then delete this folder.

Only one instance can run.

## Menu

Click the dot in the top bar or in the system tray to open the menu. The menu has these items:

- The current session.
- The next session change, with the time to it.
- The next regular open.
- New York time and local time.
- **Show status text in panel** — shows or hides the text next to the dot. The dot is always visible. This item is not in the menu on KDE Plasma, because Plasma does not show text next to tray icons. On KDE Plasma, put the pointer on the dot to see the status text.
- **Edit extra closures…** — opens the text file for unscheduled closures. See below.
- **Quit**.

## Calendar

The widget calculates these holidays: New Year's Day, Martin Luther King Jr. Day, Presidents' Day, Good Friday, Memorial Day, Juneteenth, Independence Day, Labor Day, Thanksgiving, and Christmas. It applies the Saturday and Sunday observance rules. It also calculates the three early-close days.

Rules cannot predict an unscheduled closure, for example a national day of mourning. The last one was on 9 January 2025. These closures happen about once in several years. When the NYSE announces one:

1. Click the dot in the top bar or in the system tray.
2. Click **Edit extra closures…**. A text file opens.
3. Add the date on a new line, in the format `YYYY-MM-DD`.
4. Save the file. The widget reads the file automatically. A restart is not necessary.

For more information, see [../docs/CALENDAR.md](../docs/CALENDAR.md).

## Self-test

The self-test does not open the indicator. Run this command:

```bash
./widget.sh test
```

The self-test prints the calculated holidays and early-close days for 2024 to 2028. It also prints a table of sessions for a set of test times (session limits, weekend, holiday, early-close day).

## Files

- `us_market_widget.py` — the widget. The settings (colors, flash minutes) are at the top of the file.
- `widget.sh` — the control script: install, start, stop, autostart.
- `~/.config/us-market-widget/` — the file for unscheduled closures and the panel-text setting.
- `~/.cache/us-market-widget/` — the generated icon files.
