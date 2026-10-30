import Foundation
import Speech
import AVFoundation
import ShoeboxCore

/// Hold to talk, release to stop, 15 seconds at most. Recognized on the phone only; nothing is sent (SPEC 2.3).
@MainActor
@Observable
final class Dictation {
    var heard = ""
    var listening = false
    var unavailable = false
    var level: Double = 0

    private let engine = AVAudioEngine()
    private var task: SFSpeechRecognitionTask?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var stopper: Task<Void, Never>?

    func start() async {
        guard !listening else { return }
        let speech = await withCheckedContinuation { (c: CheckedContinuation<SFSpeechRecognizerAuthorizationStatus, Never>) in
            SFSpeechRecognizer.requestAuthorization { c.resume(returning: $0) }
        }
        let mic = await AVAudioApplication.requestRecordPermission()
        guard speech == .authorized, mic, let recognizer = SFSpeechRecognizer(), recognizer.supportsOnDeviceRecognition else {
            unavailable = true; return
        }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch { unavailable = true; return }

        let req = SFSpeechAudioBufferRecognitionRequest()
        req.requiresOnDeviceRecognition = true
        req.shouldReportPartialResults = true
        request = req
        heard = ""
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        nonisolated(unsafe) let sink = req
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            sink.append(buffer)
            let n = Int(buffer.frameLength)
            guard n > 0, let ch = buffer.floatChannelData?[0] else { return }
            var sum: Float = 0
            for i in 0..<n { sum += ch[i] * ch[i] }
            let rms = Double((sum / Float(n)).squareRoot())
            Task { @MainActor in self?.level = min(1, rms * 12) }
        }
        engine.prepare()
        do { try engine.start() } catch { unavailable = true; return }
        listening = true
        task = recognizer.recognitionTask(with: req) { [weak self] result, error in
            let text = result?.bestTranscription.formattedString
            let final = (result?.isFinal ?? false) || error != nil
            Task { @MainActor in
                guard let self else { return }
                if let text { self.heard = SpokenReason.clean(text) }
                if final { self.finish() }
            }
        }
        stopper = Task { [weak self] in
            try? await Task.sleep(for: .seconds(15))
            self?.stop()
        }
    }

    func stop() {
        guard listening else { return }
        request?.endAudio()
        finish()
    }

    private func finish() {
        stopper?.cancel(); stopper = nil
        if engine.isRunning { engine.stop(); engine.inputNode.removeTap(onBus: 0) }
        listening = false
        level = 0
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
