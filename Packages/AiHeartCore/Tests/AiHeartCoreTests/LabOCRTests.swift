#if os(macOS)
import AppKit
import Foundation
import Testing
@testable import AiHeartCore

// Renders a synthetic report as an image, then reads it back with Vision, the same path
// a screenshot takes on the phone. Table columns are drawn separately on purpose.

@Suite struct LabOCRTests {
    func render(_ rows: [[String]]) -> CGImage {
        let w = 1200, h = 90 * (rows.count + 1)
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(.white); ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        let font = NSFont(name: "Hiragino Sans", size: 34) ?? .systemFont(ofSize: 34)
        let cols: [CGFloat] = [40, 560, 760, 960]
        for (r, row) in rows.enumerated() {
            for (c, cell) in row.enumerated() {
                NSAttributedString(string: cell, attributes: [.font: font, .foregroundColor: NSColor.black])
                    .draw(at: CGPoint(x: cols[min(c, 3)], y: CGFloat(h - 90 * (r + 1))))
            }
        }
        NSGraphicsContext.current = nil
        return ctx.makeImage()!
    }

    @Test func readsEnglishTable() async {
        let img = render([
            ["Collected 16 Oct 2026"],
            ["TSH", "2.31", "mIU/L", "0.35-4.94"],
            ["Free T4", "15.8", "pmol/L", "9.0-19.0"],
        ])
        let r = LabParser.parse(lines: await LabOCR.lines(from: img))
        #expect(r["TSH"]?.value == 2.31)
        #expect(r["TSH"]?.low == 0.35)
        #expect(r["FT4"]?.value == 15.8)
        #expect(r.date != nil)
    }

    @Test func readsJapaneseTable() async {
        let img = render([
            ["採血日 2026年12月18日"],
            ["甲状腺刺激ホルモン", "1.25", "μIU/mL", "0.50-5.00"],
            ["遊離T4", "1.32", "ng/dL", "0.90-1.70"],
        ])
        let lines = await LabOCR.lines(from: img)
        let r = LabParser.parse(lines: lines)
        #expect(r["TSH"]?.value == 1.25, "\(lines)")
        #expect(r["TSH"]?.unit == "μIU/mL", "\(lines)")
        #expect(r["FT4"]?.value == 1.32, "\(lines)")
    }
}
#endif
