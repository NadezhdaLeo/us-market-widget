#!/usr/bin/env python3
"""
US Market Widget for Linux: GNOME top-bar indicator.

Shows the current US stock market phase (NYSE / Nasdaq) as a colored dot plus
a short status text in the panel, with details in the drop-down menu.

Phases (ET = New York time):
  04:00 - 09:30  Pre-market
  09:30 - 16:00  Regular session (open)
  16:00 - 20:00  After-hours
  otherwise      Closed (weekends, NYSE holidays)
Early-close days: close at 13:00, after-hours until 17:00.

The holiday calendar is computed from the official NYSE rules, so it never
needs manual updates. Unscheduled closures (e.g. national days of mourning)
can be added to ~/.config/us-market-widget/extra_closures.txt, one date per
line (YYYY-MM-DD).

Dependencies (Ubuntu):  sudo apt install python3-gi gir1.2-ayatanaappindicator3-0.1
Dependencies (Fedora):  sudo dnf install python3-gobject gtk3 libayatana-appindicator-gtk3
Dependencies (Arch):    sudo pacman -S python-gobject gtk3 libayatana-appindicator
Self-test without UI:   python3 us_market_widget.py --test
"""
import datetime as dt
import functools
import os
import struct
import subprocess
import sys
import zlib
from pathlib import Path
from zoneinfo import ZoneInfo

APP_ID = "us-market-widget"
ET = ZoneInfo("America/New_York")

CONFIG_DIR = Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config")) / APP_ID
CACHE_DIR = Path(os.environ.get("XDG_CACHE_HOME", Path.home() / ".cache")) / APP_ID
EXTRA_CLOSURES_FILE = CONFIG_DIR / "extra_closures.txt"
NO_LABEL_FLAG = CONFIG_DIR / "no_label"

# ============================ SETTINGS ======================================

COLORS = {
    "Closed": (138, 143, 152),
    "Pre":    (242, 176, 30),
    "Open":   (46, 204, 113),
    "After":  (59, 139, 235),
}
PHASE_TITLE = {"Closed": "CLOSED", "Pre": "PRE-MARKET", "Open": "OPEN", "After": "AFTER-HOURS"}
# Name of the transition INTO a phase
TRANSITION_TITLE = {"Pre": "Pre-market", "Open": "Open", "After": "Close", "Closed": "After-hours end"}
# Blink this many minutes before the regular open
BLINK_BEFORE_OPEN_MIN = 5

# ============================ NYSE CALENDAR RULES ===========================

MON, TUE, WED, THU, FRI, SAT, SUN = range(7)


def easter(year: int) -> dt.date:
    """Gregorian Easter Sunday (anonymous algorithm)."""
    a = year % 19
    b, c = divmod(year, 100)
    d, e = divmod(b, 4)
    f = (b + 8) // 25
    g = (b - f + 1) // 3
    h = (19 * a + b - d - g + 15) % 30
    i, k = divmod(c, 4)
    l = (32 + 2 * e + 2 * i - h - k) % 7
    m = (a + 11 * h + 22 * l) // 451
    month, day = divmod(h + l - 7 * m + 114, 31)
    return dt.date(year, month, day + 1)


def nth_weekday(year: int, month: int, weekday: int, n: int) -> dt.date:
    first = dt.date(year, month, 1)
    return first + dt.timedelta(days=(weekday - first.weekday()) % 7 + 7 * (n - 1))


def last_weekday(year: int, month: int, weekday: int) -> dt.date:
    nxt = dt.date(year + (month == 12), month % 12 + 1, 1)
    last = nxt - dt.timedelta(days=1)
    return last - dt.timedelta(days=(last.weekday() - weekday) % 7)


def observed(d: dt.date) -> dt.date:
    """Saturday -> Friday before, Sunday -> Monday after."""
    if d.weekday() == SAT:
        return d - dt.timedelta(days=1)
    if d.weekday() == SUN:
        return d + dt.timedelta(days=1)
    return d


@functools.lru_cache(maxsize=None)
def nyse_holidays(year: int) -> frozenset:
    h = set()
    ny = dt.date(year, 1, 1)
    # NYSE rule: when New Year's Day falls on Saturday the market stays open on Friday Dec 31.
    if ny.weekday() == SUN:
        h.add(ny + dt.timedelta(days=1))
    elif ny.weekday() != SAT:
        h.add(ny)
    h.add(nth_weekday(year, 1, MON, 3))          # Martin Luther King Jr. Day
    h.add(nth_weekday(year, 2, MON, 3))          # Presidents' Day
    h.add(easter(year) - dt.timedelta(days=2))   # Good Friday
    h.add(last_weekday(year, 5, MON))            # Memorial Day
    if year >= 2022:
        h.add(observed(dt.date(year, 6, 19)))    # Juneteenth
    h.add(observed(dt.date(year, 7, 4)))         # Independence Day
    h.add(nth_weekday(year, 9, MON, 1))          # Labor Day
    h.add(nth_weekday(year, 11, THU, 4))         # Thanksgiving
    h.add(observed(dt.date(year, 12, 25)))       # Christmas
    return frozenset(h)


@functools.lru_cache(maxsize=None)
def nyse_early_closes(year: int) -> frozenset:
    e = set()
    hol = nyse_holidays(year)
    e.add(nth_weekday(year, 11, THU, 4) + dt.timedelta(days=1))  # day after Thanksgiving
    for d in (dt.date(year, 7, 3), dt.date(year, 12, 24)):       # eve of Independence Day / Christmas
        if d.weekday() < SAT and d not in hol:
            e.add(d)
    return frozenset(e)


_extra_cache = {"mtime": None, "dates": frozenset()}


def extra_closures() -> frozenset:
    """Unscheduled closures from the user's file; re-read only when the file changes."""
    try:
        mtime = EXTRA_CLOSURES_FILE.stat().st_mtime
    except FileNotFoundError:
        return frozenset()
    if mtime != _extra_cache["mtime"]:
        dates = set()
        for line in EXTRA_CLOSURES_FILE.read_text(encoding="utf-8").splitlines():
            line = line.split("#", 1)[0].strip()
            if line:
                try:
                    dates.add(dt.date.fromisoformat(line))
                except ValueError:
                    pass
        _extra_cache.update(mtime=mtime, dates=frozenset(dates))
    return _extra_cache["dates"]


def is_trading_day(d: dt.date) -> bool:
    if d.weekday() >= SAT:
        return False
    return d not in nyse_holidays(d.year) and d not in extra_closures()


def is_early_close(d: dt.date) -> bool:
    return d in nyse_early_closes(d.year)


# ============================ MARKET STATE ==================================

def at(day: dt.date, hour: int, minute: int = 0) -> dt.datetime:
    return dt.datetime.combine(day, dt.time(hour, minute), tzinfo=ET)


def day_boundaries(day: dt.date):
    """Ordered (time, phase) transitions for a date; empty on non-trading days."""
    if not is_trading_day(day):
        return []
    close_h, ah_end_h = (13, 17) if is_early_close(day) else (16, 20)
    return [
        (at(day, 4), "Pre"),
        (at(day, 9, 30), "Open"),
        (at(day, close_h), "After"),
        (at(day, ah_end_h), "Closed"),
    ]


def next_trading_day(day: dt.date) -> dt.date:
    d = day + dt.timedelta(days=1)
    while not is_trading_day(d):
        d += dt.timedelta(days=1)
    return d


def market_state(now: dt.datetime) -> dict:
    today = now.date()
    phase, next_at, next_phase = "Closed", None, None
    for t, p in day_boundaries(today):
        if t <= now:
            phase = p
        elif next_at is None:
            next_at, next_phase = t, p
    if next_at is None:
        next_at, next_phase = at(next_trading_day(today), 4), "Pre"

    open_at = None
    probe = today
    for _ in range(15):
        for t, p in day_boundaries(probe):
            if p == "Open" and t > now:
                open_at = t
                break
        if open_at:
            break
        probe += dt.timedelta(days=1)

    return {
        "phase": phase,
        "next_at": next_at,
        "next_phase": next_phase,
        "open_at": open_at,
        "is_holiday": today.weekday() < SAT and not is_trading_day(today),
        "is_early_close": is_early_close(today),
    }


def fmt_span(delta: dt.timedelta) -> str:
    s = max(0, int(delta.total_seconds()))
    d, s = divmod(s, 86400)
    h, s = divmod(s, 3600)
    m, s = divmod(s, 60)
    if d:
        return f"{d}d {h}h {m:02d}m"
    if h:
        return f"{h}h {m:02d}m"
    return f"{m}m {s:02d}s"


def fmt_when(t: dt.datetime, now: dt.datetime) -> str:
    s = f"{t:%H:%M} ET / {t.astimezone():%H:%M} local"
    if t.date() != now.date():
        s = f"{t:%a %d %b}, {s}"
    return s


# ============================ SELF-TEST =====================================

def self_test():
    now = dt.datetime.now(ET)
    print(f"Now ET: {now:%Y-%m-%d %H:%M:%S}   local: {now.astimezone():%Y-%m-%d %H:%M:%S}")
    print()
    for y in range(2024, 2029):
        print(f"{y} holidays:     ", ", ".join(d.strftime("%a %d %b") for d in sorted(nyse_holidays(y))))
        print(f"{y} early closes: ", ", ".join(d.strftime("%a %d %b") for d in sorted(nyse_early_closes(y))))
    print()
    samples = [
        now,
        at(dt.date(2026, 9, 23), 3, 59), at(dt.date(2026, 9, 23), 4), at(dt.date(2026, 9, 23), 9, 29),
        at(dt.date(2026, 9, 23), 9, 30), at(dt.date(2026, 9, 23), 15, 59), at(dt.date(2026, 9, 23), 16),
        at(dt.date(2026, 9, 23), 19, 59), at(dt.date(2026, 9, 23), 20),
        at(dt.date(2026, 9, 25), 21),    # Friday evening -> Monday
        at(dt.date(2026, 11, 26), 12),   # Thanksgiving
        at(dt.date(2026, 11, 27), 12, 59), at(dt.date(2026, 11, 27), 13),  # early close
        at(dt.date(2026, 12, 24), 17),   # early close, after-hours end -> Mon 28 Dec
    ]
    print(f"{'ET now':<18} {'Phase':<8} {'Next':<30} {'At (ET)':<18} Flags")
    for s in samples:
        st = market_state(s)
        flags = ",".join(f for f, v in (("holiday", st["is_holiday"]), ("early", st["is_early_close"])) if v)
        nxt = f"{TRANSITION_TITLE[st['next_phase']]} in {fmt_span(st['next_at'] - s)}"
        print(f"{s:%a %d.%m %H:%M}     {st['phase']:<8} {nxt:<30} {st['next_at']:%a %d.%m %H:%M}     {flags}")


# ============================ ICONS =========================================

def write_dot_png(path: Path, rgb, size: int = 22, alpha: float = 1.0):
    """Anti-aliased filled circle as RGBA PNG, no external libraries."""
    r, g, b = rgb
    cx = cy = size / 2
    radius = size / 2 - 1.5
    ss = 4
    rows = []
    for y in range(size):
        row = bytearray([0])  # filter type: none
        for x in range(size):
            cov = 0
            for sy in range(ss):
                for sx in range(ss):
                    px = x + (sx + 0.5) / ss - cx
                    py = y + (sy + 0.5) / ss - cy
                    if px * px + py * py <= radius * radius:
                        cov += 1
            a = round(255 * alpha * cov / (ss * ss))
            row += bytes((r, g, b, a))
        rows.append(bytes(row))

    def chunk(tag: bytes, data: bytes) -> bytes:
        return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)

    png = (b"\x89PNG\r\n\x1a\n"
           + chunk(b"IHDR", struct.pack(">IIBBBBB", size, size, 8, 6, 0, 0, 0))
           + chunk(b"IDAT", zlib.compress(b"".join(rows), 9))
           + chunk(b"IEND", b""))
    path.write_bytes(png)


def ensure_icons():
    CACHE_DIR.mkdir(parents=True, exist_ok=True)
    for phase, rgb in COLORS.items():
        for suffix, alpha in (("", 1.0), ("-dim", 0.3)):
            p = CACHE_DIR / f"{APP_ID}-{phase.lower()}{suffix}.png"
            if not p.exists():
                write_dot_png(p, rgb, alpha=alpha)


def icon_name(phase: str, dim: bool = False) -> str:
    return f"{APP_ID}-{phase.lower()}{'-dim' if dim else ''}"


# ============================ UI ============================================

def run_ui():
    import fcntl

    # Single instance
    runtime = Path(os.environ.get("XDG_RUNTIME_DIR", "/tmp"))
    lock = open(runtime / f"{APP_ID}.lock", "w")
    try:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
        print("US Market Widget is already running.")
        return 0

    import gi
    gi.require_version("Gtk", "3.0")
    try:
        gi.require_version("AyatanaAppIndicator3", "0.1")
        from gi.repository import AyatanaAppIndicator3 as AppIndicator
    except ValueError:
        try:
            gi.require_version("AppIndicator3", "0.1")
            from gi.repository import AppIndicator3 as AppIndicator
        except ValueError:
            print("Missing dependency: Ayatana AppIndicator 3. Run: ./widget.sh deps", file=sys.stderr)
            return 1
    from gi.repository import Gtk, GLib

    ensure_icons()
    CONFIG_DIR.mkdir(parents=True, exist_ok=True)

    ind = AppIndicator.Indicator.new_with_path(
        APP_ID, icon_name("Closed"), AppIndicator.IndicatorCategory.APPLICATION_STATUS, str(CACHE_DIR))
    ind.set_status(AppIndicator.IndicatorStatus.ACTIVE)
    ind.set_title("US Market")

    menu = Gtk.Menu()
    mi_phase = Gtk.MenuItem(label="…")
    mi_next = Gtk.MenuItem(label="")
    mi_open = Gtk.MenuItem(label="")
    mi_note = Gtk.MenuItem(label="")
    mi_clock = Gtk.MenuItem(label="")
    for mi in (mi_phase, mi_next, mi_open, mi_note, mi_clock):
        menu.append(mi)
    menu.append(Gtk.SeparatorMenuItem())

    mi_label = Gtk.CheckMenuItem(label="Show status text in panel")
    mi_label.set_active(not NO_LABEL_FLAG.exists())

    def on_label_toggle(item):
        if item.get_active():
            NO_LABEL_FLAG.unlink(missing_ok=True)
        else:
            NO_LABEL_FLAG.touch()
        refresh()

    mi_label.connect("toggled", on_label_toggle)
    menu.append(mi_label)

    mi_extra = Gtk.MenuItem(label="Edit extra closures…")

    def on_extra(_):
        if not EXTRA_CLOSURES_FILE.exists():
            EXTRA_CLOSURES_FILE.write_text(
                "# Unscheduled NYSE closures, one date per line (YYYY-MM-DD).\n"
                "# Regular holidays are computed automatically and do not belong here.\n"
                "# Example:\n# 2025-01-09  # National day of mourning\n", encoding="utf-8")
        subprocess.Popen(["xdg-open", str(EXTRA_CLOSURES_FILE)])

    mi_extra.connect("activate", on_extra)
    menu.append(mi_extra)
    menu.append(Gtk.SeparatorMenuItem())

    mi_quit = Gtk.MenuItem(label="Quit")
    mi_quit.connect("activate", lambda _: Gtk.main_quit())
    menu.append(mi_quit)
    menu.show_all()
    ind.set_menu(menu)

    state = {"icon": None, "tooltip": None}

    def refresh():
        now = dt.datetime.now(ET)
        st = market_state(now)
        phase = st["phase"]
        until = st["next_at"] - now

        mi_phase.set_label(f"●  {PHASE_TITLE[phase]}")
        mi_next.set_label(f"{TRANSITION_TITLE[st['next_phase']]} in {fmt_span(until)}  ({fmt_when(st['next_at'], now)})")

        if phase == "Open" or st["open_at"] is None:
            mi_open.hide()
        else:
            if st["next_phase"] == "Open":
                close_h = 13 if is_early_close(st["open_at"].date()) else 16
                mi_open.set_label(f"Regular session until {fmt_when(at(st['open_at'].date(), close_h), now)}")
            else:
                mi_open.set_label(f"Next open: {fmt_when(st['open_at'], now)}")
            mi_open.show()

        if st["is_holiday"]:
            mi_note.set_label("NYSE holiday today - market closed"); mi_note.show()
        elif st["is_early_close"]:
            mi_note.set_label("Early close today: 13:00 ET, after-hours until 17:00"); mi_note.show()
        else:
            mi_note.hide()

        mi_clock.set_label(f"New York {now:%H:%M:%S}   ·   local {now.astimezone():%H:%M:%S}")

        blink = (st["next_phase"] == "Open" and 0 < until.total_seconds() <= BLINK_BEFORE_OPEN_MIN * 60)
        dim = blink and now.second % 2 == 1
        name = icon_name(phase, dim)
        if name != state["icon"]:
            ind.set_icon_full(name, PHASE_TITLE[phase])
            state["icon"] = name

        status = f"{PHASE_TITLE[phase]} · {TRANSITION_TITLE[st['next_phase']]} in {fmt_span(until)}"
        if status != state["tooltip"]:
            if hasattr(ind, "set_tooltip_full"):
                ind.set_tooltip_full("", "US Market", status)
            else:
                ind.set_title(f"US Market · {status}")
            state["tooltip"] = status

        if mi_label.get_active():
            ind.set_label(status,
                          "AFTER-HOURS · After-hours end in 00h 00m")
        else:
            ind.set_label("", "")
        return True

    refresh()
    GLib.timeout_add_seconds(1, refresh)
    Gtk.main()
    return 0


if __name__ == "__main__":
    if "--test" in sys.argv:
        self_test()
        sys.exit(0)
    sys.exit(run_ui())
