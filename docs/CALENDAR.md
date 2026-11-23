# NYSE calendar rules

This document describes the calendar rules in the widget. All times are New York time (America/New_York). The two versions of the widget (`windows/us-market-widget.ps1` and `linux/us_market_widget.py`) use the same rules.

## Trading sessions

| Session        | Regular day   | Early-close day |
|----------------|---------------|-----------------|
| Pre-market     | 04:00 – 09:30 | 04:00 – 09:30   |
| Regular (open) | 09:30 – 16:00 | 09:30 – 13:00   |
| After-hours    | 16:00 – 20:00 | 13:00 – 17:00   |

The market is closed all day on Saturday, on Sunday, and on holidays. There are no pre-market or after-hours sessions on these days.

## Full-day holidays

The widget calculates these holidays for each year.

| Holiday | Rule |
|---------|------|
| New Year's Day | 1 January. If 1 January is a Sunday, the holiday is Monday 2 January. If 1 January is a Saturday, there is no holiday. The NYSE keeps Friday 31 December open. |
| Martin Luther King Jr. Day | Third Monday of January |
| Presidents' Day | Third Monday of February |
| Good Friday | The Friday before Easter Sunday. The widget calculates Gregorian Easter. |
| Memorial Day | Last Monday of May |
| Juneteenth (from 2022) | 19 June, with the observed-day rule |
| Independence Day | 4 July, with the observed-day rule |
| Labor Day | First Monday of September |
| Thanksgiving | Fourth Thursday of November |
| Christmas | 25 December, with the observed-day rule |

Observed-day rule: if the date is a Saturday, the market closes on the Friday before. If the date is a Sunday, the market closes on the Monday after.

## Early-close days

The market closes at 13:00 on these days. The widget calculates them for each year.

- The day after Thanksgiving.
- 3 July, if it is a weekday and not a holiday. Example: in 2026, 4 July is a Saturday. The holiday is Friday 3 July. There is no early close.
- 24 December, if it is a weekday and not a holiday. Example: in 2027, 25 December is a Saturday. The holiday is Friday 24 December. There is no early close.

## Verification

This is the output of the self-test (`-Test` on Windows, `--test` on Ubuntu) for 2024 to 2028:

```
2024 holidays:      Mon 01 Jan, Mon 15 Jan, Mon 19 Feb, Fri 29 Mar, Mon 27 May, Wed 19 Jun, Thu 04 Jul, Mon 02 Sep, Thu 28 Nov, Wed 25 Dec
2024 early closes:  Wed 03 Jul, Fri 29 Nov, Tue 24 Dec
2025 holidays:      Wed 01 Jan, Mon 20 Jan, Mon 17 Feb, Fri 18 Apr, Mon 26 May, Thu 19 Jun, Fri 04 Jul, Mon 01 Sep, Thu 27 Nov, Thu 25 Dec
2025 early closes:  Thu 03 Jul, Fri 28 Nov, Wed 24 Dec
2026 holidays:      Thu 01 Jan, Mon 19 Jan, Mon 16 Feb, Fri 03 Apr, Mon 25 May, Fri 19 Jun, Fri 03 Jul, Mon 07 Sep, Thu 26 Nov, Fri 25 Dec
2026 early closes:  Fri 27 Nov, Thu 24 Dec
2027 holidays:      Fri 01 Jan, Mon 18 Jan, Mon 15 Feb, Fri 26 Mar, Mon 31 May, Fri 18 Jun, Mon 05 Jul, Mon 06 Sep, Thu 25 Nov, Fri 24 Dec
2027 early closes:  Fri 26 Nov
2028 holidays:      Mon 17 Jan, Mon 21 Feb, Fri 14 Apr, Mon 29 May, Mon 19 Jun, Tue 04 Jul, Mon 04 Sep, Thu 23 Nov, Mon 25 Dec
2028 early closes:  Mon 03 Jul, Fri 24 Nov
```

The output for 2024 and 2025 is the same as the official NYSE calendars. The only difference is the unscheduled closure on 9 January 2025 (see below). Official source: https://www.nyse.com/markets/hours-calendars

## Unscheduled closures

The NYSE sometimes announces a closure that does not follow a rule. Examples: a national day of mourning, or a major event. Recent examples: 9 January 2025 (President Carter), 5 December 2018 (President Bush). Rules cannot predict these dates. You add them manually.

### Ubuntu

1. Click the indicator in the top bar.
2. Click "Edit extra closures…". A text file opens.
3. Add the date on a new line, in the format `YYYY-MM-DD`.
4. Save the file. The widget reads the file automatically. A restart is not necessary.

### Windows

1. Open `windows/us-market-widget.ps1` in a text editor.
2. Add the date to the `$ExtraClosures` list at the top of the file, in the format `'YYYY-MM-DD'`.
3. Save the file.
4. Run `Stop-Widget.cmd`, then run `Start-Widget.cmd`.

Do not add regular holidays to these lists. The widget calculates them.

## Limitations

- The widget covers the NYSE and Nasdaq equities schedule only. Futures, bonds (SIFMA calendar), and options have different hours and holidays.
- The widget does not show trading halts or delayed openings. It shows the schedule, not the live market status.
