import Foundation
import CoreAudio

final class ProcessTapMuteEngine {
    private var tapID: AudioObjectID?
    private var aggregateDeviceID: AudioObjectID?
    private var ioProcID: AudioDeviceIOProcID?
    private var tapDescription: CATapDescription?

    func startMuting(selectedBundleIDs: Set<String>, runningApps: [RunningAppSummary]) throws {
        stop()

        let pids = runningApps
            .filter { selectedBundleIDs.contains($0.bundleID) }
            .flatMap(\.processIDs)

        let processObjectIDs = Set(pids.compactMap(processObjectID(forPID:)))
        guard !processObjectIDs.isEmpty else {
            throw ProcessTapMuteError.noProcessObjects
        }

        let description = CATapDescription(stereoMixdownOfProcesses: Array(processObjectIDs))
        description.name = "appsmute Tap"
        description.isPrivate = true
        description.muteBehavior = CATapMuteBehavior.muted

        if #available(macOS 26.0, *) {
            description.bundleIDs = Array(selectedBundleIDs)
            description.isProcessRestoreEnabled = true
        }

        var newTapID: AudioObjectID = 0
        try check(
            AudioHardwareCreateProcessTap(description, &newTapID),
            operation: "AudioHardwareCreateProcessTap"
        )

        let tapDescriptionDict: [String: Any] = [
            String(kAudioSubTapUIDKey): description.uuid.uuidString,
            String(kAudioSubTapDriftCompensationKey): true
        ]

        let aggregateDescription: [String: Any] = [
            String(kAudioAggregateDeviceNameKey): "appsmute Aggregate",
            String(kAudioAggregateDeviceUIDKey): "snsxd.appsmute.aggregate.\(UUID().uuidString)",
            String(kAudioAggregateDeviceIsPrivateKey): true,
            String(kAudioAggregateDeviceTapAutoStartKey): true,
            String(kAudioAggregateDeviceTapListKey): [tapDescriptionDict]
        ]

        var newAggregateDeviceID: AudioObjectID = 0
        do {
            try check(
                AudioHardwareCreateAggregateDevice(aggregateDescription as CFDictionary, &newAggregateDeviceID),
                operation: "AudioHardwareCreateAggregateDevice"
            )
        } catch {
            _ = AudioHardwareDestroyProcessTap(newTapID)
            throw error
        }

        var newIOProcID: AudioDeviceIOProcID?
        do {
            try check(
                AudioDeviceCreateIOProcIDWithBlock(&newIOProcID, newAggregateDeviceID, nil) { _, _, _, _, _ in },
                operation: "AudioDeviceCreateIOProcIDWithBlock"
            )

            guard let safeIOProcID = newIOProcID else {
                throw ProcessTapMuteError.ioProcUnavailable
            }

            try check(AudioDeviceStart(newAggregateDeviceID, safeIOProcID), operation: "AudioDeviceStart")

            tapID = newTapID
            aggregateDeviceID = newAggregateDeviceID
            ioProcID = safeIOProcID
            tapDescription = description
        } catch {
            if let newIOProcID {
                _ = AudioDeviceDestroyIOProcID(newAggregateDeviceID, newIOProcID)
            }
            _ = AudioHardwareDestroyAggregateDevice(newAggregateDeviceID)
            _ = AudioHardwareDestroyProcessTap(newTapID)
            throw error
        }
    }

    func stop() {
        if let aggregateDeviceID, let ioProcID {
            _ = AudioDeviceStop(aggregateDeviceID, ioProcID)
            _ = AudioDeviceDestroyIOProcID(aggregateDeviceID, ioProcID)
        }

        if let aggregateDeviceID {
            _ = AudioHardwareDestroyAggregateDevice(aggregateDeviceID)
        }

        if let tapID {
            _ = AudioHardwareDestroyProcessTap(tapID)
        }

        ioProcID = nil
        aggregateDeviceID = nil
        tapID = nil
        tapDescription = nil
    }

    private func processObjectID(forPID pid: pid_t) -> AudioObjectID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyTranslatePIDToProcessObject,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var mutablePID = pid
        var processObjectID: AudioObjectID = kAudioObjectUnknown
        var dataSize = UInt32(MemoryLayout<AudioObjectID>.size)

        let status = withUnsafePointer(to: &mutablePID) { pidPointer in
            AudioObjectGetPropertyData(
                AudioObjectID(kAudioObjectSystemObject),
                &address,
                UInt32(MemoryLayout<pid_t>.size),
                pidPointer,
                &dataSize,
                &processObjectID
            )
        }

        guard status == noErr, processObjectID != AudioObjectID(kAudioObjectUnknown) else {
            return nil
        }

        return processObjectID
    }

    private func check(_ status: OSStatus, operation: String) throws {
        guard status == noErr else {
            throw ProcessTapMuteError.osStatus(operation: operation, status: status)
        }
    }
}

enum ProcessTapMuteError: LocalizedError {
    case noProcessObjects
    case ioProcUnavailable
    case osStatus(operation: String, status: OSStatus)

    var errorDescription: String? {
        switch self {
        case .noProcessObjects:
            return "No active audio process objects were found for selected apps."
        case .ioProcUnavailable:
            return "Failed to create a realtime IO processor for the tap device."
        case let .osStatus(operation, status):
            return "\(operation) failed with OSStatus \(formatted(status))."
        }
    }

    private func formatted(_ status: OSStatus) -> String {
        let raw = UInt32(bitPattern: status)
        let bytes: [UInt8] = [
            UInt8((raw >> 24) & 0xFF),
            UInt8((raw >> 16) & 0xFF),
            UInt8((raw >> 8) & 0xFF),
            UInt8(raw & 0xFF)
        ]
        let printable = bytes.allSatisfy { (32...126).contains($0) }

        if printable {
            let fourCC = String(bytes: bytes, encoding: .ascii) ?? "????"
            return "\(status) ('\(fourCC)')"
        }

        return "\(status)"
    }
}
