import AppKit

final class SoundMuteAssets {
    static let shared = SoundMuteAssets()

    let trayMuted: NSImage
    let trayUnmuted: NSImage
    let popupMuted: NSImage
    let popupUnmuted: NSImage

    private init() {
        self.trayMuted = Self.sfSymbol("speaker.slash.fill")
        self.trayUnmuted = Self.sfSymbol("speaker.wave.2.fill")
        self.popupMuted = Self.sfSymbol("speaker.slash.fill", template: false)
        self.popupUnmuted = Self.sfSymbol("speaker.wave.2.fill", template: false)
    }

    private static func sfSymbol(_ name: String, template: Bool = true) -> NSImage {
        let img = NSImage(systemSymbolName: name, accessibilityDescription: nil) ?? NSImage()
        img.isTemplate = template
        return img
    }
}

enum SoundPrefs {
    private static let enabledKey = "sounds.enabled.v1"
    private static let volumeKey = "sounds.volume.v1"

    static var isEnabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: enabledKey) == nil { return true }
            return UserDefaults.standard.bool(forKey: enabledKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }

    static var volume: Float {
        get {
            if UserDefaults.standard.object(forKey: volumeKey) == nil { return 0.6 }
            return UserDefaults.standard.float(forKey: volumeKey)
        }
        set { UserDefaults.standard.set(max(0, min(newValue, 1)), forKey: volumeKey) }
    }
}

final class SoundManager {
    var isEnabled: Bool
    var volume: Float

    init(isEnabled: Bool, volume: Float) {
        self.isEnabled = isEnabled
        self.volume = max(0, min(volume, 1))
    }

    func playOn() {
        play(preferredNames: ["Purr"])
    }

    func playOff() {
        play(preferredNames: ["Tink"])
    }

    private func play(preferredNames: [String]) {
        guard isEnabled else { return }

        if let sound = loadSound(preferredNames: preferredNames) {
            sound.volume = volume
            sound.play()
        } else {
            NSSound.beep()
        }
    }

    private func loadSound(preferredNames: [String]) -> NSSound? {
        for name in preferredNames {
            if let s = loadSystemSoundFile(named: name) { return s }
            if let s = NSSound(named: NSSound.Name(name)) { return s }
        }
        return nil
    }

    private func loadSystemSoundFile(named name: String) -> NSSound? {
        let candidates: [URL] = [
            URL(fileURLWithPath: "/System/Library/Sounds/\(name).aiff"),
            URL(fileURLWithPath: "/System/Library/Sounds/\(name).wav"),
            URL(fileURLWithPath: "/Library/Sounds/\(name).aiff"),
            URL(fileURLWithPath: "/Library/Sounds/\(name).wav")
        ]

        for url in candidates {
            if FileManager.default.fileExists(atPath: url.path),
               let s = NSSound(contentsOf: url, byReference: true) {
                return s
            }
        }
        return nil
    }
}

final class SoundIndicatorWindowController: NSObject {
    enum Status { case on, off }

    private static let minWidth: CGFloat = 96
    private static let windowHeight: CGFloat = 48
    private static let hPad: CGFloat = 14
    private static let vPad: CGFloat = 8

    private let panel: NSPanel
    private let blurView: NSVisualEffectView
    private let imageView: NSImageView
    private let label: NSTextField
    private let stack: NSStackView

    private var hideWorkItem: DispatchWorkItem?
    private var token: UInt64 = 0
    private var currentStatus: Status = .on
    private var appearanceObservation: NSKeyValueObservation?

    override init() {
        self.panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: Self.minWidth, height: Self.windowHeight),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        self.blurView = NSVisualEffectView()
        self.imageView = NSImageView(frame: .zero)
        self.label = NSTextField(labelWithString: "")
        self.stack = NSStackView()

        super.init()
        setupWindow()
        setupUI()
        updateTheme()
        appearanceObservation = NSApp.observe(\.effectiveAppearance, options: [.new]) { [weak self] _, _ in
            self?.updateTheme()
        }
    }

    func show(status: Status) {
        token &+= 1
        let currentToken = token

        hideWorkItem?.cancel()
        hideWorkItem = nil

        apply(status: status)
        moveToCursorScreenTopCenter()
        updateTheme()

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0
            panel.animator().alphaValue = 1
        }

        showAnimated()

        let work = DispatchWorkItem { [weak self] in
            self?.hideAnimated(expectedToken: currentToken)
        }
        hideWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9, execute: work)
    }

    private func setupWindow() {
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true

        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.isMovable = false

        panel.alphaValue = 1
        panel.sharingType = .none
    }

    private func setupUI() {
        blurView.translatesAutoresizingMaskIntoConstraints = false
        blurView.blendingMode = .withinWindow
        blurView.state = .active
        blurView.wantsLayer = true
        blurView.layer?.cornerRadius = 16
        blurView.layer?.masksToBounds = true

        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.imageScaling = .scaleProportionallyDown

        label.translatesAutoresizingMaskIntoConstraints = false
        label.alignment = .center
        label.font = NSFont.systemFont(ofSize: 14, weight: .regular)
        label.lineBreakMode = .byClipping
        label.setContentCompressionResistancePriority(.required, for: .horizontal)

        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 5
        stack.setHuggingPriority(.required, for: .horizontal)

        stack.addArrangedSubview(imageView)
        stack.addArrangedSubview(label)

        let content = NSView()
        content.wantsLayer = true
        content.addSubview(blurView)
        blurView.addSubview(stack)

        NSLayoutConstraint.activate([
            blurView.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            blurView.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            blurView.topAnchor.constraint(equalTo: content.topAnchor),
            blurView.bottomAnchor.constraint(equalTo: content.bottomAnchor),

            stack.centerXAnchor.constraint(equalTo: blurView.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: blurView.centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: blurView.leadingAnchor, constant: Self.hPad),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: blurView.trailingAnchor, constant: -Self.hPad),
            stack.topAnchor.constraint(greaterThanOrEqualTo: blurView.topAnchor, constant: Self.vPad),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: blurView.bottomAnchor, constant: -Self.vPad),

            imageView.widthAnchor.constraint(equalToConstant: 22),
            imageView.heightAnchor.constraint(equalToConstant: 22)
        ])

        panel.contentView = content
    }

    private func apply(status: Status) {
        currentStatus = status
        let assets = SoundMuteAssets.shared
        let image = (status == .off) ? assets.popupMuted : assets.popupUnmuted
        image.isTemplate = true
        imageView.image = image

        label.stringValue = (status == .off) ? L("indicator_off") : L("indicator_on")
        updateWindowSizeForCurrentContent()
        updateColors()
    }

    private func moveToCursorScreenTopCenter() {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main
        guard let screen else { return }

        let frame = screen.visibleFrame
        let size = panel.frame.size
        let margin: CGFloat = 14

        let x = frame.midX - (size.width / 2)
        let y = frame.maxY - size.height - margin
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    private func updateWindowSizeForCurrentContent() {
        stack.layoutSubtreeIfNeeded()
        let fitting = stack.fittingSize
        let width = max(Self.minWidth, fitting.width + (Self.hPad * 2))
        panel.setContentSize(NSSize(width: width, height: Self.windowHeight))
    }

    private func showAnimated() {
        if !panel.isVisible {
            panel.alphaValue = 0
            panel.orderFrontRegardless()
        }

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.10
            panel.animator().alphaValue = 1
        }
    }

    private func hideAnimated(expectedToken: UInt64) {
        guard expectedToken == token else { return }

        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.12
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            guard let self else { return }
            guard expectedToken == self.token else { return }
            self.panel.orderOut(nil)
            self.panel.alphaValue = 1
        })
    }

    private func updateTheme() {
        let isDark = isDarkAppearance(panel.effectiveAppearance)
        blurView.material = isDark ? .hudWindow : .popover
        updateColors()
    }

    private func updateColors() {
        let palette = currentPalette()
        let tint = (currentStatus == .off) ? palette.off : palette.on
        imageView.contentTintColor = tint
        label.textColor = tint
    }

    private func currentPalette() -> (on: NSColor, off: NSColor) {
        let isDark = isDarkAppearance(panel.effectiveAppearance)
        if isDark {
            return (
                on: NSColor(white: 0.95, alpha: 0.96),
                off: NSColor.systemRed.withAlphaComponent(0.92)
            )
        }
        return (
            on: NSColor(white: 0.12, alpha: 0.94),
            off: NSColor.systemRed.withAlphaComponent(0.88)
        )
    }

    private func isDarkAppearance(_ appearance: NSAppearance) -> Bool {
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }
}
