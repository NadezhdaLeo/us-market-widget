# US Market Widget

The US Market Widget is a small desktop indicator. It shows the current session of the US stock market (NYSE and Nasdaq). It also shows the time to the next session change.

The widget has three versions. The three versions have the same logic and the same colors. The Linux version operates on GNOME (Ubuntu).

| Platform | Type | Requirements | Folder |
|----------|------|--------------|--------|
| Windows 10 and 11 | Small window on top of other windows, plus a tray icon | None. Uses the PowerShell that is part of Windows. | [`windows/`](windows/) |
| Ubuntu 22.04 and 24.04 | Indicator in the GNOME top bar, with status text and a menu | Python 3 and two apt packages | [`linux/`](linux/) |
| macOS 13 and newer | Small window on top of other windows, plus a menu bar item | Xcode Command Line Tools | [`macos/`](macos/) |

The widget calculates the NYSE holiday calendar from the official rules. You do not update the calendar each year.

## Quick start

### Windows

1. Clone or download this repository.
2. Open the `windows` folder.
3. Double-click `Start-Widget.cmd`.

To stop the widget, double-click `Stop-Widget.cmd`. For more information, see [windows/README.md](windows/README.md).

### Ubuntu

1. Open a terminal in the `linux` folder.
2. Run this command:

```bash
chmod +x widget.sh && ./widget.sh install
```

The command installs the dependencies, enables autostart at sign-in, and starts the widget. For more information, see [linux/README.md](linux/README.md).

### macOS

1. Open a terminal in the `macos` folder.
2. Run this command:

```bash
chmod +x widget.sh && ./widget.sh install
```

The command builds the application, enables autostart at sign-in, and starts the widget. For more information, see [macos/README.md](macos/README.md).

## Sessions

All times are New York time (ET).

| Session     | Time          | Color  |
|-------------|---------------|--------|
| Pre-market  | 04:00 – 09:30 | Yellow |
| Open        | 09:30 – 16:00 | Green  |
| After-hours | 16:00 – 20:00 | Blue   |
| Closed      | All other times | Gray |

The widget shows:

- The current session.
- The time to the next session change, in ET and in your local time.
- The time of the next regular open, when the market is not open.
- A note on early-close days (close at 13:00, after-hours until 17:00).
- A note on holidays.

The indicator flashes during the last 5 minutes before the regular open. The operating system applies daylight saving time for New York and for your location.

## Calendar

The widget calculates all regular NYSE holidays and early-close days from rules. See [docs/CALENDAR.md](docs/CALENDAR.md). The calculated calendars for 2024 and 2025 are the same as the official NYSE calendars.

Rules cannot predict an unscheduled closure, for example a national day of mourning. The last unscheduled closure was on 9 January 2025. You add these dates manually. See [docs/CALENDAR.md](docs/CALENDAR.md).

## Repository layout

```
windows/   us-market-widget.ps1, Start-Widget.cmd, Stop-Widget.cmd, README.md
linux/     us_market_widget.py, widget.sh, README.md
macos/     us_market_widget.swift, widget.sh, README.md
docs/      CALENDAR.md  - calendar rules and unscheduled closures
```

## Self-test

Each version has a self-test. The self-test prints the calculated calendar for 2024 to 2028 and a table of session checks.

Windows:

```powershell
powershell -ExecutionPolicy Bypass -File windows\us-market-widget.ps1 -Test
```

Ubuntu:

```bash
linux/widget.sh test
```

macOS:

```bash
macos/widget.sh test
```

## Related

[grafana-observability-kit](https://github.com/NadezhdaLeo/grafana-observability-kit) uses a simplified version of this session logic to put exchange hours on an on-call dashboard. This widget is the full rule-based NYSE calendar; the kit's panels are weekday hours only.

## Contributing

Keep the three versions the same. The session logic, the labels, and the colors are identical by design. When you change a rule in one version, change the same rule in the other versions. Then run all self-tests. Record the change in [CHANGELOG.md](CHANGELOG.md).

## Credits and license

All three versions and the calendar rules by the repository author.

MIT. See [LICENSE](LICENSE).
