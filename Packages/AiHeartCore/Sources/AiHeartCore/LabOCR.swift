import CoreGraphics
import Foundation
import ImageIO
import Vision

/// Reads text from a lab report image on the device (Apple Vision). The image is not
/// kept and nothing is sent anywhere. Nothing read is logged.
public enum LabOCR {
    public static func lines(from data: Data) async -> [String] {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return [] }
        return await lines(from: image)
    }

    /// One string per table row (cells joined left to right), followed by a blank line and
    /// the raw observations in Vision's own order, so the parser can still use them if
    /// the grouping missed something.
    public static func lines(from image: CGImage) async -> [String] {
        await withCheckedContinuation { cont in
            let once = Once(cont)
            let request = VNRecognizeTextRequest { req, _ in
                let obs = (req.results as? [VNRecognizedTextObservation]) ?? []
                let items = obs.compactMap { o in o.topCandidates(1).first.map { ($0.string, o.boundingBox) } }
                once.resume(combined(items))
            }
            request.recognitionLevel = .accurate
            request.recognitionLanguages = ["ja-JP", "en-US"]
            request.usesLanguageCorrection = false // numbers matter more than words
            DispatchQueue.global(qos: .userInitiated).async {
                do { try VNImageRequestHandler(cgImage: image).perform([request]) } catch { once.resume([]) }
            }
        }
    }

    /// Grouped rows, then (if there are any) a blank separator and the raw lines.
    /// Pure: no Vision needed, so it can be tested.
    static func combined(_ items: [(String, CGRect)]) -> [String] {
        let rows = rows(from: items)
        let raw = items.map(\.0)
        return rows.isEmpty ? raw : rows + [""] + raw
    }

    /// Groups recognized text into table rows. Vision returns one observation per cell
    /// (or per column), so the label, value, unit and range of one analyte arrive apart.
    /// Boxes use Vision's normalized coordinates (origin bottom left, y up). Two boxes
    /// share a row when their vertical centres are within half a line height of each
    /// other. Rows run top to bottom, cells left to right, joined by two spaces.
    public static func rows(from items: [(String, CGRect)]) -> [String] {
        struct Row { var cells: [(String, CGRect)]; var midY: CGFloat; var height: CGFloat }
        let sorted = items
            .filter { !$0.0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .sorted { $0.1.midY > $1.1.midY }
        var rows: [Row] = []
        for item in sorted {
            let h = max(item.1.height, 0.0001)
            if var last = rows.last, abs(last.midY - item.1.midY) <= 0.5 * min(last.height, h) {
                last.cells.append(item)
                last.midY = last.cells.map(\.1.midY).reduce(0, +) / CGFloat(last.cells.count)
                last.height = min(last.height, h)
                rows[rows.count - 1] = last
            } else {
                rows.append(Row(cells: [item], midY: item.1.midY, height: h))
            }
        }
        return rows.map { row in
            row.cells.sorted { $0.1.minX < $1.1.minX }
                .map { $0.0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .joined(separator: "  ")
        }
    }

    /// Resumes a continuation once, whichever of Vision's completion handler or a thrown
    /// error gets there first.
    private final class Once: @unchecked Sendable {
        private let lock = NSLock()
        private var cont: CheckedContinuation<[String], Never>?
        init(_ c: CheckedContinuation<[String], Never>) { cont = c }
        func resume(_ value: [String]) {
            lock.lock()
            let c = cont
            cont = nil
            lock.unlock()
            c?.resume(returning: value)
        }
    }
}
