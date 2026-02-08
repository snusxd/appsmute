import AppKit
import SwiftUI

final class MainWindowController: NSWindowController {
    private let appState: AppState

    init(appState: AppState) {
        self.appState = appState

        let content = ContentView().environmentObject(appState)
        let hostingView = NSHostingView(rootView: content)
        hostingView.translatesAutoresizingMaskIntoConstraints = false

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 760),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )

        let blurView = NSVisualEffectView()
        blurView.translatesAutoresizingMaskIntoConstraints = false
        blurView.material = .hudWindow
        blurView.blendingMode = .behindWindow
        blurView.state = .active
        blurView.addSubview(hostingView)

        NSLayoutConstraint.activate([
            hostingView.leadingAnchor.constraint(equalTo: blurView.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: blurView.trailingAnchor),
            hostingView.topAnchor.constraint(equalTo: blurView.topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: blurView.bottomAnchor)
        ])

        window.contentView = blurView
        window.minSize = NSSize(width: 560, height: 680)
        window.maxSize = NSSize(width: 560, height: 680)
        window.title = L("menu_open_window")
        window.isOpaque = false
        window.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.86)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        window.isReleasedWhenClosed = false

        super.init(window: window)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(languageDidChange),
            name: LanguageManager.didChangeNotification,
            object: nil
        )
    }

    required init?(coder: NSCoder) { nil }

    func present() {
        guard let window else { return }

        NSApp.activate(ignoringOtherApps: true)
        window.center()
        showWindow(nil)
        window.makeKeyAndOrderFront(nil)
    }

    @objc private func languageDidChange() {
        window?.title = L("menu_open_window")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}
