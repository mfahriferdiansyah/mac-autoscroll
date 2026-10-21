import AppKit
import Carbon.HIToolbox

enum Mode: String {
    case continuous, step
}

struct Hotkey {
    let title: String
    let keyCode: UInt32
    let modifiers: UInt32
}

let speeds: [(title: String, pixelsPerSecond: Double)] = [
    ("Very slow", 15), ("Slow", 40), ("Medium", 90), ("Fast", 180), ("Very fast", 350),
]
let stepIntervals: [Double] = [1, 2, 3, 5, 10, 20]
let hotkeys: [Hotkey] = [
    Hotkey(title: "⌃⌥S", keyCode: UInt32(kVK_ANSI_S), modifiers: UInt32(controlKey | optionKey)),
    Hotkey(title: "F13", keyCode: UInt32(kVK_F13), modifiers: 0),
    Hotkey(title: "F14", keyCode: UInt32(kVK_F14), modifiers: 0),
    Hotkey(title: "F15", keyCode: UInt32(kVK_F15), modifiers: 0),
]

/// In step mode each step scrolls this many seconds' worth of the chosen speed,
/// spread over `stepAnimation` seconds so it doesn't jump.
let stepSeconds = 4.0
let stepAnimation = 0.3

final class AutoScroll: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let defaults = UserDefaults.standard
    private var statusItem: NSStatusItem!
    private var timer: Timer?
    private var hotkeyRef: EventHotKeyRef?

    private var lastTick = Date()
    private var nextStep = Date()
    private var pendingStep = 0.0
    private var fraction = 0.0

    private var mode: Mode {
        get { Mode(rawValue: defaults.string(forKey: "mode") ?? "") ?? .continuous }
        set { defaults.set(newValue.rawValue, forKey: "mode") }
    }
    private var speedIndex: Int {
        get { defaults.object(forKey: "speed") as? Int ?? 2 }
        set { defaults.set(newValue, forKey: "speed") }
    }
    private var stepInterval: Double {
        get { defaults.object(forKey: "stepInterval") as? Double ?? 3 }
        set { defaults.set(newValue, forKey: "stepInterval") }
    }
    private var hotkeyIndex: Int {
        get { defaults.object(forKey: "hotkey") as? Int ?? 0 }
        set { defaults.set(newValue, forKey: "hotkey") }
    }
    private var scrollUp: Bool {
        get { defaults.bool(forKey: "scrollUp") }
        set { defaults.set(newValue, forKey: "scrollUp") }
    }
    private var isRunning: Bool { timer != nil }

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        updateIcon()
        installHotkeyHandler()
        registerHotkey()
        checkAccessibility(prompt: true)
    }

    // MARK: Scrolling

    @objc func toggle() {
        if isRunning { stop() } else { start() }
    }

    private func start() {
        guard checkAccessibility(prompt: true) else { return }
        lastTick = Date()
        nextStep = Date()
        pendingStep = 0
        fraction = 0
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        updateIcon()
    }

    private func stop() {
        timer?.invalidate()
        timer = nil
        updateIcon()
    }

    private func tick() {
        let now = Date()
        let dt = now.timeIntervalSince(lastTick)
        lastTick = now
        let speed = speeds[speedIndex].pixelsPerSecond

        switch mode {
        case .continuous:
            fraction += speed * dt
        case .step:
            if now >= nextStep {
                pendingStep += speed * stepSeconds
                nextStep = now.addingTimeInterval(stepInterval)
            }
            let amount = min(pendingStep, speed * stepSeconds * dt / stepAnimation)
            pendingStep -= amount
            fraction += amount
        }

        let pixels = Int32(fraction)
        guard pixels != 0 else { return }
        fraction -= Double(pixels)
        let delta = scrollUp ? pixels : -pixels
        CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: delta, wheel2: 0, wheel3: 0)?
            .post(tap: .cghidEventTap)
    }

    @discardableResult
    private func checkAccessibility(prompt: Bool) -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    // MARK: Hotkey

    private func installHotkeyHandler() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, _, userData in
            let app = Unmanaged<AutoScroll>.fromOpaque(userData!).takeUnretainedValue()
            DispatchQueue.main.async { app.toggle() }
            return noErr
        }, 1, &spec, selfPtr, nil)
    }

    private func registerHotkey() {
        if let hotkeyRef { UnregisterEventHotKey(hotkeyRef) }
        hotkeyRef = nil
        let hotkey = hotkeys[hotkeyIndex]
        let id = EventHotKeyID(signature: OSType(0x4153_4352), id: 1) // "ASCR"
        RegisterEventHotKey(hotkey.keyCode, hotkey.modifiers, id, GetApplicationEventTarget(), 0, &hotkeyRef)
    }

    // MARK: Menu

    private func updateIcon() {
        statusItem.button?.image = menuBarImage(running: isRunning)
    }

    /// Mouse with a scroll wheel and two down chevrons; template, so only the alpha matters.
    private func menuBarImage(running: Bool) -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            // Mouse body, inset so the stroke stays inside the bounds.
            let body = NSBezierPath(roundedRect: NSRect(x: 2.75, y: 2.75, width: 7.5, height: 12.5),
                                    xRadius: 4.5, yRadius: 4.5)
            body.lineWidth = 1.5
            NSColor.black.set()
            if running {
                body.fill()
            } else {
                body.stroke()
            }

            // Scroll wheel, knocked out of the filled body while running.
            let wheel = NSBezierPath()
            wheel.move(to: NSPoint(x: 6.5, y: 10))
            wheel.line(to: NSPoint(x: 6.5, y: 13))
            wheel.lineWidth = 1.5
            wheel.lineCapStyle = .round
            if running { NSGraphicsContext.current?.compositingOperation = .destinationOut }
            wheel.stroke()
            if running { NSGraphicsContext.current?.compositingOperation = .sourceOver }

            // Down chevrons.
            let chevrons = NSBezierPath()
            chevrons.lineWidth = 1.5
            chevrons.lineCapStyle = .round
            chevrons.lineJoinStyle = .round
            for dy in [CGFloat(0), -4] {
                chevrons.move(to: NSPoint(x: 12.5, y: 11 + dy))
                chevrons.line(to: NSPoint(x: 14.5, y: 9 + dy))
                chevrons.line(to: NSPoint(x: 16.5, y: 11 + dy))
            }
            chevrons.stroke()

            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "AutoScroll"
        return image
    }

    func menuWillOpen(_ menu: NSMenu) {
        menu.removeAllItems()

        let hotkey = hotkeys[hotkeyIndex].title
        menu.addItem(item(isRunning ? "Stop  (\(hotkey))" : "Start  (\(hotkey))", #selector(toggle)))

        if !checkAccessibility(prompt: false) {
            menu.addItem(item("⚠ Grant Accessibility access…", #selector(openAccessibilitySettings)))
        }
        menu.addItem(.separator())

        menu.addItem(submenu("Mode", [
            item("Fully auto (continuous)", #selector(setMode(_:)), tag: 0, checked: mode == .continuous),
            item("Delay (step every few seconds)", #selector(setMode(_:)), tag: 1, checked: mode == .step),
        ]))
        menu.addItem(submenu("Speed", speeds.enumerated().map { i, speed in
            item(speed.title, #selector(setSpeed(_:)), tag: i, checked: i == speedIndex)
        }))
        menu.addItem(submenu("Step delay", stepIntervals.enumerated().map { i, seconds in
            item("Every \(Int(seconds))s", #selector(setStepInterval(_:)), tag: i, checked: seconds == stepInterval)
        }))
        menu.addItem(submenu("Direction", [
            item("Down", #selector(setDirection(_:)), tag: 0, checked: !scrollUp),
            item("Up", #selector(setDirection(_:)), tag: 1, checked: scrollUp),
        ]))
        menu.addItem(submenu("Hotkey", hotkeys.enumerated().map { i, hotkey in
            item(hotkey.title, #selector(setHotkey(_:)), tag: i, checked: i == hotkeyIndex)
        }))

        menu.addItem(.separator())
        menu.addItem(item("Quit AutoScroll", #selector(NSApplication.terminate(_:)), key: "q"))
    }

    private func item(_ title: String, _ action: Selector, tag: Int = 0, checked: Bool = false, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = action == #selector(NSApplication.terminate(_:)) ? NSApp : self
        item.tag = tag
        item.state = checked ? .on : .off
        return item
    }

    private func submenu(_ title: String, _ items: [NSMenuItem]) -> NSMenuItem {
        let parent = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let menu = NSMenu()
        items.forEach(menu.addItem)
        parent.submenu = menu
        return parent
    }

    @objc private func setMode(_ sender: NSMenuItem) { mode = sender.tag == 0 ? .continuous : .step }
    @objc private func setSpeed(_ sender: NSMenuItem) { speedIndex = sender.tag }
    @objc private func setStepInterval(_ sender: NSMenuItem) { stepInterval = stepIntervals[sender.tag] }
    @objc private func setDirection(_ sender: NSMenuItem) { scrollUp = sender.tag == 1 }
    @objc private func setHotkey(_ sender: NSMenuItem) {
        hotkeyIndex = sender.tag
        registerHotkey()
    }

    @objc private func openAccessibilitySettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }
}

let app = NSApplication.shared
let delegate = AutoScroll()
app.delegate = delegate
app.run()
