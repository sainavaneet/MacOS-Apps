import AVFoundation
import AudioToolbox
import Speech
import Foundation

@MainActor
final class SpeechEngine: ObservableObject {
    @Published var transcript: String = ""
    @Published var partialTranscript: String = ""
    @Published private(set) var isListening = false
    @Published private(set) var isReceivingAudio = false
    @Published var errorMessage: String?
    @Published private(set) var audioLevel: Float = 0
    @Published private(set) var elapsedTime: TimeInterval = 0

    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?

    private var audioEngine: AVAudioEngine?
    private var restartTimer: Timer?
    private var elapsedTimer: Timer?
    private var recordingStartDate: Date?
    private var currentMicrophoneID = ""
    private var shouldStayListening = false
    private var smoothedLevel: Float = 0
    private var pauseTimer: Timer?

    func toggleListening(microphoneID: String) {
        if isListening {
            stopListening()
        } else {
            startListening(microphoneID: microphoneID)
        }
    }

    func reconnect(microphoneID: String) {
        currentMicrophoneID = microphoneID
        guard isListening else { return }
        stopListening()
        Task {
            try? await Task.sleep(for: .milliseconds(100))
            startListening(microphoneID: microphoneID)
        }
    }

    private func startListening(microphoneID: String) {
        errorMessage = nil
        isReceivingAudio = false
        partialTranscript = ""
        currentMicrophoneID = microphoneID
        shouldStayListening = true

        print("[SpeechEngine] Starting — requesting microphone permission...")

        // First request microphone access
        AVAudioApplication.requestRecordPermission { [weak self] granted in
            guard let self else { return }
            Task { @MainActor in
                print("[SpeechEngine] Microphone permission: \(granted ? "granted" : "denied")")
                guard granted else {
                    self.errorMessage = "Microphone access denied. Enable in System Settings > Privacy & Security > Microphone."
                    self.shouldStayListening = false
                    return
                }

                // Then request speech recognition authorization
                SFSpeechRecognizer.requestAuthorization { authStatus in
                    Task { @MainActor in
                        print("[SpeechEngine] Speech recognition auth: \(authStatus.rawValue) (0=notDetermined, 1=denied, 2=restricted, 3=authorized)")
                        self.handleAuthorizationResponse(authStatus, microphoneID: microphoneID)
                    }
                }
            }
        }
    }

    private func handleAuthorizationResponse(_ authStatus: SFSpeechRecognizerAuthorizationStatus, microphoneID: String) {
        guard shouldStayListening else { return }

        switch authStatus {
        case .authorized:
            setupAudioAndRecognition(microphoneID: microphoneID)
        case .denied:
            errorMessage = "Speech recognition permission denied. Enable in System Settings > Privacy & Security > Speech Recognition."
            shouldStayListening = false
        case .restricted:
            errorMessage = "Speech recognition is restricted on this system."
            shouldStayListening = false
        case .notDetermined:
            errorMessage = "Speech recognition authorization not determined."
            shouldStayListening = false
        @unknown default:
            errorMessage = "Unknown speech recognition authorization status."
            shouldStayListening = false
        }
    }

    private func setupAudioAndRecognition(microphoneID: String) {
        guard shouldStayListening else { return }

        // 1. Set up speech recognizer with explicit locale
        let locale = Locale(identifier: "en-US")
        speechRecognizer = SFSpeechRecognizer(locale: locale)
        guard let speechRecognizer else {
            errorMessage = "Speech recognizer could not be created for locale: \(locale.identifier)"
            shouldStayListening = false
            return
        }

        guard speechRecognizer.isAvailable else {
            errorMessage = "Speech recognizer not available. Check your internet connection or enable on-device recognition in System Settings > Keyboard > Dictation."
            shouldStayListening = false
            return
        }

        print("[SpeechEngine] Recognizer available. Supports on-device: \(speechRecognizer.supportsOnDeviceRecognition)")

        // 2. Create recognition request
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true

        // Prefer on-device recognition if available (avoids network issues)
        if speechRecognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
            print("[SpeechEngine] Using on-device recognition")
        } else {
            print("[SpeechEngine] On-device not available, using server-based recognition")
        }

        recognitionRequest = request

        // 3. Start recognition task
        recognitionTask = speechRecognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor in
                self?.handleRecognitionResult(result, error: error)
            }
        }

        // 4. Set up audio engine
        let engine = AVAudioEngine()

        // Configure specific microphone if provided
        if !microphoneID.isEmpty {
            do {
                try configureInputDevice(for: engine.inputNode, uniqueID: microphoneID)
                print("[SpeechEngine] Configured microphone: \(microphoneID)")
            } catch {
                print("[SpeechEngine] Could not configure specific mic (\(error.localizedDescription)), using system default")
            }
        }

        let inputNode = engine.inputNode

        // Use the node's output format — this is the format the tap will deliver
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        print("[SpeechEngine] Audio format: \(recordingFormat.sampleRate)Hz, \(recordingFormat.channelCount)ch")

        guard recordingFormat.sampleRate > 0 && recordingFormat.channelCount > 0 else {
            errorMessage = "No audio input available. Check that a microphone is connected."
            shouldStayListening = false
            cleanup()
            return
        }

        // 5. Install tap BEFORE prepare/start
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            guard let self else { return }
            self.recognitionRequest?.append(buffer)

            // Compute RMS audio level
            let level = self.computeRMS(buffer: buffer)

            Task { @MainActor in
                if !self.isReceivingAudio {
                    self.isReceivingAudio = true
                    print("[SpeechEngine] Audio buffers flowing")
                }
                // Exponential smoothing for visual display
                self.smoothedLevel = 0.3 * level + 0.7 * self.smoothedLevel
                self.audioLevel = self.smoothedLevel
            }
        }

        // 6. Prepare and start engine
        audioEngine = engine
        engine.prepare()
        do {
            try engine.start()
            isListening = true
            startElapsedTimer()
            print("[SpeechEngine] Audio engine started — listening")
            startRestartTimer()
        } catch {
            errorMessage = "Failed to start audio engine: \(error.localizedDescription)"
            print("[SpeechEngine] ERROR starting engine: \(error)")
            shouldStayListening = false
            cleanup()
        }
    }

    private func handleRecognitionResult(_ result: SFSpeechRecognitionResult?, error: Error?) {
        // Process the result FIRST, even if there's also an error.
        // Apple's speech API can send a final result alongside an error (e.g., when the
        // recognition session ends due to timeout or restart).
        if let result = result {
            if result.isFinal {
                pauseTimer?.invalidate()
                pauseTimer = nil
                let trimmed = result.bestTranscription.formattedString.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    let time = timestampString()
                    let entry = "[\(time)] \(trimmed)"
                    transcript = transcript.isEmpty ? entry : "\(transcript)\n\(entry)"
                    print("[SpeechEngine] Final: \(trimmed)")
                }
                partialTranscript = ""
            } else {
                partialTranscript = result.bestTranscription.formattedString
                // Pause detection: if partial text stays stable for 1.5s,
                // restart recognition to finalize the utterance.
                resetPauseTimer()
            }
        }

        // Handle errors after processing result
        if let error = error {
            let nsError = error as NSError
            // Ignore common non-fatal errors:
            // 216 = partial result error (normal)
            // 209 = recognition task was cancelled (normal during restart)
            // 301 = recognition request was cancelled (normal during restart)
            // 1110 = no speech detected (expected when silent)
            let ignoredCodes: Set<Int> = [216, 209, 301, 1110]
            if !ignoredCodes.contains(nsError.code) {
                print("[SpeechEngine] Recognition error [\(nsError.code)]: \(error.localizedDescription)")
                errorMessage = error.localizedDescription
            } else {
                print("[SpeechEngine] Ignored recognition event [\(nsError.code)]: \(error.localizedDescription)")
            }
        }
    }

    private func resetPauseTimer() {
        pauseTimer?.invalidate()
        pauseTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: false) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                guard self.shouldStayListening, self.isListening,
                      !self.partialTranscript.isEmpty else { return }
                print("[SpeechEngine] Pause detected — finalizing utterance")
                self.restartRecognition()
            }
        }
    }

    private func startRestartTimer() {
        restartTimer?.invalidate()
        restartTimer = Timer.scheduledTimer(withTimeInterval: 50.0, repeats: false) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.restartRecognition()
            }
        }
    }

    private func restartRecognition() {
        guard shouldStayListening, isListening else { return }

        let currentMicID = currentMicrophoneID

        // Manually finalize any partial text BEFORE cancelling the task,
        // because cancel() kills the task before the final result callback fires.
        let pending = partialTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        if !pending.isEmpty {
            let time = timestampString()
            let entry = "[\(time)] \(pending)"
            transcript = transcript.isEmpty ? entry : "\(transcript)\n\(entry)"
            print("[SpeechEngine] Finalized on restart: \(pending)")
        }
        partialTranscript = ""
        isReceivingAudio = false

        // Now tear down and restart
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        stopAudioEngine()
        setupAudioAndRecognition(microphoneID: currentMicID)
    }

    func loadTranscript(_ text: String) {
        transcript = text
    }

    func clearTranscript() {
        transcript = ""
        partialTranscript = ""
    }

    private func stopListening() {
        print("[SpeechEngine] Stopping")
        shouldStayListening = false
        partialTranscript = ""
        recognitionRequest?.endAudio()
        stopAudioEngine()
        cleanup()
        isListening = false
        isReceivingAudio = false
        audioLevel = 0
        smoothedLevel = 0
        stopElapsedTimer()
    }

    private func stopAudioEngine() {
        if let engine = audioEngine {
            engine.stop()
            engine.inputNode.removeTap(onBus: 0)
        }
        audioEngine = nil
    }

    private func cleanup() {
        restartTimer?.invalidate()
        restartTimer = nil
        pauseTimer?.invalidate()
        pauseTimer = nil
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        stopAudioEngine()
    }

    // MARK: - Audio Level & Timer

    nonisolated private func computeRMS(buffer: AVAudioPCMBuffer) -> Float {
        guard let channelData = buffer.floatChannelData else { return 0 }
        let frames = Int(buffer.frameLength)
        guard frames > 0 else { return 0 }

        var sum: Float = 0
        let samples = channelData[0]
        for i in 0..<frames {
            let sample = samples[i]
            sum += sample * sample
        }
        let rms = sqrtf(sum / Float(frames))
        // Normalize: typical speech RMS is ~0.01–0.1, amplify for display
        return min(rms * 5.0, 1.0)
    }

    private func startElapsedTimer() {
        recordingStartDate = Date()
        elapsedTime = 0
        elapsedTimer?.invalidate()
        elapsedTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                if let start = self.recordingStartDate {
                    self.elapsedTime = Date().timeIntervalSince(start)
                }
            }
        }
    }

    private func stopElapsedTimer() {
        elapsedTimer?.invalidate()
        elapsedTimer = nil
        recordingStartDate = nil
    }

    // MARK: - Microphone Selection

    private func configureInputDevice(for inputNode: AVAudioInputNode, uniqueID: String) throws {
        guard !uniqueID.isEmpty else { return }
        guard let audioUnit = inputNode.audioUnit else {
            throw SpeechEngineError.unableToAccessAudioUnit
        }

        guard let deviceID = audioDeviceID(for: uniqueID) else {
            throw SpeechEngineError.microphoneNotFound
        }

        var mutableDeviceID = deviceID
        let status = AudioUnitSetProperty(
            audioUnit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &mutableDeviceID,
            UInt32(MemoryLayout<AudioDeviceID>.size)
        )

        guard status == noErr else {
            throw SpeechEngineError.unableToSelectMicrophone(status)
        }
    }

    private func audioDeviceID(for uid: String) -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &dataSize) == noErr else {
            return nil
        }

        let count = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var devices = Array(repeating: AudioDeviceID(0), count: count)

        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &dataSize, &devices) == noErr else {
            return nil
        }

        return devices.first(where: { deviceUID(for: $0) == uid && hasInputChannels($0) })
    }

    private func deviceUID(for device: AudioDeviceID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID,
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
        let status = AudioObjectGetPropertyData(device, &address, 0, nil, &size, valuePointer)

        guard status == noErr, let value = valuePointer.pointee else {
            return nil
        }

        return value as String
    }

    private func hasInputChannels(_ device: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )

        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(device, &address, 0, nil, &size) == noErr else {
            return false
        }

        let bufferListPointer = UnsafeMutableRawPointer.allocate(
            byteCount: Int(size),
            alignment: MemoryLayout<AudioBufferList>.alignment
        )
        defer { bufferListPointer.deallocate() }

        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, bufferListPointer) == noErr else {
            return false
        }

        let audioBufferList = bufferListPointer.bindMemory(to: AudioBufferList.self, capacity: 1)
        let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
        return buffers.reduce(0) { $0 + Int($1.mNumberChannels) } > 0
    }

    private func timestampString() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: Date())
    }
}

enum SpeechEngineError: LocalizedError {
    case microphoneNotFound
    case unableToAccessAudioUnit
    case unableToSelectMicrophone(OSStatus)

    var errorDescription: String? {
        switch self {
        case .microphoneNotFound:
            return "Selected microphone was not found."
        case .unableToAccessAudioUnit:
            return "Unable to access audio input unit."
        case .unableToSelectMicrophone(let status):
            return "Unable to use selected microphone (OSStatus: \(status))."
        }
    }
}
