import Foundation
import Carbon

final class ShortcutStore {
    private let defaults = UserDefaults.standard
    private let key = "shortcuts.list.v1"

    func load() -> [Shortcut] {
        guard let data = defaults.data(forKey: key) else { return [] }
        do {
            return try JSONDecoder().decode([Shortcut].self, from: data)
        } catch {
            NSLog("ShortcutStore.load decode error: \(error)")
            return []
        }
    }

    func save(_ shortcuts: [Shortcut]) {
        do {
            let data = try JSONEncoder().encode(shortcuts)
            defaults.set(data, forKey: key)
        } catch {
            NSLog("ShortcutStore.save encode error: \(error)")
        }
    }

    func bootstrapIfMissing() -> [Shortcut] {
        if defaults.data(forKey: key) == nil {
            let initial = [
                Shortcut(
                    id: UUID(),
                    carbonID: 1,
                    keyCode: UInt32(kVK_ANSI_M),
                    modifiers: UInt32(cmdKey | optionKey)
                )
            ]
            save(initial)
        }
        return load()
    }

    func add(keyCode: UInt32, modifiers: UInt32) -> [Shortcut] {
        var list = load()
        let newCarbonID = nextCarbonID(existing: list)
        list.append(Shortcut(id: UUID(), carbonID: newCarbonID, keyCode: keyCode, modifiers: modifiers))
        save(list)
        return list
    }

    func remove(id: UUID) -> [Shortcut] {
        var list = load()
        list.removeAll { $0.id == id }
        save(list)
        return list
    }

    private func nextCarbonID(existing: [Shortcut]) -> UInt32 {
        let used = Set(existing.map { $0.carbonID })
        var candidate: UInt32 = (existing.map { $0.carbonID }.max() ?? 0) + 1
        if candidate == 0 { candidate = 1 }
        while used.contains(candidate) {
            candidate &+= 1
            if candidate == 0 { candidate = 1 }
        }
        return candidate
    }
}
