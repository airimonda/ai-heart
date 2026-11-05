import AiHeartCore
import AVFoundation
import Speech
import SwiftUI
import UIKit

/// Recording for Listen, on the phone only (docs/13). Never sends audio anywhere.
///
/// Owner, 2026-11-02: no live transcription. She talks for as long as she needs; the whole
/// recording is transcribed after she is done, which is more accurate, and she can read the text
/// or skip it. The recording is kept with the entry if she keeps it; otherwise it is deleted.
@MainActor @Observable
final class SpeechListener {
    enum State: Equatable { case idle, listening, paused, unavailable(String) }

    var state: State = .idle
    /// Last time her voice was above the quiet level. Drives the gentle nudges.
    var lastSpeech = Date()
    /// Microphone level, 0 to 1, for the level bars.
    var level: Float = 0
    var language: String = Locale.current.language.languageCode?.identifier == "ja" ? "ja-JP" : "en-US"
    /// True while the recording is being transcribed after "I am done".
    var transcribing = false
    /// Text from the full recording. nil until transcribed, or if it could not be.
    private(set) var finalText: String?
    /// True once a transcription ran and produced nothing.
    private(set) var transcriptionFailed = false

    private let engine = AVAudioEngine()
    private let sink = AudioSink()
    private var meter: Task<Void, Never>?
    /// One file per listening stretch (Pause and Go on start a new one).
    private var segments: [URL] = []
    private var segmentStart: Date?
    private var recordedBefore: Double = 0

    var transcript: String { finalText ?? "" }
    var hasRecording: Bool { !segments.isEmpty }
    /// Seconds recorded so far, including the stretch in progress.
    var elapsed: Double { recordedBefore + (segmentStart.map { Date().timeIntervalSince($0) } ?? 0) }

    func start() async {
        guard await AVAudioApplication.requestRecordPermission() else {
            state = .unavailable("The microphone is off for AiHeart in Settings. You can type instead.")
            return
        }
        // Asked now so the transcription after she is done does not stop to ask.
        _ = await withCheckedContinuation { c in SFSpeechRecognizer.requestAuthorization { c.resume(returning: $0) } }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .default, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)
            let input = engine.inputNode
            let format = input.outputFormat(forBus: 0)
            input.removeTap(onBus: 0)
            let sink = self.sink
            input.installTap(onBus: 0, bufferSize: 2048, format: format) { buf, _ in sink.take(buf) }
            engine.prepare()
            try engine.start()
            try openSegment(format: format)
            state = .listening
            lastSpeech = .now
            UIApplication.shared.isIdleTimerDisabled = true
            startMeter()
        } catch {
            state = .unavailable("The microphone could not start. You can type instead.")
        }
    }

    private func startMeter() {
        meter?.cancel()
        meter = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(100))
                guard let self else { return }
                let l = self.state == .listening ? self.sink.level : 0
                self.level = l
                if l > 0.08 { self.lastSpeech = .now }
            }
        }
    }

    private func openSegment(format: AVAudioFormat) throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("aiheart-listen-\(UUID().uuidString).m4a")
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: format.sampleRate,
            AVNumberOfChannelsKey: Int(format.channelCount),
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
        ]
        let file = try AVAudioFile(forWriting: url, settings: settings, commonFormat: format.commonFormat, interleaved: format.isInterleaved)
        // Writable while open even if the phone locks; unreadable to anything else while locked.
        try? FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUnlessOpen], ofItemAtPath: url.path)
        segments.append(url)
        segmentStart = .now
        sink.setFile(file)
    }

    private func closeSegment() {
        sink.setFile(nil)   // releasing the file finishes writing it
        if let s = segmentStart { recordedBefore += Date().timeIntervalSince(s) }
        segmentStart = nil
    }

    func pause() {
        guard state == .listening else { return }
        closeSegment()
        state = .paused
        level = 0
        UIApplication.shared.isIdleTimerDisabled = false
    }

    func resume() {
        guard state == .paused else { return }
        finalText = nil
        transcriptionFailed = false
        try? openSegment(format: engine.inputNode.outputFormat(forBus: 0))
        state = .listening
        lastSpeech = .now
        UIApplication.shared.isIdleTimerDisabled = true
    }

    /// Transcribes everything recorded, after she is done.
    func finish() async {
        if state == .listening { pause() }
        guard !segments.isEmpty else { return }
        transcribing = true
        defer { transcribing = false }
        var parts: [String] = []
        for url in segments {
            if let t = await FileTranscriber.transcribe(url, language: language), !t.isEmpty { parts.append(t) }
        }
        let text = parts.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        NSLog("AiHeartUI listen: transcribed \(segments.count) segments, \(Int(recordedBefore)) s, \(text.count) chars")
        finalText = text.isEmpty ? nil : text
        transcriptionFailed = text.isEmpty
    }

    /// The whole recording as one m4a, for the entry. nil if nothing was recorded.
    func recording() -> (Data, Double)? {
        if state == .listening { pause() }
        guard !segments.isEmpty else { return nil }
        if segments.count == 1 { return (try? Data(contentsOf: segments[0])).map { ($0, recordedBefore) } }
        let out = FileManager.default.temporaryDirectory.appendingPathComponent("aiheart-listen-joined-\(UUID().uuidString).m4a")
        defer { try? FileManager.default.removeItem(at: out) }
        do {
            var writer: AVAudioFile?
            for url in segments {
                let input = try AVAudioFile(forReading: url)
                if writer == nil {
                    writer = try AVAudioFile(forWriting: out, settings: input.fileFormat.settings,
                                             commonFormat: input.processingFormat.commonFormat, interleaved: input.processingFormat.isInterleaved)
                }
                let buf = AVAudioPCMBuffer(pcmFormat: input.processingFormat, frameCapacity: 32_768)!
                while input.framePosition < input.length {
                    try input.read(into: buf)
                    if buf.frameLength == 0 { break }
                    try writer?.write(from: buf)
                }
            }
            writer = nil
            return (try Data(contentsOf: out), recordedBefore)
        } catch {
            return (try? Data(contentsOf: segments[0])).map { ($0, recordedBefore) }
        }
    }

    func stop() {
        meter?.cancel()
        meter = nil
        closeSegment()
        level = 0
        UIApplication.shared.isIdleTimerDisabled = false
        if engine.isRunning { engine.stop() }
        engine.inputNode.removeTap(onBus: 0)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        if case .unavailable = state {} else { state = .idle }
    }

    /// Deletes the recording and any text.
    func discard() {
        stop()
        finalText = nil
        transcriptionFailed = false
        for url in segments { try? FileManager.default.removeItem(at: url) }
        segments = []
        recordedBefore = 0
    }
}

/// Receives microphone buffers on the audio thread: writes the file and measures the level.
final class AudioSink: @unchecked Sendable {
    private let lock = NSLock()
    private var _file: AVAudioFile?
    private var _level: Float = 0

    var level: Float { lock.withLock { _level } }
    func setFile(_ f: AVAudioFile?) { lock.withLock { _file = f } }

    func take(_ buf: AVAudioPCMBuffer) {
        var rms: Float = 0
        if let ch = buf.floatChannelData, buf.frameLength > 0 {
            let n = Int(buf.frameLength)
            var sum: Float = 0
            for i in 0..<n { sum += ch[0][i] * ch[0][i] }
            rms = (sum / Float(n)).squareRoot()
        }
        // Speech sits around 0.01 to 0.2 RMS; spread it over 0 to 1.
        let l = min(1, max(0, (20 * log10(max(rms, 1e-6)) + 50) / 40))
        lock.withLock {
            try? _file?.write(from: buf)
            _level = l
        }
    }
}

/// Transcribes a recorded file on the phone. Uses Apple's long-form on-device transcriber
/// (SpeechAnalyzer, iOS 26) when the language is supported, else the older on-device recognizer
/// with the accumulator so pauses do not drop words. The audio never leaves the phone; the
/// language model asset may be downloaded once from Apple.
enum FileTranscriber {
    static func transcribe(_ url: URL, language: String) async -> String? {
        if let t = await modern(url, language: language), !t.isEmpty { return t }
        return await legacy(url, language: language)
    }

    private static func modern(_ url: URL, language: String) async -> String? {
        guard SpeechTranscriber.isAvailable,
              let locale = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: language)) else { return nil }
        let transcriber = SpeechTranscriber(locale: locale, preset: .transcription)
        do {
            if let install = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
                try await install.downloadAndInstall()
            }
            let file = try AVAudioFile(forReading: url)
            let analyzer = SpeechAnalyzer(modules: [transcriber])
            async let collected: String = transcriber.results.reduce(into: "") { acc, r in
                guard r.isFinal else { return }
                let t = String(r.text.characters).trimmingCharacters(in: .whitespacesAndNewlines)
                if !t.isEmpty { acc += (acc.isEmpty ? "" : " ") + t }
            }
            if let end = try await analyzer.analyzeSequence(from: file) {
                try await analyzer.finalizeAndFinish(through: end)
            } else {
                await analyzer.cancelAndFinishNow()
            }
            return try await collected.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            NSLog("AiHeartUI transcribe: modern failed \(error.localizedDescription)")
            return nil
        }
    }

    private static func legacy(_ url: URL, language: String) async -> String? {
        guard let r = SFSpeechRecognizer(locale: Locale(identifier: language)), r.supportsOnDeviceRecognition else { return nil }
        let req = SFSpeechURLRecognitionRequest(url: url)
        req.requiresOnDeviceRecognition = true
        req.shouldReportPartialResults = true
        req.addsPunctuation = true
        return await withCheckedContinuation { (c: CheckedContinuation<String?, Never>) in
            let box = LegacyBox()
            box.task = r.recognitionTask(with: req) { result, error in
                if let result { box.acc.update(result.bestTranscription.formattedString) }
                if result?.isFinal == true || error != nil {
                    box.acc.finishRun()
                    box.resume(c)
                }
            }
        }
    }

    private final class LegacyBox: @unchecked Sendable {
        var acc = TranscriptAccumulator()
        var task: SFSpeechRecognitionTask?
        private var done = false
        func resume(_ c: CheckedContinuation<String?, Never>) {
            guard !done else { return }
            done = true
            c.resume(returning: acc.text.isEmpty ? nil : acc.text)
        }
    }
}
