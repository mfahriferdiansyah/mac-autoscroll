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

    private var mouseMonitor: Any?
    private var mouseTravel = 0.0
    private var startedAt = Date()
    private var autoStoppedAt = Date.distantPast

    private var speedValueLabel: NSTextField?
    private var delayValueLabel: NSTextField?
    private var delaySlider: NSSlider?
    private var delayRow: NSView?

    private var mode: Mode {
        get { Mode(rawValue: defaults.string(forKey: "mode") ?? "") ?? .continuous }
        set { defaults.set(newValue.rawValue, forKey: "mode") }
    }
    private var pixelsPerSecond: Double {
        get { min(max(defaults.object(forKey: "pixelsPerSecond") as? Double ?? 90, 10), 400) }
        set { defaults.set(newValue, forKey: "pixelsPerSecond") }
    }
    private var stepInterval: Double {
        get { min(max(defaults.object(forKey: "stepInterval") as? Double ?? 3, 1), 30) }
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
    private var stopOnMouse: Bool {
        get { defaults.object(forKey: "stopOnMouse") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "stopOnMouse") }
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
        if isRunning {
            stop()
        } else {
            // A macro button also sends a click; don't let the auto-stop undo that press.
            guard Date().timeIntervalSince(autoStoppedAt) >= 0.4 else { return }
            start()
        }
    }

    private func start() {
        guard checkAccessibility(prompt: true) else { return }
        lastTick = Date()
        nextStep = Date()
        pendingStep = 0
        fraction = 0
        startedAt = Date()
        mouseTravel = 0
        if stopOnMouse {
            mouseMonitor = NSEvent.addGlobalMonitorForEvents(
                matching: [.mouseMoved, .leftMouseDown, .rightMouseDown, .leftMouseDragged, .rightMouseDragged, .scrollWheel]
            ) { [weak self] event in self?.userTookMouse(event) }
        }
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        updateIcon()
    }

    private func stop() {
        if let mouseMonitor { NSEvent.removeMonitor(mouseMonitor) }
        mouseMonitor = nil
        timer?.invalidate()
        timer = nil
        updateIcon()
    }

    private func userTookMouse(_ event: NSEvent) {
        let now = Date()
        // The hotkey press itself and a jittery hand must not stop a fresh scroll.
        guard now.timeIntervalSince(startedAt) > 0.5 else { return }
        switch event.type {
        case .scrollWheel:
            // Ignore the events we post ourselves.
            if event.cgEvent?.getIntegerValueField(.eventSourceUnixProcessID) == Int64(getpid()) { return }
        case .mouseMoved, .leftMouseDragged, .rightMouseDragged:
            mouseTravel += abs(event.deltaX) + abs(event.deltaY)
            guard mouseTravel > 8 else { return }
        default:
            break
        }
        autoStoppedAt = now
        stop()
    }

    private func tick() {
        let now = Date()
        let dt = now.timeIntervalSince(lastTick)
        lastTick = now
        let speed = pixelsPerSecond

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

        let modeControl = NSSegmentedControl(labels: ["Auto", "Delay"], trackingMode: .selectOne,
                                             target: self, action: #selector(setMode(_:)))
        modeControl.controlSize = .small
        modeControl.segmentDistribution = .fillEqually
        modeControl.selectedSegment = mode == .continuous ? 0 : 1
        menu.addItem(row("Mode", modeControl))

        let speedSlider = NSSlider(value: log(pixelsPerSecond), minValue: log(10), maxValue: log(400),
                                   target: self, action: #selector(setSpeed(_:)))
        speedSlider.isContinuous = true
        speedSlider.controlSize = .small
        let speedValue = valueLabel("\(Int(pixelsPerSecond)) px/s")
        speedValueLabel = speedValue
        menu.addItem(row("Speed", speedSlider, value: speedValue))

        let delaySlider = NSSlider(value: stepInterval, minValue: 1, maxValue: 30,
                                   target: self, action: #selector(setStepInterval(_:)))
        delaySlider.isContinuous = true
        delaySlider.controlSize = .small
        delaySlider.isEnabled = mode == .step
        let delayValue = valueLabel("\(Int(stepInterval)) s")
        delayValueLabel = delayValue
        self.delaySlider = delaySlider
        let delayItem = row("Delay", delaySlider, value: delayValue)
        delayItem.view?.alphaValue = mode == .step ? 1 : 0.4
        delayRow = delayItem.view
        menu.addItem(delayItem)

        let directionControl = NSSegmentedControl(labels: ["Down", "Up"], trackingMode: .selectOne,
                                                  target: self, action: #selector(setDirection(_:)))
        directionControl.controlSize = .small
        directionControl.segmentDistribution = .fillEqually
        directionControl.selectedSegment = scrollUp ? 1 : 0
        menu.addItem(row("Direction", directionControl))

        let hotkeyControl = NSSegmentedControl(labels: hotkeys.map(\.title), trackingMode: .selectOne,
                                               target: self, action: #selector(setHotkey(_:)))
        hotkeyControl.controlSize = .small
        hotkeyControl.segmentDistribution = .fillEqually
        hotkeyControl.selectedSegment = hotkeyIndex
        menu.addItem(row("Hotkey", hotkeyControl))

        menu.addItem(.separator())
        menu.addItem(item("Stop when I use the mouse", #selector(toggleStopOnMouse), checked: stopOnMouse))
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

    private func row(_ title: String, _ control: NSView, value: NSTextField? = nil) -> NSMenuItem {
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 280, height: 32))

        let label = NSTextField(labelWithString: title)
        label.font = .menuFont(ofSize: 0)
        label.frame = NSRect(x: 14, y: 8, width: 72, height: 16)
        view.addSubview(label)

        control.frame = NSRect(x: 90, y: 6, width: value == nil ? 182 : 130, height: 20)
        view.addSubview(control)

        if let value {
            value.frame = NSRect(x: 224, y: 8, width: 50, height: 16)
            view.addSubview(value)
        }

        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.view = view
        return item
    }

    private func valueLabel(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        label.textColor = .secondaryLabelColor
        label.alignment = .right
        return label
    }

    @objc private func setMode(_ sender: NSSegmentedControl) {
        mode = sender.selectedSegment == 0 ? .continuous : .step
        let stepEnabled = mode == .step
        delaySlider?.isEnabled = stepEnabled
        delayRow?.alphaValue = stepEnabled ? 1 : 0.4
    }

    @objc private func setSpeed(_ sender: NSSlider) {
        pixelsPerSecond = exp(sender.doubleValue).rounded()
        speedValueLabel?.stringValue = "\(Int(pixelsPerSecond)) px/s"
    }

    @objc private func setStepInterval(_ sender: NSSlider) {
        stepInterval = sender.doubleValue.rounded()
        delayValueLabel?.stringValue = "\(Int(stepInterval)) s"
    }

    @objc private func setDirection(_ sender: NSSegmentedControl) { scrollUp = sender.selectedSegment == 1 }

    @objc private func setHotkey(_ sender: NSSegmentedControl) {
        hotkeyIndex = sender.selectedSegment
        registerHotkey()
    }

    @objc private func toggleStopOnMouse() { stopOnMouse.toggle() }

    @objc private func openAccessibilitySettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }
}

let app = NSApplication.shared
let delegate = AutoScroll()
app.delegate = delegate
app.run()
