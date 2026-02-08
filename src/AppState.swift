import Foundation
import AppKit
import Combine

struct RunningAppSummary: Identifiable {
    let bundleID: String
    let name: String
    let icon: NSImage?
    let processIDs: [pid_t]

    var id: String { bundleID }
}

final class AppState: ObservableObject {
    @Published var searchText = ""
    @Published var muteEnabled = false {
        didSet {
            UserDefaults.standard.set(muteEnabled, forKey: Self.defaultsMuteEnabled)
            applyMuteConfiguration()
        }
    }
    @Published private(set) var runningApps: [RunningAppSummary] = []
    @Published private(set) var statusMessage = ""
    @Published private(set) var errorMessage: String?

    private var selectedBundleIDs: Set<String>
    private var applySelectionWorkItem: DispatchWorkItem?
    private var workspaceObservers: [NSObjectProtocol] = []
    private var languageObserver: NSObjectProtocol?
    private let engine = ProcessTapMuteEngine()

    static let defaultsSelectedBundleIDs = "appsmute.selectedBundleIDs"
    static let defaultsMuteEnabled = "appsmute.enabled"

    init() {
        let storedBundleIDs = UserDefaults.standard.stringArray(forKey: Self.defaultsSelectedBundleIDs) ?? []
        selectedBundleIDs = Set(storedBundleIDs)
        muteEnabled = UserDefaults.standard.bool(forKey: Self.defaultsMuteEnabled)
        statusMessage = L("status_disabled")

        observeWorkspace()
        observeLanguage()
        refreshApps()
        applyMuteConfiguration()
    }

    deinit {
        let center = NSWorkspace.shared.notificationCenter
        workspaceObservers.forEach { center.removeObserver($0) }

        if let languageObserver {
            NotificationCenter.default.removeObserver(languageObserver)
        }

        applySelectionWorkItem?.cancel()
        engine.stop()
    }

    var filteredApps: [RunningAppSummary] {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return runningApps
        }

        let needle = trimmed.lowercased()
        return runningApps.filter {
            $0.name.lowercased().contains(needle) || $0.bundleID.lowercased().contains(needle)
        }
    }

    var mutedSummary: String {
        let runningBundleIDs = Set(runningApps.map(\.bundleID))
        let activeMutedCount = selectedBundleIDs.intersection(runningBundleIDs).count
        return "\(L("content_selected")): \(selectedBundleIDs.count)  •  \(L("content_running_muted")): \(activeMutedCount)"
    }

    func toggleMute() {
        muteEnabled.toggle()
    }

    func refreshApps() {
        var grouped: [String: (name: String, icon: NSImage?, pids: [pid_t])] = [:]

        for app in NSWorkspace.shared.runningApplications {
            guard app.activationPolicy == .regular else { continue }
            guard let bundleID = app.bundleIdentifier, !bundleID.isEmpty else { continue }
            guard let name = app.localizedName, !name.isEmpty else { continue }

            var entry = grouped[bundleID] ?? (name: name, icon: app.icon, pids: [])
            entry.pids.append(app.processIdentifier)
            if entry.icon == nil {
                entry.icon = app.icon
            }
            grouped[bundleID] = entry
        }

        runningApps = grouped.map { bundleID, entry in
            RunningAppSummary(bundleID: bundleID, name: entry.name, icon: entry.icon, processIDs: entry.pids)
        }
        .sorted {
            if $0.name.caseInsensitiveCompare($1.name) == .orderedSame {
                return $0.bundleID < $1.bundleID
            }
            return $0.name.caseInsensitiveCompare($1.name) == .orderedAscending
        }

        if muteEnabled {
            applyMuteConfiguration()
        }
    }

    func isSelected(bundleID: String) -> Bool {
        selectedBundleIDs.contains(bundleID)
    }

    func setSelection(for bundleID: String, isSelected: Bool) {
        let oldValue = selectedBundleIDs.contains(bundleID)
        guard oldValue != isSelected else { return }

        if isSelected {
            selectedBundleIDs.insert(bundleID)
        } else {
            selectedBundleIDs.remove(bundleID)
        }

        UserDefaults.standard.set(Array(selectedBundleIDs).sorted(), forKey: Self.defaultsSelectedBundleIDs)
        objectWillChange.send()

        if muteEnabled {
            scheduleApplyMuteConfiguration()
        }
    }

    private func observeWorkspace() {
        let center = NSWorkspace.shared.notificationCenter

        let names: [Notification.Name] = [
            NSWorkspace.didLaunchApplicationNotification,
            NSWorkspace.didTerminateApplicationNotification,
            NSWorkspace.didHideApplicationNotification,
            NSWorkspace.didUnhideApplicationNotification
        ]

        workspaceObservers = names.map { name in
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.refreshApps()
            }
        }
    }

    private func observeLanguage() {
        languageObserver = NotificationCenter.default.addObserver(
            forName: LanguageManager.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.updateLocalizedStatus()
            self?.objectWillChange.send()
        }
    }

    private func updateLocalizedStatus() {
        statusMessage = muteEnabled ? L("status_enabled") : L("status_disabled")
    }

    private func scheduleApplyMuteConfiguration() {
        applySelectionWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.applyMuteConfiguration()
        }
        applySelectionWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: workItem)
    }

    private func applyMuteConfiguration() {
        errorMessage = nil

        guard muteEnabled else {
            engine.stop()
            statusMessage = L("status_disabled")
            return
        }

        let activeBundleIDs = selectedBundleIDs.intersection(Set(runningApps.map(\.bundleID)))

        guard !activeBundleIDs.isEmpty else {
            engine.stop()
            statusMessage = L("status_enabled")
            return
        }

        do {
            try engine.startMuting(selectedBundleIDs: activeBundleIDs, runningApps: runningApps)
            statusMessage = L("status_enabled")
        } catch {
            engine.stop()
            statusMessage = L("status_coreaudio_error")
            errorMessage = error.localizedDescription
        }
    }
}
