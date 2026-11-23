# US Market Widget for macOS

The widget shows the current session of the US stock market (NYSE and Nasdaq) and the time to the next session change. It shows this information in two places:

- A small window that stays on top of other windows. You can move the window to any position. The window is visible on all desktops and over full-screen applications.
- A colored dot and a short status text in the menu bar. A menu shows the details.

The window has the same layout as the Windows version. The menu bar item has the same function as the Ubuntu version.

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

## Requirements

- macOS 13 or newer.
- Xcode Command Line Tools. The tools contain the Swift compiler. To install the tools, run this command and follow the instructions on the screen:

```bash
xcode-select --install
```

The widget does not use other software.

## Installation

1. Open a terminal in this folder.
2. Run this command:

```bash
chmod +x widget.sh && ./widget.sh install
```

The command does three things:

- It builds the application `US Market Widget.app` in this folder.
- It enables autostart at sign-in. The command writes a launch agent to `~/Library/LaunchAgents/local.us-market-widget.plist`.
- It starts the widget.

`US Market Widget.app` is a standard macOS application. You can start it with a double-click. You can drag it to the Dock. To put an alias on the Desktop, run `./widget.sh shortcut`.

The widget has no Dock icon.

## Start and stop

Use these commands:

```bash
./widget.sh start
./widget.sh stop
./widget.sh restart
./widget.sh status
```

You can also stop the widget from the menu bar. Click the dot in the menu bar, then click **Quit**. Or right-click the window, then click **Quit**.

To enable or disable autostart, run `./widget.sh autostart-on` or `./widget.sh autostart-off`.

To remove the widget, run `./widget.sh uninstall`. Then delete this folder.

Only one instance can run. When the widget already runs, a second start shows the window and stops.

## Window

- To move the window, drag it with the mouse. The widget saves the position.
- To hide the window, click ✕. The widget continues to run.
- To show the window again, click the dot in the menu bar, then click **Show floating window**.
- Right-click the window to open a menu. The menu has these items: **Hide window**, **Always on top**, **Quit**.

## Menu bar

Click the dot in the menu bar to open the menu. The menu has these items:

- The current session.
- The next session change, with the time to it.
- The next regular open.
- New York time and local time.
- **Show floating window** — shows or hides the window.
- **Show status text in menu bar** — shows or hides the text next to the dot. The dot is always visible.
- **Edit extra closures…** — opens the text file for unscheduled closures. See below.
- **Quit**.

## Calendar

The widget calculates these holidays: New Year's Day, Martin Luther King Jr. Day, Presidents' Day, Good Friday, Memorial Day, Juneteenth, Independence Day, Labor Day, Thanksgiving, and Christmas. It applies the Saturday and Sunday observance rules. It also calculates the three early-close days.

Rules cannot predict an unscheduled closure, for example a national day of mourning. The last one was on 9 January 2025. These closures happen about once in several years. When the NYSE announces one:

1. Click the dot in the menu bar.
2. Click **Edit extra closures…**. A text file opens.
3. Add the date on a new line, in the format `YYYY-MM-DD`.
4. Save the file. The widget reads the file automatically. A restart is not necessary.

For more information, see [../docs/CALENDAR.md](../docs/CALENDAR.md).

## Self-test

The self-test does not open the window or the menu bar item. Run this command:

```bash
./widget.sh test
```

The self-test prints the calculated holidays and early-close days for 2024 to 2028. It also prints a table of sessions for a set of test times (session limits, weekend, holiday, early-close day).

## Files

- `us_market_widget.swift` — the widget. The settings (colors, flash minutes) are at the top of the file.
- `widget.sh` — the control script: build, install, start, stop, autostart, shortcut.
- `US Market Widget.app` — the built application. The build creates it. Git ignores it.
- `~/Library/Application Support/us-market-widget/` — the file for unscheduled closures and the menu-bar-text setting.
- `~/Library/LaunchAgents/local.us-market-widget.plist` — the autostart launch agent.
