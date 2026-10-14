import CoreAudio
import Foundation

/// What the TV does while the Mac is on a call.
enum CallAction: String, CaseIterable, Identifiable {
    case off, pause, lower, mute
    var id: String { rawValue }
    var label: String {
        switch self {
        case .off: return "Nada"
        case .pause: return "Pausar"
        case .lower: return "Abaixar"
        case .mute: return "Mudo"
        }
    }
    /// Volume to use while lowered: about a third of the current level.
    static func lowered(from volume: Int) -> Int { min(volume, max(2, Int((Double(volume) * 0.3).rounded()))) }
}

/// Watches whether any app is using an input device (Meet, Zoom, FaceTime…).
/// It reads CoreAudio's "running somewhere" flag only; it never opens the microphone.
final class CallMonitor {
    private var timer: Timer?
    private(set) var inCall = false
    var onChange: ((Bool) -> Void)?

    func start() {
        guard timer == nil else { return }
        inCall = Self.microphoneInUse()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            guard let self else { return }
            let now = Self.microphoneInUse()
            // A short check avoids flapping when an app briefly probes the microphone.
            if now != self.inCall { self.inCall = now; self.onChange?(now) }
        }
    }
    func stop() { timer?.invalidate(); timer = nil; inCall = false }

    static func microphoneInUse() -> Bool {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr, size > 0 else { return false }
        var devices = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &devices) == noErr else { return false }
        return devices.contains { device in
            var streams = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreams, mScope: kAudioObjectPropertyScopeInput, mElement: kAudioObjectPropertyElementMain)
            var streamSize: UInt32 = 0
            guard AudioObjectGetPropertyDataSize(device, &streams, 0, nil, &streamSize) == noErr, streamSize > 0 else { return false }
            var running: UInt32 = 0, runningSize = UInt32(MemoryLayout<UInt32>.size)
            var flag = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
            return AudioObjectGetPropertyData(device, &flag, 0, nil, &runningSize, &running) == noErr && running != 0
        }
    }
}
