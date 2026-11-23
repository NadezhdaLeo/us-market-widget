# US Market Widget for Windows

The widget is a small window that stays on top of other windows. It also shows an icon in the tray. The window shows the current session of the US stock market (NYSE and Nasdaq) and the time to the next session change.

The widget does not need installation. It uses the PowerShell that is part of Windows 10 and 11.

## Sessions

All times are New York time (ET).

| Session     | Time            | Color  |
|-------------|-----------------|--------|
| Pre-market  | 04:00 – 09:30   | Yellow |
| Open        | 09:30 – 16:00   | Green  |
| After-hours | 16:00 – 20:00   | Blue   |
| Closed      | All other times | Gray   |

On early-close days, the market closes at 13:00 and after-hours ends at 17:00. Early-close days are the day after Thanksgiving, 3 July, and 24 December, when these dates are weekdays. The market is closed all day on weekends and on NYSE holidays. Windows applies daylight saving time automatically.

The widget calculates the NYSE holiday calendar from the official rules. You do not update the calendar each year. Rules cannot predict an unscheduled closure, for example a national day of mourning. See [../docs/CALENDAR.md](../docs/CALENDAR.md).

The indicator flashes during the last 5 minutes before the regular open.

## Start and stop

| Action | Procedure |
|--------|-----------|
| Start | Double-click `Start-Widget.cmd`. |
| Stop | Double-click `Stop-Widget.cmd`. Or right-click the tray icon and click **Exit**. Or right-click the window and click **Exit**. |
| Hide the window. The widget continues to run. | Click ✕ on the window. Or press Alt+F4. Or left-click the tray icon. |
| Show the window again | Left-click the tray icon. Or right-click the tray icon and click **Show / hide**. |

Only one instance can run. If the widget already runs, `Start-Widget.cmd` does nothing.

To check if the widget runs, look for the colored dot in the tray. The tray is at the bottom right of the screen. The dot can be behind the ^ arrow.

To start the widget from PowerShell, run this command:

```powershell
powershell -ExecutionPolicy Bypass -File .\us-market-widget.ps1
```

## Controls

- To move the window, drag it with the left mouse button. The widget saves the position.
- Right-click the window to open a menu. The menu has these items: **Hide to tray**, **Always on top**, **Exit**.
- Right-click the tray icon to open a menu. The menu has these items: **Show / hide**, **Exit**.

## Autostart at Windows sign-in

1. Press Win + R.
2. Type `shell:startup` and press Enter. A folder opens.
3. Right-click `Start-Widget.cmd` and click **Create shortcut**.
4. Move the shortcut into the folder from step 2.

To disable autostart, delete the shortcut from that folder.

## Configuration

The settings are at the top of `us-market-widget.ps1`:

- `$ExtraClosures` — unscheduled closures. This list is normally empty. The widget calculates regular holidays.
- `$Colors` — the colors of the sessions.
- `$BlinkBeforeOpenMinutes` — the number of minutes before the open when the indicator flashes.

After you change a setting, stop the widget and start it again.

## Self-test

The self-test does not open a window. Run this command:

```powershell
powershell -ExecutionPolicy Bypass -File .\us-market-widget.ps1 -Test
```

The self-test prints the calculated holidays and early-close days for 2024 to 2028. It also prints a table of sessions for a set of test times (session limits, weekend, holiday, early-close day).
