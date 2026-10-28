import SwiftUI

/// Converts the raw CI-V S-meter value (0...255) to a readable label.
/// Assumes the usual Icom scale: 120 = S9, 241 = S9+60 dB. Verify against the G90's own meter.
enum SMeter {
    static let s9 = 120.0
    static let max = 241.0

    static func label(_ raw: Int) -> String {
        let v = Double(raw)
        if v <= s9 { return "S\(Int((v * 9 / s9).rounded()))" }
        let over = Int(((v - s9) * 60 / (max - s9) / 5).rounded()) * 5
        return over == 0 ? "S9" : "S9+\(over)"
    }
}

struct SMeterView: View {
    let value: Int
    let peak: Int

    private let segments = 40
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text("S-METER").font(.caption2).foregroundStyle(.secondary)
                Spacer()
                Text(SMeter.label(value))
                    .font(.system(size: 22, weight: .semibold, design: .monospaced))
                    .foregroundStyle(value > Int(SMeter.s9) ? Color.red : Color.green)
            }
            Canvas { ctx, size in
                let gap: CGFloat = 2
                let w = (size.width - gap * CGFloat(segments - 1)) / CGFloat(segments)
                let lit = Int((min(Double(value), SMeter.max) / SMeter.max * Double(segments)).rounded())
                let peakSeg = Int((min(Double(peak), SMeter.max) / SMeter.max * Double(segments)).rounded())
                let s9Seg = Int((SMeter.s9 / SMeter.max * Double(segments)).rounded())
                for i in 0..<segments {
                    let rect = CGRect(x: CGFloat(i) * (w + gap), y: 0, width: w, height: size.height)
                    let base: Color = i < s9Seg ? .green : .red
                    let on = i < lit || i == peakSeg - 1
                    ctx.fill(Path(roundedRect: rect, cornerRadius: 2),
                             with: .color(on ? base : base.opacity(0.14)))
                }
            }
            .frame(height: 16)

            // Scale: S1…S9 then +20/+40/+60 dB, positioned on the same linear raw scale as the bar.
            GeometryReader { geo in
                ForEach(scale, id: \.0) { label, raw in
                    Text(label)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(raw > SMeter.s9 ? Color.red : Color.secondary)
                        .position(x: geo.size.width * CGFloat(raw / SMeter.max), y: 6)
                }
            }
            .frame(height: 12)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.35)))
    }

    private var scale: [(String, Double)] {
        var marks: [(String, Double)] = []
        for n in [1, 3, 5, 7, 9] {
            marks.append((String(n), Double(n) * SMeter.s9 / 9))
        }
        let span = SMeter.max - SMeter.s9
        for db in [20, 40, 60] {
            marks.append(("+\(db)", SMeter.s9 + Double(db) / 60 * span))
        }
        return marks
    }
}
