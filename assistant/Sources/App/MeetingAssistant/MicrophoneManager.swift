import AVFoundation
import AudioToolbox
import Combine

struct Microphone: Identifiable, Hashable {
    let id: String
    let name: String
}

@MainActor
final class MicrophoneManager: ObservableObject {
    @Published private(set) var microphones: [Microphone] = []
    @Published var selectedMicrophoneID: String = ""
    @Published private(set) var hasPermission = false

    init() {
        refreshAuthorizationAndDevices()
    }

    func requestPermissionAndRefresh() {
        AVCaptureDevice.requestAccess(for: .audio) { [weak self] _ in
            Task { @MainActor in
                self?.refreshAuthorizationAndDevices()
            }
        }
    }

    func refreshAuthorizationAndDevices() {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        hasPermission = status == .authorized

        if status == .notDetermined {
            requestPermissionAndRefresh()
            return
        }

        guard hasPermission else {
            microphones = []
            selectedMicrophoneID = ""
            return
        }

        microphones = loadInputDevices()
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        if microphones.contains(where: { $0.id == selectedMicrophoneID }) {
            return
        }

        selectedMicrophoneID = microphones.first?.id ?? ""
    }

    var selectedMicrophoneName: String {
        microphones.first(where: { $0.id == selectedMicrophoneID })?.name ?? "None"
    }

    private func loadInputDevices() -> [Microphone] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &dataSize) == noErr else {
            return []
        }

        let count = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = Array(repeating: AudioDeviceID(0), count: count)

        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &dataSize, &deviceIDs) == noErr else {
            return []
        }

        return deviceIDs.compactMap { deviceID in
            guard hasInputChannels(deviceID),
                  let uid = stringProperty(selector: kAudioDevicePropertyDeviceUID, for: deviceID),
                  let name = stringProperty(selector: kAudioObjectPropertyName, for: deviceID) else {
                return nil
            }

            return Microphone(id: uid, name: name)
        }
    }

    private func hasInputChannels(_ deviceID: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )

        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &size) == noErr else {
            return false
        }

        let bufferListPointer = UnsafeMutableRawPointer.allocate(
            byteCount: Int(size),
            alignment: MemoryLayout<AudioBufferList>.alignment
        )
        defer { bufferListPointer.deallocate() }

        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, bufferListPointer) == noErr else {
            return false
        }

        let audioBufferList = bufferListPointer.bindMemory(to: AudioBufferList.self, capacity: 1)
        let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)

        return buffers.reduce(0) { $0 + Int($1.mNumberChannels) } > 0
    }

    private func stringProperty(selector: AudioObjectPropertySelector, for deviceID: AudioDeviceID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let valuePointer = UnsafeMutablePointer<CFString?>.allocate(capacity: 1)
        valuePointer.initialize(to: nil)
        defer {
            valuePointer.deinitialize(count: 1)
            valuePointer.deallocate()
        }

        var size = UInt32(MemoryLayout<CFString?>.size)
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, valuePointer)

        guard status == noErr, let value = valuePointer.pointee else {
            return nil
        }

        return value as String
    }
}
