import CoreAudio
import Foundation

/// Which processes send sound to the speakers right now, as Core Audio sees them. Reading this
/// asks for no permission and records nothing: only whether each process plays, never what.
enum AudioActivity {
    /// Bundle identifiers of the processes playing now, lowercased. nil when Core Audio could not say.
    static func audibleBundleIDs() -> Set<String>? {
        let system = AudioObjectID(kAudioObjectSystemObject)
        var address = address(kAudioHardwarePropertyProcessObjectList)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr else { return nil }
        var processes = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &processes) == noErr else { return nil }

        var audible: Set<String> = []
        for process in processes {
            var running: UInt32 = 0
            var runningSize = UInt32(MemoryLayout<UInt32>.size)
            var runningAddress = self.address(kAudioProcessPropertyIsRunningOutput)
            guard AudioObjectGetPropertyData(process, &runningAddress, 0, nil, &runningSize, &running) == noErr,
                  running != 0 else { continue }
            var bundleID: Unmanaged<CFString>?
            var bundleSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
            var bundleAddress = self.address(kAudioProcessPropertyBundleID)
            guard AudioObjectGetPropertyData(process, &bundleAddress, 0, nil, &bundleSize, &bundleID) == noErr,
                  let id = bundleID?.takeRetainedValue() as String?, !id.isEmpty else { continue }
            audible.insert(id.lowercased())
        }
        return audible
    }

    private static func address(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
                                   mElement: kAudioObjectPropertyElementMain)
    }
}
