import AppKit

final class StatusBarController: NSObject {
    private let statusItem: NSStatusItem

    private let toggleItem: NSMenuItem

    private let shortcutsRootItem: NSMenuItem
    private let shortcutsMenu: NSMenu
    private let addShortcutItem: NSMenuItem

    private let soundsRootItem: NSMenuItem
    private let soundsMenu: NSMenu
    private let soundsEnabledItem: NSMenuItem
    private let volumeItem: NSMenuItem
    private var volumeView: SoundVolumeMenuView?

    private let languageRootItem: NSMenuItem
    private let languageMenu: NSMenu

    private let openWindowItem: NSMenuItem
    private let quitItem: NSMenuItem

    private let onToggle: () -> Void
    private let onAddShortcut: () -> Void
    private let onRemoveShortcut: (UUID) -> Void
    private let onSoundsEnabledChanged: (Bool) -> Void
    private let onVolumeChanged: (Float) -> Void
    private let onOpenWindow: () -> Void

    private var currentIsMuted = false
    private var currentShortcuts: [Shortcut] = []
    private var currentSoundsEnabled = true
    private var currentSoundVolume: Float = 0.6

    init(
        onToggle: @escaping () -> Void,
        onAddShortcut: @escaping () -> Void,
        onRemoveShortcut: @escaping (UUID) -> Void,
        onSoundsEnabledChanged: @escaping (Bool) -> Void,
        onVolumeChanged: @escaping (Float) -> Void,
        onOpenWindow: @escaping () -> Void
    ) {
        self.onToggle = onToggle
        self.onAddShortcut = onAddShortcut
        self.onRemoveShortcut = onRemoveShortcut
        self.onSoundsEnabledChanged = onSoundsEnabledChanged
        self.onVolumeChanged = onVolumeChanged
        self.onOpenWindow = onOpenWindow

        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        self.toggleItem = NSMenuItem(title: L("menu_disable_sound"), action: #selector(toggleClicked), keyEquivalent: "")

        self.shortcutsRootItem = NSMenuItem(title: L("menu_shortcuts"), action: nil, keyEquivalent: "")
        self.shortcutsMenu = NSMenu(title: L("menu_shortcuts"))
        self.addShortcutItem = NSMenuItem(title: L("menu_add_shortcut"), action: #selector(addShortcutClicked), keyEquivalent: "")

        self.soundsRootItem = NSMenuItem(title: L("menu_sounds"), action: nil, keyEquivalent: "")
        self.soundsMenu = NSMenu(title: L("menu_sounds"))
        self.soundsEnabledItem = NSMenuItem(title: L("menu_sounds_enabled"), action: #selector(toggleSoundsEnabled), keyEquivalent: "")
        self.volumeItem = NSMenuItem()

        self.languageRootItem = NSMenuItem(title: L("menu_language"), action: nil, keyEquivalent: "")
        self.languageMenu = NSMenu(title: L("menu_language"))

        self.openWindowItem = NSMenuItem(title: L("menu_open_window"), action: #selector(openWindowClicked), keyEquivalent: "")
        self.quitItem = NSMenuItem(title: L("menu_quit"), action: #selector(quitClicked), keyEquivalent: "q")

        super.init()

        toggleItem.target = self
        addShortcutItem.target = self
        soundsEnabledItem.target = self
        openWindowItem.target = self
        quitItem.target = self

        shortcutsRootItem.submenu = shortcutsMenu
        soundsRootItem.submenu = soundsMenu
        languageRootItem.submenu = languageMenu

        let menu = NSMenu()
        menu.addItem(toggleItem)
        menu.addItem(.separator())
        menu.addItem(shortcutsRootItem)
        menu.addItem(soundsRootItem)
        menu.addItem(languageRootItem)
        menu.addItem(.separator())
        menu.addItem(openWindowItem)
        menu.addItem(.separator())
        menu.addItem(quitItem)

        statusItem.menu = menu

        if let button = statusItem.button {
            button.imagePosition = .imageOnly
        }

        rebuildShortcutsMenu([])
        rebuildSoundsMenu(isEnabled: true, volume: 0.6)
        rebuildLanguageMenu()
        update(isMuted: false)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(languageDidChange),
            name: LanguageManager.didChangeNotification,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func update(isMuted: Bool) {
        currentIsMuted = isMuted
        let assets = SoundMuteAssets.shared
        statusItem.button?.image = isMuted ? assets.trayMuted : assets.trayUnmuted
        toggleItem.title = isMuted ? L("menu_enable_sound") : L("menu_disable_sound")
        statusItem.button?.toolTip = isMuted ? L("tooltip_sound_off") : L("tooltip_sound_on")
    }

    func updateShortcuts(_ shortcuts: [Shortcut]) {
        currentShortcuts = shortcuts
        rebuildShortcutsMenu(shortcuts)
    }

    func updateSounds(isEnabled: Bool, volume: Float) {
        currentSoundsEnabled = isEnabled
        currentSoundVolume = max(0, min(volume, 1))
        soundsEnabledItem.state = isEnabled ? .on : .off
        volumeView?.setVolume(currentSoundVolume)
        volumeView?.setEnabled(isEnabled)
    }

    private func rebuildShortcutsMenu(_ shortcuts: [Shortcut]) {
        shortcutsMenu.removeAllItems()

        if shortcuts.isEmpty {
            let empty = NSMenuItem(title: L("menu_no_shortcuts"), action: nil, keyEquivalent: "")
            empty.isEnabled = false
            shortcutsMenu.addItem(empty)
        } else {
            for s in shortcuts {
                let title = "✕  " + ShortcutFormatter.format(keyCode: s.keyCode, modifiers: s.modifiers)
                let item = NSMenuItem(title: title, action: #selector(removeShortcut(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = s.id.uuidString
                shortcutsMenu.addItem(item)
            }
        }

        shortcutsMenu.addItem(.separator())
        shortcutsMenu.addItem(addShortcutItem)
    }

    private func rebuildSoundsMenu(isEnabled: Bool, volume: Float) {
        soundsMenu.removeAllItems()

        soundsEnabledItem.state = isEnabled ? .on : .off
        soundsMenu.addItem(soundsEnabledItem)

        let view = SoundVolumeMenuView(volume: volume, isEnabled: isEnabled)
        view.onChange = { [weak self] value in
            self?.onVolumeChanged(value)
        }
        volumeView = view

        volumeItem.view = view
        soundsMenu.addItem(volumeItem)
    }

    private func rebuildLanguageMenu() {
        languageMenu.removeAllItems()

        let langs = LanguageManager.shared.availableLanguages()
        if langs.isEmpty {
            let empty = NSMenuItem(title: L("menu_language"), action: nil, keyEquivalent: "")
            empty.isEnabled = false
            languageMenu.addItem(empty)
            return
        }

        for lang in langs {
            let item = NSMenuItem(title: lang.name, action: #selector(selectLanguage(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = lang.code
            item.state = (lang.code == LanguageManager.shared.currentCode) ? .on : .off
            languageMenu.addItem(item)
        }
    }

    @objc private func selectLanguage(_ sender: NSMenuItem) {
        guard let code = sender.representedObject as? String else { return }
        LanguageManager.shared.setCurrent(code: code)
    }

    @objc private func languageDidChange() {
        refreshLocalization()
    }

    private func refreshLocalization() {
        shortcutsRootItem.title = L("menu_shortcuts")
        shortcutsMenu.title = L("menu_shortcuts")
        addShortcutItem.title = L("menu_add_shortcut")

        soundsRootItem.title = L("menu_sounds")
        soundsMenu.title = L("menu_sounds")
        soundsEnabledItem.title = L("menu_sounds_enabled")
        volumeView?.setLabel(L("label_volume"))

        languageRootItem.title = L("menu_language")
        languageMenu.title = L("menu_language")

        openWindowItem.title = L("menu_open_window")
        quitItem.title = L("menu_quit")

        toggleItem.title = currentIsMuted ? L("menu_enable_sound") : L("menu_disable_sound")
        statusItem.button?.toolTip = currentIsMuted ? L("tooltip_sound_off") : L("tooltip_sound_on")

        rebuildShortcutsMenu(currentShortcuts)
        rebuildSoundsMenu(isEnabled: currentSoundsEnabled, volume: currentSoundVolume)
        rebuildLanguageMenu()
    }

    @objc private func toggleClicked() { onToggle() }
    @objc private func addShortcutClicked() { onAddShortcut() }

    @objc private func toggleSoundsEnabled() {
        let newValue = (soundsEnabledItem.state != .on)
        soundsEnabledItem.state = newValue ? .on : .off
        currentSoundsEnabled = newValue
        volumeView?.setEnabled(newValue)
        onSoundsEnabledChanged(newValue)
    }

    @objc private func removeShortcut(_ sender: NSMenuItem) {
        guard let s = sender.representedObject as? String,
              let id = UUID(uuidString: s) else { return }
        onRemoveShortcut(id)
    }

    @objc private func openWindowClicked() { onOpenWindow() }
    @objc private func quitClicked() { NSApp.terminate(nil) }
}

final class SoundVolumeMenuView: NSView {
    private let label = NSTextField(labelWithString: "")
    private let slider = NSSlider(value: 0.6, minValue: 0.0, maxValue: 1.0, target: nil, action: nil)

    var onChange: ((Float) -> Void)?

    init(volume: Float, isEnabled: Bool) {
        super.init(frame: NSRect(x: 0, y: 0, width: 220, height: 28))

        label.stringValue = L("label_volume")
        label.font = NSFont.systemFont(ofSize: 12, weight: .regular)
        label.textColor = NSColor.secondaryLabelColor

        slider.doubleValue = Double(max(0, min(volume, 1)))
        slider.isEnabled = isEnabled
        slider.isContinuous = true
        slider.sendAction(on: [.leftMouseDragged, .leftMouseUp])
        slider.target = self
        slider.action = #selector(sliderChanged)

        addSubview(label)
        addSubview(slider)

        label.translatesAutoresizingMaskIntoConstraints = false
        slider.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),

            slider.leadingAnchor.constraint(equalTo: label.trailingAnchor, constant: 10),
            slider.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            slider.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    required init?(coder: NSCoder) { nil }

    func setVolume(_ value: Float) {
        slider.doubleValue = Double(max(0, min(value, 1)))
    }

    func setEnabled(_ enabled: Bool) {
        slider.isEnabled = enabled
    }

    func setLabel(_ text: String) {
        label.stringValue = text
    }

    @objc private func sliderChanged() {
        onChange?(Float(slider.doubleValue))
    }
}
