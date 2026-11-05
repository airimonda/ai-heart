import AVFoundation
import AiHeartCore
import SwiftData
import SwiftUI
import UIKit

/// What she has put down on Now so far, before saving.
@MainActor @Observable
final class CaptureDraft {
    var text = ""
    var photo: Data?
    var thumb: Data?
    var regions: [String] = []
    var sensations: [String] = []
    var word: String?
    var point: MoodPoint?
    var audio: Data?
    var audioSeconds: Double?

    var isEmpty: Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && photo == nil && regions.isEmpty
            && word == nil && point == nil && audio == nil
    }

    var kind: EntryKind {
        if photo != nil { return .photo }
        if audio != nil { return .voice }
        if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return .write }
        if word != nil || point != nil { return .feeling }
        return .body
    }

    func reset() {
        text = ""; photo = nil; thumb = nil; regions = []; sensations = []
        word = nil; point = nil; audio = nil; audioSeconds = nil
    }

    /// Inserts an entry. Status is kept; automatic keep or release arrives in M9.
    @discardableResult
    func save(in context: ModelContext) -> Entry {
        let e = Entry(kind: kind)
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        e.text = trimmed.isEmpty ? nil : trimmed
        e.photoData = photo
        e.thumbData = thumb
        e.bodyRegions = regions
        e.sensations = sensations
        e.word = word
        if let p = point ?? word.flatMap(MoodWords.point(for:)) {
            e.valence = p.valence
            e.arousal = p.arousal
        }
        e.audioData = audio
        e.audioSeconds = audioSeconds
        e.deviceId = UIDevice.current.identifierForVendor?.uuidString ?? ""
        context.insert(e)
        try? context.save()
        reset()
        // Today is written: today's reminder, if any, steps aside.
        Task { await WriteReminder.reschedule(context: context) }
        return e
    }
}

enum ImageTools {
    /// Re-encodes through UIImage, which drops EXIF and GPS metadata, and downsizes.
    static func prepare(_ data: Data) -> (photo: Data, thumb: Data)? {
        guard let image = UIImage(data: data) else { return nil }
        guard let photo = resized(image, maxSide: 2048).jpegData(compressionQuality: 0.85),
              let thumb = resized(image, maxSide: 480).jpegData(compressionQuality: 0.8) else { return nil }
        return (photo, thumb)
    }

    static func prepare(_ image: UIImage) -> (photo: Data, thumb: Data)? {
        guard let data = image.jpegData(compressionQuality: 0.95) else { return nil }
        return prepare(data)
    }

    static func resized(_ image: UIImage, maxSide: CGFloat) -> UIImage {
        let scale = min(1, maxSide / max(image.size.width, image.size.height))
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }
}

/// Camera capture. The photo goes into the app, never the Camera Roll.
struct CameraPicker: UIViewControllerRepresentable {
    let onImage: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    static var isAvailable: Bool { UIImagePickerController.isSourceTypeAvailable(.camera) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker
        init(_ parent: CameraPicker) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage { parent.onImage(image) }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { parent.dismiss() }
    }
}

/// Records a voice note into a protected temporary file, then hands back the bytes.
@MainActor @Observable
final class VoiceRecorder: NSObject, AVAudioRecorderDelegate {
    var isRecording = false
    var elapsed: TimeInterval = 0
    var denied = false
    private var recorder: AVAudioRecorder?
    private var timer: Timer?
    private let url = FileManager.default.temporaryDirectory.appendingPathComponent("aiheart-voice.m4a")

    func start() async {
        let granted = await AVAudioApplication.requestRecordPermission()
        guard granted else { denied = true; return }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
            try session.setActive(true)
            let settings: [String: Any] = [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: 44_100,
                AVNumberOfChannelsKey: 1,
                AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue,
            ]
            let r = try AVAudioRecorder(url: url, settings: settings)
            r.delegate = self
            r.record()
            // Writable while open even if the phone locks (owner, 2026-11-02).
            try? FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUnlessOpen], ofItemAtPath: url.path)
            recorder = r
            isRecording = true
            // The screen stays on while she talks.
            UIApplication.shared.isIdleTimerDisabled = true
            elapsed = 0
            timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.elapsed = self?.recorder?.currentTime ?? 0 }
            }
        } catch {
            isRecording = false
        }
    }

    /// Stops and returns the recording, deleting the temporary file.
    func stop() -> (Data, Double)? {
        guard let r = recorder else { return nil }
        let seconds = r.currentTime
        r.stop()
        UIApplication.shared.isIdleTimerDisabled = false
        timer?.invalidate()
        isRecording = false
        recorder = nil
        defer { try? FileManager.default.removeItem(at: url) }
        guard let data = try? Data(contentsOf: url) else { return nil }
        return (data, seconds)
    }

    func cancel() {
        recorder?.stop()
        UIApplication.shared.isIdleTimerDisabled = false
        timer?.invalidate()
        isRecording = false
        recorder = nil
        try? FileManager.default.removeItem(at: url)
    }
}

@MainActor @Observable
final class VoicePlayer: NSObject, AVAudioPlayerDelegate {
    var playing = false
    private var player: AVAudioPlayer?

    func toggle(_ data: Data) {
        if playing { player?.stop(); playing = false; return }
        try? AVAudioSession.sharedInstance().setCategory(.playback)
        player = try? AVAudioPlayer(data: data)
        player?.delegate = self
        playing = player?.play() ?? false
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in self.playing = false }
    }
}

func formatDuration(_ seconds: Double) -> String {
    let s = Int(seconds.rounded())
    return String(format: "%d:%02d", s / 60, s % 60)
}
