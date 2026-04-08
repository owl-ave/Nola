import AVFoundation
import Observation
import Speech
import SwiftUI

@MainActor
@Observable
final class AudioRecorderManager {
    enum State: Equatable {
        case idle
        case recording
        case error(String)

        static func == (lhs: State, rhs: State) -> Bool {
            switch (lhs, rhs) {
            case (.idle, .idle), (.recording, .recording): return true
            case (.error(let a), .error(let b)): return a == b
            default: return false
            }
        }
    }

    var state: State = .idle
    var transcript: String = ""
    var audioLevels: [CGFloat] = []
    var elapsedSeconds: Int = 0

    private var audioEngine: AVAudioEngine?
    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var timerTask: Task<Void, Never>?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let maxLevels = 40

    var isRecording: Bool { state == .recording }

    var errorMessage: String? {
        if case .error(let msg) = state { return msg }
        return nil
    }

    func startRecording() {
        guard state == .idle || errorMessage != nil else { return }
        state = .idle

        speechRecognizer = SFSpeechRecognizer(locale: Locale.current)
        guard let speechRecognizer, speechRecognizer.isAvailable else {
            state = .error("Speech recognition is not available on this device.")
            return
        }

        Task {
            let audioGranted = await requestMicrophoneAccess()
            let speechGranted = await requestSpeechAccess()
            guard audioGranted else {
                state = .error("Microphone access is required. Enable it in Settings.")
                return
            }
            guard speechGranted else {
                state = .error("Speech recognition access is required. Enable it in Settings.")
                return
            }
            beginRecordingSession()
        }
    }

    func stopRecording() -> String {
        let result = transcript
        stopEngine()
        return result
    }

    func cancelRecording() {
        transcript = ""
        stopEngine()
    }

    func dismissError() {
        state = .idle
    }

    // MARK: - Private

    private func beginRecordingSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            state = .error("Failed to configure audio: \(error.localizedDescription)")
            return
        }

        let audioEngine = AVAudioEngine()
        self.audioEngine = audioEngine
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.addsPunctuation = true
        self.recognitionRequest = request

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            request.append(buffer)
            Task { @MainActor [weak self] in
                self?.processAudioLevel(buffer: buffer)
            }
        }

        recognitionTask = speechRecognizer?.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let result {
                    self.transcript = result.bestTranscription.formattedString
                }
                if error != nil || (result?.isFinal ?? false) {
                    self.stopEngine()
                }
            }
        }

        do {
            try audioEngine.start()
            state = .recording
            transcript = ""
            audioLevels = []
            elapsedSeconds = 0
            timerTask = Task {
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(1))
                    if !Task.isCancelled { elapsedSeconds += 1 }
                }
            }
        } catch {
            state = .error("Failed to start recording: \(error.localizedDescription)")
            stopEngine()
        }
    }

    private func stopEngine() {
        timerTask?.cancel()
        timerTask = nil
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        audioEngine = nil
        recognitionRequest = nil
        recognitionTask = nil
        if case .recording = state { state = .idle }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func processAudioLevel(buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData?[0] else { return }
        let frames = Int(buffer.frameLength)
        var sum: Float = 0
        for i in 0..<frames {
            sum += abs(channelData[i])
        }
        let avg = sum / Float(frames)
        let scaled = min(avg * 25, 1.0)
        let normalized = CGFloat(sqrt(scaled))

        audioLevels.append(normalized)
        if audioLevels.count > maxLevels {
            audioLevels.removeFirst(audioLevels.count - maxLevels)
        }
    }

    private func requestMicrophoneAccess() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    private func requestSpeechAccess() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }
}
