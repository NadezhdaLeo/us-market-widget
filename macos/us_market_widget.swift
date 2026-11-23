// US Market Widget for macOS (menu bar indicator).
//
// Shows the current US stock market phase (NYSE / Nasdaq) in two places:
//   - a small always-on-top window you can drag anywhere (hide/show from the menu bar), and
//   - a colored dot plus a short status text in the menu bar, with details in the drop-down menu.
//
// Phases (ET = New York time):
//   04:00 - 09:30  Pre-market
//   09:30 - 16:00  Regular session (open)
//   16:00 - 20:00  After-hours
//   otherwise      Closed (weekends, NYSE holidays)
// Early-close days: close at 13:00, after-hours until 17:00.
//
// The holiday calendar is computed from the official NYSE rules, so it never
// needs manual updates. Unscheduled closures (e.g. national days of mourning)
// can be added to
//   ~/Library/Application Support/us-market-widget/extra_closures.txt
// one date per line (YYYY-MM-DD).
//
// Build:                 swiftc -O -o us-market-widget us_market_widget.swift
// Self-test without UI:  ./us-market-widget --test

import AppKit
import Foundation

let appID = "us-market-widget"
let et = TimeZone(identifier: "America/New_York")!
let etCal: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = et
    return c
}()

let configDir = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent("Library/Application Support/\(appID)")
let extraClosuresFile = configDir.appendingPathComponent("extra_closures.txt")
let noLabelFlag = configDir.appendingPathComponent("no_label")

// ============================ SETTINGS ======================================

enum Phase: String { case closed = "Closed", pre = "Pre", open = "Open", after = "After" }

let colors: [Phase: NSColor] = [
    .closed: NSColor(red: 138/255, green: 143/255, blue: 152/255, alpha: 1),
    .pre:    NSColor(red: 242/255, green: 176/255, blue: 30/255,  alpha: 1),
    .open:   NSColor(red: 46/255,  green: 204/255, blue: 113/255, alpha: 1),
    .after:  NSColor(red: 59/255,  green: 139/255, blue: 235/255, alpha: 1),
]
let phaseTitle: [Phase: String] = [.closed: "CLOSED", .pre: "PRE-MARKET", .open: "OPEN", .after: "AFTER-HOURS"]
// Name of the transition INTO a phase
let transitionTitle: [Phase: String] = [.pre: "Pre-market", .open: "Open", .after: "Close", .closed: "After-hours end"]
// Blink this many minutes before the regular open
let blinkBeforeOpenMin = 5

// ============================ DATE HELPERS ==================================

struct Day: Hashable, Comparable {
    let y: Int, m: Int, d: Int
    static func < (a: Day, b: Day) -> Bool { (a.y, a.m, a.d) < (b.y, b.m, b.d) }
}

let MON = 0, TUE = 1, WED = 2, THU = 3, FRI = 4, SAT = 5, SUN = 6

func date(_ day: Day, _ hour: Int = 0, _ minute: Int = 0) -> Date {
    etCal.date(from: DateComponents(year: day.y, month: day.m, day: day.d, hour: hour, minute: minute))!
}

func day(of date: Date) -> Day {
    let c = etCal.dateComponents([.year, .month, .day], from: date)
    return Day(y: c.year!, m: c.month!, d: c.day!)
}

/// 0 = Monday ... 6 = Sunday (Python convention)
func weekday(_ day: Day) -> Int {
    (etCal.component(.weekday, from: date(day)) + 5) % 7
}

func addDays(_ d: Day, _ n: Int) -> Day {
    day(of: etCal.date(byAdding: .day, value: n, to: date(d))!)
}

// ============================ NYSE CALENDAR RULES ===========================

/// Gregorian Easter Sunday (anonymous algorithm).
func easter(_ year: Int) -> Day {
    let a = year % 19
    let b = year / 100, c = year % 100
    let d = b / 4, e = b % 4
    let f = (b + 8) / 25
    let g = (b - f + 1) / 3
    let h = (19 * a + b - d - g + 15) % 30
    let i = c / 4, k = c % 4
    let l = (32 + 2 * e + 2 * i - h - k) % 7
    let m = (a + 11 * h + 22 * l) / 451
    let month = (h + l - 7 * m + 114) / 31
    let dd = (h + l - 7 * m + 114) % 31
    return Day(y: year, m: month, d: dd + 1)
}

func nthWeekday(_ year: Int, _ month: Int, _ wd: Int, _ n: Int) -> Day {
    let first = Day(y: year, m: month, d: 1)
    return addDays(first, ((wd - weekday(first)) % 7 + 7) % 7 + 7 * (n - 1))
}

func lastWeekday(_ year: Int, _ month: Int, _ wd: Int) -> Day {
    let nextMonth = month == 12 ? Day(y: year + 1, m: 1, d: 1) : Day(y: year, m: month + 1, d: 1)
    let last = addDays(nextMonth, -1)
    return addDays(last, -(((weekday(last) - wd) % 7 + 7) % 7))
}

/// Saturday -> Friday before, Sunday -> Monday after.
func observed(_ d: Day) -> Day {
    switch weekday(d) {
    case SAT: return addDays(d, -1)
    case SUN: return addDays(d, 1)
    default:  return d
    }
}

var holidayCache: [Int: Set<Day>] = [:]
func nyseHolidays(_ year: Int) -> Set<Day> {
    if let h = holidayCache[year] { return h }
    var h = Set<Day>()
    let ny = Day(y: year, m: 1, d: 1)
    // NYSE rule: when New Year's Day falls on Saturday the market stays open on Friday Dec 31.
    if weekday(ny) == SUN { h.insert(addDays(ny, 1)) } else if weekday(ny) != SAT { h.insert(ny) }
    h.insert(nthWeekday(year, 1, MON, 3))              // Martin Luther King Jr. Day
    h.insert(nthWeekday(year, 2, MON, 3))              // Presidents' Day
    h.insert(addDays(easter(year), -2))                // Good Friday
    h.insert(lastWeekday(year, 5, MON))                // Memorial Day
    if year >= 2022 { h.insert(observed(Day(y: year, m: 6, d: 19))) }  // Juneteenth
    h.insert(observed(Day(y: year, m: 7, d: 4)))       // Independence Day
    h.insert(nthWeekday(year, 9, MON, 1))              // Labor Day
    h.insert(nthWeekday(year, 11, THU, 4))             // Thanksgiving
    h.insert(observed(Day(y: year, m: 12, d: 25)))     // Christmas
    holidayCache[year] = h
    return h
}

var earlyCache: [Int: Set<Day>] = [:]
func nyseEarlyCloses(_ year: Int) -> Set<Day> {
    if let e = earlyCache[year] { return e }
    var e = Set<Day>()
    let hol = nyseHolidays(year)
    e.insert(addDays(nthWeekday(year, 11, THU, 4), 1))  // day after Thanksgiving
    for d in [Day(y: year, m: 7, d: 3), Day(y: year, m: 12, d: 24)] {  // eve of Independence Day / Christmas
        if weekday(d) < SAT && !hol.contains(d) { e.insert(d) }
    }
    earlyCache[year] = e
    return e
}

var extraCacheMtime: Date? = nil
var extraCacheDates = Set<Day>()

/// Unscheduled closures from the user's file; re-read only when the file changes.
func extraClosures() -> Set<Day> {
    guard let attrs = try? FileManager.default.attributesOfItem(atPath: extraClosuresFile.path),
          let mtime = attrs[.modificationDate] as? Date else { return [] }
    if mtime != extraCacheMtime {
        var dates = Set<Day>()
        let text = (try? String(contentsOf: extraClosuresFile, encoding: .utf8)) ?? ""
        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.split(separator: "#", maxSplits: 1).first.map(String.init) ?? ""
            let t = line.trimmingCharacters(in: .whitespaces)
            let parts = t.split(separator: "-")
            if parts.count == 3, let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2]) {
                dates.insert(Day(y: y, m: m, d: d))
            }
        }
        extraCacheMtime = mtime
        extraCacheDates = dates
    }
    return extraCacheDates
}

func isTradingDay(_ d: Day) -> Bool {
    if weekday(d) >= SAT { return false }
    return !nyseHolidays(d.y).contains(d) && !extraClosures().contains(d)
}

func isEarlyClose(_ d: Day) -> Bool { nyseEarlyCloses(d.y).contains(d) }

// ============================ MARKET STATE ==================================

/// Ordered (time, phase) transitions for a date; empty on non-trading days.
func dayBoundaries(_ d: Day) -> [(Date, Phase)] {
    if !isTradingDay(d) { return [] }
    let (closeH, ahEndH) = isEarlyClose(d) ? (13, 17) : (16, 20)
    return [
        (date(d, 4), .pre),
        (date(d, 9, 30), .open),
        (date(d, closeH), .after),
        (date(d, ahEndH), .closed),
    ]
}

func nextTradingDay(_ d: Day) -> Day {
    var n = addDays(d, 1)
    while !isTradingDay(n) { n = addDays(n, 1) }
    return n
}

struct MarketState {
    let phase: Phase
    let nextAt: Date
    let nextPhase: Phase
    let openAt: Date?
    let isHoliday: Bool
    let isEarlyClose: Bool
}

func marketState(_ now: Date) -> MarketState {
    let today = day(of: now)
    var phase = Phase.closed
    var nextAt: Date? = nil
    var nextPhase = Phase.pre
    for (t, p) in dayBoundaries(today) {
        if t <= now { phase = p } else if nextAt == nil { nextAt = t; nextPhase = p }
    }
    if nextAt == nil { nextAt = date(nextTradingDay(today), 4); nextPhase = .pre }

    var openAt: Date? = nil
    var probe = today
    outer: for _ in 0..<15 {
        for (t, p) in dayBoundaries(probe) where p == .open && t > now { openAt = t; break outer }
        probe = addDays(probe, 1)
    }

    return MarketState(
        phase: phase, nextAt: nextAt!, nextPhase: nextPhase, openAt: openAt,
        isHoliday: weekday(today) < SAT && !isTradingDay(today),
        isEarlyClose: isEarlyClose(today))
}

func fmtSpan(_ seconds: TimeInterval) -> String {
    var s = max(0, Int(seconds))
    let d = s / 86400; s %= 86400
    let h = s / 3600; s %= 3600
    let m = s / 60; s %= 60
    if d > 0 { return String(format: "%dd %dh %02dm", d, h, m) }
    if h > 0 { return String(format: "%dh %02dm", h, m) }
    return String(format: "%dm %02ds", m, s)
}

func formatter(_ fmt: String, _ tz: TimeZone) -> DateFormatter {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.timeZone = tz
    f.dateFormat = fmt
    return f
}
let fmtHMEt = formatter("HH:mm", et)
let fmtHMSEt = formatter("HH:mm:ss", et)
let fmtHMLocal = formatter("HH:mm", .current)
let fmtHMSLocal = formatter("HH:mm:ss", .current)
let fmtDayEt = formatter("EEE dd MMM", et)

func fmtWhen(_ t: Date, _ now: Date) -> String {
    var s = "\(fmtHMEt.string(from: t)) ET / \(fmtHMLocal.string(from: t)) local"
    if day(of: t) != day(of: now) { s = "\(fmtDayEt.string(from: t)), \(s)" }
    return s
}

// ============================ SELF-TEST =====================================

func selfTest() {
    let now = Date()
    let fEt = formatter("yyyy-MM-dd HH:mm:ss", et), fLoc = formatter("yyyy-MM-dd HH:mm:ss", .current)
    print("Now ET: \(fEt.string(from: now))   local: \(fLoc.string(from: now))")
    print()
    for y in 2024...2028 {
        print("\(y) holidays:      " + nyseHolidays(y).sorted().map { fmtDayEt.string(from: date($0)) }.joined(separator: ", "))
        print("\(y) early closes:  " + nyseEarlyCloses(y).sorted().map { fmtDayEt.string(from: date($0)) }.joined(separator: ", "))
    }
    print()
    let samples: [Date] = [
        now,
        date(Day(y: 2026, m: 9, d: 23), 3, 59), date(Day(y: 2026, m: 9, d: 23), 4), date(Day(y: 2026, m: 9, d: 23), 9, 29),
        date(Day(y: 2026, m: 9, d: 23), 9, 30), date(Day(y: 2026, m: 9, d: 23), 15, 59), date(Day(y: 2026, m: 9, d: 23), 16),
        date(Day(y: 2026, m: 9, d: 23), 19, 59), date(Day(y: 2026, m: 9, d: 23), 20),
        date(Day(y: 2026, m: 9, d: 25), 21),    // Friday evening -> Monday
        date(Day(y: 2026, m: 11, d: 26), 12),   // Thanksgiving
        date(Day(y: 2026, m: 11, d: 27), 12, 59), date(Day(y: 2026, m: 11, d: 27), 13),  // early close
        date(Day(y: 2026, m: 12, d: 24), 17),   // early close, after-hours end -> Mon 28 Dec
    ]
    let fS = formatter("EEE dd.MM HH:mm", et)
    func pad(_ s: String, _ n: Int) -> String { s.padding(toLength: n, withPad: " ", startingAt: 0) }
    print("\(pad("ET now", 18)) \(pad("Phase", 8)) \(pad("Next", 30)) \(pad("At (ET)", 18)) Flags")
    for s in samples {
        let st = marketState(s)
        var flags: [String] = []
        if st.isHoliday { flags.append("holiday") }
        if st.isEarlyClose { flags.append("early") }
        let nxt = "\(transitionTitle[st.nextPhase]!) in \(fmtSpan(st.nextAt.timeIntervalSince(s)))"
        print("\(fS.string(from: s))     \(pad(st.phase.rawValue, 8)) \(pad(nxt, 30)) \(fS.string(from: st.nextAt))     \(flags.joined(separator: ","))")
    }
}

// ============================ UI ============================================

func dotImage(_ color: NSColor, alpha: CGFloat) -> NSImage {
    let size: CGFloat = 12
    return NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
        color.withAlphaComponent(alpha).setFill()
        NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1)).fill()
        return true
    }
}

let defaults = UserDefaults.standard
let keyWindowShown = "windowShown", keyWindowX = "windowX", keyWindowY = "windowY", keyAlwaysOnTop = "alwaysOnTop"

/// Small always-on-top window, same layout as the Windows version. Drag it anywhere.
final class FloatingPanel: NSPanel {
    static let width: CGFloat = 290
    static let pad: CGFloat = 14
    let dot = NSView()
    let phaseText = NSTextField(labelWithString: "…")
    let nextText = NSTextField(wrappingLabelWithString: "")
    let openText = NSTextField(wrappingLabelWithString: "")
    let noteText = NSTextField(wrappingLabelWithString: "")
    let clockText = NSTextField(labelWithString: "")
    let stack = NSStackView()
    var onHide: (() -> Void)?
    var suppressSave = false

    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: FloatingPanel.width, height: 100),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        title = "US Market"
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        isMovableByWindowBackground = true
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        setAlwaysOnTop(defaults.object(forKey: keyAlwaysOnTop) as? Bool ?? true)

        let root = NSView()
        root.wantsLayer = true
        root.layer?.backgroundColor = NSColor(white: 0.125, alpha: 0.94).cgColor
        root.layer?.cornerRadius = 10
        root.layer?.borderWidth = 1
        root.layer?.borderColor = NSColor(white: 1, alpha: 0.25).cgColor
        contentView = root

        dot.wantsLayer = true
        dot.layer?.cornerRadius = 7
        dot.layer?.backgroundColor = colors[.closed]!.cgColor
        dot.translatesAutoresizingMaskIntoConstraints = false
        dot.widthAnchor.constraint(equalToConstant: 14).isActive = true
        dot.heightAnchor.constraint(equalToConstant: 14).isActive = true

        phaseText.font = .systemFont(ofSize: 17, weight: .semibold)
        phaseText.textColor = .white

        let closeBtn = NSButton(title: "✕", target: self, action: #selector(hideClicked))
        closeBtn.isBordered = false
        closeBtn.font = .systemFont(ofSize: 12)
        closeBtn.contentTintColor = NSColor(white: 1, alpha: 0.5)
        closeBtn.toolTip = "Hide window (use the menu bar icon to show it again)"
        closeBtn.setContentHuggingPriority(.required, for: .horizontal)

        let header = NSStackView(views: [dot, phaseText, NSView(), closeBtn])
        header.orientation = .horizontal
        header.spacing = 10
        header.alignment = .centerY

        let textWidth = FloatingPanel.width - 2 * FloatingPanel.pad
        for (t, size, alpha) in [(nextText, 12.5, 0.88), (openText, 11.5, 0.63), (noteText, 11.5, 1.0), (clockText, 11.0, 0.44)] {
            t.font = .monospacedDigitSystemFont(ofSize: size, weight: .regular)
            t.textColor = NSColor(white: 1, alpha: alpha)
            t.preferredMaxLayoutWidth = textWidth
        }
        noteText.textColor = colors[.pre]!
        noteText.isHidden = true

        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 4
        stack.edgeInsets = NSEdgeInsets(top: 12, left: FloatingPanel.pad, bottom: 12, right: FloatingPanel.pad)
        for v in [header, nextText, openText, noteText, clockText] { stack.addArrangedSubview(v) }
        stack.setCustomSpacing(9, after: header)
        stack.setCustomSpacing(8, after: noteText)
        stack.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            stack.topAnchor.constraint(equalTo: root.topAnchor),
            stack.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            root.widthAnchor.constraint(equalToConstant: FloatingPanel.width),
        ])

        let ctx = NSMenu()
        ctx.autoenablesItems = false
        ctx.addItem(withTitle: "Hide window", action: #selector(hideClicked), keyEquivalent: "").target = self
        let top = ctx.addItem(withTitle: "Always on top", action: #selector(toggleTop(_:)), keyEquivalent: "")
        top.target = self
        top.state = level == .floating ? .on : .off
        ctx.addItem(.separator())
        ctx.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "")
        root.menu = ctx

        restorePosition()
        NotificationCenter.default.addObserver(self, selector: #selector(moved), name: NSWindow.didMoveNotification, object: self)
    }

    func setAlwaysOnTop(_ on: Bool) {
        level = on ? .floating : .normal
        defaults.set(on, forKey: keyAlwaysOnTop)
    }

    @objc func toggleTop(_ sender: NSMenuItem) {
        let on = sender.state != .on
        sender.state = on ? .on : .off
        setAlwaysOnTop(on)
    }

    @objc func hideClicked() { onHide?() }

    @objc func moved() {
        if suppressSave { return }
        defaults.set(Double(frame.origin.x), forKey: keyWindowX)
        defaults.set(Double(frame.maxY), forKey: keyWindowY)   // anchor top-left; height may change
    }

    func restorePosition() {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let area = screen.visibleFrame
        var x = area.maxX - frame.width - 16
        var top = area.minY + frame.height + 16          // default: bottom right corner
        if defaults.object(forKey: keyWindowX) != nil {
            x = CGFloat(defaults.double(forKey: keyWindowX))
            top = CGFloat(defaults.double(forKey: keyWindowY))
        }
        let all = NSScreen.screens.map { $0.frame }.reduce(area) { $0.union($1) }
        x = min(max(x, all.minX), all.maxX - frame.width)
        top = min(max(top, all.minY + frame.height), all.maxY)
        suppressSave = true
        setFrameTopLeftPoint(NSPoint(x: x, y: top))
        suppressSave = false
    }

    /// Re-fit the window height to its content, keeping the top-left corner in place.
    func fitToContent() {
        stack.layoutSubtreeIfNeeded()
        let h = stack.fittingSize.height
        if abs(h - frame.height) > 0.5 {
            let topLeft = NSPoint(x: frame.minX, y: frame.maxY)
            suppressSave = true
            setContentSize(NSSize(width: FloatingPanel.width, height: h))
            setFrameTopLeftPoint(topLeft)
            suppressSave = false
        }
    }
}

final class WidgetController: NSObject {
    let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    let menu = NSMenu()
    let miPhase = NSMenuItem(), miNext = NSMenuItem(), miOpen = NSMenuItem(), miNote = NSMenuItem(), miClock = NSMenuItem()
    let miWindow = NSMenuItem(title: "Show floating window", action: #selector(toggleWindow), keyEquivalent: "")
    let miLabel = NSMenuItem(title: "Show status text in menu bar", action: #selector(toggleLabel), keyEquivalent: "")
    let panel = FloatingPanel()
    var icons: [String: NSImage] = [:]
    var currentIcon = ""
    let titleFont = NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize(for: .small) + 1, weight: .medium)

    override init() {
        super.init()
        try? FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)

        menu.autoenablesItems = false
        for mi in [miPhase, miNext, miOpen, miNote, miClock] { mi.isEnabled = true; menu.addItem(mi) }
        menu.addItem(.separator())

        miWindow.target = self
        menu.addItem(miWindow)

        miLabel.target = self
        miLabel.state = FileManager.default.fileExists(atPath: noLabelFlag.path) ? .off : .on
        menu.addItem(miLabel)

        let miExtra = NSMenuItem(title: "Edit extra closures…", action: #selector(editExtra), keyEquivalent: "")
        miExtra.target = self
        menu.addItem(miExtra)
        menu.addItem(.separator())

        let miQuit = NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(miQuit)

        statusItem.menu = menu
        statusItem.button?.imagePosition = .imageLeading
        statusItem.button?.toolTip = "US Market"

        panel.onHide = { [weak self] in self?.setWindowShown(false) }
        setWindowShown(defaults.object(forKey: keyWindowShown) as? Bool ?? true)
        DistributedNotificationCenter.default().addObserver(
            forName: showNotification, object: nil, queue: .main) { [weak self] _ in self?.setWindowShown(true) }

        refresh()
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.refresh() }
        RunLoop.main.add(timer, forMode: .common)
    }

    func setWindowShown(_ shown: Bool) {
        defaults.set(shown, forKey: keyWindowShown)
        miWindow.state = shown ? .on : .off
        if shown { refresh(); panel.orderFrontRegardless() } else { panel.orderOut(nil) }
    }

    @objc func toggleWindow() { setWindowShown(miWindow.state != .on) }

    @objc func toggleLabel() {
        if miLabel.state == .on {
            miLabel.state = .off
            FileManager.default.createFile(atPath: noLabelFlag.path, contents: nil)
        } else {
            miLabel.state = .on
            try? FileManager.default.removeItem(at: noLabelFlag)
        }
        refresh()
    }

    @objc func editExtra() {
        if !FileManager.default.fileExists(atPath: extraClosuresFile.path) {
            let text = "# Unscheduled NYSE closures, one date per line (YYYY-MM-DD).\n"
                + "# Regular holidays are computed automatically and do not belong here.\n"
                + "# Example:\n# 2025-01-09  # National day of mourning\n"
            try? text.write(to: extraClosuresFile, atomically: true, encoding: .utf8)
        }
        NSWorkspace.shared.open(extraClosuresFile)
    }

    func icon(_ phase: Phase, dim: Bool) -> NSImage {
        let key = "\(phase.rawValue)\(dim ? "-dim" : "")"
        if let img = icons[key] { return img }
        let img = dotImage(colors[phase]!, alpha: dim ? 0.3 : 1)
        icons[key] = img
        return img
    }

    func refresh() {
        let now = Date()
        let st = marketState(now)
        let phase = st.phase
        let until = st.nextAt.timeIntervalSince(now)

        let nextStr = "\(transitionTitle[st.nextPhase]!) in \(fmtSpan(until))  (\(fmtWhen(st.nextAt, now)))"
        var openStr: String? = nil
        if phase != .open, let openAt = st.openAt {
            if st.nextPhase == .open {
                let closeH = isEarlyClose(day(of: openAt)) ? 13 : 16
                openStr = "Regular session until \(fmtWhen(date(day(of: openAt), closeH), now))"
            } else {
                openStr = "Next open: \(fmtWhen(openAt, now))"
            }
        }
        var noteStr: String? = nil
        if st.isHoliday { noteStr = "NYSE holiday today - market closed" }
        else if st.isEarlyClose { noteStr = "Early close today: 13:00 ET, after-hours until 17:00" }
        let clockStr = "New York \(fmtHMSEt.string(from: now))   ·   local \(fmtHMSLocal.string(from: now))"

        // --- menu ---
        miPhase.title = "●  \(phaseTitle[phase]!)"
        miNext.title = nextStr
        miOpen.title = openStr ?? ""; miOpen.isHidden = openStr == nil
        miNote.title = noteStr ?? ""; miNote.isHidden = noteStr == nil
        miClock.title = clockStr

        let blink = st.nextPhase == .open && until > 0 && until <= Double(blinkBeforeOpenMin * 60)
        let second = Calendar.current.component(.second, from: now)
        let dim = blink && second % 2 == 1
        let key = "\(phase.rawValue)\(dim ? "-dim" : "")"
        if key != currentIcon {
            statusItem.button?.image = icon(phase, dim: dim)
            currentIcon = key
        }

        if let button = statusItem.button {
            if miLabel.state == .on {
                let text = " \(phaseTitle[phase]!) · \(transitionTitle[st.nextPhase]!) in \(fmtSpan(until))"
                button.attributedTitle = NSAttributedString(string: text, attributes: [.font: titleFont])
            } else if !button.title.isEmpty {
                button.attributedTitle = NSAttributedString(string: "")
            }
        }

        // --- floating window ---
        if panel.isVisible {
            panel.phaseText.stringValue = phaseTitle[phase]!
            panel.nextText.stringValue = nextStr
            panel.openText.stringValue = openStr ?? ""; panel.openText.isHidden = openStr == nil
            panel.noteText.stringValue = noteStr ?? ""; panel.noteText.isHidden = noteStr == nil
            panel.clockText.stringValue = clockStr
            panel.dot.layer?.backgroundColor = colors[phase]!.cgColor
            panel.dot.layer?.opacity = dim ? 0.25 : 1
            panel.fitToContent()
        }
    }
}

func acquireSingleInstanceLock() -> Bool {
    let lockPath = NSTemporaryDirectory() + "\(appID).lock"
    let fd = open(lockPath, O_WRONLY | O_CREAT, 0o644)
    if fd < 0 { return true }
    return flock(fd, LOCK_EX | LOCK_NB) == 0
}

// ============================ MAIN ==========================================

if CommandLine.arguments.contains("--test") {
    selfTest()
    exit(0)
}

let showNotification = Notification.Name("\(appID).show-window")

if !acquireSingleInstanceLock() {
    // Second launch (e.g. double-click on the app): ask the running instance to show its window.
    DistributedNotificationCenter.default().postNotificationName(showNotification, object: nil, userInfo: nil, deliverImmediately: true)
    print("US Market Widget is already running.")
    exit(0)
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)   // no Dock icon
let controller = WidgetController()
app.run()
