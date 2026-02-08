import AppKit
import Carbon
import Combine

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let appState = AppState()

    private let store = ShortcutStore()
    private var shortcuts: [Shortcut] = []

    private let indicator = SoundIndicatorWindowController()
    private let sound = SoundManager(isEnabled: SoundPrefs.isEnabled, volume: SoundPrefs.volume)

    private let recorder = ShortcutRecorderWindowController()

    private var windowController: MainWindowController?
    private var statusBar: StatusBarController?
    private var cancellables: Set<AnyCancellable> = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        shortcuts = store.bootstrapIfMissing()
        windowController = MainWindowController(appState: appState)

        statusBar = StatusBarController(
            onToggle: { [weak self] in self?.toggleMuteAndNotify() },
            onAddShortcut: { [weak self] in self?.addShortcut() },
            onRemoveShortcut: { [weak self] id in self?.removeShortcut(id: id) },
            onSoundsEnabledChanged: { [weak self] enabled in self?.setSoundsEnabled(enabled) },
            onVolumeChanged: { [weak self] volume in self?.setSoundVolume(volume) },
            onOpenWindow: { [weak self] in self?.openMainWindow() }
        )

        statusBar?.update(isMuted: appState.muteEnabled)
        statusBar?.updateShortcuts(shortcuts)
        statusBar?.updateSounds(isEnabled: sound.isEnabled, volume: sound.volume)

        appState.$muteEnabled
            .receive(on: RunLoop.main)
            .sink { [weak self] muted in
                self?.statusBar?.update(isMuted: muted)
            }
            .store(in: &cancellables)

        appState.$muteEnabled
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] muted in
                guard let self else { return }
                self.indicator.show(status: muted ? .off : .on)
                if muted {
                    self.sound.playOff()
                } else {
                    self.sound.playOn()
                }
            }
            .store(in: &cancellables)

        registerHotKeys()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    private func openMainWindow() {
        windowController?.present()
    }

    private func toggleMuteAndNotify() {
        appState.toggleMute()
    }

    private func registerHotKeys() {
        do {
            try HotKeyManager.shared.register(shortcuts: shortcuts) { [weak self] in
                self?.toggleMuteAndNotify()
            }
        } catch {
            NSLog("HotKey register failed: \(error)")
        }
    }

    private func addShortcut() {
        let defaults = (keyCode: UInt32(kVK_ANSI_M), modifiers: UInt32(cmdKey | optionKey))
        let current = shortcuts.last.map { ($0.keyCode, $0.modifiers) } ?? defaults

        recorder.present(currentKeyCode: current.0, currentModifiers: current.1) { [weak self] keyCode, modifiers in
            guard let self else { return }
            self.shortcuts = self.store.add(keyCode: keyCode, modifiers: modifiers)
            self.statusBar?.updateShortcuts(self.shortcuts)
            self.registerHotKeys()
        }
    }

    private func removeShortcut(id: UUID) {
        shortcuts = store.remove(id: id)
        statusBar?.updateShortcuts(shortcuts)
        registerHotKeys()
    }

    private func setSoundsEnabled(_ enabled: Bool) {
        SoundPrefs.isEnabled = enabled
        sound.isEnabled = enabled
        statusBar?.updateSounds(isEnabled: sound.isEnabled, volume: sound.volume)
    }

    private func setSoundVolume(_ volume: Float) {
        SoundPrefs.volume = volume
        sound.volume = SoundPrefs.volume
        statusBar?.updateSounds(isEnabled: sound.isEnabled, volume: sound.volume)
    }
}
