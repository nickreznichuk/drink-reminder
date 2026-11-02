import AppKit
import SwiftUI

// MARK: - Config

enum Config {
    static let firstHour = 10          // first reminder at 10:00
    static let lastHour = 18           // last reminder at 18:00
    static let repeatSound: TimeInterval = 5 * 60   // replay the sound while the toast is unconfirmed
    static var slotsPerDay: Int { lastHour - firstHour + 1 }
}

enum Layout {
    static let cardWidth: CGFloat = 440
    static let bodyHeight: CGFloat = 150   // height below the notch
    static let flare: CGFloat = 12         // top "ears" that blend into the menu bar
    static let shadowPad: CGFloat = 44
}

let phrases = [
    "Кілька ковтків — і голова знову ясна.",
    "Твій мозок майже на 75% вода. Підзаряди його.",
    "Невелика пауза: склянка води вже чекає.",
    "Вода — найпростіший спосіб почуватися краще.",
    "Попий водички, а потім — далі до справ.",
    "Тіло скаже дякую. Навіть якщо мовчки.",
]

// MARK: - Storage

final class Store {
    private let d = UserDefaults.standard

    static func dayKey(_ date: Date = Date()) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    static func slotKey(_ date: Date = Date()) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd-HH"
        return f.string(from: date)
    }

    var lastSlot: String? {
        get { d.string(forKey: "lastSlot") }
        set { d.set(newValue, forKey: "lastSlot") }
    }

    var drankToday: Int {
        get { d.integer(forKey: "drank-" + Store.dayKey()) }
        set { d.set(newValue, forKey: "drank-" + Store.dayKey()) }
    }

    var pausedToday: Bool {
        get { d.string(forKey: "pausedDay") == Store.dayKey() }
        set { d.set(newValue ? Store.dayKey() : nil, forKey: "pausedDay") }
    }
}

// MARK: - Sound

/// Synthesized sound: two water drops and a soft bell. Rendered once into an in-memory WAV.
enum Chime {
    static let sound: NSSound? = NSSound(data: wav(synth(), rate: 44_100))

    static func play() {
        sound?.stop()
        sound?.play()
    }

    private static func synth() -> [Float] {
        let sr = 44_100.0
        var out = [Float](repeating: 0, count: Int(sr * 2.0))

        func drop(at start: Double, from f0: Double, to f1: Double, length: Double, amp: Double) {
            let s = Int(start * sr)
            var phase = 0.0
            for i in 0..<Int(length * sr) {
                let t = Double(i) / sr
                let f = f0 * pow(f1 / f0, t / length)
                phase += 2 * .pi * f / sr
                let env = min(1, t / 0.004) * exp(-t * 20)
                out[s + i] += Float(sin(phase) * env * amp)
            }
        }

        func bell(at start: Double, freq f: Double, amp: Double) {
            let s = Int(start * sr)
            for i in 0..<(out.count - s) {
                let t = Double(i) / sr
                let env = min(1, t / 0.006) * exp(-t * 3.0)
                let v = sin(2 * .pi * f * t)
                    + 0.30 * sin(2 * .pi * 2 * f * t) * exp(-t * 3)
                    + 0.10 * sin(2 * .pi * 3.01 * f * t) * exp(-t * 6)
                out[s + i] += Float(v * env * amp)
            }
        }

        drop(at: 0.00, from: 380, to: 1150, length: 0.17, amp: 0.55)
        drop(at: 0.15, from: 520, to: 1500, length: 0.15, amp: 0.40)
        bell(at: 0.32, freq: 880.0, amp: 0.20)    // A5
        bell(at: 0.46, freq: 1318.5, amp: 0.15)   // E6

        let peak = out.map(abs).max() ?? 1
        let fade = Int(0.15 * sr)
        for i in out.indices {
            out[i] = out[i] / peak * 0.8
            let fromEnd = out.count - i
            if fromEnd < fade { out[i] *= Float(fromEnd) / Float(fade) }
        }
        return out
    }

    private static func wav(_ samples: [Float], rate: Int) -> Data {
        var data = Data()
        func put<T: FixedWidthInteger>(_ v: T) { withUnsafeBytes(of: v.littleEndian) { data.append(contentsOf: $0) } }
        let bytes = samples.count * 2
        data.append(contentsOf: Array("RIFF".utf8)); put(UInt32(36 + bytes))
        data.append(contentsOf: Array("WAVE".utf8))
        data.append(contentsOf: Array("fmt ".utf8)); put(UInt32(16)); put(UInt16(1)); put(UInt16(1))
        put(UInt32(rate)); put(UInt32(rate * 2)); put(UInt16(2)); put(UInt16(16))
        data.append(contentsOf: Array("data".utf8)); put(UInt32(bytes))
        for s in samples { put(Int16(max(-1, min(1, s)) * Float(Int16.max))) }
        return data
    }
}

// MARK: - Toast UI

final class ToastModel: ObservableObject {
    @Published var expanded = false
    @Published var done = false
    @Published var drank: Int
    let notch: CGSize
    let phrase = phrases.randomElement()!
    let timeText: String
    var onDrank: () -> Void = {}

    init(drank: Int, notch: CGSize) {
        self.drank = drank
        self.notch = notch
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        timeText = f.string(from: Date())
    }

    var cardHeight: CGFloat { notch.height + Layout.bodyHeight }
}

/// Island shape: top corners flare outward (blending into the menu bar/notch), bottom corners are rounded.
struct NotchShape: Shape {
    var flare: CGFloat
    var radius: CGFloat

    var animatableData: CGFloat {
        get { radius }
        set { radius = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        let f = min(flare, h / 2)
        let r = max(0, min(radius, (w - 2 * f) / 2, h - f))
        var p = Path()
        p.move(to: CGPoint(x: 0, y: 0))
        p.addQuadCurve(to: CGPoint(x: f, y: f), control: CGPoint(x: f, y: 0))
        p.addLine(to: CGPoint(x: f, y: h - r))
        p.addQuadCurve(to: CGPoint(x: f + r, y: h), control: CGPoint(x: f, y: h))
        p.addLine(to: CGPoint(x: w - f - r, y: h))
        p.addQuadCurve(to: CGPoint(x: w - f, y: h - r), control: CGPoint(x: w - f, y: h))
        p.addLine(to: CGPoint(x: w - f, y: f))
        p.addQuadCurve(to: CGPoint(x: w, y: 0), control: CGPoint(x: w - f, y: 0))
        p.closeSubpath()
        return p
    }
}

struct Wave: Shape {
    var phase: Double
    var level: Double
    var amplitude: Double

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let base = rect.height * (1 - level)
        p.move(to: CGPoint(x: 0, y: rect.height))
        for x in stride(from: 0.0, through: rect.width, by: 1) {
            let y = base + sin(x / rect.width * 2 * .pi + phase) * amplitude
            p.addLine(to: CGPoint(x: x, y: y))
        }
        p.addLine(to: CGPoint(x: rect.width, y: rect.height))
        p.closeSubpath()
        return p
    }
}

let aqua = Color(red: 0.30, green: 0.82, blue: 1.0)
let deepBlue = Color(red: 0.12, green: 0.45, blue: 1.0)

struct WaterBadge: View {
    var body: some View {
        TimelineView(.animation) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate
            ZStack {
                Circle().fill(Color(white: 0.11))
                Wave(phase: t * 1.4 + 1.8, level: 0.58, amplitude: 4.5)
                    .fill(aqua.opacity(0.35))
                Wave(phase: t * 2.1, level: 0.52, amplitude: 3.5)
                    .fill(LinearGradient(colors: [aqua, deepBlue], startPoint: .top, endPoint: .bottom))
                Image(systemName: "drop.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.95))
                    .shadow(color: deepBlue.opacity(0.6), radius: 4)
                    .offset(y: sin(t * 2.4) * 2)
            }
            .clipShape(Circle())
            .overlay(Circle().strokeBorder(
                LinearGradient(colors: [.white.opacity(0.35), aqua.opacity(0.15)], startPoint: .top, endPoint: .bottom),
                lineWidth: 1.2))
        }
    }
}

struct ProgressDrops: View {
    let drank: Int

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<Config.slotsPerDay, id: \.self) { i in
                Image(systemName: i < drank ? "drop.fill" : "drop")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(i < drank ? aqua : .white.opacity(0.22))
                    .scaleEffect(i == drank - 1 ? 1.15 : 1)
            }
            Text("\(drank) сьогодні")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.45))
                .padding(.leading, 4)
        }
    }
}

struct DrankButton: View {
    let done: Bool
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: done ? "heart.fill" : "checkmark")
                Text(done ? "Молодець!" : "Я попив")
            }
            .font(.system(size: 14, weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(
                Capsule().fill(LinearGradient(
                    colors: done ? [Color(red: 0.3, green: 0.85, blue: 0.55), Color(red: 0.1, green: 0.65, blue: 0.45)]
                                 : [aqua, deepBlue],
                    startPoint: .topLeading, endPoint: .bottomTrailing))
            )
            .overlay(Capsule().strokeBorder(.white.opacity(0.25), lineWidth: 0.8))
            .shadow(color: (done ? Color.green : deepBlue).opacity(hover ? 0.7 : 0.35), radius: hover ? 14 : 8)
            .scaleEffect(hover && !done ? 1.05 : 1)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .keyboardShortcut(.defaultAction)
        .disabled(done)
        .onHover { h in withAnimation(.easeOut(duration: 0.15)) { hover = h } }
    }
}

struct ToastView: View {
    @ObservedObject var model: ToastModel

    var body: some View {
        let cardW = model.expanded ? Layout.cardWidth : model.notch.width
        let cardH = model.expanded ? model.cardHeight : max(model.notch.height, 4)
        let shape = NotchShape(flare: Layout.flare, radius: model.expanded ? 36 : 12)

        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                shape
                    .fill(Color.black)
                    .shadow(color: .black.opacity(model.expanded ? 0.5 : 0), radius: 22, y: 10)
                if model.expanded {
                    content
                        .padding(.top, model.notch.height + 16)
                        .padding(.horizontal, Layout.flare + 26)
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .offset(y: -8))
                                .animation(.easeOut(duration: 0.35).delay(0.15)),
                            removal: .opacity.animation(.easeIn(duration: 0.12))))
                }
            }
            .frame(width: cardW + 2 * Layout.flare, height: cardH)
            .clipShape(shape)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var content: some View {
        VStack(spacing: 16) {
            HStack(spacing: 16) {
                WaterBadge().frame(width: 62, height: 62)
                VStack(alignment: .leading, spacing: 5) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("Час попити води")
                            .font(.system(size: 19, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                        Text(model.timeText)
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.4))
                    }
                    Text(model.phrase)
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.68))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            HStack {
                ProgressDrops(drank: model.drank)
                Spacer()
                DrankButton(done: model.done, action: model.onDrank)
            }
        }
        .frame(width: Layout.cardWidth - 52)
    }
}

// MARK: - Toast window

final class ToastPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

final class FirstMouseHostingView<V: View>: NSHostingView<V> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

final class ToastController {
    private var panel: ToastPanel?
    private var model: ToastModel?
    private var soundTimer: Timer?
    var isShowing: Bool { panel != nil }
    var onDrank: () -> Int = { 0 }

    func show(drank: Int) {
        if panel != nil { Chime.play(); return }

        let screen = NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main ?? NSScreen.screens[0]
        let model = ToastModel(drank: drank, notch: Self.notchSize(of: screen))
        let size = CGSize(width: Layout.cardWidth + 2 * Layout.flare + 2 * Layout.shadowPad,
                          height: model.cardHeight + Layout.shadowPad)
        let frame = NSRect(x: screen.frame.midX - size.width / 2, y: screen.frame.maxY - size.height,
                           width: size.width, height: size.height)

        let panel = ToastPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel],
                               backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.isMovable = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false

        let host = FirstMouseHostingView(rootView: ToastView(model: model))
        if #available(macOS 13.0, *) { host.sizingOptions = [] }
        panel.contentView = host
        panel.setFrame(frame, display: true)
        panel.orderFrontRegardless()
        panel.makeKey()

        model.onDrank = { [weak self] in self?.confirm() }
        self.panel = panel
        self.model = model

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            withAnimation(.spring(response: 0.55, dampingFraction: 0.72)) { model.expanded = true }
        }
        Chime.play()
        soundTimer = Timer.scheduledTimer(withTimeInterval: Config.repeatSound, repeats: true) { _ in Chime.play() }
    }

    private func confirm() {
        guard let model, !model.done else { return }
        soundTimer?.invalidate()
        soundTimer = nil
        let newCount = onDrank()
        withAnimation(.spring(response: 0.35, dampingFraction: 0.6)) {
            model.done = true
            model.drank = newCount
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.9)) { model.expanded = false }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.panel?.orderOut(nil)
                self.panel = nil
                self.model = nil
            }
        }
    }

    private static func notchSize(of screen: NSScreen) -> CGSize {
        let top = screen.safeAreaInsets.top
        if top > 0, let l = screen.auxiliaryTopLeftArea, let r = screen.auxiliaryTopRightArea {
            return CGSize(width: screen.frame.width - l.width - r.width, height: top)
        }
        return CGSize(width: 200, height: 0)   // no notch: slide out of the top edge instead
    }
}

// MARK: - App

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let store = Store()
    private let toast = ToastController()
    private var statusItem: NSStatusItem!
    private var ticker: Timer?
    private let menu = NSMenu()

    func applicationDidFinishLaunching(_ notification: Notification) {
        toast.onDrank = { [store] in
            store.drankToday += 1
            return store.drankToday
        }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let icon = NSImage(systemSymbolName: "drop.fill", accessibilityDescription: "Drink Reminder")
        icon?.isTemplate = true
        statusItem.button?.image = icon
        menu.delegate = self
        statusItem.menu = menu

        // Don't show the toast right at launch mid-hour; wait for the next full hour.
        if Self.inWorkingHours(Date()) { store.lastSlot = Store.slotKey() }

        ticker = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in self?.tick() }
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in self?.tick() }

        if CommandLine.arguments.contains("--preview") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.showNow() }
        }
    }

    static func inWorkingHours(_ date: Date) -> Bool {
        (Config.firstHour...Config.lastHour).contains(Calendar.current.component(.hour, from: date))
    }

    private func tick() {
        let now = Date()
        guard Self.inWorkingHours(now), !store.pausedToday else { return }
        let slot = Store.slotKey(now)
        guard store.lastSlot != slot else { return }
        store.lastSlot = slot
        if !toast.isShowing { showNow() }
    }

    @objc private func showNow() {
        toast.show(drank: store.drankToday)
    }

    @objc private func togglePause() {
        store.pausedToday.toggle()
    }

    private func nextReminder() -> Date? {
        let cal = Calendar.current
        var c = cal.dateInterval(of: .hour, for: Date())!.start.addingTimeInterval(3600)
        for _ in 0..<72 {
            if Self.inWorkingHours(c) && !(store.pausedToday && cal.isDateInToday(c)) { return c }
            c.addTimeInterval(3600)
        }
        return nil
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let f = DateFormatter()
        f.dateFormat = Calendar.current.isDateInToday(nextReminder() ?? Date()) ? "HH:mm" : "завтра о HH:mm"

        let header = NSMenuItem(title: "💧 Сьогодні випито: \(store.drankToday) з \(Config.slotsPerDay)", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        if let next = nextReminder() {
            let item = NSMenuItem(title: "Наступне нагадування: \(f.string(from: next))", action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        }
        menu.addItem(.separator())

        let now = NSMenuItem(title: "Нагадати зараз", action: #selector(showNow), keyEquivalent: "")
        now.target = self
        menu.addItem(now)
        let pause = NSMenuItem(title: "Пауза до кінця дня", action: #selector(togglePause), keyEquivalent: "")
        pause.target = self
        pause.state = store.pausedToday ? .on : .off
        menu.addItem(pause)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Вийти", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
