import Foundation
import Carbon

private func HotKeyManagerEventHandler(
    _ nextHandler: EventHandlerCallRef?,
    _ theEvent: EventRef?,
    _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let userData else { return noErr }
    let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
    manager.handle(event: theEvent)
    return noErr
}

final class HotKeyManager {

    enum HotKeyError: Error, LocalizedError {
        case osStatus(OSStatus, String)

        var errorDescription: String? {
            switch self {
            case let .osStatus(status, context):
                return "\(context) failed with OSStatus=\(status)"
            }
        }
    }

    static let shared = HotKeyManager()

    private let signature: OSType = 0x4150534D // 'APSM'

    private var eventHandlerRef: EventHandlerRef?
    private var hotKeyRefs: [UInt32: EventHotKeyRef] = [:]
    private var handlers: [UInt32: () -> Void] = [:]

    private init() {}

    func register(shortcuts: [Shortcut], handler: @escaping () -> Void) throws {
        try installHandlerIfNeeded()

        unregisterAll()

        for s in shortcuts {
            let hkID = EventHotKeyID(signature: signature, id: s.carbonID)
            var ref: EventHotKeyRef?

            let status = RegisterEventHotKey(
                s.keyCode,
                s.modifiers,
                hkID,
                GetApplicationEventTarget(),
                0,
                &ref
            )

            guard status == noErr else {
                throw HotKeyError.osStatus(status, "RegisterEventHotKey")
            }

            if let ref {
                hotKeyRefs[s.carbonID] = ref
                handlers[s.carbonID] = handler
            }
        }
    }

    func unregisterAll() {
        for (_, ref) in hotKeyRefs {
            UnregisterEventHotKey(ref)
        }
        hotKeyRefs.removeAll()
        handlers.removeAll()
    }

    private func installHandlerIfNeeded() throws {
        if eventHandlerRef != nil { return }

        var eventSpec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let userData = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())

        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            HotKeyManagerEventHandler,
            1,
            &eventSpec,
            userData,
            &eventHandlerRef
        )

        guard status == noErr else {
            throw HotKeyError.osStatus(status, "InstallEventHandler")
        }
    }

    fileprivate func handle(event: EventRef?) {
        guard let event else { return }

        var hkID = EventHotKeyID()
        let status = GetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &hkID
        )

        guard status == noErr else { return }
        guard hkID.signature == signature else { return }

        handlers[hkID.id]?()
    }

    deinit {
        unregisterAll()
        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
        }
    }
}
