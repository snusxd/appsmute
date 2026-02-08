import AppKit
import Carbon

final class ShortcutRecorderWindowController: NSWindowController {
    private let panel: NSPanel
    private let infoLabel: NSTextField
    private let currentLabel: NSTextField
    private let recordButton: NSButton

    private var isRecording = false
    private var eventMonitor: Any?
    private var onSave: ((UInt32, UInt32) -> Void)?
    private var currentShortcutKeyCode: UInt32?
    private var currentShortcutModifiers: UInt32?

    override init(window: NSWindow?) {
        self.panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 150),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )

        self.infoLabel = NSTextField(labelWithString: "")
        self.currentLabel = NSTextField(labelWithString: "")
        self.recordButton = NSButton(title: "", target: nil, action: nil)

        super.init(window: panel)
        setupUI()
        updateLocalization()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(languageDidChange),
            name: LanguageManager.didChangeNotification,
            object: nil
        )
    }

    required init?(coder: NSCoder) { nil }

    func present(currentKeyCode: UInt32, currentModifiers: UInt32, onSave: @escaping (UInt32, UInt32) -> Void) {
        self.onSave = onSave
        currentShortcutKeyCode = currentKeyCode
        currentShortcutModifiers = currentModifiers

        isRecording = false
        stopMonitoring()
        updateLocalization()

        showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        panel.center()
        panel.makeKeyAndOrderFront(nil)
    }

    private func setupUI() {
        panel.title = L("shortcut_change_title")

        infoLabel.font = NSFont.systemFont(ofSize: 13, weight: .regular)
        currentLabel.font = NSFont.systemFont(ofSize: 13, weight: .regular)

        recordButton.bezelStyle = .rounded
        recordButton.target = self
        recordButton.action = #selector(toggleRecord)

        let stack = NSStackView(views: [infoLabel, currentLabel, recordButton])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false

        let content = NSView()
        content.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: content.centerYAnchor)
        ])

        panel.contentView = content
    }

    @objc private func toggleRecord() {
        isRecording.toggle()
        updateLocalization()
        if isRecording { startMonitoring() } else { stopMonitoring() }
    }

    private func startMonitoring() {
        stopMonitoring()

        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            guard let self else { return event }
            if !self.isRecording { return event }

            if Int(event.keyCode) == kVK_Escape {
                self.isRecording = false
                self.stopMonitoring()
                self.updateLocalization()
                return nil
            }

            let keyCode = UInt32(event.keyCode)
            let modifiers = self.carbonModifiers(from: event.modifierFlags)

            self.isRecording = false
            self.stopMonitoring()
            self.updateLocalization()

            self.onSave?(keyCode, modifiers)
            self.close()
            return nil
        }
    }

    private func stopMonitoring() {
        if let m = eventMonitor {
            NSEvent.removeMonitor(m)
            eventMonitor = nil
        }
    }

    private func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        let f = flags.intersection(.deviceIndependentFlagsMask)
        var m: UInt32 = 0
        if f.contains(.command) { m |= UInt32(cmdKey) }
        if f.contains(.shift) { m |= UInt32(shiftKey) }
        if f.contains(.option) { m |= UInt32(optionKey) }
        if f.contains(.control) { m |= UInt32(controlKey) }
        return m
    }

    @objc private func languageDidChange() {
        updateLocalization()
    }

    private func updateLocalization() {
        panel.title = L("shortcut_change_title")
        infoLabel.stringValue = L("shortcut_info")

        if let keyCode = currentShortcutKeyCode,
           let modifiers = currentShortcutModifiers {
            currentLabel.stringValue = L("shortcut_current_prefix") + ShortcutFormatter.format(keyCode: keyCode, modifiers: modifiers)
        } else {
            currentLabel.stringValue = ""
        }

        recordButton.title = isRecording ? L("shortcut_press_keys") : L("shortcut_record")
    }

    deinit {
        stopMonitoring()
        NotificationCenter.default.removeObserver(self)
    }
}
