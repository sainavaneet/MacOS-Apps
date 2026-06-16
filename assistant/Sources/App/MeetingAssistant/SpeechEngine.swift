import AVFoundation
import AudioToolbox
import Speech
import Foundation
import os

@MainActor
final class SpeechEngine: ObservableObject {
    @Published var transcript: String = ""
    @Published var partialTranscript: String = ""
    @Published private(set) var isListening = false
    @Published private(set) var isReceivingAudio = false
    @Published var errorMessage: String?
    @Published private(set) var audioLevel: Float = 0
    @Published private(set) var elapsedTime: TimeInterval = 0

    /// When true, audio buffers are NOT fed to the speech recognizer.
    /// The audio engine keeps running so BlackHole/system audio is unaffected.
    /// Set this when Claude is generating or the app is busy.
    @Published var recognitionPaused: Bool = false

    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?

    private var audioEngine: AVAudioEngine?
    private var restartTimer: Timer?
    private var elapsedTimer: Timer?
    private var audioLevelTimer: Timer?
    private var recordingStartDate: Date?
    private var currentMicrophoneID = ""
    private var shouldStayListening = false
    private var smoothedLevel: Float = 0
    private var pauseTimer: Timer?

    // Thread-safe storage — written by the real-time audio thread,
    // read by the main thread via a polling timer.
    // Using OSAllocatedUnfairLock for minimal overhead on the audio thread.
    private let _latestRMS = OSAllocatedUnfairLock(initialState: Float(0))
    private let _receivedFirstBuffer = OSAllocatedUnfairLock(initialState: false)

    // Thread-safe reference to the current recognition request.
    // The audio tap reads this to know where to send buffers.
    // Swapped atomically during recognition restarts WITHOUT stopping the engine.
    private let _activeRequest = OSAllocatedUnfairLock<SFSpeechAudioBufferRecognitionRequest?>(initialState: nil)

    // Thread-safe pause flag read by the audio tap
    private let _tapPaused = OSAllocatedUnfairLock(initialState: false)

    // MARK: - Public API

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
            try? await Task.sleep(for: .milliseconds(200))
            startListening(microphoneID: microphoneID)
        }
    }

    func loadTranscript(_ text: String) {
        transcript = text
    }

    func clearTranscript() {
        transcript = ""
        partialTranscript = ""
    }

    /// Pause recognition (e.g. while Claude is generating).
    /// Audio engine stays running — no disruption to system audio.
    func pauseRecognition() {
        recognitionPaused = true
        _tapPaused.withLock { $0 = true }
    }

    /// Resume recognition after pause.
    func resumeRecognition() {
        recognitionPaused = false
        _tapPaused.withLock { $0 = false }
    }

    // MARK: - Start / Stop

    private func startListening(microphoneID: String) {
        errorMessage = nil
        isReceivingAudio = false
        partialTranscript = ""
        currentMicrophoneID = microphoneID
        shouldStayListening = true
        let paused = recognitionPaused
        _tapPaused.withLock { $0 = paused }

        print("[SpeechEngine] Starting — requesting microphone permission...")

        AVAudioApplication.requestRecordPermission { [weak self] granted in
            guard let self else { return }
            Task { @MainActor in
                print("[SpeechEngine] Microphone permission: \(granted ? "granted" : "denied")")
                guard granted else {
                    self.errorMessage = "Microphone access denied. Enable in System Settings > Privacy & Security > Microphone."
                    self.shouldStayListening = false
                    return
                }

                SFSpeechRecognizer.requestAuthorization { authStatus in
                    Task { @MainActor in
                        print("[SpeechEngine] Speech recognition auth: \(authStatus.rawValue)")
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
            setupAudioEngine(microphoneID: microphoneID)
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

    /// Sets up the audio engine ONCE and installs the tap.
    /// The engine stays running for the entire listening session.
    /// Only the recognition request/task are restarted every ~55s.
    private func setupAudioEngine(microphoneID: String) {
        guard shouldStayListening else { return }

        // 1. Set up speech recognizer
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

        print("[SpeechEngine] Recognizer available. On-device: \(speechRecognizer.supportsOnDeviceRecognition)")

        // 2. Set up audio engine
        let engine = AVAudioEngine()

        // Configure specific microphone/device
        if !microphoneID.isEmpty {
            do {
                try configureInputDevice(for: engine.inputNode, uniqueID: microphoneID)
                print("[SpeechEngine] Configured device: \(microphoneID)")
            } catch {
                print("[SpeechEngine] Could not configure device (\(error.localizedDescription)), using system default")
            }
        }

        let inputNode = engine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        print("[SpeechEngine] Audio format: \(recordingFormat.sampleRate)Hz, \(recordingFormat.channelCount)ch")

        guard recordingFormat.sampleRate > 0 && recordingFormat.channelCount > 0 else {
            errorMessage = "No audio input available. Check that a microphone is connected."
            shouldStayListening = false
            return
        }

        // 3. Install tap — does MINIMAL work to avoid audio glitches.
        //
        // CRITICAL: This callback runs on a real-time CoreAudio thread.
        // Any blocking operation (GCD dispatch, Task creation, slow locks,
        // memory allocation, I/O) can cause audio buffer underruns,
        // producing clicking/popping/"keek" sounds.
        //
        // We ONLY do:
        //   - Read an atomic pause flag
        //   - Read an atomic request reference
        //   - Append buffer to request (lock-free internally)
        //   - Fast strided RMS calculation
        //   - Write atomic RMS value
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: recordingFormat) { [weak self] buffer, _ in
            guard let self else { return }

            // Check if paused (e.g., during Claude generation)
            let paused = self._tapPaused.withLock { $0 }
            if !paused {
                // Feed audio to the current recognition request.
                // This reference is swapped atomically during recognition restarts
                // WITHOUT stopping/restarting the audio engine.
                let request = self._activeRequest.withLock { $0 }
                request?.append(buffer)
            }

            // Always compute level (even when paused) for the visual meter
            let level = self.computeRMS(buffer: buffer)
            self._latestRMS.withLock { $0 = level }

            if !self._receivedFirstBuffer.withLock({ $0 }) {
                self._receivedFirstBuffer.withLock { $0 = true }
            }
        }

        // 4. Start engine
        audioEngine = engine
        _receivedFirstBuffer.withLock { $0 = false }
        engine.prepare()

        do {
            try engine.start()
        } catch {
            errorMessage = "Failed to start audio engine: \(error.localizedDescription)"
            print("[SpeechEngine] ERROR starting engine: \(error)")
            shouldStayListening = false
            cleanup()
            return
        }

        isListening = true
        startElapsedTimer()
        startAudioLevelTimer()
        print("[SpeechEngine] Audio engine started")

        // 5. Start the first recognition session (engine stays running from here)
        startNewRecognitionSession()
    }

    /// Creates a new SFSpeechRecognition request + task.
    /// Called on initial start and every ~55s (Apple's recognition time limit).
    /// The audio engine and tap KEEP RUNNING — only the recognition session changes.
    private func startNewRecognitionSession() {
        guard shouldStayListening,
              let speechRecognizer,
              speechRecognizer.isAvailable else { return }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.addsPunctuation = true

        if speechRecognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }

        recognitionRequest = request

        // Atomically publish the new request so the audio tap starts feeding it
        _activeRequest.withLock { $0 = request }

        recognitionTask = speechRecognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor in
                self?.handleRecognitionResult(result, error: error)
            }
        }

        startRestartTimer()
        print("[SpeechEngine] Recognition session started")
    }

    // MARK: - Recognition Results

    private func handleRecognitionResult(_ result: SFSpeechRecognitionResult?, error: Error?) {
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
                let partial = result.bestTranscription.formattedString
                if !partial.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    partialTranscript = partial
                    resetPauseTimer()
                }
            }
        }

        if let error = error {
            let nsError = error as NSError
            let ignoredCodes: Set<Int> = [216, 209, 301, 1110, 203]
            if !ignoredCodes.contains(nsError.code) {
                print("[SpeechEngine] Recognition error [\(nsError.code)]: \(error.localizedDescription)")
                if nsError.code != 4 {
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    // MARK: - Timers & Restart

    private func resetPauseTimer() {
        pauseTimer?.invalidate()
        pauseTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                guard self.shouldStayListening, self.isListening,
                      !self.partialTranscript.isEmpty else { return }
                print("[SpeechEngine] Pause detected — cycling recognition")
                self.cycleRecognitionSession()
            }
        }
    }

    private func startRestartTimer() {
        restartTimer?.invalidate()
        restartTimer = Timer.scheduledTimer(withTimeInterval: 55.0, repeats: false) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                print("[SpeechEngine] 55s limit — cycling recognition")
                self.cycleRecognitionSession()
            }
        }
    }

    /// Cycle the recognition session WITHOUT stopping the audio engine.
    /// This is the key improvement: the engine + tap keep running continuously,
    /// so BlackHole/system audio is NEVER disrupted. Only the speech recognition
    /// request and task are replaced.
    private func cycleRecognitionSession() {
        guard shouldStayListening, isListening else { return }

        // 1. Finalize any pending partial text
        let pending = partialTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        if !pending.isEmpty {
            let time = timestampString()
            let entry = "[\(time)] \(pending)"
            transcript = transcript.isEmpty ? entry : "\(transcript)\n\(entry)"
            print("[SpeechEngine] Finalized: \(pending)")
        }
        partialTranscript = ""

        // 2. Detach the old request from the audio tap FIRST (atomic)
        _activeRequest.withLock { $0 = nil }

        // 3. End the old recognition session
        restartTimer?.invalidate()
        restartTimer = nil
        pauseTimer?.invalidate()
        pauseTimer = nil
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil

        // 4. Small delay, then start a new recognition session.
        // Audio engine keeps running the whole time!
        Task {
            try? await Task.sleep(for: .milliseconds(100))
            guard self.shouldStayListening else { return }
            self.startNewRecognitionSession()
        }
    }

    // MARK: - Stop & Cleanup

    private func stopListening() {
        print("[SpeechEngine] Stopping")
        shouldStayListening = false
        partialTranscript = ""

        // Detach request from tap first
        _activeRequest.withLock { $0 = nil }

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
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
        }
        audioEngine = nil
    }

    private func cleanup() {
        restartTimer?.invalidate()
        restartTimer = nil
        pauseTimer?.invalidate()
        pauseTimer = nil
        audioLevelTimer?.invalidate()
        audioLevelTimer = nil
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        _activeRequest.withLock { $0 = nil }
        stopAudioEngine()
    }

    // MARK: - Audio Level (polled from main thread)

    /// Polls the latest RMS level at 10Hz. Keeps the audio tap
    /// completely non-blocking — no GCD/Task dispatches on the audio thread.
    private func startAudioLevelTimer() {
        audioLevelTimer?.invalidate()
        audioLevelTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                if !self.isReceivingAudio {
                    let received = self._receivedFirstBuffer.withLock { $0 }
                    if received {
                        self.isReceivingAudio = true
                        print("[SpeechEngine] Audio buffers flowing")
                    }
                }

                let level = self._latestRMS.withLock { $0 }
                let alpha: Float = level > self.smoothedLevel ? 0.4 : 0.15
                self.smoothedLevel = alpha * level + (1 - alpha) * self.smoothedLevel
                self.audioLevel = self.smoothedLevel
            }
        }
    }

    /// Fast RMS computation with stride-4 sampling.
    /// Called on the real-time audio thread — must be fast.
    nonisolated private func computeRMS(buffer: AVAudioPCMBuffer) -> Float {
        guard let channelData = buffer.floatChannelData else { return 0 }
        let frames = Int(buffer.frameLength)
        guard frames > 0 else { return 0 }

        var sum: Float = 0
        let samples = channelData[0]
        var i = 0
        while i < frames {
            let sample = samples[i]
            sum += sample * sample
            i += 4
        }
        let samplesUsed = (frames + 3) / 4
        let rms = sqrtf(sum / Float(samplesUsed))
        return min(rms * 5.0, 1.0)
    }

    private func startElapsedTimer() {
        recordingStartDate = Date()
        elapsedTime = 0
        elapsedTimer?.invalidate()
        elapsedTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
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

    // MARK: - Microphone / Device Selection

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
